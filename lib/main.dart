import 'package:bilibili_player/bili/bili.dart';
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

  runApp(const BilibiliPlayerApp());
}

Future<BiliUiMode> refreshUiMode() async {
  _resolvedUiMode = await _modeResolver.resolveEffectiveUiMode();
  return _resolvedUiMode;
}
