import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_player/vesper_player.dart';

import '../capabilities/media_danmaku.dart';
import '../models/media_playback_target.dart';

/// 弹幕 overlay 设置（开关/透明度/密度）。
final class MediaDanmakuOverlaySettings {
  const MediaDanmakuOverlaySettings({
    this.enabled = true,
    this.opacity = 0.82,
    this.density = 0.6,
  });

  final bool enabled;
  final double opacity;
  final double density;

  MediaDanmakuOverlaySettings copyWith({
    bool? enabled,
    double? opacity,
    double? density,
  }) {
    return MediaDanmakuOverlaySettings(
      enabled: enabled ?? this.enabled,
      opacity: opacity ?? this.opacity,
      density: density ?? this.density,
    );
  }
}

/// 通用弹幕渲染：滚动/逆向/顶部/底部 + 车道碰撞避让。
///
/// 平台解析层把自有协议归一化为 [MediaDanmakuEvent] 事件流，
/// 本 overlay 只消费事件列表与播放时间线。
class MediaDanmakuOverlay extends StatefulWidget {
  const MediaDanmakuOverlay({
    super.key,
    required this.events,
    required this.positionMs,
    required this.playbackState,
    required this.playbackRate,
    required this.settings,
  });

  final List<MediaDanmakuEvent> events;
  final int positionMs;
  final VesperPlaybackState playbackState;
  final double playbackRate;
  final MediaDanmakuOverlaySettings settings;

  @override
  State<MediaDanmakuOverlay> createState() => _MediaDanmakuOverlayState();
}

class _MediaDanmakuOverlayState extends State<MediaDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  // 标准弹幕字号（B 站 XML 的 25 为标准档，scale=1.0 时渲染该字号）。
  static const double _baseFontSize = 25;

  late final Ticker _ticker;
  DateTime _anchorWallClock = DateTime.now();
  int _anchorPositionMs = 0;
  double _cachedWidth = -1;
  double _cachedHeight = -1;
  double _cachedDensity = -1;
  List<MediaDanmakuEvent> _cachedEvents = const <MediaDanmakuEvent>[];
  List<_LaidOutDanmaku> _cachedLayout = const <_LaidOutDanmaku>[];

  @override
  void initState() {
    super.initState();
    _anchorPositionMs = widget.positionMs;
    _ticker = createTicker((_) => setState(() {}));
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant MediaDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionMs != widget.positionMs ||
        oldWidget.playbackState != widget.playbackState ||
        (oldWidget.playbackRate - widget.playbackRate).abs() > 0.001) {
      _anchorPositionMs = widget.positionMs;
      _anchorWallClock = DateTime.now();
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.enabled || widget.events.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          if (width <= 0 || height <= 0) {
            return const SizedBox.shrink();
          }

          final layout = _ensureLayout(width: width, height: height);
          final nowMs = _currentPositionMs();
          final children = <Widget>[];

          for (final item in layout) {
            final elapsedMs = nowMs - item.event.timeMs;
            if (elapsedMs < 0) {
              continue;
            }

            final positioned = switch (item.kind) {
              _DanmakuRenderKind.scroll => _buildScrollingDanmaku(
                item: item,
                width: width,
                elapsedMs: elapsedMs,
                reverse: false,
              ),
              _DanmakuRenderKind.reverse => _buildScrollingDanmaku(
                item: item,
                width: width,
                elapsedMs: elapsedMs,
                reverse: true,
              ),
              _DanmakuRenderKind.top ||
              _DanmakuRenderKind.bottom => _buildPinnedDanmaku(
                item: item,
                width: width,
                elapsedMs: elapsedMs,
              ),
            };
            if (positioned != null) {
              children.add(positioned);
            }
          }

          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: children,
          );
        },
      ),
    );
  }

  void _syncTicker() {
    // 无弹幕内容时不启动 ticker（省电；事件到达后经 didUpdateWidget 重启）。
    if (widget.playbackState == VesperPlaybackState.playing &&
        widget.settings.enabled &&
        widget.events.isNotEmpty) {
      if (!_ticker.isActive) {
        _ticker.start();
      }
      return;
    }
    if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  int _currentPositionMs() {
    if (widget.playbackState != VesperPlaybackState.playing) {
      return widget.positionMs;
    }
    final elapsedMs = DateTime.now()
        .difference(_anchorWallClock)
        .inMilliseconds;
    return _anchorPositionMs + (elapsedMs * widget.playbackRate).round();
  }

  List<_LaidOutDanmaku> _ensureLayout({
    required double width,
    required double height,
  }) {
    if (_cachedWidth == width &&
        _cachedHeight == height &&
        (_cachedDensity - widget.settings.density).abs() < 0.001 &&
        identical(_cachedEvents, widget.events)) {
      return _cachedLayout;
    }

    _cachedWidth = width;
    _cachedHeight = height;
    _cachedDensity = widget.settings.density;
    _cachedEvents = widget.events;
    _cachedLayout = _buildLayout(
      events: widget.events,
      width: width,
      height: height,
      density: widget.settings.density,
    );
    return _cachedLayout;
  }

  List<_LaidOutDanmaku> _buildLayout({
    required List<MediaDanmakuEvent> events,
    required double width,
    required double height,
    required double density,
  }) {
    final laneHeight = (22 + density * 8).clamp(22, 30).toDouble();
    final scrollingBandHeight = height * (0.28 + density * 0.42);
    final scrollLaneCount = (scrollingBandHeight / laneHeight)
        .floor()
        .clamp(2, 12)
        .toInt();
    final staticLaneCount = (scrollLaneCount / 2).ceil().clamp(1, 6).toInt();

    final scrollLanes = List<_LaneState>.generate(
      scrollLaneCount,
      (_) => const _LaneState(),
    );
    final topLanes = List<_LaneState>.generate(
      staticLaneCount,
      (_) => const _LaneState(),
    );
    final bottomLanes = List<_LaneState>.generate(
      staticLaneCount,
      (_) => const _LaneState(),
    );

    final laidOut = <_LaidOutDanmaku>[];
    for (final event in events) {
      final position = event.style.position;
      final effectiveFontSize =
          (_baseFontSize * event.style.fontSizeScale).clamp(16, 30).toDouble();
      final textWidth = _estimateTextWidth(event.text, effectiveFontSize);

      switch (position) {
        case MediaDanmakuPosition.roll:
        case MediaDanmakuPosition.reverse:
          const durationMs = 6200;
          final speed = (width + textWidth) / durationMs;
          final laneIndex = _pickScrollingLane(
            lanes: scrollLanes,
            appearAtMs: event.timeMs,
          );
          final laneTop = 8 + laneIndex * laneHeight;
          scrollLanes[laneIndex] = _LaneState(
            nextAvailableAtMs:
                event.timeMs + ((textWidth + 24) / speed).ceil(),
          );
          laidOut.add(
            _LaidOutDanmaku(
              event: event,
              kind: position == MediaDanmakuPosition.reverse
                  ? _DanmakuRenderKind.reverse
                  : _DanmakuRenderKind.scroll,
              top: laneTop,
              textWidth: textWidth,
              fontSize: effectiveFontSize,
              durationMs: durationMs,
            ),
          );
        case MediaDanmakuPosition.top:
          const durationMs = 4200;
          final laneIndex = _pickStaticLane(
            lanes: topLanes,
            appearAtMs: event.timeMs,
          );
          topLanes[laneIndex] = _LaneState(
            nextAvailableAtMs: event.timeMs + durationMs,
          );
          laidOut.add(
            _LaidOutDanmaku(
              event: event,
              kind: _DanmakuRenderKind.top,
              top: 8 + laneIndex * laneHeight,
              textWidth: textWidth,
              fontSize: effectiveFontSize,
              durationMs: durationMs,
            ),
          );
        case MediaDanmakuPosition.bottom:
          const durationMs = 4200;
          final laneIndex = _pickStaticLane(
            lanes: bottomLanes,
            appearAtMs: event.timeMs,
          );
          bottomLanes[laneIndex] = _LaneState(
            nextAvailableAtMs: event.timeMs + durationMs,
          );
          laidOut.add(
            _LaidOutDanmaku(
              event: event,
              kind: _DanmakuRenderKind.bottom,
              top: height - ((laneIndex + 1) * laneHeight) - 8,
              textWidth: textWidth,
              fontSize: effectiveFontSize,
              durationMs: durationMs,
            ),
          );
      }
    }

    return laidOut;
  }

  int _pickScrollingLane({
    required List<_LaneState> lanes,
    required int appearAtMs,
  }) {
    var selectedIndex = 0;
    var earliestAvailableAtMs = lanes.first.nextAvailableAtMs;
    for (var index = 0; index < lanes.length; index += 1) {
      final lane = lanes[index];
      if (appearAtMs >= lane.nextAvailableAtMs) {
        return index;
      }
      if (lane.nextAvailableAtMs < earliestAvailableAtMs) {
        earliestAvailableAtMs = lane.nextAvailableAtMs;
        selectedIndex = index;
      }
    }
    return selectedIndex;
  }

  int _pickStaticLane({
    required List<_LaneState> lanes,
    required int appearAtMs,
  }) {
    return _pickScrollingLane(lanes: lanes, appearAtMs: appearAtMs);
  }

  double _estimateTextWidth(String text, double fontSize) {
    final runeCount = text.runes.length;
    return (runeCount * fontSize * 0.62) + fontSize * 1.8;
  }

  Widget? _buildScrollingDanmaku({
    required _LaidOutDanmaku item,
    required double width,
    required int elapsedMs,
    required bool reverse,
  }) {
    if (elapsedMs > item.durationMs) {
      return null;
    }
    final progress = elapsedMs / item.durationMs;
    final left = reverse
        ? (-item.textWidth) + progress * (width + item.textWidth)
        : width - progress * (width + item.textWidth);
    return Positioned(
      left: left,
      top: item.top,
      child: _DanmakuText(
        event: item.event,
        fontSize: item.fontSize,
        opacity: widget.settings.opacity,
      ),
    );
  }

  Widget? _buildPinnedDanmaku({
    required _LaidOutDanmaku item,
    required double width,
    required int elapsedMs,
  }) {
    if (elapsedMs > item.durationMs) {
      return null;
    }
    return Positioned(
      left: (width - item.textWidth) / 2,
      top: item.top,
      child: _DanmakuText(
        event: item.event,
        fontSize: item.fontSize,
        opacity: widget.settings.opacity,
      ),
    );
  }
}

class _DanmakuText extends StatelessWidget {
  const _DanmakuText({
    required this.event,
    required this.fontSize,
    required this.opacity,
  });

  final MediaDanmakuEvent event;
  final double fontSize;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final colorValue = event.style.color ?? 0xFFFFFF;
    final color = Color(0xFF000000 | colorValue.clamp(0, 0xFFFFFF)).withValues(
      alpha: opacity,
    );
    return Text(
      event.text,
      maxLines: 1,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 1)),
          Shadow(color: Color(0xAA000000), blurRadius: 1, offset: Offset(0, 0)),
        ],
      ),
    );
  }
}

/// 弹幕层：把 provider 事件流接入播放时间线并渲染。
///
/// 平台未声明弹幕能力（[MediaDanmakuProvider] 为 null）时不挂载。
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
  final List<MediaDanmakuEvent> _events = <MediaDanmakuEvent>[];
  StreamSubscription<MediaDanmakuEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant MediaDanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.provider, widget.provider) ||
        oldWidget.target.detail.mediaId != widget.target.detail.mediaId ||
        oldWidget.target.entry.entryId != widget.target.entry.entryId) {
      _events.clear();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = widget.provider.danmakuFor(widget.target).listen((event) {
      if (mounted) {
        setState(() {
          _events.add(event);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MediaDanmakuOverlay(
      events: _events,
      positionMs: widget.positionMs,
      playbackState: widget.playbackState,
      playbackRate: widget.playbackRate,
      settings: widget.settings,
    );
  }
}

enum _DanmakuRenderKind { scroll, reverse, top, bottom }

final class _LaidOutDanmaku {
  const _LaidOutDanmaku({
    required this.event,
    required this.kind,
    required this.top,
    required this.textWidth,
    required this.fontSize,
    required this.durationMs,
  });

  final MediaDanmakuEvent event;
  final _DanmakuRenderKind kind;
  final double top;
  final double textWidth;
  final double fontSize;
  final int durationMs;
}

final class _LaneState {
  const _LaneState({this.nextAvailableAtMs = 0});

  final int nextAvailableAtMs;
}
