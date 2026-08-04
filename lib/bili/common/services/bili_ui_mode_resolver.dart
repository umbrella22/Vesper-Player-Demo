import 'package:vesper_media/app/services/app_settings_store.dart';
import 'bili_platform_info.dart';

enum BiliUiMode { phone, tv }

final class BiliUiModeResolver {
  BiliUiModeResolver({
    BiliPlatformInfo? platformInfo,
    AppSettingsStore? appSettings,
  }) : _platformInfo = platformInfo ?? BiliPlatformInfo.instance,
       _appSettings = appSettings ?? const AppSettingsStore();

  final BiliPlatformInfo _platformInfo;
  final AppSettingsStore _appSettings;

  BiliUiMode? _currentMode;

  BiliUiMode? get currentMode => _currentMode;

  Future<BiliUiMode> resolveEffectiveUiMode() async {
    final forceTvMode = await _appSettings.getForceTvMode();
    if (forceTvMode) {
      _currentMode = BiliUiMode.tv;
      return BiliUiMode.tv;
    }
    final isTv = await _platformInfo.isTv();
    final isTablet = isTv ? false : await _platformInfo.isTablet();
    _currentMode = isTv || isTablet ? BiliUiMode.tv : BiliUiMode.phone;
    return _currentMode!;
  }

  Future<void> setForceTvMode(bool value) async {
    await _appSettings.setForceTvMode(value);
  }

  Future<bool> getForceTvMode() async {
    return _appSettings.getForceTvMode();
  }
}
