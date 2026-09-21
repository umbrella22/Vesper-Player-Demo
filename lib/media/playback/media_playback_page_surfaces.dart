part of 'media_playback_page.dart';

enum _PlaybackMenuAction { listen, projection, diagnostics }

extension _MediaPlaybackPageSurfaces on _MediaPlaybackPageState {
  Widget _buildStage({
    required VesperPlayerController controller,
    required VesperPlayerSnapshot snapshot,
    required bool isFullscreen,
    required bool usesCompactControls,
  }) {
    _maybePollPictureInPictureAvailability(snapshot);
    final danmakuProvider = _viewModel.adapter.danmaku;
    return MediaVideoContent(
      key: ObjectKey(controller),
      active:
          !_viewModel.isSourceTransitioning &&
          !_viewModel.isAudioOnlyPlaybackActive &&
          !_pictureInPicturePresentation.value,
      overlayBuilder: danmakuProvider == null
          ? null
          : (interaction, visible) => SignalBuilder(
              builder: (context) => MediaDanmakuLayer(
                provider: danmakuProvider,
                target: MediaPlaybackTarget(
                  detail: _viewModel.detail,
                  entry: _viewModel.selectedEntry,
                ),
                positionMs: snapshot.timeline.positionMs,
                playbackState: snapshot.playbackState,
                playbackRate: snapshot.playbackRate,
                settings: visible
                    ? _danmakuSettings
                    : _danmakuSettings.copyWith(enabled: false),
                interactionController: interaction,
                sendController: widget.danmakuSendController,
                onEventSelected: widget.onDanmakuEventSelected,
                onMetricsChanged:
                    _performanceDiagnosticsController
                        .overlayReportingActive
                        .value
                    ? _performanceDiagnosticsController.updateOverlayMetrics
                    : null,
              ),
            ),
      builder: (onGeometryChanged, contentOverlay, onContentTap) =>
          vesper_ui.VesperPlayerStage(
            controller: controller,
            snapshot: snapshot,
            controlLayout: usesCompactControls
                ? vesper_ui.VesperStageControlLayout.compact
                : vesper_ui.VesperStageControlLayout.expanded,
            isFullscreen: isFullscreen,
            sheetOpen: _playbackModalRouteOpen,
            deviceControls: widget.deviceControls,
            contentOverlay: contentOverlay,
            onGeometryChanged: onGeometryChanged,
            onContentTap: onContentTap,
            expandedControlBarLeading: usesCompactControls
                ? null
                : _buildExpandedControlBarLeading(controller, snapshot),
            onNavigateBack: () {
              if (isFullscreen) {
                unawaited(_exitFullscreen());
              } else {
                unawaited(Navigator.of(context).maybePop());
              }
            },
            navigateBackSemanticLabel: isFullscreen ? '退出全屏' : '返回上一页',
            keepControlsVisible: _playbackModalRouteOpen,
            pictureInPicturePresentation: _pictureInPicturePresentation.value,
            topBarPrimaryAction: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (usesCompactControls && danmakuProvider != null) ...[
                  SignalBuilder(
                    builder: (context) => vesper_ui.VesperStageIconButton(
                      key: const ValueKey<String>('toggle-danmaku'),
                      icon: Icon(
                        _danmakuEnabled
                            ? AppIcons.chat3Fill
                            : AppIcons.chat3Line,
                      ),
                      label: _danmakuEnabled ? '关闭弹幕' : '开启弹幕',
                      variant: vesper_ui.VesperStageButtonVariant.toolbar,
                      onPressed: _toggleDanmaku,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                if (!usesCompactControls &&
                    mediaPerformanceDiagnosticsAvailable) ...[
                  vesper_ui.VesperStageIconButton(
                    key: const ValueKey<String>('open-performance-diagnostics'),
                    icon: const Icon(AppIcons.heartPulseLine),
                    label: '性能诊断',
                    variant: vesper_ui.VesperStageButtonVariant.toolbar,
                    onPressed: () =>
                        unawaited(_openPerformanceDiagnosticsSurface()),
                  ),
                  const SizedBox(width: 4),
                ],
                if (!usesCompactControls) ...[
                  if (_buildStageProjectionAction(controller)
                      case final projectionAction?) ...[
                    const SizedBox(width: 4),
                    projectionAction,
                  ],
                ],
                if (_pictureInPictureSupported) ...[
                  const SizedBox(width: 4),
                  vesper_ui.VesperStageIconButton(
                    key: const ValueKey<String>('enter-picture-in-picture'),
                    icon: const Icon(AppIcons.pictureInPictureLine),
                    label: '小窗',
                    variant: vesper_ui.VesperStageButtonVariant.toolbar,
                    onPressed: () => unawaited(_requestPictureInPicture()),
                  ),
                ],
              ],
            ),
            strings: const vesper_ui.VesperPlayerStageStrings.zhHans(),
            skin: appPlayerStageSkin,
            onOpenSheet: (sheet) => unawaited(
              _openStageSheet(controller, sheet, usesCompactControls),
            ),
            onToggleFullscreen: () => unawaited(_toggleFullscreen()),
          ),
    );
  }

  Widget? _buildExpandedControlBarLeading(
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
  ) {
    final hasDanmaku = _viewModel.adapter.danmaku != null;
    final hasDanmakuSettings =
        hasDanmaku && widget.danmakuSettingsSurface != null;
    final hasSubtitleSettings =
        snapshot.capabilities.supportsSubtitleTrackSelection;
    if (!hasDanmaku && !hasSubtitleSettings) {
      return null;
    }
    return Row(
      key: const ValueKey<String>('landscape-control-bar-leading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasDanmaku) ...[
          const SizedBox(width: 4),
          SignalBuilder(
            builder: (context) => vesper_ui.VesperStageIconButton(
              key: const ValueKey<String>('toggle-danmaku'),
              icon: Icon(
                _danmakuEnabled
                    ? AppIcons.chat3Fill
                    : AppIcons.chat3Line,
              ),
              label: _danmakuEnabled ? '关闭弹幕' : '开启弹幕',
              variant: vesper_ui.VesperStageButtonVariant.expanded,
              onPressed: _toggleDanmaku,
            ),
          ),
        ],
        if (hasDanmakuSettings) ...[
          const SizedBox(width: 2),
          vesper_ui.VesperStageIconButton(
            key: const ValueKey<String>('open-danmaku-settings'),
            icon: const Icon(AppIcons.equalizer2Line),
            label: '弹幕设置',
            variant: vesper_ui.VesperStageButtonVariant.expanded,
            onPressed: () => unawaited(_openDanmakuSettingsSurface()),
          ),
        ],
        if (hasSubtitleSettings) ...[
          const SizedBox(width: 2),
          vesper_ui.VesperStageIconButton(
            key: const ValueKey<String>('open-subtitle-settings'),
            icon: const Icon(AppIcons.closedCaptioningFill),
            label: '字幕设置',
            variant: vesper_ui.VesperStageButtonVariant.expanded,
            onPressed: () => unawaited(
              _openStageSheet(
                controller,
                vesper_ui.VesperPlayerStageSheet.subtitle,
                false,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStageFrame(
    Widget stage, {
    required EdgeInsetsGeometry padding,
    required bool safeBottom,
  }) {
    return ColoredBox(
      color: Colors.black,
      // Display corner radii describe the screen shape, not extra safe insets.
      child: SafeArea(
        bottom: safeBottom,
        child: Padding(padding: padding, child: stage),
      ),
    );
  }

  Widget _buildBottomSurface(
    BuildContext context,
    VesperPlayerSnapshot snapshot,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visualTheme = AppVisualTheme.of(context);
        final horizontalPadding = constraints.maxWidth >= 540 ? 34.0 : 16.0;
        // 订阅 selectedEntry：切换分 P 后评论能力可能变化（nullable
        // builder 接收当前 target），TabController 需随 entry 重建。
        // _syncInfoTabController 内的信号读取必须发生在 SignalBuilder
        // 的 builder 调用栈内才会被追踪。
        return SignalBuilder(
          builder: (context) {
            _syncInfoTabController(context);
            final errorMessage = _viewModel.playbackErrorMessage(snapshot);
            final engagement = widget.binding.buildEngagement();
            return DecoratedBox(
              key: const ValueKey<String>('playback-bottom-surface'),
              decoration: BoxDecoration(
                color: visualTheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: visualTheme.shadow,
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (engagement != null &&
                        engagement.actions.isNotEmpty &&
                        engagement.placement == MediaEngagementPlacement.shell)
                      Padding(
                        key: const ValueKey<String>(
                          'playback-shell-engagement-bar',
                        ),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: MediaEngagementBar(
                          actions: engagement.actions,
                          onMessage: _showEngagementMessage,
                        ),
                      ),
                    if (errorMessage != null) ...[
                      PlaybackInlineError(
                        title: '播放器错误',
                        message: errorMessage,
                        actionLabel: '重新解析',
                        onPressed: _reloadCurrentPage,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_contentTabCount(context) > 0) ...[
                      PlaybackContextTabs(
                        controller: _infoTabController!,
                        introLabel: _contentSurfaces?.introTabLabel ?? '简介',
                        commentsLabel: _commentsTabLabel(context),
                        trailing:
                            widget.danmakuComposer?.call(
                              () =>
                                  _viewModel
                                      .controller
                                      ?.snapshot
                                      .timeline
                                      .positionMs ??
                                  snapshot.timeline.positionMs,
                            ) ??
                            widget.contentTabsTrailing,
                      ),
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: SignalBuilder(
                            builder: (context) =>
                                _buildContentTabView(snapshot),
                          ),
                        ),
                      ),
                    ] else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEngagementMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildContentTabView(VesperPlayerSnapshot snapshot) {
    final surfaces = _contentSurfaces;
    if (surfaces == null) {
      return const SizedBox.shrink();
    }
    final target = MediaPlaybackTarget(
      detail: _viewModel.detail,
      entry: _viewModel.selectedEntry,
    );
    return TabBarView(
      controller: _infoTabController!,
      physics: const BouncingScrollPhysics(),
      children: [
        surfaces.buildIntroSurface(context, target, _contentHost.surfaceHost),
        if (_contentTabCount(context) == 2)
          surfaces.buildCommentsSurface(context, target) ??
              const SizedBox.shrink(),
      ],
    );
  }

  /// 评论 tab 文案：平台 label + 通用回复计数（如 "评论 78"）。
  /// 平台未声明评论面板（label 或 builder 为 null）时为 null
  /// （不渲染评论 tab）。
  String? _commentsTabLabel(BuildContext context) {
    if (!_computeCommentsAvailable(context)) {
      return null;
    }
    final label = _contentSurfaces?.commentsTabLabel;
    if (label == null) {
      return null;
    }
    final count = _viewModel.detail.replyCountLabel;
    return count == null || count.isEmpty ? label : '$label $count';
  }

  Future<void> _openStageSheet(
    VesperPlayerController controller,
    vesper_ui.VesperPlayerStageSheet _,
    bool isPortrait,
  ) async {
    if (!mounted) {
      return;
    }
    _mutate(() {
      _settingsSurfaceOpen = true;
    });
    _PlaybackMenuAction? action;
    try {
      await _showSettingsSurface(
        controller,
        isPortrait: isPortrait,
        onActionSelected: (value) => action = value,
      );
    } finally {
      if (mounted) {
        _mutate(() {
          _settingsSurfaceOpen = false;
        });
      }
    }
    if (!mounted) return;
    switch (action) {
      case _PlaybackMenuAction.listen:
        await _enterListenMode();
      case _PlaybackMenuAction.projection:
        await _openStageProjectionPicker();
      case _PlaybackMenuAction.diagnostics:
        await _openPerformanceDiagnosticsSurface();
      case null:
        break;
    }
  }

  Future<void> _openDanmakuSettingsSurface() async {
    final settings = widget.danmakuSettingsSurface;
    if (!mounted || settings == null) {
      return;
    }
    _mutate(() {
      _danmakuSettingsSurfaceOpen = true;
    });
    try {
      await showMediaPlaybackSideDrawer<void>(
        context,
        side: MediaPlaybackDrawerSide.trailing,
        surfaceKey: const ValueKey<String>('danmaku-settings-drawer'),
        builder: (_) => settings,
      );
    } finally {
      if (mounted) {
        _mutate(() {
          _danmakuSettingsSurfaceOpen = false;
        });
      }
    }
  }

  Widget? _buildStageProjectionAction(VesperPlayerController controller) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isAndroid) {
      // DLNA 入口按适配器能力声明显隐：未声明 dlnaConfig 的平台不显示。
      if (_viewModel.adapter.dlnaConfig == null) {
        return null;
      }
      return StageDlnaProjectionButton(
        state: _dlnaState,
        onTap: () => unawaited(_openStageProjectionPicker()),
      );
    }
    if (isIos) {
      return vesper_ui.VesperAirPlayRouteIconButton(
        controller: controller,
        tintColor: Colors.white,
        activeTintColor: AppVisualTokens.primaryBlue,
        size: 38,
      );
    }
    return null;
  }

  Future<void> _openStageProjectionPicker() async {
    if (_viewModel.adapter.dlnaConfig == null) {
      return;
    }
    if (_castingSurfaceOpen || _dlnaPickerOpen) {
      return;
    }
    if (!context.mounted) return;

    _setCastingSurfaceOpen(true);
    _ProjectionTarget? target;
    try {
      target = await showMediaGlassSheet<_ProjectionTarget>(
        context: context,
        maxContentHeightFactor: 0.5,
        builder: (sheetContext) {
          return ProjectionPickerContent(
            onDlna: () =>
                Navigator.of(sheetContext).pop(_ProjectionTarget.dlna),
          );
        },
      );
    } finally {
      _setCastingSurfaceOpen(false);
    }

    if (!mounted || target == null) {
      return;
    }
    switch (target) {
      case _ProjectionTarget.dlna:
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (mounted) {
          await _openDlnaPicker();
        }
    }
  }

  Future<void> _openDlnaPicker() async {
    if (_dlnaPickerOpen) {
      return;
    }

    final isConnected = _dlnaState == MediaDlnaState.connected;
    if (isConnected) {
      final message = await _dlnaManager.disconnect();
      if (message != null && mounted) {
        _showMessage(message);
      }
      return;
    }

    if (!context.mounted) return;
    _setDlnaPickerOpen(true);
    try {
      await showMediaGlassSheet<void>(
        context: context,
        appearance: MediaGlassSheetAppearance.readable,
        maxContentHeightFactor: 0.7,
        builder: (sheetContext) {
          return DlnaPickerContent(
            manager: _dlnaManager,
            onLoadMedia: _viewModel.loadCurrentEntryToDlna,
            onClose: () => Navigator.of(sheetContext).pop(),
            onMessage: _showMessage,
          );
        },
      );
    } finally {
      _setDlnaPickerOpen(false);
      if (_dlnaState == MediaDlnaState.discovering ||
          _dlnaState == MediaDlnaState.error) {
        unawaited(_dlnaManager.stopDiscovery());
      }
    }
  }

  String _subtitleTrackLabel(VesperMediaTrack track) {
    final label = track.label?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    final language = track.language?.trim();
    return language == null || language.isEmpty ? '字幕' : language;
  }

  Future<void> _showSettingsSurface(
    VesperPlayerController controller, {
    required bool isPortrait,
    ValueChanged<_PlaybackMenuAction>? onActionSelected,
  }) {
    return showMediaPlaybackSettingsSurface(
      context,
      isPortrait: isPortrait,
      controller: controller,
      contentBuilder: (context, snapshot) => _buildTuningPanel(
        context,
        controller,
        snapshot,
        onMenuAction: onActionSelected == null
            ? null
            : (action) {
                onActionSelected(action);
                Navigator.of(context).pop();
              },
      ),
    );
  }

  Widget _buildTuningPanel(
    BuildContext context,
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot, {
    ValueChanged<_PlaybackMenuAction>? onMenuAction,
  }) {
    final timeline = snapshot.timeline;
    final declaredQualityOptions = _viewModel.availableQualityOptions();
    final qualityOptions = _viewModel.qualitySelectionOptions(snapshot);
    final selectedId = _viewModel.selectedQualityOptionId;
    final selectedCodec = _viewModel.selectedCodecIdentity;
    final qualityPolicy = _viewModel.adapter.qualityPolicy;
    final codecLabelFor = qualityPolicy.codecLabelFor;
    final codecIdentityFor = qualityPolicy.codecStrategyIdentityFor;
    final codecIdentityLabel = qualityPolicy.codecIdentityLabelFor;
    final codecOptions = _viewModel.supportsCodecSelection
        ? () {
            // 按策略身份归组（同组轨道合并为一个选项）；选项 label 用
            // 身份的规范标签（稳定，不随轨道顺序变化——如 Dolby Vision
            // 归入 HEVC 后整组显示 "HEVC"）。
            final labelsById = <String, String>{};
            for (final option in declaredQualityOptions) {
              if (selectedId != null && option.id != selectedId) {
                continue;
              }
              for (final track in option.tracks) {
                final label = codecLabelFor?.call(track);
                if (label == null) {
                  continue;
                }
                final id = codecIdentityFor?.call(track) ?? label;
                labelsById[id] ??= codecIdentityLabel?.call(id) ?? label;
              }
            }
            return labelsById.entries
                .map((entry) {
                  final availability = _viewModel.codecSelectionAvailability(
                    snapshot,
                    entry.key,
                    optionId: selectedId,
                  );
                  return TuningCodecOption(
                    id: entry.key,
                    label: entry.value,
                    enabled:
                        availability != MediaQualityAvailability.unavailable,
                    supportingText: _viewModel.codecSelectionSupportingText(
                      snapshot,
                      entry.key,
                      optionId: selectedId,
                    ),
                  );
                })
                .toList(growable: false);
          }()
        : const <TuningCodecOption>[];
    final advertisedEmpty =
        (_resolvedPlayback?.subtitleTracks ?? const <ResolvedSubtitleTrack>[])
            .isEmpty;
    final subtitleError =
        snapshot.subtitleState.catalogError?.message ??
        _resolvedPlayback?.subtitleError;
    final subtitleLoading =
        snapshot.subtitleState.catalogState ==
        VesperSubtitleCatalogState.loading;
    return MediaPlaybackTuningPanel(
      quickActions: onMenuAction == null
          ? null
          : _buildPlaybackMenuActions(context, controller, onMenuAction),
      snapshot: snapshot,
      qualityOptions: qualityOptions,
      qualitySupportingTextFor: _viewModel.qualitySelectionSupportingText,
      selectedQualityOptionId: selectedId,
      qualityHdrBadgeFor: _viewModel.tuningHdrBadgeFor,
      hdrLabel: _viewModel.hdrDiagnosticsLabel,
      codecOptions: codecOptions,
      selectedCodecIdentity: selectedCodec,
      playbackRates: _viewModel.playbackRates(snapshot),
      subtitleTracks: _viewModel.subtitleTracks(snapshot),
      subtitleSelection: _viewModel.subtitleSelection(snapshot),
      subtitleSelectionEnabled:
          snapshot.capabilities.supportsSubtitleTrackSelection,
      subtitleEmptyMessage:
          subtitleError ??
          (advertisedEmpty && !subtitleLoading
              ? '当前视频没有可用字幕。'
              : '字幕正在准备，请稍后重试。'),
      playbackStateLabel: _viewModel.playbackStateLabel(snapshot),
      timelineLabel:
          '${mediaFormatDurationSeconds(timeline.positionMs ~/ 1000)} / '
          '${mediaFormatDurationSeconds((timeline.durationMs ?? 0) ~/ 1000)}',
      transportLabel: _resolvedPlayback?.transportLabel,
      resolvedUri: _resolvedPlayback?.uri,
      debugPath: _resolvedPlayback?.debugPath,
      cacheEntry: widget.tuningCacheEntry,
      onSelectQuality: (optionId) {
        unawaited(_selectQualityOption(optionId));
      },
      onSelectCodec: (identity) {
        unawaited(_selectCodecIdentity(identity));
      },
      onSetRate: (rate) => unawaited(_setPlaybackRate(rate)),
      onSelectSubtitle: (selection) => unawaited(_selectSubtitle(selection)),
    );
  }

  Widget _buildPlaybackMenuActions(
    BuildContext context,
    VesperPlayerController controller,
    ValueChanged<_PlaybackMenuAction> onSelected,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!_viewModel.isFullscreen)
          OutlinedButton.icon(
            key: const ValueKey<String>('enter-listen-mode'),
            onPressed: () => onSelected(_PlaybackMenuAction.listen),
            icon: const Icon(AppIcons.headphoneLine),
            label: const Text('听视频'),
          ),
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            _viewModel.adapter.dlnaConfig != null)
          OutlinedButton.icon(
            key: const ValueKey<String>('settings-projection'),
            onPressed: () => onSelected(_PlaybackMenuAction.projection),
            icon: const Icon(AppIcons.castLine),
            label: const Text('投屏'),
          ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          Semantics(
            label: 'AirPlay 投屏',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                vesper_ui.VesperAirPlayRouteIconButton(
                  controller: controller,
                  tintColor: AppVisualTheme.of(context).textPrimary,
                  activeTintColor: AppVisualTokens.primaryBlue,
                  size: 48,
                ),
                const Text('AirPlay'),
              ],
            ),
          ),
        if (mediaPerformanceDiagnosticsAvailable)
          OutlinedButton.icon(
            key: const ValueKey<String>('settings-performance-diagnostics'),
            onPressed: () => onSelected(_PlaybackMenuAction.diagnostics),
            icon: const Icon(AppIcons.heartPulseLine),
            label: const Text('性能诊断'),
          ),
      ],
    );
  }
}
