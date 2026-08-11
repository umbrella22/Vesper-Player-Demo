import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_ui/vesper_player_ui.dart' as vesper_ui;

import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_media/media/player/media_glass_sheet.dart';

enum TvPlaybackPanelType { none, quality, speed, subtitles, pages }

enum _PlaybackInfoTab { intro, comments }

/// 通用播放页壳。
///
/// 平台差异全部经构造槽位注入：
/// - [viewModel]：播放编排（调用方构造并管理生命周期）
/// - [binding]：单次播放的互动能力与内容面板
/// - [deviceControls]：亮度/音量设备控制
/// - [presentation]：系统呈现策略
/// - [contentTabsTrailing]/[tuningCacheEntry]/[tvControlBarExtras]/[tvFallbackHome]：
///   平台扩展 UI（弹幕入口/缓存入口/稍后再看/TV 首页回退）
/// - [recoveryDialogBuilder]：播放恢复失败提示（平台视觉）
class MediaPlaybackPage extends StatefulWidget {
  const MediaPlaybackPage({
    super.key,
    required this.viewModel,
    this.presentationMode = MediaPlaybackPresentationMode.phone,
    this.binding = const MediaPlaybackBinding(),
    this.deviceControls = const MediaNoopDeviceControls(),
    this.contentTabsTrailing,
    this.tuningCacheEntry,
    this.tvControlBarExtras = const <Widget>[],
    this.tvFallbackHome,
    this.recoveryDialogBuilder,
    this.presentation = MediaPlaybackPresentation.noop,
    this.onPushPlayback,
  });

  /// 播放编排 view model（调用方构造并负责 dispose）。
  final MediaPlaybackViewModel viewModel;

  final MediaPlaybackPresentationMode presentationMode;

  /// 页面级动态能力；缺省不渲染互动栏与内容 tab。
  final MediaPlaybackBinding binding;

  final MediaPlayerDeviceControls deviceControls;

  /// 内容 tab 尾部扩展（如弹幕入口胶囊）。
  final Widget? contentTabsTrailing;

  /// 调校面板的离线缓存入口（下载保持 app 级）。
  final Widget? tuningCacheEntry;

  /// TV 控制条右侧扩展按钮（如稍后再看）。
  final List<Widget> tvControlBarExtras;

  /// TV 返回栈底时的平台首页。
  final Widget? tvFallbackHome;

  /// 播放恢复失败提示对话框（平台视觉）；缺省使用默认对话框。
  final Future<bool?> Function(
    BuildContext context,
    MediaPlaybackRecoveryNotice notice,
  )?
  recoveryDialogBuilder;

  /// 系统呈现策略。
  final MediaPlaybackPresentation presentation;

  /// 打开新播放页（相关视频跳转等），由平台实现。
  final void Function(MediaDetail detail, MediaPlaybackEntry entry)?
  onPushPlayback;

  @override
  State<MediaPlaybackPage> createState() => _MediaPlaybackPageState();
}

class _MediaPlaybackPageState extends State<MediaPlaybackPage>
    with TickerProviderStateMixin {
  late final MediaPlaybackViewModel _viewModel;
  MediaContentSurfaces? _contentSurfaces;
  late final MediaPlaybackContentHost _contentHost;
  void Function()? _messageEffect;

  /// 内容 tab 控制器；平台未声明内容面板时为 null（不渲染 tab 区）。
  /// build 中按能力同步（评论面板可用性依赖 context，initState 无法判定）。
  TabController? _infoTabController;
  int _infoTabCount = 0;

  /// 评论面板可用性缓存：按 entry 失效（nullable builder 接收当前 target，
  /// 分 P 之间评论能力可能不同），surfaces 不换。
  bool? _commentsAvailable;
  String? _commentsAvailableEntryId;
  bool _settingsSurfaceOpen = false;
  bool _castingSurfaceOpen = false;
  bool _dlnaPickerOpen = false;
  _PlaybackInfoTab _selectedInfoTab = _PlaybackInfoTab.intro;
  bool _commentsRepliesOpen = false;
  final ScrollController _commentsScrollController = ScrollController();
  final ScrollController _commentRepliesScrollController = ScrollController(
    keepScrollOffset: false,
  );
  final ScrollController _relatedScrollController = ScrollController();
  final TextEditingController _commentComposerController =
      TextEditingController();
  final FocusNode _commentComposerFocusNode = FocusNode(
    debugLabel: 'comment_composer',
  );
  double _mobileStageCollapseOffset = 0;
  double? _scheduledMobileStageCollapseOffset;
  bool _mobileStageCollapseFrameScheduled = false;
  int _presentationGeneration = 0;
  bool _tvControlBarVisible = false;
  TvPlaybackPanelType _tvPanel = TvPlaybackPanelType.none;
  final FocusNode _tvPlaybackFocusNode = FocusNode(debugLabel: 'tv_playback');
  final Map<TvPlaybackPanelType, FocusNode> _tvPanelButtonFocusNodes =
      <TvPlaybackPanelType, FocusNode>{};
  TvPlaybackPanelType? _lastOpenedTvPanel;
  bool _tvPlaybackInitialFocusRequested = false;
  bool _playbackRecoveryDialogVisible = false;
  bool _tvBackDispatchPending = false;

  bool get _isTvMode =>
      widget.presentationMode == MediaPlaybackPresentationMode.tv;

  bool get _tvPanelOpen => _tvPanel != TvPlaybackPanelType.none;

  bool get _playbackModalRouteOpen =>
      _settingsSurfaceOpen ||
      _castingSurfaceOpen ||
      _dlnaPickerOpen ||
      _playbackRecoveryDialogVisible;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel;
    _contentHost = MediaPlaybackContentHost(
      surfaceHost: MediaSurfaceHost(
        pushPlayback: (detail, entry) {
          widget.onPushPlayback?.call(detail, entry);
        },
      ),
      relatedScrollController: _relatedScrollController,
      commentsScrollController: _commentsScrollController,
      commentRepliesScrollController: _commentRepliesScrollController,
      commentComposerController: _commentComposerController,
      commentComposerFocusNode: _commentComposerFocusNode,
      onContentScroll: _handleMobileContentScroll,
      onCommentRepliesVisibilityChanged: _handleCommentRepliesVisibilityChanged,
      onSeekToTime: _seekToCommentTime,
    );
    _contentSurfaces = widget.binding.buildContentSurfaces(_contentHost);
    _commentsScrollController.addListener(_handleCommentsScrollPosition);
    _commentRepliesScrollController.addListener(
      _handleCommentRepliesScrollPosition,
    );
    // One-shot messages and playback-recovery notices are surfaced through an
    // effect that tracks the VM's pending-message signals.
    _messageEffect = effect(_handleViewModelMessage);
    HardwareKeyboard.instance.addHandler(_handleTvHardwareKeyEvent);
    unawaited(_enterPlaybackPresentation());
  }

  @override
  void didUpdateWidget(MediaPlaybackPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presentationMode != widget.presentationMode) {
      _tvPlaybackInitialFocusRequested = false;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleTvHardwareKeyEvent);
    _infoTabController?.removeListener(_handleInfoTabChanged);
    _infoTabController?.dispose();
    _commentsScrollController.removeListener(_handleCommentsScrollPosition);
    _commentsScrollController.dispose();
    _commentRepliesScrollController.removeListener(
      _handleCommentRepliesScrollPosition,
    );
    _commentRepliesScrollController.dispose();
    _relatedScrollController.dispose();
    _commentComposerController.dispose();
    _commentComposerFocusNode.dispose();
    _tvPlaybackFocusNode.dispose();
    for (final node in _tvPanelButtonFocusNodes.values) {
      node.dispose();
    }
    _messageEffect?.call();
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
    final key = event.logicalKey;
    final isBackKey =
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape;
    final route = ModalRoute.of(context);
    if (!isBackKey &&
        route?.isCurrent == true &&
        !_playbackModalRouteOpen &&
        !_tvPanelOpen &&
        !_tvControlBarVisible) {
      final controller = _viewModel.controller;
      if (controller == null) {
        return false;
      }
      final snapshot = controller.snapshot;
      if (key == LogicalKeyboardKey.arrowLeft) {
        _seekTvBy(controller, snapshot, -10000);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _seekTvBy(controller, snapshot, 10000);
        return true;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space) {
        _toggleTvPlayback(controller, snapshot);
        return true;
      }
    }
    if (!isBackKey) {
      return false;
    }
    if (route != null && !route.isCurrent) {
      if (_playbackModalRouteOpen) {
        _handleTvBack();
        return true;
      }
      return false;
    }
    _handleTvBack();
    return true;
  }

  MediaPlaybackEntry get _selectedEntry => _viewModel.selectedEntry;

  ResolvedMediaPlayback? get _resolvedPlayback => _viewModel.resolvedPlayback;

  MediaDlnaState get _dlnaState => _viewModel.dlnaState;

  MediaExternalPlaybackManager get _dlnaManager => _viewModel.dlnaManager;

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

  void _handleInfoTabChanged() {
    _syncSelectedInfoTab(_tabForInfoIndex(_infoTabController!.index));
  }

  void _syncSelectedInfoTab(_PlaybackInfoTab tab) {
    if (_selectedInfoTab == tab) {
      return;
    }
    final scrollController = _scrollControllerForInfoTab(tab);
    setState(() {
      _selectedInfoTab = tab;
      _mobileStageCollapseOffset = scrollController.hasClients
          ? scrollController.offset
          : 0;
    });
  }

  _PlaybackInfoTab _tabForInfoIndex(int index) {
    return index == 1 ? _PlaybackInfoTab.comments : _PlaybackInfoTab.intro;
  }

  /// 评论面板可用性：label 与 builder 双条件——
  /// [MediaContentSurfaces.commentsTabLabel] 为 null 或
  /// [MediaContentSurfaces.buildCommentsSurface] 返回 null 都视为
  /// 未声明评论（单 tab）。判定依赖 context，首次 build 后缓存。
  bool _computeCommentsAvailable(BuildContext context) {
    final entryId = _viewModel.selectedEntry.entryId;
    final cached = _commentsAvailable;
    if (cached != null && _commentsAvailableEntryId == entryId) {
      return cached;
    }
    final surfaces = _contentSurfaces;
    var available = false;
    if (surfaces != null && surfaces.commentsTabLabel != null) {
      final target = MediaPlaybackTarget(
        detail: _viewModel.detail,
        entry: _viewModel.selectedEntry,
      );
      available = surfaces.buildCommentsSurface(context, target) != null;
    }
    _commentsAvailable = available;
    _commentsAvailableEntryId = entryId;
    return available;
  }

  /// 内容 tab 数量：无内容面板 0；仅简介 1；简介+评论 2。
  int _contentTabCount(BuildContext context) {
    final surfaces = _contentSurfaces;
    if (surfaces == null) {
      return 0;
    }
    return _computeCommentsAvailable(context) ? 2 : 1;
  }

  /// 内容 tab 控制器按能力在 build 中同步；数量变化时重建。
  void _syncInfoTabController(BuildContext context) {
    final count = _contentTabCount(context);
    if (count == _infoTabCount) {
      return;
    }
    final previous = _infoTabController;
    if (previous != null) {
      previous.removeListener(_handleInfoTabChanged);
      previous.dispose();
    }
    _infoTabCount = count;
    _infoTabController = count > 0
        ? (TabController(length: count, vsync: this)
            ..addListener(_handleInfoTabChanged))
        : null;
    // 评论 tab 消失（2 → 1/0）：新控制器从 index 0（简介）开始，
    // 重置指向已消失评论面板的选中态与回复面板状态。
    if (count < 2) {
      _selectedInfoTab = _PlaybackInfoTab.intro;
      _commentsRepliesOpen = false;
    }
  }

  bool _handleMobileContentScroll(ScrollNotification notification) {
    if (_isTvMode ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final nextOffset = notification.metrics.pixels.clamp(0.0, 1000.0);
    if ((nextOffset - _mobileStageCollapseOffset).abs() < 1) {
      return false;
    }
    _scheduledMobileStageCollapseOffset = nextOffset;
    if (_mobileStageCollapseFrameScheduled) {
      return false;
    }
    _mobileStageCollapseFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mobileStageCollapseFrameScheduled = false;
      final scheduledOffset = _scheduledMobileStageCollapseOffset;
      _scheduledMobileStageCollapseOffset = null;
      if (!mounted ||
          scheduledOffset == null ||
          (scheduledOffset - _mobileStageCollapseOffset).abs() < 1) {
        return;
      }
      setState(() {
        _mobileStageCollapseOffset = scheduledOffset;
      });
    });
    return false;
  }

  ScrollController _scrollControllerForInfoTab(_PlaybackInfoTab tab) {
    if (tab != _PlaybackInfoTab.comments) {
      return _relatedScrollController;
    }
    return _commentsRepliesOpen
        ? _commentRepliesScrollController
        : _commentsScrollController;
  }

  ScrollController get _activeInfoScrollController =>
      _scrollControllerForInfoTab(_selectedInfoTab);

  void _handleCommentsScrollPosition() {
    if (_selectedInfoTab != _PlaybackInfoTab.comments ||
        !_commentsScrollController.hasClients) {
      return;
    }
    final position = _commentsScrollController.position;
    if (position.maxScrollExtent - position.pixels <= 360) {
      unawaited(_loadMoreComments());
    }
  }

  void _handleCommentRepliesScrollPosition() {
    if (_selectedInfoTab != _PlaybackInfoTab.comments ||
        !_commentsRepliesOpen ||
        !_commentRepliesScrollController.hasClients) {
      return;
    }
    final position = _commentRepliesScrollController.position;
    if (position.maxScrollExtent - position.pixels <= 360) {
      unawaited(_loadMoreCommentReplies());
    }
  }

  void _handleCommentRepliesVisibilityChanged(bool isOpen) {
    if (_commentsRepliesOpen == isOpen) {
      return;
    }
    setState(() {
      _commentsRepliesOpen = isOpen;
      _mobileStageCollapseOffset = isOpen
          ? 0
          : _commentsScrollController.hasClients
          ? _commentsScrollController.offset
          : 0;
    });
  }

  void _handleMobileStagePointerMove(PointerMoveEvent event) {
    if (_isTvMode ||
        _viewModel.isFullscreen ||
        _viewModel.controller?.snapshot.playbackState ==
            VesperPlaybackState.playing) {
      return;
    }
    final delta = event.delta;
    if (delta.dy.abs() < 1 || delta.dy.abs() < delta.dx.abs()) {
      return;
    }
    _updateMobileStageCollapseOffset(_mobileStageCollapseOffset - delta.dy);
  }

  void _updateMobileStageCollapseOffset(double rawOffset) {
    final nextOffset = rawOffset.clamp(0.0, 1000.0).toDouble();
    if ((nextOffset - _mobileStageCollapseOffset).abs() < 1) {
      return;
    }
    final scrollController = _activeInfoScrollController;
    if (scrollController.hasClients) {
      final position = scrollController.position;
      final nextScrollOffset = nextOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((nextScrollOffset - position.pixels).abs() >= 1) {
        scrollController.jumpTo(nextScrollOffset);
      }
    }
    if (!mounted) {
      _mobileStageCollapseOffset = nextOffset;
      return;
    }
    setState(() {
      _mobileStageCollapseOffset = nextOffset;
    });
  }

  void _handleViewModelMessage() {
    final message = _viewModel.consumePendingMessage();
    if (message != null && mounted) {
      _showMessage(message);
    }
    final recoveryNotice = _viewModel.consumePendingPlaybackRecoveryNotice();
    if (recoveryNotice != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_showPlaybackRecoveryNotice(recoveryNotice));
        }
      });
    }
  }

  Future<void> _loadMoreComments() {
    return _contentHost.onLoadMoreComments?.call() ?? Future<void>.value();
  }

  Future<void> _loadMoreCommentReplies() {
    return _contentHost.onLoadMoreCommentReplies?.call() ??
        Future<void>.value();
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

  Future<void> _seekToCommentTime(int seconds) async {
    final controller = _viewModel.controller;
    if (controller == null) {
      _showMessage('播放器尚未准备好。');
      return;
    }
    final durationMs =
        controller.snapshot.timeline.durationMs ??
        (_selectedEntry.durationSeconds > 0
            ? _selectedEntry.durationSeconds * 1000
            : 0);
    if (durationMs <= 0) {
      _showMessage('当前视频暂不支持按评论时间跳转。');
      return;
    }
    final ratio = (seconds * 1000 / durationMs).clamp(0.0, 1.0).toDouble();
    // 经 VM 入口：用户 seek 使在途历史续播失效；失败时提示而非假装成功。
    final message = await _viewModel.seekToRatio(ratio);
    if (mounted) {
      _showMessage(message ?? '已跳转到 ${mediaFormatDurationSeconds(seconds)}');
    }
  }

  Future<void> _toggleFullscreen() async {
    final shouldEnterFullscreen = !_viewModel.isFullscreen;
    if (shouldEnterFullscreen) {
      _viewModel.setFullscreen(true);
      await _runPresentation(widget.presentation.enterFullscreen);
      return;
    }
    await _exitFullscreen();
  }

  Future<void> _enterPlaybackPresentation() async {
    if (_isTvMode) {
      await _runPresentation(widget.presentation.enterPlaybackTv);
      return;
    }
    await _runPresentation(widget.presentation.enterPlaybackPhone);
  }

  Future<void> _exitFullscreen() async {
    if (!_viewModel.isFullscreen) {
      return;
    }
    await _runPresentation(widget.presentation.exitFullscreen);
    if (!mounted) {
      return;
    }
    _viewModel.setFullscreen(false);
  }

  Future<void> _restoreAppPresentation() async {
    await _runPresentation(widget.presentation.restoreApp);
  }

  Future<void> _runPresentation(Future<void> Function() operation) async {
    final generation = ++_presentationGeneration;
    await operation();
    if (generation != _presentationGeneration) {
      return;
    }
  }

  Future<void> _switchEntry(MediaPlaybackEntry entry) {
    return _showViewModelMessage(_viewModel.switchEntry(entry));
  }

  Future<void> _setPlaybackRate(double rate) {
    return _showViewModelMessage(_viewModel.setPlaybackRate(rate));
  }

  Future<void> _selectQualityOption(String? optionId) {
    return _showViewModelMessage(_viewModel.selectQualityOption(optionId));
  }

  Future<void> _selectCodecIdentity(String? identity) {
    return _showViewModelMessage(_viewModel.selectCodecIdentity(identity));
  }

  Future<void> _selectSubtitle(VesperTrackSelection selection) {
    return _showViewModelMessage(_viewModel.selectSubtitle(selection));
  }

  List<double> _playbackRates(VesperPlayerSnapshot snapshot) {
    return _viewModel.playbackRates(snapshot);
  }

  List<VesperMediaTrack> _subtitleTracks(VesperPlayerSnapshot snapshot) {
    return _viewModel.subtitleTracks(snapshot);
  }

  VesperTrackSelection _subtitleSelection(VesperPlayerSnapshot snapshot) {
    return _viewModel.subtitleSelection(snapshot);
  }

  String _playbackStateLabel(VesperPlayerSnapshot snapshot) {
    return _viewModel.playbackStateLabel(snapshot);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showPlaybackRecoveryNotice(
    MediaPlaybackRecoveryNotice notice,
  ) async {
    if (!mounted || _playbackRecoveryDialogVisible) {
      return;
    }
    _playbackRecoveryDialogVisible = true;
    bool retry = false;
    try {
      final builder = widget.recoveryDialogBuilder;
      final result = builder != null
          ? await builder(context, notice)
          : await _defaultRecoveryDialog(notice);
      retry = result ?? false;
    } finally {
      _playbackRecoveryDialogVisible = false;
    }
    if (retry && mounted) {
      await _reloadCurrentPage();
    }
  }

  Future<bool?> _defaultRecoveryDialog(MediaPlaybackRecoveryNotice notice) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(notice.title),
          content: Text(notice.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('知道了'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('重新解析'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Scaffold(
      backgroundColor: visualTheme.background,
      body: SignalBuilder(
        builder: (context) {
          // VM state is read deep inside nested element builders where the
          // signals runtime cannot track reads, so the outer builder only
          // subscribes to what it directly needs (controller future and
          // fullscreen). Each layout section wraps its own reads in a leaf
          // SignalBuilder for fine-grained rebuilds.
          final isFullscreen = _viewModel.isFullscreen;
          return FutureBuilder<VesperPlayerController>(
            future: _viewModel.controllerFuture,
            builder: (context, asyncSnapshot) {
              if (asyncSnapshot.hasError) {
                return MediaPlaybackErrorState(
                  error: asyncSnapshot.error!,
                  onRetry: _reloadCurrentPage,
                );
              }
              if (!asyncSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final controller = asyncSnapshot.data!;
              final overlayStyle = _isTvMode || isFullscreen
                  ? (widget.presentation.darkSurfaceStyle ??
                        const SystemUiOverlayStyle())
                  : (widget.presentation.playbackStyleForBrightness?.call(
                          Theme.of(context).brightness,
                        ) ??
                        const SystemUiOverlayStyle());
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle,
                child: ValueListenableBuilder<VesperPlayerSnapshot>(
                  valueListenable: controller.snapshotListenable,
                  builder: (context, snapshot, _) {
                    return _buildPlaybackLayout(
                      context,
                      controller,
                      snapshot,
                      isFullscreen: isFullscreen,
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

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
    setState(() {
      _tvControlBarVisible = true;
    });
  }

  void _hideTvControlsAndRestoreFocus() {
    if (!_tvControlBarVisible) {
      _restoreTvPlaybackFocusAfterFrame();
      return;
    }
    _requestTvPlaybackFocus();
    setState(() {
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
    setState(() {
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

  Widget _buildStage({
    required VesperPlayerController controller,
    required VesperPlayerSnapshot snapshot,
    required bool isFullscreen,
  }) {
    final usesPortraitChrome = !isFullscreen;
    final stage = vesper_ui.VesperPlayerStage(
      controller: controller,
      snapshot: snapshot,
      isPortrait: usesPortraitChrome,
      sheetOpen: _settingsSurfaceOpen || _castingSurfaceOpen || _dlnaPickerOpen,
      deviceControls: widget.deviceControls,
      topBarPrimaryAction: _buildStageProjectionAction(controller),
      strings: const vesper_ui.VesperPlayerStageStrings.zhHans(),
      onOpenSheet: (sheet) =>
          unawaited(_openStageSheet(controller, sheet, usesPortraitChrome)),
      onToggleFullscreen: () => unawaited(_toggleFullscreen()),
    );
    final danmakuProvider = _viewModel.adapter.danmaku;
    if (danmakuProvider == null) {
      return stage;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        stage,
        MediaDanmakuLayer(
          provider: danmakuProvider,
          target: MediaPlaybackTarget(
            detail: _viewModel.detail,
            entry: _viewModel.selectedEntry,
          ),
          positionMs: snapshot.timeline.positionMs,
          playbackState: snapshot.playbackState,
          playbackRate: snapshot.playbackRate,
        ),
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
                        trailing: widget.contentTabsTrailing,
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
  }) {
    return showMediaPlaybackSettingsSurface(
      context,
      isPortrait: isPortrait,
      controller: controller,
      contentBuilder: (context, snapshot) =>
          _buildTuningPanel(context, controller, snapshot),
    );
  }

  Widget _buildTuningPanel(
    BuildContext context,
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
  ) {
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
      snapshot: snapshot,
      qualityOptions: qualityOptions,
      qualitySupportingTextFor: _viewModel.qualitySelectionSupportingText,
      selectedQualityOptionId: selectedId,
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
}

final class _TvPlaybackToggleBarIntent extends Intent {
  const _TvPlaybackToggleBarIntent();
}

final class _TvPlaybackMenuIntent extends Intent {
  const _TvPlaybackMenuIntent();
}

final class _TvPlayPauseIntent extends Intent {
  const _TvPlayPauseIntent();
}

final class _TvPlaybackLeftIntent extends Intent {
  const _TvPlaybackLeftIntent();
}

final class _TvPlaybackRightIntent extends Intent {
  const _TvPlaybackRightIntent();
}

final class _TvPlaybackUpIntent extends Intent {
  const _TvPlaybackUpIntent();
}

final class _TvPlaybackDownIntent extends Intent {
  const _TvPlaybackDownIntent();
}

enum _ProjectionTarget { dlna }
