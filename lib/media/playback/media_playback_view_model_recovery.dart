part of 'media_playback_view_model.dart';

extension _MediaPlaybackRecovery on MediaPlaybackViewModel {
  Future<void> _replaceControllerEventSubscription(
    VesperPlayerController controller,
    int generation,
  ) async {
    await _controllerEventsSubscription?.cancel();
    if (_isDisposed || generation != _controllerGeneration) {
      return;
    }
    _controllerEventsSubscription = controller.events.listen((event) {
      if (_isDisposed || generation != _controllerGeneration) {
        return;
      }
      switch (event) {
        case VesperPlayerSnapshotEvent():
          _handleControllerSnapshot(event.snapshot, generation);
        case VesperPlayerErrorEvent():
          _handleControllerError(event.error, generation);
        case VesperPlayerWarningEvent():
          _handleControllerWarning(event.warning, generation);
        default:
      }
    });
  }

  void _handleControllerSnapshot(
    VesperPlayerSnapshot snapshot,
    int generation,
  ) {
    if (_isDisposed || generation != _controllerGeneration) {
      return;
    }
    if (snapshot.lastError == null &&
        _suppressedPlaybackCommandError.value != null) {
      _suppressedPlaybackCommandError.value = null;
    }
    _reconcileRuntimeTrackFallback(snapshot);
    if (snapshot.lastError != null) {
      _playbackRecoverySuccessTimer?.cancel();
      return;
    }
    if (_playbackRecoveryAttempts > 0 &&
        !_playbackRecoveryInFlight &&
        snapshot.playbackState == VesperPlaybackState.playing) {
      _schedulePlaybackRecoverySuccessReset(generation);
    }
  }

  void _handleControllerWarning(VesperRuntimeWarning warning, int generation) {
    if (_isDisposed || generation != _controllerGeneration) {
      return;
    }
    final capability = warning.capability;
    if (warning.domain != VesperRuntimeWarningDomain.capability ||
        capability == null) {
      return;
    }
    final diagnostics = capability.diagnostics;
    final code = '${diagnostics['code'] ?? capability.reasonRawValue ?? ''}';
    final trackId = diagnostics['trackId'];
    if (code != 'runtimeTrackRejected' ||
        trackId is! String ||
        trackId.isEmpty) {
      return;
    }
    final rejectionKey =
        '$generation:${diagnostics['sourceEpoch'] ?? ''}:$trackId';
    if (!_handledRuntimeTrackRejections.add(rejectionKey)) {
      return;
    }
    _runtimeRejectedVideoTrackIds.add(trackId);
    _pendingRuntimeFallbackTrackId = trackId;
    _invalidatePlaybackSelectionRequests();
    _selectedQualityOptionId.value = null;
    _selectedCodecIdentity.value = null;
  }

  void _reconcileRuntimeTrackFallback(VesperPlayerSnapshot snapshot) {
    final rejectedTrackId = _pendingRuntimeFallbackTrackId;
    final effectiveTrackId = snapshot.effectiveVideoTrackId;
    if (rejectedTrackId == null ||
        effectiveTrackId == null ||
        effectiveTrackId == rejectedTrackId ||
        snapshot.lastError != null ||
        snapshot.isBuffering ||
        snapshot.playbackState != VesperPlaybackState.playing) {
      return;
    }
    _pendingRuntimeFallbackTrackId = null;
    final fallbackLabel = _qualityLabelForTrackId(snapshot, effectiveTrackId);
    _emitMessage(
      fallbackLabel == null
          ? '当前设备无法继续播放所选清晰度，已切换为自动清晰度。'
          : '当前设备无法继续播放所选清晰度，已切换至 $fallbackLabel。',
    );
  }

  String? _qualityLabelForTrackId(
    VesperPlayerSnapshot snapshot,
    String trackId,
  ) {
    for (final option in availableQualityOptions()) {
      if (option.tracks.any((track) => track.id == trackId)) {
        return option.label;
      }
    }
    final track = _nativeVideoTrack(snapshot, trackId);
    final label = track?.label?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    final height = track?.height;
    return height == null || height <= 0 ? null : '${height}P';
  }

  void _resetRuntimeTrackCapabilityState() {
    _runtimeRejectedVideoTrackIds.clear();
    _handledRuntimeTrackRejections.clear();
    _pendingRuntimeFallbackTrackId = null;
  }

  void _invalidatePlaybackSelectionRequests() {
    _playbackSelectionGeneration += 1;
  }

  void _handleControllerError(VesperPlayerError error, int generation) {
    if (_isDisposed || generation != _controllerGeneration) {
      return;
    }
    if (_playbackSourceTransitionInFlight) {
      return;
    }
    if (!_shouldAutoRecoverPlaybackSource(error)) {
      return;
    }
    _playbackRecoverySuccessTimer?.cancel();
    if (_playbackRecoveryFailureReported) {
      return;
    }
    if (_playbackRecoveryInFlight) {
      _deferredPlaybackRecoveryError = error;
      return;
    }
    if (_playbackRecoveryAttempts >=
        MediaPlaybackViewModel._maxPlaybackRecoveryAttempts) {
      _emitPlaybackRecoveryFailure(error.message);
      return;
    }
    unawaited(
      _attemptPlaybackRecovery(error, generation, _playbackRecoveryGeneration),
    );
  }

  bool _shouldAutoRecoverPlaybackSource(VesperPlayerError error) {
    final resolved = _resolvedPlayback.value;
    if (resolved == null || resolved.isLocalFile) {
      return false;
    }
    if (error.details['domain'] == 'subtitle') {
      return false;
    }
    if (error.details['keySystem'] != null ||
        error.details['domain'] == 'drm') {
      return false;
    }
    if (error.code == VesperPlayerErrorCode.invalidSource ||
        error.category == VesperPlayerErrorCategory.source) {
      return true;
    }
    if (error.code != VesperPlayerErrorCode.backendFailure ||
        (error.category != VesperPlayerErrorCategory.network &&
            error.category != VesperPlayerErrorCategory.platform)) {
      return false;
    }
    final iosHttpStatus = int.tryParse(
      '${error.details['avPlayerItemErrorStatusCode'] ?? ''}',
    );
    if (iosHttpStatus != null && iosHttpStatus >= 400 && iosHttpStatus <= 599) {
      return true;
    }
    return switch ('${error.details['errorCodeName'] ?? ''}') {
      'ERROR_CODE_IO_BAD_HTTP_STATUS' ||
      'ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE' => true,
      _ => false,
    };
  }

  Future<void> _attemptPlaybackRecovery(
    VesperPlayerError triggerError,
    int controllerGeneration,
    int recoveryGeneration,
  ) async {
    if (_isDisposed ||
        controllerGeneration != _controllerGeneration ||
        recoveryGeneration != _playbackRecoveryGeneration ||
        _playbackSourceTransitionInFlight ||
        _playbackRecoveryInFlight) {
      return;
    }
    final controller = _controller;
    final recoveryEntry = _selectedEntry.value;
    if (controller == null) {
      return;
    }

    _playbackRecoveryInFlight = true;
    _playbackRecoverySuccessTimer?.cancel();
    var lastFailureMessage = triggerError.message;
    try {
      while (!_isDisposed &&
          controllerGeneration == _controllerGeneration &&
          recoveryGeneration == _playbackRecoveryGeneration &&
          !_playbackSourceTransitionInFlight &&
          _playbackRecoveryAttempts <
              MediaPlaybackViewModel._maxPlaybackRecoveryAttempts) {
        final attempt = _playbackRecoveryAttempts + 1;
        _playbackRecoveryAttempts = attempt;
        _deferredPlaybackRecoveryError = null;
        final backoff =
            MediaPlaybackViewModel._playbackRecoveryBackoff[attempt - 1];
        if (backoff > Duration.zero) {
          await Future<void>.delayed(backoff);
          if (_isDisposed ||
              controllerGeneration != _controllerGeneration ||
              recoveryGeneration != _playbackRecoveryGeneration ||
              _playbackSourceTransitionInFlight) {
            return;
          }
        }

        final timeline = controller.snapshot.timeline;
        final resumeRatio =
            timeline.durationMs != null &&
                timeline.durationMs! > 0 &&
                timeline.positionMs > 0
            ? (timeline.positionMs / timeline.durationMs!)
                  .clamp(0.0, 1.0)
                  .toDouble()
            : null;
        try {
          final resolved = await adapter.resolvePlayback(
            detail: detail,
            entry: recoveryEntry,
          );
          if (_isDisposed ||
              controllerGeneration != _controllerGeneration ||
              recoveryGeneration != _playbackRecoveryGeneration ||
              _playbackSourceTransitionInFlight ||
              recoveryEntry.entryId != _selectedEntry.value.entryId) {
            return;
          }
          final source = _sourceForMode(resolved, _sourceMode);
          if (source == null) {
            throw StateError('当前条目没有可用的纯音频源。');
          }
          final shouldRetry = await _runSourceTransaction<bool?>(() async {
            if (!_isCurrentPlaybackRecovery(
              controller: controller,
              recoveryEntry: recoveryEntry,
              controllerGeneration: controllerGeneration,
              recoveryGeneration: recoveryGeneration,
            )) {
              return null;
            }
            await controller.selectSource(source);
            if (!_isCurrentPlaybackRecovery(
              controller: controller,
              recoveryEntry: recoveryEntry,
              controllerGeneration: controllerGeneration,
              recoveryGeneration: recoveryGeneration,
            )) {
              return null;
            }
            await _configureSystemPlayback(
              controller,
              resolved,
              activeSource: source,
              activeEntry: recoveryEntry,
            );
            if (!_isCurrentPlaybackRecovery(
              controller: controller,
              recoveryEntry: recoveryEntry,
              controllerGeneration: controllerGeneration,
              recoveryGeneration: recoveryGeneration,
            )) {
              return null;
            }
            if (resumeRatio != null && resumeRatio > 0) {
              await controller.seekToRatio(resumeRatio);
            }
            if (!_isCurrentPlaybackRecovery(
              controller: controller,
              recoveryEntry: recoveryEntry,
              controllerGeneration: controllerGeneration,
              recoveryGeneration: recoveryGeneration,
            )) {
              return null;
            }
            await controller.play();
            if (!_isCurrentPlaybackRecovery(
              controller: controller,
              recoveryEntry: recoveryEntry,
              controllerGeneration: controllerGeneration,
              recoveryGeneration: recoveryGeneration,
            )) {
              return null;
            }
            await Future<void>.delayed(Duration.zero);
            final deferredError = _deferredPlaybackRecoveryError;
            if (deferredError != null) {
              lastFailureMessage = deferredError.message;
              return true;
            }
            _resolvedPlayback.value = resolved;
            _schedulePlaybackRecoverySuccessReset(
              controllerGeneration,
              recoveryGeneration,
            );
            return false;
          });
          if (shouldRetry == null) {
            return;
          }
          if (shouldRetry) {
            continue;
          }
          return;
        } catch (error) {
          lastFailureMessage = '重新解析失败：${mediaErrorMessage(error)}';
        }
      }
    } finally {
      if (recoveryGeneration == _playbackRecoveryGeneration) {
        _playbackRecoveryInFlight = false;
      }
    }

    if (!_isDisposed &&
        controllerGeneration == _controllerGeneration &&
        recoveryGeneration == _playbackRecoveryGeneration &&
        _playbackRecoveryAttempts >=
            MediaPlaybackViewModel._maxPlaybackRecoveryAttempts) {
      _emitPlaybackRecoveryFailure(lastFailureMessage);
    }
  }

  bool _isCurrentPlaybackRecovery({
    required VesperPlayerController controller,
    required MediaPlaybackEntry recoveryEntry,
    required int controllerGeneration,
    required int recoveryGeneration,
  }) {
    return !_isDisposed &&
        identical(controller, _controller) &&
        controllerGeneration == _controllerGeneration &&
        recoveryGeneration == _playbackRecoveryGeneration &&
        !_playbackSourceTransitionInFlight &&
        recoveryEntry.entryId == _selectedEntry.value.entryId;
  }

  void _schedulePlaybackRecoverySuccessReset(
    int controllerGeneration, [
    int? expectedRecoveryGeneration,
  ]) {
    final recoveryGeneration =
        expectedRecoveryGeneration ?? _playbackRecoveryGeneration;
    _playbackRecoverySuccessTimer?.cancel();
    _playbackRecoverySuccessTimer = Timer(
      MediaPlaybackViewModel._playbackRecoverySuccessWindow,
      () {
        if (_isDisposed ||
            controllerGeneration != _controllerGeneration ||
            recoveryGeneration != _playbackRecoveryGeneration) {
          return;
        }
        _resetPlaybackRecoveryState(clearPendingNotice: false);
      },
    );
  }

  void _emitPlaybackRecoveryFailure(String failureMessage) {
    if (_playbackRecoveryFailureReported) {
      return;
    }
    _playbackRecoveryFailureReported = true;
    _pendingPlaybackRecoveryNotice.value = MediaPlaybackRecoveryNotice(
      title: '播放地址刷新失败',
      message: '已自动重新解析并重试 3 次，仍然无法恢复播放。\n\n$failureMessage',
    );
  }

  void _resetPlaybackRecoveryState({required bool clearPendingNotice}) {
    _playbackRecoveryGeneration += 1;
    _playbackRecoverySuccessTimer?.cancel();
    _playbackRecoverySuccessTimer = null;
    _playbackRecoveryInFlight = false;
    _playbackRecoveryFailureReported = false;
    _playbackRecoveryAttempts = 0;
    _deferredPlaybackRecoveryError = null;
    if (clearPendingNotice) {
      _pendingPlaybackRecoveryNotice.value = null;
    }
  }
}
