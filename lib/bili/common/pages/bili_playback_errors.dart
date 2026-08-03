part of 'bili_playback_page.dart';

class _PlaybackInlineError extends StatelessWidget {
  const _PlaybackInlineError({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          visualTheme.destructive.withValues(alpha: 0.12),
          visualTheme.surfaceRaised,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: visualTheme.destructive,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: visualTheme.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => unawaited(onPressed()),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _BiliPlaybackErrorState extends StatelessWidget {
  const _BiliPlaybackErrorState({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: visualTheme.surface,
              borderRadius: BorderRadius.circular(30),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: visualTheme.shadow,
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '播放器启动失败',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: visualTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    biliErrorMessage(error),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: visualTheme.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => unawaited(onRetry()),
                    child: const Text('重新尝试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
