import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VesperPlayerPlatform previousPlatform;
  late _DiagnosticsPlayerPlatform platform;
  late List<VesperPlayerController> playerControllers;
  late List<MediaPlaybackPerformanceDiagnosticsController>
  diagnosticsControllers;

  setUp(() {
    previousPlatform = VesperPlayerPlatform.instance;
    platform = _DiagnosticsPlayerPlatform();
    VesperPlayerPlatform.instance = platform;
    playerControllers = <VesperPlayerController>[];
    diagnosticsControllers = <MediaPlaybackPerformanceDiagnosticsController>[];
  });

  tearDown(() async {
    for (final controller in diagnosticsControllers.reversed) {
      await controller.dispose();
    }
    for (final controller in playerControllers.reversed) {
      await controller.dispose();
    }
    await platform.close();
    VesperPlayerPlatform.instance = previousPlatform;
  });

  Future<VesperPlayerController> createPlayer() async {
    final controller = await VesperPlayerController.create();
    playerControllers.add(controller);
    return controller;
  }

  MediaPlaybackPerformanceDiagnosticsController createDiagnostics({
    MediaPerformanceDiagnosticsRunFactory? runFactory,
    required ValueChanged<bool?> onOverride,
    MediaDiagnosticsDelay? delay,
    Duration readinessTimeout = const Duration(seconds: 10),
    Duration warmupDuration = const Duration(seconds: 5),
    Duration transitionDuration = const Duration(seconds: 1),
    Duration cohortDuration = const Duration(seconds: 12),
  }) {
    final controller = MediaPlaybackPerformanceDiagnosticsController(
      onDanmakuEnabledOverride: onOverride,
      runFactory: runFactory,
      delay: delay,
      snapshotInterval: const Duration(days: 1),
      readinessTimeout: readinessTimeout,
      warmupDuration: warmupDuration,
      transitionDuration: transitionDuration,
      cohortDuration: cohortDuration,
    );
    diagnosticsControllers.add(controller);
    return controller;
  }

  test(
    'host report counts frame timings and Vesper playback observations',
    () async {
      platform.initialSnapshot = platform.initialSnapshot.copyWith(
        isBuffering: true,
        playbackDiagnostics: const VesperPlaybackDiagnosticsSnapshot(
          playbackEpoch: 1,
        ),
      );
      final player = await createPlayer();
      final diagnostics = createDiagnostics(onOverride: (_) {})..attach(player);
      await diagnostics.start();
      final dispatcher = ui.PlatformDispatcher.instance;
      final firstFrame = dispatcher.frameData.frameNumber + 1;
      ui.FrameTiming timing(int frame, int loadUs) => ui.FrameTiming(
        frameNumber: frame,
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 100,
        rasterStart: 100,
        rasterFinish: 100 + loadUs,
        rasterFinishWallTime: 100 + loadUs,
      );
      final budgetUs = (diagnostics.state.value.report!.frameBudgetMs * 1000)
          .ceil();
      dispatcher.onReportTimings!([
        timing(firstFrame - 1, 10), // Delivered late from before collection.
        timing(firstFrame, budgetUs + 1),
      ]);
      diagnostics.setDrawerVisible(true);
      await Future<void>.delayed(Duration.zero);
      dispatcher.onReportTimings!([timing(firstFrame + 1, budgetUs * 3)]);
      platform._events.add(
        VesperPlayerSnapshotEvent(
          playerId: player.playerId,
          snapshot: player.snapshot.copyWith(isBuffering: false),
        ),
      );
      platform._events.add(
        VesperPlayerWarningEvent(
          playerId: player.playerId,
          warning: const VesperRuntimeWarning.playback(
            VesperPlaybackStallObservation(
              playbackEpoch: 1,
              kind: VesperPlaybackStallKind.bufferingTimeout,
              stalledForMs: 1000,
              elapsedSinceLoadStartMs: 3000,
              mediaPositionMs: 2000,
              audio: VesperAudioPlaybackDiagnostics(),
            ),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final report = (await diagnostics.stop())!;
      final steady = report.cohorts[MediaFrameGroup.overlayInactive]!;
      expect(steady.sampleCount, 1);
      expect(steady.jankCount, 1);
      expect(steady.severeJankCount, 0);
      expect(steady.p95LoadMs, (budgetUs + 1) / 1000);
      expect(report.cohorts[MediaFrameGroup.excluded]!.severeJankCount, 1);
      expect(report.bufferingCount, 1);
      expect(report.stallCount, 1);
      final wire = jsonDecode(report.toJson()) as Map<String, dynamic>;
      expect(wire['schema'], 'vesper_media.host_performance.v1');
      expect(wire['playback'], isNot(contains('droppedVideoFrames')));
    },
  );

  test('concurrent start requests create one diagnostics run', () async {
    final player = await createPlayer();
    final gate = Completer<void>();
    final run = _FakeDiagnosticsRun();
    var factoryCalls = 0;
    final diagnostics = createDiagnostics(
      onOverride: (_) {},
      runFactory: (_) async {
        factoryCalls += 1;
        await gate.future;
        return run;
      },
    )..attach(player);

    final first = diagnostics.start();
    final second = diagnostics.start();
    expect(factoryCalls, 1);

    gate.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(factoryCalls, 1);
    expect(diagnostics.state.value.sessionActive, isTrue);
    expect(run.snapshotCount, 1);
  });

  test('stop during start invalidates and releases the late run', () async {
    final player = await createPlayer();
    final gate = Completer<void>();
    final run = _FakeDiagnosticsRun();
    final diagnostics = createDiagnostics(
      onOverride: (_) {},
      runFactory: (_) async {
        await gate.future;
        return run;
      },
    )..attach(player);

    final starting = diagnostics.start();
    final stopping = diagnostics.stop();
    expect(
      diagnostics.state.value.phase,
      MediaPerformanceDiagnosticsPhase.stopping,
    );

    gate.complete();
    await starting;
    await stopping;

    expect(run.stopCount, 1);
    expect(run.snapshotCount, 0);
    expect(diagnostics.state.value.sessionActive, isFalse);
    expect(
      diagnostics.state.value.phase,
      MediaPerformanceDiagnosticsPhase.finished,
    );
  });

  test(
    'dispose during start releases the late run without reactivation',
    () async {
      final player = await createPlayer();
      final gate = Completer<void>();
      final run = _FakeDiagnosticsRun();
      final diagnostics = createDiagnostics(
        onOverride: (_) {},
        runFactory: (_) async {
          await gate.future;
          return run;
        },
      )..attach(player);

      final starting = diagnostics.start();
      final disposing = diagnostics.dispose();
      gate.complete();
      await Future.wait(<Future<void>>[starting, disposing]);

      expect(run.stopCount, 1);
      expect(run.snapshotCount, 0);
    },
  );

  test(
    'attaching a replacement player stops the previous player run',
    () async {
      final firstPlayer = await createPlayer();
      final secondPlayer = await createPlayer();
      final run = _FakeDiagnosticsRun();
      final diagnostics = createDiagnostics(
        onOverride: (_) {},
        runFactory: (_) async => run,
      )..attach(firstPlayer);
      await diagnostics.start();

      diagnostics.attach(secondPlayer);
      await diagnostics.stop();

      expect(run.stopCount, 1);
      expect(diagnostics.state.value.sessionActive, isFalse);
    },
  );

  test(
    'snapshot requests coalesce and stop waits for the in-flight snapshot',
    () async {
      final player = await createPlayer();
      final run = _FakeDiagnosticsRun();
      final diagnostics = createDiagnostics(
        onOverride: (_) {},
        runFactory: (_) async => run,
      )..attach(player);
      await diagnostics.start();
      expect(run.snapshotCount, 1);

      run.snapshotGate = Completer<void>();
      final firstSnapshot = diagnostics.refreshSnapshot();
      final secondSnapshot = diagnostics.refreshSnapshot();
      await Future<void>.delayed(Duration.zero);
      expect(run.snapshotCount, 2);

      final stopping = diagnostics.stop();
      await Future<void>.delayed(Duration.zero);
      expect(run.stopCount, 0);

      run.snapshotGate!.complete();
      await Future.wait(<Future<void>>[firstSnapshot, secondSnapshot]);
      final report = await stopping;
      final cachedReport = await diagnostics.stop();

      expect(run.snapshotCount, 2);
      expect(run.stopCount, 1);
      expect(identical(report, cachedReport), isTrue);
    },
  );

  test(
    'guided A/B records off-on-off-on transition and steady cohorts',
    () async {
      final player = await createPlayer();
      final run = _FakeDiagnosticsRun();
      final overrides = <bool?>[];
      final delays = <Duration>[];
      final diagnostics = createDiagnostics(
        onOverride: overrides.add,
        runFactory: (_) async => run,
        delay: (duration) async {
          delays.add(duration);
        },
        warmupDuration: Duration.zero,
        transitionDuration: const Duration(milliseconds: 1),
        cohortDuration: const Duration(milliseconds: 2),
      )..attach(player);
      diagnostics.updateOverlayMetrics(
        const MediaDanmakuOverlayMetrics(
          active: true,
          loadedBasicItemCount: 12,
          loadedAdvancedItemCount: 3,
          advancedEffectsActive: true,
        ),
      );

      await diagnostics.runGuidedAb();

      expect(overrides.take(4), <bool>[false, true, false, true]);
      expect(overrides.last, isNull);
      expect(run.markers, <String>[
        'guided_warmup_start',
        'guided_segment_start:0:false',
        'guided_segment_start:1:true',
        'guided_segment_start:2:false',
        'guided_segment_start:3:true',
        'guided_sequence_complete',
      ]);
      expect(
        run.overlayStates
            .where(
              (state) =>
                  state.sampleClass == MediaPerformanceSampleClass.transition ||
                  state.sampleClass == MediaPerformanceSampleClass.steady,
            )
            .map((state) => '${state.sampleClass.name}:${state.active}'),
        containsAllInOrder(<String>[
          'transition:false',
          'steady:false',
          'transition:true',
          'steady:true',
          'transition:false',
          'steady:false',
          'transition:true',
          'steady:true',
        ]),
      );
      expect(delays, hasLength(8));
      expect(run.stopCount, 1);
      expect(
        diagnostics.state.value.phase,
        MediaPerformanceDiagnosticsPhase.finished,
      );
    },
  );

  test('guided readiness timeout restores the temporary override', () async {
    platform.initialSnapshot = const VesperPlayerSnapshot.initial();
    final player = await createPlayer();
    final run = _FakeDiagnosticsRun();
    final overrides = <bool?>[];
    final diagnostics = createDiagnostics(
      onOverride: overrides.add,
      runFactory: (_) async => run,
      readinessTimeout: Duration.zero,
    )..attach(player);

    await diagnostics.runGuidedAb();

    expect(overrides.last, isNull);
    expect(diagnostics.state.value.guidedActive, isFalse);
    expect(diagnostics.state.value.errorCode, 'readinessTimeout');
    expect(run.stopCount, 0);
  });

  test('guided cancellation marker is serialized before stop', () async {
    final player = await createPlayer();
    final run = _FakeDiagnosticsRun()
      ..cancellationMarkerGate = Completer<void>();
    final warmupGate = Completer<void>();
    final warmupEntered = Completer<void>();
    final overrides = <bool?>[];
    var delayCalls = 0;
    final diagnostics = createDiagnostics(
      onOverride: overrides.add,
      runFactory: (_) async => run,
      delay: (_) {
        delayCalls += 1;
        if (delayCalls == 1) {
          warmupEntered.complete();
          return warmupGate.future;
        }
        return Future<void>.value();
      },
      warmupDuration: const Duration(milliseconds: 1),
      transitionDuration: const Duration(milliseconds: 1),
      cohortDuration: const Duration(milliseconds: 2),
    )..attach(player);
    diagnostics.updateOverlayMetrics(
      const MediaDanmakuOverlayMetrics(
        active: true,
        loadedBasicItemCount: 1,
        loadedAdvancedItemCount: 0,
        advancedEffectsActive: false,
      ),
    );

    final guided = diagnostics.runGuidedAb();
    await warmupEntered.future;
    diagnostics.cancelGuidedCollection();
    expect(overrides.last, isNull);

    final stopping = diagnostics.stop();
    await Future<void>.delayed(Duration.zero);
    expect(run.stopCount, 0);

    run.cancellationMarkerGate!.complete();
    await stopping;
    warmupGate.complete();
    await guided;

    expect(run.stopCount, 1);
    expect(
      run.operations.indexOf('marker:guided_sequence_cancelled'),
      lessThan(run.operations.indexOf('stop')),
    );
  });
}

final class _FakeDiagnosticsRun implements MediaPerformanceDiagnosticsRun {
  final report = const MediaPerformanceReport(
    runId: 'app-run',
    durationMs: 0,
    frameBudgetMs: 16.67,
    cohorts: {},
    bufferingCount: 0,
    bufferingDurationMs: 0,
    stallCount: 0,
    markers: [],
  );
  final List<String> operations = <String>[];
  final List<String> markers = <String>[];
  final List<MediaPerformanceOverlayState> overlayStates =
      <MediaPerformanceOverlayState>[];
  Completer<void>? snapshotGate;
  Completer<void>? cancellationMarkerGate;
  int snapshotCount = 0;
  int stopCount = 0;

  @override
  Future<void> updateOverlayState(MediaPerformanceOverlayState state) async {
    overlayStates.add(state);
    operations.add('overlay:${state.sampleClass.name}:${state.active}');
  }

  @override
  Future<void> recordMarker(
    String name, {
    int? sequenceIndex,
    bool? expectedOverlayActive,
  }) async {
    final suffix = sequenceIndex == null
        ? ''
        : ':$sequenceIndex:$expectedOverlayActive';
    markers.add('$name$suffix');
    operations.add('marker:$name');
    if (name == 'guided_sequence_cancelled') {
      await cancellationMarkerGate?.future;
    }
  }

  @override
  Future<MediaPerformanceReport> snapshot() async {
    snapshotCount += 1;
    operations.add('snapshot');
    await snapshotGate?.future;
    return report;
  }

  @override
  Future<MediaPerformanceReport> stop() async {
    stopCount += 1;
    operations.add('stop');
    return report;
  }
}

final class _DiagnosticsPlayerPlatform extends VesperPlayerPlatform {
  final StreamController<VesperPlayerEvent> _events =
      StreamController<VesperPlayerEvent>.broadcast();
  var initialSnapshot = const VesperPlayerSnapshot.initial().copyWith(
    playbackState: VesperPlaybackState.playing,
  );
  var _nextPlayerId = 0;

  @override
  Future<VesperPlatformCreateResult> createPlayer({
    VesperPlayerSource? initialSource,
    VesperPlayerRenderSurfaceKind renderSurfaceKind =
        VesperPlayerRenderSurfaceKind.auto,
    VesperPlaybackResiliencePolicy resiliencePolicy =
        const VesperPlaybackResiliencePolicy(),
    VesperTrackPreferencePolicy trackPreferencePolicy =
        const VesperTrackPreferencePolicy(),
    VesperPreloadBudgetPolicy preloadBudgetPolicy =
        const VesperPreloadBudgetPolicy(),
    bool keepScreenOnDuringPlayback = true,
    VesperBenchmarkConfiguration benchmarkConfiguration =
        const VesperBenchmarkConfiguration.disabled(),
    VesperSourceNormalizerConfiguration sourceNormalizerConfiguration =
        const VesperSourceNormalizerConfiguration(),
    VesperFrameProcessorConfiguration frameProcessorConfiguration =
        const VesperFrameProcessorConfiguration(),
    VesperNativeFramePipelineConfiguration nativeFramePipelineConfiguration =
        const VesperNativeFramePipelineConfiguration(),
  }) async => VesperPlatformCreateResult(
    playerId: 'app-diagnostics-player-${++_nextPlayerId}',
    snapshot: initialSnapshot,
  );

  @override
  Stream<VesperPlayerEvent> eventsFor(String playerId) => _events.stream;

  @override
  Future<void> dispose(String playerId) async {}

  Future<void> close() => _events.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
