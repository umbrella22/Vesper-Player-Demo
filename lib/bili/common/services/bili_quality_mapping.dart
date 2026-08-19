import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';

import '../models/bili_models.dart';

/// Bilibili 清晰度/编码映射：轨道 ↔ 质量 ID ↔ 通用质量选项。
///
/// 抽取计划 §4.5：壳不猜清晰度。质量分组与反向解析全部收在平台侧，
/// 壳只消费 [MediaQualityOption] / [MediaQualityPolicy]。
final class BiliQualityMapping {
  const BiliQualityMapping._();

  /// 从轨道解析 Bilibili 质量 ID（id → label → 形状 三路回退）。
  static int? qualityIdForTrack(VesperMediaTrack track) {
    return _qualityIdFromTrackId(track.id) ??
        _qualityIdFromTrackLabel(track.label) ??
        _qualityIdFromTrackShape(track);
  }

  /// 轨道 → codec 子选项文案（AV1/HEVC/AVC/Dolby Vision）。
  static String? codecLabelForTrack(VesperMediaTrack track) {
    final codec = track.codec?.toLowerCase() ?? '';
    if (codec.contains('dvh1') || codec.contains('dvhe')) {
      return 'Dolby Vision';
    }
    if (codec.contains('av01')) {
      return 'AV1';
    }
    if (codec.contains('hev1') || codec.contains('hvc1')) {
      return 'HEVC';
    }
    if (codec.contains('avc1')) {
      return 'AVC';
    }
    final codecId = _codecIdFromTrackId(track.id);
    return switch (codecId) {
      13 => 'AV1',
      12 => 'HEVC',
      7 => 'AVC',
      _ => null,
    };
  }

  /// 轨道展示文案（质量 + codec + 帧率 + 码率）。
  static String videoTrackLabel(VesperMediaTrack track) {
    final parts = <String>[];
    final qualityId = qualityIdForTrack(track);
    final qualityLabel = qualityId == null
        ? null
        : biliQualityLabelForId(qualityId);
    if (qualityLabel != null) {
      parts.add(qualityLabel);
    } else if (track.label != null && track.label!.trim().isNotEmpty) {
      parts.add(track.label!.trim());
    } else if (track.width != null && track.height != null) {
      parts.add('${track.width}x${track.height}');
    } else if (track.height != null) {
      parts.add('${track.height}p');
    }
    final codecLabel = codecLabelForTrack(track);
    if (codecLabel != null) {
      parts.add(codecLabel);
    }
    if (track.frameRate != null && track.frameRate! >= 50) {
      parts.add('${track.frameRate!.round()}fps');
    }
    if (track.bitRate != null) {
      parts.add('${(track.bitRate! / 1000).round()} kbps');
    }
    return parts.isEmpty ? track.id : parts.join(' · ');
  }

  /// 按质量 ID 分组轨道为 [MediaQualityOption] 列表（质量降序）。
  static List<MediaQualityOption> buildQualityOptions(
    List<VesperMediaTrack> tracks,
  ) {
    final groups = <int, List<VesperMediaTrack>>{};
    for (final track in tracks) {
      final qualityId = qualityIdForTrack(track);
      if (qualityId == null) {
        continue;
      }
      groups.putIfAbsent(qualityId, () => <VesperMediaTrack>[]).add(track);
    }
    final qualityIds = groups.keys.toList()
      ..sort((left, right) => biliQualityRank(right).compareTo(
            biliQualityRank(left),
          ));
    return qualityIds
        .map(
          (qualityId) => MediaQualityOption(
            id: qualityId.toString(),
            label: biliQualityLabelForId(qualityId) ?? '$qualityId',
            tracks: groups[qualityId]!,
          ),
        )
        .toList(growable: false);
  }

  /// 轨道 → codec 策略身份：Dolby Vision 归入 HEVC 组（旧版 BiliCodecStrategy
  /// 语义），与展示 label（[codecLabelForTrack] 保留独立 "Dolby Vision"）分开。
  static String? codecIdentityForTrack(VesperMediaTrack track) {
    final label = codecLabelForTrack(track);
    return switch (label) {
      'Dolby Vision' => 'HEVC',
      _ => label,
    };
  }

  static MediaQualityPolicy buildQualityPolicy() {
    return MediaQualityPolicy(
      supportsCodecSelection: true,
      qualityOptionIdForNativeTrack: qualityOptionIdForNativeTrack,
      codecLabelFor: codecLabelForTrack,
      codecIdentityFor: codecIdentityForTrack,
      // B 站策略身份即规范标签（AV1/HEVC/AVC）。
      codecIdentityLabelFor: (identity) => identity,
    );
  }

  /// 将 SDK 原生轨道映射回解析阶段的 Bilibili 清晰度选项。
  ///
  /// 原生轨道 ID 由 SDK 定义且不透明。优先使用平台 label；否则在声明轨道
  /// 中按 codec、画面尺寸、帧率与接近码率寻找同一表示，最后才按画面形状
  /// 回退到常规清晰度。
  static String? qualityOptionIdForNativeTrack(
    VesperMediaTrack nativeTrack,
    List<MediaQualityOption> declaredOptions,
  ) {
    final declaredIds = declaredOptions.map((option) => option.id).toSet();
    final labelQualityId = _qualityIdFromTrackLabel(nativeTrack.label);
    if (labelQualityId != null &&
        declaredIds.contains(labelQualityId.toString())) {
      return labelQualityId.toString();
    }

    ({String optionId, int evidence, double bitRateDelta})? best;
    var bestIsAmbiguous = false;
    for (final option in declaredOptions) {
      for (final declaredTrack in option.tracks) {
        final score = _nativeTrackMatchScore(nativeTrack, declaredTrack);
        if (score == null) {
          continue;
        }
        final candidate = (
          optionId: option.id,
          evidence: score.evidence,
          bitRateDelta: score.bitRateDelta,
        );
        final current = best;
        if (current == null || _isBetterNativeMatch(candidate, current)) {
          best = candidate;
          bestIsAmbiguous = false;
          continue;
        }
        if (candidate.optionId != current.optionId &&
            candidate.evidence == current.evidence &&
            (candidate.bitRateDelta - current.bitRateDelta).abs() < 0.000001) {
          bestIsAmbiguous = true;
        }
      }
    }
    if (best != null && !bestIsAmbiguous) {
      return best.optionId;
    }

    final shapeQualityId = _qualityIdFromTrackShape(nativeTrack);
    if (shapeQualityId != null &&
        declaredIds.contains(shapeQualityId.toString())) {
      return shapeQualityId.toString();
    }
    return null;
  }

  static ({int evidence, double bitRateDelta})? _nativeTrackMatchScore(
    VesperMediaTrack nativeTrack,
    VesperMediaTrack declaredTrack,
  ) {
    var evidence = 0;

    final nativeCodec = _codecFamily(nativeTrack.codec);
    final declaredCodec = _codecFamily(declaredTrack.codec);
    if (nativeCodec != null && declaredCodec != null) {
      if (nativeCodec != declaredCodec) {
        return null;
      }
      evidence += 2;
    }

    final nativeWidth = nativeTrack.width;
    final declaredWidth = declaredTrack.width;
    if (nativeWidth != null && declaredWidth != null) {
      if (nativeWidth != declaredWidth) {
        return null;
      }
      evidence += 1;
    }

    final nativeHeight = nativeTrack.height;
    final declaredHeight = declaredTrack.height;
    if (nativeHeight != null && declaredHeight != null) {
      if (nativeHeight != declaredHeight) {
        return null;
      }
      evidence += 3;
    }

    final nativeFrameRate = nativeTrack.frameRate;
    final declaredFrameRate = declaredTrack.frameRate;
    if (nativeFrameRate != null && declaredFrameRate != null) {
      if ((nativeFrameRate - declaredFrameRate).abs() > 1) {
        return null;
      }
      evidence += 2;
    }

    final nativeLabelQualityId = _qualityIdFromTrackLabel(nativeTrack.label);
    final declaredLabelQualityId = _qualityIdFromTrackLabel(
      declaredTrack.label,
    );
    if (nativeLabelQualityId != null && declaredLabelQualityId != null) {
      if (nativeLabelQualityId != declaredLabelQualityId) {
        return null;
      }
      evidence += 4;
    }

    final nativeBitRate = nativeTrack.bitRate;
    final declaredBitRate = declaredTrack.bitRate;
    final hasBitRateEvidence =
        nativeBitRate != null &&
        nativeBitRate > 0 &&
        declaredBitRate != null &&
        declaredBitRate > 0;
    if (hasBitRateEvidence) {
      evidence += 1;
    }
    if (evidence < 3) {
      return null;
    }
    final bitRateDelta = hasBitRateEvidence
        ? (nativeBitRate - declaredBitRate).abs() / declaredBitRate
        : double.infinity;
    return (evidence: evidence, bitRateDelta: bitRateDelta);
  }

  static bool _isBetterNativeMatch(
    ({String optionId, int evidence, double bitRateDelta}) candidate,
    ({String optionId, int evidence, double bitRateDelta}) current,
  ) {
    if (candidate.evidence != current.evidence) {
      return candidate.evidence > current.evidence;
    }
    return candidate.bitRateDelta < current.bitRateDelta;
  }

  static String? _codecFamily(String? codec) {
    final value = codec?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.contains('dvh1') || value.contains('dvhe')) {
      return 'dolby-vision';
    }
    if (value.contains('av01')) {
      return 'av1';
    }
    if (value.contains('hev1') || value.contains('hvc1')) {
      return 'hevc';
    }
    if (value.contains('avc1')) {
      return 'avc';
    }
    return value.split('.').first;
  }

  static int? _qualityIdFromTrackId(String trackId) {
    final match = RegExp(r'^video-(\d+)-').firstMatch(trackId);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    final nestedMatch = RegExp(r':video-(\d+)-').firstMatch(trackId);
    if (nestedMatch != null) {
      return int.tryParse(nestedMatch.group(1)!);
    }
    return int.tryParse(trackId);
  }

  static int? _qualityIdFromTrackLabel(String? label) {
    final value = label?.toLowerCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.contains('杜比视界') || value.contains('dolby vision')) {
      return 126;
    }
    if (value.contains('hdr')) {
      return 125;
    }
    if (value.contains('8k')) {
      return 127;
    }
    if (value.contains('4k') || value.contains('2160')) {
      return 120;
    }
    if (value.contains('1080') && value.contains('60')) {
      return 116;
    }
    if (value.contains('1080') &&
        (value.contains('高码率') || value.contains('high bitrate'))) {
      return 112;
    }
    if (value.contains('1080')) {
      return 80;
    }
    if (value.contains('720') && value.contains('60')) {
      return 74;
    }
    if (value.contains('720')) {
      return 64;
    }
    if (value.contains('480')) {
      return 32;
    }
    if (value.contains('360')) {
      return 16;
    }
    if (value.contains('240')) {
      return 6;
    }
    return null;
  }

  static int? _qualityIdFromTrackShape(VesperMediaTrack track) {
    final height = track.height;
    if (height == null || height <= 0) {
      return null;
    }

    final frameRate = track.frameRate ?? 0;
    if (height >= 4320) {
      return 127;
    }
    if (height >= 2160) {
      return 120;
    }
    if (height >= 1080) {
      return frameRate >= 50 ? 116 : 80;
    }
    if (height >= 720) {
      return frameRate >= 50 ? 74 : 64;
    }
    if (height >= 480) {
      return 32;
    }
    if (height >= 360) {
      return 16;
    }
    return 6;
  }

  static int? _codecIdFromTrackId(String trackId) {
    final match = RegExp(r'(?:^|:)video-\d+-(\d+)-').firstMatch(trackId);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }
}
