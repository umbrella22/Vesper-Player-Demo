import 'dart:async';
import 'dart:ui' as ui;

import 'package:vesper_media/bili/bili.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/design/app_glass_startup_policy.dart';
import 'app/services/app_settings_store.dart';
import 'app/system_presentation.dart';

const _appSettings = AppSettingsStore();
final _modeResolver = BiliUiModeResolver(appSettings: _appSettings);
BiliUiMode _resolvedUiMode = BiliUiMode.phone;
final ValueNotifier<bool> _tvMode = ValueNotifier<bool>(false);

BiliUiMode get initialUiMode => _resolvedUiMode;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setBiliSystemUiMode(SystemUiMode.edgeToEdge);

  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final modeFuture = _modeResolver.resolveEffectiveUiMode();
  final qualityFuture = _appSettings.getGlassQuality();
  final themeFuture = _appSettings.getThemePreference();
  final hcppFuture = isAndroid
      ? BiliPlatformInfo.instance.isHcppPlatformSupported()
      : Future<bool>.value(true);

  _resolvedUiMode = await modeFuture;
  _tvMode.value = _resolvedUiMode == BiliUiMode.tv;
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
    _tvMode.value
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
        tvModeListenable: _tvMode,
        initialTvMode: _tvMode.value,
      ),
    ),
  );
}

Future<BiliUiMode> refreshUiMode() async {
  _resolvedUiMode = await _modeResolver.resolveEffectiveUiMode();
  _tvMode.value = _resolvedUiMode == BiliUiMode.tv;
  return _resolvedUiMode;
}
