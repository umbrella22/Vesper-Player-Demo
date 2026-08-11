import 'package:flutter/services.dart';
import 'package:vesper_media/media/media.dart';

/// 播放页壳的设备控制实现：亮度/音量走平台通道。
final class BiliStageDeviceControls implements MediaPlayerDeviceControls {
  const BiliStageDeviceControls();

  @override
  Future<double?> currentBrightnessRatio() {
    return BiliDeviceControls.instance.getBrightness();
  }

  @override
  Future<double?> setBrightnessRatio(double ratio) {
    return BiliDeviceControls.instance.setBrightness(ratio);
  }

  @override
  Future<double?> currentVolumeRatio() {
    return BiliDeviceControls.instance.getVolume();
  }

  @override
  Future<double?> setVolumeRatio(double ratio) {
    return BiliDeviceControls.instance.setVolume(ratio);
  }
}

final class BiliDeviceControls {
  const BiliDeviceControls._();

  static const instance = BiliDeviceControls._();
  static const MethodChannel _channel = MethodChannel(
    'dev.ikaros.vesper_player/device_controls',
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
