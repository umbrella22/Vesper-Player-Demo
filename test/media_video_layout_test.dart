import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/media/models/media_video_layout.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  const initial = VesperPlayerSnapshot.initial();
  const landscape = VesperMediaTrack(
    id: 'landscape',
    kind: VesperMediaTrackKind.video,
    width: 1920,
    height: 1080,
  );
  const portrait = VesperMediaTrack(
    id: 'portrait',
    kind: VesperMediaTrackKind.video,
    width: 720,
    height: 1280,
  );

  test('native display size overrides encoded dimensions after rotation', () {
    final snapshot = initial.copyWith(
      videoPresentation: const VesperVideoPresentation(
        displayWidth: 1080,
        displayHeight: 1920,
      ),
      effectiveVideoTrackId: 'landscape',
      trackCatalog: const VesperTrackCatalog(tracks: [landscape]),
    );
    expect(resolveMediaVideoAspectRatio(snapshot: snapshot), 9 / 16);
  });

  test('native display size preserves pixel aspect correction', () {
    final snapshot = initial.copyWith(
      videoPresentation: const VesperVideoPresentation(
        displayWidth: 1024,
        displayHeight: 576,
      ),
      trackCatalog: const VesperTrackCatalog(
        tracks: [
          VesperMediaTrack(
            id: 'pal',
            kind: VesperMediaTrackKind.video,
            width: 720,
            height: 576,
          ),
        ],
      ),
    );
    expect(resolveMediaVideoAspectRatio(snapshot: snapshot), 16 / 9);
  });

  test('effective track resolves a catalog with conflicting orientations', () {
    final snapshot = initial.copyWith(
      effectiveVideoTrackId: 'portrait',
      trackCatalog: const VesperTrackCatalog(tracks: [landscape, portrait]),
    );
    expect(resolveMediaVideoAspectRatio(snapshot: snapshot), 9 / 16);
    expect(
      resolveMediaVideoAspectRatio(
        snapshot: snapshot.copyWith(effectiveVideoTrackId: 'unknown'),
        declaredAspectRatio: 1,
      ),
      1,
    );
  });

  test('consistent declared qualities are a provisional ratio', () {
    expect(
      resolveMediaVideoAspectRatio(
        declaredTracks: const [
          portrait,
          VesperMediaTrack(
            id: 'portrait-hd',
            kind: VesperMediaTrackKind.video,
            width: 1080,
            height: 1920,
          ),
        ],
      ),
      9 / 16,
    );
    expect(
      resolveMediaVideoAspectRatio(
        declaredTracks: const [portrait, landscape],
        declaredAspectRatio: 4 / 3,
      ),
      4 / 3,
    );
  });

  test('unknown and invalid dimensions fall back without nonfinite layout', () {
    expect(resolveMediaVideoAspectRatio(), 16 / 9);
    for (final ratio in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        resolveMediaVideoAspectRatio(
          snapshot: initial.copyWith(
            videoPresentation: const VesperVideoPresentation(
              displayWidth: 0,
              displayHeight: 0,
            ),
          ),
          declaredTracks: const [
            VesperMediaTrack(id: 'unknown', kind: VesperMediaTrackKind.video),
            VesperMediaTrack(
              id: 'invalid',
              kind: VesperMediaTrackKind.video,
              width: 720,
              height: 0,
            ),
          ],
          declaredAspectRatio: ratio,
        ),
        16 / 9,
      );
    }
  });
}
