import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_player/vesper_player.dart';

import '../capabilities/media_danmaku.dart';
import '../models/media_playback_target.dart';

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
  late final _MediaDanmakuClock _clock;
  late final Ticker _ticker;
  final _DanmakuTextCache _textCache = _DanmakuTextCache();
  final _DanmakuLayoutCache _layoutCache = _DanmakuLayoutCache();
  final _AdvancedDanmakuLayoutCache _advancedLayoutCache =
      _AdvancedDanmakuLayoutCache();

  @override
  void initState() {
    super.initState();
    _clock = _MediaDanmakuClock(
      positionMs: widget.positionMs,
      playbackState: widget.playbackState,
      playbackRate: widget.playbackRate,
    );
    _ticker = createTicker((_) => _clock.notifyFrame());
    _syncTicker();
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
      );
    }
    if (!identical(oldWidget.events, widget.events) ||
        !identical(oldWidget.advancedEvents, widget.advancedEvents) ||
        oldWidget.settings != widget.settings) {
      _textCache.retainKeys(<String>{
        for (final event in widget.events)
          if (widget.settings.allowsStandardEvent(event))
            'standard:${event.id}',
        for (final event in widget.advancedEvents)
          if (widget.settings.allowsAdvancedEvent(event))
            'advanced:${event.id}',
      });
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _textCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.enabled ||
        (widget.events.isEmpty && widget.advancedEvents.isEmpty)) {
      return const SizedBox.shrink();
    }
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

  void _syncTicker() {
    final shouldTick =
        widget.playbackState == VesperPlaybackState.playing &&
        widget.settings.enabled &&
        (widget.events.isNotEmpty || widget.advancedEvents.isNotEmpty);
    if (shouldTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
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
    final plans = _plansFor(size);
    final positionMs = _clock.currentPositionMs;
    for (final plan in _visiblePlans(plans, positionMs)) {
      final offset = _offsetFor(plan, size.width, positionMs);
      if (offset != null) {
        plan.textPainter.paint(canvas, offset);
      }
    }
    final advancedPlans = _advancedLayoutCache.resolve(
      events: _advancedEvents,
      size: size,
      settings: _settings,
      textCache: _textCache,
    );
    for (final plan in _visibleAdvancedPlans(advancedPlans, positionMs)) {
      _paintAdvancedPlan(canvas, size, plan, positionMs);
    }
    canvas.restore();
  }

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
        textCache: _textCache,
      ),
      positionMs,
    ).map((plan) => plan.event.id).toList(growable: false);
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
        textCache: _textCache,
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
      _plansFor(size),
      positionMs,
    ).map((plan) => plan.event.id).toList(growable: false);
  }

  @visibleForTesting
  Offset? debugOffsetForEventAt({
    required String eventId,
    required int positionMs,
    required Size size,
  }) {
    for (final plan in _visiblePlans(_plansFor(size), positionMs)) {
      if (plan.event.id == eventId) {
        return _offsetFor(plan, size.width, positionMs);
      }
    }
    return null;
  }

  List<_DanmakuRenderPlan> _plansFor(Size size) {
    return _layoutCache.resolve(
      events: _events,
      size: size,
      settings: _settings,
      textCache: _textCache,
    );
  }

  Iterable<_DanmakuRenderPlan> _visiblePlans(
    List<_DanmakuRenderPlan> plans,
    int positionMs,
  ) sync* {
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
    for (var index = low; index < plans.length; index += 1) {
      final plan = plans[index];
      if (plan.event.timeMs > positionMs) {
        break;
      }
      final elapsedMs = positionMs - plan.event.timeMs;
      if (elapsedMs >= 0 && elapsedMs <= plan.event.durationMs) {
        yield plan;
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

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final center = Offset(
      plan.textPainter.width / 2,
      plan.textPainter.height / 2,
    );
    canvas.translate(center.dx, center.dy);
    canvas.rotate(event.rotationZDegrees * math.pi / 180);
    canvas.scale(math.cos(event.rotationYDegrees * math.pi / 180), 1);
    canvas.translate(-center.dx, -center.dy);
    canvas.saveLayer(
      Offset.zero & Size(plan.textPainter.width, plan.textPainter.height),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    plan.textPainter.paint(canvas, Offset.zero);
    canvas.restore();
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
        -plan.textPainter.width + plan.speed * elapsedMs,
        plan.top,
      ),
      _DanmakuRenderKind.top || _DanmakuRenderKind.bottom => Offset(
        (canvasWidth - plan.textPainter.width) / 2,
        plan.top,
      ),
    };
  }

  @override
  bool shouldRepaint(covariant MediaDanmakuPainter oldDelegate) {
    return !identical(oldDelegate._events, _events) ||
        !identical(oldDelegate._advancedEvents, _advancedEvents) ||
        oldDelegate._settings != _settings;
  }
}

final class _DanmakuLayoutCache {
  Size? _size;
  List<MediaDanmakuEvent>? _events;
  MediaDanmakuOverlaySettings? _settings;
  List<_DanmakuRenderPlan> _plans = const <_DanmakuRenderPlan>[];

  List<_DanmakuRenderPlan> resolve({
    required List<MediaDanmakuEvent> events,
    required Size size,
    required MediaDanmakuOverlaySettings settings,
    required _DanmakuTextCache textCache,
  }) {
    if (_size == size && identical(_events, events) && _settings == settings) {
      return _plans;
    }
    _size = size;
    _events = events;
    _settings = settings;
    _plans = _buildPlans(
      events: events,
      size: size,
      settings: settings,
      textCache: textCache,
    );
    return _plans;
  }

  List<_DanmakuRenderPlan> _buildPlans({
    required List<MediaDanmakuEvent> events,
    required Size size,
    required MediaDanmakuOverlaySettings settings,
    required _DanmakuTextCache textCache,
  }) {
    final density = settings.density.clamp(0.0, 1.0).toDouble();
    if (density <= 0) {
      return const <_DanmakuRenderPlan>[];
    }
    final prepared = <_PreparedDanmaku>[];
    var maximumTextHeight = 0.0;
    for (final event in events) {
      if (!settings.allowsStandardEvent(event)) {
        continue;
      }
      final fontSize = (25 * event.style.fontSizeScale * settings.fontScale)
          .clamp(10.0, 48.0)
          .toDouble();
      final painter = textCache.resolve(
        event: event,
        fontSize: fontSize,
        opacity: settings.opacity.clamp(0.0, 1.0).toDouble(),
      );
      maximumTextHeight = math.max(maximumTextHeight, painter.height);
      prepared.add(_PreparedDanmaku(event: event, textPainter: painter));
    }
    prepared.sort((left, right) {
      final byTime = left.event.timeMs.compareTo(right.event.timeMs);
      return byTime != 0 ? byTime : left.event.id.compareTo(right.event.id);
    });

    final laneHeight = math.max(22.0, maximumTextHeight + 4).toDouble();
    final scrollingBandHeight =
        size.height * settings.displayArea.clamp(0.25, 1.0).toDouble();
    final scrollLaneCount = ((scrollingBandHeight / laneHeight) * density)
        .floor()
        .clamp(1, 12)
        .toInt();
    final staticLaneCount = (scrollLaneCount / 2).ceil().clamp(1, 6).toInt();
    final scrollLanes = List<_ScrollingLaneState>.generate(
      scrollLaneCount,
      (_) => _ScrollingLaneState(),
    );
    final topLanes = List<int>.filled(staticLaneCount, 0);
    final bottomLanes = List<int>.filled(staticLaneCount, 0);
    final plans = <_DanmakuRenderPlan>[];

    for (final item in prepared) {
      final event = item.event;
      final position = event.channel == MediaDanmakuChannel.caption
          ? MediaDanmakuPosition.bottom
          : event.style.position;
      switch (position) {
        case MediaDanmakuPosition.roll:
        case MediaDanmakuPosition.reverse:
          final kind = position == MediaDanmakuPosition.reverse
              ? _DanmakuRenderKind.reverse
              : _DanmakuRenderKind.scroll;
          final speed =
              (size.width + item.textPainter.width) /
              MediaDanmakuPainter._scrollDurationMs;
          final candidate = _DanmakuRenderPlan(
            event: event,
            kind: kind,
            top: 0,
            textPainter: item.textPainter,
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
          topLanes[laneIndex] =
              event.timeMs + MediaDanmakuPainter._pinnedDurationMs;
          plans.add(
            _DanmakuRenderPlan(
              event: event,
              kind: _DanmakuRenderKind.top,
              top: 8 + laneIndex * laneHeight,
              textPainter: item.textPainter,
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
              textPainter: item.textPainter,
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
            canvasWidth +
            previous.textPainter.width -
            previous.speed * elapsedMs;
        return (canvasWidth - trailingEdge, trailingEdge / previous.speed);
      }(),
      _DanmakuRenderKind.reverse => () {
        final leadingEdge =
            -previous.textPainter.width + previous.speed * elapsedMs;
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
  Size? _size;
  List<MediaAdvancedDanmakuEvent>? _events;
  MediaDanmakuOverlaySettings? _settings;
  List<_AdvancedDanmakuRenderPlan> _plans =
      const <_AdvancedDanmakuRenderPlan>[];

  List<_AdvancedDanmakuRenderPlan> resolve({
    required List<MediaAdvancedDanmakuEvent> events,
    required Size size,
    required MediaDanmakuOverlaySettings settings,
    required _DanmakuTextCache textCache,
  }) {
    if (_size == size && identical(_events, events) && _settings == settings) {
      return _plans;
    }
    _size = size;
    _events = events;
    _settings = settings;
    final plans = <_AdvancedDanmakuRenderPlan>[];
    for (final event in events) {
      if (!settings.allowsAdvancedEvent(event) || event.path.isEmpty) {
        continue;
      }
      final fontSize = (25 * event.fontSizeScale * settings.fontScale)
          .clamp(10.0, 72.0)
          .toDouble();
      plans.add(
        _AdvancedDanmakuRenderPlan(
          event: event,
          textPainter: textCache.resolveAdvanced(
            event: event,
            fontSize: fontSize,
          ),
        ),
      );
    }
    plans.sort((left, right) {
      final byTime = left.event.timeMs.compareTo(right.event.timeMs);
      return byTime != 0 ? byTime : left.event.id.compareTo(right.event.id);
    });
    return _plans = List<_AdvancedDanmakuRenderPlan>.unmodifiable(plans);
  }
}

final class _DanmakuTextCache {
  final Map<String, _CachedDanmakuText> _entries =
      <String, _CachedDanmakuText>{};

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
  }) {
    return _resolve(
      key: 'advanced:${event.id}',
      text: event.text,
      fontSize: fontSize,
      colorValue: (event.color ?? 0xFFFFFF).clamp(0, 0xFFFFFF).toInt(),
      opacity: 1,
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
    cached?.painter.dispose();
    final color = Color(0xFF000000 | colorValue).withValues(alpha: opacity);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          shadows: const <Shadow>[
            Shadow(
              color: Color(0xCC000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
            Shadow(color: Color(0xAA000000), blurRadius: 1),
          ],
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
    return painter;
  }

  void retainKeys(Set<String> keys) {
    final removedIds = _entries.keys
        .where((id) => !keys.contains(id))
        .toList(growable: false);
    for (final id in removedIds) {
      _entries.remove(id)?.painter.dispose();
    }
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
    notifyListeners();
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
  });

  final MediaDanmakuProvider provider;
  final MediaPlaybackTarget target;
  final int positionMs;
  final VesperPlaybackState playbackState;
  final double playbackRate;
  final MediaDanmakuOverlaySettings settings;

  @override
  State<MediaDanmakuLayer> createState() => _MediaDanmakuLayerState();
}

class _MediaDanmakuLayerState extends State<MediaDanmakuLayer> {
  MediaDanmakuSession? _session;
  StreamSubscription<MediaDanmakuSnapshot>? _subscription;
  MediaDanmakuSnapshot _snapshot = const MediaDanmakuSnapshot();
  int _sessionGeneration = 0;

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
  }

  @override
  void dispose() {
    _sessionGeneration += 1;
    unawaited(_subscription?.cancel());
    unawaited(_session?.close());
    super.dispose();
  }

  void _openSession() {
    final generation = ++_sessionGeneration;
    unawaited(_subscription?.cancel());
    unawaited(_session?.close());
    final session = widget.provider.openSession(widget.target);
    _session = session;
    _snapshot = const MediaDanmakuSnapshot();
    _subscription = session.snapshots.listen(
      (snapshot) {
        if (mounted && generation == _sessionGeneration) {
          setState(() {
            _snapshot = snapshot;
          });
        }
      },
      onError: (Object error) {
        if (mounted && generation == _sessionGeneration) {
          setState(() {
            _snapshot = MediaDanmakuSnapshot(error: error);
          });
        }
      },
    );
    session.updatePosition(widget.positionMs);
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
    required this.textPainter,
  });

  final MediaAdvancedDanmakuEvent event;
  final TextPainter textPainter;
}

final class _PreparedDanmaku {
  const _PreparedDanmaku({required this.event, required this.textPainter});

  final MediaDanmakuEvent event;
  final TextPainter textPainter;
}

final class _DanmakuRenderPlan {
  const _DanmakuRenderPlan({
    required this.event,
    required this.kind,
    required this.top,
    required this.textPainter,
    required this.durationMs,
    required this.speed,
  });

  final MediaDanmakuEvent event;
  final _DanmakuRenderKind kind;
  final double top;
  final TextPainter textPainter;
  final int durationMs;
  final double speed;

  _DanmakuRenderPlan copyWith({required double top}) {
    return _DanmakuRenderPlan(
      event: event,
      kind: kind,
      top: top,
      textPainter: textPainter,
      durationMs: durationMs,
      speed: speed,
    );
  }
}

final class _ScrollingLaneState {
  _DanmakuRenderPlan? last;
}
