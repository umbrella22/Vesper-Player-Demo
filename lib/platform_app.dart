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
import 'app/system_presentation.dart';
import 'bili/common/services/bili_client.dart';
import 'bili/common/services/bili_platform_info.dart';
import 'bili/common/services/bili_ui_mode_resolver.dart';
import 'download/services/offline_download_controller.dart';

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
    this.uiModeController,
    this.client,
    this.offlineController,
  });

  final AppSettingsStore appSettings;
  final AppThemePreference initialThemePreference;
  final BiliUiModeController? uiModeController;
  final BiliClient? client;
  final BiliOfflineDownloadController? offlineController;

  @override
  State<PlatformApp> createState() => _PlatformAppState();
}

class _PlatformAppState extends State<PlatformApp> {
  late final BiliUiModeController _uiModeController;

  @override
  void initState() {
    super.initState();
    _uiModeController =
        widget.uiModeController ??
        BiliUiModeController(
          resolver: BiliUiModeResolver(appSettings: widget.appSettings),
        );
  }

  @override
  void dispose() {
    if (widget.uiModeController == null) {
      _uiModeController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VesperApp(
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
    );
  }
}

Future<void> runPlatformApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setBiliSystemUiMode(SystemUiMode.edgeToEdge);

  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final uiModeController = BiliUiModeController(
    resolver: BiliUiModeResolver(appSettings: _appSettings),
  );
  final biliClient = BiliClient();
  final offlineController = BiliOfflineDownloadController(client: biliClient);
  final modeFuture = uiModeController.refresh();
  final qualityFuture = _appSettings.getGlassQuality();
  final themeFuture = _appSettings.getThemePreference();
  final hcppFuture = isAndroid
      ? BiliPlatformInfo.instance.isHcppPlatformSupported()
      : Future<bool>.value(true);

  await modeFuture;
  final savedGlassQuality = await qualityFuture;
  final themePreference = await themeFuture;
  final isHcppPlatformSupported = await hcppFuture;
  final glassPolicy = AppGlassStartupPolicy.resolve(
    platform: defaultTargetPlatform,
    isHcppPlatformSupported: isHcppPlatformSupported,
    areShaderFiltersSupported: ui.ImageFilter.isShaderFilterSupported,
    savedQuality: savedGlassQuality,
  );

  final systemBrightness = ui.PlatformDispatcher.instance.platformBrightness;
  final appBrightness = switch (themePreference) {
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
    await LiquidGlassWidgets.initialize();
  }

  runApp(
    LiquidGlassWidgets.wrap(
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
        initialThemePreference: themePreference,
        uiModeController: uiModeController,
        client: biliClient,
        offlineController: offlineController,
      ),
    ),
  );
}
