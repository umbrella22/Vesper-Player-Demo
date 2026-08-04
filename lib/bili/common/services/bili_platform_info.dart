import 'package:flutter/services.dart';

final class BiliPlatformInfo {
  BiliPlatformInfo._();

  static final instance = BiliPlatformInfo._();
  static const MethodChannel _channel = MethodChannel(
    'dev.ikaros.vesper_player/platform',
  );

  bool? _cachedIsTv;
  bool? _cachedIsTablet;

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

  Future<bool> isTablet() async {
    if (_cachedIsTablet != null) {
      return _cachedIsTablet!;
    }
    try {
      final result = await _channel.invokeMethod<bool>('isTablet');
      _cachedIsTablet = result ?? false;
      return _cachedIsTablet!;
    } on MissingPluginException {
      _cachedIsTablet = false;
      return false;
    } on PlatformException {
      _cachedIsTablet = false;
      return false;
    }
  }

  Future<bool> isAutoRotateEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAutoRotateEnabled') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isHcppPlatformSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isHcppPlatformSupported') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> shouldPreferTextureViewForPlayback() async {
    try {
      return await _channel.invokeMethod<bool>(
            'shouldPreferTextureViewForPlayback',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
