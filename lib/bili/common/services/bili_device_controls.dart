import 'package:flutter/services.dart';

final class BiliDeviceControls {
  const BiliDeviceControls._();

  static const instance = BiliDeviceControls._();
  static const MethodChannel _channel = MethodChannel(
    'dev.ikaros.bilibili_player/device_controls',
  );

  Future<double?> getBrightness() => _invokeRatio('getBrightness');

  Future<double?> setBrightness(double value) {
    return _invokeRatio('setBrightness', value: value);
  }

  Future<double?> getVolume() => _invokeRatio('getVolume');

  Future<double?> setVolume(double value) {
    return _invokeRatio('setVolume', value: value);
  }

  Future<double?> _invokeRatio(String method, {double? value}) async {
    try {
      final result = await _channel.invokeMethod<double>(
        method,
        value == null
            ? null
            : <String, Object?>{'value': value.clamp(0, 1).toDouble()},
      );
      return result?.clamp(0, 1).toDouble();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
