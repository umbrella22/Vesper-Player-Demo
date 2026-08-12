part of 'bili_playback_content_surfaces.dart';

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
