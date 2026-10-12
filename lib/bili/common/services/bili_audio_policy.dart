import '../models/bili_models.dart';

/// Explicit user intent. Automatic recovery is deliberately session-only.
enum BiliAudioPolicyOverride { automatic, allowDolby, blockDolby }

enum BiliAudioPolicyReason { unrestricted, override, quirk, watchdog }

final class BiliAudioQuirk {
  const BiliAudioQuirk({
    required this.brandPrefix,
    required this.model,
    this.modelIsPrefix = false,
  });
  final String brandPrefix;
  final String model;
  final bool modelIsPrefix;

  bool matches(String brand, String deviceModel) {
    final normalizedBrand = brand.trim().toLowerCase();
    final normalizedModel = deviceModel.trim().toLowerCase();
    if (normalizedBrand.isEmpty ||
        normalizedModel.isEmpty ||
        brandPrefix.isEmpty ||
        model.isEmpty) {
      return false;
    }
    return normalizedBrand.startsWith(brandPrefix.toLowerCase()) &&
        (modelIsPrefix
            ? normalizedModel.startsWith(model.toLowerCase())
            : normalizedModel == model.toLowerCase());
  }
}

final class BiliAudioQuirkTable {
  const BiliAudioQuirkTable({this.entries = const []});
  // Add only verified brand/model pairs, never an entire unverified brand.
  final List<BiliAudioQuirk> entries;
  bool blocksDolby(String brand, String model) =>
      entries.any((entry) => entry.matches(brand, model));
}

final class BiliAudioPolicy {
  const BiliAudioPolicy({
    this.allowDolby = true,
    this.reason = BiliAudioPolicyReason.unrestricted,
  });
  final bool allowDolby;
  final BiliAudioPolicyReason reason;
  bool get allowFlac => true;

  static BiliAudioPolicy resolve({
    required BiliAudioPolicyOverride override,
    required String brand,
    required String model,
    BiliAudioQuirkTable quirks = const BiliAudioQuirkTable(),
    bool recoveryAttemptedThisSession = false,
  }) {
    if (override != BiliAudioPolicyOverride.automatic) {
      return BiliAudioPolicy(
        allowDolby: override == BiliAudioPolicyOverride.allowDolby,
        reason: BiliAudioPolicyReason.override,
      );
    }
    if (recoveryAttemptedThisSession) {
      return const BiliAudioPolicy(
        allowDolby: false,
        reason: BiliAudioPolicyReason.watchdog,
      );
    }
    if (quirks.blocksDolby(brand, model)) {
      return const BiliAudioPolicy(
        allowDolby: false,
        reason: BiliAudioPolicyReason.quirk,
      );
    }
    return const BiliAudioPolicy();
  }

  BiliDashManifestData filter(BiliDashManifestData manifest) {
    if (allowDolby) return manifest;
    final audio = manifest.audioStreams
        .where((stream) => !isDolbyStream(stream))
        .toList(growable: false);
    // A policy must not turn an audio-bearing source into silent video.
    return audio.isEmpty ? manifest : manifest.copyWith(audioStreams: audio);
  }

  String diagnosticLabel(
    BiliDashManifestData original,
    BiliDashManifestData filtered,
  ) {
    if (allowDolby) return '';
    final keptDolby = filtered.audioStreams.any(isDolbyStream);
    return 'audio-policy=dolby-blocked(${reason.name})'
        '${keptDolby ? "; filter-skipped=no-alternative" : ""}';
  }

  static bool isDolbyStream(BiliDashStream stream) =>
      const {30250, 30255}.contains(stream.id) || isDolbyCodec(stream.codecs);

  static bool isDolbyCodec(String? codec) {
    final value = codec?.toLowerCase() ?? '';
    return value.contains('ec-3') ||
        value.contains('eac3') ||
        value.contains('e-ac-3');
  }
}
