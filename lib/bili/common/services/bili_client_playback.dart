part of 'bili_client.dart';

extension _BiliClientPlaybackImplementation on BiliClient {
  Future<BiliResolvedPlayback> resolvePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required TargetPlatform platform,
  }) async {
    final pageBvid = page.bvid ?? detail.bvid;
    final referer = biliVideoReferer(pageBvid);
    final revision = sessionRevision;
    final dashFallbackReasons = <String>[];
    // Deadline starts alongside playurl, not after it. Late results are not
    // attached to a playing source; the underlying subtitle future is observed.
    final subtitles =
        _resolveOptionalSubtitles(
          bvid: pageBvid,
          cid: page.cid,
          aid: page.aid ?? detail.aid,
        ).timeout(
          const Duration(milliseconds: 600),
          onTimeout: () =>
              (tracks: const <BiliSubtitleTrack>[], error: '字幕加载超时，本次播放已跳过。'),
        );
    final policyFuture = platform == TargetPlatform.android
        ? audioPolicy.resolve()
        : Future.value(const BiliAudioPolicy());
    void checkSession() {
      if (revision != sessionRevision) {
        throw const BiliApiException('登录状态已变更，请重试。');
      }
    }

    Future<BiliResolvedPlayback?> buildDash(
      Map<String, Object?> data,
      BiliDashRequestVariant variant, {
      bool prefetched = false,
    }) async {
      checkSession();
      final parsed = const BiliDashManifestParser().parse(data);
      final original = parsed.manifest;
      if (original == null) {
        dashFallbackReasons.add('${variant.label}: ${parsed.reason}');
        return null;
      }
      final policy = await policyFuture;
      final manifest = policy.filter(original);
      final file = await _writeDashManifest(
        bvid: pageBvid,
        cid: page.cid,
        manifestText: _manifestBuilder.build(manifest),
      );
      final headers = _transport.buildBiliMediaSourceHeaders();
      final audioOnly = await _buildListenPlaybackVariant(
        bvid: pageBvid,
        cid: page.cid,
        manifest: manifest,
        headers: headers,
      );
      final subtitleResult = await subtitles;
      checkSession();
      final policyLabel = policy.diagnosticLabel(original, manifest);
      return BiliResolvedPlayback(
        bvid: pageBvid,
        cid: page.cid,
        title: detail.title,
        subtitle: 'P${page.pageNumber} · ${page.title}',
        uri: file.uri.toString(),
        protocol: VesperPlayerSourceProtocol.dash,
        headers: headers,
        isLocalFile: true,
        canRefreshSource: true,
        transportLabel:
            'Bilibili DASH via generated MPD (${variant.label}, '
            '${manifest.videoStreams.length}V/${manifest.audioStreams.length}A, source headers)'
            '${prefetched ? "; playurl=prefetch" : ""}${policyLabel.isEmpty ? "" : "; $policyLabel"}',
        videoTracks: _buildDashVideoTracks(manifest.videoStreams),
        audioTracks: manifest.audioStreams
            .map(
              (stream) => VesperMediaTrack(
                id: stream.representationId ?? 'audio-${stream.id}',
                kind: VesperMediaTrackKind.audio,
                codec: stream.codecs,
                bitRate: stream.bandwidth,
              ),
            )
            .toList(growable: false),
        subtitleTracks: subtitleResult.tracks,
        subtitleError: subtitleResult.error,
        debugPath: file.path,
        audioOnlySource: audioOnly,
        dolbyAudioBlocked:
            !policy.allowDolby &&
            !manifest.audioStreams.any(BiliAudioPolicy.isDolbyStream),
      );
    }

    if (_supportsDashPlaybackPlatform(platform)) {
      final cached = playbackPrefetcher.take((bvid: pageBvid, cid: page.cid));
      if (cached?.dashData != null && cached?.variant != null) {
        try {
          final resolved = await buildDash(
            cached!.dashData!,
            cached.variant!,
            prefetched: true,
          );
          if (resolved != null) return resolved;
        } catch (_) {
          checkSession();
          // A consumed cache entry never replaces the normal network retry chain.
        }
      }
      for (final variant in biliDashRequestVariants) {
        checkSession();
        try {
          final data = await _requestDashData(
            aid: page.aid ?? detail.aid,
            bvid: pageBvid,
            cid: page.cid,
            variant: variant,
          );
          final resolved = await buildDash(data, variant);
          if (resolved != null) return resolved;
        } on BiliApiException catch (error) {
          dashFallbackReasons.add('${variant.label}: $error');
        } on FormatException catch (error) {
          dashFallbackReasons.add('${variant.label}: ${error.message}');
        } on IOException catch (error) {
          dashFallbackReasons.add('${variant.label}: $error');
        } on TypeError catch (error) {
          dashFallbackReasons.add('${variant.label}: $error');
        }
      }
    } else {
      dashFallbackReasons.add(
        'platform ${platform.name} uses progressive path',
      );
    }
    checkSession();
    final progressive = await _resolveProgressivePlayback(
      detail: detail,
      page: page,
      referer: referer,
      fallbackReason: dashFallbackReasons.join(' | '),
      subtitles: subtitles,
    );
    checkSession();
    if (progressive != null) return progressive;
    throw const BiliApiException(
      'Bilibili playback resolve failed: no supported source was returned.',
    );
  }

  bool _supportsDashPlaybackPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  Future<({List<BiliSubtitleTrack> tracks, String? error})>
  _resolveOptionalSubtitles({
    required String bvid,
    required int cid,
    required int aid,
  }) async {
    try {
      final tracks = await fetchVideoSubtitles(bvid: bvid, cid: cid, aid: aid);
      return (tracks: tracks, error: null);
    } catch (error) {
      // Subtitle discovery/materialization is optional and must not make an
      // otherwise playable video source fail to resolve.
      return (
        tracks: const <BiliSubtitleTrack>[],
        error: '字幕加载失败：${biliErrorMessage(error)}',
      );
    }
  }

  List<VesperMediaTrack> _buildDashVideoTracks(List<BiliDashStream> streams) {
    return streams
        .where((stream) => stream.isVideo)
        .map(
          (stream) => VesperMediaTrack(
            id: stream.representationId ?? 'video-${stream.id}',
            kind: VesperMediaTrackKind.video,
            label: stream.qualityLabel,
            codec: stream.codecs,
            bitRate: stream.bandwidth > 0 ? stream.bandwidth : null,
            width: stream.width,
            height: stream.height,
            frameRate: parseDashFrameRate(stream.frameRate),
          ),
        )
        .toList(growable: false);
  }

  Future<BiliResolvedPlaybackVariant?> _buildListenPlaybackVariant({
    required String bvid,
    required int cid,
    required BiliDashManifestData manifest,
    required Map<String, String> headers,
  }) async {
    final audio = const BiliListenAudioSelector().select(manifest.audioStreams);
    if (audio == null) {
      return null;
    }
    try {
      final audioManifest = manifest.copyWith(
        videoStreams: const <BiliDashStream>[],
        audioStreams: <BiliDashStream>[audio],
      );
      final file = await _writeDashManifest(
        bvid: bvid,
        cid: cid,
        manifestText: _manifestBuilder.build(audioManifest),
        fileNameSuffix: '-audio',
      );
      return BiliResolvedPlaybackVariant(
        uri: file.uri.toString(),
        protocol: VesperPlayerSourceProtocol.dash,
        transportLabel:
            'Bilibili audio-only DASH (AAC ${audio.id}, '
            '${audio.bandwidth}bps)',
        isLocalFile: true,
        headers: headers,
        debugPath: file.path,
      );
    } on IOException {
      // 伴听源是可选能力；本地派生文件失败不能破坏正常视频播放。
      return null;
    }
  }

  Future<File> _writeDashManifest({
    required String bvid,
    required int cid,
    required String manifestText,
    String fileNameSuffix = '',
  }) async {
    final directory = Directory('${Directory.systemTemp.path}/vesper/dash');
    final file = File(
      '${directory.path}/${sanitizeAssetPart(bvid)}-$cid$fileNameSuffix-'
      '${DateTime.now().microsecondsSinceEpoch}-${_manifestSequence++}.mpd',
    );
    await writeStringAtomically(file, manifestText);
    // Best-effort: keep the dash temp directory from growing unbounded across
    // sessions. Cleanup must never break playback resolution.
    unawaited(
      deleteStaleGeneratedFilesBestEffort(
        directory,
        fileExtension: '.mpd',
        maxAge: const Duration(days: 1),
      ),
    );
    return file;
  }

  Future<BiliResolvedPlayback?> _resolveProgressivePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required String referer,
    required String fallbackReason,
    required Future<({List<BiliSubtitleTrack> tracks, String? error})>
    subtitles,
  }) async {
    for (final quality in const <int>[64, 32, 16, 6]) {
      final data = await _transport.getData(
        host: biliApiHost,
        path: BiliApiPaths.playerWbiPlayUrl,
        params: <String, Object?>{
          'avid': page.aid ?? detail.aid,
          'bvid': page.bvid ?? detail.bvid,
          'cid': page.cid,
          'qn': quality,
          'fnver': 0,
          'fnval': 1,
          'fourk': 0,
          'platform': 'html5',
          'high_quality': 1,
          'gaia_source': 'view-card',
          'session': _transport.buildSessionValue(),
        },
        useWbi: true,
        referer: referer,
      );

      final durlList = readObjectList(data['durl']);
      if (durlList.isEmpty) {
        continue;
      }

      final first = readObjectMap(durlList.first);
      final url = readString(first['url']) ?? '';
      if (url.isEmpty) {
        continue;
      }

      final actualQuality = readInt(data['quality']) ?? quality;
      final reason = fallbackReason.isEmpty
          ? 'DASH unavailable'
          : fallbackReason;
      final pageBvid = page.bvid ?? detail.bvid;
      final subtitleResult = await subtitles;
      return BiliResolvedPlayback(
        bvid: pageBvid,
        cid: page.cid,
        title: detail.title,
        subtitle: 'P${page.pageNumber} · ${page.title}',
        uri: url,
        protocol: VesperPlayerSourceProtocol.progressive,
        headers: _transport.buildBiliMediaSourceHeaders(),
        transportLabel:
            'Bilibili progressive MP4 fallback (qn=$actualQuality; $reason)',
        isLocalFile: false,
        subtitleTracks: subtitleResult.tracks,
        subtitleError: subtitleResult.error,
      );
    }

    return null;
  }
}
