import 'bili_app_settings.dart';
import 'bili_platform_info.dart';

enum BiliUiMode { phone, tv }

final class BiliUiModeResolver {
  BiliUiModeResolver({
    BiliPlatformInfo? platformInfo,
    BiliAppSettings? appSettings,
  }) : _platformInfo = platformInfo ?? BiliPlatformInfo.instance,
       _appSettings = appSettings ?? const BiliAppSettings();

  final BiliPlatformInfo _platformInfo;
  final BiliAppSettings _appSettings;

  BiliUiMode? _currentMode;

  BiliUiMode? get currentMode => _currentMode;

  Future<BiliUiMode> resolveEffectiveUiMode() async {
    final forceTvMode = await _appSettings.getForceTvMode();
    if (forceTvMode) {
      _currentMode = BiliUiMode.tv;
      return BiliUiMode.tv;
    }
    final isTv = await _platformInfo.isTv();
    _currentMode = isTv ? BiliUiMode.tv : BiliUiMode.phone;
    return _currentMode!;
  }

  Future<void> setForceTvMode(bool value) async {
    await _appSettings.setForceTvMode(value);
  }

  Future<bool> getForceTvMode() async {
    return _appSettings.getForceTvMode();
  }
}
