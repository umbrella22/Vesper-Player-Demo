part of 'bili_tv_home_page.dart';

class _TvMediaShelf extends StatelessWidget {
  const _TvMediaShelf({
    super.key,
    required this.title,
    required this.controller,
    required this.itemCount,
    required this.cardWidth,
    required this.itemBuilder,
    this.onDirectionalEdge,
  });

  final String title;
  final ScrollController controller;
  final int itemCount;
  final double cardWidth;
  final IndexedWidgetBuilder itemBuilder;
  final bool Function(TraversalDirection direction)? onDirectionalEdge;

  @override
  Widget build(BuildContext context) {
    final cardHeight = cardWidth / (16 / 9) + 58;
    return TvFocusGroupScope(
      group: ValueKey<String>('tv-shelf-focus-$title'),
      onDirectionalEdge: (direction) {
        if (onDirectionalEdge?.call(direction) == true) {
          return true;
        }
        if (!controller.hasClients ||
            (direction != TraversalDirection.left &&
                direction != TraversalDirection.right)) {
          return false;
        }
        final position = controller.position;
        final delta = cardWidth + 14;
        final target = switch (direction) {
          TraversalDirection.left => (position.pixels - delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
          TraversalDirection.right => (position.pixels + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
          _ => position.pixels,
        };
        if ((target - position.pixels).abs() < 1) {
          return false;
        }
        unawaited(
          controller.animateTo(
            target,
            duration: AppVisualTokens.motionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            curve: Curves.easeOutCubic,
          ),
        );
        return true;
      },
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: cardHeight + _tvGridFocusInset * 2,
                child: Overlay.wrap(
                  clipBehavior: Clip.none,
                  child: ListView.separated(
                    key: ValueKey<String>('tv-shelf-list-$title'),
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    scrollCacheExtent: ScrollCacheExtent.pixels(
                      cardWidth * 2.5,
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      _tvGridFocusInset,
                      _tvGridFocusInset,
                      34,
                      _tvGridFocusInset,
                    ),
                    itemCount: itemCount,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, index) => SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: itemBuilder(context, index),
                    ),
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

class _TvGridOverlayScope extends StatelessWidget {
  const _TvGridOverlayScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(clipBehavior: Clip.hardEdge, child: child);
  }
}

class _TvSearchSuffixIcon extends StatelessWidget {
  const _TvSearchSuffixIcon({
    required this.loading,
    required this.visible,
    required this.onClear,
  });

  final bool loading;
  final bool visible;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>('bili-tv-search-suffix'),
      width: 48,
      height: 48,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: loading
              ? const SizedBox(
                  key: ValueKey<String>('search-loading'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0x88FFFFFF),
                  ),
                )
              : visible
              ? IconButton(
                  key: const ValueKey<String>('search-clear'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0x88FFFFFF),
                    size: 20,
                  ),
                  onPressed: onClear,
                )
              : const SizedBox.shrink(key: ValueKey<String>('search-empty')),
        ),
      ),
    );
  }
}

class _TvRegionVideoGrid extends StatelessWidget {
  const _TvRegionVideoGrid({
    required this.items,
    required this.onTapItem,
    required this.onFocusItem,
    required this.onNearEnd,
  });

  final List<BiliRegionVideo> items;
  final void Function(BiliRegionVideo item) onTapItem;
  final void Function(BiliRegionVideo item, bool focused) onFocusItem;
  final VoidCallback onNearEnd;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final maxCrossAxisExtent = biliTvGridMaxCrossAxisExtentForWidth(
          constraints.crossAxisExtent,
        );
        final coverCacheWidth = biliTvCoverCacheWidth(
          tileWidth: biliTvVideoGridTileWidthForCrossAxisExtent(
            constraints.crossAxisExtent,
            maxCrossAxisExtent: maxCrossAxisExtent,
          ),
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        return SliverGrid.builder(
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCrossAxisExtent,
            mainAxisSpacing: _tvGridMainAxisSpacing,
            crossAxisSpacing: _tvGridCrossAxisSpacing,
            childAspectRatio: _tvGridChildAspectRatio,
          ),
          itemBuilder: (context, index) {
            if (index >= items.length - 8) {
              onNearEnd();
            }
            final item = items[index];
            final subtitle = item.seasonId != null
                ? item.indexLabel ?? item.followCountLabel ?? '番剧'
                : item.subtitle ?? item.followCountLabel ?? '';
            final duration = item.seasonId != null
                ? item.scoreLabel == null
                      ? '剧集'
                      : '${item.scoreLabel}分'
                : item.indexLabel ?? '';
            return _TvVideoCard(
              key: ValueKey('region_${item.id}'),
              coverUrl: item.coverUrl,
              coverCacheWidth: coverCacheWidth,
              title: item.title,
              author: subtitle,
              duration: duration,
              playCount: item.followCountLabel ?? '',
              focusArea: TvFocusArea.regionGrid,
              onFocusChange: (focused) => onFocusItem(item, focused),
              onTap: () => onTapItem(item),
            );
          },
        );
      },
    );
  }
}

class _TvRegionPill extends StatelessWidget {
  const _TvRegionPill({
    super.key,
    required this.section,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final BiliRegionSection section;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvGlassSelectable(
      autofocus: autofocus,
      selected: selected,
      scale: 1.06,
      borderRadius: AppVisualTokens.controlRadius,
      focusArea: TvFocusArea.regionCategories,
      debugLabel: 'region_${section.id}',
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      builder: (context, state) {
        final focused =
            state == TvGlassSelectableState.focused ||
            state == TvGlassSelectableState.pressed;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(section.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(
              section.name,
              style: TextStyle(
                color: focused || selected
                    ? Colors.white
                    : const Color(0xAAFFFFFF),
                fontSize: 15,
                fontWeight: focused || selected
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppVisualTokens.primaryBlue,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TvVideoCard extends StatelessWidget {
  const _TvVideoCard({
    super.key,
    required this.coverUrl,
    required this.coverCacheWidth,
    required this.title,
    required this.author,
    required this.duration,
    required this.playCount,
    required this.onTap,
    this.onFocusChange,
    this.focusArea = TvFocusArea.content,
  });

  final String coverUrl;
  final int coverCacheWidth;
  final String title;
  final String author;
  final String duration;
  final String playCount;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;
  final TvFocusArea focusArea;

  @override
  Widget build(BuildContext context) {
    return TvFocusableSurface(
      scale: 1.07,
      focusPadding: _tvCardFocusPadding,
      useOverlayLift: true,
      focusArea: focusArea,
      debugLabel: 'video_$title',
      onFocusChange: onFocusChange,
      onTap: onTap,
      builder: (context, focused) => LayoutBuilder(
        builder: (context, constraints) {
          final boundedHeight = constraints.hasBoundedHeight;
          final tight = boundedHeight && constraints.maxHeight < 116;
          final condensed = boundedHeight && constraints.maxHeight < 136;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFF1A1A24),
                        child: coverUrl.isEmpty
                            ? const Icon(
                                Icons.video_library_outlined,
                                color: Color(0x55FFFFFF),
                                size: 40,
                              )
                            : Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: coverCacheWidth,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: Color(0xFF1A1A24)),
                              ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 6,
                        child: Text(
                          playCount,
                          style: const TextStyle(
                            color: Color(0xDDFFFFFF),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            duration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: condensed ? 4 : 5),
              Text(
                title,
                maxLines: tight ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: focused ? Colors.white : const Color(0xEEFFFFFF),
                  fontSize: condensed ? 12 : 12.2,
                  fontWeight: focused ? FontWeight.w800 : FontWeight.w600,
                  height: 1.17,
                ),
              ),
              if (!condensed) ...[
                const SizedBox(height: 2),
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x66FFFFFF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TvSearchResultCard extends StatelessWidget {
  const _TvSearchResultCard({
    required this.coverUrl,
    required this.coverCacheWidth,
    required this.title,
    required this.author,
    required this.duration,
    required this.playCount,
    required this.onTap,
    this.onFocusChange,
  });

  final String coverUrl;
  final int coverCacheWidth;
  final String title;
  final String author;
  final String duration;
  final String playCount;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    return _TvVideoCard(
      coverUrl: coverUrl,
      coverCacheWidth: coverCacheWidth,
      title: title,
      author: author,
      duration: duration,
      playCount: playCount,
      onFocusChange: onFocusChange,
      onTap: onTap,
    );
  }
}

class _TvHistoryCard extends StatelessWidget {
  const _TvHistoryCard({
    super.key,
    required this.coverUrl,
    required this.coverCacheWidth,
    required this.title,
    required this.subtitle,
    required this.ownerName,
    required this.progress,
    required this.onTap,
    this.autofocus = false,
    this.onFocusChange,
  });

  final String coverUrl;
  final int coverCacheWidth;
  final String title;
  final String subtitle;
  final String ownerName;
  final double progress;
  final VoidCallback onTap;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    return TvFocusableSurface(
      autofocus: autofocus,
      scale: 1.07,
      focusPadding: _tvCardFocusPadding,
      useOverlayLift: true,
      focusArea: TvFocusArea.content,
      debugLabel: 'history_$title',
      onFocusChange: onFocusChange,
      onTap: onTap,
      builder: (context, focused) => LayoutBuilder(
        builder: (context, constraints) {
          final boundedHeight = constraints.hasBoundedHeight;
          final tight = boundedHeight && constraints.maxHeight < 116;
          final condensed = boundedHeight && constraints.maxHeight < 136;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFF1A1A24),
                        child: coverUrl.isEmpty
                            ? const Icon(
                                Icons.video_library_outlined,
                                color: Color(0x55FFFFFF),
                                size: 40,
                              )
                            : Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: coverCacheWidth,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: Color(0xFF1A1A24)),
                              ),
                      ),
                      if (progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            backgroundColor: const Color(0x33000000),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppVisualTokens.primaryBlue,
                            ),
                            minHeight: 3,
                          ),
                        ),
                      Positioned(
                        right: 8,
                        bottom: progress > 0 ? 10 : 7,
                        child: Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: condensed ? 4 : 5),
              Text(
                title,
                maxLines: tight ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: focused ? Colors.white : const Color(0xEEFFFFFF),
                  fontSize: condensed ? 12 : 12.2,
                  fontWeight: focused ? FontWeight.w800 : FontWeight.w600,
                  height: 1.17,
                ),
              ),
              if (!condensed) ...[
                const SizedBox(height: 2),
                Text(
                  '$ownerName · $subtitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x66FFFFFF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
