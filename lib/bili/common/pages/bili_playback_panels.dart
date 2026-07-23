part of 'bili_playback_page.dart';

extension _BiliPlaybackPanels on _BiliPlaybackPageState {
  Widget _buildIntroPanel(BuildContext context, VesperPlayerSnapshot snapshot) {
    return TabBarView(
      controller: _infoTabController,
      physics: const BouncingScrollPhysics(),
      children: [
        _buildIntroBody(context, snapshot),
        _buildCommentsPanel(context),
      ],
    );
  }

  Widget _buildIntroBody(BuildContext context, VesperPlayerSnapshot snapshot) {
    final description = widget.detail.description.trim();
    final pages = widget.detail.pages;
    final isPgc = _isPgcDetail;

    final topChildren = <Widget>[
      if (!isPgc) ...[
        _OwnerSummary(
          name: widget.detail.ownerName,
          avatarUrl: widget.detail.ownerAvatarUrl,
          subtitle: _ownerSubtitle,
          isFollowing: _engagement?.isFollowingOwner ?? false,
          isBusy: _pendingEngagementAction == BiliEngagementAction.follow,
          onFollow: () => unawaited(_toggleFollow()),
        ),
        const SizedBox(height: 18),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              widget.detail.title,
              maxLines: _introExpanded ? 4 : 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF11131A),
                fontWeight: FontWeight.w900,
                height: 1.18,
              ),
            ),
          ),
          if (description.isNotEmpty)
            _IntroExpandButton(
              expanded: _introExpanded,
              onTap: _toggleIntroExpanded,
            ),
        ],
      ),
      const SizedBox(height: 9),
      _PlaybackMetaLine(
        entries: [
          if (widget.detail.playCountLabel != '--')
            _PlaybackMetaEntry(
              icon: Icons.play_circle_outline_rounded,
              label: '${widget.detail.playCountLabel}播放',
            ),
          if (widget.detail.danmakuCountLabel != '--')
            _PlaybackMetaEntry(
              icon: Icons.subtitles_outlined,
              label: widget.detail.danmakuCountLabel,
            ),
          if (widget.detail.publishedAtLabel != null)
            _PlaybackMetaEntry(
              icon: Icons.schedule_rounded,
              label: widget.detail.publishedAtLabel!,
            ),
          _PlaybackMetaEntry(
            icon: Icons.confirmation_number_outlined,
            label: _selectedPage.bvid ?? widget.detail.bvid,
          ),
        ],
      ),
      if (description.isNotEmpty) ...[
        const SizedBox(height: 13),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Text(
            description,
            maxLines: _introExpanded ? null : 3,
            overflow: _introExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF626875),
              height: 1.62,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
      if (!isPgc) ...[
        const SizedBox(height: 22),
        _ActionStatRow(
          likeCountLabel: widget.detail.likeCountLabel,
          coinCountLabel: _coinCountLabel,
          favoriteCountLabel: widget.detail.favoriteCountLabel,
          shareCountLabel: _shareCountLabel,
          liked: _engagement?.isLiked ?? false,
          sentCoinCount: _sentCoinCount,
          favorited: _engagement?.isFavorited ?? false,
          loading: _engagementLoading,
          pendingAction: _pendingEngagementAction,
          onLike: () => unawaited(_toggleLike()),
          onCoin: () => unawaited(_addCoin()),
          onFavorite: () => unawaited(_toggleFavorite()),
          onShare: () => unawaited(_shareVideo()),
        ),
      ],
      if (pages.length > 1) ...[
        const SizedBox(height: 18),
        _PageSelectionButton(
          title: isPgc
              ? '剧集 · 共 ${pages.length} 话/集'
              : '合集 · 共 ${pages.length} 个分 P',
          selectedLabel: isPgc
              ? '第 ${_selectedPage.pageNumber} 话 · ${_selectedPage.title}'
              : 'P${_selectedPage.pageNumber} · ${_selectedPage.title}',
          coverUrl: _selectedPage.coverUrl ?? widget.detail.coverUrl,
          durationLabel: biliFormatDurationSeconds(
            _selectedPage.durationSeconds,
          ),
          onTap: () => unawaited(_showPageSelectionSheet()),
        ),
      ],
      const SizedBox(height: 10),
      _WatchLaterButton(
        selected: _isInWatchLater,
        busy:
            _watchLaterLoading ||
            _pendingEngagementAction == BiliEngagementAction.watchLater,
        onTap: () => unawaited(_toggleWatchLater()),
      ),
      const SizedBox(height: 18),
      _PlaybackSectionHeader(
        title: '相关推荐',
        action: _relatedVideosError == null
            ? null
            : TextButton.icon(
                onPressed: () => unawaited(_reloadRelatedVideos()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(58, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: const Color(0xFFFB7299),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
      ),
      const SizedBox(height: 12),
    ];

    return NotificationListener<ScrollNotification>(
      onNotification: _handleMobileContentScroll,
      child: ListView(
        key: const PageStorageKey<String>('playback-related'),
        controller: _relatedScrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.only(top: 14, bottom: 18),
        children: [
          ...topChildren,
          _RelatedVideoList(
            items: _relatedVideos,
            loading: _relatedVideosLoading,
            errorMessage: _relatedVideosError,
            openingBvid: _openingRelatedBvid,
            onTap: (video) => unawaited(_openRelatedVideo(video)),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsPanel(BuildContext context) {
    final bottomPadding = 118 + MediaQuery.viewPaddingOf(context).bottom;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _handleMobileContentScroll,
          child: ListView(
            key: const PageStorageKey<String>('playback-comments'),
            controller: _commentsScrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.only(top: 14, bottom: bottomPadding),
            children: [
              _CommentThreadList(
                comments: _comments,
                loading: _commentsLoading,
                loadingMore: _commentsLoadingMore,
                hasMore: _commentsHasMore,
                errorMessage: _commentsError,
                onReload: _reloadComments,
                onLoadMore: _loadMoreComments,
                onSeekToTime: (seconds) =>
                    unawaited(_seekToCommentTime(seconds)),
                onOpenReplies: (comment) =>
                    unawaited(_showCommentReplies(comment)),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _CommentComposerBar(
            controller: _commentComposerController,
            focusNode: _commentComposerFocusNode,
            submitting: _commentSubmitting,
            onSubmitted: (message) => unawaited(_submitComment(message)),
          ),
        ),
      ],
    );
  }

  bool get _isPgcDetail =>
      widget.detail.ownerMid <= 0 && widget.detail.ownerName == '番剧';
}
