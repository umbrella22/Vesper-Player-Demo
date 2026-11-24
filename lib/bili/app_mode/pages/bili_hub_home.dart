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
        final coverCacheWidth = biliHomeCoverCacheWidth(
          tileWidth: tileWidth,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        final titleStyle = AppTypography.videoCardTitle(
          context,
          cardWidth: tileWidth,
        );

        final textScaler = MediaQuery.textScalerOf(context);
        final scaledTitleHeight =
            (2 * textScaler.scale(titleStyle.fontSize!) * titleStyle.height!)
                .ceilToDouble();
        final authorFontSize =
            Theme.of(context).textTheme.bodySmall?.fontSize ?? 12.0;
        final scaledAuthorHeight = math.max(
          18.0,
          (textScaler.scale(authorFontSize) * 1.35).ceilToDouble(),
        );
        final infoHeight = math.max(
          kMinInteractiveDimension,
          7 + scaledTitleHeight + 5 + scaledAuthorHeight + 7,
        );
        final tileHeight = tileWidth * 9 / 16 + infoHeight;
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
                titleStyle: titleStyle,
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
    required this.titleStyle,
    required this.onTap,
    required this.onCacheTap,
  });

  final _HomeVideoItem item;
  final int coverCacheWidth;
  final TextStyle titleStyle;
  final VoidCallback onTap;
  final VoidCallback onCacheTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return BiliVideoGridCard(
      onTap: onTap,
      cover: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: visualTheme.surfaceRaised,
              child: item.coverUrl.isEmpty
                  ? Icon(AppIcons.filmLine, color: visualTheme.textTertiary)
                  : AppNetworkImage(
                      item.coverUrl,
                      fit: BoxFit.cover,
                      cacheWidth: coverCacheWidth,
                      errorBuilder: (_, _, _) => Icon(
                        AppIcons.imageLine,
                        color: visualTheme.textTertiary,
                      ),
                    ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: visualTheme.imageOutline),
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
                    AppIcons.playCircleLine,
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
      details: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 7, 0, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle.copyWith(color: visualTheme.textPrimary),
                  ),
                  const Spacer(),
                  Row(
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
                            fontWeight: FontWeight.w400,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.bottomEnd,
            child: SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: IconButton(
                onPressed: onCacheTap,
                tooltip: '缓存',
                padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
                alignment: AlignmentDirectional.bottomEnd,
                icon: Icon(
                  AppIcons.moreFill,
                  color: visualTheme.textTertiary,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionMenuButton extends StatelessWidget {
  const _RegionMenuButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return AppPressScale(
      child: SizedBox.square(
        dimension: kMinInteractiveDimension,
        child: IconButton(
          onPressed: onTap,
          padding: EdgeInsets.zero,
          icon: const Icon(AppIcons.listUnordered, size: 22),
          color: visualTheme.textPrimary,
          tooltip: '分区',
        ),
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
          return SingleChildScrollView(
            child: _InlineErrorBanner(
              message: biliErrorMessage(error),
              actionLabel: '重试',
              onPressed: _reload,
            ),
          );
        }
        final detail = snapshot.data;
        if (detail == null) {
          return SingleChildScrollView(
            child: _InlineErrorBanner(
              message: '缓存面板加载失败。',
              actionLabel: '重试',
              onPressed: _reload,
            ),
          );
        }
        if (detail.pages.isEmpty) {
          return const SingleChildScrollView(
            child: _EmptyPanel(title: '没有可缓存的分P', body: '这个视频没有可用的合集缓存项。'),
          );
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
        color: const Color(0xFFBF5200),
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
