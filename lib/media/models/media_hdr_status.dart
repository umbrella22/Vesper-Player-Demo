import 'package:vesper_player/vesper_player.dart';

/// HDR 表达的三条独立信息轴。
///
/// 「有 HDR 档位」「能播放」「设备真正在输出 HDR」是三件事，任何一条都
/// 不能由另一条推导：
///
/// - [source] 来自本应用的清单解析（qn 与 codec 字符串），是确定的；
/// - [playability] 来自 SDK 轨道能力判定，表示本次会话能否尝试该档位；
/// - [output] 需要 SDK 提供当前显示链路的实际输出证据。能力探测只证明
///   支持能力，不能确认正在输出 HDR；证据不足时界面显示「未确认」。
final class MediaHdrStatus {
  const MediaHdrStatus({
    this.source = MediaHdrSource.none,
    this.playability = MediaHdrPlayability.notApplicable,
    this.output = MediaHdrOutputState.unknown,
    this.outputDetail,
    this.sourceLabel,
    this.dolbyVisionProfile,
    this.lumaBitDepth,
    this.maxContentLightLevelNits,
  });

  /// 空状态：当前目标是 SDR，或尚未解析。
  static const none = MediaHdrStatus();

  /// 源侧 HDR 类型。由清单与 codec 字符串确定。
  final MediaHdrSource source;

  /// 该档位在当前设备上能否尝试播放。
  final MediaHdrPlayability playability;

  /// 设备实际输出 HDR 的证据强度。
  final MediaHdrOutputState output;

  /// 输出判定的一句话依据，用于诊断展示。
  final String? outputDetail;

  /// 平台提供的档位文案（如「HDR 真彩」），有则优先用于展示。
  final String? sourceLabel;

  final int? dolbyVisionProfile;
  final int? lumaBitDepth;
  final int? maxContentLightLevelNits;

  /// 源是 HDR/DV 档位。仅表示素材带 HDR，不表示设备能播或正在输出 HDR。
  bool get hasHdrSource => source != MediaHdrSource.none;

  /// 已在界面上确认设备正在输出 HDR。只有这一状态允许显示「已开启 HDR」。
  bool get isOutputConfirmed => output == MediaHdrOutputState.confirmed;

  /// 源是 HDR，但输出无法确认。界面应显示「HDR（未确认输出）」，不得显示已开启。
  bool get isOutputUnconfirmed =>
      hasHdrSource && output != MediaHdrOutputState.confirmed;

  /// 角标文案；SDR 时返回 null，调用方不渲染角标。
  String? get badgeLabel => switch (source) {
    MediaHdrSource.dolbyVision => 'DV',
    MediaHdrSource.hdr10 || MediaHdrSource.hlg => 'HDR',
    MediaHdrSource.unknown => 'HDR?',
    MediaHdrSource.none => null,
  };

  /// 展示文案：区分「有档位」「能播」「确认输出」。
  String get displayLabel {
    final label =
        sourceLabel ??
        switch (source) {
          MediaHdrSource.dolbyVision => '杜比视界',
          MediaHdrSource.hdr10 => 'HDR10',
          MediaHdrSource.hlg => 'HLG',
          MediaHdrSource.unknown => 'HDR（类型未知）',
          MediaHdrSource.none => 'SDR',
        };
    if (!hasHdrSource) {
      return label;
    }
    return switch (output) {
      MediaHdrOutputState.confirmed => '$label · 已开启 HDR',
      MediaHdrOutputState.unconfirmed => '$label · 输出未确认',
      MediaHdrOutputState.unsupported => '$label · 当前输出为 SDR',
      MediaHdrOutputState.unknown => '$label · 输出未确认',
    };
  }

  /// 会话信息里的一行依据。
  String get diagnosticsLabel {
    final parts = <String>[
      ?sourceLabel,
      switch (playability) {
        MediaHdrPlayability.playable => '可播',
        MediaHdrPlayability.unknown => '兼容性未知',
        MediaHdrPlayability.unplayable => '不可播',
        MediaHdrPlayability.notApplicable => '不适用',
      },
      switch (output) {
        MediaHdrOutputState.confirmed => '已确认 HDR 输出',
        MediaHdrOutputState.unconfirmed => '输出未确认',
        MediaHdrOutputState.unsupported => '输出 SDR',
        MediaHdrOutputState.unknown => '未探测',
      },
      if (lumaBitDepth case final int depth) '${depth}bit',
      if (dolbyVisionProfile case final int profile) 'DV profile $profile',
      if (maxContentLightLevelNits case final int nits) 'MaxCLL ${nits}nits',
      ?outputDetail,
    ];
    return parts.join(' · ');
  }

  MediaHdrStatus copyWith({
    MediaHdrSource? source,
    MediaHdrPlayability? playability,
    MediaHdrOutputState? output,
    String? outputDetail,
    String? sourceLabel,
    int? dolbyVisionProfile,
    int? lumaBitDepth,
    int? maxContentLightLevelNits,
  }) {
    return MediaHdrStatus(
      source: source ?? this.source,
      playability: playability ?? this.playability,
      output: output ?? this.output,
      outputDetail: outputDetail ?? this.outputDetail,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      dolbyVisionProfile: dolbyVisionProfile ?? this.dolbyVisionProfile,
      lumaBitDepth: lumaBitDepth ?? this.lumaBitDepth,
      maxContentLightLevelNits:
          maxContentLightLevelNits ?? this.maxContentLightLevelNits,
    );
  }
}

/// 源侧 HDR 类型：来自清单解析，与本机能力无关。
enum MediaHdrSource { none, hdr10, hlg, dolbyVision, unknown }

/// 档位可播性：与源侧类型、设备输出都独立。
enum MediaHdrPlayability { notApplicable, playable, unknown, unplayable }

/// 设备输出状态：须有实际输出证据，不得由源类型或支持能力推导。
enum MediaHdrOutputState { unknown, confirmed, unconfirmed, unsupported }

/// 一个清晰度选项的 HDR 角标：源标识 + 输出确认。
///
/// 两者独立：`label` 说「这个档位是 HDR 源」，`confirmed` 说「设备已确认在
/// 输出 HDR」。没有探测证据时 `confirmed` 必须是 false。
final class TuningQualityHdrBadge {
  const TuningQualityHdrBadge({required this.label, this.confirmed = false});

  final String label;
  final bool confirmed;
}

/// 判定 HDR 源类型。
///
/// 使用明确的 DV codec 前缀或质量 ID（125 HDR、126 DV）。位深不能证明 HDR。
MediaHdrSource mediaHdrSourceForTrack(
  VesperMediaTrack track, {
  int? qualityId,
}) {
  final codec = track.codec?.toLowerCase() ?? '';
  if (codec.startsWith('dvh1') || codec.startsWith('dvhe')) {
    return MediaHdrSource.dolbyVision;
  }
  if (qualityId == 126) {
    return MediaHdrSource.dolbyVision;
  }
  if (qualityId == 125) {
    return MediaHdrSource.hdr10;
  }
  return MediaHdrSource.none;
}

/// 能力探测只补充素材元数据。SDK 0.5.6 没有明确的实际显示输出证据，
/// P010、sessionProbe 和显示设备能力都不能确认正在输出 HDR 或 SDR。
MediaHdrStatus mediaHdrStatusFromProbe({
  required VesperPlaybackCapabilityProbeResult probe,
  required MediaHdrSource source,
  required MediaHdrPlayability playability,
  String? sourceLabel,
}) {
  final metadata = probe.hdrMetadata;

  return MediaHdrStatus(
    source: source,
    playability: playability,
    output: probe.status == VesperPlaybackCapabilityProbeStatus.unknown
        ? MediaHdrOutputState.unknown
        : MediaHdrOutputState.unconfirmed,
    outputDetail: '能力探测未提供实际显示输出证据',
    sourceLabel: sourceLabel,
    dolbyVisionProfile: metadata?.dolbyVisionProfile,
    lumaBitDepth: metadata?.lumaBitDepth,
    maxContentLightLevelNits: metadata?.maxContentLightLevelNits,
  );
}

/// 能力告警是否指向 HDR 原生帧处理限制。
///
/// 判别依据是 `reasonRawValue`（平台原始串），不是 `reason` 枚举：
/// [VesperCapabilityWarningReason] 目前只有 `hdrNativeFrameUnsupported`
/// 一个值，反序列化时它是缺省回退值，因此每条能力告警的 `reason` 都是它。
/// 若不按原始串判别，`runtimeTrackRejected` 会被误判为 HDR 告警而跳过轨道
/// 拒绝处理。与轨道拒绝分开归类：前者是 HDR 输出通路问题，后者是轨道被
/// 运行时拒绝，两者的提示与恢复动作不同。
bool mediaCapabilityWarningIsHdrRelated(VesperCapabilityWarning warning) {
  return warning.reasonRawValue == 'hdrNativeFrameUnsupported';
}
