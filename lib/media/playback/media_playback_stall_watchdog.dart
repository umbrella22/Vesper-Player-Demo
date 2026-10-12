import 'package:vesper_player/vesper_player.dart';

enum MediaPlaybackStallReason { positionStopped, bufferingTimeout }

/// Infers playback stagnation, never a particular decoder failure.
final class MediaPlaybackStallWatchdog {
  Duration? _positionSince;
  Duration? _bufferingSince;
  int? _positionMs;

  void reset() {
    _positionSince = null;
    _bufferingSince = null;
    _positionMs = null;
  }

  MediaPlaybackStallReason? observe({
    required VesperPlayerSnapshot snapshot,
    required Duration now,
    required bool eligible,
  }) {
    final timeline = snapshot.timeline;
    if (!eligible ||
        snapshot.lastError != null ||
        snapshot.isInterrupted ||
        snapshot.trackSelection.audio.mode ==
            VesperTrackSelectionMode.disabled ||
        snapshot.playbackState == VesperPlaybackState.paused ||
        snapshot.playbackState == VesperPlaybackState.finished ||
        (timeline.durationMs != null &&
            timeline.durationMs! > 0 &&
            timeline.positionMs >= timeline.durationMs!)) {
      reset();
      return null;
    }
    if (snapshot.isBuffering) {
      _positionSince = null;
      _positionMs = null;
      _bufferingSince ??= now;
      return now - _bufferingSince! >= const Duration(seconds: 30)
          ? MediaPlaybackStallReason.bufferingTimeout
          : null;
    }
    _bufferingSince = null;
    if (snapshot.playbackState != VesperPlaybackState.playing) {
      reset();
      return null;
    }
    if (_positionMs != timeline.positionMs) {
      _positionMs = timeline.positionMs;
      _positionSince = now;
    }
    _positionSince ??= now;
    return now - _positionSince! >= const Duration(seconds: 10)
        ? MediaPlaybackStallReason.positionStopped
        : null;
  }
}
