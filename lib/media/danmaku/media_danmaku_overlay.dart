import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_player/vesper_player.dart';

import '../capabilities/media_danmaku.dart';
import '../models/media_playback_target.dart';

const int _highVolumeDanmakuEventThreshold = 5000;
const int _highVolumeScrollingLaneLimit = 4;
const int _highVolumeStaticLaneLimit = 2;

final class MediaDanmakuOverlayMetrics {
  const MediaDanmakuOverlayMetrics({
    required this.active,
    required this.loadedBasicItemCount,
    required this.loadedAdvancedItemCount,
    required this.advancedEffectsActive,
  });

  final bool active;
  final int loadedBasicItemCount;
  final int loadedAdvancedItemCount;
  final bool advancedEffectsActive;

  bool get hasItems => loadedBasicItemCount + loadedAdvancedItemCount > 0;

  @override
  bool operator ==(Object other) {
    return other is MediaDanmakuOverlayMetrics &&
        other.active == active &&
        other.loadedBasicItemCount == loadedBasicItemCount &&
        other.loadedAdvancedItemCount == loadedAdvancedItemCount &&
        other.advancedEffectsActive == advancedEffectsActive;
  }

  @override
  int get hashCode => Object.hash(
    active,
    loadedBasicItemCount,
    loadedAdvancedItemCount,
    advancedEffectsActive,
  );
}

/// 弹幕 overlay 的平台无关显示与文字过滤设置。
final class MediaDanmakuOverlaySettings {
  const MediaDanmakuOverlaySettings({
    this.enabled = true,
    this.opacity = 0.82,
    this.density = 0.8,
    this.fontScale = 1.0,
    this.displayArea = 0.75,
    this.showScroll = true,
    this.showTop = true,
    this.showBottom = true,
    this.showReverse = true,
    this.showCaption = true,
    this.showAdvanced = true,
    this.showColor = true,
    this.blockedKeywords = const <String>[],
  });

  final bool enabled;
  final double opacity;
  final double density;
  final double fontScale;
  final double displayArea;
  final bool showScroll;
  final bool showTop;
  final bool showBottom;
  final bool showReverse;
  final bool showCaption;
  final bool showAdvanced;
  final bool showColor;

  /// 大小写敏感的字面子串。空格和 Unicode 原样参与匹配。
  final List<String> blockedKeywords;

  MediaDanmakuOverlaySettings copyWith({
    bool? enabled,
    double? opacity,
    double? density,
    double? fontScale,
    double? displayArea,
    bool? showScroll,
    bool? showTop,
    bool? showBottom,
    bool? showReverse,
    bool? showCaption,
    bool? showAdvanced,
    bool? showColor,
    List<String>? blockedKeywords,
  }) {
    return MediaDanmakuOverlaySettings(
      enabled: enabled ?? this.enabled,
      opacity: opacity ?? this.opacity,
      density: density ?? this.density,
      fontScale: fontScale ?? this.fontScale,
      displayArea: displayArea ?? this.displayArea,
      showScroll: showScroll ?? this.showScroll,
      showTop: showTop ?? this.showTop,
      showBottom: showBottom ?? this.showBottom,
      showReverse: showReverse ?? this.showReverse,
      showCaption: showCaption ?? this.showCaption,
      showAdvanced: showAdvanced ?? this.showAdvanced,
      showColor: showColor ?? this.showColor,
      blockedKeywords: blockedKeywords ?? this.blockedKeywords,
    );
  }

  bool allowsStandardEvent(MediaDanmakuEvent event) {
    if (event.channel == MediaDanmakuChannel.caption) {
      return showCaption &&
          _allowsColor(event.style.color) &&
          !_blocksText(event.text);
    }
    final positionAllowed = switch (event.style.position) {
      MediaDanmakuPosition.roll => showScroll,
      MediaDanmakuPosition.top => showTop,
      MediaDanmakuPosition.bottom => showBottom,
      MediaDanmakuPosition.reverse => showReverse,
    };
    return positionAllowed &&
        _allowsColor(event.style.color) &&
        !_blocksText(event.text);
  }

  bool allowsAdvancedEvent(MediaAdvancedDanmakuEvent event) {
    return showAdvanced &&
        _allowsColor(event.color) &&
        !_blocksText(event.text);
  }

  bool _allowsColor(int? color) {
    return showColor || color == null || color == 0xFFFFFF;
  }

  bool _blocksText(String text) {
    for (final keyword in blockedKeywords) {
      if (keyword.isNotEmpty && text.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  @override
  bool operator ==(Object other) {
    return other is MediaDanmakuOverlaySettings &&
        other.enabled == enabled &&
        other.opacity == opacity &&
        other.density == density &&
        other.fontScale == fontScale &&
        other.displayArea == displayArea &&
        other.showScroll == showScroll &&
        other.showTop == showTop &&
        other.showBottom == showBottom &&
        other.showReverse == showReverse &&
        other.showCaption == showCaption &&
        other.showAdvanced == showAdvanced &&
        other.showColor == showColor &&
        _sameStringList(other.blockedKeywords, blockedKeywords);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    enabled,
    opacity,
    density,
    fontScale,
    displayArea,
    showScroll,
    showTop,
    showBottom,
    showReverse,
    showCaption,
    showAdvanced,
    showColor,
    Object.hashAll(blockedKeywords),
  ]);
}

bool _sameStringList(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _sameDanmakuRenderSettings(
  MediaDanmakuOverlaySettings left,
  MediaDanmakuOverlaySettings right,
) {
  return left.opacity == right.opacity &&
      left.density == right.density &&
      left.fontScale == right.fontScale &&
      left.displayArea == right.displayArea &&
      left.showScroll == right.showScroll &&
      left.showTop == right.showTop &&
      left.showBottom == right.showBottom &&
      left.showReverse == right.showReverse &&
      left.showCaption == right.showCaption &&
      left.showAdvanced == right.showAdvanced &&
      left.showColor == right.showColor &&
      _sameStringList(left.blockedKeywords, right.blockedKeywords);
}

/// 通用弹幕画布。Ticker 只通知 painter 重绘，不重建 widget 树。
class MediaDanmakuOverlay extends StatefulWidget {
  const MediaDanmakuOverlay({
    super.key,
    required this.events,
    this.advancedEvents = const <MediaAdvancedDanmakuEvent>[],
    required this.positionMs,
    required this.playbackState,
    required this.playbackRate,
    required this.settings,
  });

  final List<MediaDanmakuEvent> events;
  final List<MediaAdvancedDanmakuEvent> advancedEvents;
  final int positionMs;
  final VesperPlaybackState playbackState;
  final double playbackRate;
  final MediaDanmakuOverlaySettings settings;

  @override
  State<MediaDanmakuOverlay> createState() => _MediaDanmakuOverlayState();
}

class _MediaDanmakuOverlayState extends State<MediaDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _reducedFrameInterval = Duration(milliseconds: 33);
  static const Duration _highVolumeFrameInterval = Duration(milliseconds: 50);

  late final _MediaDanmakuClock _clock;
  late final Ticker _ticker;
  final _DanmakuTextCache _textCache = _DanmakuTextCache();
  final _DanmakuLayoutCache _layoutCache = _DanmakuLayoutCache();
  final _AdvancedDanmakuLayoutCache _advancedLayoutCache =
      _AdvancedDanmakuLayoutCache();
  Timer? _reducedFrameTimer;
  Duration? _reducedFrameTimerInterval;

  @override
  void initState() {
    super.initState();
    _clock = _MediaDanmakuClock(
      positionMs: widget.positionMs,
      playbackState: widget.playbackState,
      playbackRate: widget.playbackRate,
    );
    _ticker = createTicker((_) => _clock.notifyFrame());
    _syncAnimationDriver();
  }

  @override
  void didUpdateWidget(covariant MediaDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionMs != widget.positionMs ||
        oldWidget.playbackState != widget.playbackState ||
        (oldWidget.playbackRate - widget.playbackRate).abs() > 0.001) {
      _clock.sync(
        positionMs: widget.positionMs,
        playbackState: widget.playbackState,
        playbackRate: widget.playbackRate,
        notify: widget.playbackState != VesperPlaybackState.playing,
      );
    }
    _syncAnimationDriver();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _reducedFrameTimer?.cancel();
    _clock.dispose();
    _textCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: MediaDanmakuPainter._(
              events: widget.events,
              advancedEvents: widget.advancedEvents,
              settings: widget.settings,
              clock: _clock,
              textCache: _textCache,
              layoutCache: _layoutCache,
              advancedLayoutCache: _advancedLayoutCache,
            ),
          ),
        ),
      ),
    );
  }

  void _syncAnimationDriver() {
    final shouldAnimate =
        widget.playbackState == VesperPlaybackState.playing &&
        widget.settings.enabled &&
        (widget.events.isNotEmpty || widget.advancedEvents.isNotEmpty);
    if (!shouldAnimate) {
      _ticker.stop();
      _reducedFrameTimer?.cancel();
      _reducedFrameTimer = null;
      _reducedFrameTimerInterval = null;
      return;
    }
    final highVolume = widget.events.length >= _highVolumeDanmakuEventThreshold;
    final reducedFrameInterval = highVolume
        ? _highVolumeFrameInterval
        : widget.advancedEvents.isNotEmpty
        ? _reducedFrameInterval
        : null;
    if (reducedFrameInterval != null) {
      _ticker.stop();
      if (_reducedFrameTimerInterval != reducedFrameInterval) {
        _reducedFrameTimer?.cancel();
        _reducedFrameTimer = Timer.periodic(
          reducedFrameInterval,
          (_) => _clock.notifyFrame(),
        );
        _reducedFrameTimerInterval = reducedFrameInterval;
      }
      return;
    }
    _reducedFrameTimer?.cancel();
    _reducedFrameTimer = null;
    _reducedFrameTimerInterval = null;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }
}

/// Painter is public only so widget tests can inspect its deterministic render
/// plan without reintroducing one Text widget per danmaku.
class MediaDanmakuPainter extends CustomPainter {
  MediaDanmakuPainter._({
    required this._events,
    required this._advancedEvents,
    required this._settings,
    required _MediaDanmakuClock clock,
    required this._textCache,
    required this._layoutCache,
    required this._advancedLayoutCache,
  }) : _clock = clock,
       super(repaint: clock);

  static const int _scrollDurationMs = 6200;
  static const int _pinnedDurationMs = 4200;
  static const int _maximumVisibleDurationMs = 12000;
  static const int _maximumVisibleAdvancedCount = 8;
  static const int _highVolumeVisibleAdvancedCount = 4;

  final List<MediaDanmakuEvent> _events;
  final List<MediaAdvancedDanmakuEvent> _advancedEvents;
  final MediaDanmakuOverlaySettings _settings;
  final _MediaDanmakuClock _clock;
  final _DanmakuTextCache _textCache;
  final _DanmakuLayoutCache _layoutCache;
  final _AdvancedDanmakuLayoutCache _advancedLayoutCache;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        (_events.isEmpty && _advancedEvents.isEmpty) ||
        !_settings.enabled) {
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final positionMs = _clock.currentPositionMs;
    final plans = _plansFor(size, positionMs);
    final firstPlanIndex = _firstVisiblePlanIndex(plans, positionMs);
    for (var index = firstPlanIndex; index < plans.length; index += 1) {
      final plan = plans[index];
      if (plan.event.timeMs > positionMs) {
        break;
      }
      if (positionMs - plan.event.timeMs > plan.durationMs) {
        continue;
      }
      final offset = _offsetFor(plan, size.width, positionMs);
      if (offset != null) {
        _textCache
            .resolve(
              event: plan.event,
              fontSize: plan.fontSize,
              opacity: _settings.opacity.clamp(0.0, 1.0).toDouble(),
            )
            .paint(canvas, offset);
      }
    }
    final advancedPlans = _advancedLayoutCache.resolve(
      events: _advancedEvents,
      size: size,
      settings: _settings,
      positionMs: positionMs,
    );
    final firstAdvancedPlanIndex = _firstVisibleAdvancedPlanIndex(
      advancedPlans,
      positionMs,
    );
    var visibleAdvancedCount = 0;
    for (
      var index = firstAdvancedPlanIndex;
      index < advancedPlans.length;
      index += 1
    ) {
      final plan = advancedPlans[index];
      if (plan.event.timeMs > positionMs) {
        break;
      }
      final elapsedMs = positionMs - plan.event.timeMs;
      if (elapsedMs < 0 || elapsedMs > plan.event.durationMs) {
        continue;
      }
      _paintAdvancedPlan(canvas, size, plan, positionMs);
      visibleAdvancedCount += 1;
      if (visibleAdvancedCount >= _visibleAdvancedCountLimit) {
        break;
      }
    }
    canvas.restore();
  }

  int _firstVisiblePlanIndex(List<_DanmakuRenderPlan> plans, int positionMs) {
    final firstTime = positionMs - _maximumVisibleDurationMs;
    var low = 0;
    var high = plans.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (plans[middle].event.timeMs < firstTime) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _firstVisibleAdvancedPlanIndex(
    List<_AdvancedDanmakuRenderPlan> plans,
    int positionMs,
  ) {
    final firstTime = positionMs - _maximumVisibleDurationMs;
    var low = 0;
    var high = plans.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (plans[middle].event.timeMs < firstTime) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int get _visibleAdvancedCountLimit =>
      _events.length + _advancedEvents.length >=
          _highVolumeDanmakuEventThreshold
      ? _highVolumeVisibleAdvancedCount
      : _maximumVisibleAdvancedCount;

  @visibleForTesting
  List<String> debugVisibleAdvancedEventIdsAt({
    required int positionMs,
    required Size size,
  }) {
    return _visibleAdvancedPlans(
      _advancedLayoutCache.resolve(
        events: _advancedEvents,
        size: size,
        settings: _settings,
        positionMs: positionMs,
      ),
      positionMs,
    ).map((plan) => plan.event.id).toList(growable: false);
  }

  @visibleForTesting
  List<String> debugAdvancedOpacityLayerEventIdsAt({
    required int positionMs,
    required Size size,
  }) {
    return _visibleAdvancedPlans(
          _advancedLayoutCache.resolve(
            events: _advancedEvents,
            size: size,
            settings: _settings,
            positionMs: positionMs,
          ),
          positionMs,
        )
        .where((plan) => plan.usesOpacityLayer)
        .map((plan) => plan.event.id)
        .toList(growable: false);
  }

  @visibleForTesting
  int debugStandardLayoutBuildCount(Size size, {int positionMs = 0}) {
    _plansFor(size, positionMs);
    return _layoutCache.buildCount;
  }

  @visibleForTesting
  int debugCachedTextLayoutCountAt({
    required int positionMs,
    required Size size,
  }) {
    _plansFor(size, positionMs);
    return _textCache.length;
  }

  @visibleForTesting
  int debugStandardWindowEventCountAt({
    required int positionMs,
    required Size size,
  }) {
    _plansFor(size, positionMs);
    return _layoutCache.windowEventCount;
  }

  @visibleForTesting
  Offset? debugAdvancedOffsetForEventAt({
    required String eventId,
    required int positionMs,
    required Size size,
  }) {
    for (final plan in _visibleAdvancedPlans(
      _advancedLayoutCache.resolve(
        events: _advancedEvents,
        size: size,
        settings: _settings,
        positionMs: positionMs,
      ),
      positionMs,
    )) {
      if (plan.event.id == eventId) {
        return _advancedOffset(plan.event, size, positionMs);
      }
    }
    return null;
  }

  @visibleForTesting
  List<String> debugVisibleEventIdsAt({
    required int positionMs,
    required Size size,
  }) {
    return _visiblePlans(
      _plansFor(size, positionMs),
      positionMs,
    ).map((plan) => plan.event.id).toList(growable: false);
  }

  @visibleForTesting
  Offset? debugOffsetForEventAt({
    required String eventId,
    required int positionMs,
    required Size size,
  }) {
    for (final plan in _visiblePlans(_plansFor(size, positionMs), positionMs)) {
      if (plan.event.id == eventId) {
        return _offsetFor(plan, size.width, positionMs);
      }
    }
    return null;
  }

  List<_DanmakuRenderPlan> _plansFor(Size size, int positionMs) {
    return _layoutCache.resolve(
      events: _events,
      size: size,
      settings: _settings,
      textCache: _textCache,
      positionMs: positionMs,
    );
  }

  Iterable<_DanmakuRenderPlan> _visiblePlans(
    List<_DanmakuRenderPlan> plans,
    int positionMs,
  ) sync* {
    final low = _firstVisiblePlanIndex(plans, positionMs);
    for (var index = low; index < plans.length; index += 1) {
      final plan = plans[index];
      if (plan.event.timeMs > positionMs) {
        break;
      }
      if (positionMs - plan.event.timeMs <= plan.durationMs) {
        yield plan;
      }
    }
  }

  Iterable<_AdvancedDanmakuRenderPlan> _visibleAdvancedPlans(
    List<_AdvancedDanmakuRenderPlan> plans,
    int positionMs,
  ) sync* {
    final low = _firstVisibleAdvancedPlanIndex(plans, positionMs);
    var visibleCount = 0;
    for (var index = low; index < plans.length; index += 1) {
      final plan = plans[index];
      if (plan.event.timeMs > positionMs) {
        break;
      }
      final elapsedMs = positionMs - plan.event.timeMs;
      if (elapsedMs >= 0 && elapsedMs <= plan.event.durationMs) {
        yield plan;
        visibleCount += 1;
        if (visibleCount >= _visibleAdvancedCountLimit) {
          break;
        }
      }
    }
  }

  void _paintAdvancedPlan(
    Canvas canvas,
    Size size,
    _AdvancedDanmakuRenderPlan plan,
    int positionMs,
  ) {
    final event = plan.event;
    final offset = _advancedOffset(event, size, positionMs);
    if (offset == null) {
      return;
    }
    final elapsedMs = positionMs - event.timeMs;
    final lifetimeProgress = event.durationMs <= 0
        ? 1.0
        : (elapsedMs / event.durationMs).clamp(0.0, 1.0).toDouble();
    final eventAlpha =
        event.alphaFrom + (event.alphaTo - event.alphaFrom) * lifetimeProgress;
    final opacity = (eventAlpha * _settings.opacity).clamp(0.0, 1.0).toDouble();
    if (opacity <= 0) {
      return;
    }

    final textPainter = _textCache.resolveAdvanced(
      event: event,
      fontSize: plan.fontSize,
      opacity: plan.usesOpacityLayer ? 1 : plan.fixedOpacity,
    );

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final center = Offset(textPainter.width / 2, textPainter.height / 2);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(event.rotationZDegrees * math.pi / 180);
    canvas.scale(math.cos(event.rotationYDegrees * math.pi / 180), 1);
    canvas.translate(-center.dx, -center.dy);
    if (plan.usesOpacityLayer) {
      canvas.saveLayer(
        Offset.zero & Size(textPainter.width, textPainter.height),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      textPainter.paint(canvas, Offset.zero);
    }
    canvas.restore();
  }

  Offset? _advancedOffset(
    MediaAdvancedDanmakuEvent event,
    Size size,
    int positionMs,
  ) {
    final elapsedMs = positionMs - event.timeMs;
    if (elapsedMs < 0 || elapsedMs > event.durationMs || event.path.isEmpty) {
      return null;
    }
    final motionElapsedMs = elapsedMs - event.motionDelayMs;
    final motionProgress = motionElapsedMs <= 0
        ? 0.0
        : event.motionDurationMs <= 0
        ? 1.0
        : (motionElapsedMs / event.motionDurationMs).clamp(0.0, 1.0).toDouble();
    final point = _pointAlongPath(event.path, motionProgress);
    return Offset(point.x * size.width, point.y * size.height);
  }

  MediaDanmakuPoint _pointAlongPath(
    List<MediaDanmakuPoint> path,
    double progress,
  ) {
    if (path.length == 1 || progress <= 0) {
      return path.first;
    }
    if (progress >= 1) {
      return path.last;
    }
    final scaled = progress * (path.length - 1);
    final segment = scaled.floor().clamp(0, path.length - 2);
    final localProgress = scaled - segment;
    final from = path[segment];
    final to = path[segment + 1];
    return MediaDanmakuPoint(
      from.x + (to.x - from.x) * localProgress,
      from.y + (to.y - from.y) * localProgress,
    );
  }

  Offset? _offsetFor(
    _DanmakuRenderPlan plan,
    double canvasWidth,
    int positionMs,
  ) {
    final elapsedMs = positionMs - plan.event.timeMs;
    if (elapsedMs < 0 || elapsedMs > plan.durationMs) {
      return null;
    }
    return switch (plan.kind) {
      _DanmakuRenderKind.scroll => Offset(
        canvasWidth - plan.speed * elapsedMs,
        plan.top,
      ),
      _DanmakuRenderKind.reverse => Offset(
        -plan.textWidth + plan.speed * elapsedMs,
        plan.top,
      ),
      _DanmakuRenderKind.top || _DanmakuRenderKind.bottom => Offset(
        (canvasWidth - plan.textWidth) / 2,
        plan.top,
      ),
    };
  }

  @override
  bool shouldRepaint(covariant MediaDanmakuPainter oldDelegate) {
    return !identical(oldDelegate._events, _events) ||
        !identical(oldDelegate._advancedEvents, _advancedEvents) ||
        oldDelegate._settings.enabled != _settings.enabled ||
        !_sameDanmakuRenderSettings(oldDelegate._settings, _settings);
  }
}

final class _DanmakuLayoutCache {
  final _timeline = _DanmakuTimelineIndex<MediaDanmakuEvent>(
    timeOf: (event) => event.timeMs,
    idOf: (event) => event.id,
  );
  Size? _size;
  MediaDanmakuOverlaySettings? _settings;
  bool? _highVolume;
  int? _windowAnchorMs;
  List<_DanmakuRenderPlan> _plans = const <_DanmakuRenderPlan>[];
  int buildCount = 0;
  int windowEventCount = 0;

  List<_DanmakuRenderPlan> resolve({
    required List<MediaDanmakuEvent> events,
    required Size size,
    required MediaDanmakuOverlaySettings settings,
    required _DanmakuTextCache textCache,
    required int positionMs,
  }) {
    final sourceChanged = _timeline.updateSource(events);
    final highVolume = events.length >= _highVolumeDanmakuEventThreshold;
    final windowAnchorMs = _windowAnchorMs;
    if (_size == size &&
        !sourceChanged &&
        _settings != null &&
        _sameDanmakuRenderSettings(_settings!, settings) &&
        _highVolume == highVolume &&
        windowAnchorMs != null &&
        _DanmakuTimelineIndex.covers(windowAnchorMs, positionMs)) {
      return _plans;
    }
    _size = size;
    _settings = settings;
    _highVolume = highVolume;
    _windowAnchorMs = positionMs;
    buildCount += 1;
    final windowEvents = _timeline.windowAt(positionMs);
    windowEventCount = windowEvents.length;
    _plans = _buildPlans(
      events: windowEvents,
      size: size,
      settings: settings,
      textCache: textCache,
      highVolume: highVolume,
    );
    return _plans;
  }

  List<_DanmakuRenderPlan> _buildPlans({
    required List<MediaDanmakuEvent> events,
    required Size size,
    required MediaDanmakuOverlaySettings settings,
    required _DanmakuTextCache textCache,
    required bool highVolume,
  }) {
    final density = settings.density.clamp(0.0, 1.0).toDouble();
    if (density <= 0) {
      return const <_DanmakuRenderPlan>[];
    }
    final prepared = <MediaDanmakuEvent>[];
    var maximumFontSize = 0.0;
    for (final event in events) {
      if (!settings.allowsStandardEvent(event)) {
        continue;
      }
      final fontSize = (25 * event.style.fontSizeScale * settings.fontScale)
          .clamp(10.0, 48.0)
          .toDouble();
      maximumFontSize = math.max(maximumFontSize, fontSize);
      prepared.add(event);
    }

    final laneHeight = math.max(22.0, maximumFontSize * 1.35 + 4).toDouble();
    final scrollingBandHeight =
        size.height * settings.displayArea.clamp(0.25, 1.0).toDouble();
    final scrollLaneCount = ((scrollingBandHeight / laneHeight) * density)
        .floor()
        .clamp(1, highVolume ? _highVolumeScrollingLaneLimit : 12)
        .toInt();
    final staticLaneCount = (scrollLaneCount / 2)
        .ceil()
        .clamp(1, highVolume ? _highVolumeStaticLaneLimit : 6)
        .toInt();
    final scrollLanes = List<_ScrollingLaneState>.generate(
      scrollLaneCount,
      (_) => _ScrollingLaneState(),
    );
    final topLanes = List<int>.filled(staticLaneCount, 0);
    final bottomLanes = List<int>.filled(staticLaneCount, 0);
    final plans = <_DanmakuRenderPlan>[];

    for (final event in prepared) {
      final fontSize = (25 * event.style.fontSizeScale * settings.fontScale)
          .clamp(10.0, 48.0)
          .toDouble();
      final position = event.channel == MediaDanmakuChannel.caption
          ? MediaDanmakuPosition.bottom
          : event.style.position;
      switch (position) {
        case MediaDanmakuPosition.roll:
        case MediaDanmakuPosition.reverse:
          final kind = position == MediaDanmakuPosition.reverse
              ? _DanmakuRenderKind.reverse
              : _DanmakuRenderKind.scroll;
          if (!_hasPotentialScrollingLane(
            lanes: scrollLanes,
            kind: kind,
            appearAtMs: event.timeMs,
          )) {
            continue;
          }
          final textPainter = textCache.resolve(
            event: event,
            fontSize: fontSize,
            opacity: settings.opacity.clamp(0.0, 1.0).toDouble(),
          );
          final speed =
              (size.width + textPainter.width) /
              MediaDanmakuPainter._scrollDurationMs;
          final candidate = _DanmakuRenderPlan(
            event: event,
            kind: kind,
            top: 0,
            fontSize: fontSize,
            textWidth: textPainter.width,
            durationMs: MediaDanmakuPainter._scrollDurationMs,
            speed: speed,
          );
          final laneIndex = _pickScrollingLane(
            lanes: scrollLanes,
            candidate: candidate,
            canvasWidth: size.width,
          );
          if (laneIndex == null) {
            continue;
          }
          final plan = candidate.copyWith(top: 8 + laneIndex * laneHeight);
          scrollLanes[laneIndex].last = plan;
          plans.add(plan);
        case MediaDanmakuPosition.top:
          final laneIndex = _pickStaticLane(
            availableAtMs: topLanes,
            appearAtMs: event.timeMs,
          );
          if (laneIndex == null) {
            continue;
          }
          final textPainter = textCache.resolve(
            event: event,
            fontSize: fontSize,
            opacity: settings.opacity.clamp(0.0, 1.0).toDouble(),
          );
          topLanes[laneIndex] =
              event.timeMs + MediaDanmakuPainter._pinnedDurationMs;
          plans.add(
            _DanmakuRenderPlan(
              event: event,
              kind: _DanmakuRenderKind.top,
              top: 8 + laneIndex * laneHeight,
              fontSize: fontSize,
              textWidth: textPainter.width,
              durationMs: MediaDanmakuPainter._pinnedDurationMs,
              speed: 0,
            ),
          );
        case MediaDanmakuPosition.bottom:
          final laneIndex = _pickStaticLane(
            availableAtMs: bottomLanes,
            appearAtMs: event.timeMs,
          );
          if (laneIndex == null) {
            continue;
          }
          final textPainter = textCache.resolve(
            event: event,
            fontSize: fontSize,
            opacity: settings.opacity.clamp(0.0, 1.0).toDouble(),
          );
          bottomLanes[laneIndex] =
              event.timeMs + MediaDanmakuPainter._pinnedDurationMs;
          final bottomBoundary = event.channel == MediaDanmakuChannel.caption
              ? size.height
              : scrollingBandHeight;
          plans.add(
            _DanmakuRenderPlan(
              event: event,
              kind: _DanmakuRenderKind.bottom,
              top: bottomBoundary - ((laneIndex + 1) * laneHeight) - 8,
              fontSize: fontSize,
              textWidth: textPainter.width,
              durationMs: MediaDanmakuPainter._pinnedDurationMs,
              speed: 0,
            ),
          );
      }
    }
    plans.sort((left, right) {
      final byTime = left.event.timeMs.compareTo(right.event.timeMs);
      return byTime != 0 ? byTime : left.event.id.compareTo(right.event.id);
    });
    return List<_DanmakuRenderPlan>.unmodifiable(plans);
  }

  int? _pickScrollingLane({
    required List<_ScrollingLaneState> lanes,
    required _DanmakuRenderPlan candidate,
    required double canvasWidth,
  }) {
    for (var index = 0; index < lanes.length; index += 1) {
      final previous = lanes[index].last;
      if (previous == null ||
          _canFollow(
            previous: previous,
            candidate: candidate,
            canvasWidth: canvasWidth,
          )) {
        return index;
      }
    }
    return null;
  }

  bool _hasPotentialScrollingLane({
    required List<_ScrollingLaneState> lanes,
    required _DanmakuRenderKind kind,
    required int appearAtMs,
  }) {
    for (final lane in lanes) {
      final previous = lane.last;
      if (previous == null) {
        return true;
      }
      final elapsedMs = appearAtMs - previous.event.timeMs;
      if (elapsedMs >= previous.durationMs) {
        return true;
      }
      if (elapsedMs < 0 || previous.kind != kind) {
        continue;
      }
      final entryGap = switch (previous.kind) {
        _DanmakuRenderKind.scroll =>
          previous.speed * elapsedMs - previous.textWidth,
        _DanmakuRenderKind.reverse =>
          -previous.textWidth + previous.speed * elapsedMs,
        _DanmakuRenderKind.top ||
        _DanmakuRenderKind.bottom => double.negativeInfinity,
      };
      if (entryGap >= 24) {
        return true;
      }
    }
    return false;
  }

  bool _canFollow({
    required _DanmakuRenderPlan previous,
    required _DanmakuRenderPlan candidate,
    required double canvasWidth,
  }) {
    final elapsedMs = candidate.event.timeMs - previous.event.timeMs;
    if (elapsedMs >= previous.durationMs) {
      return true;
    }
    if (elapsedMs < 0 || previous.kind != candidate.kind) {
      return false;
    }

    const minimumGap = 24.0;
    final (entryGap, previousExitMs) = switch (previous.kind) {
      _DanmakuRenderKind.scroll => () {
        final trailingEdge =
            canvasWidth + previous.textWidth - previous.speed * elapsedMs;
        return (canvasWidth - trailingEdge, trailingEdge / previous.speed);
      }(),
      _DanmakuRenderKind.reverse => () {
        final leadingEdge = -previous.textWidth + previous.speed * elapsedMs;
        return (leadingEdge, (canvasWidth - leadingEdge) / previous.speed);
      }(),
      _DanmakuRenderKind.top || _DanmakuRenderKind.bottom => throw StateError(
        'static danmaku cannot occupy a scrolling lane',
      ),
    };
    if (previousExitMs <= 0) {
      return true;
    }
    if (entryGap < minimumGap) {
      return false;
    }
    if (candidate.speed <= previous.speed) {
      return true;
    }
    final catchUpMs = entryGap / (candidate.speed - previous.speed);
    return catchUpMs >= previousExitMs;
  }

  int? _pickStaticLane({
    required List<int> availableAtMs,
    required int appearAtMs,
  }) {
    for (var index = 0; index < availableAtMs.length; index += 1) {
      if (appearAtMs >= availableAtMs[index]) {
        return index;
      }
    }
    return null;
  }
}

final class _AdvancedDanmakuLayoutCache {
  final _timeline = _DanmakuTimelineIndex<MediaAdvancedDanmakuEvent>(
    timeOf: (event) => event.timeMs,
    idOf: (event) => event.id,
  );
  Size? _size;
  MediaDanmakuOverlaySettings? _settings;
  int? _windowAnchorMs;
  List<_AdvancedDanmakuRenderPlan> _plans =
      const <_AdvancedDanmakuRenderPlan>[];

  List<_AdvancedDanmakuRenderPlan> resolve({
    required List<MediaAdvancedDanmakuEvent> events,
    required Size size,
    required MediaDanmakuOverlaySettings settings,
    required int positionMs,
  }) {
    final sourceChanged = _timeline.updateSource(events);
    final windowAnchorMs = _windowAnchorMs;
    if (_size == size &&
        !sourceChanged &&
        _settings != null &&
        _sameDanmakuRenderSettings(_settings!, settings) &&
        windowAnchorMs != null &&
        _DanmakuTimelineIndex.covers(windowAnchorMs, positionMs)) {
      return _plans;
    }
    _size = size;
    _settings = settings;
    _windowAnchorMs = positionMs;
    final plans = <_AdvancedDanmakuRenderPlan>[];
    for (final event in _timeline.windowAt(positionMs)) {
      if (!settings.allowsAdvancedEvent(event) || event.path.isEmpty) {
        continue;
      }
      final fontSize = (25 * event.fontSizeScale * settings.fontScale)
          .clamp(10.0, 72.0)
          .toDouble();
      final usesOpacityLayer = (event.alphaFrom - event.alphaTo).abs() > 0.001;
      final fixedOpacity = (event.alphaFrom * settings.opacity)
          .clamp(0.0, 1.0)
          .toDouble();
      if (!usesOpacityLayer && fixedOpacity <= 0) {
        continue;
      }
      plans.add(
        _AdvancedDanmakuRenderPlan(
          event: event,
          fontSize: fontSize,
          usesOpacityLayer: usesOpacityLayer,
          fixedOpacity: fixedOpacity,
        ),
      );
    }
    return _plans = List<_AdvancedDanmakuRenderPlan>.unmodifiable(plans);
  }
}

final class _DanmakuTimelineIndex<T> {
  _DanmakuTimelineIndex({required this.timeOf, required this.idOf});

  static const int _lookBehindMs =
      MediaDanmakuPainter._maximumVisibleDurationMs + 1000;
  static const int _refreshAfterMs = 15000;
  static const int _lookAheadMs = _refreshAfterMs;
  static const int _backwardToleranceMs = 1000;

  final int Function(T event) timeOf;
  final String Function(T event) idOf;
  List<T>? _source;
  List<T> _sorted = <T>[];

  bool updateSource(List<T> source) {
    if (identical(_source, source)) {
      return false;
    }
    _source = source;
    _sorted = List<T>.of(source)
      ..sort((left, right) {
        final byTime = timeOf(left).compareTo(timeOf(right));
        return byTime != 0 ? byTime : idOf(left).compareTo(idOf(right));
      });
    return true;
  }

  List<T> windowAt(int positionMs) {
    final startMs = positionMs - _lookBehindMs;
    final endMs = positionMs + _lookAheadMs;
    final start = _lowerBound(startMs);
    final end = _upperBound(endMs);
    return _sorted.sublist(start, end);
  }

  static bool covers(int anchorMs, int positionMs) {
    return positionMs >= anchorMs - _backwardToleranceMs &&
        positionMs <= anchorMs + _refreshAfterMs;
  }

  int _lowerBound(int timeMs) {
    var low = 0;
    var high = _sorted.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (timeOf(_sorted[middle]) < timeMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _upperBound(int timeMs) {
    var low = 0;
    var high = _sorted.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (timeOf(_sorted[middle]) <= timeMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

final class _DanmakuTextCache {
  static const int maximumEntryCount = 256;

  final LinkedHashMap<String, _CachedDanmakuText> _entries =
      LinkedHashMap<String, _CachedDanmakuText>();

  int get length => _entries.length;

  TextPainter resolve({
    required MediaDanmakuEvent event,
    required double fontSize,
    required double opacity,
  }) {
    final colorValue = (event.style.color ?? 0xFFFFFF)
        .clamp(0, 0xFFFFFF)
        .toInt();
    return _resolve(
      key: 'standard:${event.id}',
      text: event.text,
      fontSize: fontSize,
      colorValue: colorValue,
      opacity: opacity,
      maxLines: 1,
    );
  }

  TextPainter resolveAdvanced({
    required MediaAdvancedDanmakuEvent event,
    required double fontSize,
    required double opacity,
  }) {
    return _resolve(
      key: 'advanced:${event.id}',
      text: event.text,
      fontSize: fontSize,
      colorValue: (event.color ?? 0xFFFFFF).clamp(0, 0xFFFFFF).toInt(),
      opacity: opacity,
      maxLines: null,
    );
  }

  TextPainter _resolve({
    required String key,
    required String text,
    required double fontSize,
    required int colorValue,
    required double opacity,
    required int? maxLines,
  }) {
    final cached = _entries[key];
    if (cached != null &&
        cached.text == text &&
        cached.fontSize == fontSize &&
        cached.colorValue == colorValue &&
        cached.opacity == opacity &&
        cached.maxLines == maxLines) {
      return cached.painter;
    }
    _entries.remove(key);
    cached?.painter.dispose();
    final color = Color(0xFF000000 | colorValue).withValues(alpha: opacity);
    final shadow = const Color(
      0xE6000000,
    ).withValues(alpha: (0.9 * opacity).clamp(0.0, 1.0).toDouble());
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          shadows: <Shadow>[Shadow(color: shadow, offset: const Offset(1, 1))],
        ),
      ),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
    )..layout();
    _entries[key] = _CachedDanmakuText(
      text: text,
      fontSize: fontSize,
      colorValue: colorValue,
      opacity: opacity,
      maxLines: maxLines,
      painter: painter,
    );
    while (_entries.length > maximumEntryCount) {
      _entries.remove(_entries.keys.first)?.painter.dispose();
    }
    return painter;
  }

  void dispose() {
    for (final entry in _entries.values) {
      entry.painter.dispose();
    }
    _entries.clear();
  }
}

final class _CachedDanmakuText {
  const _CachedDanmakuText({
    required this.text,
    required this.fontSize,
    required this.colorValue,
    required this.opacity,
    required this.maxLines,
    required this.painter,
  });

  final String text;
  final double fontSize;
  final int colorValue;
  final double opacity;
  final int? maxLines;
  final TextPainter painter;
}

final class _MediaDanmakuClock extends ChangeNotifier {
  _MediaDanmakuClock({
    required int positionMs,
    required this._playbackState,
    required this._playbackRate,
  }) : _anchorPositionMs = positionMs {
    if (_playbackState == VesperPlaybackState.playing) {
      _elapsedSinceAnchor.start();
    }
  }

  final Stopwatch _elapsedSinceAnchor = Stopwatch();
  int _anchorPositionMs;
  VesperPlaybackState _playbackState;
  double _playbackRate;

  int get currentPositionMs {
    if (_playbackState != VesperPlaybackState.playing) {
      return _anchorPositionMs;
    }
    return _anchorPositionMs +
        (_elapsedSinceAnchor.elapsedMilliseconds * _playbackRate).round();
  }

  void sync({
    required int positionMs,
    required VesperPlaybackState playbackState,
    required double playbackRate,
    bool notify = true,
  }) {
    _anchorPositionMs = positionMs;
    _playbackState = playbackState;
    _playbackRate = playbackRate;
    _elapsedSinceAnchor
      ..stop()
      ..reset();
    if (_playbackState == VesperPlaybackState.playing) {
      _elapsedSinceAnchor.start();
    }
    if (notify) {
      notifyListeners();
    }
  }

  void notifyFrame() => notifyListeners();
}

/// 弹幕层：把 provider 会话接入播放时间线并渲染不可变快照。
class MediaDanmakuLayer extends StatefulWidget {
  const MediaDanmakuLayer({
    super.key,
    required this.provider,
    required this.target,
    required this.positionMs,
    required this.playbackState,
    required this.playbackRate,
    this.settings = const MediaDanmakuOverlaySettings(),
    this.onMetricsChanged,
  });

  final MediaDanmakuProvider provider;
  final MediaPlaybackTarget target;
  final int positionMs;
  final VesperPlaybackState playbackState;
  final double playbackRate;
  final MediaDanmakuOverlaySettings settings;
  final ValueChanged<MediaDanmakuOverlayMetrics>? onMetricsChanged;

  @override
  State<MediaDanmakuLayer> createState() => _MediaDanmakuLayerState();
}

class _MediaDanmakuLayerState extends State<MediaDanmakuLayer> {
  MediaDanmakuSession? _session;
  StreamSubscription<MediaDanmakuSnapshot>? _subscription;
  MediaDanmakuSnapshot _snapshot = const MediaDanmakuSnapshot();
  int _sessionGeneration = 0;
  Timer? _metricsTimer;
  MediaDanmakuOverlayMetrics? _pendingMetrics;
  DateTime? _lastMetricsSentAt;

  @override
  void initState() {
    super.initState();
    _openSession();
  }

  @override
  void didUpdateWidget(covariant MediaDanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetChanged =
        !identical(oldWidget.provider, widget.provider) ||
        oldWidget.target.detail.mediaId != widget.target.detail.mediaId ||
        oldWidget.target.entry.entryId != widget.target.entry.entryId;
    if (targetChanged) {
      _openSession();
    } else if (oldWidget.positionMs != widget.positionMs) {
      _session?.updatePosition(widget.positionMs);
    }
    if (oldWidget.onMetricsChanged != widget.onMetricsChanged ||
        oldWidget.settings != widget.settings) {
      _scheduleMetricsReport();
    }
  }

  @override
  void dispose() {
    _sessionGeneration += 1;
    unawaited(_subscription?.cancel());
    unawaited(_session?.close());
    _metricsTimer?.cancel();
    super.dispose();
  }

  void _openSession() {
    final generation = ++_sessionGeneration;
    unawaited(_subscription?.cancel());
    unawaited(_session?.close());
    final session = widget.provider.openSession(widget.target);
    _session = session;
    _snapshot = const MediaDanmakuSnapshot();
    _scheduleMetricsReport();
    _subscription = session.snapshots.listen(
      (snapshot) {
        if (mounted && generation == _sessionGeneration) {
          setState(() {
            _snapshot = snapshot;
          });
          _scheduleMetricsReport();
        }
      },
      onError: (Object error) {
        if (mounted && generation == _sessionGeneration) {
          setState(() {
            _snapshot = MediaDanmakuSnapshot(error: error);
          });
          _scheduleMetricsReport();
        }
      },
    );
    session.updatePosition(widget.positionMs);
  }

  void _scheduleMetricsReport() {
    final callback = widget.onMetricsChanged;
    if (callback == null) {
      _pendingMetrics = null;
      _metricsTimer?.cancel();
      _metricsTimer = null;
      return;
    }
    _pendingMetrics = MediaDanmakuOverlayMetrics(
      active: widget.settings.enabled,
      loadedBasicItemCount: _snapshot.events.length,
      loadedAdvancedItemCount: _snapshot.advancedEvents.length,
      advancedEffectsActive:
          widget.settings.enabled &&
          widget.settings.showAdvanced &&
          _snapshot.advancedEvents.isNotEmpty,
    );
    final lastSentAt = _lastMetricsSentAt;
    final elapsed = lastSentAt == null
        ? const Duration(milliseconds: 500)
        : DateTime.now().difference(lastSentAt);
    if (elapsed >= const Duration(milliseconds: 500)) {
      _emitMetricsReport();
      return;
    }
    _metricsTimer ??= Timer(
      const Duration(milliseconds: 500) - elapsed,
      _emitMetricsReport,
    );
  }

  void _emitMetricsReport() {
    _metricsTimer?.cancel();
    _metricsTimer = null;
    final callback = widget.onMetricsChanged;
    final metrics = _pendingMetrics;
    _pendingMetrics = null;
    if (!mounted || callback == null || metrics == null) {
      return;
    }
    _lastMetricsSentAt = DateTime.now();
    callback(metrics);
  }

  @override
  Widget build(BuildContext context) {
    return MediaDanmakuOverlay(
      events: _snapshot.events,
      advancedEvents: _snapshot.advancedEvents,
      positionMs: widget.positionMs,
      playbackState: widget.playbackState,
      playbackRate: widget.playbackRate,
      settings: widget.settings,
    );
  }
}

enum _DanmakuRenderKind { scroll, reverse, top, bottom }

final class _AdvancedDanmakuRenderPlan {
  const _AdvancedDanmakuRenderPlan({
    required this.event,
    required this.fontSize,
    required this.usesOpacityLayer,
    required this.fixedOpacity,
  });

  final MediaAdvancedDanmakuEvent event;
  final double fontSize;
  final bool usesOpacityLayer;
  final double fixedOpacity;
}

final class _DanmakuRenderPlan {
  const _DanmakuRenderPlan({
    required this.event,
    required this.kind,
    required this.top,
    required this.fontSize,
    required this.textWidth,
    required this.durationMs,
    required this.speed,
  });

  final MediaDanmakuEvent event;
  final _DanmakuRenderKind kind;
  final double top;
  final double fontSize;
  final double textWidth;
  final int durationMs;
  final double speed;

  _DanmakuRenderPlan copyWith({required double top}) {
    return _DanmakuRenderPlan(
      event: event,
      kind: kind,
      top: top,
      fontSize: fontSize,
      textWidth: textWidth,
      durationMs: durationMs,
      speed: speed,
    );
  }
}

final class _ScrollingLaneState {
  _DanmakuRenderPlan? last;
}
