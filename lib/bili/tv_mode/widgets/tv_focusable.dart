import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:bilibili_player/app/design/app_visual_theme.dart';

const _tvWhiteRamp = Color(0xFFFFFFFF);
const _tvBlackRamp = Color(0xFF000000);

enum TvFocusArea { rail, content, playbackControls, playbackPanel }

class TvGlassQualityScope extends InheritedWidget {
  const TvGlassQualityScope({
    super.key,
    this.maxQuality = GlassQuality.standard,
    required super.child,
  });

  final GlassQuality maxQuality;

  static GlassQuality of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TvGlassQualityScope>();
    final maximum = scope?.maxQuality ?? GlassQuality.standard;
    final adaptive = GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
    if (adaptive == null ||
        adaptive == GlassQuality.minimal ||
        maximum == GlassQuality.minimal) {
      return GlassQuality.minimal;
    }
    return GlassQuality.standard;
  }

  @override
  bool updateShouldNotify(TvGlassQualityScope oldWidget) {
    return oldWidget.maxQuality != maxQuality;
  }
}

class TvFocusAreaScope extends InheritedWidget {
  const TvFocusAreaScope({super.key, required this.area, required super.child});

  final TvFocusArea area;

  static TvFocusArea? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TvFocusAreaScope>()?.area;
  }

  @override
  bool updateShouldNotify(TvFocusAreaScope oldWidget) {
    return oldWidget.area != area;
  }
}

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.scale = 1.10,
    this.focusElevation = 12.0,
    this.focusCornerRadius = 12.0,
    this.baseCornerRadius = 8.0,
    this.duration = AppVisualTokens.tvFocusDuration,
    this.showGlow = true,
    this.onFocusChange,
    this.debugLabel,
    this.focusArea,
  });

  final Widget child;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final double focusElevation;
  final double focusCornerRadius;
  final double baseCornerRadius;
  final Duration duration;
  final bool showGlow;
  final ValueChanged<bool>? onFocusChange;
  final String? debugLabel;
  final TvFocusArea? focusArea;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _internalNode;
  FocusNode get _node => widget.focusNode ?? _internalNode;
  bool _hasFocus = false;
  bool _pressed = false;
  TvFocusArea? _lastFocusArea;

  @override
  void initState() {
    super.initState();
    _internalNode = widget.focusNode == null
        ? FocusNode(debugLabel: widget.debugLabel)
        : (widget.focusNode!..debugLabel ??= widget.debugLabel);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _node.requestFocus();
        }
      });
    }
    _node.addListener(_handleFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyFocusArea(widget.focusArea ?? TvFocusAreaScope.maybeOf(context));
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyFocusArea(widget.focusArea ?? TvFocusAreaScope.maybeOf(context));
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _internalNode.dispose();
    }
    super.dispose();
  }

  void _applyFocusArea(TvFocusArea? area) {
    if (_lastFocusArea == area) {
      return;
    }
    _lastFocusArea = area;
    setTvFocusArea(_node, area);
  }

  void _handleFocusChange() {
    final focused = _node.hasFocus;
    if (_hasFocus != focused) {
      _hasFocus = focused;
      widget.onFocusChange?.call(focused);
      if (mounted) {
        setState(() {});
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final direction = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
        LogicalKeyboardKey.arrowRight => TraversalDirection.right,
        _ => null,
      };
      if (direction != null) {
        return _moveFocus(direction);
      }
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space) {
        _setPressed(true);
        widget.onTap();
        WidgetsBinding.instance.addPostFrameCallback((_) => _setPressed(false));
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _setPressed(bool value) {
    if (mounted && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  KeyEventResult _moveFocus(TraversalDirection direction) {
    final moved = moveTvFocusSpatially(_node, direction);
    if (moved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        if (focusedContext != null) {
          Scrollable.ensureVisible(
            focusedContext,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    }
    return moved ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppVisualTokens.motionDuration(context, widget.duration);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _node.requestFocus();
        _setPressed(true);
      },
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKeyEvent: _handleKeyEvent,
        child: AnimatedScale(
          scale: _pressed
              ? AppVisualTokens.pressedScale
              : _hasFocus
              ? widget.scale
              : 1.0,
          duration: _pressed
              ? AppVisualTokens.motionDuration(
                  context,
                  AppVisualTokens.buttonPressDuration,
                )
              : duration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            decoration: _hasFocus && widget.showGlow
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      widget.focusCornerRadius,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _tvWhiteRamp.withValues(alpha: 0.18),
                        blurRadius: widget.focusElevation * 2,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: _tvBlackRamp.withValues(alpha: 0.35),
                        blurRadius: widget.focusElevation,
                        spreadRadius: 0,
                      ),
                    ],
                  )
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      widget.baseCornerRadius,
                    ),
                    boxShadow: const [],
                  ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

enum TvGlassSelectableState { idle, selected, focused, pressed }

typedef TvGlassSelectableBuilder =
    Widget Function(BuildContext context, TvGlassSelectableState state);

class TvGlassSelectable extends StatefulWidget {
  const TvGlassSelectable({
    super.key,
    required this.builder,
    required this.onTap,
    this.selected = false,
    this.focusNode,
    this.autofocus = false,
    this.debugLabel,
    this.focusArea,
    this.borderRadius = AppVisualTokens.controlRadius,
    this.scale = 1.035,
    this.padding = EdgeInsets.zero,
    this.onFocusChange,
    this.useOwnLayer = true,
  });

  final TvGlassSelectableBuilder builder;
  final VoidCallback onTap;
  final bool selected;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? debugLabel;
  final TvFocusArea? focusArea;
  final double borderRadius;
  final double scale;
  final EdgeInsetsGeometry padding;
  final ValueChanged<bool>? onFocusChange;
  final bool useOwnLayer;

  @override
  State<TvGlassSelectable> createState() => _TvGlassSelectableState();
}

class _TvGlassSelectableState extends State<TvGlassSelectable> {
  bool _focused = false;
  bool _pressed = false;

  TvGlassSelectableState get _state {
    if (_pressed) {
      return TvGlassSelectableState.pressed;
    }
    if (_focused) {
      return TvGlassSelectableState.focused;
    }
    if (widget.selected) {
      return TvGlassSelectableState.selected;
    }
    return TvGlassSelectableState.idle;
  }

  void _handleFocusChange(bool focused) {
    if (_focused != focused) {
      setState(() => _focused = focused);
      widget.onFocusChange?.call(focused);
    }
  }

  void _setPressed(bool pressed) {
    if (_pressed != pressed) {
      setState(() => _pressed = pressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final duration = AppVisualTokens.motionDuration(
      context,
      AppVisualTokens.tvFocusDuration,
    );
    final radius = BorderRadius.circular(widget.borderRadius);
    final content = AnimatedContainer(
      key: ValueKey<String>(
        'tv-glass-selectable-state-${widget.debugLabel ?? 'selectable'}',
      ),
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: switch (state) {
          TvGlassSelectableState.focused => const Color(0x00FFFFFF),
          TvGlassSelectableState.pressed => const Color(0x14FFFFFF),
          TvGlassSelectableState.selected => const Color(0x00FFFFFF),
          TvGlassSelectableState.idle => const Color(0x00000000),
        },
        borderRadius: radius,
        border: Border.all(
          color: switch (state) {
            TvGlassSelectableState.focused => const Color(0x66FFFFFF),
            TvGlassSelectableState.pressed => const Color(0x88FFFFFF),
            TvGlassSelectableState.selected => const Color(0x00FFFFFF),
            TvGlassSelectableState.idle => const Color(0x00000000),
          },
        ),
      ),
      child: widget.builder(context, state),
    );

    return TvFocusable(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      scale: widget.scale,
      showGlow: false,
      focusCornerRadius: widget.borderRadius,
      baseCornerRadius: widget.borderRadius,
      duration: duration,
      focusArea: widget.focusArea,
      debugLabel: widget.debugLabel,
      onFocusChange: _handleFocusChange,
      onTap: widget.onTap,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: _focused
            ? GlassContainer(
                key: ValueKey<String>(
                  'tv-glass-focus-${widget.debugLabel ?? 'selectable'}',
                ),
                useOwnLayer: widget.useOwnLayer,
                quality: widget.useOwnLayer
                    ? TvGlassQualityScope.of(context)
                    : null,
                shape: LiquidRoundedSuperellipse(
                  borderRadius: widget.borderRadius,
                ),
                settings: widget.useOwnLayer
                    ? const LiquidGlassSettings(
                        blur: 7,
                        thickness: 18,
                        glassColor: Color(0x00FFFFFF),
                        lightIntensity: 0.72,
                        saturation: 1.18,
                      )
                    : null,
                child: content,
              )
            : content,
      ),
    );
  }
}

class TvGlowOverlay extends StatelessWidget {
  const TvGlowOverlay({
    super.key,
    required this.visible,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.glowColor = const Color(0x22FFFFFF),
  });

  final bool visible;
  final Widget child;
  final BorderRadius borderRadius;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (visible)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: math.sqrt2,
                    colors: [glowColor, const Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

typedef TvFocusableSurfaceBuilder =
    Widget Function(BuildContext context, bool focused);

class TvFocusableSurface extends StatefulWidget {
  const TvFocusableSurface({
    super.key,
    required this.builder,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.debugLabel,
    this.scale = 1.12,
    this.borderRadius = 14,
    this.focusPadding = 8,
    this.useOverlayLift = true,
    this.focusArea,
  });

  final TvFocusableSurfaceBuilder builder;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? debugLabel;
  final double scale;
  final double borderRadius;
  final double focusPadding;
  final bool useOverlayLift;
  final TvFocusArea? focusArea;

  @override
  State<TvFocusableSurface> createState() => _TvFocusableSurfaceState();
}

class _TvFocusableSurfaceState extends State<TvFocusableSurface> {
  final GlobalKey _targetKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  late final OverlayPortalController _overlayController =
      OverlayPortalController(debugLabel: widget.debugLabel);
  bool _focused = false;

  void _handleFocusChange(bool focused) {
    if (_focused == focused) {
      return;
    }
    if (widget.useOverlayLift) {
      if (focused) {
        _overlayController.show();
      } else if (_overlayController.isShowing) {
        _overlayController.hide();
      }
    }
    setState(() {
      _focused = focused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppVisualTokens.motionDuration(
      context,
      AppVisualTokens.tvFocusDuration,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetSize =
            constraints.hasBoundedWidth && constraints.hasBoundedHeight
            ? constraints.biggest
            : null;
        return TvFocusable(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          scale: 1,
          focusElevation: 0,
          focusCornerRadius: widget.borderRadius,
          baseCornerRadius: widget.borderRadius,
          showGlow: false,
          debugLabel: widget.debugLabel,
          focusArea: widget.focusArea,
          onFocusChange: _handleFocusChange,
          onTap: widget.onTap,
          child: widget.useOverlayLift
              ? OverlayPortal(
                  controller: _overlayController,
                  overlayChildBuilder: (context) =>
                      _buildFocusedOverlay(context, targetSize),
                  child: CompositedTransformTarget(
                    link: _layerLink,
                    child: Opacity(
                      key: _targetKey,
                      opacity: _focused ? 0 : 1,
                      child: _TvFocusableSurfaceBody(
                        focused: false,
                        borderRadius: widget.borderRadius,
                        builder: widget.builder,
                      ),
                    ),
                  ),
                )
              : _TvFocusableSurfaceBody(
                  key: _targetKey,
                  focused: _focused,
                  borderRadius: widget.borderRadius,
                  builder: widget.builder,
                  contentPadding: EdgeInsets.zero,
                  inlineWrapper: (context, child) => Padding(
                    padding: EdgeInsets.all(widget.focusPadding),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: _focused ? 1 : 0),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, -2 * value),
                          child: Transform.scale(
                            scale: ui.lerpDouble(1, widget.scale, value)!,
                            alignment: Alignment.center,
                            child: child,
                          ),
                        );
                      },
                      child: child,
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildFocusedOverlay(BuildContext context, Size? layoutSize) {
    final renderObject = _targetKey.currentContext?.findRenderObject();
    final measuredSize = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.size
        : null;
    final targetSize = layoutSize ?? measuredSize;
    if (targetSize == null || targetSize.width <= 0 || targetSize.height <= 0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.topLeft,
        child: UnconstrainedBox(
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(-widget.focusPadding, -widget.focusPadding),
            child: _TvFocusableSurfaceLift(
              size: targetSize,
              scale: widget.scale,
              borderRadius: widget.borderRadius,
              padding: widget.focusPadding,
              builder: widget.builder,
            ),
          ),
        ),
      ),
    );
  }
}

class _TvFocusableSurfaceLift extends StatelessWidget {
  const _TvFocusableSurfaceLift({
    required this.size,
    required this.scale,
    required this.borderRadius,
    required this.padding,
    required this.builder,
  });

  final Size size;
  final double scale;
  final double borderRadius;
  final double padding;
  final TvFocusableSurfaceBuilder builder;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final duration = AppVisualTokens.motionDuration(
      context,
      AppVisualTokens.tvFocusDuration,
    );
    return SizedBox.fromSize(
      size: Size(size.width + padding * 2, size.height + padding * 2),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: scale),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            alignment: Alignment.center,
            child: child,
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: _tvWhiteRamp.withValues(alpha: 0.20),
                blurRadius: 34,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: _tvBlackRamp.withValues(alpha: 0.45),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: _TvFocusableSurfaceBody(
            focused: true,
            borderRadius: borderRadius,
            contentPadding: EdgeInsets.all(padding),
            builder: builder,
          ),
        ),
      ),
    );
  }
}

class _TvFocusableSurfaceBody extends StatelessWidget {
  const _TvFocusableSurfaceBody({
    super.key,
    required this.focused,
    required this.borderRadius,
    required this.builder,
    this.contentPadding = EdgeInsets.zero,
    this.inlineWrapper,
  });

  final bool focused;
  final double borderRadius;
  final TvFocusableSurfaceBuilder builder;
  final EdgeInsetsGeometry contentPadding;
  final Widget Function(BuildContext context, Widget child)? inlineWrapper;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final duration = AppVisualTokens.motionDuration(
      context,
      AppVisualTokens.tvFocusDuration,
    );
    final body = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: focused ? const Color(0xDDF8FBFF) : const Color(0x00FFFFFF),
          width: focused ? 1.4 : 0,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: _tvWhiteRamp.withValues(alpha: 0.18),
                  blurRadius: 30,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: _tvBlackRamp.withValues(alpha: 0.42),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: GlassContainer(
                    key: const ValueKey<String>('tv-content-glass-overlay'),
                    useOwnLayer: true,
                    quality: TvGlassQualityScope.of(context),
                    shape: LiquidRoundedSuperellipse(
                      borderRadius: borderRadius,
                    ),
                    settings: const LiquidGlassSettings(
                      blur: 8,
                      thickness: 20,
                      glassColor: Color(0x00FFFFFF),
                      lightIntensity: 0.72,
                      saturation: 1.18,
                    ),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            Positioned.fill(
              child: Padding(
                padding: contentPadding,
                child: builder(context, focused),
              ),
            ),
            if (focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x18FFFFFF),
                          Color(0x06FFFFFF),
                          Color(0x08000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return inlineWrapper?.call(context, body) ?? body;
  }
}

final Expando<TvFocusArea> _tvFocusAreas = Expando<TvFocusArea>('tvFocusAreas');

void setTvFocusArea(FocusNode node, TvFocusArea? area) {
  _tvFocusAreas[node] = area;
}

TvFocusArea? tvFocusAreaOf(FocusNode node) {
  return _tvFocusAreas[node];
}

bool moveTvFocusSpatially(
  FocusNode current,
  TraversalDirection direction, {
  Set<TvFocusArea>? allowedAreas,
}) {
  final currentArea = tvFocusAreaOf(current);
  if (allowedAreas != null) {
    return _moveTvFocusSpatially(
      current,
      direction,
      allowedAreas: allowedAreas,
    );
  }
  if (currentArea == TvFocusArea.content &&
      direction == TraversalDirection.left) {
    return _moveTvFocusSpatially(
          current,
          direction,
          allowedAreas: {TvFocusArea.content},
        ) ||
        _moveTvFocusSpatially(
          current,
          direction,
          allowedAreas: {TvFocusArea.rail},
        );
  }
  return _moveTvFocusSpatially(
    current,
    direction,
    allowedAreas: _defaultAllowedAreas(currentArea, direction),
  );
}

Set<TvFocusArea>? _defaultAllowedAreas(
  TvFocusArea? currentArea,
  TraversalDirection direction,
) {
  return switch (currentArea) {
    TvFocusArea.rail when direction == TraversalDirection.right => {
      TvFocusArea.content,
    },
    TvFocusArea.rail => {TvFocusArea.rail},
    TvFocusArea.content => {TvFocusArea.content},
    TvFocusArea.playbackControls => {TvFocusArea.playbackControls},
    TvFocusArea.playbackPanel => {TvFocusArea.playbackPanel},
    null => null,
  };
}

bool _moveTvFocusSpatially(
  FocusNode current,
  TraversalDirection direction, {
  Set<TvFocusArea>? allowedAreas,
}) {
  final currentRect = tvGlobalRectFor(current);
  final scope = current.nearestScope;
  if (currentRect == null || scope == null) {
    return false;
  }

  FocusNode? bestNode;
  var bestScore = double.infinity;
  for (final candidate in scope.traversalDescendants) {
    if (candidate == current ||
        candidate.skipTraversal ||
        !candidate.canRequestFocus) {
      continue;
    }
    if (allowedAreas != null &&
        !allowedAreas.contains(tvFocusAreaOf(candidate))) {
      continue;
    }
    final candidateRect = tvGlobalRectFor(candidate);
    if (candidateRect == null) {
      continue;
    }
    if (candidateRect.contains(currentRect.center) &&
        candidateRect.size != currentRect.size) {
      continue;
    }
    final primaryDelta = switch (direction) {
      TraversalDirection.up => currentRect.center.dy - candidateRect.center.dy,
      TraversalDirection.down =>
        candidateRect.center.dy - currentRect.center.dy,
      TraversalDirection.left =>
        currentRect.center.dx - candidateRect.center.dx,
      TraversalDirection.right =>
        candidateRect.center.dx - currentRect.center.dx,
    };
    if (primaryDelta <= 1) {
      continue;
    }
    final secondaryDelta =
        direction == TraversalDirection.left ||
            direction == TraversalDirection.right
        ? (candidateRect.center.dy - currentRect.center.dy).abs()
        : (candidateRect.center.dx - currentRect.center.dx).abs();
    final score = primaryDelta * 1000 + secondaryDelta;
    if (score < bestScore) {
      bestScore = score;
      bestNode = candidate;
    }
  }
  bestNode?.requestFocus();
  return bestNode != null;
}

Rect? tvGlobalRectFor(FocusNode node) {
  final context = node.context;
  final renderObject = context?.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return null;
  }
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}
