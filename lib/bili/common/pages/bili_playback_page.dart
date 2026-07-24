import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';
import 'package:vesper_player_ui/vesper_player_ui.dart' as vesper_ui;

import 'package:bilibili_player/app/system_presentation.dart';
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

enum BiliPlaybackPresentationMode { phone, tv }

enum TvPlaybackPanelType { none, quality, speed, subtitles, pages }

enum _PlaybackInfoTab { intro, comments }

class BiliPlaybackPage extends StatefulWidget {
  const BiliPlaybackPage({
    super.key,
    required this.detail,
    required this.initialPage,
    required this.client,
    required this.historyStore,
    this.offlineController,
    this.initialResolvedPlayback,
    this.initialPositionMs = 0,
    this.presentationMode = BiliPlaybackPresentationMode.phone,
  });

  final BiliVideoDetail detail;
  final BiliVideoPageEntry initialPage;
  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliOfflineDownloadController? offlineController;
  final BiliResolvedPlayback? initialResolvedPlayback;
  final int initialPositionMs;
  final BiliPlaybackPresentationMode presentationMode;

  @override
  State<BiliPlaybackPage> createState() => _BiliPlaybackPageState();
}

class _BiliPlaybackPageState extends State<BiliPlaybackPage>
    with SingleTickerProviderStateMixin {
  late final BiliPlaybackViewModel _viewModel;
  late final TabController _infoTabController;
  bool _settingsSurfaceOpen = false;
  bool _castingSurfaceOpen = false;
  bool _dlnaPickerOpen = false;
  bool _introExpanded = false;
  _PlaybackInfoTab _selectedInfoTab = _PlaybackInfoTab.intro;
  BiliVideoComment? _openedCommentReplies;
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
  String? _openingRelatedBvid;
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
  bool _playbackRecoveryDialogVisible = false;

  bool get _isTvMode =>
      widget.presentationMode == BiliPlaybackPresentationMode.tv;

  bool get _tvPanelOpen => _tvPanel != TvPlaybackPanelType.none;

  @override
  void initState() {
    super.initState();
    _infoTabController = TabController(length: 2, vsync: this)
      ..addListener(_handleInfoTabChanged);
    _commentsScrollController.addListener(_handleCommentsScrollPosition);
    _commentRepliesScrollController.addListener(
      _handleCommentRepliesScrollPosition,
    );
    _viewModel = BiliPlaybackViewModel(
      detail: widget.detail,
      initialPage: widget.initialPage,
      client: widget.client,
      historyStore: widget.historyStore,
      offlineController: widget.offlineController,
      initialResolvedPlayback: widget.initialResolvedPlayback,
      initialPositionMs: widget.initialPositionMs,
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
    _infoTabController.removeListener(_handleInfoTabChanged);
    _infoTabController.dispose();
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

  List<BiliVideoComment> get _comments => _viewModel.comments;

  bool get _commentsLoading => _viewModel.commentsLoading;

  bool get _commentsLoadingMore => _viewModel.commentsLoadingMore;

  bool get _commentsHasMore => _viewModel.commentsHasMore;

  List<BiliVideoComment> get _commentReplies => _viewModel.commentReplies;

  bool get _commentRepliesLoading => _viewModel.commentRepliesLoading;

  bool get _commentRepliesLoadingMore => _viewModel.commentRepliesLoadingMore;

  bool get _commentRepliesHasMore => _viewModel.commentRepliesHasMore;

  String? get _commentRepliesError => _viewModel.commentRepliesError;

  int? get _commentRepliesTotalCount => _viewModel.commentRepliesTotalCount;

  bool get _commentSubmitting => _viewModel.commentSubmitting;

  String? get _commentsError => _viewModel.commentsError;

  List<BiliFeedVideo> get _relatedVideos => _viewModel.relatedVideos;

  bool get _relatedVideosLoading => _viewModel.relatedVideosLoading;

  String? get _relatedVideosError => _viewModel.relatedVideosError;

  String get _coinCountLabel => _viewModel.coinCountLabel;

  String get _shareCountLabel => _viewModel.shareCountLabel;

  int get _sentCoinCount => _viewModel.sentCoinCount;

  BiliEngagementAction? get _pendingEngagementAction =>
      _viewModel.pendingEngagementAction;

  bool get _isInWatchLater => _viewModel.isInWatchLater;

  bool get _watchLaterLoading => _viewModel.watchLaterLoading;

  int? get _selectedBiliQualityId => _viewModel.selectedBiliQualityId;

  BiliCodecStrategy get _selectedCodecStrategy =>
      _viewModel.selectedCodecStrategy;

  BiliDlnaState get _dlnaState => _viewModel.dlnaState;

  BiliExternalPlaybackManager get _dlnaManager => _viewModel.dlnaManager;

  BiliOfflineDownloadController get _offlineController =>
      _viewModel.offlineController;

  String get _ownerSubtitle => _viewModel.ownerSubtitle;

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

  void _toggleIntroExpanded() {
    setState(() {
      _introExpanded = !_introExpanded;
    });
  }

  void _handleInfoTabChanged() {
    _syncSelectedInfoTab(_tabForInfoIndex(_infoTabController.index));
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
    return _openedCommentReplies == null
        ? _commentsScrollController
        : _commentRepliesScrollController;
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
        _openedCommentReplies == null ||
        !_commentRepliesScrollController.hasClients) {
      return;
    }
    final position = _commentRepliesScrollController.position;
    if (position.maxScrollExtent - position.pixels <= 360) {
      unawaited(_loadMoreCommentReplies());
    }
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

  Future<void> _showViewModelMessage(Future<String?> operation) async {
    final message = await operation;
    if (message != null && mounted) {
      _showMessage(message);
    }
  }

  Future<void> _reloadCurrentPage() {
    return _viewModel.reloadCurrentPage();
  }

  Future<void> _reloadRelatedVideos() {
    return _viewModel.loadRelatedVideos();
  }

  Future<void> _reloadComments() {
    return _viewModel.loadComments();
  }

  Future<void> _loadMoreComments() {
    return _viewModel.loadMoreComments();
  }

  Future<void> _loadMoreCommentReplies() {
    return _viewModel.loadMoreCommentReplies();
  }

  Future<void> _retryCommentReplies() {
    final rootComment = _openedCommentReplies;
    if (rootComment == null) {
      return Future<void>.value();
    }
    return _viewModel.retryCommentReplies(rootComment);
  }

  Future<void> _toggleLike() {
    return _showViewModelMessage(_viewModel.toggleLike());
  }

  Future<void> _addCoin() {
    return _showViewModelMessage(_viewModel.addCoin());
  }

  Future<void> _toggleFavorite() {
    return _showViewModelMessage(_viewModel.toggleFavorite());
  }

  Future<void> _toggleFollow() {
    return _showViewModelMessage(_viewModel.toggleFollow());
  }

  Future<void> _toggleWatchLater() {
    return _showViewModelMessage(_viewModel.toggleWatchLater());
  }

  Future<void> _shareVideo() {
    return _showViewModelMessage(_viewModel.shareVideo());
  }

  Future<void> _submitComment(String rawMessage) async {
    final message = rawMessage.trim();
    if (message.isEmpty) {
      _showMessage('评论内容不能为空');
      return;
    }
    final result = await _viewModel.submitComment(message);
    if (!mounted || result == null) {
      return;
    }
    if (result == '已发送评论') {
      _commentComposerController.clear();
      _commentComposerFocusNode.unfocus();
      if (_commentsScrollController.hasClients) {
        unawaited(
          _commentsScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    }
    _showMessage(result);
  }

  Future<void> _seekToCommentTime(int seconds) async {
    final controller = _viewModel.controller;
    if (controller == null) {
      _showMessage('播放器尚未准备好。');
      return;
    }
    final durationMs =
        controller.snapshot.timeline.durationMs ??
        (_selectedPage.durationSeconds > 0
            ? _selectedPage.durationSeconds * 1000
            : 0);
    if (durationMs <= 0) {
      _showMessage('当前视频暂不支持按评论时间跳转。');
      return;
    }
    final ratio = (seconds * 1000 / durationMs).clamp(0.0, 1.0).toDouble();
    await controller.seekToRatio(ratio);
    if (mounted) {
      _showMessage('已跳转到 ${biliFormatDurationSeconds(seconds)}');
    }
  }

  Future<void> _openRelatedVideo(BiliFeedVideo video) async {
    if (_openingRelatedBvid != null) {
      return;
    }
    setState(() {
      _openingRelatedBvid = video.bvid;
    });
    try {
      final detail = await widget.client.fetchVideoDetail(video.bvid);
      if (!mounted) {
        return;
      }
      final nextPage = detail.pages.isEmpty ? null : detail.pages.first;
      if (nextPage == null) {
        _showMessage('这个视频没有可播放分 P。');
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => BiliPlaybackPage(
            detail: detail,
            initialPage: nextPage,
            client: widget.client,
            historyStore: widget.historyStore,
            offlineController: widget.offlineController,
            presentationMode: widget.presentationMode,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        _showMessage('打开相关视频失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingRelatedBvid = null;
        });
      }
    }
  }

  Future<void> _showPageSelectionSheet() async {
    final pages = widget.detail.pages;
    if (pages.length <= 1 || !mounted) {
      return;
    }
    final isPgc =
        widget.detail.ownerMid <= 0 && widget.detail.ownerName == '番剧';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _PlaybackBottomSheetScaffold(
          title: isPgc
              ? '剧集 · 共 ${pages.length} 话/集'
              : '合集 · 共 ${pages.length} 个分 P',
          child: _EpisodePreviewList(
            pages: pages,
            selectedPage: _selectedPage,
            coverUrl: widget.detail.coverUrl,
            onTap: (page) async {
              Navigator.of(context).pop();
              await _switchPage(page);
            },
            isPgc: isPgc,
          ),
        );
      },
    );
  }

  void _showCommentReplies(BiliVideoComment comment) {
    if (!mounted) {
      return;
    }
    _commentComposerFocusNode.unfocus();
    setState(() {
      _openedCommentReplies = comment;
      _mobileStageCollapseOffset = 0;
    });
    unawaited(_viewModel.loadCommentReplies(comment));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _commentRepliesScrollController.hasClients) {
        _commentRepliesScrollController.jumpTo(0);
      }
    });
  }

  void _closeCommentReplies() {
    if (_openedCommentReplies == null) {
      return;
    }
    setState(() {
      _openedCommentReplies = null;
      _mobileStageCollapseOffset = _commentsScrollController.hasClients
          ? _commentsScrollController.offset
          : 0;
    });
    _viewModel.clearCommentReplies();
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
        orientations: biliLandscapeOrientations,
        systemUiMode: SystemUiMode.immersiveSticky,
        overlayStyle: biliDarkSurfaceSystemUiStyle,
      );
      return;
    }
    await _applySystemPresentation(
      orientations: biliPortraitOrientations,
      systemUiMode: SystemUiMode.edgeToEdge,
      overlayStyle: biliDarkSurfaceSystemUiStyle,
    );
  }

  Future<void> _enterFullscreenPresentation() async {
    await _applySystemPresentation(
      orientations: biliLandscapeOrientations,
      systemUiMode: SystemUiMode.immersiveSticky,
      overlayStyle: biliDarkSurfaceSystemUiStyle,
    );
  }

  Future<void> _exitFullscreenPresentation() async {
    await _applySystemPresentation(
      orientations: biliPortraitOrientations,
      systemUiMode: SystemUiMode.edgeToEdge,
      overlayStyle: biliDarkSurfaceSystemUiStyle,
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
        orientations: biliLandscapeOrientations,
        systemUiMode: SystemUiMode.immersiveSticky,
        overlayStyle: biliDarkSurfaceSystemUiStyle,
      );
      return;
    }
    await _applySystemPresentation(
      orientations: biliAppDefaultOrientations,
      systemUiMode: SystemUiMode.edgeToEdge,
      overlayStyle: biliAppSystemUiStyle,
    );
  }

  Future<void> _applySystemPresentation({
    required List<DeviceOrientation> orientations,
    required SystemUiMode systemUiMode,
    required SystemUiOverlayStyle overlayStyle,
  }) async {
    final generation = ++_presentationGeneration;
    await setBiliPreferredOrientations(orientations);
    if (generation != _presentationGeneration) {
      return;
    }
    await setBiliSystemUiMode(systemUiMode);
    if (generation != _presentationGeneration) {
      return;
    }
    setBiliSystemUiOverlayStyle(overlayStyle);
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

  Future<void> _selectSubtitle(VesperTrackSelection selection) {
    return _showViewModelMessage(_viewModel.selectSubtitle(selection));
  }

  List<double> _playbackRates(VesperPlayerSnapshot snapshot) {
    return _viewModel.playbackRates(snapshot);
  }

  List<VesperMediaTrack> _playbackSelectionTracks(
    VesperPlayerSnapshot snapshot,
  ) {
    return _viewModel.playbackSelectionTracks(snapshot);
  }

  List<VesperMediaTrack> _subtitleTracks(VesperPlayerSnapshot snapshot) {
    return _viewModel.subtitleTracks(snapshot);
  }

  VesperTrackSelection _subtitleSelection(VesperPlayerSnapshot snapshot) {
    return _viewModel.subtitleSelection(snapshot);
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

  Future<void> _showPlaybackRecoveryNotice(
    BiliPlaybackRecoveryNotice notice,
  ) async {
    if (!mounted || _playbackRecoveryDialogVisible) {
      return;
    }
    _playbackRecoveryDialogVisible = true;
    bool retry = false;
    try {
      retry =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              return AlertDialog(
                title: Text(notice.title),
                content: Text(notice.message),
                actions: <Widget>[
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
          ) ??
          false;
    } finally {
      _playbackRecoveryDialogVisible = false;
    }
    if (retry && mounted) {
      await _reloadCurrentPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: biliDarkSurfaceSystemUiStyle,
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
              child: _CollapsedPlaybackBar(
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

  List<_TvPanelOption> _tvSubtitlePanelOptions(VesperPlayerSnapshot snapshot) {
    final tracks = _subtitleTracks(snapshot);
    if (tracks.isEmpty ||
        !snapshot.capabilities.supportsSubtitleTrackSelection) {
      return const <_TvPanelOption>[];
    }
    final selection = _subtitleSelection(snapshot);
    final selectedTrackId = selection.mode == VesperTrackSelectionMode.track
        ? selection.trackId
        : null;
    return <_TvPanelOption>[
      _TvPanelOption(
        label: '关闭',
        selected: selection.mode == VesperTrackSelectionMode.disabled,
        onTap: () {
          unawaited(_selectSubtitle(const VesperTrackSelection.disabled()));
        },
      ),
      _TvPanelOption(
        label: '自动',
        selected: selection.mode == VesperTrackSelectionMode.auto,
        onTap: () {
          unawaited(_selectSubtitle(const VesperTrackSelection.auto()));
        },
      ),
      for (final track in tracks)
        _TvPanelOption(
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
        _resolvedPlayback?.subtitleTracks ?? const <BiliSubtitleTrack>[];
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
    final tracks = _playbackSelectionTracks(snapshot);
    final qualityIds = _availableBiliQualityIds(tracks);
    final currentQualityId = _currentBiliQualityId(snapshot, tracks);
    final rates = _playbackRates(snapshot);
    final subtitleOptions = _tvSubtitlePanelOptions(snapshot);
    final subtitleMessage = _tvSubtitlePanelMessage(snapshot);
    final pages = widget.detail.pages;
    final isPgc =
        widget.detail.ownerMid <= 0 && widget.detail.ownerName == '番剧';
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
      TvPlaybackPanelType.subtitles => subtitleOptions,
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
                  key: ValueKey<TvPlaybackPanelType>(_tvPanel),
                  panel: _tvPanel,
                  label: label,
                  subtitle: subtitle,
                  options: options,
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
                  const SizedBox(width: 14),
                  _TvBarButton(
                    label: '字幕',
                    icon: Icons.subtitles_outlined,
                    focusNode: _tvPanelButtonNode(
                      TvPlaybackPanelType.subtitles,
                    ),
                    onTap: () => _openTvPanel(TvPlaybackPanelType.subtitles),
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
                  const SizedBox(width: 14),
                  _TvBarButton(
                    label: _isInWatchLater ? '已加入稍后再看' : '稍后再看',
                    icon: _isInWatchLater
                        ? Icons.watch_later_rounded
                        : Icons.watch_later_outlined,
                    onTap: _watchLaterLoading
                        ? () {}
                        : () => unawaited(_toggleWatchLater()),
                  ),
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
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                if (errorMessage != null) ...[
                  _PlaybackInlineError(
                    title: '播放器错误',
                    message: errorMessage,
                    actionLabel: '重新解析',
                    onPressed: _reloadCurrentPage,
                  ),
                  const SizedBox(height: 14),
                ],
                _PlaybackContextTabs(
                  controller: _infoTabController,
                  replyCountLabel: widget.detail.replyCountLabel,
                  danmakuCountLabel: widget.detail.danmakuCountLabel,
                ),
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: _buildIntroPanel(context, snapshot),
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
    super.key,
    required this.panel,
    required this.label,
    required this.subtitle,
    required this.options,
    required this.emptyMessage,
    required this.onClose,
  });

  final TvPlaybackPanelType panel;
  final String label;
  final String subtitle;
  final List<_TvPanelOption> options;
  final String? emptyMessage;
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
          child: options.isEmpty
              ? Center(
                  child: Text(
                    emptyMessage ?? '暂无可用选项。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xA6FFFFFF),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                )
              : _TvPanelOptionList(panel: panel, options: options),
        ),
        TvFocusable(
          autofocus: options.isEmpty,
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
