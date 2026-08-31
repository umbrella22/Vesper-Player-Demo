import '../models/bili_models.dart';
import 'bili_api_core.dart';

/// Parses the DASH response shape shared by playback and offline downloads.
final class BiliDashManifestParser {
  const BiliDashManifestParser();

  BiliDashParseResult parse(
    Map<String, Object?> data, {
    bool useResponseQualityLabels = true,
  }) {
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
    final qualityLabels = useResponseQualityLabels
        ? _parseSupportQualityLabels(readObjectList(data['support_formats']))
        : const <int, String>{};

    final videos = <BiliDashStream>[];
    final videoRejectReasons = <String, int>{};
    for (final raw in rawVideos.whereType<Map<Object?, Object?>>()) {
      final parsed = _parseDashStream(
        readObjectMap(raw),
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

  Map<int, String> _parseSupportQualityLabels(List<Object?> values) {
    final labels = <int, String>{};
    for (final raw in values.whereType<Map<Object?, Object?>>()) {
      final value = readObjectMap(raw);
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
      representationId: _buildRepresentationId(
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

  String _buildRepresentationId({
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
}
