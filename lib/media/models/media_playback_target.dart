import 'media_detail.dart';

/// 一次播放会话的完整目标：详情 + 当前分 P/剧集。
///
/// 适配器的全部能力方法（弹幕、历史等）都接收该对象，保证平台侧总能
/// 拿到解析所需的标识。
final class MediaPlaybackTarget {
  const MediaPlaybackTarget({required this.detail, required this.entry});

  final MediaDetail detail;
  final MediaPlaybackEntry entry;
}
