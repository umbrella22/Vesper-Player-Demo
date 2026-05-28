import 'package:bilibili_player/bili/bili.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';

final _modeResolver = BiliUiModeResolver();
BiliUiMode _resolvedUiMode = BiliUiMode.phone;

BiliUiMode get initialUiMode => _resolvedUiMode;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),
  );

  _resolvedUiMode = await _modeResolver.resolveEffectiveUiMode();

  runApp(const BilibiliPlayerApp());
}

Future<BiliUiMode> refreshUiMode() async {
  _resolvedUiMode = await _modeResolver.resolveEffectiveUiMode();
  return _resolvedUiMode;
}
