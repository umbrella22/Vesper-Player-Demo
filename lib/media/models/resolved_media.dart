import 'package:vesper_player/vesper_player.dart';

/// 解析完成的可播放媒体，是适配器与播放编排之间的归一化结果。
///
/// [toSource] 与平台无关：任何平台解析出的内容都转换为统一的
/// [VesperPlayerSource] 交给 SDK 播放。
final class ResolvedMediaPlayback {
  const ResolvedMediaPlayback({
    required this.title,
    required this.subtitle,
    required this.uri,
    required this.protocol,
    required this.transportLabel,
    required this.isLocalFile,
    this.headers = const <String, String>{},
    this.videoTracks = const <VesperMediaTrack>[],
    this.subtitleTracks = const <ResolvedSubtitleTrack>[],
    this.subtitleError,
    this.debugPath,
    this.qualityOptions = const <MediaQualityOption>[],
    this.supportsCodecSelection = false,
  });

  final String title;
  final String subtitle;
  final String uri;
  final VesperPlayerSourceProtocol protocol;
  final String transportLabel;
  final bool isLocalFile;
  final Map<String, String> headers;
  final List<VesperMediaTrack> videoTracks;
  final List<ResolvedSubtitleTrack> subtitleTracks;
  final String? subtitleError;
  final String? debugPath;

  /// 清晰度选项（按清晰度分组的轨道候选），由适配器在解析时构建。
  final List<MediaQualityOption> qualityOptions;

  /// 该平台是否为同一清晰度提供多 codec（如 B 站 AV1/HEVC/AVC 细分）。
  final bool supportsCodecSelection;

  VesperPlayerSource toSource() {
    final sourceLabel = subtitle.isEmpty ? title : '$title · $subtitle';
    final externalSubtitles = subtitleTracks
        .map(
          (track) => VesperExternalSubtitleSource(
            id: track.id,
            uri: track.url,
            mimeType: VesperExternalSubtitleSource.mimeWebvtt,
            language: track.language,
            label: track.languageLabel,
            isDefault: track.isDefault,
          ),
        )
        .toList(growable: false);
    if (isLocalFile) {
      return VesperPlayerSource(
        uri: uri,
        label: sourceLabel,
        kind: VesperPlayerSourceKind.local,
        protocol: protocol,
        headers: headers,
        externalSubtitles: externalSubtitles,
      );
    }

    return VesperPlayerSource.remote(
      uri: uri,
      label: sourceLabel,
      protocol: protocol,
      headers: headers,
      externalSubtitles: externalSubtitles,
    );
  }
}

/// 归一化的字幕轨道（外挂字幕），由适配器从平台字幕数据构建。
final class ResolvedSubtitleTrack {
  const ResolvedSubtitleTrack({
    required this.id,
    required this.language,
    required this.languageLabel,
    required this.url,
    this.isDefault = false,
    this.format = 'webvtt',
  });

  final String id;
  final String language;
  final String languageLabel;
  final String url;
  final bool isDefault;
  final String format;
}

/// 一个清晰度选项：同一清晰度下的一个或多个轨道候选。
final class MediaQualityOption {
  const MediaQualityOption({
    required this.id,
    required this.label,
    required this.tracks,
    this.isDefault = false,
  });

  /// 平台内清晰度标识（如 B 站 125），壳不解释其含义。
  final String id;

  /// 平台提供的清晰度文案（如 "HDR 真彩"）。
  final String label;

  final List<VesperMediaTrack> tracks;
  final bool isDefault;
}

/// 当前播放器目录下，一个清晰度选项的动态可选状态。
///
/// `unknown` 表示 SDK 尚无可靠能力证据，仍允许用户尝试；它不能被当作
/// `unavailable`。解析结果中的 [MediaQualityOption] 保持静态分组，本类型由
/// 播放 ViewModel 按最新 track catalog 计算。
enum MediaQualityAvailability { available, unavailable, unknown }

final class MediaQualitySelectionOption {
  const MediaQualitySelectionOption({
    required this.option,
    required this.availability,
    required this.candidateTracks,
    this.unavailableReason,
  });

  final MediaQualityOption option;
  final MediaQualityAvailability availability;
  final List<VesperMediaTrack> candidateTracks;
  final VesperTrackSupportReason? unavailableReason;

  String get id => option.id;
  String get label => option.label;
  bool get isDefault => option.isDefault;
  bool get canSelect => availability != MediaQualityAvailability.unavailable;
}

/// 平台级清晰度能力声明。
final class MediaQualityPolicy {
  const MediaQualityPolicy({
    this.supportsCodecSelection = false,
    this.codecLabelFor,
    this.codecIdentityFor,
    this.codecIdentityLabelFor,
  });

  /// 是否支持在清晰度内细分 codec（AV1/HEVC/AVC）选择。
  final bool supportsCodecSelection;

  /// 可选：轨道 → codec 子选项展示文案。
  final String? Function(VesperMediaTrack track)? codecLabelFor;

  /// 可选：轨道 → codec 策略身份。用于选择匹配与归组；
  /// 缺省回退到 [codecLabelFor]。
  ///
  /// 展示 label 与策略身份分开的场景：平台把某类轨道（如 Dolby Vision）
  /// 展示为独立选项，但策略上归入另一组（如 HEVC）——身份相同即同组，
  /// 选中与轨道匹配都按身份进行。
  final String? Function(VesperMediaTrack track)? codecIdentityFor;

  /// 可选：策略身份 → 规范展示标签。策略身份是匹配键（可能是内部键，
  /// 如 hevc-main），不能直接展示给用户；平台应提供稳定的规范标签。
  /// 未提供（null 或返回 null）时，壳回退到该组内轨道的展示 label
  /// （[codecLabelFor]），绝不直接显示身份内部键。
  final String? Function(String identity)? codecIdentityLabelFor;

  /// 轨道 → 策略身份（缺省 = 展示 label）。
  String? Function(VesperMediaTrack track)? get codecStrategyIdentityFor =>
      codecIdentityFor ?? codecLabelFor;
}
