part of 'media_playback_page.dart';

extension _MediaPlaybackPageActions on _MediaPlaybackPageState {
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
    if (_displayMode == _MediaPlaybackDisplayMode.listen) {
      if (isBackKey && ModalRoute.of(context)?.isCurrent == true) {
        _returnToVideoMode();
        return true;
      }
      if (key == LogicalKeyboardKey.mediaPlayPause ||
          key == LogicalKeyboardKey.mediaPlay ||
          key == LogicalKeyboardKey.mediaPause) {
        final controller = _viewModel.controller;
        if (controller != null) {
          _toggleTvPlayback(controller, controller.snapshot);
          return true;
        }
      }
      return false;
    }
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

  Future<void> _enterListenMode() async {
    if (_viewModel.isFullscreen ||
        _displayMode == _MediaPlaybackDisplayMode.listen) {
      return;
    }
    final message = await _viewModel.enterListenMode();
    if (!mounted) {
      return;
    }
    if (message != null) {
      _showMessage(message);
      return;
    }
    _tvControlBarVisible = false;
    _tvPanel = TvPlaybackPanelType.none;
    _lastOpenedTvPanel = null;
    _mutate(() {
      _displayMode = _MediaPlaybackDisplayMode.listen;
    });
  }

  Future<void> _returnToVideoMode() async {
    if (_displayMode == _MediaPlaybackDisplayMode.video) {
      return;
    }
    final message = await _viewModel.exitListenMode();
    if (!mounted) {
      return;
    }
    if (message != null) {
      _showMessage(message);
      return;
    }
    _tvPlaybackInitialFocusRequested = false;
    _mutate(() {
      _displayMode = _MediaPlaybackDisplayMode.video;
    });
  }

  void _setCastingSurfaceOpen(bool value) {
    if (_castingSurfaceOpen == value) {
      return;
    }
    if (!mounted) {
      _castingSurfaceOpen = value;
      return;
    }
    _mutate(() {
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
    _mutate(() {
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
    _mutate(() {
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
      _mutate(() {
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
    _mutate(() {
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
    _mutate(() {
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
}
