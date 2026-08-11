import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';

import '../adapter/media_platform_adapter.dart';
import '../capabilities/media_history.dart';
import '../models/media_detail.dart';
import '../models/media_playback_notice.dart';
import '../models/resolved_media.dart';
import '../player/media_text.dart';
import '../player/player_options.dart';
import 'media_external_playback_manager.dart';

/// 过时代际的播放器创建被取消（reload/dispose 后旧创建链才完成）。
final class _PlaybackSourceObsoleted implements Exception {
  const _PlaybackSourceObsoleted();
}

final class _TrackSelectionAvailability {
  const _TrackSelectionAvailability({
    required this.availability,
    required this.declaredTracks,
    required this.candidateTracks,
    this.unavailableReason,
  });

  final MediaQualityAvailability availability;
  final List<VesperMediaTrack> declaredTracks;
  final List<VesperMediaTrack> candidateTracks;
  final VesperTrackSupportReason? unavailableReason;
}

/// 通用播放编排：控制器生命周期、解析/恢复、清晰度/倍速/字幕、DLNA、
/// 系统播放与历史。
///
/// 平台差异全部收敛在 [MediaPlatformAdapter]：
/// - 解析：`adapter.resolvePlayback(detail, entry)`
/// - 清晰度：`resolved.qualityOptions` + `adapter.qualityPolicy`
/// - DLNA 格式适配：`adapter.dlnaConfig`
/// - 历史：`adapter.history`（可选，缺省不记录）
final class MediaPlaybackViewModel {
  MediaPlaybackViewModel({
    required MediaDetail detail,
    required MediaPlaybackEntry initialEntry,
    required MediaPlatformAdapter adapter,
    MediaHistoryStore? historyStore,
    this._initialResolvedPlayback,
    int initialPositionMs = 0,
    Future<bool> Function()? preferTextureViewForPlayback,
  }) : detail = detail,
       adapter = adapter,
       historyStore = historyStore ?? adapter.history,
       _selectedEntry = signal(initialEntry),
       _pendingInitialPositionMs = initialPositionMs > 0
           ? initialPositionMs
           : null,
       _preferTextureViewForPlayback =
           preferTextureViewForPlayback ?? _defaultPreferTextureView {
    _dlnaManager = MediaExternalPlaybackManager(
      detail: detail,
      formatAdaptation: adapter.dlnaConfig?.formatAdaptation,
    )..addListener(_handleDlnaChanged);
    _handleDlnaChanged();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _castEventsSubscription = _externalPlaybackForCast.events.listen(
        _handleExternalPlaybackEvent,
        onError: (Object _) {},
      );
    }
    // 未显式指定初始位置时，播放创建完成后从历史存储异步续播
    // （见 _applyHistoryResume）；这里无需预启动查询。
    _controllerFuture = signal(_trackControllerFuture(_createController()));
  }

  static Future<bool> _defaultPreferTextureView() async => false;

  /// 历史续播是否已应用（仅首次创建消费一次）。
  bool _historyResumeApplied = false;

  /// 切源代际：switchEntry 的 selectSource 前递增，使在途历史续播失效。
  int _sourceGeneration = 0;

  /// 用户操作代际：经 VM 的 seek 入口（seekToRatio/seekBy）时递增，
  /// 使在途历史续播失效。
  int _userSeekGeneration = 0;

  final MediaDetail detail;
  final MediaPlatformAdapter adapter;

  /// 历史存储：显式注入优先，缺省回退到 [MediaPlatformAdapter.history]。
  /// 未声明该能力的平台不记录观看历史。
  final MediaHistoryStore? historyStore;

  final VesperExternalPlaybackController _externalPlaybackForCast =
      VesperExternalPlaybackController();
  static const int _maxPlaybackRecoveryAttempts = 3;
  static const List<Duration> _playbackRecoveryBackoff = <Duration>[
    Duration.zero,
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ];
  static const Duration _playbackRecoverySuccessWindow = Duration(seconds: 5);

  late final Signal<Future<VesperPlayerController>> _controllerFuture;
  VesperPlayerController? _controller;

  /// 对外暴露的控制器：seek 感知代理（stage 手势 seek 使在途历史续播失效）。
  VesperPlayerController? _userController;
  int? _pendingInitialPositionMs;
  ResolvedMediaPlayback? _initialResolvedPlayback;
  final Future<bool> Function() _preferTextureViewForPlayback;
  late final Signal<MediaPlaybackEntry> _selectedEntry;
  final Signal<ResolvedMediaPlayback?> _resolvedPlayback =
      Signal<ResolvedMediaPlayback?>(null);
  final Signal<String?> _selectedQualityOptionId = Signal<String?>(null);
  final Signal<String?> _selectedCodecIdentity = Signal<String?>(null);
  final Signal<VesperPlayerError?> _suppressedPlaybackCommandError =
      Signal<VesperPlayerError?>(null);
  final Signal<VesperSystemPlaybackPermissionStatus>
  _systemPlaybackPermissionStatus =
      Signal<VesperSystemPlaybackPermissionStatus>(
        VesperSystemPlaybackPermissionStatus.notRequired,
      );
  final Signal<String?> _castMessage = Signal<String?>(null);
  final Signal<MediaDlnaState> _dlnaState = Signal<MediaDlnaState>(
    MediaDlnaState.idle,
  );
  final Signal<List<VesperExternalPlaybackRoute>> _dlnaRoutes =
      Signal<List<VesperExternalPlaybackRoute>>(
        const <VesperExternalPlaybackRoute>[],
      );
  final Signal<String?> _dlnaMessage = Signal<String?>(null);
  final Signal<String?> _pendingMessage = Signal<String?>(null);
  final Signal<MediaPlaybackRecoveryNotice?> _pendingPlaybackRecoveryNotice =
      Signal<MediaPlaybackRecoveryNotice?>(null);
  bool _castPausedLocalPlayback = false;
  final Signal<bool> _isFullscreen = Signal<bool>(false);
  bool _isDisposed = false;
  bool _playbackRecoveryInFlight = false;
  bool _playbackRecoveryFailureReported = false;
  bool _playbackSourceTransitionInFlight = false;
  int _playbackRecoveryAttempts = 0;
  int _playbackRecoveryGeneration = 0;
  int _controllerGeneration = 0;
  int _playbackSelectionGeneration = 0;
  final Set<String> _runtimeRejectedVideoTrackIds = <String>{};
  final Set<String> _handledRuntimeTrackRejections = <String>{};
  String? _pendingRuntimeFallbackTrackId;
  VesperPlayerError? _deferredPlaybackRecoveryError;
  StreamSubscription<VesperPlayerEvent>? _controllerEventsSubscription;
  Timer? _playbackRecoverySuccessTimer;
  StreamSubscription<VesperExternalPlaybackSessionEvent>?
  _castEventsSubscription;
  late final MediaExternalPlaybackManager _dlnaManager;

  Future<VesperPlayerController> get controllerFuture =>
      _controllerFuture.value;

  VesperPlayerController? get controller => _userController;

  MediaPlaybackEntry get selectedEntry => _selectedEntry.value;

  ResolvedMediaPlayback? get resolvedPlayback => _resolvedPlayback.value;

  String? get selectedQualityOptionId => _selectedQualityOptionId.value;

  String? get selectedCodecIdentity => _selectedCodecIdentity.value;

  /// Command rejections do not make otherwise healthy playback terminal.
  /// Subtitle failures are presented by their selection surface, while a
  /// fixed-track rejection is presented by the typed command result.
  String? playbackErrorMessage(VesperPlayerSnapshot snapshot) {
    final error = snapshot.lastError;
    if (error == null ||
        error.details['domain'] == 'subtitle' ||
        identical(error, _suppressedPlaybackCommandError.value)) {
      return null;
    }
    return error.message;
  }

  VesperSystemPlaybackPermissionStatus get systemPlaybackPermissionStatus =>
      _systemPlaybackPermissionStatus.value;

  String? get castMessage => _castMessage.value;

  MediaDlnaState get dlnaState => _dlnaState.value;

  List<VesperExternalPlaybackRoute> get dlnaRoutes => _dlnaRoutes.value;

  String? get dlnaMessage => _dlnaMessage.value;

  MediaExternalPlaybackManager get dlnaManager => _dlnaManager;

  bool get isFullscreen => _isFullscreen.value;

  String? consumePendingMessage() {
    if (_isDisposed) {
      return null;
    }
    final message = _pendingMessage.value;
    _pendingMessage.value = null;
    return message;
  }

  MediaPlaybackRecoveryNotice? consumePendingPlaybackRecoveryNotice() {
    if (_isDisposed) {
      return null;
    }
    final notice = _pendingPlaybackRecoveryNotice.value;
    _pendingPlaybackRecoveryNotice.value = null;
    return notice;
  }

  void setFullscreen(bool value) {
    if (_isDisposed) {
      return;
    }
    if (_isFullscreen.value == value) {
      return;
    }
    _isFullscreen.value = value;
  }

  /// 兜底监听创建 future 的取消错误：过时代际以 [_PlaybackSourceObsoleted]
  /// 结束（调用方不应收到已销毁实例），但旧 future 可能已无订阅者，
  /// 这里挂一个忽略监听避免 unhandled async error。
  static Future<VesperPlayerController> _trackControllerFuture(
    Future<VesperPlayerController> future,
  ) {
    unawaited(future.then<void>((_) {}, onError: (Object _) {}));
    return future;
  }

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

  Future<void> reloadCurrentPage() async {
    if (_isDisposed) {
      return;
    }
    _controllerGeneration += 1;
    _resetPlaybackRecoveryState(clearPendingNotice: true);
    final previous = _controller;
    final previousSnapshot = previous?.snapshot;
    _controller = null;
    _userController = null;
    if (previous != null && previousSnapshot != null) {
      if (previousSnapshot.lastError != null) {
        unawaited(_persistHistory(previousSnapshot));
      } else {
        await _persistLatestHistory(previous, fallback: previousSnapshot);
      }
    }
    if (previous != null) {
      await _disposeController(previous);
    }
    if (_isDisposed) {
      return;
    }
    _controllerFuture.value = _trackControllerFuture(_createController());
  }

  Future<String?> switchEntry(MediaPlaybackEntry entry) async {
    if (_isDisposed) {
      return null;
    }
    final controller = _controller;
    if (controller == null || entry.entryId == _selectedEntry.value.entryId) {
      return null;
    }
    // Reentrancy guard: a previous switch may still be resolving/selecting
    // its source. Let the in-flight transition finish untouched instead of
    // interleaving two resolvePlayback -> selectSource -> play chains that
    // would race on _selectedEntry/_resolvedPlayback writes.
    if (_playbackSourceTransitionInFlight) {
      return null;
    }

    _playbackSourceTransitionInFlight = true;
    _invalidatePlaybackSelectionRequests();
    _resetPlaybackRecoveryState(clearPendingNotice: true);
    // 切源前递增：在途的历史续播查询（绑定旧 source）立即失效，
    // 避免 selectSource 之后、_selectedEntry 更新之前返回的旧进度
    // 被 seek 到新 source。
    _sourceGeneration += 1;
    try {
      final currentSnapshot = controller.snapshot;
      unawaited(_persistHistory(currentSnapshot));
      final resolved = await adapter.resolvePlayback(
        detail: detail,
        entry: entry,
      );
      await controller.selectSource(resolved.toSource());
      await _configureSystemPlayback(controller, resolved);
      await controller.play();
      if (_isDisposed) {
        return null;
      }
      _selectedEntry.value = entry;
      _resolvedPlayback.value = resolved;
      _resetRuntimeTrackCapabilityState();
      _selectedQualityOptionId.value = null;
      _selectedCodecIdentity.value = null;
      return null;
    } catch (error) {
      return '切换分 P 失败：${mediaErrorMessage(error)}';
    } finally {
      _playbackSourceTransitionInFlight = false;
    }
  }

  Future<String?> loadCurrentEntryToDlna() async {
    if (_isDisposed) {
      return null;
    }
    try {
      final resolved = await _refreshCurrentResolvedPlayback();
      if (_isDisposed) {
        return null;
      }
      return _dlnaManager.loadMedia(
        resolved: resolved,
        selectedPage: _selectedEntry.value,
        refreshResolved: _refreshCurrentResolvedPlayback,
      );
    } catch (error) {
      return '投屏播放地址刷新失败：${mediaErrorMessage(error)}';
    }
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
    if (_playbackRecoveryAttempts >= _maxPlaybackRecoveryAttempts) {
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
          _playbackRecoveryAttempts < _maxPlaybackRecoveryAttempts) {
        final attempt = _playbackRecoveryAttempts + 1;
        _playbackRecoveryAttempts = attempt;
        _deferredPlaybackRecoveryError = null;
        final backoff = _playbackRecoveryBackoff[attempt - 1];
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
          _resolvedPlayback.value = resolved;
          await controller.selectSource(resolved.toSource());
          await _configureSystemPlayback(controller, resolved);
          if (resumeRatio != null && resumeRatio > 0) {
            await controller.seekToRatio(resumeRatio);
          }
          await controller.play();
          if (_isDisposed ||
              controllerGeneration != _controllerGeneration ||
              recoveryGeneration != _playbackRecoveryGeneration ||
              _playbackSourceTransitionInFlight) {
            return;
          }
          await Future<void>.delayed(Duration.zero);
          final deferredError = _deferredPlaybackRecoveryError;
          if (deferredError != null) {
            lastFailureMessage = deferredError.message;
            continue;
          }
          _schedulePlaybackRecoverySuccessReset(
            controllerGeneration,
            recoveryGeneration,
          );
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
        _playbackRecoveryAttempts >= _maxPlaybackRecoveryAttempts) {
      _emitPlaybackRecoveryFailure(lastFailureMessage);
    }
  }

  void _schedulePlaybackRecoverySuccessReset(
    int controllerGeneration, [
    int? expectedRecoveryGeneration,
  ]) {
    final recoveryGeneration =
        expectedRecoveryGeneration ?? _playbackRecoveryGeneration;
    _playbackRecoverySuccessTimer?.cancel();
    _playbackRecoverySuccessTimer = Timer(_playbackRecoverySuccessWindow, () {
      if (_isDisposed ||
          controllerGeneration != _controllerGeneration ||
          recoveryGeneration != _playbackRecoveryGeneration) {
        return;
      }
      _resetPlaybackRecoveryState(clearPendingNotice: false);
    });
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

  Future<String?> requestSystemPlaybackPermissions(
    VesperPlayerController controller,
  ) async {
    if (_isDisposed) {
      return null;
    }
    try {
      final permissionStatus = await controller
          .requestSystemPlaybackPermissions();
      if (_isDisposed) {
        return null;
      }
      _systemPlaybackPermissionStatus.value = permissionStatus;
      return null;
    } catch (error) {
      return '系统播放权限请求失败：${mediaErrorMessage(error)}';
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

  Future<String?> setPlaybackRate(double rate) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    try {
      await controller.setPlaybackRate(rate);
      return null;
    } catch (error) {
      return '倍速切换失败：${mediaErrorMessage(error)}';
    }
  }

  /// 用户 seek 入口（壳内所有 seek 调用走这里）：递增用户操作代际，
  /// 使在途的历史续播查询失效，避免慢 IO 返回后覆盖用户操作。
  /// 返回错误消息（null = 成功）；代际递增与错误处理分离，
  /// 失败时不会伪装成功。
  Future<String?> seekToRatio(double ratio) async {
    _userSeekGeneration += 1;
    final controller = _controller;
    if (controller == null) {
      return '播放器尚未准备好。';
    }
    try {
      await controller.seekToRatio(ratio);
      return null;
    } catch (error) {
      return '跳转失败：${mediaErrorMessage(error)}';
    }
  }

  /// 用户 seek 入口（相对增量形式），语义同 [seekToRatio]。
  Future<String?> seekBy(int deltaMs) async {
    _userSeekGeneration += 1;
    final controller = _controller;
    if (controller == null) {
      return '播放器尚未准备好。';
    }
    try {
      await controller.seekBy(deltaMs);
      return null;
    } catch (error) {
      return '跳转失败：${mediaErrorMessage(error)}';
    }
  }

  /// 选择清晰度选项；null 表示回到自动。
  Future<String?> selectQualityOption(String? optionId) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final nextCodecIdentity = optionId == null
        ? null
        : _selectedCodecIdentity.value;
    if (optionId != null) {
      final option = _qualitySelectionOption(
        controller.snapshot,
        optionId,
        codecIdentity: nextCodecIdentity,
      );
      if (option == null) {
        return '当前视频没有可用的清晰度轨道。';
      }
      if (!option.canSelect) {
        return _unavailableSelectionMessage(
          option.unavailableReason,
          noMatchingTracks: option.candidateTracks.isEmpty,
        );
      }
    }
    final selectionGeneration = ++_playbackSelectionGeneration;
    final result = await _applyPlaybackSelection(
      optionId: optionId,
      codecIdentity: nextCodecIdentity,
    );
    if (_isDisposed || selectionGeneration != _playbackSelectionGeneration) {
      return null;
    }
    if (result == null) {
      _selectedQualityOptionId.value = optionId;
      _selectedCodecIdentity.value = nextCodecIdentity;
    }
    return result;
  }

  /// 选择 codec 子策略（AV1/HEVC/AVC 等身份）；null 表示默认。
  Future<String?> selectCodecIdentity(String? identity) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final optionId = _selectedQualityOptionId.value;
    if (identity != null) {
      final availability = _codecSelectionAvailability(
        controller.snapshot,
        identity,
        optionId: optionId,
      );
      final label = _codecDisplayLabel(identity);
      if (availability.declaredTracks.isEmpty) {
        return '当前分辨率没有 $label 策略。';
      }
      if (availability.availability == MediaQualityAvailability.unavailable) {
        return '当前设备不支持 $label 策略。';
      }
    }
    final selectionGeneration = ++_playbackSelectionGeneration;
    final result = await _applyPlaybackSelection(
      optionId: optionId,
      codecIdentity: identity,
    );
    if (_isDisposed || selectionGeneration != _playbackSelectionGeneration) {
      return null;
    }
    if (result == null) {
      _selectedCodecIdentity.value = identity;
    }
    return result;
  }

  Future<String?> applyPlaybackSelection() {
    return _applyPlaybackSelection(
      optionId: _selectedQualityOptionId.value,
      codecIdentity: _selectedCodecIdentity.value,
    );
  }

  Future<String?> _applyPlaybackSelection({
    required String? optionId,
    required String? codecIdentity,
  }) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    try {
      if (optionId == null && codecIdentity == null) {
        await controller.setAbrPolicy(const VesperAbrPolicy.auto());
        return null;
      }

      final snapshot = controller.snapshot;
      final track = _selectBestTrackForPlaybackSelection(
        snapshot,
        optionId: optionId,
        codecIdentity: codecIdentity,
      );
      if (track == null) {
        return '当前视频没有可用的清晰度轨道。';
      }
      final nativeTrack = _nativeVideoTrack(snapshot, track.id);
      if (nativeTrack != null && snapshot.capabilities.supportsAbrFixedTrack) {
        await controller.setAbrPolicy(
          VesperAbrPolicy.fixedTrack(track.id),
          expectedCatalogRevision: snapshot.trackCatalog.catalogRevision,
        );
        return null;
      }

      final bitRate = track.bitRate;
      if (snapshot.capabilities.supportsAbrConstrained &&
          bitRate != null &&
          bitRate > 0) {
        await controller.setAbrPolicy(
          VesperAbrPolicy.constrained(maxBitRate: bitRate),
        );
        return null;
      }

      return '当前播放内核不支持切换到该清晰度。';
    } on VesperFixedTrackSelectionException catch (error) {
      _suppressCurrentPlaybackCommandError(controller);
      if (error.code == VesperFixedTrackSelectionErrorCode.staleCatalog) {
        try {
          await controller.refresh();
        } catch (_) {
          // The original typed rejection remains the actionable result.
          _suppressCurrentPlaybackCommandError(controller);
        }
      }
      return '清晰度切换失败：${_fixedTrackSelectionErrorMessage(error)}';
    } catch (error) {
      return '清晰度切换失败：${mediaErrorMessage(error)}';
    }
  }

  List<double> playbackRates(VesperPlayerSnapshot snapshot) {
    final rates = <double>{
      1.0,
      1.25,
      1.5,
      2.0,
      snapshot.playbackRate,
      ...snapshot.capabilities.supportedPlaybackRates,
    };
    final normalized = rates.where((value) => value > 0).toList()..sort();
    return normalized;
  }

  List<VesperMediaTrack> playbackSelectionTracks(
    VesperPlayerSnapshot snapshot,
  ) {
    final nativeTracks = snapshot.trackCatalog.videoTracks;
    if (nativeTracks.isNotEmpty) {
      return nativeTracks;
    }
    final manifestTracks =
        _resolvedPlayback.value?.videoTracks ?? const <VesperMediaTrack>[];
    if (manifestTracks.isNotEmpty) {
      return manifestTracks;
    }
    return nativeTracks;
  }

  /// 当前解析结果提供的清晰度选项（适配器已分组）。
  List<MediaQualityOption> availableQualityOptions() {
    return _resolvedPlayback.value?.qualityOptions ??
        const <MediaQualityOption>[];
  }

  /// 将解析阶段的清晰度分组与最新 SDK track catalog 能力合并。
  List<MediaQualitySelectionOption> qualitySelectionOptions(
    VesperPlayerSnapshot snapshot, {
    String? codecIdentity,
  }) {
    final effectiveCodecIdentity =
        codecIdentity ?? _selectedCodecIdentity.value;
    return availableQualityOptions()
        .map((option) {
          final availability = _optionSelectionAvailability(
            snapshot,
            option,
            codecIdentity: effectiveCodecIdentity,
          );
          return MediaQualitySelectionOption(
            option: option,
            availability: availability.availability,
            candidateTracks: availability.candidateTracks,
            unavailableReason: availability.unavailableReason,
          );
        })
        .toList(growable: false);
  }

  MediaQualityAvailability codecSelectionAvailability(
    VesperPlayerSnapshot snapshot,
    String identity, {
    String? optionId,
  }) {
    return _codecSelectionAvailability(
      snapshot,
      identity,
      optionId: optionId,
    ).availability;
  }

  String? qualitySelectionSupportingText(MediaQualitySelectionOption option) {
    return switch (option.availability) {
      MediaQualityAvailability.available => null,
      MediaQualityAvailability.unknown => '兼容性未知',
      MediaQualityAvailability.unavailable =>
        option.candidateTracks.isEmpty
            ? option.unavailableReason == null
                  ? '当前清晰度无此编码'
                  : '清晰度暂不可用'
            : _unavailableSelectionSupportingText(option.unavailableReason),
    };
  }

  String? codecSelectionSupportingText(
    VesperPlayerSnapshot snapshot,
    String identity, {
    String? optionId,
  }) {
    final availability = _codecSelectionAvailability(
      snapshot,
      identity,
      optionId: optionId,
    );
    return switch (availability.availability) {
      MediaQualityAvailability.available => null,
      MediaQualityAvailability.unknown => '兼容性未知',
      MediaQualityAvailability.unavailable =>
        availability.declaredTracks.isEmpty
            ? '当前清晰度无此编码'
            : _unavailableSelectionSupportingText(
                availability.unavailableReason,
              ),
    };
  }

  /// 是否支持 codec 细分选择（平台声明）。
  bool get supportsCodecSelection =>
      _resolvedPlayback.value?.supportsCodecSelection ?? false;

  List<VesperMediaTrack> subtitleTracks(VesperPlayerSnapshot snapshot) {
    return snapshot.trackCatalog.subtitleTracks;
  }

  VesperTrackSelection subtitleSelection(VesperPlayerSnapshot snapshot) {
    return snapshot.trackSelection.confirmedSubtitle;
  }

  Future<String?> selectSubtitle(VesperTrackSelection selection) async {
    final controller = _controller;
    if (controller == null) {
      return '播放器尚未准备好。';
    }
    final snapshot = controller.snapshot;
    if (!snapshot.capabilities.supportsSubtitleTrackSelection) {
      return '当前播放内核不支持字幕切换。';
    }
    try {
      await controller.setSubtitleTrackSelection(selection);
      return null;
    } on VesperSubtitleException catch (error) {
      return '字幕切换失败：${_subtitleSelectionErrorMessage(error)}';
    } catch (error) {
      return '字幕切换失败：${mediaErrorMessage(error)}';
    }
  }

  String playbackStateLabel(VesperPlayerSnapshot snapshot) {
    return switch (snapshot.playbackState) {
      VesperPlaybackState.ready => '就绪',
      VesperPlaybackState.playing => '播放中',
      VesperPlaybackState.paused => '已暂停',
      VesperPlaybackState.finished => '已结束',
    };
  }

  VesperMediaTrack? _nativeVideoTrack(
    VesperPlayerSnapshot snapshot,
    String trackId,
  ) {
    for (final track in snapshot.trackCatalog.videoTracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  bool _canAttemptExplicitTrack(
    VesperPlayerSnapshot snapshot,
    VesperMediaTrack track,
  ) {
    if (_runtimeRejectedVideoTrackIds.contains(track.id)) {
      return false;
    }
    final nativeTrack = _nativeVideoTrack(snapshot, track.id);
    return (nativeTrack?.support ?? track.support).canAttemptExplicitSelection;
  }

  MediaQualitySelectionOption? _qualitySelectionOption(
    VesperPlayerSnapshot snapshot,
    String optionId, {
    String? codecIdentity,
  }) {
    for (final option in availableQualityOptions()) {
      if (option.id == optionId) {
        final availability = _optionSelectionAvailability(
          snapshot,
          option,
          codecIdentity: codecIdentity,
        );
        return MediaQualitySelectionOption(
          option: option,
          availability: availability.availability,
          candidateTracks: availability.candidateTracks,
          unavailableReason: availability.unavailableReason,
        );
      }
    }
    return null;
  }

  _TrackSelectionAvailability _optionSelectionAvailability(
    VesperPlayerSnapshot snapshot,
    MediaQualityOption option, {
    String? codecIdentity,
  }) {
    final identityForTrack = adapter.qualityPolicy.codecStrategyIdentityFor;
    final declaredTracks = option.tracks
        .where(
          (track) =>
              codecIdentity == null ||
              identityForTrack?.call(track) == codecIdentity,
        )
        .toList(growable: false);
    return _trackSelectionAvailability(snapshot, declaredTracks);
  }

  _TrackSelectionAvailability _codecSelectionAvailability(
    VesperPlayerSnapshot snapshot,
    String identity, {
    String? optionId,
  }) {
    final identityForTrack = adapter.qualityPolicy.codecStrategyIdentityFor;
    final declaredTracks = <VesperMediaTrack>[];
    for (final option in availableQualityOptions()) {
      if (optionId != null && option.id != optionId) {
        continue;
      }
      declaredTracks.addAll(
        option.tracks.where(
          (track) => identityForTrack?.call(track) == identity,
        ),
      );
    }
    return _trackSelectionAvailability(snapshot, declaredTracks);
  }

  _TrackSelectionAvailability _trackSelectionAvailability(
    VesperPlayerSnapshot snapshot,
    List<VesperMediaTrack> declaredTracks,
  ) {
    if (declaredTracks.isEmpty) {
      return const _TrackSelectionAvailability(
        availability: MediaQualityAvailability.unavailable,
        declaredTracks: <VesperMediaTrack>[],
        candidateTracks: <VesperMediaTrack>[],
      );
    }
    final nativeTracks = snapshot.trackCatalog.videoTracks;
    final candidateTracks = nativeTracks.isEmpty
        ? List<VesperMediaTrack>.of(declaredTracks)
        : () {
            final tracksById = <String, VesperMediaTrack>{
              for (final track in nativeTracks) track.id: track,
            };
            return declaredTracks
                .map((track) => tracksById[track.id])
                .whereType<VesperMediaTrack>()
                .toList(growable: false);
          }();
    if (candidateTracks.isEmpty) {
      return _TrackSelectionAvailability(
        availability: MediaQualityAvailability.unavailable,
        declaredTracks: declaredTracks,
        candidateTracks: candidateTracks,
        unavailableReason: VesperTrackSupportReason.platformUnknown,
      );
    }

    var hasUnknown = false;
    VesperTrackSupportReason? unavailableReason;
    for (final track in candidateTracks) {
      if (_runtimeRejectedVideoTrackIds.contains(track.id)) {
        unavailableReason ??= VesperTrackSupportReason.runtimeFailure;
        continue;
      }
      switch (track.support.status) {
        case VesperTrackSupportStatus.supported:
          return _TrackSelectionAvailability(
            availability: MediaQualityAvailability.available,
            declaredTracks: declaredTracks,
            candidateTracks: candidateTracks,
          );
        case VesperTrackSupportStatus.unknown:
          hasUnknown = true;
        case VesperTrackSupportStatus.exceedsCapabilities:
        case VesperTrackSupportStatus.unsupported:
          unavailableReason ??= track.support.reason;
      }
    }
    return _TrackSelectionAvailability(
      availability: hasUnknown
          ? MediaQualityAvailability.unknown
          : MediaQualityAvailability.unavailable,
      declaredTracks: declaredTracks,
      candidateTracks: candidateTracks,
      unavailableReason: hasUnknown ? null : unavailableReason,
    );
  }

  String _unavailableSelectionMessage(
    VesperTrackSupportReason? reason, {
    required bool noMatchingTracks,
  }) {
    if (noMatchingTracks) {
      return '当前清晰度没有匹配的播放轨道。';
    }
    return switch (reason) {
      VesperTrackSupportReason.routeUnavailable ||
      VesperTrackSupportReason.presentationUnavailable => '当前播放链路不支持该清晰度。',
      VesperTrackSupportReason.unsupportedDrm => '当前内容保护方式不支持该清晰度。',
      _ => '当前设备无法播放该清晰度。',
    };
  }

  String _unavailableSelectionSupportingText(VesperTrackSupportReason? reason) {
    return switch (reason) {
      VesperTrackSupportReason.routeUnavailable ||
      VesperTrackSupportReason.presentationUnavailable => '当前播放链路不支持',
      VesperTrackSupportReason.unsupportedDrm => '内容保护方式不支持',
      VesperTrackSupportReason.runtimeFailure => '本次播放已自动降级',
      _ => '当前设备不支持',
    };
  }

  /// 策略身份的展示文案：显式规范标签优先；缺省取组内首个匹配
  /// 身份轨道的展示 label——身份是内部键，绝不直接显示。
  String _codecDisplayLabel(String identity) {
    final explicit = adapter.qualityPolicy.codecIdentityLabelFor?.call(
      identity,
    );
    if (explicit != null) {
      return explicit;
    }
    final labelFor = adapter.qualityPolicy.codecLabelFor;
    final identityFor = adapter.qualityPolicy.codecStrategyIdentityFor;
    for (final option in availableQualityOptions()) {
      for (final track in option.tracks) {
        if (identityFor?.call(track) == identity) {
          final label = labelFor?.call(track);
          if (label != null) {
            return label;
          }
        }
      }
    }
    return identity;
  }

  VesperMediaTrack? _selectBestTrackForPlaybackSelection(
    VesperPlayerSnapshot snapshot, {
    required String? optionId,
    required String? codecIdentity,
  }) {
    final tracks = _sortedVideoTracks(playbackSelectionTracks(snapshot));
    Iterable<VesperMediaTrack> candidates = tracks.where(
      (track) => _canAttemptExplicitTrack(snapshot, track),
    );
    if (optionId != null) {
      final option = _qualitySelectionOption(
        snapshot,
        optionId,
        codecIdentity: codecIdentity,
      );
      final optionTracks = _sortedVideoTracks(
        option?.candidateTracks ?? const <VesperMediaTrack>[],
      );
      candidates = optionTracks.where(
        (track) => _canAttemptExplicitTrack(snapshot, track),
      );
    }

    if (codecIdentity != null) {
      final identityForTrack = adapter.qualityPolicy.codecStrategyIdentityFor;
      final codecMatches = candidates
          .where((track) => identityForTrack?.call(track) == codecIdentity)
          .toList(growable: false);
      return codecMatches.isEmpty ? null : codecMatches.first;
    }

    for (final candidate in candidates) {
      return candidate;
    }
    return null;
  }

  String _fixedTrackSelectionErrorMessage(
    VesperFixedTrackSelectionException error,
  ) {
    if (error.codeRawValue == 'runtimeTrackRejected') {
      return '当前设备无法继续播放该清晰度，已恢复自动选择。';
    }
    return switch (error.code) {
      VesperFixedTrackSelectionErrorCode.trackUnavailable => '该清晰度已不可用，请重新选择。',
      VesperFixedTrackSelectionErrorCode.trackExceedsCapabilities =>
        '当前设备无法播放该清晰度。',
      VesperFixedTrackSelectionErrorCode.trackUnsupported => '当前播放内核不支持该清晰度。',
      VesperFixedTrackSelectionErrorCode.staleCatalog => '清晰度列表已更新，请重试。',
      VesperFixedTrackSelectionErrorCode.unknown => '当前无法切换到该清晰度。',
    };
  }

  void _suppressCurrentPlaybackCommandError(VesperPlayerController controller) {
    if (_isDisposed) {
      return;
    }
    final commandError = controller.snapshot.lastError;
    if (commandError != null) {
      _suppressedPlaybackCommandError.value = commandError;
    }
  }

  String _subtitleSelectionErrorMessage(VesperSubtitleException error) {
    return switch (error.code) {
      'subtitle_selection_timeout' => '字幕轨道仍在准备，请稍后重试。',
      'subtitle_track_not_found' ||
      'subtitle_platform_track_unavailable' ||
      'subtitle_auto_candidate_unavailable' => '该字幕轨道暂不可用，请重新选择。',
      'subtitle_selection_superseded' ||
      'subtitle_selection_cancelled' ||
      'subtitle_source_changed' => '字幕选择已失效，请重试。',
      'subtitle_selection_invalid' ||
      'subtitle_selection_mismatch' => '当前无法应用该字幕选择。',
      'subtitle_resource_failed' ||
      'subtitle_manifest_parse_failed' ||
      'subtitle_transport_failure' => '字幕加载失败，请稍后重试。',
      'subtitle_uri_invalid' => '字幕地址无效，请重新选择。',
      'subtitle_encoding_unsupported' => '当前字幕编码不受支持。',
      'subtitle_default_track_ambiguous' ||
      'subtitle_request_identity_ambiguous' ||
      'subtitle_track_identity_ambiguous' => '字幕轨道无法唯一确定，请重新选择。',
      'subtitle_selection_failed' => '字幕切换失败，请稍后重试。',
      _ => error.retriable ? '字幕切换暂未完成，请稍后重试。' : '当前无法切换字幕。',
    };
  }

  List<VesperMediaTrack> _sortedVideoTracks(List<VesperMediaTrack> tracks) {
    final sorted = List<VesperMediaTrack>.of(tracks);
    sorted.sort((left, right) {
      final heightCompare = (right.height ?? 0).compareTo(left.height ?? 0);
      if (heightCompare != 0) {
        return heightCompare;
      }
      final bitRateCompare = (right.bitRate ?? 0).compareTo(left.bitRate ?? 0);
      if (bitRateCompare != 0) {
        return bitRateCompare;
      }
      return (left.codec ?? '').compareTo(right.codec ?? '');
    });
    return sorted;
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

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _controllerGeneration += 1;
    _playbackRecoveryGeneration += 1;
    _playbackRecoverySuccessTimer?.cancel();
    final controller = _controller;
    final snapshot = controller?.snapshot;
    if (controller != null && snapshot != null) {
      unawaited(_persistLatestHistory(controller, fallback: snapshot));
    }
    unawaited(_controllerEventsSubscription?.cancel() ?? Future<void>.value());
    unawaited(_castEventsSubscription?.cancel() ?? Future<void>.value());
    _externalPlaybackForCast.dispose();
    _dlnaManager.removeListener(_handleDlnaChanged);
    _dlnaManager.dispose();
    _controller = null;
    _userController = null;
    if (controller != null) {
      unawaited(_disposeController(controller));
    }
    _selectedEntry.dispose();
    _controllerFuture.dispose();
    _resolvedPlayback.dispose();
    _selectedQualityOptionId.dispose();
    _selectedCodecIdentity.dispose();
    _suppressedPlaybackCommandError.dispose();
    _systemPlaybackPermissionStatus.dispose();
    _castMessage.dispose();
    _dlnaState.dispose();
    _dlnaRoutes.dispose();
    _dlnaMessage.dispose();
    _pendingMessage.dispose();
    _pendingPlaybackRecoveryNotice.dispose();
    _isFullscreen.dispose();
  }
}

/// 用户 seek 感知的播放控制器代理：转发全部公开成员，
/// 仅拦截 seek 入口（seekBy/seekToRatio）通知回调。
///
/// SDK 的 `VesperPlayerStage` 进度条直接调用原始 controller.seekToRatio，
/// 不经 view model——用代理替换对外暴露的 controller 后，
/// 主播放器手势 seek 也能使在途历史续播失效。
final class _SeekAwareController implements VesperPlayerController {
  _SeekAwareController(this._inner, this._onUserSeek);

  final VesperPlayerController _inner;
  final VoidCallback _onUserSeek;

  @override
  String get playerId => _inner.playerId;

  @override
  ValueNotifier<VesperPlayerSnapshot> get snapshotListenable =>
      _inner.snapshotListenable;

  @override
  VesperPlayerSnapshot get snapshot => _inner.snapshot;

  @override
  VesperPlayerPlatform get platformForSequence => _inner.platformForSequence;

  @override
  List<VesperPluginDiagnostic> get pluginDiagnostics =>
      _inner.pluginDiagnostics;

  @override
  VesperPlayerCapabilities get capabilities => _inner.capabilities;

  @override
  Stream<VesperPlayerEvent> get events => _inner.events;

  @override
  Stream<VesperPlayerSnapshot> get snapshots => _inner.snapshots;

  @override
  Stream<VesperPlayerPictureInPictureEvent> get pictureInPictureEvents =>
      _inner.pictureInPictureEvents;

  @override
  Future<VesperPlaybackCapabilityProbeResult> probeAssociatedPlaybackCapability(
    VesperPlaybackCapabilityProbeRequest request,
  ) => _inner.probeAssociatedPlaybackCapability(request);

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  Future<void> selectSource(VesperPlayerSource source) =>
      _inner.selectSource(source);

  @override
  Future<void> refresh() => _inner.refresh();

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> togglePause() => _inner.togglePause();

  @override
  Future<void> stop() => _inner.stop();

  @override
  Future<void> seekBy(int deltaMs) {
    _onUserSeek();
    return _inner.seekBy(deltaMs);
  }

  @override
  Future<void> seekToRatio(double ratio) {
    _onUserSeek();
    return _inner.seekToRatio(ratio);
  }

  @override
  Future<void> seekToLiveEdge() {
    // SDK Stage 的"回到直播"直接调用本方法：同样视为用户 seek。
    _onUserSeek();
    return _inner.seekToLiveEdge();
  }

  @override
  Future<void> setPlaybackRate(double rate) => _inner.setPlaybackRate(rate);

  @override
  Future<void> setVideoTrackSelection(VesperTrackSelection selection) =>
      _inner.setVideoTrackSelection(selection);

  @override
  Future<void> setAudioTrackSelection(VesperTrackSelection selection) =>
      _inner.setAudioTrackSelection(selection);

  @override
  Future<void> setSubtitleTrackSelection(VesperTrackSelection selection) =>
      _inner.setSubtitleTrackSelection(selection);

  @override
  Future<void> setSubtitleStyle(VesperSubtitleStyle style) =>
      _inner.setSubtitleStyle(style);

  @override
  Future<void> setAbrPolicy(
    VesperAbrPolicy policy, {
    int? expectedCatalogRevision,
  }) => _inner.setAbrPolicy(
    policy,
    expectedCatalogRevision: expectedCatalogRevision,
  );

  @override
  Future<void> setPlaybackResiliencePolicy(
    VesperPlaybackResiliencePolicy policy,
  ) => _inner.setPlaybackResiliencePolicy(policy);

  @override
  Future<void> setResiliencePolicy(VesperPlaybackResiliencePolicy policy) =>
      _inner.setResiliencePolicy(policy);

  @override
  Future<void> setKeepScreenOnDuringPlayback(bool enabled) =>
      _inner.setKeepScreenOnDuringPlayback(enabled);

  @override
  Future<void> updateViewport(VesperPlayerViewport viewport) =>
      _inner.updateViewport(viewport);

  @override
  Future<void> clearViewport() => _inner.clearViewport();

  @override
  Future<void> configureSystemPlayback(
    VesperSystemPlaybackConfiguration configuration,
  ) => _inner.configureSystemPlayback(configuration);

  @override
  Future<void> updateSystemPlaybackMetadata(
    VesperSystemPlaybackMetadata metadata,
  ) => _inner.updateSystemPlaybackMetadata(metadata);

  @override
  Future<void> clearSystemPlayback() => _inner.clearSystemPlayback();

  @override
  Future<VesperPictureInPictureAvailability> isPictureInPictureAvailable() =>
      _inner.isPictureInPictureAvailable();

  @override
  Future<void> requestPictureInPicture({
    VesperPictureInPictureConfiguration? configuration,
  }) => _inner.requestPictureInPicture(configuration: configuration);

  @override
  Future<void> exitPictureInPicture() => _inner.exitPictureInPicture();

  @override
  Future<void> setPictureInPictureConfiguration(
    VesperPictureInPictureConfiguration configuration,
  ) => _inner.setPictureInPictureConfiguration(configuration);

  @override
  Future<VesperSystemPlaybackPermissionStatus>
  requestSystemPlaybackPermissions() =>
      _inner.requestSystemPlaybackPermissions();

  @override
  Future<VesperSystemPlaybackPermissionStatus>
  getSystemPlaybackPermissionStatus() =>
      _inner.getSystemPlaybackPermissionStatus();
}
