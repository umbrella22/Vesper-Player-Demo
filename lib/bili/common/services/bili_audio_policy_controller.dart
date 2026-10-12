import 'package:vesper_media/app/services/app_settings_store.dart';

import 'bili_audio_policy.dart';
import 'bili_platform_info.dart';

/// One device policy per app client. Recovery does not write user settings.
final class BiliAudioPolicyController {
  BiliAudioPolicyController({
    this.store,
    BiliPlatformInfo? platformInfo,
    BiliAudioPolicyOverride initialOverride = BiliAudioPolicyOverride.automatic,
    this.quirks = const BiliAudioQuirkTable(),
  }) : _platformInfo = platformInfo ?? BiliPlatformInfo.instance,
       _override = initialOverride;

  final AppSettingsStore? store;
  final BiliPlatformInfo _platformInfo;
  final BiliAudioQuirkTable quirks;
  BiliAudioPolicyOverride _override;
  bool _recoveryAttemptedThisSession = false;
  Future<({String brand, String model})>? _device;

  BiliAudioPolicyOverride get override => _override;
  bool get recoveryAttemptedThisSession => _recoveryAttemptedThisSession;

  Future<BiliAudioPolicy> resolve() async {
    // No device query is needed until a verified rule can use the identity.
    final device =
        quirks.entries.isEmpty || _override != BiliAudioPolicyOverride.automatic
        ? (brand: '', model: '')
        : await (_device ??= _readDevice());
    return BiliAudioPolicy.resolve(
      override: _override,
      brand: device.brand,
      model: device.model,
      quirks: quirks,
      recoveryAttemptedThisSession: _recoveryAttemptedThisSession,
    );
  }

  Future<({String brand, String model})> _readDevice() async {
    final values = await Future.wait([
      _platformInfo.deviceBrand(),
      _platformInfo.deviceModel(),
    ]);
    return (brand: values[0], model: values[1]);
  }

  bool recordRecoveryAttempt() {
    if (_recoveryAttemptedThisSession ||
        _override != BiliAudioPolicyOverride.automatic) {
      return false;
    }
    _recoveryAttemptedThisSession = true;
    return true;
  }

  Future<void> setOverride(BiliAudioPolicyOverride value) async {
    await store?.setAudioPolicyOverride(value);
    _override = value;
  }
}
