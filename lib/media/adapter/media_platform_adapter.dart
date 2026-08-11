import 'package:vesper_player/vesper_player.dart';

import '../capabilities/media_content_surfaces.dart';
import '../capabilities/media_danmaku.dart';
import '../capabilities/media_engagement.dart';
import '../capabilities/media_history.dart';
import '../models/media_detail.dart';
import '../models/resolved_media.dart';

/// 平台适配器：新供应商接入的全部成本都在实现这个接口。
///
/// 唯一必须实现的方法是 [resolvePlayback]；其余均为可选能力，
/// 缺省为"无"——壳据此决定渲染什么，不做平台判断。
abstract interface class MediaPlatformAdapter {
  /// 把平台视频解析成源 + 轨道 + 字幕。
  Future<ResolvedMediaPlayback> resolvePlayback({
    required MediaDetail detail,
    required MediaPlaybackEntry entry,
  });

  /// 互动能力声明（动作槽列表）。null 表示无互动栏。
  MediaEngagementCapability? get engagement;

  /// 弹幕能力。null 表示不挂载弹幕 overlay。
  MediaDanmakuProvider? get danmaku;

  /// 内容面板（简介/评论/相关视频）。null 表示无内容 tab。
  MediaContentSurfaces? get contentSurfaces;

  /// 历史能力。null 表示不记录观看历史。
  MediaHistoryStore? get history;

  /// 平台级清晰度能力声明。
  MediaQualityPolicy get qualityPolicy;

  /// DLNA 投屏格式适配配置。null 表示不支持投屏。
  MediaDlnaConfig? get dlnaConfig;
}

/// DLNA 投屏配置（请求头等平台私有部分由适配器提供）。
final class MediaDlnaConfig {
  const MediaDlnaConfig({required this.formatAdaptation});

  final VesperExternalFormatAdaptationConfig formatAdaptation;
}
