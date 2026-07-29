import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/bili/common/services/bili_platform_info.dart';

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

SystemUiOverlayStyle appSystemUiStyleForBrightness(Brightness brightness) {
  return brightness == Brightness.dark
      ? biliDarkSurfaceSystemUiStyle
      : biliAppSystemUiStyle;
}

SystemUiOverlayStyle playbackSystemUiStyleForBrightness(Brightness brightness) {
  return biliDarkSurfaceSystemUiStyle.copyWith(
    systemNavigationBarIconBrightness: brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark,
  );
}

int _preferredOrientationGeneration = 0;
bool _usesAppOrientationPolicy = true;

Future<void> setBiliPreferredOrientations(
  List<DeviceOrientation> orientations,
) async {
  _usesAppOrientationPolicy = false;
  _preferredOrientationGeneration += 1;
  await _applyBiliPreferredOrientations(orientations);
}

Future<void> _applyBiliPreferredOrientations(
  List<DeviceOrientation> orientations,
) async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }
  await SystemChrome.setPreferredOrientations(orientations);
}

typedef BiliAutoRotateReader = Future<bool> Function();

@visibleForTesting
Future<List<DeviceOrientation>> resolveBiliAppPreferredOrientations({
  BiliAutoRotateReader? readAutoRotateEnabled,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return biliAppDefaultOrientations;
  }

  final autoRotateEnabled =
      await (readAutoRotateEnabled ??
          BiliPlatformInfo.instance.isAutoRotateEnabled)();
  return autoRotateEnabled
      ? biliAppDefaultOrientations
      : biliPortraitOrientations;
}

Future<void> setBiliAppPreferredOrientations({
  BiliAutoRotateReader? readAutoRotateEnabled,
}) async {
  _usesAppOrientationPolicy = true;
  await _refreshBiliAppPreferredOrientations(
    readAutoRotateEnabled: readAutoRotateEnabled,
  );
}

Future<void> refreshBiliAppPreferredOrientationsIfActive({
  BiliAutoRotateReader? readAutoRotateEnabled,
}) async {
  if (!_usesAppOrientationPolicy) {
    return;
  }
  await _refreshBiliAppPreferredOrientations(
    readAutoRotateEnabled: readAutoRotateEnabled,
  );
}

Future<void> _refreshBiliAppPreferredOrientations({
  BiliAutoRotateReader? readAutoRotateEnabled,
}) async {
  final generation = ++_preferredOrientationGeneration;
  final orientations = await resolveBiliAppPreferredOrientations(
    readAutoRotateEnabled: readAutoRotateEnabled,
  );
  if (generation != _preferredOrientationGeneration ||
      !_usesAppOrientationPolicy) {
    return;
  }
  await _applyBiliPreferredOrientations(orientations);
}

Future<void> setBiliSystemUiMode(SystemUiMode systemUiMode) async {
  if (systemUiMode == SystemUiMode.edgeToEdge) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: biliVisibleSystemOverlays,
    );
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.restoreSystemUIOverlays();
    return;
  }

  await SystemChrome.setEnabledSystemUIMode(systemUiMode);
}

void setBiliSystemUiOverlayStyle(SystemUiOverlayStyle overlayStyle) {
  SystemChrome.setSystemUIOverlayStyle(overlayStyle);
}
