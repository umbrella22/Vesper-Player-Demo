import 'dart:async';

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
    required MediaPerformanceDiagnosticsRunFactory runFactory,
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

  test('concurrent start requests create one diagnostics run', () async {
    final player = await createPlayer();
    final gate = Completer<void>();
    final run = _FakeDiagnosticsRun();
    var factoryCalls = 0;
    final diagnostics = createDiagnostics(
      onOverride: (_) {},
      runFactory: (_, _) async {
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
      runFactory: (_, _) async {
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
        runFactory: (_, _) async {
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
        runFactory: (_, _) async => run,
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
        runFactory: (_, _) async => run,
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
        runFactory: (_, _) async => run,
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
                  state.sampleClass ==
                      VesperPerformanceSampleClass.transition ||
                  state.sampleClass == VesperPerformanceSampleClass.steady,
            )
            .map((state) => '${state.sampleClass.rawValue}:${state.active}'),
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
      runFactory: (_, _) async => run,
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
      runFactory: (_, _) async => run,
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
  _FakeDiagnosticsRun() : report = _report('app-run');

  final VesperPerformanceDiagnosticsReport report;
  final List<String> operations = <String>[];
  final List<String> markers = <String>[];
  final List<VesperPerformanceOverlayState> overlayStates =
      <VesperPerformanceOverlayState>[];
  Completer<void>? snapshotGate;
  Completer<void>? cancellationMarkerGate;
  int snapshotCount = 0;
  int stopCount = 0;

  @override
  String get runId => report.runId;

  @override
  Future<void> updateOverlayState(VesperPerformanceOverlayState state) async {
    overlayStates.add(state);
    operations.add('overlay:${state.sampleClass.rawValue}:${state.active}');
  }

  @override
  Future<void> recordMarker(
    String name, {
    double? value,
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
  Future<VesperPerformanceDiagnosticsReport> snapshot() async {
    snapshotCount += 1;
    operations.add('snapshot');
    await snapshotGate?.future;
    return report;
  }

  @override
  Future<VesperPerformanceDiagnosticsReport> stop() async {
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
    VesperPipelineEventHookConfiguration pipelineEventHookConfiguration =
        const VesperPipelineEventHookConfiguration(),
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

VesperPerformanceDiagnosticsReport _report(String runId) =>
    VesperPerformanceDiagnosticsReport.fromMap(<Object?, Object?>{
      'schemaVersion': 1,
      'runId': runId,
      'sessionId': 'app-session',
      'platform': 'test',
      'probe': 'flutterFrameTiming',
      'durationNs': 1,
      'frameBudgetNs': 16666667,
      'cohorts': <String, Object?>{
        for (final name in <String>[
          'overlayInactive',
          'overlayActive',
          'transition',
          'excluded',
        ])
          name: <String, Object?>{
            'sampleCount': 0,
            'jankCount': 0,
            'severeJankCount': 0,
            'jankRatio': 0.0,
            'severeJankRatio': 0.0,
            'minLoadNs': 0,
            'p50LoadNs': 0,
            'p95LoadNs': 0,
            'maxLoadNs': 0,
          },
      },
      'playback': <String, Object?>{
        'activeDurationNs': 0,
        'droppedVideoFrames': 0,
        'bufferingCount': 0,
        'bufferingDurationNs': 0,
        'stallCount': 0,
      },
      'diagnosis': <String, Object?>{
        'kind': 'insufficientEvidence',
        'confidence': 'low',
        'evidenceCodes': <String>['steady_cohorts_below_120'],
      },
      'acceptedEvents': 0,
      'droppedEvents': 0,
      'rawEventsDropped': 0,
      'diagnostics': <Object?>[
        <String, Object?>{
          'code': 'performance.diagnosis',
          'severity': 'warning',
          'message': 'Correlation only.',
          'attributes': <String, String>{
            'kind': 'insufficientEvidence',
            'confidence': 'low',
            'evidenceCodes': 'steady_cohorts_below_120',
          },
        },
      ],
      'rawEvents': <Object?>[],
    });
