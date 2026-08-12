part of 'media_playback_page.dart';

extension _MediaPlaybackPageTvLayout on _MediaPlaybackPageState {
  Widget _buildTvPlaybackLayout(
    BuildContext context,
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
  ) {
    final isPlaying = snapshot.playbackState == VesperPlaybackState.playing;
    _requestTvPlaybackFocusAfterFrame();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleTvBack();
        }
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.select):
              _TvPlaybackToggleBarIntent(),
          SingleActivator(LogicalKeyboardKey.enter):
              _TvPlaybackToggleBarIntent(),
          SingleActivator(LogicalKeyboardKey.contextMenu):
              _TvPlaybackMenuIntent(),
          SingleActivator(LogicalKeyboardKey.mediaPlayPause):
              _TvPlayPauseIntent(),
          SingleActivator(LogicalKeyboardKey.mediaPlay): _TvPlayPauseIntent(),
          SingleActivator(LogicalKeyboardKey.mediaPause): _TvPlayPauseIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _TvPlaybackLeftIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _TvPlaybackRightIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): _TvPlaybackUpIntent(),
          SingleActivator(LogicalKeyboardKey.arrowDown):
              _TvPlaybackDownIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _TvPlaybackToggleBarIntent:
                CallbackAction<_TvPlaybackToggleBarIntent>(
                  onInvoke: (_) {
                    _handleTvSelect();
                    return null;
                  },
                ),
            _TvPlaybackMenuIntent: CallbackAction<_TvPlaybackMenuIntent>(
              onInvoke: (_) {
                _showTvControls();
                return null;
              },
            ),
            _TvPlayPauseIntent: CallbackAction<_TvPlayPauseIntent>(
              onInvoke: (_) {
                _toggleTvPlayback(controller, snapshot);
                return null;
              },
            ),
            _TvPlaybackLeftIntent: CallbackAction<_TvPlaybackLeftIntent>(
              onInvoke: (_) {
                _handleTvDirectionalIntent(TraversalDirection.left);
                return null;
              },
            ),
            _TvPlaybackRightIntent: CallbackAction<_TvPlaybackRightIntent>(
              onInvoke: (_) {
                _handleTvDirectionalIntent(TraversalDirection.right);
                return null;
              },
            ),
            _TvPlaybackUpIntent: CallbackAction<_TvPlaybackUpIntent>(
              onInvoke: (_) {
                _handleTvDirectionalIntent(TraversalDirection.up);
                return null;
              },
            ),
            _TvPlaybackDownIntent: CallbackAction<_TvPlaybackDownIntent>(
              onInvoke: (_) {
                _handleTvDirectionalIntent(TraversalDirection.down);
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _tvPlaybackFocusNode,
            autofocus: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTvStageTap,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: VesperPlayerView(controller: controller),
                    ),
                    if (_viewModel.adapter.danmaku case final danmaku?)
                      Positioned.fill(
                        child: MediaDanmakuLayer(
                          provider: danmaku,
                          target: MediaPlaybackTarget(
                            detail: _viewModel.detail,
                            entry: _viewModel.selectedEntry,
                          ),
                          positionMs: snapshot.timeline.positionMs,
                          playbackState: snapshot.playbackState,
                          playbackRate: snapshot.playbackRate,
                        ),
                      ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _handleTvStageTap,
                      ),
                    ),
                    if (_tvControlBarVisible || _tvPanelOpen)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SignalBuilder(
                          builder: (context) => _buildTvControlBar(
                            controller,
                            snapshot,
                            isPlaying,
                          ),
                        ),
                      ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      top: 0,
                      bottom: 0,
                      right: _tvPanelOpen ? 0 : -420,
                      width: 420,
                      child: IgnorePointer(
                        ignoring: !_tvPanelOpen,
                        child: _tvPanelOpen
                            ? SignalBuilder(
                                builder: (context) =>
                                    _buildTvPanel(controller, snapshot),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleTvStageTap() {
    _tvPlaybackFocusNode.requestFocus();
    if (_tvPanelOpen) {
      return;
    }
    if (_tvControlBarVisible) {
      _hideTvControlsAndRestoreFocus();
    } else {
      _showTvControls();
    }
  }

  void _handleTvSelect() {
    if (_tvPanelOpen) {
      return;
    }
    if (!_tvControlBarVisible) {
      return;
    }
    _hideTvControlsAndRestoreFocus();
  }

  void _showTvControls() {
    if (_tvControlBarVisible) {
      return;
    }
    _mutate(() {
      _tvControlBarVisible = true;
    });
  }

  void _hideTvControlsAndRestoreFocus() {
    if (!_tvControlBarVisible) {
      _restoreTvPlaybackFocusAfterFrame();
      return;
    }
    _requestTvPlaybackFocus();
    _mutate(() {
      _tvControlBarVisible = false;
    });
    _restoreTvPlaybackFocusAfterFrame();
  }

  void _restoreTvPlaybackFocusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestTvPlaybackFocus();
    });
  }

  void _requestTvPlaybackFocus() {
    if (mounted && _tvPlaybackFocusNode.canRequestFocus) {
      _tvPlaybackFocusNode.requestFocus();
    }
  }

  void _toggleTvPlayback(
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
  ) {
    if (snapshot.isBuffering) {
      return;
    }
    if (snapshot.playbackState == VesperPlaybackState.playing) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  void _handleTvBack() {
    if (_tvBackDispatchPending) {
      return;
    }
    _tvBackDispatchPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tvBackDispatchPending = false;
    });
    if (_playbackModalRouteOpen) {
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        unawaited(Navigator.of(context, rootNavigator: true).maybePop());
      }
      return;
    }
    if (_tvPanelOpen) {
      _closeTvPanelAndRestoreFocus();
      return;
    }
    if (_tvControlBarVisible) {
      _hideTvControlsAndRestoreFocus();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    final fallbackHome = widget.tvFallbackHome;
    if (fallbackHome != null) {
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => fallbackHome),
      );
    }
  }

  void _handleTvDirectionalIntent(TraversalDirection direction) {
    if (_tvPanelOpen) {
      _moveTvPanelFocus(direction);
      return;
    }
    if (_tvControlBarVisible || _tvPanelOpen) {
      if (!_moveTvFocus(direction) &&
          (direction == TraversalDirection.up ||
              direction == TraversalDirection.down)) {
        _showTvControls();
      }
      return;
    }
    if (direction == TraversalDirection.left) {
      return;
    }
    if (direction == TraversalDirection.right) {
      return;
    }
    _showTvControls();
  }

  bool _moveTvFocus(TraversalDirection direction) {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final moved = primaryFocus == null
        ? false
        : moveTvFocusSpatially(primaryFocus, direction);
    if (moved) {
      revealFocusedTvControl(direction);
    }
    return moved;
  }

  bool _moveTvPanelFocus(TraversalDirection direction) {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final moved = primaryFocus == null
        ? false
        : moveTvFocusSpatially(
            primaryFocus,
            direction,
            allowedAreas: {TvFocusArea.playbackPanel},
          );
    if (moved) {
      revealFocusedTvControl(direction);
    }
    return moved;
  }

  void _seekTvBy(
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
    int deltaMs,
  ) {
    final durationMs = snapshot.timeline.durationMs ?? 0;
    if (durationMs <= 0) {
      return;
    }
    final nextMs = (snapshot.timeline.positionMs + deltaMs).clamp(
      0,
      durationMs,
    );
    // 经 VM 入口：用户 seek 使在途历史续播失效。
    unawaited(_viewModel.seekToRatio(nextMs / durationMs));
  }

  void _openTvPanel(TvPlaybackPanelType panel) {
    final willOpen = _tvPanel != panel;
    _mutate(() {
      _tvControlBarVisible = true;
      _tvPanel = willOpen ? panel : TvPlaybackPanelType.none;
      _lastOpenedTvPanel = willOpen ? panel : null;
    });
    if (!willOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tvPanelButtonFocusNodes[panel]?.requestFocus();
      });
    }
  }

  List<TvPanelOption> _tvSubtitlePanelOptions(VesperPlayerSnapshot snapshot) {
    final tracks = _subtitleTracks(snapshot);
    if (tracks.isEmpty ||
        !snapshot.capabilities.supportsSubtitleTrackSelection) {
      return const <TvPanelOption>[];
    }
    final selection = _subtitleSelection(snapshot);
    final selectedTrackId = selection.mode == VesperTrackSelectionMode.track
        ? selection.trackId
        : null;
    return <TvPanelOption>[
      TvPanelOption(
        label: '关闭',
        selected: selection.mode == VesperTrackSelectionMode.disabled,
        onTap: () {
          unawaited(_selectSubtitle(const VesperTrackSelection.disabled()));
        },
      ),
      TvPanelOption(
        label: '自动',
        selected: selection.mode == VesperTrackSelectionMode.auto,
        onTap: () {
          unawaited(_selectSubtitle(const VesperTrackSelection.auto()));
        },
      ),
      for (final track in tracks)
        TvPanelOption(
          label: _subtitleTrackLabel(track),
          selected: selectedTrackId == track.id,
          onTap: () {
            unawaited(_selectSubtitle(VesperTrackSelection.track(track.id)));
          },
        ),
    ];
  }

  String? _tvSubtitlePanelMessage(VesperPlayerSnapshot snapshot) {
    if (!snapshot.capabilities.supportsSubtitleTrackSelection) {
      return '当前播放内核不支持字幕切换。';
    }
    if (_subtitleTracks(snapshot).isNotEmpty) {
      return null;
    }
    final advertised =
        _resolvedPlayback?.subtitleTracks ?? const <ResolvedSubtitleTrack>[];
    final subtitleError =
        snapshot.subtitleState.catalogError?.message ??
        _resolvedPlayback?.subtitleError;
    if (subtitleError != null) {
      return subtitleError;
    }
    final isLoading =
        snapshot.subtitleState.catalogState ==
        VesperSubtitleCatalogState.loading;
    return advertised.isEmpty && !isLoading ? '当前视频没有可用字幕。' : '字幕正在准备，请稍后重试。';
  }

  Widget _buildTvPanel(
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
  ) {
    final qualityOptions = _viewModel.qualitySelectionOptions(snapshot);
    final currentOptionId = _viewModel.selectedQualityOptionId;
    final rates = _playbackRates(snapshot);
    final subtitleOptions = _tvSubtitlePanelOptions(snapshot);
    final subtitleMessage = _tvSubtitlePanelMessage(snapshot);
    final pages = _viewModel.detail.pages;
    final isPgc = _viewModel.detail.isEpisodic;
    final label = switch (_tvPanel) {
      TvPlaybackPanelType.quality => '清晰度',
      TvPlaybackPanelType.speed => '倍速',
      TvPlaybackPanelType.subtitles => '字幕',
      TvPlaybackPanelType.pages => isPgc ? '选集' : '分P',
      TvPlaybackPanelType.none => '',
    };
    final subtitle = switch (_tvPanel) {
      TvPlaybackPanelType.quality => '确认后立即切换当前播放清晰度',
      TvPlaybackPanelType.speed => '确认后立即改变播放速度',
      TvPlaybackPanelType.subtitles => '字幕语言与显示方式',
      TvPlaybackPanelType.pages =>
        isPgc ? '上下选择剧集，确认播放选中的一集' : '上下选择分 P，确认播放选中的分段',
      TvPlaybackPanelType.none => '',
    };
    final optionsList = switch (_tvPanel) {
      TvPlaybackPanelType.quality => <TvPanelOption>[
        TvPanelOption(
          label: '自动',
          selected: currentOptionId == null,
          onTap: () {
            unawaited(_selectQualityOption(null));
          },
        ),
        for (final option in qualityOptions)
          TvPanelOption(
            label: option.label,
            subtitle: _viewModel.qualitySelectionSupportingText(option),
            selected: currentOptionId == option.id,
            enabled: option.canSelect,
            onTap: () {
              unawaited(_selectQualityOption(option.id));
            },
          ),
      ],
      TvPlaybackPanelType.speed =>
        rates
            .map(
              (rate) => TvPanelOption(
                label: '${rate}x',
                selected: (snapshot.playbackRate - rate).abs() < 0.01,
                onTap: () {
                  unawaited(_setPlaybackRate(rate));
                },
              ),
            )
            .toList(),
      TvPlaybackPanelType.subtitles => subtitleOptions,
      TvPlaybackPanelType.pages =>
        pages
            .map(
              (page) => TvPanelOption(
                label: isPgc ? '第 ${page.pageNumber} 集' : 'P${page.pageNumber}',
                subtitle: page.title,
                selected: _selectedEntry.entryId == page.entryId,
                onTap: () {
                  unawaited(_switchEntry(page));
                },
              ),
            )
            .toList(),
      TvPlaybackPanelType.none => const <TvPanelOption>[],
    };

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x00101012), Color(0xF2101012)],
        ),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(22),
          ),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              width: 390,
              height: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              decoration: const BoxDecoration(
                color: Color(0xD91C1C1E),
                border: Border(
                  left: BorderSide(color: Color(0x22FFFFFF), width: 0.5),
                ),
              ),
              child: SafeArea(
                left: false,
                child: TvPanelDrawer(
                  key: ValueKey<TvPlaybackPanelType>(_tvPanel),
                  panelKey: _tvPanel == TvPlaybackPanelType.quality
                      ? '${_tvPanel.name}:${snapshot.trackCatalog.catalogRevision}'
                      : _tvPanel.name,
                  label: label,
                  subtitle: subtitle,
                  options: optionsList,
                  emptyMessage: _tvPanel == TvPlaybackPanelType.subtitles
                      ? subtitleMessage
                      : null,
                  onClose: _closeTvPanelAndRestoreFocus,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _closeTvPanelAndRestoreFocus() {
    final panel = _lastOpenedTvPanel;
    _mutate(() {
      _tvPanel = TvPlaybackPanelType.none;
      _lastOpenedTvPanel = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final panelButton = panel == null
          ? null
          : _tvPanelButtonFocusNodes[panel];
      if (_tvControlBarVisible &&
          panelButton?.canRequestFocus == true &&
          panelButton?.context != null) {
        panelButton!.requestFocus();
        return;
      }
      _tvPlaybackFocusNode.requestFocus();
    });
  }

  Widget _buildTvControlBar(
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
    bool isPlaying,
  ) {
    final positionMs = snapshot.timeline.positionMs;
    final durationMs = snapshot.timeline.durationMs ?? 0;
    final ratio = snapshot.timeline.displayedRatio ?? 0.0;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x44000000), Color(0xEE000000)],
            ),
            border: const Border(
              top: BorderSide(color: Color(0x18FFFFFF), width: 0.5),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(40, 20, 40, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 28,
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        _formatMilliseconds(positionMs),
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: const SliderThemeData(
                          trackHeight: 4,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: Color(0xCCFFFFFF),
                          inactiveTrackColor: Color(0x33FFFFFF),
                          thumbColor: Color(0xFFFFFFFF),
                          overlayColor: Color(0x22FFFFFF),
                        ),
                        child: Slider(
                          value: ratio.clamp(0.0, 1.0),
                          onChanged: (value) {
                            unawaited(_viewModel.seekToRatio(value));
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        _formatMilliseconds(durationMs),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 20),
                  TvBarButton(
                    label: isPlaying ? '暂停' : '播放',
                    icon: isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    autofocus: !_tvPanelOpen,
                    onTap: () {
                      if (isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    },
                  ),
                  const SizedBox(width: 14),
                  TvBarButton(
                    label: '快退 10s',
                    icon: Icons.replay_10_rounded,
                    onTap: () {
                      final newPosMs = (positionMs - 10000).clamp(
                        0,
                        durationMs,
                      );
                      unawaited(
                        _viewModel.seekToRatio(
                          durationMs > 0 ? newPosMs / durationMs : 0,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 14),
                  TvBarButton(
                    label: '快进 10s',
                    icon: Icons.forward_10_rounded,
                    onTap: () {
                      final newPosMs = (positionMs + 10000).clamp(
                        0,
                        durationMs,
                      );
                      unawaited(
                        _viewModel.seekToRatio(
                          durationMs > 0 ? newPosMs / durationMs : 0,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 14),
                  TvBarButton(
                    label: '清晰度',
                    icon: Icons.hd_rounded,
                    focusNode: _tvPanelButtonNode(TvPlaybackPanelType.quality),
                    onTap: () => _openTvPanel(TvPlaybackPanelType.quality),
                  ),
                  const SizedBox(width: 14),
                  TvBarButton(
                    label: '倍速',
                    icon: Icons.speed_rounded,
                    focusNode: _tvPanelButtonNode(TvPlaybackPanelType.speed),
                    onTap: () => _openTvPanel(TvPlaybackPanelType.speed),
                  ),
                  const SizedBox(width: 14),
                  TvBarButton(
                    label: '字幕',
                    icon: Icons.subtitles_outlined,
                    focusNode: _tvPanelButtonNode(
                      TvPlaybackPanelType.subtitles,
                    ),
                    onTap: () => _openTvPanel(TvPlaybackPanelType.subtitles),
                  ),
                  if (_viewModel.detail.pages.length > 1) ...[
                    const SizedBox(width: 14),
                    TvBarButton(
                      label: '分P',
                      icon: Icons.playlist_play_rounded,
                      focusNode: _tvPanelButtonNode(TvPlaybackPanelType.pages),
                      onTap: () => _openTvPanel(TvPlaybackPanelType.pages),
                    ),
                  ],
                  for (final extra in widget.tvControlBarExtras) ...[
                    const SizedBox(width: 14),
                    extra,
                  ],
                ],
              ),
              SizedBox(
                height: MediaQuery.paddingOf(context).bottom > 0 ? 8 : 0,
              ),
            ],
          ),
        ),
      ),
    );
  }

  FocusNode _tvPanelButtonNode(TvPlaybackPanelType panel) {
    return _tvPanelButtonFocusNodes.putIfAbsent(
      panel,
      () => FocusNode(debugLabel: 'tv_${panel.name}_button'),
    );
  }

  String _formatMilliseconds(int ms) {
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
