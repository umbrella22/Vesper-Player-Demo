part of 'media_playback_view_model.dart';

extension MediaPlaybackDiagnosticsView on MediaPlaybackViewModel {
  String? get nativeFirstFrameLabel {
    final frame = _nativeDiagnostics.value?.firstFrame;
    return frame == null ? null : mediaFirstFrameLabel(frame);
  }

  String? get audioDiagnosticsLabel {
    final diagnostics = _nativeDiagnostics.value;
    return diagnostics == null
        ? null
        : mediaAudioDiagnosticsLabel(diagnostics.audio);
  }

  String? get audioDecoderCapabilityLabel {
    final result = _audioDecoderCapability.value;
    return result == null
        ? _audioProbeError.value
        : mediaAudioDecoderCapabilityLabel(result);
  }

  String? get playbackStallLabel {
    final stall = _nativeDiagnostics.value?.lastStall;
    return stall == null ? null : mediaPlaybackStallLabel(stall);
  }

  String? get lastPlaybackFailureLabel {
    final evidence = _lastPlaybackFailureEvidence.value;
    return evidence == null
        ? null
        : 'epoch=${evidence.playbackEpoch}; ${mediaAudioDiagnosticsLabel(evidence.audio)}';
  }
}

extension _MediaPlaybackNativeDiagnostics on MediaPlaybackViewModel {
  void _resetNativePlaybackDiagnostics() {
    _nativeDiagnostics.value = null;
    _audioDecoderCapability.value = null;
    _audioProbeError.value = null;
    _audioProbeKey = null;
    _handledNativeStall = null;
  }

  void _observeNativePlaybackDiagnostics(
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
    int generation,
  ) {
    if (_isDisposed || generation != _controllerGeneration) return;
    final diagnostics = snapshot.playbackDiagnostics;
    startupTiming?.observe(controller.playerId, diagnostics);
    _nativeDiagnostics.value = diagnostics;
    if (snapshot.lastError case final error?) {
      _capturePlaybackFailureEvidence(error);
    }
    if (diagnostics == null || diagnostics.playbackEpoch <= 0) {
      _audioProbeKey = null;
      _audioDecoderCapability.value = null;
      _audioProbeError.value = null;
      return;
    }
    if (_playbackSourceTransitionInFlight.value) return;
    final audio = diagnostics.audio;
    final key = (
      generation,
      _sourceTransitionGeneration,
      diagnostics.playbackEpoch,
      audio.codec,
      audio.sampleMimeType,
      audio.channels,
      audio.sampleRate,
    );
    if (_audioProbeKey == key) return;
    _audioProbeKey = key;
    _audioDecoderCapability.value = null;
    _audioProbeError.value = null;
    if ((audio.codec == null || audio.codec!.isEmpty) &&
        (audio.sampleMimeType == null || audio.sampleMimeType!.isEmpty)) {
      return;
    }
    // Runtime inputs only. In particular, an MP4 container MIME, a requested
    // track or a guessed channel count is not a decoder-format observation.
    final request = VesperAudioDecoderCapabilityRequest(
      codec: audio.codec,
      sampleMimeType: audio.sampleMimeType,
      channels: audio.channels,
      sampleRate: audio.sampleRate,
    );
    unawaited(() async {
      try {
        final result = await VesperPlayerController.probeAudioDecoderCapability(
          request,
        );
        if (_isDisposed || _audioProbeKey != key) return;
        // Capability evidence is diagnostic; it never lifts a device quirk or
        // changes explicit user policy, including when status is supported.
        _audioDecoderCapability.value = result;
      } catch (_) {
        if (_isDisposed || _audioProbeKey != key) return;
        _audioProbeError.value = 'unknown; reason=audioProbeUnavailable';
      }
    }());
  }

  void _capturePlaybackFailureEvidence(VesperPlayerError error) {
    final evidence = error.playbackDiagnostics;
    if (evidence != null) _lastPlaybackFailureEvidence.value = evidence;
  }

  void _handleNativePlaybackWarning(
    VesperPlayerController controller,
    VesperRuntimeWarning warning,
    int generation,
  ) {
    final snapshot = controller.snapshot;
    final epoch = snapshot.playbackDiagnostics?.playbackEpoch;
    final audio = warning.audio;
    if (warning.domain == VesperRuntimeWarningDomain.audio &&
        audio != null &&
        audio.playbackEpoch == epoch) {
      debugPrint(
        '[PlaybackAudio] epoch=$epoch; ${mediaAudioDiagnosticsLabel(audio.diagnostics)}',
      );
    }
    final stall = warning.playback;
    if (warning.domain != VesperRuntimeWarningDomain.playback ||
        stall == null ||
        stall.playbackEpoch != epoch) {
      return;
    }
    final key = (
      generation,
      epoch,
      stall.elapsedSinceLoadStartMs,
      stall.kindRawValue ?? stall.kind.name,
    );
    if (_handledNativeStall == key) return;
    _handledNativeStall = key;
    debugPrint(
      '[PlaybackStall] ${mediaPlaybackStallLabel(stall)}; ${mediaAudioDiagnosticsLabel(stall.audio)}',
    );
    // Retained stalls are historical. A replay after progress, pause, seek or
    // source transition cannot authorize recovery of the current source.
    final playback = _resolvedPlayback.value;
    final policy = adapter.audioCompatibility;
    final duration = snapshot.timeline.durationMs;
    if (_isDisposed ||
        generation != _controllerGeneration ||
        !identical(controller, _controller) ||
        playback == null ||
        policy == null ||
        _audioRecoveryAttempted ||
        _userSeeksInFlight > 0 ||
        _playbackSourceTransitionInFlight.value ||
        _playbackRecoveryInFlight ||
        _sourceMode != MediaPlaybackSourceMode.video ||
        snapshot.lastError != null ||
        snapshot.isInterrupted ||
        (snapshot.playbackState != VesperPlaybackState.playing &&
            !(snapshot.playbackState == VesperPlaybackState.ready &&
                snapshot.isBuffering)) ||
        snapshot.trackSelection.audio.mode ==
            VesperTrackSelectionMode.disabled ||
        snapshot.timeline.positionMs != stall.mediaPositionMs ||
        (duration != null &&
            duration > 0 &&
            snapshot.timeline.positionMs >= duration) ||
        !policy.canRecover(playback, snapshot)) {
      return;
    }
    final reason = switch (stall.kind) {
      VesperPlaybackStallKind.positionNotAdvancing =>
        MediaPlaybackStallReason.positionStopped,
      VesperPlaybackStallKind.bufferingTimeout =>
        MediaPlaybackStallReason.bufferingTimeout,
      VesperPlaybackStallKind.unknown => null,
    };
    if (reason == null || !policy.claimRecovery()) return;
    _audioRecoveryAttempted = true;
    unawaited(_recoverStalledAudio(controller, reason));
  }
}
