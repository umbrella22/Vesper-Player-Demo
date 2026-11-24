part of 'media_playback_performance_diagnostics.dart';

enum MediaPerformanceSampleClass { steady, transition, excluded }

typedef MediaPerformanceOverlayState = ({
  bool active,
  MediaPerformanceSampleClass sampleClass,
});

enum MediaFrameGroup { overlayInactive, overlayActive, transition, excluded }

final class MediaFrameCohort {
  const MediaFrameCohort(
    this.sampleCount,
    this.jankCount,
    this.severeJankCount,
    this.p95LoadMs,
  );

  final int sampleCount;
  final int jankCount;
  final int severeJankCount;
  final double p95LoadMs;

  Map<String, Object> toMap() => {
    'sampleCount': sampleCount,
    'jankCount': jankCount,
    'severeJankCount': severeJankCount,
    'p95LoadMs': p95LoadMs,
  };
}

final class MediaPerformanceReport {
  const MediaPerformanceReport({
    required this.runId,
    required this.durationMs,
    required this.frameBudgetMs,
    required this.cohorts,
    required this.bufferingCount,
    required this.bufferingDurationMs,
    required this.stallCount,
    required this.markers,
  });

  final String runId;
  final int durationMs;
  final double frameBudgetMs;
  final Map<MediaFrameGroup, MediaFrameCohort> cohorts;
  final int bufferingCount;
  final int bufferingDurationMs;
  final int stallCount;
  final List<Map<String, Object>> markers;

  // Keep the steady-sample floor used by the guided overlay comparison.
  static const minimumComparisonFrames = 120;

  double? get overlayJankDeltaPoints {
    final off = cohorts[MediaFrameGroup.overlayInactive];
    final on = cohorts[MediaFrameGroup.overlayActive];
    if (off == null ||
        on == null ||
        off.sampleCount < minimumComparisonFrames ||
        on.sampleCount < minimumComparisonFrames) {
      return null;
    }
    return 100 *
        (on.jankCount / on.sampleCount - off.jankCount / off.sampleCount);
  }

  String toJson() => jsonEncode({
    'schema': 'vesper_media.host_performance.v1',
    'runId': runId,
    'probe': 'flutterFrameTiming',
    'durationMs': durationMs,
    'frameBudgetMs': frameBudgetMs,
    'cohorts': {
      for (final entry in cohorts.entries) entry.key.name: entry.value.toMap(),
    },
    'playback': {
      'bufferingCount': bufferingCount,
      'bufferingDurationMs': bufferingDurationMs,
      'stallCount': stallCount,
    },
    'overlayJankDeltaPoints': ?overlayJankDeltaPoints,
    'markers': markers,
  });
}

final class _HostPerformanceRun implements MediaPerformanceDiagnosticsRun {
  _HostPerformanceRun(VesperPlayerController player)
    : _runId = '${player.playerId}-${DateTime.now().microsecondsSinceEpoch}' {
    _observeBuffering(player.snapshot.isBuffering);
    _subscription = player.events.listen((event) {
      if (event is VesperPlayerSnapshotEvent) {
        _observeBuffering(event.snapshot.isBuffering);
      } else if (event is VesperPlayerWarningEvent &&
          event.warning.playback != null) {
        _stallCount++;
      }
    });
    SchedulerBinding.instance.addTimingsCallback(_onFrames);
  }

  final String _runId;
  final _clock = Stopwatch()..start();
  final double _budgetUs = _frameBudgetUs();
  late final StreamSubscription<VesperPlayerEvent> _subscription;
  final _cohorts = <MediaFrameGroup, _FrameSamples>{};
  final _markers = <Map<String, Object>>[];
  int _bufferingCount = 0;
  int _bufferingMs = 0;
  int? _bufferingStartMs;
  int _stallCount = 0;

  // Flutter delivers timings in batches. Classify by the frame where the
  // change takes effect, even if the drawer has reopened before delivery.
  final _groups = ListQueue<({int firstFrame, MediaFrameGroup group})>();

  static double _frameBudgetUs() {
    final hz =
        ui.PlatformDispatcher.instance.views.firstOrNull?.display.refreshRate;
    return Duration.microsecondsPerSecond /
        (hz != null && hz.isFinite && hz > 0 ? hz : 60);
  }

  @override
  Future<void> updateOverlayState(MediaPerformanceOverlayState state) async {
    final group = switch (state.sampleClass) {
      MediaPerformanceSampleClass.excluded => MediaFrameGroup.excluded,
      MediaPerformanceSampleClass.transition => MediaFrameGroup.transition,
      MediaPerformanceSampleClass.steady =>
        state.active
            ? MediaFrameGroup.overlayActive
            : MediaFrameGroup.overlayInactive,
    };
    if (_groups.isNotEmpty && _groups.last.group == group) return;
    final firstFrame = ui.PlatformDispatcher.instance.frameData.frameNumber + 1;
    if (_groups.isNotEmpty && _groups.last.firstFrame == firstFrame) {
      _groups.removeLast();
    }
    _groups.add((firstFrame: firstFrame, group: group));
  }

  void _onFrames(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      if (_groups.isEmpty || timing.frameNumber < _groups.first.firstFrame) {
        continue;
      }
      while (_groups.length > 1 &&
          _groups.elementAt(1).firstFrame <= timing.frameNumber) {
        _groups.removeFirst();
      }
      final samples = _cohorts.putIfAbsent(
        _groups.first.group,
        _FrameSamples.new,
      );
      samples.add(
        math.max(
          timing.buildDuration.inMicroseconds,
          timing.rasterDuration.inMicroseconds,
        ),
        _budgetUs,
      );
    }
  }

  void _observeBuffering(bool buffering) {
    final start = _bufferingStartMs;
    if (buffering && start == null) {
      _bufferingStartMs = _clock.elapsedMilliseconds;
      _bufferingCount++;
    } else if (!buffering && start != null) {
      _bufferingMs += _clock.elapsedMilliseconds - start;
      _bufferingStartMs = null;
    }
  }

  @override
  Future<void> recordMarker(
    String name, {
    int? sequenceIndex,
    bool? expectedOverlayActive,
  }) async {
    _markers.add({
      'name': name,
      'elapsedMs': _clock.elapsedMilliseconds,
      'sequenceIndex': ?sequenceIndex,
      'expectedOverlayActive': ?expectedOverlayActive,
    });
  }

  @override
  Future<MediaPerformanceReport> snapshot() async {
    final elapsed = _clock.elapsedMilliseconds;
    final start = _bufferingStartMs;
    return MediaPerformanceReport(
      runId: _runId,
      durationMs: elapsed,
      frameBudgetMs: _budgetUs / 1000,
      cohorts: {
        for (final entry in _cohorts.entries) entry.key: entry.value.snapshot(),
      },
      bufferingCount: _bufferingCount,
      bufferingDurationMs: _bufferingMs + (start == null ? 0 : elapsed - start),
      stallCount: _stallCount,
      markers: List.unmodifiable(_markers),
    );
  }

  @override
  Future<MediaPerformanceReport> stop() async {
    _clock.stop();
    SchedulerBinding.instance.removeTimingsCallback(_onFrames);
    await _subscription.cancel();
    return snapshot();
  }
}

final class _FrameSamples {
  // The percentile uses a uniform reservoir across the run. Counts stay exact.
  static const _capacity = 2048;
  final _sampleUs = <int>[];
  final _random = math.Random(0);
  int _count = 0;
  int _jank = 0;
  int _severeJank = 0;

  void add(int loadUs, double budgetUs) {
    _count++;
    if (loadUs > budgetUs) _jank++;
    if (loadUs > budgetUs * 2) _severeJank++;
    if (_sampleUs.length < _capacity) {
      _sampleUs.add(loadUs);
    } else {
      final index = _random.nextInt(_count);
      if (index < _capacity) _sampleUs[index] = loadUs;
    }
  }

  MediaFrameCohort snapshot() {
    final sorted = _sampleUs.toList()..sort();
    return MediaFrameCohort(
      _count,
      _jank,
      _severeJank,
      sorted[(0.95 * sorted.length).ceil() - 1] / 1000,
    );
  }
}
