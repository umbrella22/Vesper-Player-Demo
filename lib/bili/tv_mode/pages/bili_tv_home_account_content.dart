part of 'bili_tv_home_page.dart';

extension _BiliTvHomeAccountContent on _BiliTvHomePageState {
  Widget _buildMinePage() {
    return SignalBuilder(
      builder: (context) {
        final profile = _viewModel.profile.value;
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 760 || constraints.maxHeight < 390;
            final contentMaxWidth = (constraints.maxWidth * 0.72)
                .clamp(980.0, 1440.0)
                .toDouble();
            final account = _buildMineAccount(profile, compact: compact);
            final library = _buildMineLibraryActions(compact: compact);
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                28,
                compact ? 8 : 22,
                28,
                compact ? 24 : 36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            account,
                            const SizedBox(height: 22),
                            library,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 5, child: account),
                            const SizedBox(width: 48),
                            Expanded(flex: 6, child: library),
                          ],
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMineAccount(BiliUserProfile profile, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: compact ? 32 : 40,
              backgroundColor: const Color(0x33FFFFFF),
              backgroundImage: profile.avatarUrl.isNotEmpty
                  ? NetworkImage(profile.avatarUrl)
                  : null,
              child: profile.avatarUrl.isEmpty
                  ? Icon(
                      Icons.person_rounded,
                      color: const Color(0x99FFFFFF),
                      size: compact ? 30 : 36,
                    )
                  : null,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.isLoggedIn ? profile.name : '未登录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    profile.isLoggedIn ? '账号已登录' : '登录后同步账号内容',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0x77FFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 16 : 24),
        if (!profile.isLoggedIn)
          _TvMineCommand(
            key: const ValueKey<String>('bili-tv-mine-login'),
            icon: Icons.qr_code_scanner_rounded,
            label: '扫码登录',
            primary: true,
            onTap: () => unawaited(_openQrLogin()),
          )
        else
          Row(
            children: [
              Expanded(
                child: _TvMineCommand(
                  key: const ValueKey<String>('bili-tv-mine-logout'),
                  icon: Icons.logout_rounded,
                  label: '退出登录',
                  onTap: () => unawaited(_confirmLogout()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TvMineCommand(
                  key: const ValueKey<String>('bili-tv-mine-refresh'),
                  icon: Icons.refresh_rounded,
                  label: '刷新状态',
                  onTap: () => unawaited(_viewModel.refreshMine()),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildMineLibraryActions({required bool compact}) {
    final visualTheme = AppVisualTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '我的内容',
          style: TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: visualTheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: visualTheme.imageOutline),
            boxShadow: [
              BoxShadow(
                color: visualTheme.shadow,
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _TvLibraryAction(
                  key: const ValueKey<String>('bili-tv-mine-history'),
                  icon: Icons.history_rounded,
                  label: '历史播放',
                  compact: compact,
                  onTap: () =>
                      unawaited(_openLibrary(BiliLibrarySection.history)),
                ),
              ),
              Container(width: 1, height: 54, color: visualTheme.divider),
              Expanded(
                child: _TvLibraryAction(
                  key: const ValueKey<String>('bili-tv-mine-watch-later'),
                  icon: Icons.watch_later_outlined,
                  label: '稍后再看',
                  compact: compact,
                  onTap: () =>
                      unawaited(_openLibrary(BiliLibrarySection.watchLater)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 420;
        final panelMaxWidth = (constraints.maxWidth * 0.56)
            .clamp(600.0, 1100.0)
            .toDouble();
        return Align(
          alignment: compactHeight ? Alignment.topCenter : Alignment.center,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              compactHeight ? 4 : 24,
              24,
              compactHeight ? 24 : 36,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: panelMaxWidth),
              child: _buildSettingsPanelContent(compact: compactHeight),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsPanelContent({required bool compact}) {
    final modeChanged = _forceTvMode != _initialForceTvMode;
    final visualTheme = AppVisualTheme.of(context);
    return Container(
      padding: EdgeInsets.all(compact ? 22 : 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TV 设置',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 14 : 24),
          TvGlassSelectable(
            key: const ValueKey<String>('bili-tv-settings-force-mode-card'),
            scale: 1.025,
            borderRadius: AppVisualTokens.controlRadius,
            focusArea: TvFocusArea.content,
            debugLabel: 'tv_settings_force_mode',
            onTap: () => _toggleForceTvMode(!_forceTvMode),
            builder: (context, state) => DecoratedBox(
              decoration: BoxDecoration(
                color: visualTheme.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(
                  AppVisualTokens.controlRadius,
                ),
                border: Border.all(color: visualTheme.imageOutline),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 18 : 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '强制 TV 模式',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _forceTvMode ? '当前：TV 模式' : '当前：自动检测（根据设备）',
                            style: const TextStyle(
                              color: Color(0x88FFFFFF),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    IgnorePointer(
                      child: Switch(
                        value: _forceTvMode,
                        onChanged: _toggleForceTvMode,
                        activeThumbColor: AppVisualTokens.primaryBlue,
                        activeTrackColor: const Color(0x66409EFF),
                        inactiveThumbColor: const Color(0xDDFFFFFF),
                        inactiveTrackColor: const Color(0x22FFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 12 : 20),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              key: const ValueKey<String>('bili-tv-settings-about-card'),
              decoration: BoxDecoration(
                color: visualTheme.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(
                  AppVisualTokens.controlRadius,
                ),
                border: Border.all(color: visualTheme.imageOutline),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 18 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '关于 Vesper',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Vesper ${_appVersion.isEmpty ? '--' : _appVersion} · TV',
                      style: const TextStyle(
                        color: Color(0x88FFFFFF),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (modeChanged) ...[
            SizedBox(height: compact ? 12 : 20),
            Center(
              child: TvFocusable(
                autofocus: false,
                scale: 1.05,
                focusCornerRadius: 14,
                baseCornerRadius: 14,
                showGlow: false,
                onTap: () async {
                  _clearMessages();
                  final nextMode = await _uiModeController.refresh();
                  await _applyPresentationFor(nextMode);
                  if (!mounted) {
                    return;
                  }
                  final navigator = Navigator.of(context);
                  if (widget.uiModeController != null) {
                    navigator.popUntil((route) => route.isFirst);
                    return;
                  }

                  _restorePresentationOnDispose = false;
                  _uiModeControllerTransferred = true;
                  navigator.pushAndRemoveUntil(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, a, b) => HomePage.owningUiModeController(
                        uiModeController: _uiModeController,
                        client: _viewModel.client,
                        historyStore: _viewModel.historyStore,
                        sessionStore: _viewModel.sessionStore,
                        offlineController: _viewModel.offlineController,
                        appSettings: _appSettings,
                      ),
                      transitionsBuilder: (_, animation, c, child) {
                        return FadeTransition(
                          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOutCubic,
                            ),
                          ),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeInOutCubic,
                              ),
                            ),
                            child: child,
                          ),
                        );
                      },
                      transitionDuration: const Duration(milliseconds: 400),
                    ),
                    (_) => false,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppVisualTokens.primaryBlue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '返回首页并切换',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
          SizedBox(height: compact ? 12 : 20),
          const Text(
            '提示：开启强制 TV 模式后，应用将在手机和平板上也显示 TV 界面。'
            '关闭后将根据设备自动选择界面。模式切换将在返回首页后生效。',
            style: TextStyle(
              color: Color(0x66FFFFFF),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openQrLogin() async {
    final profile = await showBiliTvQrLoginDialog(
      context: context,
      client: _viewModel.client,
      sessionStore: _viewModel.sessionStore,
    );
    if (profile == null || !mounted) {
      return;
    }
    await _viewModel.applyLoggedInProfile(profile);
    await _loadHistory();
    _mutate(() {});
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showBiliTvGlassDialog<bool>(
      context: context,
      title: '退出登录？',
      message: '本机保存的登录状态会被清除，正在进行的离线缓存也会暂停。',
      icon: Icons.logout_rounded,
      actions: const [
        BiliTvDialogAction(
          label: '取消',
          value: false,
          icon: Icons.close_rounded,
          autofocus: true,
        ),
        BiliTvDialogAction(
          label: '退出登录',
          value: true,
          icon: Icons.logout_rounded,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _viewModel.logout();
      await _loadHistory();
      if (mounted) {
        _mutate(() {});
      }
    } catch (error) {
      if (mounted) {
        _showMessage('退出登录失败：${biliErrorMessage(error)}');
      }
    }
  }

  Future<bool?> _confirmRegionLogin() {
    return showBiliTvGlassDialog<bool>(
      context: context,
      title: '需要登录',
      message: '分区内容需要登录后才能观看，请先登录 Bilibili 账号。',
      icon: Icons.lock_outline_rounded,
      actions: const [
        BiliTvDialogAction(
          label: '取消',
          value: false,
          icon: Icons.close_rounded,
          autofocus: true,
        ),
        BiliTvDialogAction(label: '登录', value: true, icon: Icons.login_rounded),
      ],
    );
  }
}
