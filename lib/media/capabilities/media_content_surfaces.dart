import 'package:flutter/widgets.dart';

import '../models/media_detail.dart';
import '../models/media_playback_target.dart';

/// 内容面板能力：简介/评论/相关视频等平台定义性 UX 由单次播放 binding
/// 提供 widget，壳只负责 tab 槽位与面板宿主。
///
/// 未声明该能力的平台不渲染内容 tab；互动栏由 binding 的独立能力决定。
abstract interface class MediaContentSurfaces {
  /// 简介 tab 文案（如 "简介"）。
  String get introTabLabel;

  /// 评论 tab 文案（如 "评论"）。为 null 时不渲染评论 tab。
  String? get commentsTabLabel;

  /// 简介面板：包含简介、计数、选集入口与相关视频（平台自持数据源）。
  Widget buildIntroSurface(
    BuildContext context,
    MediaPlaybackTarget target,
    MediaSurfaceHost host,
  );

  /// 评论面板；为 null 时评论 tab 自动隐藏。
  Widget? buildCommentsSurface(
    BuildContext context,
    MediaPlaybackTarget target,
  );
}

/// 壳提供给内容面板的宿主回调。
final class MediaSurfaceHost {
  const MediaSurfaceHost({required this.pushPlayback});

  /// 打开新的播放页（如从相关视频跳转）。由壳实现，推到当前导航栈。
  final void Function(MediaDetail detail, MediaPlaybackEntry entry)
  pushPlayback;
}

/// 相关视频/推荐条目（内容面板内部使用的展示数据）。
final class MediaRelatedItem {
  const MediaRelatedItem({
    required this.mediaId,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.durationLabel,
    required this.playCountLabel,
    required this.danmakuCountLabel,
  });

  final String mediaId;
  final String title;
  final String author;
  final String coverUrl;
  final String durationLabel;
  final String playCountLabel;
  final String danmakuCountLabel;
}
