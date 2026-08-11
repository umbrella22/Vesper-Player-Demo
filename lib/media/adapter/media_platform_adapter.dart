import 'package:vesper_player/vesper_player.dart';

import '../capabilities/media_danmaku.dart';
import '../capabilities/media_history.dart';
import '../models/media_detail.dart';
import '../models/resolved_media.dart';

/// 平台适配器：解析平台媒体，并声明平台级静态能力。
///
/// 唯一必须实现的方法是 [resolvePlayback]；其余均为可选能力，
/// 缺省为"无"——壳据此决定渲染什么，不做平台判断。
///
/// 新平台通过 `extends MediaPlatformAdapter` 继承缺省能力。互动和内容面板
/// 属于单次播放会话，使用 `MediaPlaybackBinding` 注入播放页。
abstract base class MediaPlatformAdapter {
  const MediaPlatformAdapter();

  /// 把平台视频解析成源 + 轨道 + 字幕。
  Future<ResolvedMediaPlayback> resolvePlayback({
    required MediaDetail detail,
    required MediaPlaybackEntry entry,
  });

  /// 弹幕能力。null 表示不挂载弹幕 overlay。
  MediaDanmakuProvider? get danmaku => null;

  /// 历史能力。null 表示不记录观看历史。
  MediaHistoryStore? get history => null;

  /// 平台级清晰度能力声明。
  MediaQualityPolicy get qualityPolicy => const MediaQualityPolicy();

  /// DLNA 投屏格式适配配置。null 表示不支持投屏。
  MediaDlnaConfig? get dlnaConfig => null;
}

/// DLNA 投屏配置（请求头等平台私有部分由适配器提供）。
final class MediaDlnaConfig {
  const MediaDlnaConfig({required this.formatAdaptation});

  final VesperExternalFormatAdaptationConfig formatAdaptation;
}
