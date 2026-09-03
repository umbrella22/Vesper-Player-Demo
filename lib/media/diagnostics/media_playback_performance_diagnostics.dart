import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';
import 'package:vesper_player/vesper_player.dart';

import '../danmaku/media_danmaku_overlay.dart';

// Public named parameters intentionally initialize private implementation state.
// ignore_for_file: prefer_initializing_formals

const bool mediaPerformanceDiagnosticsAvailable = !kReleaseMode;

enum MediaPerformanceDiagnosticsPhase {
  idle,
  starting,
  running,
  waitingForPlayback,
  warmingUp,
  sampling,
  stopping,
  finished,
  failed,
}

final class MediaPerformanceDiagnosticsViewState {
  const MediaPerformanceDiagnosticsViewState({
    this.phase = MediaPerformanceDiagnosticsPhase.idle,
    this.sessionActive = false,
    this.guidedActive = false,
    this.guidedSegmentIndex,
    this.expectedOverlayActive,
    this.status = '尚未开始采集',
    this.errorCode,
    this.report,
  });

  final MediaPerformanceDiagnosticsPhase phase;
  final bool sessionActive;
  final bool guidedActive;
  final int? guidedSegmentIndex;
  final bool? expectedOverlayActive;
  final String status;
  final String? errorCode;
  final VesperPerformanceDiagnosticsReport? report;

  bool get busy =>
      phase == MediaPerformanceDiagnosticsPhase.starting ||
      phase == MediaPerformanceDiagnosticsPhase.stopping;

  MediaPerformanceDiagnosticsViewState copyWith({
    MediaPerformanceDiagnosticsPhase? phase,
    bool? sessionActive,
    bool? guidedActive,
    Object? guidedSegmentIndex = _unchanged,
    Object? expectedOverlayActive = _unchanged,
    String? status,
    Object? errorCode = _unchanged,
    Object? report = _unchanged,
  }) {
    return MediaPerformanceDiagnosticsViewState(
      phase: phase ?? this.phase,
      sessionActive: sessionActive ?? this.sessionActive,
      guidedActive: guidedActive ?? this.guidedActive,
      guidedSegmentIndex: identical(guidedSegmentIndex, _unchanged)
          ? this.guidedSegmentIndex
          : guidedSegmentIndex as int?,
      expectedOverlayActive: identical(expectedOverlayActive, _unchanged)
          ? this.expectedOverlayActive
          : expectedOverlayActive as bool?,
      status: status ?? this.status,
      errorCode: identical(errorCode, _unchanged)
          ? this.errorCode
          : errorCode as String?,
      report: identical(report, _unchanged)
          ? this.report
          : report as VesperPerformanceDiagnosticsReport?,
    );
  }
}

abstract interface class MediaPerformanceDiagnosticsRun {
  String get runId;

  Future<void> updateOverlayState(VesperPerformanceOverlayState state);

  Future<void> recordMarker(
    String name, {
    double? value,
    int? sequenceIndex,
    bool? expectedOverlayActive,
  });

  Future<VesperPerformanceDiagnosticsReport> snapshot();

  Future<VesperPerformanceDiagnosticsReport> stop();
}

typedef MediaPerformanceDiagnosticsRunFactory =
    Future<MediaPerformanceDiagnosticsRun> Function(
      VesperPlayerController controller,
      VesperPerformanceDiagnosticsConfiguration configuration,
    );

typedef MediaDiagnosticsDelay = Future<void> Function(Duration duration);

final class MediaPlaybackPerformanceDiagnosticsController {
  MediaPlaybackPerformanceDiagnosticsController({
    required ValueChanged<bool?> onDanmakuEnabledOverride,
    MediaPerformanceDiagnosticsRunFactory? runFactory,
    MediaDiagnosticsDelay? delay,
    Duration snapshotInterval = const Duration(seconds: 1),
    Duration readinessTimeout = const Duration(seconds: 10),
    Duration warmupDuration = const Duration(seconds: 5),
    Duration transitionDuration = const Duration(seconds: 1),
    Duration cohortDuration = const Duration(seconds: 12),
  }) : _onDanmakuEnabledOverride = onDanmakuEnabledOverride,
       _runFactory = runFactory ?? _startVesperDiagnosticsRun,
       _delay = delay ?? Future<void>.delayed,
       _snapshotInterval = snapshotInterval,
       _readinessTimeout = readinessTimeout,
       _warmupDuration = warmupDuration,
       _transitionDuration = transitionDuration,
       _cohortDuration = cohortDuration;

  final ValueChanged<bool?> _onDanmakuEnabledOverride;
  final MediaPerformanceDiagnosticsRunFactory _runFactory;
  final MediaDiagnosticsDelay _delay;
  final Duration _snapshotInterval;
  final Duration _readinessTimeout;
  final Duration _warmupDuration;
  final Duration _transitionDuration;
  final Duration _cohortDuration;

  final Signal<MediaPerformanceDiagnosticsViewState> _state =
      Signal<MediaPerformanceDiagnosticsViewState>(
        const MediaPerformanceDiagnosticsViewState(),
      );
  final Signal<bool> _overlayReportingActive = Signal<bool>(false);

  ReadonlySignal<MediaPerformanceDiagnosticsViewState> get state => _state;
  ReadonlySignal<bool> get overlayReportingActive => _overlayReportingActive;

  VesperPlayerController? _controller;
  StreamSubscription<VesperPlayerSnapshot>? _playbackSubscription;
  VesperPlayerSnapshot? _latestPlaybackSnapshot;
  MediaPerformanceDiagnosticsRun? _run;
  Future<void>? _startFuture;
  Future<VesperPerformanceDiagnosticsReport?>? _stopFuture;
  Timer? _snapshotTimer;
  Future<void>? _snapshotFuture;
  bool _drawerVisible = false;
  bool _disposed = false;
  int _attachmentGeneration = 0;
  int _runGeneration = 0;
  int _guideGeneration = 0;
  VesperPerformanceSampleClass _guidedSampleClass =
      VesperPerformanceSampleClass.steady;
  bool? _guidedExpectedOverlayActive;
  MediaDanmakuOverlayMetrics _latestOverlayMetrics =
      const MediaDanmakuOverlayMetrics(
        active: false,
        loadedBasicItemCount: 0,
        loadedAdvancedItemCount: 0,
        advancedEffectsActive: false,
      );
  Future<void> _runCommandTail = Future<void>.value();

  void attach(VesperPlayerController controller) {
    if (_disposed || identical(_controller, controller)) {
      return;
    }
    final replacingController = _controller != null;
    final attachmentGeneration = ++_attachmentGeneration;
    final previousSubscription = _playbackSubscription;
    _controller = controller;
    _latestPlaybackSnapshot = controller.snapshot;
    _playbackSubscription = controller.snapshots.listen((snapshot) {
      if (!_disposed && attachmentGeneration == _attachmentGeneration) {
        _latestPlaybackSnapshot = snapshot;
      }
    });
    unawaited(previousSubscription?.cancel());
    if (replacingController && (_startFuture != null || _run != null)) {
      unawaited(interrupt());
    }
  }

  Future<void> start() {
    if (_disposed || _state.value.busy || _run != null) {
      return Future<void>.value();
    }
    final pendingStart = _startFuture;
    if (pendingStart != null) {
      return pendingStart;
    }
    final controller = _controller;
    if (!mediaPerformanceDiagnosticsAvailable || controller == null) {
      _fail('artifactUnavailable');
      return Future<void>.value();
    }

    final generation = ++_runGeneration;
    _publish(
      phase: MediaPerformanceDiagnosticsPhase.starting,
      status: '正在启动诊断探针',
      errorCode: null,
      report: null,
    );
    final completion = _startOnce(controller, generation);
    _startFuture = completion;
    return completion.whenComplete(() {
      if (identical(_startFuture, completion)) {
        _startFuture = null;
      }
    });
  }

  Future<void> _startOnce(
    VesperPlayerController controller,
    int generation,
  ) async {
    try {
      final run = await _runFactory(
        controller,
        const VesperPerformanceDiagnosticsConfiguration(
          includeRawEvents: false,
          maxRawEvents: 256,
        ),
      );
      if (_disposed ||
          generation != _runGeneration ||
          !identical(_controller, controller)) {
        await _stopDetachedRun(run);
        return;
      }
      _run = run;
      _publish(
        phase: MediaPerformanceDiagnosticsPhase.running,
        sessionActive: true,
        status: '正在采集，关闭此抽屉后帧样本计入稳态',
      );
      _scheduleSnapshots();
      _queueOverlayUpdate();
      await refreshSnapshot();
    } catch (error) {
      if (!_disposed &&
          generation == _runGeneration &&
          identical(_controller, controller)) {
        _fail(_diagnosticsErrorCode(error));
      }
    }
  }

  Future<VesperPerformanceDiagnosticsReport?> stop() {
    final pending = _stopFuture;
    if (pending != null) {
      return pending;
    }
    _runGeneration += 1;
    _cancelGuidedCollection(recordMarker: false);
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    if (_startFuture == null && _run == null) {
      return Future<VesperPerformanceDiagnosticsReport?>.value(
        _state.value.report,
      );
    }
    _publish(
      phase: MediaPerformanceDiagnosticsPhase.stopping,
      sessionActive: _run != null,
      status: '正在汇总诊断报告',
    );
    final completion = _stopOnce();
    _stopFuture = completion;
    return completion.whenComplete(() {
      if (identical(_stopFuture, completion)) {
        _stopFuture = null;
      }
    });
  }

  Future<VesperPerformanceDiagnosticsReport?> _stopOnce() async {
    final pendingStart = _startFuture;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (_) {
        // The matching start path owns its user-facing failure state.
      }
    }
    final run = _run;
    if (run == null) {
      final report = _state.value.report;
      if (!_disposed) {
        _publish(
          phase: MediaPerformanceDiagnosticsPhase.finished,
          sessionActive: false,
          guidedActive: false,
          guidedSegmentIndex: null,
          expectedOverlayActive: null,
          status: '采集已停止',
          errorCode: null,
          report: report,
        );
      }
      return report;
    }
    try {
      final pendingSnapshot = _snapshotFuture;
      if (pendingSnapshot != null) {
        await pendingSnapshot;
      }
      await _runCommandTail;
      final report = await run.stop();
      if (identical(_run, run)) {
        _run = null;
      }
      _publish(
        phase: MediaPerformanceDiagnosticsPhase.finished,
        sessionActive: false,
        guidedActive: false,
        guidedSegmentIndex: null,
        expectedOverlayActive: null,
        status: '采集已完成',
        errorCode: null,
        report: report,
      );
      return report;
    } catch (error) {
      if (identical(_run, run)) {
        _run = null;
      }
      _fail(_diagnosticsErrorCode(error));
      return null;
    }
  }

  Future<void> refreshSnapshot() {
    final pendingSnapshot = _snapshotFuture;
    if (pendingSnapshot != null) {
      return pendingSnapshot;
    }
    final run = _run;
    if (_disposed ||
        run == null ||
        _state.value.phase == MediaPerformanceDiagnosticsPhase.stopping) {
      return Future<void>.value();
    }
    final completion = _refreshSnapshotOnce(run);
    _snapshotFuture = completion;
    return completion.whenComplete(() {
      if (identical(_snapshotFuture, completion)) {
        _snapshotFuture = null;
      }
    });
  }

  Future<void> _refreshSnapshotOnce(MediaPerformanceDiagnosticsRun run) async {
    try {
      await _runCommandTail;
      final report = await run.snapshot();
      if (!_disposed && identical(_run, run)) {
        _publish(report: report, errorCode: null);
      }
    } catch (error) {
      if (!_disposed && identical(_run, run)) {
        _publish(
          status: '实时快照暂不可用，采集仍在继续',
          errorCode: _diagnosticsErrorCode(error),
        );
      }
    }
  }

  Future<void> runGuidedAb() async {
    if (_disposed || _state.value.guidedActive) {
      return;
    }
    if (_run == null) {
      await start();
    }
    final run = _run;
    if (_disposed || run == null) {
      return;
    }

    final generation = ++_guideGeneration;
    _guidedSampleClass = VesperPerformanceSampleClass.excluded;
    _guidedExpectedOverlayActive = null;
    _publish(
      phase: MediaPerformanceDiagnosticsPhase.waitingForPlayback,
      sessionActive: true,
      guidedActive: true,
      guidedSegmentIndex: null,
      expectedOverlayActive: null,
      status: '等待播放稳定且弹幕加载完成',
      errorCode: null,
    );
    _queueOverlayUpdate();

    try {
      final ready = await _waitUntilReady(generation);
      _ensureGuideActive(generation);
      if (!ready) {
        _restoreDanmakuOverride();
        _publish(
          phase: MediaPerformanceDiagnosticsPhase.running,
          guidedActive: false,
          status: '等待播放或弹幕超时，请确认视频正在播放后重试',
          errorCode: 'readinessTimeout',
        );
        return;
      }

      _publish(
        phase: MediaPerformanceDiagnosticsPhase.warmingUp,
        status: '预热中，此阶段不计入 A/B 对比',
      );
      await _recordMarker(run, 'guided_warmup_start');
      await _waitGuideDuration(_warmupDuration, generation);

      const sequence = <bool>[false, true, false, true];
      for (var index = 0; index < sequence.length; index += 1) {
        _ensureGuideActive(generation);
        final enabled = sequence[index];
        _guidedExpectedOverlayActive = enabled;
        _guidedSampleClass = VesperPerformanceSampleClass.transition;
        _onDanmakuEnabledOverride(enabled);
        _publish(
          phase: MediaPerformanceDiagnosticsPhase.sampling,
          guidedSegmentIndex: index,
          expectedOverlayActive: enabled,
          status: 'A/B ${index + 1}/4：弹幕${enabled ? '开启' : '关闭'}',
        );
        _queueOverlayUpdate();
        await _recordMarker(
          run,
          'guided_segment_start',
          sequenceIndex: index,
          expectedOverlayActive: enabled,
        );

        final transition = _transitionDuration > _cohortDuration
            ? _cohortDuration
            : _transitionDuration;
        await _waitGuideDuration(transition, generation);
        _guidedSampleClass = VesperPerformanceSampleClass.steady;
        _queueOverlayUpdate();
        await _waitGuideDuration(_cohortDuration - transition, generation);
      }

      _ensureGuideActive(generation);
      await _recordMarker(run, 'guided_sequence_complete');
      _restoreDanmakuOverride();
      _publish(
        phase: MediaPerformanceDiagnosticsPhase.running,
        guidedActive: false,
        guidedSegmentIndex: null,
        expectedOverlayActive: null,
        status: 'A/B 采集完成，正在生成报告',
      );
      await stop();
    } on _GuidedCollectionCancelled {
      // Cancellation restores the in-memory override synchronously.
    } catch (error) {
      _restoreDanmakuOverride();
      if (!_disposed && identical(_run, run)) {
        _publish(
          phase: MediaPerformanceDiagnosticsPhase.running,
          guidedActive: false,
          guidedSegmentIndex: null,
          expectedOverlayActive: null,
          status: 'A/B 采集已中止',
          errorCode: _diagnosticsErrorCode(error),
        );
      }
    }
  }

  void cancelGuidedCollection() {
    final run = _run;
    final wasGuided = _state.value.guidedActive;
    _cancelGuidedCollection(recordMarker: true);
    if (wasGuided && run != null && !_disposed) {
      _publish(
        phase: MediaPerformanceDiagnosticsPhase.running,
        guidedActive: false,
        guidedSegmentIndex: null,
        expectedOverlayActive: null,
        status: 'A/B 采集已取消，诊断会话仍在运行',
      );
    }
  }

  Future<void> interrupt() async {
    if (_disposed) {
      return;
    }
    _cancelGuidedCollection(recordMarker: false);
    await stop();
  }

  void setDrawerVisible(bool visible) {
    if (_disposed || _drawerVisible == visible) {
      return;
    }
    _drawerVisible = visible;
    _queueOverlayUpdate();
  }

  void updateOverlayMetrics(MediaDanmakuOverlayMetrics metrics) {
    if (_disposed || _latestOverlayMetrics == metrics) {
      return;
    }
    _latestOverlayMetrics = metrics;
    _queueOverlayUpdate();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _attachmentGeneration += 1;
    _runGeneration += 1;
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _cancelGuidedCollection(recordMarker: false);
    await _playbackSubscription?.cancel();
    _playbackSubscription = null;
    final pendingStop = _stopFuture;
    if (pendingStop != null) {
      try {
        await pendingStop;
      } catch (_) {
        // Page disposal is best-effort; the SDK controller also owns cleanup.
      }
    } else {
      final pendingStart = _startFuture;
      if (pendingStart != null) {
        try {
          await pendingStart;
        } catch (_) {
          // A failed start has no native run left to release.
        }
      }
      final pendingSnapshot = _snapshotFuture;
      if (pendingSnapshot != null) {
        try {
          await pendingSnapshot;
        } catch (_) {
          // Snapshot failure does not prevent final session cleanup.
        }
      }
      final run = _run;
      _run = null;
      if (run != null) {
        try {
          await _runCommandTail;
          await run.stop();
        } catch (_) {
          // Page disposal is best-effort; the SDK controller also owns cleanup.
        }
      }
    }
    _overlayReportingActive.dispose();
    _state.dispose();
  }

  void _scheduleSnapshots() {
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer.periodic(_snapshotInterval, (_) {
      unawaited(refreshSnapshot());
    });
  }

  Future<bool> _waitUntilReady(int generation) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < _readinessTimeout) {
      _ensureGuideActive(generation);
      final playback = _latestPlaybackSnapshot;
      if (playback != null &&
          playback.playbackState == VesperPlaybackState.playing &&
          !playback.isBuffering &&
          _latestOverlayMetrics.hasItems) {
        return true;
      }
      await _waitGuideDuration(const Duration(milliseconds: 250), generation);
    }
    return false;
  }

  Future<void> _waitGuideDuration(Duration duration, int generation) async {
    var remaining = duration;
    while (remaining > Duration.zero) {
      _ensureGuideActive(generation);
      final step = remaining > const Duration(milliseconds: 250)
          ? const Duration(milliseconds: 250)
          : remaining;
      await _delay(step);
      remaining -= step;
    }
    _ensureGuideActive(generation);
  }

  void _ensureGuideActive(int generation) {
    if (_disposed ||
        generation != _guideGeneration ||
        !_state.value.guidedActive) {
      throw const _GuidedCollectionCancelled();
    }
  }

  void _cancelGuidedCollection({required bool recordMarker}) {
    final wasGuided = _state.value.guidedActive;
    _guideGeneration += 1;
    if (recordMarker && wasGuided) {
      final run = _run;
      if (run != null) {
        unawaited(_recordCancellationMarker(run));
      }
    }
    _restoreDanmakuOverride();
  }

  void _restoreDanmakuOverride() {
    _guidedSampleClass = VesperPerformanceSampleClass.steady;
    _guidedExpectedOverlayActive = null;
    _onDanmakuEnabledOverride(null);
    _queueOverlayUpdate();
  }

  void _queueOverlayUpdate() {
    final run = _run;
    if (_disposed || run == null) {
      return;
    }
    final metrics = _latestOverlayMetrics;
    final expectedActive = _guidedExpectedOverlayActive;
    final state = VesperPerformanceOverlayState(
      active: expectedActive ?? metrics.active,
      sampleClass: _drawerVisible
          ? VesperPerformanceSampleClass.excluded
          : _guidedSampleClass,
      loadedBasicItemCount: metrics.loadedBasicItemCount,
      loadedAdvancedItemCount: metrics.loadedAdvancedItemCount,
      advancedEffectsActive:
          (expectedActive ?? metrics.active) && metrics.advancedEffectsActive,
    );
    unawaited(_submitOverlayUpdate(run, state));
  }

  Future<void> _submitOverlayUpdate(
    MediaPerformanceDiagnosticsRun run,
    VesperPerformanceOverlayState state,
  ) async {
    try {
      await _enqueueRunCommand(run, () => run.updateOverlayState(state));
    } catch (error) {
      if (!_disposed && identical(_run, run)) {
        _publish(
          status: '弹幕状态样本暂未提交，帧采集仍在继续',
          errorCode: _diagnosticsErrorCode(error),
        );
      }
    }
  }

  Future<void> _recordMarker(
    MediaPerformanceDiagnosticsRun run,
    String name, {
    double? value,
    int? sequenceIndex,
    bool? expectedOverlayActive,
  }) {
    return _enqueueRunCommand(
      run,
      () => run.recordMarker(
        name,
        value: value,
        sequenceIndex: sequenceIndex,
        expectedOverlayActive: expectedOverlayActive,
      ),
    );
  }

  Future<void> _recordCancellationMarker(
    MediaPerformanceDiagnosticsRun run,
  ) async {
    try {
      await _recordMarker(run, 'guided_sequence_cancelled');
    } catch (error) {
      if (!_disposed && identical(_run, run)) {
        _publish(
          status: 'A/B 取消标记未写入，诊断会话仍在运行',
          errorCode: _diagnosticsErrorCode(error),
        );
      }
    }
  }

  Future<void> _enqueueRunCommand(
    MediaPerformanceDiagnosticsRun run,
    Future<void> Function() command,
  ) {
    final completion = _runCommandTail.then((_) async {
      if (!_disposed && identical(_run, run)) {
        await command();
      }
    });
    _runCommandTail = completion.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return completion;
  }

  Future<void> _stopDetachedRun(MediaPerformanceDiagnosticsRun run) async {
    try {
      await run.stop();
    } catch (_) {
      // The run was invalidated before activation; no UI owns this failure.
    }
  }

  void _fail(String code) {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _run = null;
    _restoreDanmakuOverride();
    if (_disposed) {
      return;
    }
    _publish(
      phase: MediaPerformanceDiagnosticsPhase.failed,
      sessionActive: false,
      guidedActive: false,
      guidedSegmentIndex: null,
      expectedOverlayActive: null,
      status: _diagnosticsErrorMessage(code),
      errorCode: code,
    );
  }

  void _publish({
    MediaPerformanceDiagnosticsPhase? phase,
    bool? sessionActive,
    bool? guidedActive,
    Object? guidedSegmentIndex = _unchanged,
    Object? expectedOverlayActive = _unchanged,
    String? status,
    Object? errorCode = _unchanged,
    Object? report = _unchanged,
  }) {
    if (_disposed) {
      return;
    }
    final next = _state.value.copyWith(
      phase: phase,
      sessionActive: sessionActive,
      guidedActive: guidedActive,
      guidedSegmentIndex: guidedSegmentIndex,
      expectedOverlayActive: expectedOverlayActive,
      status: status,
      errorCode: errorCode,
      report: report,
    );
    _state.value = next;
    if (_overlayReportingActive.value != next.sessionActive) {
      _overlayReportingActive.value = next.sessionActive;
    }
  }
}

final class _VesperPerformanceDiagnosticsRun
    implements MediaPerformanceDiagnosticsRun {
  const _VesperPerformanceDiagnosticsRun(this.session);

  final VesperPerformanceDiagnosticsSession session;

  @override
  String get runId => session.runId;

  @override
  Future<void> updateOverlayState(VesperPerformanceOverlayState state) =>
      session.updateOverlayState(state);

  @override
  Future<void> recordMarker(
    String name, {
    double? value,
    int? sequenceIndex,
    bool? expectedOverlayActive,
  }) => session.recordMarker(
    name,
    value: value,
    sequenceIndex: sequenceIndex,
    expectedOverlayActive: expectedOverlayActive,
  );

  @override
  Future<VesperPerformanceDiagnosticsReport> snapshot() => session.snapshot();

  @override
  Future<VesperPerformanceDiagnosticsReport> stop() => session.stop();
}

Future<MediaPerformanceDiagnosticsRun> _startVesperDiagnosticsRun(
  VesperPlayerController controller,
  VesperPerformanceDiagnosticsConfiguration configuration,
) async {
  final session = await controller.startPerformanceDiagnostics(
    configuration: configuration,
  );
  return _VesperPerformanceDiagnosticsRun(session);
}

String _diagnosticsErrorCode(Object error) {
  if (error is VesperPerformanceDiagnosticsException) {
    return error.code;
  }
  return 'internalFailure';
}

String _diagnosticsErrorMessage(String code) => switch (code) {
  'alreadyActive' => '当前播放器已有诊断任务',
  'artifactUnavailable' => '当前构建未包含原生诊断插件',
  'probeUnavailable' => '当前设备无法启用帧探针',
  'invalidConfiguration' => '诊断配置无效',
  'controllerDisposed' => '播放器会话已经结束',
  'protocolViolation' => '诊断插件返回了不兼容的数据',
  'readinessTimeout' => '等待播放或弹幕加载超时',
  _ => '诊断任务发生内部错误',
};

const Object _unchanged = Object();

final class _GuidedCollectionCancelled implements Exception {
  const _GuidedCollectionCancelled();
}
