part of 'bili_hub_page.dart';

class _HubNavigationBar extends StatelessWidget {
  const _HubNavigationBar({
    required this.selectedTab,
    required this.onSelected,
  });

  final BiliHubTab selectedTab;
  final ValueChanged<BiliHubTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppGlassBottomNavigation(
      selectedIndex: selectedTab.index,
      onSelected: (index) => onSelected(BiliHubTab.values[index]),
      items: const [
        AppGlassNavigationItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: '首页',
        ),
        AppGlassNavigationItem(
          icon: Icons.live_tv_outlined,
          activeIcon: Icons.live_tv_rounded,
          label: '我的',
        ),
      ],
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  const _InlineErrorBanner({
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final String message;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: visualTheme.destructive.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: visualTheme.destructive),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: visualTheme.textPrimary,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: visualTheme.surface,
        borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: visualTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({
    required this.name,
    required this.avatarUrl,
    required this.onTap,
  });

  final String name;
  final String avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: AppVisualTokens.minimumTapTarget,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Center(
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppVisualTokens.biliSourcePink.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.18
                  : 0.12,
            ),
            backgroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
            child: avatarUrl.isEmpty
                ? Text(
                    (name.isEmpty ? 'B' : name.characters.first).toUpperCase(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppVisualTokens.biliSourcePink,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

final class _HomeVideoItem {
  const _HomeVideoItem({
    required this.bvid,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.durationLabel,
    required this.playCountLabel,
    required this.vertical,
  });

  factory _HomeVideoItem.fromFeed(BiliFeedVideo item) {
    return _HomeVideoItem(
      bvid: item.bvid,
      title: item.title,
      author: item.author,
      coverUrl: item.coverUrl,
      durationLabel: item.durationLabel,
      playCountLabel: item.playCountLabel,
      vertical: false,
    );
  }

  factory _HomeVideoItem.fromSearch(BiliSearchResult item) {
    return _HomeVideoItem(
      bvid: item.bvid,
      title: item.title,
      author: item.author,
      coverUrl: item.coverUrl,
      durationLabel: item.durationLabel,
      playCountLabel: item.playCountLabel,
      vertical: false,
    );
  }

  final String bvid;
  final String title;
  final String author;
  final String coverUrl;
  final String durationLabel;
  final String playCountLabel;
  final bool vertical;
}
