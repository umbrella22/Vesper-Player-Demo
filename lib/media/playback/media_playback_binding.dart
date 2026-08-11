import '../capabilities/media_content_surfaces.dart';
import '../capabilities/media_engagement.dart';
import 'media_playback_presentation.dart';

typedef MediaEngagementCapabilityBuilder =
    MediaEngagementCapability? Function();

typedef MediaContentSurfacesBuilder =
    MediaContentSurfaces? Function(MediaPlaybackContentHost host);

/// 单次播放会话与通用播放页之间的动态能力绑定。
///
/// Adapter 负责解析和平台级服务；互动状态、动作回调和内容 widget 通常
/// 依赖页面级 view model，因此由创建播放页的供应商包装层在这里绑定。
final class MediaPlaybackBinding {
  const MediaPlaybackBinding({
    this.engagementBuilder,
    this.contentSurfacesBuilder,
  });

  /// 构建当前互动能力快照。播放页在信号追踪的 build 栈内调用。
  final MediaEngagementCapabilityBuilder? engagementBuilder;

  /// 构建简介、评论和相关内容面板。每个播放页实例调用一次。
  final MediaContentSurfacesBuilder? contentSurfacesBuilder;

  MediaEngagementCapability? buildEngagement() => engagementBuilder?.call();

  MediaContentSurfaces? buildContentSurfaces(MediaPlaybackContentHost host) =>
      contentSurfacesBuilder?.call(host);
}
