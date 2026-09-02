import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/design/app_glass_startup_policy.dart';
import 'app/home_page.dart';
import 'app/services/app_settings_store.dart';
import 'app/services/bili_ui_mode_controller.dart';
import 'app/services/danmaku_settings_controller.dart';
import 'app/system_presentation.dart';
import 'bili/common/services/bili_client.dart';
import 'bili/common/services/bili_platform_info.dart';
import 'bili/common/services/bili_ui_mode_resolver.dart';
import 'download/services/offline_download_controller.dart';
import 'danmaku/danmaku.dart';

const _appSettings = AppSettingsStore();

/// 当前仓库选择的单一供应商应用。
///
/// 二开项目在这个文件中替换客户端、首页和可选的 TV/系统呈现接线；
/// `main.dart`、`VesperApp` 和 `lib/media/` 无需改动。
class PlatformApp extends StatefulWidget {
  const PlatformApp({
    super.key,
    this.appSettings = const AppSettingsStore(),
    this.initialThemePreference = AppThemePreference.system,
    this.initialDanmakuSettings = const BiliDanmakuSettings(),
    this.uiModeController,
    this.danmakuSettingsController,
    this.client,
    this.offlineController,
  });

  final AppSettingsStore appSettings;
  final AppThemePreference initialThemePreference;
  final BiliDanmakuSettings initialDanmakuSettings;
  final BiliUiModeController? uiModeController;
  final DanmakuSettingsController? danmakuSettingsController;
  final BiliClient? client;
  final BiliOfflineDownloadController? offlineController;

  @override
  State<PlatformApp> createState() => _PlatformAppState();
}

class _PlatformAppState extends State<PlatformApp> {
  late final BiliUiModeController _uiModeController;
  late final DanmakuSettingsController _danmakuSettingsController;

  @override
  void initState() {
    super.initState();
    _uiModeController =
        widget.uiModeController ??
        BiliUiModeController(
          resolver: BiliUiModeResolver(appSettings: widget.appSettings),
        );
    _danmakuSettingsController =
        widget.danmakuSettingsController ??
        DanmakuSettingsController(
          store: widget.appSettings,
          initialSettings: widget.initialDanmakuSettings,
        );
  }

  @override
  void dispose() {
    if (widget.uiModeController == null) {
      _uiModeController.dispose();
    }
    if (widget.danmakuSettingsController == null) {
      _danmakuSettingsController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DanmakuSettingsScope(
      controller: _danmakuSettingsController,
      child: VesperApp(
        appSettings: widget.appSettings,
        initialThemePreference: widget.initialThemePreference,
        host: VesperAppHost(
          tvModeListenable: _uiModeController.tvModeListenable,
          refreshPreferredOrientations:
              refreshBiliAppPreferredOrientationsIfActive,
          tvSystemUiStyle: biliTvSystemUiStyle,
          systemUiStyleForBrightness: appSystemUiStyleForBrightness,
          homeBuilder: (_) => HomePage(
            uiModeController: _uiModeController,
            client: widget.client,
            offlineController: widget.offlineController,
            appSettings: widget.appSettings,
          ),
        ),
      ),
    );
  }
}

const platformAppStartupFrameKey = ValueKey<String>(
  'platform-app-startup-frame',
);

const _startupStorageTimeout = Duration(seconds: 5);
const _startupPlatformTimeout = Duration(seconds: 5);
const _startupShaderTimeout = Duration(seconds: 5);

typedef PlatformAppLoader = Future<Widget> Function();

class PlatformAppBootstrap extends StatefulWidget {
  const PlatformAppBootstrap({super.key, this.appLoader});

  @visibleForTesting
  final PlatformAppLoader? appLoader;

  @override
  State<PlatformAppBootstrap> createState() => _PlatformAppBootstrapState();
}

class _PlatformAppBootstrapState extends State<PlatformAppBootstrap> {
  Widget? _configuredApp;
  bool _loadStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadStarted) {
        return;
      }
      _loadStarted = true;
      unawaited(_loadConfiguredApp());
    });
  }

  Future<void> _loadConfiguredApp() async {
    try {
      final loader = widget.appLoader;
      final Widget configuredApp;
      final bool shouldApplyPhoneSystemUi;
      if (loader != null) {
        configuredApp = await loader();
        shouldApplyPhoneSystemUi = false;
      } else {
        final result = await _createConfiguredApp();
        configuredApp = result.app;
        shouldApplyPhoneSystemUi = !result.isTvMode;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _configuredApp = configuredApp;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && shouldApplyPhoneSystemUi) {
          unawaited(_applyInitialSystemUiMode());
        }
      });
    } catch (error) {
      _logStartupFallback('app assembly', error);
      if (!mounted) {
        return;
      }
      setState(() {
        _configuredApp = PlatformApp(appSettings: _appSettings);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final configuredApp = _configuredApp;
    if (configuredApp != null) {
      return configuredApp;
    }

    final isDark =
        ui.PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    return Directionality(
      key: platformAppStartupFrameKey,
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: isDark ? const Color(0xFF111318) : const Color(0xFFF4F6F8),
        child: const Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
              color: Color(0xFF409EFF),
              strokeWidth: 3,
            ),
          ),
        ),
      ),
    );
  }
}

Future<({Widget app, bool isTvMode})> _createConfiguredApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final settingsFuture = _loadStartupSettings();
  final hcppFuture = _readHcppSupport(isAndroid: isAndroid);
  final settings = await settingsFuture;
  final uiModeController = BiliUiModeController(
    resolver: BiliUiModeResolver(appSettings: _appSettings),
  );
  try {
    await uiModeController
        .refresh(knownForceTvMode: settings.forceTvMode)
        .timeout(_startupPlatformTimeout);
  } catch (error) {
    _logStartupFallback('UI mode detection', error);
  }
  final isHcppPlatformSupported = await hcppFuture;
  var glassPolicy = AppGlassStartupPolicy.resolve(
    platform: defaultTargetPlatform,
    isHcppPlatformSupported: isHcppPlatformSupported,
    areShaderFiltersSupported: ui.ImageFilter.isShaderFilterSupported,
    savedQuality: settings.glassQuality,
  );

  final systemBrightness = ui.PlatformDispatcher.instance.platformBrightness;
  final appBrightness = switch (settings.themePreference) {
    AppThemePreference.system => systemBrightness,
    AppThemePreference.light => Brightness.light,
    AppThemePreference.dark => Brightness.dark,
  };
  setBiliSystemUiOverlayStyle(
    uiModeController.tvModeListenable.value
        ? biliTvSystemUiStyle
        : appSystemUiStyleForBrightness(appBrightness),
  );

  if (glassPolicy.shouldInitializeShaders) {
    try {
      await LiquidGlassWidgets.initialize().timeout(_startupShaderTimeout);
    } catch (error) {
      _logStartupFallback('glass shader initialization', error);
      glassPolicy = AppGlassStartupPolicy.resolve(
        platform: defaultTargetPlatform,
        isHcppPlatformSupported: false,
        areShaderFiltersSupported: false,
        savedQuality: null,
      );
    }
  }

  final biliClient = BiliClient();
  final offlineController = BiliOfflineDownloadController(client: biliClient);
  final app = LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    adaptiveQuality: true,
    // ignore: experimental_member_use
    adaptiveConfig: GlassAdaptiveScopeConfig(
      minQuality: GlassQuality.minimal,
      maxQuality: glassPolicy.maxQuality,
      initialQuality: glassPolicy.initialQuality,
      allowStepUp: glassPolicy.allowStepUp,
      onQualityChanged: glassPolicy.shouldPersistAdaptiveQuality
          ? (_, quality) {
              unawaited(_appSettings.setGlassQuality(quality));
            }
          : null,
    ),
    child: PlatformApp(
      appSettings: _appSettings,
      initialThemePreference: settings.themePreference,
      initialDanmakuSettings: settings.danmakuSettings,
      uiModeController: uiModeController,
      client: biliClient,
      offlineController: offlineController,
    ),
  );
  return (app: app, isTvMode: uiModeController.tvModeListenable.value);
}

Future<AppSettingsSnapshot> _loadStartupSettings() async {
  try {
    return await _appSettings.loadSnapshot().timeout(_startupStorageTimeout);
  } catch (error) {
    _logStartupFallback('settings load', error);
    return AppSettingsSnapshot.defaults;
  }
}

Future<bool> _readHcppSupport({required bool isAndroid}) async {
  if (!isAndroid) {
    return true;
  }
  try {
    return await BiliPlatformInfo.instance.isHcppPlatformSupported().timeout(
      _startupPlatformTimeout,
    );
  } catch (error) {
    _logStartupFallback('HCPP capability detection', error);
    return false;
  }
}

Future<void> _applyInitialSystemUiMode() async {
  try {
    await setBiliSystemUiMode(
      SystemUiMode.edgeToEdge,
    ).timeout(_startupPlatformTimeout);
  } catch (error) {
    _logStartupFallback('system UI setup', error);
  }
}

void _logStartupFallback(String stage, Object error) {
  debugPrint('[Startup] $stage failed: ${error.runtimeType}');
}

Future<void> runPlatformApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PlatformAppBootstrap());
  return Future<void>.value();
}
