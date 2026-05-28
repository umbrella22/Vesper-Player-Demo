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
    final imageProvider = avatarUrl.isEmpty ? null : NetworkImage(avatarUrl);
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
    required this.favorited,
    required this.loading,
    required this.pendingAction,
    required this.onLike,
    required this.onFavorite,
    required this.onShare,
  });

  final String likeCountLabel;
  final String coinCountLabel;
  final String favoriteCountLabel;
  final String shareCountLabel;
  final bool liked;
  final bool favorited;
  final bool loading;
  final BiliEngagementAction? pendingAction;
  final VoidCallback onLike;
  final VoidCallback onFavorite;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final disabled = loading || pendingAction != null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ActionStatButton(
          icon: liked ? Icons.thumb_up_rounded : Icons.thumb_up_alt_outlined,
          label: '点赞',
          value: likeCountLabel,
          selected: liked,
          busy: pendingAction == BiliEngagementAction.like,
          onTap: disabled ? null : onLike,
        ),
        _ActionStatButton(
          icon: Icons.monetization_on_outlined,
          label: '硬币',
          value: coinCountLabel,
          selected: false,
        ),
        _ActionStatButton(
          icon: favorited ? Icons.star_rounded : Icons.star_border_rounded,
          label: '收藏',
          value: favoriteCountLabel,
          selected: favorited,
          busy: pendingAction == BiliEngagementAction.favorite,
          onTap: disabled ? null : onFavorite,
        ),
        _ActionStatButton(
          icon: Icons.ios_share_rounded,
          label: '分享',
          value: shareCountLabel,
          selected: false,
          busy: pendingAction == BiliEngagementAction.share,
          onTap: disabled ? null : onShare,
        ),
      ],
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
    final background = selected ? const Color(0xFFFFEDF3) : Colors.white;
    final borderColor = selected
        ? const Color(0xFFFFC8DA)
        : const Color(0xFFE8EAF0);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: busy ? null : onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: SizedBox(
            width: 72,
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, size: 20, color: foreground),
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
                  ),
                ),
                const SizedBox(height: 2),
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
