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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EAF0))),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: selectedTab.index,
          onTap: (index) => onSelected(BiliHubTab.values[index]),
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFFB7299),
          unselectedItemColor: const Color(0xFF5C6069),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.live_tv_outlined),
              activeIcon: Icon(Icons.live_tv_rounded),
              label: '我的',
            ),
          ],
        ),
      ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFB33A59)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF8D2A46),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF20232B),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF858A94),
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
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: CircleAvatar(
        radius: 16,
        backgroundColor: const Color(0xFFFFDCE7),
        backgroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
        child: avatarUrl.isEmpty
            ? Text(
                (name.isEmpty ? 'B' : name.characters.first).toUpperCase(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFFB7299),
                  fontWeight: FontWeight.w900,
                ),
              )
            : null,
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

String _formatPosition(int positionMs, int? durationMs) {
  final left = biliFormatDurationSeconds(positionMs ~/ 1000);
  final right = durationMs == null
      ? '--:--'
      : biliFormatDurationSeconds(durationMs ~/ 1000);
  return '$left / $right';
}
