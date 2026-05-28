import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:vesper_player/vesper_player.dart';

import '../models/danmaku_models.dart';

class BiliDanmakuOverlay extends StatefulWidget {
  const BiliDanmakuOverlay({
    super.key,
    required this.entries,
    required this.positionMs,
    required this.playbackState,
    required this.playbackRate,
    required this.settings,
  });

  final List<BiliDanmakuEntry> entries;
  final int positionMs;
  final VesperPlaybackState playbackState;
  final double playbackRate;
  final DanmakuOverlaySettings settings;

  @override
  State<BiliDanmakuOverlay> createState() => _BiliDanmakuOverlayState();
}

class _BiliDanmakuOverlayState extends State<BiliDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  DateTime _anchorWallClock = DateTime.now();
  int _anchorPositionMs = 0;
  double _cachedWidth = -1;
  double _cachedHeight = -1;
  double _cachedDensity = -1;
  List<BiliDanmakuEntry> _cachedEntries = const <BiliDanmakuEntry>[];
  List<_LaidOutDanmaku> _cachedLayout = const <_LaidOutDanmaku>[];

  @override
  void initState() {
    super.initState();
    _anchorPositionMs = widget.positionMs;
    _ticker = createTicker((_) => setState(() {}));
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant BiliDanmakuOverlay oldWidget) {
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
    if (!widget.settings.enabled || widget.entries.isEmpty) {
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
            final elapsedMs = nowMs - item.entry.appearAtMs;
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
    if (widget.playbackState == VesperPlaybackState.playing &&
        widget.settings.enabled) {
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
        identical(_cachedEntries, widget.entries)) {
      return _cachedLayout;
    }

    _cachedWidth = width;
    _cachedHeight = height;
    _cachedDensity = widget.settings.density;
    _cachedEntries = widget.entries;
    _cachedLayout = _buildLayout(
      entries: widget.entries,
      width: width,
      height: height,
      density: widget.settings.density,
    );
    return _cachedLayout;
  }

  List<_LaidOutDanmaku> _buildLayout({
    required List<BiliDanmakuEntry> entries,
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
    for (final entry in entries) {
      if (!entry.mode.isSupported) {
        continue;
      }

      final effectiveFontSize = entry.fontSize.clamp(16, 30).toDouble();
      final textWidth = _estimateTextWidth(entry.text, effectiveFontSize);

      switch (entry.mode) {
        case BiliDanmakuMode.scroll:
        case BiliDanmakuMode.reverse:
          const durationMs = 6200;
          final speed = (width + textWidth) / durationMs;
          final laneIndex = _pickScrollingLane(
            lanes: scrollLanes,
            appearAtMs: entry.appearAtMs,
          );
          final laneTop = 8 + laneIndex * laneHeight;
          scrollLanes[laneIndex] = _LaneState(
            nextAvailableAtMs:
                entry.appearAtMs + ((textWidth + 24) / speed).ceil(),
          );
          laidOut.add(
            _LaidOutDanmaku(
              entry: entry,
              kind: entry.mode == BiliDanmakuMode.reverse
                  ? _DanmakuRenderKind.reverse
                  : _DanmakuRenderKind.scroll,
              top: laneTop,
              textWidth: textWidth,
              fontSize: effectiveFontSize,
              durationMs: durationMs,
            ),
          );
        case BiliDanmakuMode.top:
          const durationMs = 4200;
          final laneIndex = _pickStaticLane(
            lanes: topLanes,
            appearAtMs: entry.appearAtMs,
          );
          topLanes[laneIndex] = _LaneState(
            nextAvailableAtMs: entry.appearAtMs + durationMs,
          );
          laidOut.add(
            _LaidOutDanmaku(
              entry: entry,
              kind: _DanmakuRenderKind.top,
              top: 8 + laneIndex * laneHeight,
              textWidth: textWidth,
              fontSize: effectiveFontSize,
              durationMs: durationMs,
            ),
          );
        case BiliDanmakuMode.bottom:
          const durationMs = 4200;
          final laneIndex = _pickStaticLane(
            lanes: bottomLanes,
            appearAtMs: entry.appearAtMs,
          );
          bottomLanes[laneIndex] = _LaneState(
            nextAvailableAtMs: entry.appearAtMs + durationMs,
          );
          laidOut.add(
            _LaidOutDanmaku(
              entry: entry,
              kind: _DanmakuRenderKind.bottom,
              top: height - ((laneIndex + 1) * laneHeight) - 8,
              textWidth: textWidth,
              fontSize: effectiveFontSize,
              durationMs: durationMs,
            ),
          );
        case BiliDanmakuMode.unsupported:
          break;
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
        entry: item.entry,
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
        entry: item.entry,
        fontSize: item.fontSize,
        opacity: widget.settings.opacity,
      ),
    );
  }
}

class _DanmakuText extends StatelessWidget {
  const _DanmakuText({
    required this.entry,
    required this.fontSize,
    required this.opacity,
  });

  final BiliDanmakuEntry entry;
  final double fontSize;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final color = entry.color.withValues(alpha: opacity);
    return Text(
      entry.text,
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

enum _DanmakuRenderKind { scroll, reverse, top, bottom }

final class _LaidOutDanmaku {
  const _LaidOutDanmaku({
    required this.entry,
    required this.kind,
    required this.top,
    required this.textWidth,
    required this.fontSize,
    required this.durationMs,
  });

  final BiliDanmakuEntry entry;
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
