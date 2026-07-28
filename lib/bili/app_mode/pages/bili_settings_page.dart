import 'dart:async';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import 'package:bilibili_player/app/design/app_visual_theme.dart';
import 'package:bilibili_player/app/design/app_glass_controls.dart';
import 'package:bilibili_player/app/system_presentation.dart';
import 'package:bilibili_player/bili/common/services/bili_app_settings.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_logout_service.dart';
import 'package:bilibili_player/bili/common/services/bili_session_store.dart';
import 'package:bilibili_player/bili/common/services/bili_ui_mode_resolver.dart';
import 'package:bilibili_player/bili/common/widgets/bili_glass_sheet.dart';
import 'package:bilibili_player/download/download.dart';
import 'package:bilibili_player/app/home_page.dart';
import 'package:bilibili_player/main.dart';

class BiliSettingsPage extends StatefulWidget {
  const BiliSettingsPage({
    super.key,
    this.appSettings,
    this.client,
    this.sessionStore,
    this.offlineController,
  });

  final BiliAppSettings? appSettings;
  final BiliClient? client;
  final BiliSessionStore? sessionStore;
  final BiliOfflineDownloadController? offlineController;

  @override
  State<BiliSettingsPage> createState() => _BiliSettingsPageState();
}

class _BiliSettingsPageState extends State<BiliSettingsPage> {
  late final BiliAppSettings _appSettings;
  late final BiliClient _client;
  late final BiliSessionStore _sessionStore;
  late final BiliOfflineDownloadController _offlineController;
  final _forceTvMode = signal(false);
  final _hasAuthenticatedSession = signal(false);
  final _loading = signal(true);
  final _loggingOut = signal(false);

  @override
  void initState() {
    super.initState();
    _appSettings = widget.appSettings ?? const BiliAppSettings();
    _client = widget.client ?? BiliClient.instance;
    _sessionStore = widget.sessionStore ?? const BiliSessionStore();
    _offlineController =
        widget.offlineController ?? BiliOfflineDownloadController.instance;
    _load();
  }

  @override
  void dispose() {
    _forceTvMode.dispose();
    _hasAuthenticatedSession.dispose();
    _loading.dispose();
    _loggingOut.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      _appSettings.getForceTvMode(),
      _sessionStore.loadCookies(),
    ]);
    final forceTvMode = values[0] as bool;
    final cookies = values[1] as Map<String, String>;
    if (cookies.isNotEmpty) {
      _client.restoreCookies(cookies);
    }
    if (mounted) {
      _forceTvMode.value = forceTvMode;
      _hasAuthenticatedSession.value =
          _client.hasAuthenticatedSession || _isAuthenticatedCookieSet(cookies);
      _loading.value = false;
    }
  }

  Future<void> _toggleForceTvMode(bool value) async {
    await _appSettings.setForceTvMode(value);
    if (!mounted) {
      return;
    }
    _forceTvMode.value = value;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(value ? 'TV 模式已开启' : 'TV 模式已关闭'),
          action: SnackBarAction(
            label: '返回首页切换',
            onPressed: () => _switchHome(),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
  }

  Future<void> _switchHome() async {
    final nextMode = await refreshUiMode();
    await _applyPresentationFor(nextMode);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (_, a, b) => const HomePage(),
        transitionsBuilder: (_, animation, c, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 420),
      ),
      (_) => false,
    );
  }

  Future<void> _confirmLogout() async {
    if (_loggingOut.value || !_hasAuthenticatedSession.value) {
      return;
    }
    final confirmed = await showBiliGlassDialog<bool>(
      context: context,
      title: '退出登录',
      message: '将清除本地 cookie 和登录态，并暂停当前离线缓存任务。',
      actions: const [
        BiliGlassDialogAction(label: '取消', value: false),
        BiliGlassDialogAction(label: '退出', value: true, isDestructive: true),
      ],
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _logout();
  }

  Future<void> _logout() async {
    _loggingOut.value = true;
    try {
      final result = await clearBiliAuthenticatedSession(
        client: _client,
        sessionStore: _sessionStore,
        offlineController: _offlineController,
      );
      _hasAuthenticatedSession.value = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.pausedDownloadsSuccessfully
                  ? '已退出登录，离线缓存任务已暂停'
                  : '已退出登录，但暂停离线缓存时遇到问题',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('退出登录失败：$error')));
    } finally {
      if (mounted) {
        _loggingOut.value = false;
      }
    }
  }

  Future<void> _applyPresentationFor(BiliUiMode mode) async {
    if (mode == BiliUiMode.tv) {
      await setBiliPreferredOrientations(biliLandscapeOrientations);
    } else {
      await setBiliAppPreferredOrientations();
    }
    await setBiliSystemUiMode(
      mode == BiliUiMode.tv
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.edgeToEdge,
    );
    setBiliSystemUiOverlayStyle(
      mode == BiliUiMode.tv ? biliTvSystemUiStyle : biliAppSystemUiStyle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassScaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      statusBarStyle: GlassStatusBarStyle.auto,
      extendBody: false,
      appBar: const GlassAppBar(
        centerTitle: false,
        title: Text(
          '设置',
          style: TextStyle(
            color: Color(0xFF20232B),
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
      ),
      body: SignalBuilder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading.value) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _buildSectionLabel('显示模式'),
        SignalBuilder(builder: _buildDisplayModeCard),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '开启后应用将在手机和平板上也显示 TV 界面。'
            '关闭后将根据设备自动选择界面。切换后需返回首页生效。',
            style: TextStyle(
              color: const Color(0xFF8B9098).withValues(alpha: 0.75),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        SignalBuilder(builder: _buildReturnHomeAction),
        const SizedBox(height: 28),
        _buildSectionLabel('账号'),
        SignalBuilder(builder: _buildAccountCard),
        const SizedBox(height: 28),
        _buildSectionLabel('关于'),
        GlassCard(
          useOwnLayer: true,
          quality: GlassQuality.minimal,
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(
              Icons.info_outline_rounded,
              color: AppVisualTokens.primaryBlue,
            ),
            title: const Text(
              'bilibili_player',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              '0.1.0 — TV Preview',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final loggedIn = _hasAuthenticatedSession.value;
    final loggingOut = _loggingOut.value;
    return GlassCard(
      useOwnLayer: true,
      quality: GlassQuality.minimal,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          loggedIn
              ? Icons.account_circle_rounded
              : Icons.account_circle_outlined,
          color: AppVisualTokens.biliSourcePink,
        ),
        title: const Text(
          'Bilibili 账号',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          loggedIn ? '当前已保存本地登录 cookie' : '当前未保存本地登录 cookie',
          style: const TextStyle(color: Color(0xFF8B9098), fontSize: 13),
        ),
        trailing: loggedIn
            ? TextButton(
                onPressed: loggingOut ? null : _confirmLogout,
                child: loggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('退出登录'),
              )
            : null,
      ),
    );
  }

  Widget _buildDisplayModeCard(BuildContext context) {
    final forceTvMode = _forceTvMode.value;
    return GlassCard(
      useOwnLayer: true,
      quality: GlassQuality.minimal,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        secondary: const Icon(
          Icons.tv_rounded,
          color: AppVisualTokens.primaryBlue,
        ),
        title: const Text(
          '强制 TV 模式',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF20232B),
          ),
        ),
        subtitle: Text(
          forceTvMode ? '当前：TV 模式界面' : '当前：根据设备自动选择',
          style: const TextStyle(color: Color(0xFF8B9098), fontSize: 13),
        ),
        value: forceTvMode,
        onChanged: _toggleForceTvMode,
        activeThumbColor: AppVisualTokens.primaryBlue,
      ),
    );
  }

  Widget _buildReturnHomeAction(BuildContext context) {
    if (_forceTvMode.value == (initialUiMode == BiliUiMode.tv)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: AppGlassButton(
          onPressed: _switchHome,
          icon: Icons.home_rounded,
          label: '返回首页并切换',
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF8B9098),
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  bool _isAuthenticatedCookieSet(Map<String, String> cookies) {
    return (cookies['SESSDATA'] ?? '').isNotEmpty &&
        (cookies['bili_jct'] ?? '').isNotEmpty;
  }
}
