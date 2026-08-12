part of 'bili_playback_content_surfaces.dart';

class _IntroSurface extends StatefulWidget {
  const _IntroSurface({required this.surfaces});

  final BiliPlaybackContentSurfaces surfaces;

  @override
  State<_IntroSurface> createState() => _IntroSurfaceState();
}

class _IntroSurfaceState extends State<_IntroSurface> {
  bool _introExpanded = false;
  String? _openingRelatedBvid;

  @override
  Widget build(BuildContext context) {
    // VM 信号读取必须发生在 SignalBuilder 的 builder 调用栈内才会被追踪，
    // 因此放在 build 内部的 leaf SignalBuilder 里。
    return SignalBuilder(builder: (context) => _buildIntroBody(context));
  }

  Widget _buildIntroBody(BuildContext context) {
    final s = widget.surfaces;
    final vm = s.viewModel;
    final detail = s.detail;
    final isPgc = detail.ownerMid <= 0 && detail.ownerName == '番剧';
    final pages = detail.pages;
    final selectedPage = vm.selectedPage;

    final topChildren = <Widget>[
      if (!isPgc) ...[
        _OwnerSummary(
          name: detail.ownerName,
          avatarUrl: detail.ownerAvatarUrl,
          subtitle: vm.ownerSubtitle,
          isFollowing: vm.engagement?.isFollowingOwner ?? false,
          isBusy: vm.pendingEngagementAction == BiliEngagementAction.follow,
          onFollow: () => _runAction(context, vm.toggleFollow),
        ),
        const SizedBox(height: 18),
      ],
      _PlaybackIntroSummary(
        title: detail.title,
        description: detail.description.trim(),
        expanded: _introExpanded,
        onToggleExpanded: () {
          setState(() {
            _introExpanded = !_introExpanded;
          });
        },
        metadata: _PlaybackMetaLine(
          entries: [
            if (detail.playCountLabel != '--')
              _PlaybackMetaEntry(
                icon: Icons.play_circle_outline_rounded,
                label: '${detail.playCountLabel}播放',
              ),
            if (detail.danmakuCountLabel != '--')
              _PlaybackMetaEntry(
                icon: Icons.subtitles_outlined,
                label: detail.danmakuCountLabel,
              ),
            if (detail.publishedAtLabel != null)
              _PlaybackMetaEntry(
                icon: Icons.schedule_rounded,
                label: detail.publishedAtLabel!,
              ),
            _PlaybackMetaEntry(
              icon: Icons.confirmation_number_outlined,
              label: selectedPage.bvid ?? detail.bvid,
            ),
          ],
        ),
      ),
      SignalBuilder(
        builder: (context) {
          final capability = vm.buildEngagementCapability();
          if (capability.actions.isEmpty ||
              capability.placement != MediaEngagementPlacement.intro) {
            return const SizedBox.shrink();
          }
          return Padding(
            key: const ValueKey<String>('bili-intro-engagement-bar'),
            padding: const EdgeInsets.only(top: 22),
            child: MediaEngagementBar(
              actions: capability.actions,
              onMessage: (message) => _showSnackBar(context, message),
              layout: MediaEngagementBarLayout.compactIconRow,
            ),
          );
        },
      ),
      if (pages.length > 1) ...[
        const SizedBox(height: 18),
        _PageSelectionButton(
          title: isPgc
              ? '剧集 · 共 ${pages.length} 话/集'
              : '合集 · 共 ${pages.length} 个分 P',
          selectedLabel: isPgc
              ? '第 ${selectedPage.pageNumber} 话 · ${selectedPage.title}'
              : 'P${selectedPage.pageNumber} · ${selectedPage.title}',
          coverUrl: selectedPage.coverUrl ?? detail.coverUrl,
          durationLabel: biliFormatDurationSeconds(
            selectedPage.durationSeconds,
          ),
          onTap: () => unawaited(s._showPageSelectionSheet(context)),
        ),
      ],
      const SizedBox(height: 18),
      _PlaybackSectionHeader(
        title: '相关推荐',
        action: vm.relatedVideosError == null
            ? null
            : TextButton.icon(
                onPressed: () => unawaited(vm.loadRelatedVideos()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(58, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: AppVisualTokens.primaryBlue,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
      ),
      const SizedBox(height: 12),
    ];

    return NotificationListener<ScrollNotification>(
      onNotification: s.host.onContentScroll,
      child: CustomScrollView(
        key: const PageStorageKey<String>('playback-related'),
        controller: s.host.relatedScrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverList(delegate: SliverChildListDelegate(topChildren)),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 18),
            sliver: _RelatedVideoSliverList(
              items: vm.relatedVideos,
              loading: vm.relatedVideosLoading,
              errorMessage: vm.relatedVideosError,
              openingBvid: _openingRelatedBvid,
              onTap: (video) {
                setState(() {
                  _openingRelatedBvid = video.bvid;
                });
                unawaited(
                  s._openRelatedVideo(context, video).whenComplete(() {
                    if (mounted) {
                      setState(() {
                        _openingRelatedBvid = null;
                      });
                    }
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DanmakuEntryPill extends StatelessWidget {
  const DanmakuEntryPill({super.key, required this.danmakuCountLabel});

  final String danmakuCountLabel;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20, maxWidth: 140),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visualTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: visualTheme.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  danmakuCountLabel == '--' ? '弹幕' : '弹幕 $danmakuCountLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: visualTheme.textTertiary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 14,
                color: visualTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _PlaybackMetaEntry {
  const _PlaybackMetaEntry({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _PlaybackMetaLine extends StatelessWidget {
  const _PlaybackMetaLine({required this.entries});

  final List<_PlaybackMetaEntry> entries;

  @override
  Widget build(BuildContext context) {
    final visibleEntries = entries
        .where((entry) => entry.label.trim().isNotEmpty && entry.label != '--')
        .toList(growable: false);
    return Wrap(
      spacing: 10,
      runSpacing: 7,
      children: [
        for (final entry in visibleEntries)
          _PlaybackMetaChip(icon: entry.icon, label: entry.label),
      ],
    );
  }
}

class _PlaybackMetaChip extends StatelessWidget {
  const _PlaybackMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: visualTheme.textTertiary),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: visualTheme.textTertiary,
            fontWeight: FontWeight.w700,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PlaybackIntroSummary extends StatelessWidget {
  const _PlaybackIntroSummary({
    required this.title,
    required this.description,
    required this.expanded,
    required this.onToggleExpanded,
    required this.metadata,
  });

  final String title;
  final String description;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final Widget metadata;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      color: visualTheme.textPrimary,
      fontWeight: FontWeight.w900,
      height: 1.18,
    );
    final descriptionStyle = theme.textTheme.bodyMedium?.copyWith(
      color: visualTheme.textSecondary,
      height: 1.62,
      fontWeight: FontWeight.w500,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final locale = Localizations.maybeLocaleOf(context);
        final descriptionPainter = TextPainter(
          text: TextSpan(text: description, style: descriptionStyle),
          maxLines: 3,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        )..layout(maxWidth: constraints.maxWidth);
        final showsExpandButton =
            description.isNotEmpty && descriptionPainter.didExceedMaxLines;
        descriptionPainter.dispose();
        final effectiveExpanded = showsExpandButton && expanded;
        final titleLinePainter = TextPainter(
          text: TextSpan(text: 'M', style: titleStyle),
          maxLines: 1,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        )..layout();
        final titleFirstLineHeight = titleLinePainter.preferredLineHeight;
        titleLinePainter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey<String>('playback-intro-title'),
                    maxLines: effectiveExpanded ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                if (showsExpandButton)
                  _IntroExpandButton(
                    key: const ValueKey<String>('playback-intro-expand'),
                    expanded: effectiveExpanded,
                    firstLineHeight: titleFirstLineHeight,
                    onTap: onToggleExpanded,
                  ),
              ],
            ),
            const SizedBox(height: 9),
            metadata,
            if (description.isNotEmpty) ...[
              const SizedBox(height: 13),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Text(
                  description,
                  key: const ValueKey<String>('playback-intro-description'),
                  maxLines: showsExpandButton && !effectiveExpanded ? 3 : null,
                  overflow: showsExpandButton && !effectiveExpanded
                      ? TextOverflow.ellipsis
                      : TextOverflow.visible,
                  style: descriptionStyle,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _IntroExpandButton extends StatelessWidget {
  const _IntroExpandButton({
    super.key,
    required this.expanded,
    required this.firstLineHeight,
    required this.onTap,
  });

  final bool expanded;
  final double firstLineHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Transform.translate(
      offset: Offset(0, (firstLineHeight - 40) / 2),
      child: IconButton(
        onPressed: onTap,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        alignment: Alignment.center,
        icon: AnimatedRotation(
          turns: expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: visualTheme.textTertiary,
            size: 28,
          ),
        ),
        tooltip: expanded ? '收起简介' : '展开简介',
      ),
    );
  }
}

class _PlaybackSectionHeader extends StatelessWidget {
  const _PlaybackSectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
        ),
        ?action,
      ],
    );
  }
}

class _PageSelectionButton extends StatelessWidget {
  const _PageSelectionButton({
    required this.title,
    required this.selectedLabel,
    required this.coverUrl,
    required this.durationLabel,
    required this.onTap,
  });

  final String title;
  final String selectedLabel;
  final String coverUrl;
  final String durationLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final cacheWidth = (96 * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(160, 360)
        .toInt();
    return Material(
      color: visualTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 96,
                  height: 54,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: visualTheme.surfaceMuted,
                        ),
                        child: coverUrl.isEmpty
                            ? Icon(
                                Icons.video_library_outlined,
                                color: visualTheme.textTertiary,
                              )
                            : Image.network(
                                coverUrl,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: visualTheme.textTertiary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      selectedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: visualTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      durationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: visualTheme.textTertiary,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 28,
                color: visualTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerSummary extends StatelessWidget {
  const _OwnerSummary({
    required this.name,
    required this.avatarUrl,
    required this.subtitle,
    required this.isFollowing,
    required this.isBusy,
    required this.onFollow,
  });

  final String name;
  final String avatarUrl;
  final String subtitle;
  final bool isFollowing;
  final bool isBusy;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final imageProvider = avatarUrl.isEmpty
        ? null
        : ResizeImage.resizeIfNeeded(96, 96, NetworkImage(avatarUrl));
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppVisualTokens.primaryBlue,
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
                  name.isEmpty ? 'UP' : name.characters.first,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: visualTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: visualTheme.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: isBusy ? null : onFollow,
          style: FilledButton.styleFrom(
            minimumSize: const Size(78, 34),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: isBusy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text(isFollowing ? '已关注' : '关注'),
                  ],
                )
              : Text(isFollowing ? '已关注' : '关注'),
        ),
      ],
    );
  }
}
