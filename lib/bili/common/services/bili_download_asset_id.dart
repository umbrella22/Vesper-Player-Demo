import '../models/bili_models.dart';

/// Download selection fields encoded in a persisted Bilibili asset ID.
final class BiliDownloadAssetSelection {
  const BiliDownloadAssetSelection({
    required this.qualityId,
    required this.codecPreference,
  });

  final int qualityId;
  final BiliVideoCodecPreference codecPreference;
}

/// Parses only the selection fields owned by the Bilibili download protocol.
/// Video identity remains sourced from persisted download metadata.
BiliDownloadAssetSelection? tryParseBiliDownloadAssetSelection(String assetId) {
  final qualityMatch = RegExp(r'-q(\d+)-').firstMatch(assetId);
  final qualityId = qualityMatch == null
      ? null
      : int.tryParse(qualityMatch.group(1) ?? '');
  if (qualityId == null) {
    return null;
  }

  final codecPreference = switch (assetId) {
    final value when value.contains('-av1-') => BiliVideoCodecPreference.av1,
    final value when value.contains('-hevc-') => BiliVideoCodecPreference.hevc,
    final value when value.contains('-avc-') => BiliVideoCodecPreference.avc,
    _ => BiliVideoCodecPreference.automatic,
  };
  return BiliDownloadAssetSelection(
    qualityId: qualityId,
    codecPreference: codecPreference,
  );
}
