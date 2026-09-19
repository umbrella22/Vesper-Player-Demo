import 'package:flutter/widgets.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_player/vesper_player.dart';

import '../danmaku/media_danmaku_overlay.dart';

/// Stores geometry for one mounted playback view. Fullscreen, collapsed, and
/// replacement views each start with unknown geometry, even with one controller.
class MediaVideoContent extends StatefulWidget {
  const MediaVideoContent({
    super.key,
    required this.active,
    required this.builder,
    this.overlayBuilder,
  });

  final bool active;
  final Widget Function(
    ValueChanged<VesperVideoSurfaceGeometry?> onGeometryChanged,
    Widget? contentOverlay,
    bool Function(Offset) onContentTap,
  )
  builder;
  final Widget Function(
    MediaDanmakuInteractionController interaction,
    bool visible,
  )?
  overlayBuilder;

  @override
  State<MediaVideoContent> createState() => _MediaVideoContentState();
}

class _MediaVideoContentState extends State<MediaVideoContent> {
  final _geometry = signal<VesperVideoSurfaceGeometry?>(null);
  final _interaction = MediaDanmakuInteractionController();
  Size _size = Size.zero;

  Rect? get _contentRect {
    final geometry = _geometry.value;
    if (!widget.active || geometry == null || _size.isEmpty) return null;
    // A native layout callback may trail Flutter by a frame. Never reuse a
    // rectangle measured for a different container; allow physical-pixel rounding.
    final tolerance = 1 / View.of(context).devicePixelRatio;
    if ((geometry.width - _size.width).abs() > tolerance ||
        (geometry.height - _size.height).abs() > tolerance) {
      return null;
    }
    final rect = geometry.contentRect;
    return Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
  }

  void _onGeometryChanged(VesperVideoSurfaceGeometry? geometry) {
    if (mounted) _geometry.value = geometry;
  }

  bool _onContentTap(Offset position) {
    final rect = _contentRect;
    if (rect == null || !rect.contains(position)) return false;
    return _interaction.selectAt(position - rect.topLeft);
  }

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      final overlayBuilder = widget.overlayBuilder;
      return widget.builder(
        _onGeometryChanged,
        overlayBuilder == null
            ? null
            : SignalBuilder(
                builder: (context) {
                  final rect = _contentRect;
                  return Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        left: rect?.left ?? 0,
                        top: rect?.top ?? 0,
                        width: rect?.width ?? 0,
                        height: rect?.height ?? 0,
                        child: Offstage(
                          offstage: rect == null,
                          child: TickerMode(
                            enabled: rect != null,
                            child: ClipRect(
                              child: overlayBuilder(_interaction, rect != null),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
        _onContentTap,
      );
    },
  );
}
