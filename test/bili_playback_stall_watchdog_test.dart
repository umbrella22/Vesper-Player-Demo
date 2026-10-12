import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_media/media/playback/media_playback_stall_watchdog.dart';

void main() {
  final playing = const VesperPlayerSnapshot.initial().copyWith(
    playbackState: VesperPlaybackState.playing,
  );
  test(
    'stopped position needs 10 seconds; progress and seek reset the interval',
    () {
      final watchdog = MediaPlaybackStallWatchdog();
      MediaPlaybackStallReason? at(int second, VesperPlayerSnapshot snapshot) =>
          watchdog.observe(
            snapshot: snapshot,
            now: Duration(seconds: second),
            eligible: true,
          );
      expect(at(0, playing), isNull);
      expect(at(9, playing), isNull);
      expect(at(10, playing), MediaPlaybackStallReason.positionStopped);
      watchdog.reset();
      expect(at(20, playing), isNull);
      expect(at(29, playing), isNull);
      final moved = playing.copyWith(
        timeline: VesperTimeline(
          kind: VesperTimelineKind.vod,
          isSeekable: true,
          seekableRange: null,
          liveEdgeMs: null,
          positionMs: 1,
          durationMs: 60000,
        ),
      );
      expect(at(29, moved), isNull);
      expect(at(30, moved), isNull);
      expect(at(39, moved), MediaPlaybackStallReason.positionStopped);
    },
  );
  test('buffering uses 30 seconds and resets when playback advances', () {
    final watchdog = MediaPlaybackStallWatchdog();
    final buffering = playing.copyWith(isBuffering: true);
    expect(
      watchdog.observe(snapshot: buffering, now: Duration.zero, eligible: true),
      isNull,
    );
    expect(
      watchdog.observe(
        snapshot: buffering,
        now: const Duration(seconds: 29),
        eligible: true,
      ),
      isNull,
    );
    expect(
      watchdog.observe(
        snapshot: buffering,
        now: const Duration(seconds: 30),
        eligible: true,
      ),
      MediaPlaybackStallReason.bufferingTimeout,
    );
    expect(
      watchdog.observe(
        snapshot: playing,
        now: const Duration(seconds: 31),
        eligible: true,
      ),
      isNull,
    );
  });
  test(
    'pause, interruption, finished, disabled audio and ineligible sources reset observations',
    () {
      for (final snapshot in [
        playing.copyWith(
          playbackState: VesperPlaybackState.paused,
          isBuffering: true,
        ),
        playing.copyWith(isInterrupted: true),
        playing.copyWith(playbackState: VesperPlaybackState.finished),
        playing.copyWith(
          trackSelection: const VesperTrackSelectionSnapshot(
            audio: VesperTrackSelection.disabled(),
          ),
        ),
      ]) {
        final watchdog = MediaPlaybackStallWatchdog();
        watchdog.observe(snapshot: playing, now: Duration.zero, eligible: true);
        expect(
          watchdog.observe(
            snapshot: snapshot,
            now: const Duration(seconds: 40),
            eligible: true,
          ),
          isNull,
        );
        expect(
          watchdog.observe(
            snapshot: playing,
            now: const Duration(seconds: 41),
            eligible: true,
          ),
          isNull,
        );
        expect(
          watchdog.observe(
            snapshot: playing,
            now: const Duration(seconds: 90),
            eligible: false,
          ),
          isNull,
        );
      }
    },
  );
}
