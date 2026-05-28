part of 'bili_hub_page.dart';

class _MineTab extends StatelessWidget {
  const _MineTab({
    required this.profile,
    required this.profileErrorMessage,
    required this.isRefreshingProfile,
    required this.historyCount,
    required this.onLoginTap,
    required this.onLogoutTap,
    required this.onSpaceTap,
    required this.onCacheTap,
    required this.onHistoryTap,
    required this.onFavoritesTap,
    required this.onWatchLaterTap,
    required this.onSettingsTap,
    required this.onRefresh,
  });

  final BiliUserProfile profile;
  final String? profileErrorMessage;
  final bool isRefreshingProfile;
  final int historyCount;
  final Future<void> Function() onLoginTap;
  final Future<void> Function() onLogoutTap;
  final VoidCallback onSpaceTap;
  final VoidCallback onCacheTap;
  final Future<void> Function() onHistoryTap;
  final VoidCallback onFavoritesTap;
  final VoidCallback onWatchLaterTap;
  final VoidCallback onSettingsTap;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _MineProfileHeader(
              profile: profile,
              isRefreshing: isRefreshingProfile,
              onLoginTap: onLoginTap,
              onLogoutTap: onLogoutTap,
              onSpaceTap: onSpaceTap,
            ),
            if (!profile.isLoggedIn && profileErrorMessage != null) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _InlineErrorBanner(
                  message: profileErrorMessage!,
                  actionLabel: '重新登录',
                  onPressed: onLoginTap,
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MineShortcut(
                          icon: Icons.download_for_offline_outlined,
                          label: '离线缓存',
                          onTap: onCacheTap,
                        ),
                      ),
                      Expanded(
                        child: _MineShortcut(
                          icon: Icons.history_rounded,
                          label: historyCount == 0 ? '历史记录' : '历史记录',
                          onTap: onHistoryTap,
                        ),
                      ),
                      Expanded(
                        child: _MineShortcut(
                          icon: Icons.star_border_rounded,
                          label: '我的收藏',
                          onTap: onFavoritesTap,
                        ),
                      ),
                      Expanded(
                        child: _MineShortcut(
                          icon: Icons.play_circle_outline_rounded,
                          label: '稍后再看',
                          onTap: onWatchLaterTap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text(
                    '更多服务',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF20232B),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MineServiceRow(
                    icon: Icons.settings_outlined,
                    label: '设置',
                    onTap: onSettingsTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MineProfileHeader extends StatelessWidget {
  const _MineProfileHeader({
    required this.profile,
    required this.isRefreshing,
    required this.onLoginTap,
    required this.onLogoutTap,
    required this.onSpaceTap,
  });

  final BiliUserProfile profile;
  final bool isRefreshing;
  final Future<void> Function() onLoginTap;
  final Future<void> Function() onLogoutTap;
  final VoidCallback onSpaceTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MineAvatar(profile: profile),
              const SizedBox(width: 13),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: profile.isLoggedIn
                                        ? const Color(0xFFFB7299)
                                        : const Color(0xFF20232B),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          if (profile.level case final level?) ...[
                            const SizedBox(width: 7),
                            _MineLevelBadge(level: level),
                          ],
                          if (isRefreshing) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      if (profile.isLoggedIn && profile.vipLabel != null)
                        _MineVipPill(label: profile.vipLabel!)
                      else
                        Text(
                          profile.isLoggedIn ? '账号已登录' : '扫码登录后同步推荐与播放解析',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: const Color(0xFF858A94),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      const SizedBox(height: 7),
                      _MineAssetLine(profile: profile),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _MineSpaceAction(
                loggedIn: profile.isLoggedIn,
                onLoginTap: onLoginTap,
                onSpaceTap: onSpaceTap,
                onLogoutTap: onLogoutTap,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _MineStatsRow(profile: profile),
        ],
      ),
    );
  }
}

class _MineAvatar extends StatelessWidget {
  const _MineAvatar({required this.profile});

  final BiliUserProfile profile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: const Color(0xFFFFDCE7),
            backgroundImage: profile.avatarUrl.isEmpty
                ? null
                : NetworkImage(profile.avatarUrl),
            child: profile.avatarUrl.isEmpty
                ? Icon(
                    profile.isLoggedIn
                        ? Icons.person_rounded
                        : Icons.qr_code_2_rounded,
                    color: const Color(0xFFFB7299),
                    size: 27,
                  )
                : null,
          ),
          if (profile.isLoggedIn)
            Positioned(
              right: -2,
              bottom: 1,
              child: Container(
                width: 21,
                height: 21,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFB7299),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  profile.vipLabel == null ? '已' : '大',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MineLevelBadge extends StatelessWidget {
  const _MineLevelBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5D79),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'LV$level',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 9,
          height: 1,
        ),
      ),
    );
  }
}

class _MineVipPill extends StatelessWidget {
  const _MineVipPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFFFB7299),
          fontWeight: FontWeight.w900,
          fontSize: 10,
          height: 1,
        ),
      ),
    );
  }
}

class _MineAssetLine extends StatelessWidget {
  const _MineAssetLine({required this.profile});

  final BiliUserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Text(
      'B币：${_formatBalance(profile.bCoinBalance)}   硬币：${_formatBalance(profile.coinBalance)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: const Color(0xFF858A94),
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    );
  }
}

class _MineSpaceAction extends StatelessWidget {
  const _MineSpaceAction({
    required this.loggedIn,
    required this.onLoginTap,
    required this.onSpaceTap,
    required this.onLogoutTap,
  });

  final bool loggedIn;
  final Future<void> Function() onLoginTap;
  final VoidCallback onSpaceTap;
  final Future<void> Function() onLogoutTap;

  @override
  Widget build(BuildContext context) {
    if (!loggedIn) {
      return TextButton(
        onPressed: onLoginTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(54, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('登录'),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSpaceTap,
      onLongPress: () {
        onLogoutTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '空间',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF9AA0AA),
                fontWeight: FontWeight.w800,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFB6BBC4),
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _MineStatsRow extends StatelessWidget {
  const _MineStatsRow({required this.profile});

  final BiliUserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MineStatItem(
            value: _formatStat(profile.dynamicCount),
            label: '动态',
          ),
        ),
        const _MineStatDivider(),
        Expanded(
          child: _MineStatItem(
            value: _formatStat(profile.followingCount),
            label: '关注',
          ),
        ),
        const _MineStatDivider(),
        Expanded(
          child: _MineStatItem(
            value: _formatStat(profile.followerCount),
            label: '粉丝',
          ),
        ),
      ],
    );
  }
}

class _MineStatItem extends StatelessWidget {
  const _MineStatItem({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF20232B),
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xFF8D929C),
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _MineStatDivider extends StatelessWidget {
  const _MineStatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 18, color: const Color(0xFFE3E6EB));
  }
}

String _formatBalance(double? value) {
  if (value == null) {
    return '--';
  }
  if ((value - value.roundToDouble()).abs() < 0.01) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

String _formatStat(int? value) {
  if (value == null) {
    return '--';
  }
  return value.toString();
}

class _MineShortcut extends StatelessWidget {
  const _MineShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF28A9DF), size: 29),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF4A4E57),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MineServiceRow extends StatelessWidget {
  const _MineServiceRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: const Color(0xFFFB7299), size: 27),
      title: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: const Color(0xFF4A4E57),
          fontWeight: FontWeight.w900,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFFADB2BB),
        size: 28,
      ),
      onTap: onTap,
    );
  }
}
