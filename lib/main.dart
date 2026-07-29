import 'dart:async';
import 'dart:ui' as ui;

import 'package:bilibili_player/bili/bili.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/design/app_glass_startup_policy.dart';
import 'app/system_presentation.dart';

final _modeResolver = BiliUiModeResolver();
BiliUiMode _resolvedUiMode = BiliUiMode.phone;

BiliUiMode get initialUiMode => _resolvedUiMode;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setBiliSystemUiMode(SystemUiMode.edgeToEdge);
  setBiliSystemUiOverlayStyle(biliAppSystemUiStyle);

  _resolvedUiMode = await _modeResolver.resolveEffectiveUiMode();

  const appSettings = BiliAppSettings();
  final savedGlassQuality = await appSettings.getGlassQuality();
  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final isHcppPlatformSupported =
      !isAndroid || await BiliPlatformInfo.instance.isHcppPlatformSupported();
  final glassPolicy = AppGlassStartupPolicy.resolve(
    platform: defaultTargetPlatform,
    isHcppPlatformSupported: isHcppPlatformSupported,
    areShaderFiltersSupported: ui.ImageFilter.isShaderFilterSupported,
    savedQuality: savedGlassQuality,
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
                unawaited(appSettings.setGlassQuality(quality));
              }
            : null,
      ),
      child: const BilibiliPlayerApp(),
    ),
  );
}

Future<BiliUiMode> refreshUiMode() async {
  _resolvedUiMode = await _modeResolver.resolveEffectiveUiMode();
  return _resolvedUiMode;
}
