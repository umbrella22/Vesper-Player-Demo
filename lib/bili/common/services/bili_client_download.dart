part of 'bili_client.dart';

extension _BiliClientDownloadImplementation on BiliClient {
  Future<BiliDownloadOptions> resolveDownloadOptions({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
  }) async {
    final pageBvid = page.bvid ?? detail.bvid;
    final referer = biliVideoReferer(pageBvid);
    final fallbackReasons = <String>[];

    for (final variant in biliDashRequestVariants) {
      try {
        final dashData = await _transport.getData(
          host: biliApiHost,
          path: BiliApiPaths.playerWbiPlayUrl,
          params: _buildDashPlayUrlParams(
            detail: detail,
            page: page,
            variant: variant,
          ),
          useWbi: true,
          referer: referer,
        );
        final dashParseResult = _parseDashManifest(dashData);
        final manifest = dashParseResult.manifest;
        if (manifest == null) {
          fallbackReasons.add('${variant.label}: ${dashParseResult.reason}');
          continue;
        }
        return BiliDownloadOptions(
          bvid: pageBvid,
          cid: page.cid,
          videoTitle: detail.title,
          pageTitle: 'P${page.pageNumber} · ${page.title}',
          coverUrl: page.coverUrl ?? detail.coverUrl,
          referer: referer,
          headers: _transport.buildBiliMediaSourceHeaders(),
          manifest: manifest,
          qualities: _buildDownloadQualityOptions(manifest.videoStreams),
          variantLabel: variant.label,
        );
      } on BiliApiException catch (error) {
        fallbackReasons.add('${variant.label}: ${error.toString()}');
      } on FormatException catch (error) {
        fallbackReasons.add('${variant.label}: ${error.message}');
      } on IOException catch (error) {
        fallbackReasons.add('${variant.label}: ${error.toString()}');
      } on TypeError catch (error) {
        fallbackReasons.add('${variant.label}: ${error.toString()}');
      }
    }

    throw BiliApiException('没有可缓存的 DASH 视频流：${fallbackReasons.join(' | ')}');
  }

  BiliPreparedDownloadAsset prepareDownloadAsset({
    required BiliDownloadOptions options,
    required int qualityId,
    BiliVideoCodecPreference codecPreference =
        BiliVideoCodecPreference.automatic,
    String? targetDirectory,
  }) {
    final video = _selectDownloadVideoStream(
      options.manifest.videoStreams,
      qualityId: qualityId,
      codecPreference: codecPreference,
    );
    final audio = _selectDownloadAudioStream(options.manifest.audioStreams);
    final qualityLabel =
        video.qualityLabel ?? biliQualityLabelForId(video.id) ?? '${video.id}P';
    final codecKey = _downloadCodecKey(video);
    final audioKey = _downloadAudioKey(audio);
    final assetId = sanitizeAssetPart(
      'bili-${options.bvid}-${options.cid}-q${video.id}-$codecKey-$audioKey',
    );
    final videoPath =
        'media/video-q${video.id}-$codecKey.${_extensionFromDashStream(video)}';
    final audioPath =
        'media/audio-${audio.id}-$audioKey.${_extensionFromDashStream(audio)}';
    final localManifest = options.manifest.copyWith(
      videoStreams: <BiliDashStream>[
        video.copyWith(baseUrl: videoPath, backupUrls: const <String>[]),
      ],
      audioStreams: <BiliDashStream>[
        audio.copyWith(baseUrl: audioPath, backupUrls: const <String>[]),
      ],
    );
    final manifestText = _manifestBuilder.build(localManifest);
    final selectedTrackIds = <String>[
      ?video.representationId,
      ?audio.representationId,
    ];
    const manifestUri = 'vesper-generated://dash/manifest.mpd';
    final manifestPath = _downloadManifestPathForPlatform(targetDirectory);
    final source = VesperPlayerSource(
      uri: manifestUri,
      label: '${options.videoTitle} · ${options.pageTitle}',
      kind: VesperPlayerSourceKind.local,
      protocol: VesperPlayerSourceProtocol.dash,
      headers: options.headers,
    );
    final totalSizeBytes = switch ((video.sizeBytes, audio.sizeBytes)) {
      (final int videoBytes, final int audioBytes) => videoBytes + audioBytes,
      _ => null,
    };

    return BiliPreparedDownloadAsset(
      assetId: assetId,
      source: VesperDownloadSource.fromSource(
        source: source,
        contentFormat: VesperDownloadContentFormat.dashSegments,
        manifestUri: manifestUri,
      ),
      profile: VesperDownloadProfile(
        selectedTrackIds: selectedTrackIds,
        targetOutputFormat: VesperDownloadOutputFormat.mp4,
        targetDirectory: targetDirectory,
      ),
      assetIndex: VesperDownloadAssetIndex(
        contentFormat: VesperDownloadContentFormat.dashSegments,
        totalSizeBytes: totalSizeBytes,
        resources: <VesperDownloadResourceRecord>[
          VesperDownloadResourceRecord(
            resourceId: 'dash-manifest',
            uri: manifestUri,
            relativePath: manifestPath,
            generatedText: manifestText,
          ),
          VesperDownloadResourceRecord(
            resourceId: 'dash-video-${video.representationId ?? video.id}',
            uri: video.baseUrl,
            relativePath: videoPath,
            sizeBytes: video.sizeBytes,
          ),
          VesperDownloadResourceRecord(
            resourceId: 'dash-audio-${audio.representationId ?? audio.id}',
            uri: audio.baseUrl,
            relativePath: audioPath,
            sizeBytes: audio.sizeBytes,
          ),
        ],
      ),
      selectedVideo: video,
      selectedAudio: audio,
      qualityLabel: qualityLabel,
    );
  }

  Future<BiliPreparedDownloadAsset> prepareVerifiedDownloadAsset({
    required BiliDownloadOptions options,
    required int qualityId,
    BiliVideoCodecPreference codecPreference =
        BiliVideoCodecPreference.automatic,
    String? targetDirectory,
  }) async {
    final video = _selectDownloadVideoStream(
      options.manifest.videoStreams,
      qualityId: qualityId,
      codecPreference: codecPreference,
    );
    final audio = _selectDownloadAudioStream(options.manifest.audioStreams);
    debugPrint(
      '[BiliOffline] prepare bvid=${options.bvid} cid=${options.cid} '
      'quality=$qualityId video=${video.representationId ?? video.id} '
      'audio=${audio.representationId ?? audio.id}',
    );
    final verifiedVideo = await _resolveDownloadableDashStream(
      video,
      kind: 'video',
      headers: options.headers,
    );
    final verifiedAudio = await _resolveDownloadableDashStream(
      audio,
      kind: 'audio',
      headers: options.headers,
    );
    final verifiedOptions = options.copyWith(
      manifest: options.manifest.copyWith(
        videoStreams: options.manifest.videoStreams
            .map((stream) => identical(stream, video) ? verifiedVideo : stream)
            .toList(growable: false),
        audioStreams: options.manifest.audioStreams
            .map((stream) => identical(stream, audio) ? verifiedAudio : stream)
            .toList(growable: false),
      ),
    );
    final prepared = prepareDownloadAsset(
      options: verifiedOptions,
      qualityId: qualityId,
      codecPreference: codecPreference,
      targetDirectory: targetDirectory,
    );
    return prepared;
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
    final dash = readObjectMap(data['dash']);
    if (dash.isEmpty) {
      return BiliDashParseResult.failure(
        'no dash object; data keys=${formatKeys(data)}',
      );
    }

    final rawVideos = readObjectList(dash['video']);
    final rawAudios = <Object?>[
      ...readObjectList(dash['audio']),
      ..._readDashAudioList(dash['flac']),
      ..._readDashAudioList(dash['dolby']),
    ];

    final videos = <BiliDashStream>[];
    final videoRejectReasons = <String, int>{};
    for (final raw in rawVideos.whereType<Map<Object?, Object?>>()) {
      final parsed = _parseDashStream(
        readObjectMap(raw),
        qualityLabels: const <int, String>{},
        index: videos.length,
        rejectReasons: videoRejectReasons,
      );
      if (parsed != null) {
        videos.add(parsed);
      }
    }

    final audios = <BiliDashStream>[];
    final audioRejectReasons = <String, int>{};
    for (final raw in rawAudios.whereType<Map<Object?, Object?>>()) {
      final parsed = _parseDashStream(
        readObjectMap(raw),
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

  List<Object?> _readDashAudioList(Object? value) {
    final map = readObjectMap(value);
    final audio = map['audio'];
    return switch (audio) {
      List<Object?> raw => raw,
      Map<Object?, Object?> raw => <Object?>[raw],
      _ => const <Object?>[],
    };
  }

  BiliDashStream? _parseDashStream(
    Map<String, Object?> value, {
    required Map<int, String> qualityLabels,
    required int index,
    required Map<String, int> rejectReasons,
  }) {
    final segmentMap = switch (value['SegmentBase']) {
      Map<Object?, Object?> map => readObjectMap(map),
      _ => switch (value['segment_base']) {
        Map<Object?, Object?> map => readObjectMap(map),
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

  List<BiliDownloadQualityOption> _buildDownloadQualityOptions(
    List<BiliDashStream> streams,
  ) {
    final grouped = <int, List<BiliDashStream>>{};
    for (final stream in streams.where((stream) => stream.isVideo)) {
      grouped.putIfAbsent(stream.id, () => <BiliDashStream>[]).add(stream);
    }
    final options = grouped.entries
        .map((entry) {
          final label =
              entry.value.first.qualityLabel ??
              biliQualityLabelForId(entry.key) ??
              '${entry.key}P';
          final tracks = List<BiliDashStream>.of(entry.value)
            ..sort((left, right) => right.bandwidth.compareTo(left.bandwidth));
          return BiliDownloadQualityOption(
            qualityId: entry.key,
            label: label,
            videoStreams: tracks,
          );
        })
        .toList(growable: false);
    options.sort(
      (left, right) => biliQualityRank(
        right.qualityId,
      ).compareTo(biliQualityRank(left.qualityId)),
    );
    return options;
  }

  BiliDashStream _selectDownloadVideoStream(
    List<BiliDashStream> streams, {
    required int qualityId,
    required BiliVideoCodecPreference codecPreference,
  }) {
    final qualityMatches = streams
        .where((stream) => stream.isVideo && stream.id == qualityId)
        .toList(growable: false);
    if (qualityMatches.isEmpty) {
      throw BiliApiException(
        '当前视频没有 ${biliQualityLabelForId(qualityId) ?? qualityId} 可缓存资源。',
      );
    }

    final preferredMatches =
        codecPreference == BiliVideoCodecPreference.automatic
        ? const <BiliDashStream>[]
        : qualityMatches
              .where(
                (stream) =>
                    _streamMatchesCodecPreference(stream, codecPreference),
              )
              .toList(growable: false);
    final candidates = preferredMatches.isEmpty
        ? qualityMatches
        : preferredMatches;
    final sorted = List<BiliDashStream>.of(candidates)
      ..sort((left, right) => right.bandwidth.compareTo(left.bandwidth));
    return sorted.first;
  }

  BiliDashStream _selectDownloadAudioStream(List<BiliDashStream> streams) {
    final candidates = streams.where((stream) => stream.isAudio).toList();
    if (candidates.isEmpty) {
      throw const BiliApiException('当前视频没有可缓存音频流。');
    }
    candidates.sort((left, right) {
      final priorityCompare = _audioDownloadPriority(
        right,
      ).compareTo(_audioDownloadPriority(left));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return right.bandwidth.compareTo(left.bandwidth);
    });
    return candidates.first;
  }

  Future<BiliDashStream> _resolveDownloadableDashStream(
    BiliDashStream stream, {
    required String kind,
    required Map<String, String> headers,
  }) async {
    Object? lastError;
    final candidates = _dashStreamDownloadUrlCandidates(stream);
    debugPrint(
      '[BiliOffline] $kind candidates for ${stream.representationId ?? stream.id}: '
      '${candidates.length}',
    );
    for (var index = 0; index < candidates.length; index += 1) {
      final url = candidates[index];
      debugPrint('[BiliOffline] $kind url[$index]: $url');
      try {
        final sizeBytes = await _probeDashMediaSize(
          url,
          kind: kind,
          index: index,
          headers: headers,
        );
        debugPrint(
          '[BiliOffline] selected $kind url[$index] size=$sizeBytes: $url',
        );
        return stream.copyWith(baseUrl: url, sizeBytes: sizeBytes);
      } catch (error) {
        lastError = error;
        debugPrint('[BiliOffline] rejected $kind url[$index]: $error');
      }
    }
    throw BiliApiException(
      '缓存资源链接不可用，请重新打开页面后再试：${lastError ?? 'no usable media url'}',
    );
  }

  List<String> _dashStreamDownloadUrlCandidates(BiliDashStream stream) {
    final seen = <String>{};
    final rawCandidates = <String>[];
    void add(String? value) {
      if (value == null || value.isEmpty || !seen.add(value)) {
        return;
      }
      rawCandidates.add(value);
    }

    add(stream.baseUrl);
    for (final url in stream.backupUrls) {
      add(url);
    }
    return sortBiliMediaUrlCandidates(rawCandidates);
  }

  Future<int> _probeDashMediaSize(
    String url, {
    required String kind,
    required int index,
    required Map<String, String> headers,
  }) {
    return _probeDashMediaSizeOnce(
      url,
      kind: kind,
      index: index,
      headers: headers,
    ).timeout(
      _mediaProbeTimeout,
      onTimeout: () => throw BiliApiException(
        'media url probe timed out after '
        '${_mediaProbeTimeout.inSeconds}s.',
      ),
    );
  }

  Future<int> _probeDashMediaSizeOnce(
    String url, {
    required String kind,
    required int index,
    required Map<String, String> headers,
  }) async {
    debugPrint('[BiliOffline] probe $kind url[$index] Range GET: $url');
    final uri = Uri.parse(url);
    final request = await _transport.httpClient.getUrl(uri);
    headers.forEach((name, value) {
      if (name.isNotEmpty && value.isNotEmpty) {
        request.headers.set(name, value);
      }
    });
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    request.followRedirects = true;

    // Future.timeout 只放弃等待，不会取消底层 HttpClientRequest：超时后
    // 连接会一直挂到对端关闭。因此这里用 Timer 主动 abort 请求；若响应头
    // 已返回（例如 206 的 body drain 被挂起），同时销毁响应 socket 中断
    // body 读取。getUrl 阶段尚未持有 request，仍由外层 timeout 兜底。
    HttpClientResponse? response;
    var timedOut = false;
    final timeoutTimer = Timer(_mediaProbeTimeout, () {
      timedOut = true;
      request.abort();
      final current = response;
      if (current != null) {
        unawaited(_abortProbeResponseBody(current));
      }
    });
    try {
      try {
        response = await request.close();
      } catch (error) {
        if (timedOut) {
          throw BiliApiException(
            'media url probe timed out after '
            '${_mediaProbeTimeout.inSeconds}s.',
          );
        }
        rethrow;
      }
      final statusCode = response.statusCode;
      final contentRange = response.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      debugPrint(
        '[BiliOffline] probe result $kind url[$index] '
        'HTTP $statusCode, contentLength=${response.contentLength}, '
        'contentRange=${contentRange ?? ''}',
      );

      // 先读响应头，再决定是否消费 body：若 CDN 忽略 Range 以 200 返回完整
      // 文件，drain 会白白下载整个视频（参考 ATV-Bilibili-demo CDNDiagnostics
      // 的有界探测模式：短超时 + 先取头后取体，且只读取需要的字节数）。
      if (statusCode == HttpStatus.partialContent) {
        final totalText = contentRange?.split('/').last.trim();
        final totalBytes = totalText == null ? null : int.tryParse(totalText);
        if (totalBytes != null && totalBytes > 0) {
          // 206 的 body 即请求的 1 字节，drain 以释放连接复用。
          await response.drain<void>();
          return totalBytes;
        }
      }
      if (statusCode == HttpStatus.ok) {
        final contentLength = response.contentLength;
        if (contentLength > 0) {
          // Range 被忽略（200 + 完整 body）：不 drain，直接中断连接。
          await _abortProbeResponseBody(response);
          return contentLength;
        }
      }
      await _abortProbeResponseBody(response);
      if (isStaleMediaStatus(statusCode)) {
        throw BiliApiException(
          'media url is stale or rejected (HTTP $statusCode)',
        );
      }
      throw BiliApiException('media url probe failed (HTTP $statusCode)');
    } catch (error) {
      // abort 打断 body 读取时会抛底层 Socket/Http 异常，统一转为超时错误。
      if (timedOut) {
        throw BiliApiException(
          'media url probe timed out after '
          '${_mediaProbeTimeout.inSeconds}s.',
        );
      }
      rethrow;
    } finally {
      timeoutTimer.cancel();
    }
  }

  String _downloadManifestPathForPlatform(String? targetDirectory) {
    if (defaultTargetPlatform != TargetPlatform.iOS ||
        targetDirectory == null ||
        targetDirectory.isEmpty) {
      return 'manifest.mpd';
    }
    final trimmedTargetDirectory = targetDirectory.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    if (trimmedTargetDirectory.isEmpty) {
      return 'manifest.mpd';
    }
    return '$trimmedTargetDirectory/manifest.mpd';
  }

  bool _streamMatchesCodecPreference(
    BiliDashStream stream,
    BiliVideoCodecPreference preference,
  ) {
    final codec = stream.codecs.toLowerCase();
    return switch (preference) {
      BiliVideoCodecPreference.automatic => true,
      BiliVideoCodecPreference.av1 =>
        codec.contains('av01') || stream.codecid == 13,
      BiliVideoCodecPreference.hevc =>
        codec.contains('hev1') ||
            codec.contains('hvc1') ||
            codec.contains('dvh1') ||
            codec.contains('dvhe') ||
            stream.codecid == 12,
      BiliVideoCodecPreference.avc =>
        codec.contains('avc1') || stream.codecid == 7,
    };
  }

  int _audioDownloadPriority(BiliDashStream stream) {
    final codec = stream.codecs.toLowerCase();
    if (stream.id == 30251 || codec.contains('flac')) {
      return 3000000000 + stream.bandwidth;
    }
    if (stream.id == 30250 ||
        stream.id == 30255 ||
        codec.contains('ec-3') ||
        codec.contains('ac-3') ||
        codec.contains('eac3')) {
      return 2000000000 + stream.bandwidth;
    }
    return stream.bandwidth;
  }

  String _downloadCodecKey(BiliDashStream stream) {
    if (_streamMatchesCodecPreference(stream, BiliVideoCodecPreference.av1)) {
      return 'av1';
    }
    if (_streamMatchesCodecPreference(stream, BiliVideoCodecPreference.hevc)) {
      return 'hevc';
    }
    if (_streamMatchesCodecPreference(stream, BiliVideoCodecPreference.avc)) {
      return 'avc';
    }
    return 'codec${stream.codecid ?? _codecIdPart(stream.codecs)}';
  }

  String _downloadAudioKey(BiliDashStream stream) {
    final codec = stream.codecs.toLowerCase();
    if (stream.id == 30251 || codec.contains('flac')) {
      return 'flac';
    }
    if (stream.id == 30250 ||
        stream.id == 30255 ||
        codec.contains('ec-3') ||
        codec.contains('ac-3') ||
        codec.contains('eac3')) {
      return 'dolby';
    }
    return 'audio${stream.id}';
  }

  String _extensionFromDashStream(BiliDashStream stream) {
    final uriPath = Uri.tryParse(stream.baseUrl)?.path;
    final uriName = uriPath == null || uriPath.isEmpty
        ? ''
        : uriPath.split('/').last;
    final uriExtension = uriName.contains('.') ? uriName.split('.').last : '';
    if (uriExtension.isNotEmpty && uriExtension.length <= 5) {
      return uriExtension;
    }
    if (stream.mimeType.contains('mp4')) {
      return 'm4s';
    }
    return stream.isAudio ? 'audio' : 'video';
  }
}

/// 单次媒体 URL 探测的总体超时。参考 ATV-Bilibili-demo CDNDiagnostics 的
/// 起播 quickSession（3s/4s 短超时）；此处取 10s 兼顾弱网与备用源重试。
const _mediaProbeTimeout = Duration(seconds: 10);

/// 中止一次媒体探测的响应体读取：服务器忽略 Range 以 200 返回完整文件时，
/// 直接拆下底层 socket 并销毁，避免把整个视频 body 下载下来。
Future<void> _abortProbeResponseBody(HttpClientResponse response) async {
  try {
    final socket = await response.detachSocket();
    socket.destroy();
  } catch (_) {
    // 连接已关闭或不可拆离，无需处理。
  }
}
