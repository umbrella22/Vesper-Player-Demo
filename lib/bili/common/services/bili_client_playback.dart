part of 'bili_client.dart';

extension BiliClientPlayback on BiliClient {
  Future<BiliResolvedPlayback> resolvePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required TargetPlatform platform,
  }) async {
    final pageBvid = page.bvid ?? detail.bvid;
    final referer = 'https://www.bilibili.com/video/$pageBvid';
    final dashFallbackReasons = <String>[];

    if (_supportsDashPlaybackPlatform(platform)) {
      for (final variant in biliDashRequestVariants) {
        try {
          final dashData = await _transport.getData(
            host: 'api.bilibili.com',
            path: '/x/player/wbi/playurl',
            params: _buildDashPlayUrlParams(
              detail: detail,
              page: page,
              variant: variant,
            ),
            useWbi: true,
            referer: referer,
          );

          final dashParseResult = _parseDashManifest(dashData);
          final dashManifest = dashParseResult.manifest;
          if (dashManifest != null) {
            final manifestText = _manifestBuilder.build(dashManifest);
            final file = await _writeDashManifest(
              bvid: pageBvid,
              cid: page.cid,
              manifestText: manifestText,
            );
            return BiliResolvedPlayback(
              bvid: pageBvid,
              cid: page.cid,
              title: detail.title,
              subtitle: 'P${page.pageNumber} · ${page.title}',
              uri: file.uri.toString(),
              protocol: VesperPlayerSourceProtocol.dash,
              headers: _transport.buildBiliMediaSourceHeaders(),
              transportLabel:
                  'Bilibili DASH via generated MPD (${variant.label}, '
                  '${dashManifest.videoStreams.length}V/'
                  '${dashManifest.audioStreams.length}A, source headers)',
              isLocalFile: true,
              videoTracks: _buildDashVideoTracks(dashManifest.videoStreams),
              debugPath: file.path,
            );
          }

          dashFallbackReasons.add(
            '${variant.label}: ${dashParseResult.reason}',
          );
        } on BiliApiException catch (error) {
          dashFallbackReasons.add('${variant.label}: ${error.toString()}');
        } on FormatException catch (error) {
          dashFallbackReasons.add('${variant.label}: ${error.message}');
        } on IOException catch (error) {
          dashFallbackReasons.add('${variant.label}: ${error.toString()}');
        } on TypeError catch (error) {
          dashFallbackReasons.add('${variant.label}: ${error.toString()}');
        }
      }
    } else {
      dashFallbackReasons.add(
        'platform ${platform.name} uses progressive path',
      );
    }

    final progressive = await _resolveProgressivePlayback(
      detail: detail,
      page: page,
      referer: referer,
      fallbackReason: dashFallbackReasons.join(' | '),
    );
    if (progressive != null) {
      return progressive;
    }

    throw const BiliApiException(
      'Bilibili playback resolve failed: no supported source was returned.',
    );
  }

  bool _supportsDashPlaybackPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  Map<String, Object?> _buildDashPlayUrlParams({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required BiliDashRequestVariant variant,
  }) {
    return <String, Object?>{
      'avid': page.aid ?? detail.aid,
      'bvid': page.bvid ?? detail.bvid,
      'cid': page.cid,
      'qn': biliMaxVideoQuality,
      'otype': 'json',
      'fnver': 0,
      'fnval': variant.fnval,
      'fourk': 1,
      'support_multi_audio': 'true',
      'session': _transport.buildSessionValue(),
      ...variant.extraParams,
    };
  }

  BiliDashParseResult _parseDashManifest(Map<String, Object?> data) {
    final dash = data['dash'] is Map
        ? Map<String, Object?>.from(data['dash'] as Map)
        : const <String, Object?>{};
    if (dash.isEmpty) {
      return BiliDashParseResult.failure(
        'no dash object; data keys=${formatKeys(data)}',
      );
    }

    final rawVideos = dash['video'] as List<dynamic>? ?? const <dynamic>[];
    final rawAudios = <dynamic>[
      ...(dash['audio'] as List<dynamic>? ?? const <dynamic>[]),
      ..._readDashAudioList(dash['flac']),
      ..._readDashAudioList(dash['dolby']),
    ];
    final qualityLabels = _parseSupportQualityLabels(
      data['support_formats'] as List<dynamic>? ?? const <dynamic>[],
    );

    final videos = <BiliDashStream>[];
    final videoRejectReasons = <String, int>{};
    for (final raw in rawVideos.whereType<Map>()) {
      final parsed = _parseDashStream(
        Map<String, Object?>.from(raw),
        qualityLabels: qualityLabels,
        index: videos.length,
        rejectReasons: videoRejectReasons,
      );
      if (parsed != null) {
        videos.add(parsed);
      }
    }

    final audios = <BiliDashStream>[];
    final audioRejectReasons = <String, int>{};
    for (final raw in rawAudios.whereType<Map>()) {
      final parsed = _parseDashStream(
        Map<String, Object?>.from(raw),
        qualityLabels: const <int, String>{},
        index: audios.length,
        rejectReasons: audioRejectReasons,
      );
      if (parsed != null) {
        audios.add(parsed);
      }
    }

    if (videos.isEmpty || audios.isEmpty) {
      return BiliDashParseResult.failure(
        'dash parsed ${videos.length}V/${audios.length}A from '
        '${rawVideos.length}V/${rawAudios.length}A; '
        'video rejects=${formatRejectReasons(videoRejectReasons)}, '
        'audio rejects=${formatRejectReasons(audioRejectReasons)}',
      );
    }

    return BiliDashParseResult.success(
      BiliDashManifestData(
        durationMs: ((readDouble(dash['duration']) ?? 0) * 1000).round(),
        minBufferTimeMs: ((readDouble(dash['min_buffer_time']) ?? 1.5) * 1000)
            .round(),
        videoStreams: videos,
        audioStreams: audios,
      ),
    );
  }

  List<dynamic> _readDashAudioList(Object? value) {
    final map = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    final audio = map['audio'];
    return switch (audio) {
      List raw => raw,
      Map raw => <dynamic>[raw],
      _ => const <dynamic>[],
    };
  }

  Map<int, String> _parseSupportQualityLabels(List<dynamic> values) {
    final labels = <int, String>{};
    for (final raw in values.whereType<Map>()) {
      final value = Map<String, Object?>.from(raw);
      final quality = readInt(value['quality']);
      if (quality == null) {
        continue;
      }
      final label =
          readString(value['new_description']) ??
          readString(value['display_desc']) ??
          readString(value['description']) ??
          readString(value['format']);
      if (label != null && label.isNotEmpty) {
        labels[quality] = label;
      }
    }
    return labels;
  }

  BiliDashStream? _parseDashStream(
    Map<String, Object?> value, {
    required Map<int, String> qualityLabels,
    required int index,
    required Map<String, int> rejectReasons,
  }) {
    final segmentMap = switch (value['SegmentBase']) {
      Map map => Map<String, Object?>.from(map),
      _ => switch (value['segment_base']) {
        Map map => Map<String, Object?>.from(map),
        _ => const <String, Object?>{},
      },
    };

    final urlCandidates = sortBiliMediaUrlCandidates(
      readDashMediaUrlCandidates(value),
    );
    final baseUrl = urlCandidates.isEmpty ? '' : urlCandidates.first;
    final mimeType =
        readString(value['mimeType']) ?? readString(value['mime_type']) ?? '';
    final codecs = readString(value['codecs']) ?? '';
    final id = readInt(value['id']) ?? 0;
    final bandwidth = readInt(value['bandwidth']) ?? 0;
    final codecid = readInt(value['codecid']);
    final initialization =
        readString(segmentMap['Initialization']) ??
        readString(segmentMap['initialization']) ??
        '';
    final indexRange =
        readString(segmentMap['indexRange']) ??
        readString(segmentMap['index_range']) ??
        '';

    if (baseUrl.isEmpty) {
      return rejectDashStream(rejectReasons, 'missing baseUrl');
    }
    if (mimeType.isEmpty) {
      return rejectDashStream(rejectReasons, 'missing mimeType');
    }
    if (codecs.isEmpty) {
      return rejectDashStream(rejectReasons, 'missing codecs');
    }
    if (initialization.isEmpty) {
      return rejectDashStream(rejectReasons, 'missing initialization');
    }
    if (indexRange.isEmpty) {
      return rejectDashStream(rejectReasons, 'missing indexRange');
    }

    return BiliDashStream(
      id: id,
      baseUrl: baseUrl,
      mimeType: mimeType,
      codecs: codecs,
      bandwidth: bandwidth,
      segmentInfo: BiliDashSegmentInfo(
        initialization: initialization,
        indexRange: indexRange,
      ),
      backupUrls: urlCandidates
          .where((url) => url != baseUrl)
          .toList(growable: false),
      width: readInt(value['width']),
      height: readInt(value['height']),
      frameRate:
          readString(value['frameRate']) ?? readString(value['frame_rate']),
      audioSamplingRate:
          readString(value['audioSamplingRate']) ??
          readString(value['audio_sampling_rate']),
      codecid: codecid,
      startWithSap:
          readInt(value['startWithSap']) ?? readInt(value['start_with_sap']),
      representationId: _buildDashRepresentationId(
        mimeType: mimeType,
        qualityId: id,
        bandwidth: bandwidth,
        codecid: codecid,
        codecs: codecs,
        index: index,
      ),
      qualityLabel: qualityLabels[id] ?? biliQualityLabelForId(id),
      sizeBytes: readInt(value['size']) ?? readInt(value['size_bytes']),
    );
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

  String _buildDashRepresentationId({
    required String mimeType,
    required int qualityId,
    required int bandwidth,
    required int? codecid,
    required String codecs,
    required int index,
  }) {
    final kind = mimeType.startsWith('audio/') ? 'audio' : 'video';
    final codecKey = codecid?.toString() ?? _codecIdPart(codecs);
    return '$kind-$qualityId-$codecKey-$bandwidth-$index';
  }

  String _codecIdPart(String codecs) {
    final buffer = StringBuffer();
    for (final codeUnit in codecs.codeUnits) {
      final isNumber = codeUnit >= 48 && codeUnit <= 57;
      final isUpper = codeUnit >= 65 && codeUnit <= 90;
      final isLower = codeUnit >= 97 && codeUnit <= 122;
      if (isNumber || isUpper || isLower) {
        buffer.writeCharCode(codeUnit);
      }
    }
    final value = buffer.toString();
    return value.isEmpty ? 'codec' : value;
  }

  Future<File> _writeDashManifest({
    required String bvid,
    required int cid,
    required String manifestText,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'bilibili-player-dash-',
    );
    final file = File('${directory.path}/$bvid-$cid.mpd');
    await file.writeAsString(manifestText);
    return file;
  }

  Future<BiliResolvedPlayback?> _resolveProgressivePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required String referer,
    required String fallbackReason,
  }) async {
    for (final quality in const <int>[64, 32, 16, 6]) {
      final data = await _transport.getData(
        host: 'api.bilibili.com',
        path: '/x/player/wbi/playurl',
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

      final durlList = data['durl'] as List<dynamic>? ?? const <dynamic>[];
      if (durlList.isEmpty) {
        continue;
      }

      final first = Map<String, Object?>.from(
        durlList.first as Map? ?? const <String, Object?>{},
      );
      final url = first['url'] as String? ?? '';
      if (url.isEmpty) {
        continue;
      }

      final actualQuality = readInt(data['quality']) ?? quality;
      final reason = fallbackReason.isEmpty
          ? 'DASH unavailable'
          : fallbackReason;
      return BiliResolvedPlayback(
        bvid: page.bvid ?? detail.bvid,
        cid: page.cid,
        title: detail.title,
        subtitle: 'P${page.pageNumber} · ${page.title}',
        uri: url,
        protocol: VesperPlayerSourceProtocol.progressive,
        headers: _transport.buildBiliMediaSourceHeaders(),
        transportLabel:
            'Bilibili progressive MP4 fallback (qn=$actualQuality; $reason)',
        isLocalFile: false,
      );
    }

    return null;
  }
}
