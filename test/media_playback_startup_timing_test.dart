import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/media/diagnostics/media_playback_startup_timing.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  VesperPlaybackDiagnosticsSnapshot evidence(
    int epoch, {
    bool frame = true,
  }) => VesperPlaybackDiagnosticsSnapshot(
    playbackEpoch: epoch,
    firstFrame: frame
        ? VesperFirstFrameObservation(
            playbackEpoch: epoch,
            elapsedSinceLoadStartMs: 120,
            kind: VesperFirstFrameObservationKind.avPlayerLayerReadyForDisplay,
            mediaPositionMs: 90000,
          )
        : null,
  );

  test(
    'retained first frame uses receipt time independently of media/native clocks',
    () {
      var now = Duration.zero;
      final timing = MediaPlaybackStartupTiming(elapsed: () => now);
      timing.markPushed();
      timing.markResolveStarted();
      now = const Duration(milliseconds: 300);
      timing.markSourceReady();
      timing.bindController('player');
      timing.observe('player', evidence(1, frame: false));
      expect(timing.firstFrameReceived, isNull);
      now = const Duration(milliseconds: 700);
      timing.observe('player', evidence(1));
      now = const Duration(seconds: 2);
      timing.observe('player', evidence(1));
      expect(timing.firstFrameReceived, const Duration(milliseconds: 700));
      expect(timing.firstFrame?.elapsedSinceLoadStartMs, 120);
      expect(timing.firstFrame?.mediaPositionMs, 90000);
    },
  );

  test(
    'retry epoch discards the old frame and cannot claim initial tap timing',
    () {
      final timing = MediaPlaybackStartupTiming();
      timing.bindController('player');
      timing.observe('player', evidence(1, frame: false));
      timing.observe('player', evidence(2, frame: false));
      timing.observe('player', evidence(1));
      expect(timing.firstFrame, isNull);
      timing.observe('player', evidence(2));
      expect(timing.firstFrame?.playbackEpoch, 2);
      expect(timing.firstFrameReceived, isNull);
    },
  );

  test(
    'replaced controllers and explicitly changed sources cannot contaminate tap timing',
    () {
      final timing = MediaPlaybackStartupTiming();
      timing.bindController('old');
      timing.bindController('new');
      timing.observe('old', evidence(40));
      expect(timing.firstFrame, isNull);
      timing.observe('new', evidence(1));
      expect(timing.firstFrame?.playbackEpoch, 1);
      expect(timing.firstFrameReceived, isNull);

      final switched = MediaPlaybackStartupTiming();
      switched.bindController('player');
      switched.endNavigationAttempt();
      switched.observe('player', evidence(1));
      expect(switched.firstFrameReceived, isNull);
    },
  );

  test('no observation and mismatched frame epochs never become successes', () {
    final timing = MediaPlaybackStartupTiming();
    timing.bindController('player');
    timing.observe('player', null);
    timing.observe(
      'player',
      const VesperPlaybackDiagnosticsSnapshot(playbackEpoch: 0),
    );
    timing.observe(
      'player',
      VesperPlaybackDiagnosticsSnapshot(
        playbackEpoch: 2,
        firstFrame: evidence(1).firstFrame,
      ),
    );
    expect(timing.firstFrame, isNull);
    expect(timing.firstFrameReceived, isNull);
  });
}
