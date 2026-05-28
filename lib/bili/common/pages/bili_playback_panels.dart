part of 'bili_playback_page.dart';

extension _BiliPlaybackPanels on _BiliPlaybackPageState {
  Widget _buildIntroPanel(BuildContext context, VesperPlayerSnapshot snapshot) {
    final description = widget.detail.description.trim();
    final pages = widget.detail.pages;
    final isPgc = _isPgcDetail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.detail.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF11131A),
            fontWeight: FontWeight.w900,
            height: 1.18,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _videoMetaLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF8C929F),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (!isPgc) ...[
          const SizedBox(height: 18),
          _ActionStatRow(
            likeCountLabel: widget.detail.likeCountLabel,
            coinCountLabel: widget.detail.coinCountLabel,
            favoriteCountLabel: widget.detail.favoriteCountLabel,
            shareCountLabel: _shareCountLabel,
            liked: _engagement?.isLiked ?? false,
            favorited: _engagement?.isFavorited ?? false,
            loading: _engagementLoading,
            pendingAction: _pendingEngagementAction,
            onLike: () => unawaited(_toggleLike()),
            onFavorite: () => unawaited(_toggleFavorite()),
            onShare: () => unawaited(_shareVideo()),
          ),
          const SizedBox(height: 22),
          _OwnerSummary(
            name: widget.detail.ownerName,
            avatarUrl: widget.detail.ownerAvatarUrl,
            subtitle: _ownerSubtitle,
            isFollowing: _engagement?.isFollowingOwner ?? false,
            isBusy: _pendingEngagementAction == BiliEngagementAction.follow,
            onFollow: () => unawaited(_toggleFollow()),
          ),
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF575D69),
              height: 1.65,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (pages.length > 1) ...[
          const SizedBox(height: 20),
          _PanelHeading(
            title: isPgc
                ? '剧集 · 共 ${pages.length} 话/集'
                : '合集 · 共 ${pages.length} 个分 P',
          ),
          const SizedBox(height: 12),
          _EpisodePreviewList(
            pages: pages,
            selectedPage: _selectedPage,
            coverUrl: widget.detail.coverUrl,
            onTap: _switchPage,
            isPgc: isPgc,
          ),
        ],
      ],
    );
  }

  bool get _isPgcDetail =>
      widget.detail.ownerMid <= 0 && widget.detail.ownerName == '番剧';
}
