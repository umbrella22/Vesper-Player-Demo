part of 'bili_hub_page.dart';

@visibleForTesting
int biliHomeGridCrossAxisCountForWidth(double crossAxisExtent) {
  return (crossAxisExtent / 220).floor().clamp(2, 5).toInt();
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.profile,
    required this.controller,
    required this.isSearching,
    required this.onAccountTap,
    required this.onRegionTap,
    required this.onChanged,
    required this.onSubmit,
    required this.onClear,
  });

  final BiliUserProfile profile;
  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onAccountTap;
  final VoidCallback onRegionTap;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AvatarButton(
          name: profile.name,
          avatarUrl: profile.avatarUrl,
          onTap: onAccountTap,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onChanged: (_) => onChanged(),
              onSubmitted: (_) => onSubmit(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF2D3038),
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: '搜索视频、BV 号或链接',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                suffixIcon: isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : onClear == null
                    ? null
                    : IconButton(
                        onPressed: onClear,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 18,
                        tooltip: '清除',
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(
                    color: Color(0xFF9EA2AA),
                    width: 1.1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(
                    color: Color(0xFFFB7299),
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _RegionMenuButton(onTap: onRegionTap),
      ],
    );
  }
}

class _HomeSearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _HomeSearchHeaderDelegate({
    required this.child,
    required this.topPadding,
  });

  final Widget child;
  final double topPadding;

  static const double _contentHeight = 42;

  @override
  double get minExtent => topPadding + _contentHeight;

  @override
  double get maxExtent => topPadding + _contentHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Colors.white,
      elevation: overlapsContent ? 1 : 0,
      shadowColor: const Color(0x1A000000),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, topPadding + 5, 10, 5),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HomeSearchHeaderDelegate oldDelegate) {
    return child != oldDelegate.child || topPadding != oldDelegate.topPadding;
  }
}

class _HomeVideoGrid extends StatelessWidget {
  const _HomeVideoGrid({
    required this.items,
    required this.onTap,
    required this.onCacheTap,
  });

  final List<_HomeVideoItem> items;
  final ValueChanged<_HomeVideoItem> onTap;
  final ValueChanged<_HomeVideoItem> onCacheTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 10.0;
        const crossAxisSpacing = 10.0;
        final crossAxisCount = biliHomeGridCrossAxisCountForWidth(
          constraints.crossAxisExtent,
        );
        final rawTileWidth =
            (constraints.crossAxisExtent -
                horizontalPadding * 2 -
                crossAxisSpacing * (crossAxisCount - 1)) /
            crossAxisCount;
        final tileWidth = rawTileWidth <= 0 ? 1.0 : rawTileWidth;
        final tileHeight = tileWidth * 9 / 16 + _HomeVideoCard.infoHeight;

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            10,
            horizontalPadding,
            18,
          ),
          sliver: SliverGrid.builder(
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: crossAxisSpacing,
              childAspectRatio: tileWidth / tileHeight,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return _HomeVideoCard(
                item: item,
                onTap: () => onTap(item),
                onCacheTap: () => onCacheTap(item),
              );
            },
          ),
        );
      },
    );
  }
}

class _HomeVideoCard extends StatelessWidget {
  const _HomeVideoCard({
    required this.item,
    required this.onTap,
    required this.onCacheTap,
  });

  static const double infoHeight = 88;

  final _HomeVideoItem item;
  final VoidCallback onTap;
  final VoidCallback onCacheTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageCacheWidth =
        ((MediaQuery.sizeOf(context).width / 2) *
                MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(240, 720)
            .toInt();
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x2E1E2633),
      borderRadius: BorderRadius.circular(8),
      surfaceTintColor: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFFE4E7EC),
                        child: item.coverUrl.isEmpty
                            ? const Icon(
                                Icons.video_library_outlined,
                                color: Color(0xFF8C929F),
                              )
                            : Image.network(
                                item.coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: imageCacheWidth,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: Color(0xFF8C929F),
                                ),
                              ),
                      ),
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0x00000000),
                                Color(0x12000000),
                                Color(0x99000000),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 7,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.play_circle_outline_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                item.playCountLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              item.durationLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: infoHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: const Color(0xFF20232B),
                            fontWeight: FontWeight.w900,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 24,
                        child: Row(
                          children: [
                            if (item.vertical) ...[
                              const _VerticalBadge(),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                item.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF8B9098),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              height: 32,
                              child: IconButton(
                                onPressed: onCacheTap,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 32,
                                ),
                                icon: const Icon(
                                  Icons.more_vert_rounded,
                                  color: Color(0xFF9AA0AA),
                                  size: 20,
                                ),
                                tooltip: '缓存',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionMenuButton extends StatelessWidget {
  const _RegionMenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.menu_rounded, size: 22),
        color: const Color(0xFF2D3038),
        tooltip: '分区',
      ),
    );
  }
}

class _HomeCacheSurface extends StatefulWidget {
  const _HomeCacheSurface({
    required this.client,
    required this.historyStore,
    required this.bvid,
    required this.controller,
    required this.onMessage,
  });

  final BiliClient client;
  final BiliHistoryStore historyStore;
  final String bvid;
  final BiliOfflineDownloadController controller;
  final void Function(String message) onMessage;

  @override
  State<_HomeCacheSurface> createState() => _HomeCacheSurfaceState();
}

class _HomeCacheSurfaceState extends State<_HomeCacheSurface> {
  late Future<BiliVideoDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.client.fetchVideoDetail(widget.bvid);
  }

  Future<void> _reload() async {
    setState(() {
      _detailFuture = widget.client.fetchVideoDetail(widget.bvid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BiliVideoDetail>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final error = snapshot.error;
        if (error != null) {
          return _InlineErrorBanner(
            message: error.toString(),
            actionLabel: '重试',
            onPressed: _reload,
          );
        }
        final detail = snapshot.data;
        if (detail == null) {
          return _InlineErrorBanner(
            message: '缓存面板加载失败。',
            actionLabel: '重试',
            onPressed: _reload,
          );
        }
        if (detail.pages.isEmpty) {
          return const _EmptyPanel(title: '没有可缓存的分P', body: '这个视频没有可用的合集缓存项。');
        }
        return BiliCacheDownloadPanel(
          detail: detail,
          currentPage: detail.pages.first,
          selectedQualityId: null,
          codecPreference: BiliVideoCodecPreference.automatic,
          controller: widget.controller,
          onMessage: widget.onMessage,
          client: widget.client,
          historyStore: widget.historyStore,
        );
      },
    );
  }
}

class _VerticalBadge extends StatelessWidget {
  const _VerticalBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFA15F),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          '竖屏',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.isLoading, required this.hasMore});

  final bool isLoading;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 18),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: isLoading
              ? const SizedBox(
                  key: ValueKey<String>('loading'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  hasMore ? '上滑加载更多' : '没有更多了',
                  key: ValueKey<String>(hasMore ? 'more' : 'done'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8B9098),
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
