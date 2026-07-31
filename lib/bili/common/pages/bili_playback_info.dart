part of 'bili_playback_page.dart';

class _DanmakuEntryPill extends StatelessWidget {
  const _DanmakuEntryPill({required this.danmakuCountLabel});

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

class _ActionStatRow extends StatelessWidget {
  const _ActionStatRow({
    required this.likeCountLabel,
    required this.coinCountLabel,
    required this.favoriteCountLabel,
    required this.shareCountLabel,
    required this.liked,
    required this.sentCoinCount,
    required this.favorited,
    required this.loading,
    required this.pendingAction,
    required this.onLike,
    required this.onCoin,
    required this.onFavorite,
    required this.onShare,
  });

  final String likeCountLabel;
  final String coinCountLabel;
  final String favoriteCountLabel;
  final String shareCountLabel;
  final bool liked;
  final int sentCoinCount;
  final bool favorited;
  final bool loading;
  final BiliEngagementAction? pendingAction;
  final VoidCallback onLike;
  final VoidCallback onCoin;
  final VoidCallback onFavorite;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final disabled = loading || pendingAction != null;
    return Row(
      children: [
        Expanded(
          child: _ActionStatButton(
            icon: liked ? Icons.thumb_up_rounded : Icons.thumb_up_alt_outlined,
            label: '点赞',
            value: likeCountLabel,
            selected: liked,
            busy: pendingAction == BiliEngagementAction.like,
            onTap: disabled ? null : onLike,
          ),
        ),
        Expanded(
          child: _ActionStatButton(
            icon: Icons.monetization_on_outlined,
            label: '硬币',
            value: coinCountLabel,
            selected: sentCoinCount > 0,
            busy: pendingAction == BiliEngagementAction.coin,
            onTap: disabled ? null : onCoin,
          ),
        ),
        Expanded(
          child: _ActionStatButton(
            icon: favorited ? Icons.star_rounded : Icons.star_border_rounded,
            label: '收藏',
            value: favoriteCountLabel,
            selected: favorited,
            busy: pendingAction == BiliEngagementAction.favorite,
            onTap: disabled ? null : onFavorite,
          ),
        ),
        Expanded(
          child: _ActionStatButton(
            icon: Icons.ios_share_rounded,
            label: '分享',
            value: shareCountLabel,
            selected: false,
            busy: pendingAction == BiliEngagementAction.share,
            onTap: disabled ? null : onShare,
          ),
        ),
      ],
    );
  }
}

class _WatchLaterButton extends StatelessWidget {
  const _WatchLaterButton({
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final foreground = selected
        ? AppVisualTokens.primaryBlue
        : visualTheme.textSecondary;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        icon: busy
            ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Icon(
                selected
                    ? Icons.watch_later_rounded
                    : Icons.watch_later_outlined,
              ),
        label: Text(selected ? '移出稍后再看' : '加入稍后再看'),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size.fromHeight(42),
          side: BorderSide(
            color: selected
                ? AppVisualTokens.primaryBlue40
                : visualTheme.divider,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _ActionStatButton extends StatelessWidget {
  const _ActionStatButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    this.busy = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final foreground = selected
        ? AppVisualTokens.primaryBlue
        : visualTheme.textSecondary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: busy ? null : onTap,
        child: SizedBox(
          height: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, size: 25, color: foreground),
              const SizedBox(height: 5),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: visualTheme.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: visualTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: visualTheme.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
