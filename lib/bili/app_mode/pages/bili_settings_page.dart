import 'dart:async';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/app/design/app_visual_theme.dart';
import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/app/design/app_theme_controller.dart';
import 'package:vesper_media/app/system_presentation.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_logout_service.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/common/services/bili_ui_mode_resolver.dart';
import 'package:vesper_media/bili/common/widgets/bili_glass_sheet.dart';
import 'package:vesper_media/download/download.dart';
import 'package:vesper_media/app/home_page.dart';
import 'package:vesper_media/main.dart';

class BiliSettingsPage extends StatefulWidget {
  const BiliSettingsPage({
    super.key,
    this.appSettings,
    this.client,
    this.sessionStore,
    this.offlineController,
  });

  final AppSettingsStore? appSettings;
  final BiliClient? client;
  final BiliSessionStore? sessionStore;
  final BiliOfflineDownloadController? offlineController;

  @override
  State<BiliSettingsPage> createState() => _BiliSettingsPageState();
}

class _BiliSettingsPageState extends State<BiliSettingsPage> {
  late final AppSettingsStore _appSettings;
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
    _appSettings = widget.appSettings ?? const AppSettingsStore();
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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
        transitionDuration: AppVisualTokens.motionDuration(
          context,
          AppVisualTokens.overlayDuration,
        ),
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
      mode == BiliUiMode.tv
          ? biliTvSystemUiStyle
          : appSystemUiStyleForBrightness(_preferredAppBrightness()),
    );
  }

  Brightness _preferredAppBrightness() {
    return switch (AppThemeScope.of(context).preference) {
      AppThemePreference.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      AppThemePreference.light => Brightness.light,
      AppThemePreference.dark => Brightness.dark,
    };
  }

  Future<void> _showThemePicker() async {
    final controller = AppThemeScope.of(context);
    await showBiliGlassSheet<void>(
      context: context,
      appearance: BiliGlassSheetAppearance.readable,
      maxContentHeightFactor: 0.62,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
              child: Text(
                '外观',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            AppGroupedSurface(
              children: [
                for (final preference in AppThemePreference.values)
                  AppSettingsRow(
                    icon: _themePreferenceIcon(preference),
                    title: _themePreferenceLabel(preference),
                    subtitle: _themePreferenceDescription(preference),
                    trailing: controller.preference == preference
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppVisualTokens.primaryBlue,
                          )
                        : const SizedBox(width: 24),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_setThemePreference(preference));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Future<void> _setThemePreference(AppThemePreference preference) async {
    try {
      await AppThemeScope.of(context).setPreference(preference);
    } catch (error) {
      if (mounted) {
        _showMessage('保存主题失败：$error');
      }
    }
  }

  Future<void> _openOfflineCache() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OfflineCachePage(controller: _offlineController, client: _client),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return AppGlassScaffold(
      backgroundColor: visualTheme.background,
      statusBarStyle: GlassStatusBarStyle.auto,
      extendBody: false,
      appBar: GlassAppBar(
        centerTitle: false,
        title: Text(
          '设置',
          style: TextStyle(
            color: visualTheme.textPrimary,
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
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const AppSectionLabel('外观与显示'),
        AppGroupedSurface(
          children: [
            AppSettingsRow(
              icon: _themePreferenceIcon(AppThemeScope.of(context).preference),
              title: '外观',
              subtitle: _themePreferenceLabel(
                AppThemeScope.of(context).preference,
              ),
              onTap: _showThemePicker,
            ),
            SignalBuilder(builder: _buildDisplayModeRow),
          ],
        ),
        SignalBuilder(builder: _buildReturnHomeAction),
        const AppSectionLabel('Bilibili 账号'),
        AppGroupedSurface(children: [SignalBuilder(builder: _buildAccountRow)]),
        const AppSectionLabel('离线数据'),
        AppGroupedSurface(
          children: [
            AppSettingsRow(
              icon: Icons.download_done_rounded,
              title: '离线缓存',
              subtitle: '管理下载、存储占用和导出内容',
              onTap: () => unawaited(_openOfflineCache()),
            ),
          ],
        ),
        const AppSectionLabel('关于'),
        const AppGroupedSurface(
          children: [
            AppSettingsRow(
              icon: Icons.play_circle_outline_rounded,
              title: 'Vesper',
              subtitle: '版本 1.2.0',
              trailing: SizedBox(width: 24),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAccountRow(BuildContext context) {
    final loggedIn = _hasAuthenticatedSession.value;
    final loggingOut = _loggingOut.value;
    return AppSettingsRow(
      icon: loggedIn
          ? Icons.account_circle_rounded
          : Icons.account_circle_outlined,
      iconColor: AppVisualTokens.biliSourcePink,
      title: loggedIn ? '已登录' : '未登录',
      subtitle: loggedIn ? '登录信息仅保存在本机' : '可在“我的”页面扫码登录',
      trailing: loggedIn
          ? TextButton(
              onPressed: loggingOut ? null : _confirmLogout,
              child: loggingOut
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('退出'),
            )
          : const SizedBox(width: 24),
    );
  }

  Widget _buildDisplayModeRow(BuildContext context) {
    final forceTvMode = _forceTvMode.value;
    return AppSettingsRow(
      icon: Icons.tv_rounded,
      title: '强制 TV 模式',
      subtitle: forceTvMode ? '返回首页后切换为 TV 界面' : '根据设备自动选择界面',
      onTap: () => unawaited(_toggleForceTvMode(!forceTvMode)),
      trailing: Switch(value: forceTvMode, onChanged: _toggleForceTvMode),
    );
  }

  Widget _buildReturnHomeAction(BuildContext context) {
    if (_forceTvMode.value == (initialUiMode == BiliUiMode.tv)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: AppGlassButton(
          onPressed: _switchHome,
          icon: Icons.home_rounded,
          label: '返回首页并切换',
        ),
      ),
    );
  }

  bool _isAuthenticatedCookieSet(Map<String, String> cookies) {
    return (cookies['SESSDATA'] ?? '').isNotEmpty &&
        (cookies['bili_jct'] ?? '').isNotEmpty;
  }
}

String _themePreferenceLabel(AppThemePreference preference) {
  return switch (preference) {
    AppThemePreference.system => '跟随系统',
    AppThemePreference.light => '浅色',
    AppThemePreference.dark => '深色',
  };
}

String _themePreferenceDescription(AppThemePreference preference) {
  return switch (preference) {
    AppThemePreference.system => '随设备的外观设置自动切换',
    AppThemePreference.light => '始终使用银雾浅色界面',
    AppThemePreference.dark => '始终使用石墨深色界面',
  };
}

IconData _themePreferenceIcon(AppThemePreference preference) {
  return switch (preference) {
    AppThemePreference.system => Icons.brightness_auto_rounded,
    AppThemePreference.light => Icons.light_mode_rounded,
    AppThemePreference.dark => Icons.dark_mode_rounded,
  };
}
