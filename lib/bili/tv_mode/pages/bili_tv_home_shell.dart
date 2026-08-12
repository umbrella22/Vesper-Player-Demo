part of 'bili_tv_home_page.dart';

extension _BiliTvHomeShell on _BiliTvHomePageState {
  Future<void> _confirmExitApp() async {
    if (!mounted || _exitDialogVisible) {
      return;
    }
    _exitDialogVisible = true;
    bool? shouldExit;
    try {
      shouldExit = await showBiliTvGlassDialog<bool>(
        context: context,
        maxWidth: 690,
        title: '退出 Vesper？',
        message: '播放进度已经保存，下次打开时可以继续观看。',
        icon: Icons.logout_rounded,
        actions: const [
          BiliTvDialogAction(
            label: '继续观看',
            value: false,
            icon: Icons.play_arrow_rounded,
            autofocus: true,
          ),
          BiliTvDialogAction(
            label: '退出应用',
            value: true,
            icon: Icons.power_settings_new_rounded,
            isDestructive: true,
          ),
        ],
      );
    } finally {
      _exitDialogVisible = false;
    }
    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }

  Widget _buildTvBackdrop(BoxConstraints constraints) {
    final hero = _heroItem;
    final duration = AppVisualTokens.motionDuration(
      context,
      _tvHeroCrossFadeDuration,
    );
    final cacheWidth =
        (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(960, 2560)
            .toInt();
    return RepaintBoundary(
      key: const ValueKey<String>('bili-tv-hero-backdrop'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: [...previousChildren, ?currentChild],
            ),
            child: hero == null || hero.coverUrl.isEmpty
                ? const ColoredBox(
                    key: ValueKey<String>('tv-hero-empty'),
                    color: AppVisualTokens.tvBackground,
                  )
                : Image.network(
                    hero.coverUrl,
                    key: ValueKey<String>('tv-hero-${hero.identity}'),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    cacheWidth: cacheWidth,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: AppVisualTokens.tvBackground),
                  ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0, 0.42, 1],
                colors: [
                  Color(0xF2111318),
                  Color(0xA6111318),
                  Color(0x33111318),
                ],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.46, 0.78, 1],
                colors: [
                  Color(0x1A111318),
                  Color(0x4D111318),
                  Color(0xE6111318),
                  AppVisualTokens.tvBackground,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftRail({required bool expanded}) {
    final quality = TvGlassQualityScope.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final contents = LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 620;
        final showLabels = expanded && constraints.maxWidth >= 180;
        return Column(
          children: [
            _buildRailProfile(expanded: showLabels, compact: compactHeight),
            SizedBox(height: compactHeight ? 6 : 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: compactHeight ? 8 : 10,
                ),
                children: [
                  for (final item in _TvNavItem.values)
                    _buildRailItem(
                      item,
                      expanded: showLabels,
                      compact: compactHeight,
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                showLabels ? 20 : 0,
                4,
                showLabels ? 20 : 0,
                compactHeight ? 10 : 18,
              ),
              child: Row(
                mainAxisAlignment: showLabels
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 40,
                    child: Center(
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 16,
                        color: Color(0x73FFFFFF),
                      ),
                    ),
                  ),
                  if (showLabels) ...[
                    const SizedBox(width: 12),
                    const Flexible(
                      child: Text(
                        '按返回键退出',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0x73FFFFFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
    final surface = DecoratedBox(
      key: const ValueKey<String>('bili-tv-left-rail'),
      decoration: BoxDecoration(
        color: highContrast ? const Color(0xFF17191F) : const Color(0xB317191F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highContrast
              ? const Color(0xB3FFFFFF)
              : const Color(0x2EFFFFFF),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: contents,
      ),
    );
    if (highContrast) {
      return surface;
    }
    return AdaptiveLiquidGlassLayer(
      quality: quality,
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      settings: const LiquidGlassSettings(
        blur: 11,
        thickness: 18,
        glassColor: Color(0x2417191F),
        lightIntensity: 0.62,
        saturation: 1.05,
      ),
      child: GlassContainer(
        useOwnLayer: false,
        quality: quality,
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        clipBehavior: Clip.hardEdge,
        child: surface,
      ),
    );
  }

  Widget _buildRailProfile({required bool expanded, bool compact = false}) {
    return SignalBuilder(
      builder: (context) {
        final profile = _viewModel.profile.value;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            expanded ? 20 : 0,
            compact ? 12 : 18,
            expanded ? 20 : 0,
            0,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  SizedBox(
                    key: const ValueKey<String>('bili-tv-rail-logo'),
                    width: 40,
                    child: Center(
                      child: Container(
                        width: compact ? 36 : 40,
                        height: compact ? 36 : 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6FA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 2),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Color(0xFF111318),
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Text(
                        'VESPER',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: compact ? 10 : 16),
              const Divider(height: 1, color: Color(0x24FFFFFF)),
              SizedBox(height: compact ? 10 : 16),
              Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  SizedBox(
                    key: const ValueKey<String>('bili-tv-rail-avatar'),
                    width: 40,
                    child: Center(
                      child: CircleAvatar(
                        radius: compact ? 17 : 19,
                        backgroundColor: const Color(0x33FFFFFF),
                        backgroundImage: profile.avatarUrl.isNotEmpty
                            ? NetworkImage(profile.avatarUrl)
                            : null,
                        child: profile.avatarUrl.isEmpty
                            ? Icon(
                                profile.isLoggedIn
                                    ? Icons.person_rounded
                                    : Icons.person_outline_rounded,
                                color: const Color(0xB3FFFFFF),
                                size: compact ? 18 : 20,
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.isLoggedIn ? profile.name : '未登录',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xF2FFFFFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile.isLoggedIn ? '已同步播放记录' : '登录后同步内容',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0x80FFFFFF),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRailItem(
    _TvNavItem item, {
    required bool expanded,
    bool compact = false,
  }) {
    final selected = _selectedNav == item;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 1 : 3),
      child: TvGlassSelectable(
        autofocus: item == _TvNavItem.recommend,
        selected: selected,
        useOwnLayer: false,
        scale: 1,
        borderRadius: 12,
        focusArea: TvFocusArea.homeRail,
        debugLabel: 'nav_${item.name}',
        onTap: () => unawaited(_handleNavTap(item)),
        onFocusChange: (focused) => _handleRailItemFocus(item, focused),
        builder: (context, state) {
          final focused =
              state == TvGlassSelectableState.focused ||
              state == TvGlassSelectableState.pressed;
          return SizedBox(
            height: compact ? 42 : 50,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: 0,
                  child: AnimatedContainer(
                    duration: AppVisualTokens.motionDuration(
                      context,
                      AppVisualTokens.tvFocusDuration,
                    ),
                    width: 3,
                    height: compact ? 20 : 24,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppVisualTokens.primaryBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: expanded ? 10 : 0,
                    right: expanded ? 10 : 0,
                  ),
                  child: Row(
                    mainAxisAlignment: expanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(expanded ? -1 : 0, 0),
                        child: SizedBox(
                          key: ValueKey<String>(
                            'bili-tv-rail-icon-${item.name}',
                          ),
                          width: 40,
                          child: Center(
                            child: Icon(
                              item.icon(),
                              color: focused || selected
                                  ? Colors.white
                                  : const Color(0x99FFFFFF),
                              size: focused
                                  ? (compact ? 21 : 23)
                                  : (compact ? 20 : 22),
                            ),
                          ),
                        ),
                      ),
                      if (expanded) ...[
                        SizedBox(width: compact ? 9 : 11),
                        Expanded(
                          child: Text(
                            key: ValueKey<String>(
                              'bili-tv-rail-label-${item.name}',
                            ),
                            item.label(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 14 : 15,
                              fontWeight: focused || selected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: focused || selected
                                  ? Colors.white
                                  : const Color(0x99FFFFFF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContentArea({
    required double followingRailOffset,
    required double followingVerticalInset,
  }) {
    final followingSelected = _selectedNav == _TvNavItem.following;
    final followingSessionIdentity = _followingSessionIdentity();
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Offstage(
            offstage: followingSelected,
            child: TickerMode(
              enabled: !followingSelected,
              child: ExcludeFocus(
                excluding: followingSelected,
                child: _buildPrimaryContentArea(_lastPrimaryNav),
              ),
            ),
          ),
        ),
        if (_followingPaneActivated)
          Positioned.fill(
            child: Offstage(
              offstage: !followingSelected,
              child: TickerMode(
                enabled: followingSelected,
                child: ExcludeFocus(
                  excluding: !followingSelected,
                  child: KeyedSubtree(
                    key: const ValueKey<String>('bili-tv-home-following-pane'),
                    child: BiliLibraryPage.tvFollowingPane(
                      key: ValueKey<String>(
                        'bili-tv-home-following-session-'
                        '$followingSessionIdentity',
                      ),
                      client: _viewModel.client,
                      historyStore: _viewModel.historyStore,
                      offlineController: _viewModel.offlineController,
                      onLoginTap: _openQrLogin,
                      forceCompactTvFollowingRail:
                          _activeFocusArea != TvFocusArea.rail,
                      tvFollowingRailOffset: followingRailOffset,
                      tvFollowingVerticalInset: followingVerticalInset,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _followingSessionIdentity() {
    final client = _viewModel.client;
    if (!client.hasAuthenticatedSession) {
      return 'logged-out';
    }
    final mid = client.snapshotCookies()['DedeUserID']?.trim();
    return mid == null || mid.isEmpty ? 'authenticated' : 'mid-$mid';
  }
}
