import 'package:vesper_player/vesper_player.dart';

/// App durations use the Dart clock. Native load duration is retained separately.
/// Receiving native video evidence does not establish that the UI has painted it.
final class MediaPlaybackStartupTiming {
  MediaPlaybackStartupTiming({this.elapsed}) : _clock = Stopwatch()..start();
  final Stopwatch _clock;
  final Duration Function()? elapsed;
  Duration get _now => elapsed?.call() ?? _clock.elapsed;
  Duration? pushed;
  Duration? resolveStarted;
  Duration? sourceReady;
  Duration? firstFrameReceived;
  String? _playerId;
  int? _epoch;
  bool _navigationAttempt = true;
  VesperFirstFrameObservation? firstFrame;

  void markPushed() => pushed ??= _now;
  void markResolveStarted() => resolveStarted ??= _now;
  void markSourceReady() => sourceReady ??= _now;

  void bindController(String playerId) {
    if (_playerId != null) endNavigationAttempt();
    _playerId = playerId;
    _epoch = null;
    firstFrame = null;
  }

  /// Entry changes, listen mode, retries and disposal end the initial tap metric.
  void endNavigationAttempt() {
    _navigationAttempt = false;
  }

  void observe(
    String playerId,
    VesperPlaybackDiagnosticsSnapshot? diagnostics,
  ) {
    if (_playerId != playerId || diagnostics == null) return;
    final epoch = diagnostics.playbackEpoch;
    if (epoch <= 0 || (_epoch != null && epoch < _epoch!)) return;
    if (_epoch != epoch) {
      if (_epoch != null) endNavigationAttempt();
      _epoch = epoch;
      firstFrame = null;
    }
    final observation = diagnostics.firstFrame;
    if (observation == null ||
        observation.playbackEpoch != epoch ||
        firstFrame != null) {
      return;
    }
    firstFrame = observation;
    if (_navigationAttempt) firstFrameReceived ??= _now;
  }

  String get label => [
    if (pushed != null) 'tap→push=${pushed!.inMilliseconds}ms',
    if (pushed != null && resolveStarted != null)
      'push→resolveStart=${(resolveStarted! - pushed!).inMilliseconds}ms',
    if (resolveStarted != null && sourceReady != null)
      'resolveStart→sourceReady=${(sourceReady! - resolveStarted!).inMilliseconds}ms',
    if (firstFrameReceived case final received?)
      'tap→firstFrameReceived=${received.inMilliseconds}ms',
  ].join(', ');
}
