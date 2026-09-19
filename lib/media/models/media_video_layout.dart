import 'package:vesper_player/vesper_player.dart';

/// Native display size includes rotation and pixel aspect correction. Track
/// dimensions and metadata are provisional hints for the currently loaded entry.
double resolveMediaVideoAspectRatio({
  VesperPlayerSnapshot? snapshot,
  List<VesperMediaTrack> declaredTracks = const [],
  double? declaredAspectRatio,
}) {
  final presentation = snapshot?.videoPresentation;
  if (presentation != null) {
    final ratio = _dimensionRatio(
      presentation.displayWidth,
      presentation.displayHeight,
    );
    if (ratio != null) return ratio;
  }

  final tracks =
      snapshot?.trackCatalog.videoTracks ?? const <VesperMediaTrack>[];
  final effectiveId = snapshot?.effectiveVideoTrackId;
  if (effectiveId != null) {
    for (final track in tracks) {
      if (track.id == effectiveId) {
        final ratio = _dimensionRatio(track.width, track.height);
        if (ratio != null) return ratio;
      }
    }
  }
  return _sharedTrackRatio(tracks) ??
      _sharedTrackRatio(declaredTracks) ??
      (declaredAspectRatio != null &&
              declaredAspectRatio.isFinite &&
              declaredAspectRatio > 0
          ? declaredAspectRatio
          : 16 / 9);
}

double? _dimensionRatio(num? width, num? height) {
  if (width == null ||
      height == null ||
      !width.isFinite ||
      !height.isFinite ||
      width <= 0 ||
      height <= 0) {
    return null;
  }
  final ratio = width / height;
  return ratio.isFinite && ratio > 0 ? ratio : null;
}

double? _sharedTrackRatio(Iterable<VesperMediaTrack> tracks) {
  double? result;
  for (final track in tracks) {
    if (track.kind != VesperMediaTrackKind.video) continue;
    final ratio = _dimensionRatio(track.width, track.height);
    if (ratio == null) continue;
    // The catalog can contain multiple qualities, but ambiguous orientations
    // must wait for an effective track or native presentation dimensions.
    if (result != null && (ratio - result).abs() > 0.001) return null;
    result = ratio;
  }
  return result;
}
