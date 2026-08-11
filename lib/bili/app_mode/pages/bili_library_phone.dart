part of 'bili_library_page.dart';

class _LibraryLoadMoreButton extends StatelessWidget {
  const _LibraryLoadMoreButton({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more_rounded),
        label: Text(loading ? '加载中' : '加载更多'),
      ),
    );
  }
}

class _FollowingTile extends StatelessWidget {
  const _FollowingTile({required this.user, required this.onTap});

  final BiliFollowingUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: visualTheme.surface,
      borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppVisualTokens.biliSourcePink.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.12,
          ),
          backgroundImage: user.avatarUrl.isEmpty
              ? null
              : NetworkImage(user.avatarUrl),
          child: user.avatarUrl.isEmpty
              ? const Icon(
                  Icons.person_outline_rounded,
                  color: AppVisualTokens.primaryBlue,
                )
              : null,
        ),
        title: Text(
          user.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          user.sign.isEmpty ? (user.officialLabel ?? '已关注') : user.sign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _LibraryVideoTile extends StatelessWidget {
  const _LibraryVideoTile({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.progressMs,
    required this.durationMs,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final int progressMs;
  final int durationMs;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final progress = durationMs <= 0
        ? 0.0
        : (progressMs / durationMs).clamp(0.0, 1.0).toDouble();
    return Material(
      color: visualTheme.surface,
      borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 116,
                  height: 70,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      coverUrl.isEmpty
                          ? ColoredBox(color: visualTheme.surfaceRaised)
                          : Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  ColoredBox(color: visualTheme.surfaceRaised),
                            ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: visualTheme.imageOutline,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (progress > 0)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.25,
                            ),
                            color: AppVisualTokens.primaryBlue,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: visualTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: visualTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryErrorView extends StatelessWidget {
  const _LibraryErrorView({required this.message, this.onLogin, this.onRetry});

  final String message;
  final VoidCallback? onLogin;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          size: 44,
          color: AppVisualTokens.primaryBlue,
        ),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 18),
        if (onLogin != null)
          FilledButton(onPressed: onLogin, child: const Text('登录')),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

class _LibraryEmptyView extends StatelessWidget {
  const _LibraryEmptyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.inbox_outlined, size: 42, color: visualTheme.textTertiary),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: visualTheme.textSecondary),
        ),
      ],
    );
  }
}
