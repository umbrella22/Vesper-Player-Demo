import 'dart:async';

import 'package:bilibili_player/bili/bili.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
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

  await LiquidGlassWidgets.initialize();

  runApp(
    LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      // ignore: experimental_member_use
      adaptiveConfig: GlassAdaptiveScopeConfig(
        initialQuality: savedGlassQuality,
        onQualityChanged: (_, quality) {
          unawaited(appSettings.setGlassQuality(quality));
        },
      ),
      child: const BilibiliPlayerApp(),
    ),
  );
}

Future<BiliUiMode> refreshUiMode() async {
  _resolvedUiMode = await _modeResolver.resolveEffectiveUiMode();
  return _resolvedUiMode;
}
