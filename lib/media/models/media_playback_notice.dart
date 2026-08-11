/// 播放恢复失败提示（自动重新解析重试后仍失败时展示）。
final class MediaPlaybackRecoveryNotice {
  const MediaPlaybackRecoveryNotice({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;
}
