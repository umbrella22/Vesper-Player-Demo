import 'dart:async';
import 'dart:ui' as ui;

import 'package:vesper_media/bili/bili.dart';
import 'package:vesper_media/download/download.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/design/app_glass_startup_policy.dart';
import 'app/services/app_settings_store.dart';
import 'app/services/bili_ui_mode_controller.dart';
import 'app/system_presentation.dart';

const _appSettings = AppSettingsStore();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setBiliSystemUiMode(SystemUiMode.edgeToEdge);

  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final uiModeController = BiliUiModeController(
    resolver: BiliUiModeResolver(appSettings: _appSettings),
  );
  // Composition root: the app owns a single BiliClient and offline download
  // controller and injects them down the tree, so production code paths do
  // not fall back to the global singletons.
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
      child: VesperApp(
        appSettings: _appSettings,
        initialThemePreference: themePreference,
        uiModeController: uiModeController,
        client: biliClient,
        offlineController: offlineController,
      ),
    ),
  );
}
