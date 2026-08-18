part of 'media_playback_view_model.dart';

final class _ListenVideoPolicyRestore {
  const _ListenVideoPolicyRestore({
    required this.abrPolicy,
    required this.qualityOptionId,
    required this.codecIdentity,
  });

  final VesperAbrPolicy abrPolicy;
  final String? qualityOptionId;
  final String? codecIdentity;
}

extension MediaPlaybackListenMode on MediaPlaybackViewModel {
  Future<String?> enterListenMode() async {
    if (_isDisposed || _sourceMode == MediaPlaybackSourceMode.audioOnly) {
      return null;
    }
    final controller = _controller;
    final resolved = _resolvedPlayback.value;
    if (controller == null || resolved == null) {
      return '播放器尚未准备好。';
    }
    final audioSource = resolved.toAudioOnlySource();
    if (audioSource == null) {
      return '当前视频暂无可用的纯音频源。';
    }
    if (_playbackSourceTransitionInFlight) {
      return '播放源正在切换，请稍候。';
    }

    final previousSnapshot = controller.snapshot;
    final policyRestore = _ListenVideoPolicyRestore(
      abrPolicy: previousSnapshot.trackSelection.abrPolicy,
      qualityOptionId: _selectedQualityOptionId.value,
      codecIdentity: _selectedCodecIdentity.value,
    );
    final transitionGeneration = _beginSourceTransition();
    return _runSourceTransaction(() async {
      try {
        await _selectSourcePreservingPausedIntent(
          controller,
          audioSource,
          previousSnapshot,
        );
        _assertCurrentSourceTransition(
          transitionGeneration,
          controller: controller,
        );
        await _restoreSourceContinuity(controller, previousSnapshot);
        _assertCurrentSourceTransition(
          transitionGeneration,
          controller: controller,
        );
        await _configureSystemPlayback(
          controller,
          resolved,
          activeSource: audioSource,
        );
        _assertCurrentSourceTransition(
          transitionGeneration,
          controller: controller,
        );
        _sourceMode = MediaPlaybackSourceMode.audioOnly;
        _listenVideoPolicyRestore = policyRestore;
        return null;
      } on _PlaybackSourceObsoleted {
        return '播放源已更新，请重新进入听视频。';
      } catch (error) {
        final rollbackRestored = await _rollbackSourceTransition(
          transitionGeneration: transitionGeneration,
          controller: controller,
          source: resolved.toSource(),
          snapshot: previousSnapshot,
          videoPolicy: policyRestore,
        );
        return rollbackRestored
            ? '进入听视频失败：${mediaErrorMessage(error)}'
            : '进入听视频失败，且视频源恢复失败，请重新加载。';
      } finally {
        _finishSourceTransition(transitionGeneration);
      }
    });
  }

  Future<String?> exitListenMode() async {
    if (_isDisposed || _sourceMode == MediaPlaybackSourceMode.video) {
      return null;
    }
    final controller = _controller;
    final resolved = _resolvedPlayback.value;
    final audioSource = resolved?.toAudioOnlySource();
    if (controller == null || resolved == null || audioSource == null) {
      return '播放器尚未准备好。';
    }
    if (_playbackSourceTransitionInFlight) {
      return '播放源正在切换，请稍候。';
    }

    final previousSnapshot = controller.snapshot;
    final policyRestore =
        _listenVideoPolicyRestore ??
        const _ListenVideoPolicyRestore(
          abrPolicy: VesperAbrPolicy.auto(),
          qualityOptionId: null,
          codecIdentity: null,
        );
    final transitionGeneration = _beginSourceTransition();
    return _runSourceTransaction(() async {
      try {
        final videoSource = resolved.toSource();
        await _selectSourcePreservingPausedIntent(
          controller,
          videoSource,
          previousSnapshot,
        );
        _assertCurrentSourceTransition(
          transitionGeneration,
          controller: controller,
        );
        final videoPolicyRestored = await _restoreSourceContinuity(
          controller,
          previousSnapshot,
          videoPolicy: policyRestore,
        );
        _assertCurrentSourceTransition(
          transitionGeneration,
          controller: controller,
        );
        await _configureSystemPlayback(
          controller,
          resolved,
          activeSource: videoSource,
        );
        _assertCurrentSourceTransition(
          transitionGeneration,
          controller: controller,
        );
        _sourceMode = MediaPlaybackSourceMode.video;
        _listenVideoPolicyRestore = null;
        _selectedQualityOptionId.value = videoPolicyRestored
            ? policyRestore.qualityOptionId
            : null;
        _selectedCodecIdentity.value = videoPolicyRestored
            ? policyRestore.codecIdentity
            : null;
        return null;
      } on _PlaybackSourceObsoleted {
        return '播放源已更新，请重试返回视频。';
      } catch (error) {
        final rollbackRestored = await _rollbackSourceTransition(
          transitionGeneration: transitionGeneration,
          controller: controller,
          source: audioSource,
          snapshot: previousSnapshot,
        );
        return rollbackRestored
            ? '返回视频失败：${mediaErrorMessage(error)}'
            : '返回视频失败，且纯音频源恢复失败，请重新加载。';
      } finally {
        _finishSourceTransition(transitionGeneration);
      }
    });
  }

  int _beginSourceTransition() {
    _playbackSourceTransitionInFlight = true;
    _invalidatePlaybackSelectionRequests();
    _resetPlaybackRecoveryState(clearPendingNotice: true);
    _sourceGeneration += 1;
    return ++_sourceTransitionGeneration;
  }

  void _finishSourceTransition(int generation) {
    if (generation == _sourceTransitionGeneration) {
      _playbackSourceTransitionInFlight = false;
    }
  }

  bool _isCurrentSourceTransition(
    int generation, {
    required VesperPlayerController controller,
  }) {
    return !_isDisposed &&
        generation == _sourceTransitionGeneration &&
        identical(controller, _controller);
  }

  void _assertCurrentSourceTransition(
    int generation, {
    required VesperPlayerController controller,
  }) {
    if (!_isCurrentSourceTransition(generation, controller: controller)) {
      throw const _PlaybackSourceObsoleted();
    }
  }

  VesperPlayerSource? _sourceForMode(
    ResolvedMediaPlayback resolved,
    MediaPlaybackSourceMode mode,
  ) {
    return switch (mode) {
      MediaPlaybackSourceMode.video => resolved.toSource(),
      MediaPlaybackSourceMode.audioOnly => resolved.toAudioOnlySource(),
    };
  }

  Future<void> _selectSourcePreservingPausedIntent(
    VesperPlayerController controller,
    VesperPlayerSource source,
    VesperPlayerSnapshot previousSnapshot,
  ) async {
    final sourceSelection = controller.selectSource(source);
    if (previousSnapshot.playbackState == VesperPlaybackState.playing) {
      await sourceSelection;
      return;
    }

    await Future.wait<void>(<Future<void>>[
      sourceSelection,
      controller.pause(),
    ]);
  }

  Future<bool> _restoreSourceContinuity(
    VesperPlayerController controller,
    VesperPlayerSnapshot previousSnapshot, {
    _ListenVideoPolicyRestore? videoPolicy,
  }) async {
    final playbackRate = previousSnapshot.playbackRate;
    if (playbackRate.isFinite && playbackRate > 0) {
      await controller.setPlaybackRate(playbackRate);
    }

    final previousTimeline = previousSnapshot.timeline;
    final previousPositionMs = previousTimeline.positionMs;
    final previousDurationMs = previousTimeline.durationMs;
    if (previousPositionMs > 0) {
      if (previousDurationMs != null && previousDurationMs > 0) {
        final targetPositionMs = previousPositionMs
            .clamp(0, previousDurationMs - 1)
            .toInt();
        await controller.seekToRatio(targetPositionMs / previousDurationMs);
      } else {
        // Native source selection starts the replacement source at zero. This
        // fallback avoids depending on a Dart snapshot event arriving before
        // the MethodChannel response.
        await controller.seekBy(previousPositionMs);
      }
    }

    final videoPolicyRestored = videoPolicy == null
        ? true
        : await _restoreVideoPolicy(controller, videoPolicy);

    if (previousSnapshot.playbackState == VesperPlaybackState.playing) {
      await controller.play();
    } else {
      await controller.pause();
    }
    return videoPolicyRestored;
  }

  Future<bool> _restoreVideoPolicy(
    VesperPlayerController controller,
    _ListenVideoPolicyRestore restore,
  ) async {
    if (restore.qualityOptionId != null || restore.codecIdentity != null) {
      final fallbackMessage = await _applyPlaybackSelection(
        optionId: restore.qualityOptionId,
        codecIdentity: restore.codecIdentity,
      );
      if (fallbackMessage == null) {
        return true;
      }
      _emitMessage(fallbackMessage);
      return false;
    }
    try {
      final expectedRevision =
          restore.abrPolicy.mode == VesperAbrMode.fixedTrack
          ? controller.snapshot.trackCatalog.catalogRevision
          : null;
      await controller.setAbrPolicy(
        restore.abrPolicy,
        expectedCatalogRevision: expectedRevision,
      );
      return true;
    } catch (_) {
      _suppressCurrentPlaybackCommandError(controller);
      final fallbackMessage = await _applyPlaybackSelection(
        optionId: restore.qualityOptionId,
        codecIdentity: restore.codecIdentity,
      );
      if (fallbackMessage != null) {
        _emitMessage(fallbackMessage);
        return false;
      }
      return true;
    }
  }

  Future<bool> _rollbackSourceTransition({
    required int transitionGeneration,
    required VesperPlayerController controller,
    required VesperPlayerSource source,
    required VesperPlayerSnapshot snapshot,
    _ListenVideoPolicyRestore? videoPolicy,
  }) async {
    if (!_isCurrentSourceTransition(
      transitionGeneration,
      controller: controller,
    )) {
      return false;
    }
    try {
      await _selectSourcePreservingPausedIntent(controller, source, snapshot);
      _assertCurrentSourceTransition(
        transitionGeneration,
        controller: controller,
      );
      await _restoreSourceContinuity(
        controller,
        snapshot,
        videoPolicy: videoPolicy,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
