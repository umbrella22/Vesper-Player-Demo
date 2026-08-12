part of 'media_playback_view_model.dart';

extension _MediaPlaybackControllerLifecycle on MediaPlaybackViewModel {
  Future<VesperPlayerController> _createController() async {
    final generation = ++_controllerGeneration;
    _invalidatePlaybackSelectionRequests();
    _resetRuntimeTrackCapabilityState();
    _suppressedPlaybackCommandError.value = null;
    VesperPlayerController? nextController;
    try {
      // 初始解析结果按约定与初始条目对应（调用方在构造时传入），
      // 首次创建直接使用；之后一律走适配器重新解析。
      final initialResolved = _initialResolvedPlayback;
      _initialResolvedPlayback = null;
      final resolved =
          initialResolved ??
          await adapter.resolvePlayback(
            detail: detail,
            entry: _selectedEntry.value,
          );
      if (!_isDisposed && generation == _controllerGeneration) {
        _resolvedPlayback.value = resolved;
      }

      final sourceNormalizerFuture = mediaPlayerSourceNormalizerConfiguration();
      final renderSurfaceKindFuture = _resolveRenderSurfaceKind();
      final sourceNormalizerConfiguration = await sourceNormalizerFuture;
      final renderSurfaceKind = await renderSurfaceKindFuture;
      nextController = await VesperPlayerController.create(
        initialSource: resolved.toSource(),
        renderSurfaceKind: renderSurfaceKind,
        resiliencePolicy: mediaPlayerResiliencePolicy,
        trackPreferencePolicy: mediaPlayerTrackPreferencePolicy,
        preloadBudgetPolicy: mediaPlayerPreloadBudgetPolicy,
        benchmarkConfiguration: mediaPlayerBenchmarkConfiguration(),
        sourceNormalizerConfiguration: sourceNormalizerConfiguration,
      );
      if (_isDisposed || generation != _controllerGeneration) {
        await nextController.dispose();
        throw const _PlaybackSourceObsoleted();
      }
      _resetPlaybackRecoveryState(clearPendingNotice: true);
      await _replaceControllerEventSubscription(nextController, generation);
      await nextController.initialize();
      if (_isDisposed || generation != _controllerGeneration) {
        await nextController.dispose();
        throw const _PlaybackSourceObsoleted();
      }
      final initialPositionMs = _pendingInitialPositionMs;
      if (initialPositionMs != null) {
        _pendingInitialPositionMs = null;
        await _seekToResumePosition(nextController, initialPositionMs);
      }
      await _configureSystemPlayback(nextController, resolved);
      if (_isDisposed || generation != _controllerGeneration) {
        await nextController.dispose();
        throw const _PlaybackSourceObsoleted();
      }
      await nextController.play();
      // 未显式指定初始位置时，从历史存储异步续播——不阻塞创建链
      // （存储读取可能是真实 IO，且平台可能未声明历史能力）。
      if (initialPositionMs == null && historyStore != null) {
        unawaited(_applyHistoryResume(nextController, generation));
      }
      if (_isDisposed || generation != _controllerGeneration) {
        await nextController.dispose();
        throw const _PlaybackSourceObsoleted();
      }
      _controller = nextController;
      _userController = _SeekAwareController(
        nextController,
        () => _userSeekGeneration += 1,
      );
      if (nextController.snapshot.lastError case final lastError?) {
        _handleControllerError(lastError, generation);
      }
      // controllerFuture 对外 resolve 代理：页面/舞台拿到的是
      // seek 感知实例（SDK 进度条手势 seek 使在途历史续播失效）。
      return _userController!;
    } catch (_) {
      if (nextController != null) {
        await nextController.dispose();
      }
      if (_controllerGeneration == generation) {
        _controller = null;
        _userController = null;
      }
      rethrow;
    }
  }

  /// 统一的位置续播：先 clamp 到媒体时长内，再 seek。
  /// 恢复失败只提示，不阻塞播放。
  Future<void> _seekToResumePosition(
    VesperPlayerController controller,
    int initialPositionMs,
  ) async {
    final timeline = controller.snapshot.timeline;
    final fallbackDurationMs = _selectedEntry.value.durationSeconds > 0
        ? _selectedEntry.value.durationSeconds * 1000
        : null;
    final durationMs = timeline.durationMs ?? fallbackDurationMs;
    final resumePositionMs =
        durationMs != null &&
            durationMs > 0 &&
            initialPositionMs >= durationMs - 3000
        ? 0
        : durationMs == null || durationMs <= 0
        ? initialPositionMs
        : initialPositionMs.clamp(0, durationMs - 1).toInt();
    if (resumePositionMs <= 0) {
      return;
    }
    try {
      await controller.seekBy(resumePositionMs - timeline.positionMs);
    } catch (error) {
      if (!_isDisposed) {
        _emitMessage('恢复历史播放位置失败：${mediaErrorMessage(error)}');
      }
    }
  }

  /// 从历史存储查询续播位置并 seek。仅首次创建时执行一次
  /// （[_historyResumeApplied] 置位），错误恢复/切分 P 不再查询。
  ///
  /// 查询绑定显式 generation（不依赖时间线位置推断意图）：
  /// - [_sourceGeneration]：切源（switchEntry 的 selectSource 前）时递增，
  ///   查询期间切分 P → 丢弃，避免旧进度应用到新 source；
  /// - [_userSeekGeneration]：用户 seek（VM 包装入口）时递增，
  ///   查询期间用户操作 → 丢弃，避免慢 IO 返回后覆盖。
  Future<void> _applyHistoryResume(
    VesperPlayerController controller,
    int generation,
  ) async {
    final historyStore = this.historyStore;
    if (historyStore == null ||
        _historyResumeApplied ||
        _isDisposed ||
        generation != _controllerGeneration) {
      return;
    }
    _historyResumeApplied = true;
    final entryId = _selectedEntry.value.entryId;
    final sourceGeneration = _sourceGeneration;
    final userSeekGeneration = _userSeekGeneration;
    try {
      final stored = await historyStore.latestPositionMsFor(
        detail.mediaId,
        entryId,
      );
      if (_isDisposed ||
          generation != _controllerGeneration ||
          stored == null ||
          stored <= 0 ||
          _selectedEntry.value.entryId != entryId ||
          _sourceGeneration != sourceGeneration ||
          _userSeekGeneration != userSeekGeneration) {
        return;
      }
      await _seekToResumePosition(controller, stored);
    } catch (_) {
      // 历史存储不可用不阻塞播放。
    }
  }

  Future<VesperPlayerRenderSurfaceKind> _resolveRenderSurfaceKind() async {
    final useLegacyCompatibility = await _preferTextureViewForPlayback();
    return useLegacyCompatibility
        ? VesperPlayerRenderSurfaceKind.textureView
        : VesperPlayerRenderSurfaceKind.auto;
  }

  Future<ResolvedMediaPlayback> _refreshCurrentResolvedPlayback() async {
    final resolved = await adapter.resolvePlayback(
      detail: detail,
      entry: _selectedEntry.value,
    );
    if (!_isDisposed) {
      _resolvedPlayback.value = resolved;
    }
    return resolved;
  }

  Future<void> _disposeController(VesperPlayerController controller) async {
    try {
      await controller.clearSystemPlayback();
    } catch (_) {
      // System playback is optional and may already be unavailable during tear-down.
    }
    await controller.dispose();
  }

  Future<void> _configureSystemPlayback(
    VesperPlayerController controller,
    ResolvedMediaPlayback resolved,
  ) async {
    if (_isDisposed) {
      return;
    }
    try {
      final useLegacyCompatibility = await _preferTextureViewForPlayback();
      if (_isDisposed) {
        return;
      }
      final permissionStatus = await controller
          .getSystemPlaybackPermissionStatus();
      if (_isDisposed) {
        return;
      }
      _systemPlaybackPermissionStatus.value = permissionStatus;
      await controller.configureSystemPlayback(
        mediaPlayerSystemPlaybackConfiguration(
          metadata: _systemPlaybackMetadataForResolved(resolved),
          backgroundMode: useLegacyCompatibility
              ? VesperBackgroundPlaybackMode.disabled
              : VesperBackgroundPlaybackMode.continueAudio,
        ),
      );
    } catch (error) {
      if (!_isDisposed) {
        _emitMessage('系统播放接入失败：${mediaErrorMessage(error)}');
      }
    }
  }

  Future<void> _handleExternalPlaybackEvent(
    VesperExternalPlaybackSessionEvent event,
  ) async {
    final controller = _controller;
    final resolved = _resolvedPlayback.value;
    if (controller == null || resolved == null || _isDisposed) {
      return;
    }

    if (event.routeId != VesperExternalPlaybackController.castRouteId) {
      return;
    }

    try {
      switch (event.kind) {
        case VesperExternalPlaybackSessionEventKind.routeConnected:
          final result = await _externalPlaybackForCast.loadFromPlayer(
            player: controller,
            source: resolved.toSource(),
            metadata: _systemPlaybackMetadataForResolved(resolved),
          );
          if (_isDisposed) return;
          _castPausedLocalPlayback = result.isSuccess;
          _castMessage.value = result.isSuccess
              ? '投屏已连接：${event.routeName ?? '外部设备'}'
              : result.message ?? '当前资源暂不支持投屏。';
        case VesperExternalPlaybackSessionEventKind.routeDisconnected:
          if (_castPausedLocalPlayback) {
            final positionMs = event.positionMs;
            if (positionMs != null) {
              final deltaMs =
                  positionMs - controller.snapshot.timeline.positionMs;
              await controller.seekBy(deltaMs);
            }
            await controller.play();
          }
          if (_isDisposed) return;
          _castPausedLocalPlayback = false;
          _castMessage.value = '投屏已断开，本地播放已恢复。';
        case VesperExternalPlaybackSessionEventKind.suspended:
          if (_isDisposed) return;
          _castMessage.value = '投屏连接已暂停。';
        default:
      }
    } catch (error) {
      // 事件回调是 fire-and-forget 的流监听，async 回调内抛出的异常不会
      // 进入流的 onError，会成为 unhandled async error（如投屏断开瞬间
      // 控制器已被 dispose，seekBy/play 抛出的平台异常）。
      if (_isDisposed) return;
      _castPausedLocalPlayback = false;
      _castMessage.value = '投屏操作失败：${mediaErrorMessage(error)}';
    }
  }

  VesperSystemPlaybackMetadata _systemPlaybackMetadataForResolved(
    ResolvedMediaPlayback resolved,
  ) {
    final selectedEntry = _selectedEntry.value;
    final durationSeconds = selectedEntry.durationSeconds;
    final durationMs = durationSeconds > 0 ? durationSeconds * 1000 : null;
    return mediaPlayerSystemPlaybackMetadata(
      title: resolved.title,
      subtitle: resolved.subtitle,
      artist: detail.ownerName,
      artworkUri: selectedEntry.coverUrl ?? detail.coverUrl,
      contentUri: resolved.uri,
      durationMs: durationMs,
    );
  }

  Future<void> _persistHistory(
    VesperPlayerSnapshot snapshot, {
    MediaPlaybackEntry? entry,
  }) async {
    final historyStore = this.historyStore;
    if (historyStore == null) {
      return;
    }
    final selectedEntry = entry ?? _selectedEntry.value;
    await historyStore.saveEntry(
      MediaHistoryEntry(
        mediaId: detail.mediaId,
        entryId: selectedEntry.entryId,
        videoTitle: detail.title,
        pageTitle: selectedEntry.title,
        coverUrl: selectedEntry.coverUrl ?? detail.coverUrl,
        ownerName: detail.ownerName ?? '',
        playedAtMs: DateTime.now().millisecondsSinceEpoch,
        lastPositionMs: snapshot.timeline.positionMs,
        durationMs: snapshot.timeline.durationMs,
        platformExtras: selectedEntry.platformExtras,
      ),
    );
  }

  Future<void> _persistLatestHistory(
    VesperPlayerController controller, {
    required VesperPlayerSnapshot fallback,
  }) async {
    // Snapshot the selected entry synchronously: dispose() may dispose the
    // signal while this async body is awaiting controller.refresh().
    final selectedEntry = _selectedEntry.value;
    var snapshot = fallback;
    try {
      await controller.refresh();
      snapshot = controller.snapshot;
    } catch (_) {
      snapshot = fallback;
    }
    await _persistHistory(snapshot, entry: selectedEntry);
  }

  void _handleDlnaChanged() {
    if (_isDisposed) {
      return;
    }
    _dlnaState.value = _dlnaManager.state;
    _dlnaRoutes.value = _dlnaManager.routes;
    _dlnaMessage.value = _dlnaManager.message;
  }

  void _emitMessage(String message) {
    if (_isDisposed) {
      return;
    }
    _pendingMessage.value = message;
  }
}
