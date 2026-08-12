part of 'bili_playback_content_surfaces.dart';

class EpisodePreviewList extends StatelessWidget {
  const EpisodePreviewList({
    super.key,
    required this.pages,
    required this.selectedPage,
    required this.coverUrl,
    required this.onTap,
    this.isPgc = false,
  });

  final List<BiliVideoPageEntry> pages;
  final BiliVideoPageEntry selectedPage;
  final String coverUrl;
  final Future<void> Function(BiliVideoPageEntry) onTap;
  final bool isPgc;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        for (final page in pages) ...[
          _EpisodePreviewTile(
            page: page,
            selected: page.cid == selectedPage.cid,
            coverUrl: coverUrl,
            isPgc: isPgc,
            onTap: () => unawaited(onTap(page)),
          ),
          if (page != pages.last) const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _EpisodePreviewTile extends StatelessWidget {
  const _EpisodePreviewTile({
    required this.page,
    required this.selected,
    required this.coverUrl,
    required this.isPgc,
    required this.onTap,
  });

  final BiliVideoPageEntry page;
  final bool selected;
  final String coverUrl;
  final bool isPgc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final titleColor = selected
        ? AppVisualTokens.primaryBlue
        : visualTheme.textPrimary;
    final label = isPgc ? '第 ${page.pageNumber} 话' : 'P${page.pageNumber}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 174,
                  height: 104,
                  child: (page.coverUrl ?? coverUrl).isEmpty
                      ? ColoredBox(color: visualTheme.surfaceRaised)
                      : Image.network(
                          page.coverUrl ?? coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: visualTheme.surfaceRaised),
                        ),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      page.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      biliFormatDurationSeconds(page.durationSeconds),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: visualTheme.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelatedVideoSliverList extends StatelessWidget {
  const _RelatedVideoSliverList({
    required this.items,
    required this.loading,
    required this.errorMessage,
    required this.openingBvid,
    required this.onTap,
  });

  final List<BiliFeedVideo> items;
  final bool loading;
  final String? errorMessage;
  final String? openingBvid;
  final ValueChanged<BiliFeedVideo> onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    if (items.isEmpty && loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      );
    }
    if (items.isEmpty && errorMessage != null) {
      return SliverToBoxAdapter(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              visualTheme.destructive.withValues(alpha: 0.12),
              visualTheme.surfaceRaised,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: visualTheme.destructive,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Text(
          '暂无相关视频',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: visualTheme.textTertiary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final relatedChildCount = items.length * 2 - 1;
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index >= relatedChildCount) {
          return const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }
        if (index.isOdd) {
          return Divider(
            height: 18,
            thickness: 0.7,
            color: visualTheme.divider,
          );
        }
        final item = items[index ~/ 2];
        return _RelatedVideoTile(
          item: item,
          opening: openingBvid == item.bvid,
          onTap: () => onTap(item),
        );
      }, childCount: relatedChildCount + (loading ? 1 : 0)),
    );
  }
}

class _RelatedVideoTile extends StatelessWidget {
  const _RelatedVideoTile({
    required this.item,
    required this.opening,
    required this.onTap,
  });

  final BiliFeedVideo item;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverWidth = constraints.maxWidth < 390 ? 132.0 : 150.0;
        final coverHeight = (coverWidth * 9 / 16).clamp(86.0, 96.0);
        final cacheWidth = (coverWidth * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(220, 560)
            .toInt();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: opening ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: SizedBox(
                      width: coverWidth,
                      height: coverHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: visualTheme.surfaceRaised,
                            ),
                            child: item.coverUrl.isEmpty
                                ? Icon(
                                    Icons.video_library_outlined,
                                    color: visualTheme.textTertiary,
                                  )
                                : Image.network(
                                    item.coverUrl,
                                    fit: BoxFit.cover,
                                    cacheWidth: cacheWidth,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.broken_image_outlined,
                                      color: visualTheme.textTertiary,
                                    ),
                                  ),
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.fromBorderSide(
                                BorderSide(color: visualTheme.imageOutline),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 5,
                            bottom: 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xB3000000),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                child: Text(
                                  item.durationLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    height: 1.05,
                                    fontFeatures: [
                                      ui.FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (opening)
                            const ColoredBox(
                              color: Color(0x66000000),
                              child: Center(
                                child: SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: coverHeight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: visualTheme.textPrimary,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: visualTheme.textTertiary,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Icon(
                                Icons.play_circle_outline_rounded,
                                size: 15,
                                color: visualTheme.textTertiary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  item.playCountLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: visualTheme.textTertiary,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      ui.FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.subtitles_outlined,
                                size: 15,
                                color: visualTheme.textTertiary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  item.danmakuCountLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: visualTheme.textTertiary,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      ui.FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
      },
    );
  }
}
