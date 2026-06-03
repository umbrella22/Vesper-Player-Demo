import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const biliAppDefaultOrientations = <DeviceOrientation>[];

const biliPortraitOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
];

const biliLandscapeOrientations = <DeviceOrientation>[
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

const biliVisibleSystemOverlays = <SystemUiOverlay>[
  SystemUiOverlay.top,
  SystemUiOverlay.bottom,
];

const biliAppSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

const biliDarkSurfaceSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

const biliTvSystemUiStyle = biliDarkSurfaceSystemUiStyle;

Future<void> setBiliPreferredOrientations(
  List<DeviceOrientation> orientations,
) async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }
  await SystemChrome.setPreferredOrientations(orientations);
}

Future<void> setBiliSystemUiMode(SystemUiMode systemUiMode) async {
  if (systemUiMode == SystemUiMode.edgeToEdge) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: biliVisibleSystemOverlays,
    );
    return;
  }

  await SystemChrome.setEnabledSystemUIMode(systemUiMode);
}

void setBiliSystemUiOverlayStyle(SystemUiOverlayStyle overlayStyle) {
  SystemChrome.setSystemUIOverlayStyle(overlayStyle);
}
