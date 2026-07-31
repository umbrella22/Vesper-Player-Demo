part of 'bili_playback_page.dart';

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
    final visualTheme = AppVisualTheme.of(context);
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
                  color: visualTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
            ),
            Icon(Icons.sort_rounded, size: 20, color: visualTheme.textTertiary),
            const SizedBox(width: 5),
            Text(
              '按热度',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: visualTheme.textTertiary,
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
                color: visualTheme.textTertiary,
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
              Divider(height: 28, thickness: 0.7, color: visualTheme.divider),
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
                  foregroundColor: AppVisualTokens.primaryBlue,
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
                  color: visualTheme.textTertiary,
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
    final visualTheme = AppVisualTheme.of(context);
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
          backgroundColor: Color.alphaBlend(
            AppVisualTokens.primaryBlue.withValues(alpha: 0.12),
            visualTheme.surfaceRaised,
          ),
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
                  comment.authorName.isEmpty
                      ? '?'
                      : comment.authorName.characters.first,
                  style: TextStyle(
                    color: AppVisualTokens.primaryBlue,
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
                      color: visualTheme.textSecondary,
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
                    color: visualTheme.textTertiary,
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
                  color: visualTheme.textPrimary,
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
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          AppVisualTokens.biliSourcePink.withValues(alpha: 0.12),
          visualTheme.surfaceRaised,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          label,
          style: const TextStyle(
            color: AppVisualTokens.biliSourcePink,
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
    final visualTheme = AppVisualTheme.of(context);
    final style =
        widget.style ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: visualTheme.textPrimary,
          height: 1.5,
        );
    final linkStyle = style?.copyWith(
      color: AppVisualTokens.primaryBlue,
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
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: Color.alphaBlend(
        AppVisualTokens.primaryBlue.withValues(alpha: 0.12),
        visualTheme.surfaceRaised,
      ),
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
                color: AppVisualTokens.primaryBlue,
              ),
              const SizedBox(width: 3),
              Text(
                link.label,
                style: const TextStyle(
                  color: AppVisualTokens.primaryBlue,
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
    final visualTheme = AppVisualTheme.of(context);
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
            decoration: BoxDecoration(color: visualTheme.surfaceRaised),
            child: Image.network(
              picture.url,
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
    );
  }
}

class _CommentActionRow extends StatelessWidget {
  const _CommentActionRow({required this.comment});

  final BiliVideoComment comment;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
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
        Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: visualTheme.textTertiary,
        ),
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
    final visualTheme = AppVisualTheme.of(context);
    final color = selected
        ? AppVisualTokens.primaryBlue
        : visualTheme.textSecondary;
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
    final visualTheme = AppVisualTheme.of(context);
    final replies = comment.replies.take(2).toList(growable: false);
    final total = comment.replyCount > replies.length
        ? comment.replyCount
        : comment.replies.length;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: visualTheme.surfaceMuted,
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
                      color: AppVisualTokens.primaryBlue,
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
    final visualTheme = AppVisualTheme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${reply.authorName}: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppVisualTokens.primaryBlue,
            fontWeight: FontWeight.w900,
            height: 1.45,
          ),
        ),
        _CommentMessageText(
          message: reply.message,
          timeLinks: reply.timeLinks,
          onSeekToTime: onSeekToTime,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: visualTheme.textPrimary,
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
    final visualTheme = AppVisualTheme.of(context);
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visualTheme.surface,
          boxShadow: [
            BoxShadow(
              color: visualTheme.shadow,
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
                    fillColor: visualTheme.surfaceRaised,
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
                        : Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                            color: visualTheme.textTertiary,
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
                icon: const Icon(
                  Icons.send_rounded,
                  color: AppVisualTokens.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentReplySummary extends StatelessWidget {
  const _CommentReplySummary({required this.totalCount});

  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(color: visualTheme.surfaceMuted),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '相关回复共$totalCount条',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: visualTheme.textTertiary,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Icon(
                Icons.sort_rounded,
                size: 20,
                color: visualTheme.textTertiary,
              ),
              const SizedBox(width: 5),
              Text(
                '按时间',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: visualTheme.textTertiary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentReplyPanel extends StatelessWidget {
  const _CommentReplyPanel({
    required this.comment,
    required this.replies,
    required this.totalCount,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.errorMessage,
    required this.controller,
    required this.onClose,
    required this.onLoadMore,
    required this.onRetry,
    required this.onSeekToTime,
  });

  final BiliVideoComment comment;
  final List<BiliVideoComment> replies;
  final int? totalCount;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? errorMessage;
  final ScrollController controller;
  final VoidCallback onClose;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRetry;
  final ValueChanged<int> onSeekToTime;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
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
                    color: visualTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: '关闭评论详情',
                icon: Icon(
                  Icons.close_rounded,
                  size: 28,
                  color: visualTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: visualTheme.divider),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey<String>('playback-comment-replies'),
            controller: controller,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            itemCount: replies.length + 3,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _CommentTile(
                    comment: comment,
                    onSeekToTime: onSeekToTime,
                    onOpenReplies: (_) {},
                    showRepliesPreview: false,
                  ),
                );
              }
              if (index == 1) {
                final visibleTotal =
                    totalCount ??
                    (comment.replyCount > 0
                        ? comment.replyCount
                        : replies.length);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _CommentReplySummary(totalCount: visibleTotal),
                );
              }

              final replyIndex = index - 2;
              if (replyIndex < replies.length) {
                final reply = replies[replyIndex];
                return KeyedSubtree(
                  key: ValueKey<String>('playback-comment-reply-${reply.id}'),
                  child: Column(
                    children: [
                      _CommentTile(
                        comment: reply,
                        onSeekToTime: onSeekToTime,
                        onOpenReplies: (_) {},
                        showRepliesPreview: false,
                      ),
                      if (replyIndex != replies.length - 1)
                        Divider(
                          height: 28,
                          thickness: 0.7,
                          color: visualTheme.divider,
                        ),
                    ],
                  ),
                );
              }

              return _CommentReplyLoadFooter(
                hasReplies: replies.isNotEmpty,
                loading: loading || loadingMore,
                hasMore: hasMore,
                errorMessage: errorMessage,
                onLoadMore: onLoadMore,
                onRetry: onRetry,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CommentReplyLoadFooter extends StatelessWidget {
  const _CommentReplyLoadFooter({
    required this.hasReplies,
    required this.loading,
    required this.hasMore,
    required this.errorMessage,
    required this.onLoadMore,
    required this.onRetry,
  });

  final bool hasReplies;
  final bool loading;
  final bool hasMore;
  final String? errorMessage;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    if (errorMessage case final message?) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: visualTheme.destructive,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (!hasReplies) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            '暂无相关回复',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: visualTheme.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton.icon(
            onPressed: () => unawaited(onLoadMore()),
            icon: const Icon(Icons.expand_more_rounded, size: 20),
            label: const Text('加载更多回复'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          '没有更多回复了',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: visualTheme.textTertiary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
