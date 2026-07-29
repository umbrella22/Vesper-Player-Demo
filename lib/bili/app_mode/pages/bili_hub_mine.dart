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
    required this.onFollowingTap,
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
  final VoidCallback onFollowingTap;
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
          padding: EdgeInsets.only(
            bottom: AppGlassBottomNavigation.contentClearance(context),
          ),
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
                  Text(
                    '常用功能',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppVisualTheme.of(context).textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppGroupedSurface(
                    key: const ValueKey<String>('bili-mine-shortcuts-glass'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
                              label: '历史记录',
                              onTap: onHistoryTap,
                            ),
                          ),
                          Expanded(
                            child: _MineShortcut(
                              icon: Icons.people_alt_outlined,
                              label: '关注列表',
                              onTap: onFollowingTap,
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
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '更多服务',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppVisualTheme.of(context).textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppGroupedSurface(
                    children: [
                      AppSettingsRow(
                        key: const ValueKey<String>(
                          'bili-mine-settings-surface',
                        ),
                        icon: Icons.settings_outlined,
                        title: '设置',
                        subtitle: '外观、TV 模式、账号与离线数据',
                        onTap: onSettingsTap,
                      ),
                    ],
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
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      key: const ValueKey<String>('bili-mine-profile-header'),
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
                                    color: visualTheme.textPrimary,
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
                                color: visualTheme.textSecondary,
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
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: AppVisualTokens.biliSourcePink.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.18
                  : 0.12,
            ),
            backgroundImage: profile.avatarUrl.isEmpty
                ? null
                : NetworkImage(profile.avatarUrl),
            child: profile.avatarUrl.isEmpty
                ? Icon(
                    profile.isLoggedIn
                        ? Icons.person_rounded
                        : Icons.qr_code_2_rounded,
                    color: AppVisualTokens.biliSourcePink,
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
                  color: AppVisualTokens.primaryBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: visualTheme.background, width: 2),
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
        color: AppVisualTokens.biliSourcePink,
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
        color: AppVisualTokens.biliSourcePink.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppVisualTokens.biliSourcePink,
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
    final visualTheme = AppVisualTheme.of(context);
    return Text(
      'B币：${_formatBalance(profile.bCoinBalance)}   硬币：${_formatBalance(profile.coinBalance)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: visualTheme.textSecondary,
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
    final visualTheme = AppVisualTheme.of(context);
    if (!loggedIn) {
      return TextButton(
        onPressed: onLoginTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(54, AppVisualTokens.minimumTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 10),
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
                color: visualTheme.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: visualTheme.textTertiary,
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
    final visualTheme = AppVisualTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: visualTheme.textSecondary,
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
    return Container(
      width: 1,
      height: 18,
      color: AppVisualTheme.of(context).divider,
    );
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
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppVisualTokens.controlRadius),
        onTap: onTap,
        child: SizedBox(
          height: 74,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIconTile(icon: icon, color: visualTheme.textPrimary),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: visualTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
