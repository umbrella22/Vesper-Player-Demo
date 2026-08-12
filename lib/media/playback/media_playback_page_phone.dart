part of 'media_playback_page.dart';

extension _MediaPlaybackPagePhoneLayout on _MediaPlaybackPageState {
  Widget _buildPlaybackLayout(
    BuildContext context,
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot, {
    required bool isFullscreen,
  }) {
    if (_isTvMode) {
      return _buildTvPlaybackLayout(context, controller, snapshot);
    }

    final visualTheme = AppVisualTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stageCornerPadding = _displayCornerPadding(context);
        // Stage and bottom surface read different VM signals, so each is
        // wrapped in its own SignalBuilder to rebuild independently.
        final stage = SignalBuilder(
          builder: (context) => _buildStage(
            controller: controller,
            snapshot: snapshot,
            isFullscreen: isFullscreen,
          ),
        );

        if (isFullscreen) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) {
                unawaited(_exitFullscreen());
              }
            },
            child: ColoredBox(color: Colors.black, child: stage),
          );
        }

        final isWide =
            constraints.maxWidth >= 840 && constraints.maxHeight >= 480;
        final bottomSurface = _buildBottomSurface(context, snapshot);

        if (isWide) {
          final panelWidth = (constraints.maxWidth * 0.36)
              .clamp(constraints.maxWidth * 0.28, constraints.maxWidth * 0.42)
              .toDouble();
          return PopScope(
            canPop: true,
            child: ColoredBox(
              color: visualTheme.background,
              child: Row(
                children: [
                  Expanded(
                    child: _buildStageFrame(
                      stage,
                      padding: stageCornerPadding.add(
                        const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      ),
                      safeBottom: true,
                    ),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: SafeArea(left: false, child: bottomSurface),
                  ),
                ],
              ),
            ),
          );
        }

        return PopScope(
          canPop: true,
          child: ColoredBox(
            color: visualTheme.background,
            child: Builder(
              builder: (context) {
                final stagePadding = stageCornerPadding.add(
                  const EdgeInsets.fromLTRB(10, 6, 10, 12),
                );
                final expandedStageHeight = _mobileStageExpandedHeight(
                  context,
                  constraints,
                  stagePadding,
                );
                final collapsedStageHeight =
                    MediaQuery.paddingOf(context).top + 64;
                final collapseDistance =
                    expandedStageHeight - collapsedStageHeight;
                final effectiveCollapseOffset =
                    snapshot.playbackState == VesperPlaybackState.playing
                    ? 0.0
                    : _mobileStageCollapseOffset;
                final collapseProgress = collapseDistance <= 0
                    ? 0.0
                    : (effectiveCollapseOffset / collapseDistance)
                          .clamp(0.0, 1.0)
                          .toDouble();
                final stageHeight = ui.lerpDouble(
                  expandedStageHeight,
                  collapsedStageHeight,
                  collapseProgress,
                )!;
                return Column(
                  children: [
                    SizedBox(
                      height: stageHeight,
                      child: _buildCollapsibleStageFrame(
                        stage,
                        controller: controller,
                        snapshot: snapshot,
                        padding: stagePadding,
                        progress: collapseProgress,
                      ),
                    ),
                    Expanded(child: bottomSurface),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  double _mobileStageExpandedHeight(
    BuildContext context,
    BoxConstraints constraints,
    EdgeInsetsGeometry padding,
  ) {
    final resolvedPadding = padding.resolve(Directionality.of(context));
    final availableWidth =
        constraints.maxWidth - resolvedPadding.left - resolvedPadding.right;
    final videoHeight =
        availableWidth.clamp(0.0, constraints.maxWidth) * 9 / 16;
    return MediaQuery.paddingOf(context).top +
        resolvedPadding.top +
        videoHeight +
        resolvedPadding.bottom;
  }

  Widget _buildCollapsibleStageFrame(
    Widget stage, {
    required VesperPlayerController controller,
    required VesperPlayerSnapshot snapshot,
    required EdgeInsetsGeometry padding,
    required double progress,
  }) {
    final stageOpacity = (1 - progress * 1.35).clamp(0.0, 1.0).toDouble();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: _handleMobileStagePointerMove,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (progress < 0.55)
            IgnorePointer(
              ignoring: progress > 0.42,
              child: Opacity(
                opacity: stageOpacity,
                child: _buildStageFrame(
                  stage,
                  padding: padding,
                  safeBottom: false,
                ),
              ),
            ),
          IgnorePointer(
            ignoring: progress < 0.08,
            child: Opacity(
              opacity: progress,
              child: CollapsedPlaybackBar(
                title: _playbackStateLabel(snapshot),
                isPlaying:
                    snapshot.playbackState == VesperPlaybackState.playing,
                onBack: () => Navigator.of(context).maybePop(),
                onHome: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                onPlayPause: () {
                  if (snapshot.playbackState == VesperPlaybackState.playing) {
                    unawaited(controller.pause());
                  } else {
                    unawaited(controller.play());
                  }
                },
                onMore: () => unawaited(
                  _openStageSheet(
                    controller,
                    vesper_ui.VesperPlayerStageSheet.menu,
                    true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
