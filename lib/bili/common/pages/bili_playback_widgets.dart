part of 'bili_playback_page.dart';

class _TuningOptionButton extends StatelessWidget {
  const _TuningOptionButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? selected
              ? const Color(0xFFFB7299)
              : const Color(0xFF162033)
        : const Color(0xFF9AA3B2);
    return Material(
      color: selected ? const Color(0xFFFFEDF3) : const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              fontSize: 14,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

class _CacheEntryButton extends StatelessWidget {
  const _CacheEntryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              const Icon(
                Icons.download_for_offline_outlined,
                size: 20,
                color: Color(0xFFFB7299),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '缓存',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF162033),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: Color(0xFF9AA3B2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        color: const Color(0xFF162033),
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _PlaybackContextTabs extends StatelessWidget {
  const _PlaybackContextTabs({
    required this.controller,
    required this.replyCountLabel,
    required this.danmakuCountLabel,
  });

  final TabController controller;
  final String replyCountLabel;
  final String danmakuCountLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8EAF0))),
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: TabBar(
                controller: controller,
                isScrollable: true,
                dividerColor: Colors.transparent,
                indicatorColor: const Color(0xFFFB7299),
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 3,
                labelColor: const Color(0xFFFB7299),
                unselectedLabelColor: const Color(0xFF777D88),
                labelPadding: const EdgeInsets.only(right: 28),
                splashBorderRadius: BorderRadius.circular(8),
                labelStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
                unselectedLabelStyle: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                tabs: [
                  _PlaybackTab(label: '简介'),
                  _PlaybackTab(label: '评论 $replyCountLabel'),
                ],
              ),
            ),
            _DanmakuEntryPill(danmakuCountLabel: danmakuCountLabel),
          ],
        ),
      ),
    );
  }
}

class _PlaybackTab extends StatelessWidget {
  const _PlaybackTab({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _CollapsedPlaybackBar extends StatelessWidget {
  const _CollapsedPlaybackBar({
    required this.title,
    required this.isPlaying,
    required this.onBack,
    required this.onHome,
    required this.onPlayPause,
    required this.onMore,
  });

  final String title;
  final bool isPlaying;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onPlayPause;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFB5C99),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _CollapsedBarIcon(icon: Icons.arrow_back_rounded, onTap: onBack),
              _CollapsedBarIcon(icon: Icons.home_outlined, onTap: onHome),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onPlayPause,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isPlaying ? '正在播放' : '继续播放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _CollapsedBarIcon(icon: Icons.more_vert_rounded, onTap: onMore),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsedBarIcon extends StatelessWidget {
  const _CollapsedBarIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
      icon: Icon(icon, color: Colors.white, size: 30),
    );
  }
}

class _CommentThreadList extends StatelessWidget {
  const _CommentThreadList({
    required this.comments,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.errorMessage,
    required this.onReload,
    required this.onLoadMore,
    required this.onSeekToTime,
    required this.onOpenReplies,
  });

  final List<BiliVideoComment> comments;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? errorMessage;
  final Future<void> Function() onReload;
  final Future<void> Function() onLoadMore;
  final ValueChanged<int> onSeekToTime;
  final ValueChanged<BiliVideoComment> onOpenReplies;

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty && loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (comments.isEmpty && errorMessage != null) {
      return _PlaybackInlineError(
        title: '评论加载失败',
        message: errorMessage!,
        actionLabel: '重新加载',
        onPressed: onReload,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '热门评论',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF171923),
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
            ),
            const Icon(Icons.sort_rounded, size: 20, color: Color(0xFF8C929F)),
            const SizedBox(width: 5),
            Text(
              '按热度',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF8C929F),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              '暂无评论',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF8C929F),
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else ...[
          for (final comment in comments) ...[
            _CommentTile(
              comment: comment,
              onSeekToTime: onSeekToTime,
              onOpenReplies: onOpenReplies,
            ),
            if (comment != comments.last)
              const Divider(
                height: 28,
                thickness: 0.7,
                color: Color(0xFFE8EAF0),
              ),
          ],
          if (loadingMore) ...[
            const SizedBox(height: 14),
            const Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ] else if (errorMessage != null) ...[
            const SizedBox(height: 14),
            Center(
              child: TextButton.icon(
                onPressed: () => unawaited(onLoadMore()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('加载更多失败，点此重试'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFB7299),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ] else if (!hasMore) ...[
            const SizedBox(height: 18),
            Center(
              child: Text(
                '没有更多评论了',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFA0A6B2),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onSeekToTime,
    required this.onOpenReplies,
    this.showRepliesPreview = true,
  });

  final BiliVideoComment comment;
  final ValueChanged<int> onSeekToTime;
  final ValueChanged<BiliVideoComment> onOpenReplies;
  final bool showRepliesPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageProvider = comment.authorAvatarUrl.isEmpty
        ? null
        : ResizeImage.resizeIfNeeded(
            96,
            96,
            NetworkImage(comment.authorAvatarUrl),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFFE8F4FA),
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
                  comment.authorName.isEmpty
                      ? '?'
                      : comment.authorName.characters.first,
                  style: TextStyle(
                    color: const Color(0xFF178DB8),
                    fontSize: 15,
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
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    comment.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF404756),
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                    ),
                  ),
                  if (comment.authorLevelLabel != null)
                    _CommentLevelBadge(label: comment.authorLevelLabel!),
                ],
              ),
              if (comment.createdAtLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  comment.createdAtLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA0A6B2),
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _CommentMessageText(
                message: comment.message,
                timeLinks: comment.timeLinks,
                onSeekToTime: onSeekToTime,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF171923),
                  fontWeight: FontWeight.w800,
                  height: 1.5,
                ),
              ),
              _CommentExtraTimeLinks(
                links: comment.timeLinks,
                onSeekToTime: onSeekToTime,
              ),
              if (comment.pictures.isNotEmpty) ...[
                const SizedBox(height: 12),
                _CommentPictureGrid(pictures: comment.pictures),
              ],
              const SizedBox(height: 10),
              _CommentActionRow(comment: comment),
              if (showRepliesPreview && comment.replies.isNotEmpty) ...[
                const SizedBox(height: 12),
                _CommentReplyPreview(
                  comment: comment,
                  onSeekToTime: onSeekToTime,
                  onOpenReplies: () => onOpenReplies(comment),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentLevelBadge extends StatelessWidget {
  const _CommentLevelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFEAF0),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFFB7299),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            height: 1.15,
            fontFeatures: [ui.FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _CommentMessageText extends StatefulWidget {
  const _CommentMessageText({
    required this.message,
    required this.timeLinks,
    required this.onSeekToTime,
    this.style,
  });

  final String message;
  final List<BiliCommentTimeLink> timeLinks;
  final ValueChanged<int> onSeekToTime;
  final TextStyle? style;

  @override
  State<_CommentMessageText> createState() => _CommentMessageTextState();
}

class _CommentMessageTextState extends State<_CommentMessageText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _syncRecognizers();
  }

  @override
  void didUpdateWidget(_CommentMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeLinks != widget.timeLinks ||
        oldWidget.onSeekToTime != widget.onSeekToTime) {
      _syncRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _syncRecognizers() {
    _disposeRecognizers();
    for (final link in widget.timeLinks.where(_hasInlineRange)) {
      _recognizers.add(
        TapGestureRecognizer()..onTap = () => widget.onSeekToTime(link.seconds),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style =
        widget.style ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF171923),
          height: 1.5,
        );
    final linkStyle = style?.copyWith(
      color: const Color(0xFF178DB8),
      fontWeight: FontWeight.w900,
      decoration: TextDecoration.none,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    var recognizerIndex = 0;
    for (final link in widget.timeLinks.where(_hasInlineRange)) {
      final start = link.start!;
      final end = link.end!;
      if (start < cursor || start > widget.message.length) {
        continue;
      }
      if (cursor < start) {
        spans.add(TextSpan(text: widget.message.substring(cursor, start)));
      }
      spans.add(
        TextSpan(
          text: widget.message.substring(start, end),
          style: linkStyle,
          recognizer: _recognizers[recognizerIndex],
        ),
      );
      recognizerIndex += 1;
      cursor = end;
    }
    if (cursor < widget.message.length) {
      spans.add(TextSpan(text: widget.message.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
      textScaler: MediaQuery.textScalerOf(context),
    );
  }
}

bool _hasInlineRange(BiliCommentTimeLink link) =>
    link.start != null && link.end != null && link.start! < link.end!;

class _CommentExtraTimeLinks extends StatelessWidget {
  const _CommentExtraTimeLinks({
    required this.links,
    required this.onSeekToTime,
  });

  final List<BiliCommentTimeLink> links;
  final ValueChanged<int> onSeekToTime;

  @override
  Widget build(BuildContext context) {
    final extraLinks = links
        .where((link) => !_hasInlineRange(link))
        .toList(growable: false);
    if (extraLinks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final link in extraLinks)
            _CommentTimeChip(
              link: link,
              onTap: () => onSeekToTime(link.seconds),
            ),
        ],
      ),
    );
  }
}

class _CommentTimeChip extends StatelessWidget {
  const _CommentTimeChip({required this.link, required this.onTap});

  final BiliCommentTimeLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF7FC),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: Color(0xFF178DB8),
              ),
              const SizedBox(width: 3),
              Text(
                link.label,
                style: const TextStyle(
                  color: Color(0xFF178DB8),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentPictureGrid extends StatelessWidget {
  const _CommentPictureGrid({required this.pictures});

  final List<BiliCommentPicture> pictures;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (pictures.length == 1) {
          final picture = pictures.first;
          final width = constraints.maxWidth.clamp(180.0, 420.0).toDouble();
          final aspectRatio = _pictureAspectRatio(picture).clamp(0.72, 1.78);
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: width,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: _CommentPicture(picture: picture),
              ),
            ),
          );
        }

        final itemWidth = ((constraints.maxWidth - 16) / 3)
            .clamp(76.0, 118.0)
            .toDouble();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final picture in pictures.take(9))
              SizedBox.square(
                dimension: itemWidth,
                child: _CommentPicture(picture: picture),
              ),
          ],
        );
      },
    );
  }

  double _pictureAspectRatio(BiliCommentPicture picture) {
    final width = picture.width;
    final height = picture.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }
}

class _CommentPicture extends StatelessWidget {
  const _CommentPicture({required this.picture});

  final BiliCommentPicture picture;

  @override
  Widget build(BuildContext context) {
    final cacheWidth = (MediaQuery.devicePixelRatioOf(context) * 420)
        .round()
        .clamp(280, 960)
        .toInt();
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFFE7EAF0)),
            child: Image.network(
              picture.url,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Color(0xFF8C929F),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(color: Color(0x1A000000)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentActionRow extends StatelessWidget {
  const _CommentActionRow({required this.comment});

  final BiliVideoComment comment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CommentPassiveAction(
          icon: comment.liked
              ? Icons.thumb_up_rounded
              : Icons.thumb_up_alt_outlined,
          label: comment.likeCountLabel,
          selected: comment.liked,
        ),
        const SizedBox(width: 14),
        const _CommentPassiveAction(
          icon: Icons.thumb_down_alt_outlined,
          label: '',
        ),
        const SizedBox(width: 14),
        const _CommentPassiveAction(icon: Icons.ios_share_rounded, label: ''),
        const SizedBox(width: 14),
        const _CommentPassiveAction(
          icon: Icons.mode_comment_outlined,
          label: '',
        ),
        const Spacer(),
        const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFFADB3BE)),
      ],
    );
  }
}

class _CommentPassiveAction extends StatelessWidget {
  const _CommentPassiveAction({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFFB7299) : const Color(0xFF6D7480);
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentReplyPreview extends StatelessWidget {
  const _CommentReplyPreview({
    required this.comment,
    required this.onSeekToTime,
    required this.onOpenReplies,
  });

  final BiliVideoComment comment;
  final ValueChanged<int> onSeekToTime;
  final VoidCallback onOpenReplies;

  @override
  Widget build(BuildContext context) {
    final replies = comment.replies.take(2).toList(growable: false);
    final total = comment.replyCount > replies.length
        ? comment.replyCount
        : comment.replies.length;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onOpenReplies,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final reply in replies) ...[
                  _NestedReplyLine(reply: reply, onSeekToTime: onSeekToTime),
                  if (reply != replies.last) const SizedBox(height: 8),
                ],
                if (total > replies.length) ...[
                  const SizedBox(height: 9),
                  Text(
                    '共$total条回复 >',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF178DB8),
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NestedReplyLine extends StatelessWidget {
  const _NestedReplyLine({required this.reply, required this.onSeekToTime});

  final BiliVideoComment reply;
  final ValueChanged<int> onSeekToTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${reply.authorName}: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF178DB8),
            fontWeight: FontWeight.w900,
            height: 1.45,
          ),
        ),
        _CommentMessageText(
          message: reply.message,
          timeLinks: reply.timeLinks,
          onSeekToTime: onSeekToTime,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF171923),
            fontWeight: FontWeight.w700,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _CommentComposerBar extends StatelessWidget {
  const _CommentComposerBar({
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 16,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !submitting,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: submitting ? null : onSubmitted,
                  decoration: InputDecoration(
                    hintText: '你猜我的评论区在等谁？',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF0F1F5),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: submitting
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                            color: Color(0xFF8C929F),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: submitting
                    ? null
                    : () => onSubmitted(controller.text),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.send_rounded, color: Color(0xFFFB7299)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackBottomSheetScaffold extends StatelessWidget {
  const _PlaybackBottomSheetScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 54,
                  child: Row(
                    children: [
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFF171923),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 30,
                          color: Color(0xFF9AA0AA),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE8EAF0)),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentReplyDetail extends StatelessWidget {
  const _CommentReplyDetail({
    required this.comment,
    required this.onSeekToTime,
  });

  final BiliVideoComment comment;
  final ValueChanged<int> onSeekToTime;

  @override
  Widget build(BuildContext context) {
    final replies = comment.replies;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommentTile(
          comment: comment,
          onSeekToTime: onSeekToTime,
          onOpenReplies: (_) {},
          showRepliesPreview: false,
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFFF5F6FA)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '相关回复共${comment.replyCount > 0 ? comment.replyCount : replies.length}条',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF8C929F),
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.sort_rounded,
                    size: 20,
                    color: Color(0xFF8C929F),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '按时间',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF8C929F),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (replies.isEmpty)
          Text(
            '暂无相关回复',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF8C929F),
              fontWeight: FontWeight.w700,
            ),
          )
        else
          for (final reply in replies) ...[
            _CommentTile(
              comment: reply,
              onSeekToTime: onSeekToTime,
              onOpenReplies: (_) {},
              showRepliesPreview: false,
            ),
            if (reply != replies.last)
              const Divider(
                height: 28,
                thickness: 0.7,
                color: Color(0xFFE8EAF0),
              ),
          ],
      ],
    );
  }
}

class _CommentReplyPanel extends StatelessWidget {
  const _CommentReplyPanel({
    required this.comment,
    required this.controller,
    required this.onClose,
    required this.onSeekToTime,
  });

  final BiliVideoComment comment;
  final ScrollController controller;
  final VoidCallback onClose;
  final ValueChanged<int> onSeekToTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          key: const ValueKey<String>('playback-comment-replies-header'),
          height: 54,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '评论详情',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF171923),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: '关闭评论详情',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 28,
                  color: Color(0xFF9AA0AA),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE8EAF0)),
        Expanded(
          child: ListView(
            key: const PageStorageKey<String>('playback-comment-replies'),
            controller: controller,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            children: [
              _CommentReplyDetail(comment: comment, onSeekToTime: onSeekToTime),
            ],
          ),
        ),
      ],
    );
  }
}

class _DanmakuEntryPill extends StatelessWidget {
  const _DanmakuEntryPill({required this.danmakuCountLabel});

  final String danmakuCountLabel;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20, maxWidth: 140),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8FA),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE9EAF0)),
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
                    color: const Color(0xFF9AA0AA),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 14,
                color: Color(0xFF5E6572),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF9AA0AA)),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF8C929F),
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
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      color: const Color(0xFF11131A),
      fontWeight: FontWeight.w900,
      height: 1.18,
    );
    final descriptionStyle = theme.textTheme.bodyMedium?.copyWith(
      color: const Color(0xFF626875),
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
    return IconButton(
      onPressed: onTap,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      alignment: Alignment.topCenter,
      icon: AnimatedRotation(
        turns: expanded ? 0.5 : 0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: Transform.translate(
          offset: Offset(0, (firstLineHeight - 28) / 2),
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF9AA0AA),
            size: 28,
          ),
        ),
      ),
      tooltip: expanded ? '收起简介' : '展开简介',
    );
  }
}

class _PlaybackSectionHeader extends StatelessWidget {
  const _PlaybackSectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF171923),
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
    final cacheWidth = (96 * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(160, 360)
        .toInt();
    return Material(
      color: const Color(0xFFF7F8FA),
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
                        decoration: const BoxDecoration(
                          color: Color(0xFFE4E7EC),
                        ),
                        child: coverUrl.isEmpty
                            ? const Icon(
                                Icons.video_library_outlined,
                                color: Color(0xFF8C929F),
                              )
                            : Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: cacheWidth,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: Color(0xFF8C929F),
                                ),
                              ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.fromBorderSide(
                            BorderSide(color: Color(0x1A000000)),
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
                        color: const Color(0xFF8C929F),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      selectedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF171923),
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
                        color: const Color(0xFF8C929F),
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 28,
                color: Color(0xFF9AA0AA),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _BiliStageDeviceControls
    implements vesper_ui.VesperPlayerDeviceControls {
  const _BiliStageDeviceControls();

  @override
  Future<double?> currentBrightnessRatio() {
    return BiliDeviceControls.instance.getBrightness();
  }

  @override
  Future<double?> setBrightnessRatio(double ratio) {
    return BiliDeviceControls.instance.setBrightness(ratio);
  }

  @override
  Future<double?> currentVolumeRatio() {
    return BiliDeviceControls.instance.getVolume();
  }

  @override
  Future<double?> setVolumeRatio(double ratio) {
    return BiliDeviceControls.instance.setVolume(ratio);
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
    final imageProvider = avatarUrl.isEmpty
        ? null
        : ResizeImage.resizeIfNeeded(96, 96, NetworkImage(avatarUrl));
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF29A9DF),
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
                  color: const Color(0xFF171923),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8B909B),
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
    final foreground = selected
        ? const Color(0xFFFB7299)
        : const Color(0xFF343A46);
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
            color: selected ? const Color(0x66FB7299) : const Color(0x22343A46),
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
    final foreground = selected
        ? const Color(0xFFFB7299)
        : const Color(0xFF343A46);
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
                style: const TextStyle(
                  color: Color(0xFF8C929F),
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

class _EpisodePreviewList extends StatelessWidget {
  const _EpisodePreviewList({
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
    final titleColor = selected
        ? const Color(0xFFFB7299)
        : const Color(0xFF171923);
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
                      ? const ColoredBox(color: Color(0xFFC8CAD2))
                      : Image.network(
                          page.coverUrl ?? coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Color(0xFFC8CAD2)),
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
                        color: const Color(0xFF8C929F),
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

class _RelatedVideoList extends StatelessWidget {
  const _RelatedVideoList({
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
    if (items.isEmpty && loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (items.isEmpty && errorMessage != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF2F4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            errorMessage!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF8D2A46),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return Text(
        '暂无相关视频',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF8C929F),
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      children: [
        for (final item in items) ...[
          _RelatedVideoTile(
            item: item,
            opening: openingBvid == item.bvid,
            onTap: () => onTap(item),
          ),
          if (item != items.last)
            const Divider(height: 18, thickness: 0.7, color: Color(0xFFE8EAF0)),
        ],
        if (loading) ...[
          const SizedBox(height: 14),
          const Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
        ],
      ],
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
                            decoration: const BoxDecoration(
                              color: Color(0xFFE4E7EC),
                            ),
                            child: item.coverUrl.isEmpty
                                ? const Icon(
                                    Icons.video_library_outlined,
                                    color: Color(0xFF8C929F),
                                  )
                                : Image.network(
                                    item.coverUrl,
                                    fit: BoxFit.cover,
                                    cacheWidth: cacheWidth,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.broken_image_outlined,
                                      color: Color(0xFF8C929F),
                                    ),
                                  ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.fromBorderSide(
                                BorderSide(color: Color(0x1A000000)),
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
                              color: const Color(0xFF171923),
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
                              color: const Color(0xFF8C929F),
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              const Icon(
                                Icons.play_circle_outline_rounded,
                                size: 15,
                                color: Color(0xFF9AA0AA),
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  item.playCountLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF8C929F),
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      ui.FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.subtitles_outlined,
                                size: 15,
                                color: Color(0xFF9AA0AA),
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  item.danmakuCountLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF8C929F),
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

class _PlaybackInlineError extends StatelessWidget {
  const _PlaybackInlineError({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F4),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF9A2947),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6F3147),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => unawaited(onPressed()),
              child: Text(actionLabel),
            ),
          ],
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
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
                color: const Color(0xFF171923),
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
                color: const Color(0xFF7B8B9F),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF162033),
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

class _BiliPlaybackErrorState extends StatelessWidget {
  const _BiliPlaybackErrorState({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x140A1628),
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '播放器启动失败',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF162033),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    error.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF4B5B6E),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => unawaited(onRetry()),
                    child: const Text('重新尝试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
