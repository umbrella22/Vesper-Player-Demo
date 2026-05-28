import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';
import 'package:vesper_player_ui/vesper_player_ui.dart' as vesper_ui;

import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_device_controls.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:bilibili_player/bili/common/services/bili_text.dart';
import 'package:bilibili_player/bili/tv_mode/pages/bili_tv_home_page.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_focusable.dart';
import 'package:bilibili_player/bili/common/view_models/bili_external_playback_manager.dart';
import 'package:bilibili_player/bili/common/view_models/bili_playback_view_model.dart';
import 'package:bilibili_player/bili/common/widgets/bili_cache_download_panel.dart';
import 'package:bilibili_player/download/services/offline_download_controller.dart';

part 'bili_playback_panels.dart';
part 'bili_playback_settings.dart';
part 'bili_playback_dlna.dart';
part 'bili_playback_tuning.dart';
part 'bili_playback_widgets.dart';

const _appSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

const _playbackSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

const _playbackPortraitOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
];

const _playbackLandscapeOrientations = <DeviceOrientation>[
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

const _appDefaultOrientations = <DeviceOrientation>[];

enum BiliPlaybackPresentationMode { phone, tv }

enum TvPlaybackPanelType { none, quality, speed, pages }

class BiliPlaybackPage extends StatefulWidget {
  const BiliPlaybackPage({
    super.key,
    required this.detail,
    required this.initialPage,
    required this.client,
    required this.historyStore,
    this.offlineController,
    this.initialResolvedPlayback,
    this.presentationMode = BiliPlaybackPresentationMode.phone,
  });

  final BiliVideoDetail detail;
  final BiliVideoPageEntry initialPage;
  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliOfflineDownloadController? offlineController;
  final BiliResolvedPlayback? initialResolvedPlayback;
  final BiliPlaybackPresentationMode presentationMode;

  @override
  State<BiliPlaybackPage> createState() => _BiliPlaybackPageState();
}

class _BiliPlaybackPageState extends State<BiliPlaybackPage> {
  late final BiliPlaybackViewModel _viewModel;
  bool _settingsSurfaceOpen = false;
  bool _castingSurfaceOpen = false;
  bool _dlnaPickerOpen = false;
  int _presentationGeneration = 0;
  final _BiliStageDeviceControls _stageDeviceControls =
      const _BiliStageDeviceControls();
  bool _tvControlBarVisible = false;
  TvPlaybackPanelType _tvPanel = TvPlaybackPanelType.none;
  final FocusNode _tvPlaybackFocusNode = FocusNode(debugLabel: 'tv_playback');
  final Map<TvPlaybackPanelType, FocusNode> _tvPanelButtonFocusNodes =
      <TvPlaybackPanelType, FocusNode>{};
  TvPlaybackPanelType? _lastOpenedTvPanel;
  bool _tvPlaybackInitialFocusRequested = false;

  bool get _isTvMode =>
      widget.presentationMode == BiliPlaybackPresentationMode.tv;

  bool get _tvPanelOpen => _tvPanel != TvPlaybackPanelType.none;

  @override
  void initState() {
    super.initState();
    _viewModel = BiliPlaybackViewModel(
      detail: widget.detail,
      initialPage: widget.initialPage,
      client: widget.client,
      historyStore: widget.historyStore,
      offlineController: widget.offlineController,
      initialResolvedPlayback: widget.initialResolvedPlayback,
    )..addListener(_handleViewModelMessage);
    HardwareKeyboard.instance.addHandler(_handleTvHardwareKeyEvent);
    unawaited(_enterPlaybackPresentation());
  }

  @override
  void didUpdateWidget(BiliPlaybackPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presentationMode != widget.presentationMode) {
      _tvPlaybackInitialFocusRequested = false;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleTvHardwareKeyEvent);
    _tvPlaybackFocusNode.dispose();
    for (final node in _tvPanelButtonFocusNodes.values) {
      node.dispose();
    }
    _viewModel
      ..removeListener(_handleViewModelMessage)
      ..dispose();
    unawaited(_restoreAppPresentation());
    super.dispose();
  }

  void _requestTvPlaybackFocusAfterFrame() {
    if (!_isTvMode || _tvPlaybackInitialFocusRequested) {
      return;
    }
    _tvPlaybackInitialFocusRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_tvPlaybackFocusNode);
      }
    });
  }

  bool _handleTvHardwareKeyEvent(KeyEvent event) {
    if (!_isTvMode || event is! KeyDownEvent || !mounted) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return false;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape) {
      _handleTvBack();
      return true;
    }
    return false;
  }

  BiliVideoPageEntry get _selectedPage => _viewModel.selectedPage;

  BiliResolvedPlayback? get _resolvedPlayback => _viewModel.resolvedPlayback;

  BiliVideoEngagement? get _engagement => _viewModel.engagement;

  bool get _engagementLoading => _viewModel.engagementLoading;

  String get _shareCountLabel => _viewModel.shareCountLabel;

  BiliEngagementAction? get _pendingEngagementAction =>
      _viewModel.pendingEngagementAction;

  int? get _selectedBiliQualityId => _viewModel.selectedBiliQualityId;

  BiliCodecStrategy get _selectedCodecStrategy =>
      _viewModel.selectedCodecStrategy;

  BiliDlnaState get _dlnaState => _viewModel.dlnaState;

  BiliExternalPlaybackManager get _dlnaManager => _viewModel.dlnaManager;

  BiliOfflineDownloadController get _offlineController =>
      _viewModel.offlineController;

  String get _ownerSubtitle => _viewModel.ownerSubtitle;

  String get _videoMetaLine => _viewModel.videoMetaLine;

  void _setCastingSurfaceOpen(bool value) {
    if (_castingSurfaceOpen == value) {
      return;
    }
    if (!mounted) {
      _castingSurfaceOpen = value;
      return;
    }
    setState(() {
      _castingSurfaceOpen = value;
    });
  }

  void _setDlnaPickerOpen(bool value) {
    if (_dlnaPickerOpen == value) {
      return;
    }
    if (!mounted) {
      _dlnaPickerOpen = value;
      return;
    }
    setState(() {
      _dlnaPickerOpen = value;
    });
  }

  void _handleViewModelMessage() {
    final message = _viewModel.consumePendingMessage();
    if (message != null && mounted) {
      _showMessage(message);
    }
  }

  Future<void> _showViewModelMessage(Future<String?> operation) async {
    final message = await operation;
    if (message != null && mounted) {
      _showMessage(message);
    }
  }

  Future<void> _reloadCurrentPage() {
    return _viewModel.reloadCurrentPage();
  }

  Future<void> _toggleLike() {
    return _showViewModelMessage(_viewModel.toggleLike());
  }

  Future<void> _toggleFavorite() {
    return _showViewModelMessage(_viewModel.toggleFavorite());
  }

  Future<void> _toggleFollow() {
    return _showViewModelMessage(_viewModel.toggleFollow());
  }

  Future<void> _shareVideo() {
    return _showViewModelMessage(_viewModel.shareVideo());
  }

  Future<void> _toggleFullscreen() async {
    final shouldEnterFullscreen = !_viewModel.isFullscreen;
    if (shouldEnterFullscreen) {
      _viewModel.setFullscreen(true);
      await _enterFullscreenPresentation();
      return;
    }
    await _exitFullscreen();
  }

  Future<void> _enterPlaybackPresentation() async {
    if (_isTvMode) {
      await _applySystemPresentation(
        orientations: _playbackLandscapeOrientations,
        systemUiMode: SystemUiMode.immersiveSticky,
        overlayStyle: _playbackSystemUiStyle,
      );
      return;
    }
    await _applySystemPresentation(
      orientations: _playbackPortraitOrientations,
      systemUiMode: SystemUiMode.edgeToEdge,
      overlayStyle: _playbackSystemUiStyle,
    );
  }

  Future<void> _enterFullscreenPresentation() async {
    await _applySystemPresentation(
      orientations: _playbackLandscapeOrientations,
      systemUiMode: SystemUiMode.immersiveSticky,
      overlayStyle: _playbackSystemUiStyle,
    );
  }

  Future<void> _exitFullscreenPresentation() async {
    await _applySystemPresentation(
      orientations: _playbackPortraitOrientations,
      systemUiMode: SystemUiMode.edgeToEdge,
      overlayStyle: _playbackSystemUiStyle,
    );
  }

  Future<void> _exitFullscreen() async {
    if (!_viewModel.isFullscreen) {
      return;
    }
    await _exitFullscreenPresentation();
    if (!mounted) {
      return;
    }
    _viewModel.setFullscreen(false);
  }

  Future<void> _restoreAppPresentation() async {
    if (_isTvMode) {
      await _applySystemPresentation(
        orientations: _playbackLandscapeOrientations,
        systemUiMode: SystemUiMode.immersiveSticky,
        overlayStyle: _playbackSystemUiStyle,
      );
      return;
    }
    await _applySystemPresentation(
      orientations: _appDefaultOrientations,
      systemUiMode: SystemUiMode.edgeToEdge,
      overlayStyle: _appSystemUiStyle,
    );
  }

  Future<void> _applySystemPresentation({
    required List<DeviceOrientation> orientations,
    required SystemUiMode systemUiMode,
    required SystemUiOverlayStyle overlayStyle,
  }) async {
    final generation = ++_presentationGeneration;
    await _setPreferredOrientations(orientations);
    if (generation != _presentationGeneration) {
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(systemUiMode);
    if (generation != _presentationGeneration) {
      return;
    }
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
  }

  Future<void> _setPreferredOrientations(
    List<DeviceOrientation> orientations,
  ) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    await SystemChrome.setPreferredOrientations(orientations);
  }

  Future<void> _switchPage(BiliVideoPageEntry page) {
    return _showViewModelMessage(_viewModel.switchPage(page));
  }

  Future<void> _setPlaybackRate(double rate) {
    return _showViewModelMessage(_viewModel.setPlaybackRate(rate));
  }

  Future<void> _selectBiliQuality(int? qualityId) {
    return _showViewModelMessage(_viewModel.selectBiliQuality(qualityId));
  }

  Future<void> _selectCodecStrategy(BiliCodecStrategy strategy) {
    return _showViewModelMessage(_viewModel.selectCodecStrategy(strategy));
  }

  List<double> _playbackRates(VesperPlayerSnapshot snapshot) {
    return _viewModel.playbackRates(snapshot);
  }

  List<VesperMediaTrack> _playbackSelectionTracks(
    VesperPlayerSnapshot snapshot,
  ) {
    return _viewModel.playbackSelectionTracks(snapshot);
  }

  List<int> _availableBiliQualityIds(List<VesperMediaTrack> tracks) {
    return _viewModel.availableBiliQualityIds(tracks);
  }

  bool _hasTrackForSelection(
    List<VesperMediaTrack> tracks,
    int? qualityId,
    BiliCodecStrategy strategy,
  ) {
    return _viewModel.hasTrackForSelection(tracks, qualityId, strategy);
  }

  BiliVideoCodecPreference _currentDownloadCodecPreference() {
    return _viewModel.currentDownloadCodecPreference();
  }

  String _playbackStateLabel(VesperPlayerSnapshot snapshot) {
    return _viewModel.playbackStateLabel(snapshot);
  }

  String? _biliQualityLabelFromQualityId(int qualityId) {
    return _viewModel.biliQualityLabelFromQualityId(qualityId);
  }

  int? _currentBiliQualityId(
    VesperPlayerSnapshot snapshot,
    List<VesperMediaTrack> tracks,
  ) {
    final selected = _selectedBiliQualityId;
    if (selected != null) {
      return selected;
    }

    final effectiveTrackId = snapshot.effectiveVideoTrackId;
    if (effectiveTrackId != null) {
      for (final track in tracks) {
        if (track.id == effectiveTrackId) {
          return _viewModel.biliQualityIdForTrack(track);
        }
      }
      final directQualityId = RegExp(
        r'(?:^|:)video-(\d+)-',
      ).firstMatch(effectiveTrackId);
      if (directQualityId != null) {
        return int.tryParse(directQualityId.group(1)!);
      }
    }

    final observation = snapshot.videoVariantObservation;
    if (observation == null) {
      return null;
    }
    VesperMediaTrack? bestMatch;
    var bestScore = double.infinity;
    for (final track in tracks) {
      final height = track.height;
      final bitRate = track.bitRate;
      var score = 0.0;
      if (height != null && observation.height != null) {
        score += (height - observation.height!).abs() * 100000.0;
      }
      if (bitRate != null && observation.bitRate != null) {
        score += (bitRate - observation.bitRate!).abs().toDouble();
      }
      if (score < bestScore) {
        bestScore = score;
        bestMatch = track;
      }
    }
    return bestMatch == null
        ? null
        : _viewModel.biliQualityIdForTrack(bestMatch);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _playbackSystemUiStyle,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F4F8),
        body: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            return FutureBuilder<VesperPlayerController>(
              future: _viewModel.controllerFuture,
              builder: (context, asyncSnapshot) {
                if (asyncSnapshot.hasError) {
                  return _BiliPlaybackErrorState(
                    error: asyncSnapshot.error!,
                    onRetry: _reloadCurrentPage,
                  );
                }
                if (!asyncSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final controller = asyncSnapshot.data!;
                return ValueListenableBuilder<VesperPlayerSnapshot>(
                  valueListenable: controller.snapshotListenable,
                  builder: (context, snapshot, _) {
                    return _buildPlaybackLayout(context, controller, snapshot);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaybackLayout(
    BuildContext context,
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
  ) {
    if (_isTvMode) {
      return _buildTvPlaybackLayout(context, controller, snapshot);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isFullscreen = _viewModel.isFullscreen;
        final stageCornerPadding = _displayCornerPadding(context);
        final stage = _buildStage(
          controller: controller,
          snapshot: snapshot,
          isFullscreen: isFullscreen,
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
        final bottomSurface = _buildBottomSurface(
          context,
          snapshot,
          errorMessage: snapshot.lastError?.message,
        );

        if (isWide) {
          final panelWidth = (constraints.maxWidth * 0.36)
              .clamp(constraints.maxWidth * 0.28, constraints.maxWidth * 0.42)
              .toDouble();
          return PopScope(
            canPop: true,
            child: ColoredBox(
              color: const Color(0xFFF4F4F8),
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
            color: const Color(0xFFF4F4F8),
            child: Column(
              children: [
                _buildStageFrame(
                  stage,
                  padding: stageCornerPadding.add(
                    const EdgeInsets.fromLTRB(10, 6, 10, 12),
                  ),
                  safeBottom: false,
                ),
                Expanded(child: bottomSurface),
              ],
            ),
          ),
        );
      },
    );
  }

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
          SingleActivator(LogicalKeyboardKey.goBack): _TvPlaybackBackIntent(),
          SingleActivator(LogicalKeyboardKey.browserBack):
              _TvPlaybackBackIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _TvPlaybackBackIntent(),
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
                if (!snapshot.isBuffering) {
                  if (isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                }
                return null;
              },
            ),
            _TvPlaybackLeftIntent: CallbackAction<_TvPlaybackLeftIntent>(
              onInvoke: (_) {
                _handleTvDirectionalIntent(
                  TraversalDirection.left,
                  controller,
                  snapshot,
                );
                return null;
              },
            ),
            _TvPlaybackRightIntent: CallbackAction<_TvPlaybackRightIntent>(
              onInvoke: (_) {
                _handleTvDirectionalIntent(
                  TraversalDirection.right,
                  controller,
                  snapshot,
                );
                return null;
              },
            ),
            _TvPlaybackUpIntent: CallbackAction<_TvPlaybackUpIntent>(
              onInvoke: (_) {
                _handleTvDirectionalIntent(
                  TraversalDirection.up,
                  controller,
                  snapshot,
                );
                return null;
              },
            ),
            _TvPlaybackDownIntent: CallbackAction<_TvPlaybackDownIntent>(
              onInvoke: (_) {
                _handleTvDirectionalIntent(
                  TraversalDirection.down,
                  controller,
                  snapshot,
                );
                return null;
              },
            ),
            _TvPlaybackBackIntent: CallbackAction<_TvPlaybackBackIntent>(
              onInvoke: (_) {
                _handleTvBack();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _tvPlaybackFocusNode,
            autofocus: true,
            onKeyEvent: _handleTvPlaybackKeyEvent,
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
                        child: _buildTvControlBar(
                          controller,
                          snapshot,
                          isPlaying,
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
                        child: _buildTvPanel(controller, snapshot),
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

  KeyEventResult _handleTvPlaybackKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape) {
      _handleTvBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleTvStageTap() {
    _tvPlaybackFocusNode.requestFocus();
    _handleTvSelect();
  }

  void _handleTvSelect() {
    if (_tvPanelOpen) {
      return;
    }
    setState(() {
      _tvControlBarVisible = !_tvControlBarVisible;
    });
  }

  void _showTvControls() {
    if (_tvControlBarVisible) {
      return;
    }
    setState(() {
      _tvControlBarVisible = true;
    });
  }

  void _handleTvBack() {
    if (_tvPanelOpen) {
      _closeTvPanelAndRestoreFocus();
      return;
    }
    if (_tvControlBarVisible) {
      setState(() {
        _tvControlBarVisible = false;
      });
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => BiliTvHomePage(
          client: widget.client,
          historyStore: widget.historyStore,
          offlineController: widget.offlineController,
        ),
      ),
    );
  }

  void _handleTvDirectionalIntent(
    TraversalDirection direction,
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
  ) {
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
      _seekTvBy(controller, snapshot, -10000);
      return;
    }
    if (direction == TraversalDirection.right) {
      _seekTvBy(controller, snapshot, 10000);
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
    controller.seekToRatio(nextMs / durationMs);
  }

  void _openTvPanel(TvPlaybackPanelType panel) {
    final willOpen = _tvPanel != panel;
    setState(() {
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

  Widget _buildTvPanel(
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
  ) {
    final tracks = _playbackSelectionTracks(snapshot);
    final qualityIds = _availableBiliQualityIds(tracks);
    final currentQualityId = _currentBiliQualityId(snapshot, tracks);
    final rates = _playbackRates(snapshot);
    final pages = widget.detail.pages;
    final isPgc =
        widget.detail.ownerMid <= 0 && widget.detail.ownerName == '番剧';
    final label = switch (_tvPanel) {
      TvPlaybackPanelType.quality => '清晰度',
      TvPlaybackPanelType.speed => '倍速',
      TvPlaybackPanelType.pages => isPgc ? '选集' : '分P',
      TvPlaybackPanelType.none => '',
    };
    final subtitle = switch (_tvPanel) {
      TvPlaybackPanelType.quality => '确认后立即切换当前播放清晰度',
      TvPlaybackPanelType.speed => '确认后立即改变播放速度',
      TvPlaybackPanelType.pages =>
        isPgc ? '上下选择剧集，确认播放选中的一集' : '上下选择分 P，确认播放选中的分段',
      TvPlaybackPanelType.none => '',
    };
    final options = switch (_tvPanel) {
      TvPlaybackPanelType.quality =>
        qualityIds
            .map(
              (id) => _TvPanelOption(
                label: _biliQualityLabelFromQualityId(id) ?? '$id',
                selected: currentQualityId == id,
                onTap: () {
                  unawaited(_selectBiliQuality(id));
                },
              ),
            )
            .toList(),
      TvPlaybackPanelType.speed =>
        rates
            .map(
              (rate) => _TvPanelOption(
                label: '${rate}x',
                selected: (snapshot.playbackRate - rate).abs() < 0.01,
                onTap: () {
                  unawaited(_setPlaybackRate(rate));
                },
              ),
            )
            .toList(),
      TvPlaybackPanelType.pages =>
        pages
            .map(
              (page) => _TvPanelOption(
                label: isPgc ? '第 ${page.pageNumber} 集' : 'P${page.pageNumber}',
                subtitle: page.title,
                selected: _selectedPage.cid == page.cid,
                onTap: () {
                  unawaited(_switchPage(page));
                },
              ),
            )
            .toList(),
      TvPlaybackPanelType.none => const <_TvPanelOption>[],
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
                child: _TvPanelDrawer(
                  panel: _tvPanel,
                  label: label,
                  subtitle: subtitle,
                  options: options,
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
    setState(() {
      _tvPanel = TvPlaybackPanelType.none;
      _lastOpenedTvPanel = null;
    });
    if (panel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tvPanelButtonFocusNodes[panel]?.requestFocus();
      });
    }
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
                            controller.seekToRatio(value);
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
                  _TvBarButton(
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
                  _TvBarButton(
                    label: '快退 10s',
                    icon: Icons.replay_10_rounded,
                    onTap: () {
                      final newPosMs = (positionMs - 10000).clamp(
                        0,
                        durationMs,
                      );
                      controller.seekToRatio(
                        durationMs > 0 ? newPosMs / durationMs : 0,
                      );
                    },
                  ),
                  const SizedBox(width: 14),
                  _TvBarButton(
                    label: '快进 10s',
                    icon: Icons.forward_10_rounded,
                    onTap: () {
                      final newPosMs = (positionMs + 10000).clamp(
                        0,
                        durationMs,
                      );
                      controller.seekToRatio(
                        durationMs > 0 ? newPosMs / durationMs : 0,
                      );
                    },
                  ),
                  const SizedBox(width: 14),
                  _TvBarButton(
                    label: '清晰度',
                    icon: Icons.hd_rounded,
                    focusNode: _tvPanelButtonNode(TvPlaybackPanelType.quality),
                    onTap: () => _openTvPanel(TvPlaybackPanelType.quality),
                  ),
                  const SizedBox(width: 14),
                  _TvBarButton(
                    label: '倍速',
                    icon: Icons.speed_rounded,
                    focusNode: _tvPanelButtonNode(TvPlaybackPanelType.speed),
                    onTap: () => _openTvPanel(TvPlaybackPanelType.speed),
                  ),
                  if (widget.detail.pages.length > 1) ...[
                    const SizedBox(width: 14),
                    _TvBarButton(
                      label: '分P',
                      icon: Icons.playlist_play_rounded,
                      focusNode: _tvPanelButtonNode(TvPlaybackPanelType.pages),
                      onTap: () => _openTvPanel(TvPlaybackPanelType.pages),
                    ),
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

  Widget _buildStage({
    required VesperPlayerController controller,
    required VesperPlayerSnapshot snapshot,
    required bool isFullscreen,
  }) {
    final usesPortraitChrome = !isFullscreen;
    return vesper_ui.VesperPlayerStage(
      controller: controller,
      snapshot: snapshot,
      isPortrait: usesPortraitChrome,
      sheetOpen: _settingsSurfaceOpen || _castingSurfaceOpen || _dlnaPickerOpen,
      deviceControls: _stageDeviceControls,
      topBarPrimaryAction: _buildStageProjectionAction(controller),
      strings: const vesper_ui.VesperPlayerStageStrings.zhHans(),
      onOpenSheet: (sheet) =>
          unawaited(_openStageSheet(controller, sheet, usesPortraitChrome)),
      onToggleFullscreen: () => unawaited(_toggleFullscreen()),
    );
  }

  Widget _buildStageFrame(
    Widget stage, {
    required EdgeInsetsGeometry padding,
    required bool safeBottom,
  }) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        bottom: safeBottom,
        child: Padding(
          padding: padding,
          child: Center(
            child: AspectRatio(aspectRatio: 16 / 9, child: stage),
          ),
        ),
      ),
    );
  }

  EdgeInsets _displayCornerPadding(BuildContext context) {
    final corners = MediaQuery.maybeDisplayCornerRadiiOf(context);
    if (corners == null) {
      return EdgeInsets.zero;
    }
    final topPadding = corners.topLeft.x > corners.topRight.x
        ? corners.topLeft.x
        : corners.topRight.x;
    return EdgeInsets.only(
      left: corners.topLeft.x,
      top: topPadding,
      right: corners.topRight.x,
    );
  }

  Widget _buildBottomSurface(
    BuildContext context,
    VesperPlayerSnapshot snapshot, {
    String? errorMessage,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 540 ? 34.0 : 16.0;
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFF4F4F8),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              18,
              horizontalPadding,
              28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errorMessage != null) ...[
                  _PlaybackInlineError(
                    title: '播放器错误',
                    message: errorMessage,
                    actionLabel: '重新解析',
                    onPressed: _reloadCurrentPage,
                  ),
                  const SizedBox(height: 14),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    key: const PageStorageKey<String>('playback-intro'),
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildIntroPanel(context, snapshot),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openStageSheet(
    VesperPlayerController controller,
    vesper_ui.VesperPlayerStageSheet _,
    bool isPortrait,
  ) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _settingsSurfaceOpen = true;
    });
    try {
      await _showSettingsSurface(controller, isPortrait: isPortrait);
    } finally {
      if (mounted) {
        setState(() {
          _settingsSurfaceOpen = false;
        });
      }
    }
  }
}

class _TvBarButton extends StatelessWidget {
  const _TvBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      scale: 1.12,
      focusElevation: 0,
      focusCornerRadius: 12,
      baseCornerRadius: 12,
      showGlow: true,
      focusArea: TvFocusArea.playbackControls,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvPanelDrawer extends StatelessWidget {
  const _TvPanelDrawer({
    required this.panel,
    required this.label,
    required this.subtitle,
    required this.options,
    required this.onClose,
  });

  final TvPlaybackPanelType panel;
  final String label;
  final String subtitle;
  final List<_TvPanelOption> options;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0x88FFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: _TvPanelOptionList(panel: panel, options: options),
        ),
        TvFocusable(
          autofocus: false,
          showGlow: false,
          scale: 1.04,
          focusCornerRadius: 12,
          baseCornerRadius: 12,
          focusArea: TvFocusArea.playbackPanel,
          debugLabel: 'tv_panel_close',
          onTap: onClose,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0x18FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x18FFFFFF)),
            ),
            child: const Text(
              '关闭',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TvPanelOptionList extends StatefulWidget {
  const _TvPanelOptionList({required this.panel, required this.options});

  final TvPlaybackPanelType panel;
  final List<_TvPanelOption> options;

  @override
  State<_TvPanelOptionList> createState() => _TvPanelOptionListState();
}

class _TvPanelOptionListState extends State<_TvPanelOptionList> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSelectedOption());
  }

  @override
  void didUpdateWidget(_TvPanelOptionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel != widget.panel ||
        oldWidget.options.length != widget.options.length ||
        _selectedIndex(oldWidget.options) != _selectedIndex(widget.options)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusSelectedOption(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _selectedIndex(List<_TvPanelOption> options) {
    final index = options.indexWhere((option) => option.selected);
    return index < 0 ? 0 : index;
  }

  void _focusSelectedOption() {
    if (!mounted || !_controller.hasClients || widget.options.isEmpty) {
      return;
    }
    final selectedIndex = _selectedIndex(widget.options);
    _controller.animateTo(
      (selectedIndex * 86.0).clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(widget.options);
    return ListView.separated(
      key: PageStorageKey<String>('tv-panel-list-${widget.panel.name}'),
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
      itemCount: widget.options.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final option = widget.options[index];
        return _TvPanelOptionTile(
          option: option,
          autofocus: index == selectedIndex,
        );
      },
    );
  }
}

class _TvPanelOptionTile extends StatefulWidget {
  const _TvPanelOptionTile({required this.option, required this.autofocus});

  final _TvPanelOption option;
  final bool autofocus;

  @override
  State<_TvPanelOptionTile> createState() => _TvPanelOptionTileState();
}

class _TvPanelOptionTileState extends State<_TvPanelOptionTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final selected = option.selected;
    final focused = _focused;
    return TvFocusable(
      autofocus: widget.autofocus,
      debugLabel: 'tv_panel_${option.label}',
      showGlow: false,
      scale: 1,
      focusCornerRadius: 14,
      baseCornerRadius: 14,
      focusArea: TvFocusArea.playbackPanel,
      onFocusChange: (value) {
        setState(() {
          _focused = value;
        });
      },
      onTap: option.onTap,
      child: AnimatedScale(
        scale: focused ? 1.035 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: focused ? const Offset(-0.018, 0) : Offset.zero,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.24)
                  : selected
                  ? const Color(0xFFFB7299)
                  : const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused
                    ? const Color(0xF2F8FBFF)
                    : selected
                    ? const Color(0xCCFB7299)
                    : const Color(0x16FFFFFF),
                width: focused ? 1.6 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.16),
                        blurRadius: 26,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.36),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 4,
                  height: 34,
                  decoration: BoxDecoration(
                    color: focused || selected
                        ? Colors.white
                        : const Color(0x00FFFFFF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: focused || selected
                              ? Colors.white
                              : const Color(0xDFFFFFFF),
                          fontSize: 16,
                          fontWeight: focused || selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      if (option.subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          option.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: focused || selected
                                ? Colors.white.withValues(alpha: 0.82)
                                : const Color(0x88FFFFFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (selected)
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  )
                else if (focused)
                  const Icon(
                    Icons.radio_button_unchecked_rounded,
                    color: Color(0xCCFFFFFF),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvPanelOption {
  const _TvPanelOption({
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
}

class _TvPlaybackToggleBarIntent extends Intent {
  const _TvPlaybackToggleBarIntent();
}

class _TvPlaybackMenuIntent extends Intent {
  const _TvPlaybackMenuIntent();
}

class _TvPlayPauseIntent extends Intent {
  const _TvPlayPauseIntent();
}

class _TvPlaybackLeftIntent extends Intent {
  const _TvPlaybackLeftIntent();
}

class _TvPlaybackRightIntent extends Intent {
  const _TvPlaybackRightIntent();
}

class _TvPlaybackUpIntent extends Intent {
  const _TvPlaybackUpIntent();
}

class _TvPlaybackDownIntent extends Intent {
  const _TvPlaybackDownIntent();
}

class _TvPlaybackBackIntent extends Intent {
  const _TvPlaybackBackIntent();
}
