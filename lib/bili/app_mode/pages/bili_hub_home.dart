part of 'bili_hub_page.dart';

@visibleForTesting
int biliHomeGridCrossAxisCountForWidth(double crossAxisExtent) {
  return (crossAxisExtent / 220).floor().clamp(2, 5).toInt();
}

@visibleForTesting
int biliHomeCoverCacheWidth({
  required double tileWidth,
  required double devicePixelRatio,
}) {
  assert(tileWidth > 0);
  assert(devicePixelRatio > 0);
  return (tileWidth * devicePixelRatio).ceil().clamp(160, 720).toInt();
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
    final visualTheme = AppVisualTheme.of(context);
    return Row(
      children: [
        _AvatarButton(
          name: profile.name,
          avatarUrl: profile.avatarUrl,
          onTap: onAccountTap,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              GlassSearchBar(
                controller: controller,
                placeholder: '搜索视频、BV 号或链接',
                onChanged: (value) {
                  onChanged();
                  if (value.trim().isEmpty && onClear != null) {
                    onClear!();
                  }
                },
                onSubmitted: (_) => onSubmit(),
                height: 36,
                quality: GlassQuality.standard,
                textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: visualTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                placeholderStyle: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(
                      color: visualTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                searchIconColor: visualTheme.textSecondary,
                clearIconColor: visualTheme.textSecondary,
              ),
              if (isSearching)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        _RegionMenuButton(onTap: onRegionTap),
      ],
    );
  }
}

class _HomeVideoGrid extends StatelessWidget {
  const _HomeVideoGrid({
    required this.itemCount,
    required this.itemAt,
    required this.onTap,
    required this.onCacheTap,
  });

  final int itemCount;
  final _HomeVideoItem Function(int index) itemAt;
  final ValueChanged<_HomeVideoItem> onTap;
  final ValueChanged<_HomeVideoItem> onCacheTap;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) {
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
        final coverCacheWidth = biliHomeCoverCacheWidth(
          tileWidth: tileWidth,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            10,
            horizontalPadding,
            18,
          ),
          sliver: SliverGrid.builder(
            itemCount: itemCount,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: crossAxisSpacing,
              childAspectRatio: tileWidth / tileHeight,
            ),
            itemBuilder: (context, index) {
              final item = itemAt(index);
              return _HomeVideoCard(
                key: ValueKey<String>('${item.bvid}-$index'),
                item: item,
                coverCacheWidth: coverCacheWidth,
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
    super.key,
    required this.item,
    required this.coverCacheWidth,
    required this.onTap,
    required this.onCacheTap,
  });

  static const double infoHeight = 88;

  final _HomeVideoItem item;
  final int coverCacheWidth;
  final VoidCallback onTap;
  final VoidCallback onCacheTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: visualTheme.surface,
      elevation: Theme.of(context).brightness == Brightness.dark ? 0 : 1,
      shadowColor: visualTheme.shadow,
      borderRadius: BorderRadius.circular(8),
      surfaceTintColor: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: visualTheme.surface,
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
                        color: visualTheme.surfaceRaised,
                        child: item.coverUrl.isEmpty
                            ? Icon(
                                Icons.video_library_outlined,
                                color: visualTheme.textTertiary,
                              )
                            : Image.network(
                                item.coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: coverCacheWidth,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.broken_image_outlined,
                                  color: visualTheme.textTertiary,
                                ),
                              ),
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
                            color: visualTheme.textPrimary,
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
                                  color: visualTheme.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: AppVisualTokens.minimumTapTarget,
                              height: AppVisualTokens.minimumTapTarget,
                              child: IconButton(
                                onPressed: onCacheTap,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: AppVisualTokens.minimumTapTarget,
                                  minHeight: AppVisualTokens.minimumTapTarget,
                                ),
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: visualTheme.textTertiary,
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
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox.square(
      dimension: AppVisualTokens.minimumTapTarget,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.menu_rounded, size: 22),
        color: visualTheme.textPrimary,
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
            message: biliErrorMessage(error),
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
    final visualTheme = AppVisualTheme.of(context);
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
                    color: visualTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
