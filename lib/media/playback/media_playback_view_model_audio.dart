part of 'media_playback_view_model.dart';

extension _MediaPlaybackAudioRecovery on MediaPlaybackViewModel {
  void _startAudioWatchdog(int controllerGeneration) {
    _audioWatchdogTimer?.cancel();
    _audioWatchdog.reset();
    if (adapter.audioCompatibility == null ||
        (_resolvedPlayback.value?.audioTracks.isEmpty ?? true)) {
      return;
    }
    _audioWatchdogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed || controllerGeneration != _controllerGeneration) {
        timer.cancel();
        return;
      }
      final controller = _controller;
      final playback = _resolvedPlayback.value;
      final policy = adapter.audioCompatibility;
      if (controller == null || playback == null || policy == null) return;
      final snapshot = controller.snapshot;
      final stable =
          !_playbackSourceTransitionInFlight.value &&
          !_playbackRecoveryInFlight &&
          _userSeeksInFlight == 0 &&
          _sourceMode == MediaPlaybackSourceMode.video;
      if (stable) {
        final trackId = policy.fallbackTrackId(playback, snapshot);
        final pinKey = (
          _sourceTransitionGeneration,
          snapshot.trackCatalog.catalogRevision,
          trackId,
        );
        if (trackId != null && _audioPinAttempt != pinKey) {
          _audioPinAttempt = pinKey;
          // Use a native catalog id verbatim; Bilibili ids are not SDK ids.
          final sourceGeneration = _sourceTransitionGeneration;
          unawaited(
            _runSourceTransaction(() async {
              if (_isDisposed ||
                  !identical(controller, _controller) ||
                  sourceGeneration != _sourceTransitionGeneration ||
                  _playbackSourceTransitionInFlight.value ||
                  _playbackRecoveryInFlight) {
                return;
              }
              try {
                await controller.setAudioTrackSelection(
                  VesperTrackSelection.track(trackId),
                );
              } catch (_) {
                debugPrint(
                  '[PlaybackRecovery] compatible audio track selection failed',
                );
              }
            }),
          );
        }
      }
      final reason = _audioWatchdog.observe(
        snapshot: snapshot,
        now: Duration(seconds: timer.tick),
        eligible:
            stable &&
            // Native observations handle seek, suspension and startup windows.
            // App sampling remains available when the host has no diagnostics.
            snapshot.playbackDiagnostics == null &&
            !_audioRecoveryAttempted &&
            policy.canRecover(playback, snapshot),
      );
      if (reason != null && policy.claimRecovery()) {
        _audioRecoveryAttempted = true;
        unawaited(_recoverStalledAudio(controller, reason));
      }
    });
  }

  Future<void> _recoverStalledAudio(
    VesperPlayerController controller,
    MediaPlaybackStallReason reason,
  ) async {
    final previous = _resolvedPlayback.value;
    if (previous == null) return;
    final entry = _selectedEntry.value;
    final seekGeneration = _userSeekGeneration;
    final intentGeneration = _playbackIntentGeneration;
    final transition = _beginSourceTransition();
    bool current() =>
        _isCurrentSourceTransition(transition, controller: controller) &&
        _sourceMode == MediaPlaybackSourceMode.video;
    debugPrint(
      '[PlaybackRecovery] playback-stall=${reason.name}; audio-policy=dolby-blocked(watchdog); entry=${entry.entryId}',
    );
    try {
      final resolved = await adapter.resolvePlayback(
        detail: detail,
        entry: entry,
      );
      if (!current() || seekGeneration != _userSeekGeneration) return;
      await _runSourceTransaction(() async {
        if (!current() || seekGeneration != _userSeekGeneration) return;
        // Snapshot immediately before source replacement preserves seeks and
        // pauses that happened while resolution was in flight.
        final snapshot = controller.snapshot;
        final playbackRate = snapshot.playbackRate;
        final source = resolved.toSource();
        await _selectSourcePreservingPausedIntent(controller, source, snapshot);
        if (!current()) return;
        _resolvedPlayback.value = resolved;
        _resetRuntimeTrackCapabilityState();
        _selectedQualityOptionId.value = null;
        _selectedCodecIdentity.value = null;
        await _configureSystemPlayback(
          controller,
          resolved,
          activeSource: source,
        );
        if (!current()) return;
        await controller.setPlaybackRate(playbackRate);
        if (!current()) return;
        final duration = snapshot.timeline.durationMs;
        if (seekGeneration == _userSeekGeneration &&
            snapshot.timeline.positionMs > 0) {
          if (duration != null && duration > 0) {
            await controller.seekToRatio(
              (snapshot.timeline.positionMs / duration).clamp(0.0, 1.0),
            );
          } else {
            await controller.seekBy(snapshot.timeline.positionMs);
          }
        }
        if (!current()) return;
        final shouldPlay = intentGeneration == _playbackIntentGeneration
            ? snapshot.playbackState == VesperPlaybackState.playing ||
                  (snapshot.playbackState == VesperPlaybackState.ready &&
                      snapshot.isBuffering)
            : _latestPlayIntent == true;
        if (shouldPlay && !controller.snapshot.isInterrupted) {
          await controller.play();
        } else {
          await controller.pause();
        }
        if (current()) _emitMessage('检测到播放停滞，已尝试使用兼容音轨恢复播放。');
      });
    } catch (error) {
      if (current()) _emitMessage('兼容音轨恢复失败，请重新加载：${mediaErrorMessage(error)}');
    } finally {
      _finishSourceTransition(transition);
      _audioWatchdog.reset();
    }
  }
}
