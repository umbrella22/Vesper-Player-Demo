part of 'bili_playback_content_surfaces.dart';

class _CommentsSurface extends StatefulWidget {
  const _CommentsSurface({required this.surfaces});

  final BiliPlaybackContentSurfaces surfaces;

  @override
  State<_CommentsSurface> createState() => _CommentsSurfaceState();
}

class _CommentsSurfaceState extends State<_CommentsSurface> {
  BiliVideoComment? _openedCommentReplies;

  @override
  Widget build(BuildContext context) {
    // VM 信号读取必须发生在 SignalBuilder 的 builder 调用栈内才会被追踪。
    return SignalBuilder(builder: (context) => _buildCommentsBody(context));
  }

  void _openReplies(BiliVideoComment comment) {
    final s = widget.surfaces;
    s.host.commentComposerFocusNode.unfocus();
    setState(() {
      _openedCommentReplies = comment;
    });
    s.host.onCommentRepliesVisibilityChanged(true);
    unawaited(s.viewModel.loadCommentReplies(comment));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && s.host.commentRepliesScrollController.hasClients) {
        s.host.commentRepliesScrollController.jumpTo(0);
      }
    });
  }

  void _closeReplies() {
    final s = widget.surfaces;
    if (_openedCommentReplies == null) {
      return;
    }
    setState(() {
      _openedCommentReplies = null;
    });
    s.host.onCommentRepliesVisibilityChanged(false);
    s.viewModel.clearCommentReplies();
  }

  Widget _buildCommentsBody(BuildContext context) {
    final s = widget.surfaces;
    final vm = s.viewModel;
    final openedCommentReplies = _openedCommentReplies;
    if (openedCommentReplies != null) {
      return NotificationListener<ScrollNotification>(
        onNotification: s.host.onContentScroll,
        child: _CommentReplyPanel(
          comment: openedCommentReplies,
          replies: vm.commentReplies,
          totalCount: vm.commentRepliesTotalCount,
          loading: vm.commentRepliesLoading,
          loadingMore: vm.commentRepliesLoadingMore,
          hasMore: vm.commentRepliesHasMore,
          errorMessage: vm.commentRepliesError,
          controller: s.host.commentRepliesScrollController,
          onClose: _closeReplies,
          onLoadMore: vm.loadMoreCommentReplies,
          onRetry: () => vm.retryCommentReplies(openedCommentReplies),
          onSeekToTime: (seconds) {
            _closeReplies();
            unawaited(s.host.onSeekToTime(seconds));
          },
        ),
      );
    }

    final bottomPadding = 118 + MediaQuery.viewPaddingOf(context).bottom;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: s.host.onContentScroll,
          child: ListView(
            key: const PageStorageKey<String>('playback-comments'),
            controller: s.host.commentsScrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.only(top: 14, bottom: bottomPadding),
            children: [
              _CommentThreadList(
                comments: vm.comments,
                loading: vm.commentsLoading,
                loadingMore: vm.commentsLoadingMore,
                hasMore: vm.commentsHasMore,
                errorMessage: vm.commentsError,
                onReload: vm.loadComments,
                onLoadMore: vm.loadMoreComments,
                onSeekToTime: (seconds) =>
                    unawaited(s.host.onSeekToTime(seconds)),
                onOpenReplies: _openReplies,
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _CommentComposerBar(
            controller: s.host.commentComposerController,
            focusNode: s.host.commentComposerFocusNode,
            submitting: vm.commentSubmitting,
            onSubmitted: (message) =>
                unawaited(_submitComment(context, message)),
          ),
        ),
      ],
    );
  }

  Future<void> _submitComment(BuildContext context, String rawMessage) async {
    final s = widget.surfaces;
    final vm = s.viewModel;
    final message = rawMessage.trim();
    if (message.isEmpty) {
      _showSnackBar(context, '评论内容不能为空');
      return;
    }
    final result = await vm.submitComment(message);
    if (!context.mounted || result == null) {
      return;
    }
    if (result == '已发送评论') {
      s.host.commentComposerController.clear();
      s.host.commentComposerFocusNode.unfocus();
      if (s.host.commentsScrollController.hasClients) {
        unawaited(
          s.host.commentsScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    }
    _showSnackBar(context, result);
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
    final visualTheme = AppVisualTheme.of(context);
    if (comments.isEmpty && loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (comments.isEmpty && errorMessage != null) {
      return PlaybackInlineError(
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
