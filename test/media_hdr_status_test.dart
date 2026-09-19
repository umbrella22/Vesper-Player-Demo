import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/media/models/media_hdr_status.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  group('HDR 源类型判定', () {
    test('codec 字符串区分 DV 与普通 HEVC', () {
      // DV 只能靠 codec 前缀识别：codecid 12 与 HEVC 相同。
      expect(
        mediaHdrSourceForTrack(_track(codec: 'dvh1.05.06')),
        MediaHdrSource.dolbyVision,
      );
      expect(
        mediaHdrSourceForTrack(_track(codec: 'dvhe.08.03')),
        MediaHdrSource.dolbyVision,
      );
      // 普通 HEVC 不是 HDR——HEVC 本身不等于 HDR。
      expect(
        mediaHdrSourceForTrack(_track(codec: 'hev1.1.6.L120.90')),
        MediaHdrSource.none,
      );
      expect(
        mediaHdrSourceForTrack(_track(codec: 'hvc1.1.6.L120.90')),
        MediaHdrSource.none,
      );
    });

    test('质量 ID 让 HDR 档位可识别，未知档位不猜测', () {
      expect(
        mediaHdrSourceForTrack(_track(codec: 'hev1'), qualityId: 125),
        MediaHdrSource.hdr10,
      );
      expect(
        mediaHdrSourceForTrack(_track(codec: 'hev1'), qualityId: 126),
        MediaHdrSource.dolbyVision,
      );
      // 1080P 等普通档位保持 SDR。
      expect(
        mediaHdrSourceForTrack(_track(codec: 'avc1'), qualityId: 80),
        MediaHdrSource.none,
      );
      expect(
        mediaHdrSourceForTrack(_track(codec: 'av01.0.08M.10')),
        MediaHdrSource.none,
      );
      expect(
        mediaHdrSourceForTrack(_track(codec: 'av01.0.08M.08')),
        MediaHdrSource.none,
      );
    });
  });

  group('HDR 输出三态', () {
    test('unknown 探测不产生「已开启 HDR」', () {
      final status = mediaHdrStatusFromProbe(
        probe: _probe(
          hdrKind: VesperPlaybackCapabilityHdrKind.unknown,
          outputFormat: VesperPlaybackCapabilityOutputFormat.unknown,
        ),
        source: MediaHdrSource.hdr10,
        playability: MediaHdrPlayability.playable,
      );
      expect(status.hasHdrSource, isTrue);
      expect(status.isOutputConfirmed, isFalse);
      expect(status.displayLabel, contains('输出未确认'));
      expect(status.displayLabel, isNot(contains('已开启')));
    });

    test('已知 HDR 类型但输出通路不是 10bit 时不算确认', () {
      final status = mediaHdrStatusFromProbe(
        probe: _probe(
          hdrKind: VesperPlaybackCapabilityHdrKind.hdr10,
          outputFormat: VesperPlaybackCapabilityOutputFormat.nv12,
        ),
        source: MediaHdrSource.hdr10,
        playability: MediaHdrPlayability.playable,
      );
      expect(status.isOutputConfirmed, isFalse);
      expect(status.output, MediaHdrOutputState.unconfirmed);
    });

    test('p010 但缺少会话级证据时仍不算确认', () {
      final status = mediaHdrStatusFromProbe(
        probe: _probe(
          hdrKind: VesperPlaybackCapabilityHdrKind.hdr10,
          outputFormat: VesperPlaybackCapabilityOutputFormat.p010,
          confidence: VesperPlaybackCapabilityConfidence.codecOnly,
        ),
        source: MediaHdrSource.hdr10,
        playability: MediaHdrPlayability.playable,
      );
      expect(status.isOutputConfirmed, isFalse);
      expect(status.outputDetail, contains('未提供实际显示输出证据'));
    });

    test('P010 和 sessionProbe 不能单独确认实际 HDR 输出', () {
      final status = mediaHdrStatusFromProbe(
        probe: _probe(
          hdrKind: VesperPlaybackCapabilityHdrKind.hdr10,
          outputFormat: VesperPlaybackCapabilityOutputFormat.p010,
          confidence: VesperPlaybackCapabilityConfidence.sessionProbe,
        ),
        source: MediaHdrSource.hdr10,
        playability: MediaHdrPlayability.playable,
      );
      expect(status.isOutputConfirmed, isFalse);
      expect(status.displayLabel, contains('输出未确认'));
    });

    test('能力探测报告 none 不表示当前实际输出 SDR', () {
      final status = mediaHdrStatusFromProbe(
        probe: _probe(hdrKind: VesperPlaybackCapabilityHdrKind.none),
        source: MediaHdrSource.dolbyVision,
        playability: MediaHdrPlayability.unplayable,
      );
      expect(status.hasHdrSource, isTrue);
      expect(status.output, MediaHdrOutputState.unconfirmed);
      expect(status.displayLabel, contains('输出未确认'));
    });

    test('可播性与输出确认互相独立', () {
      final status = mediaHdrStatusFromProbe(
        probe: _probe(
          hdrKind: VesperPlaybackCapabilityHdrKind.dolbyVision,
          outputFormat: VesperPlaybackCapabilityOutputFormat.p010,
          confidence: VesperPlaybackCapabilityConfidence.sessionProbe,
          dolbyVisionProfile: 8,
        ),
        source: MediaHdrSource.dolbyVision,
        playability: MediaHdrPlayability.unknown,
        sourceLabel: '杜比视界',
      );
      // 素材元数据和可播性仍可展示，但不据此确认输出。
      expect(status.playability, MediaHdrPlayability.unknown);
      expect(status.isOutputConfirmed, isFalse);
      expect(status.dolbyVisionProfile, 8);
      expect(status.diagnosticsLabel, contains('DV profile 8'));
      expect(status.diagnosticsLabel, contains('兼容性未知'));
    });
  });

  group('HDR 告警归类', () {
    test('按原始串判别，不按只有单一取值的枚举', () {
      expect(
        mediaCapabilityWarningIsHdrRelated(
          _warning(reasonRawValue: 'hdrNativeFrameUnsupported'),
        ),
        isTrue,
      );
      // runtimeTrackRejected 的 reason 也会回退成 hdrNativeFrameUnsupported，
      // 必须靠原始串区分，否则轨道拒绝处理会被跳过。
      expect(
        mediaCapabilityWarningIsHdrRelated(
          _warning(reasonRawValue: 'runtimeTrackRejected'),
        ),
        isFalse,
      );
    });
  });

  test('无 HDR 源的角标为空且不显示已开启', () {
    const status = MediaHdrStatus.none;
    expect(status.badgeLabel, isNull);
    expect(status.hasHdrSource, isFalse);
    expect(status.displayLabel, 'SDR');
  });
}

VesperMediaTrack _track({required String codec}) {
  return VesperMediaTrack(
    id: 'video-125-12-1000-0',
    kind: VesperMediaTrackKind.video,
    label: 'HDR 真彩',
    codec: codec,
  );
}

VesperPlaybackCapabilityProbeResult _probe({
  required VesperPlaybackCapabilityHdrKind hdrKind,
  VesperPlaybackCapabilityOutputFormat outputFormat =
      VesperPlaybackCapabilityOutputFormat.unknown,
  VesperPlaybackCapabilityConfidence confidence =
      VesperPlaybackCapabilityConfidence.codecOnly,
  int? dolbyVisionProfile,
}) {
  return VesperPlaybackCapabilityProbeResult(
    status: VesperPlaybackCapabilityProbeStatus.supported,
    codecFamily: VesperPlaybackCodecFamily.hevc,
    systemPlaybackSupported: true,
    hardwareDecodeSupported: true,
    sdkManagedNativeFrameSupported: false,
    recommendedPlaybackPath: VesperRecommendedPlaybackPath.systemPlayer,
    outputFormat: outputFormat,
    hdrKind: hdrKind,
    dolbyVisionMode: VesperPlaybackCapabilityDolbyVisionMode.none,
    confidence: confidence,
    hdrMetadata: VesperHdrMetadata(
      hdrKind: hdrKind,
      dolbyVisionProfile: dolbyVisionProfile,
    ),
  );
}

VesperCapabilityWarning _warning({required String reasonRawValue}) {
  return VesperCapabilityWarning(
    reason: VesperCapabilityWarningReason.hdrNativeFrameUnsupported,
    reasonRawValue: reasonRawValue,
    recommendedPlaybackPath: VesperRecommendedPlaybackPath.systemPlayer,
    hdrKind: VesperPlaybackCapabilityHdrKind.hdr10,
  );
}
