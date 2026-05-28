import 'package:flutter/services.dart';

final class BiliPlatformInfo {
  BiliPlatformInfo._();

  static final instance = BiliPlatformInfo._();
  static const MethodChannel _channel = MethodChannel(
    'dev.ikaros.bilibili_player/platform',
  );

  bool? _cachedIsTv;

  Future<bool> isTv() async {
    if (_cachedIsTv != null) {
      return _cachedIsTv!;
    }
    try {
      final result = await _channel.invokeMethod<bool>('isTv');
      _cachedIsTv = result ?? false;
      return _cachedIsTv!;
    } on MissingPluginException {
      _cachedIsTv = false;
      return false;
    } on PlatformException {
      _cachedIsTv = false;
      return false;
    }
  }
}
