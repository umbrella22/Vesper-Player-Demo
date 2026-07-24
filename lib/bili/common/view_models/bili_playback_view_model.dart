import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';

import 'package:bilibili_player/download/services/offline_download_controller.dart';
import '../../../player/player_sdk_options.dart';
import '../models/bili_models.dart';
import '../services/bili_client.dart';
import '../services/bili_history_store.dart';
import '../services/bili_text.dart';
import 'bili_external_playback_manager.dart';

enum BiliEngagementAction { like, coin, favorite, share, follow, watchLater }

enum BiliCodecStrategy {
  defaultStrategy('默认'),
  av1('AV1'),
  hevc('HEVC'),
  avc('AVC');

  const BiliCodecStrategy(this.label);

  final String label;
}

final class BiliPlaybackRecoveryNotice {
  const BiliPlaybackRecoveryNotice({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;
}

final class BiliPlaybackViewModel extends ChangeNotifier {
  BiliPlaybackViewModel({
    required this.detail,
    required BiliVideoPageEntry initialPage,
    required this.client,
    required this.historyStore,
    BiliOfflineDownloadController? offlineController,
    BiliResolvedPlayback? initialResolvedPlayback,
    int initialPositionMs = 0,
  }) : offlineController =
           offlineController ?? BiliOfflineDownloadController.instance,
       _selectedPage = initialPage,
       _coinCountLabel = detail.coinCountLabel,
       _shareCountLabel = detail.shareCountLabel,
       _pendingInitialPositionMs = initialPositionMs > 0
           ? initialPositionMs
           : null,
       _initialResolvedPlayback = initialResolvedPlayback {
    _dlnaManager = BiliExternalPlaybackManager(detail: detail)
      ..setOnChanged(_notify);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _castEventsSubscription = _externalPlaybackForCast.events.listen(
        _handleExternalPlaybackEvent,
      );
    }
    _controllerFuture = _createController();
    unawaited(loadEngagementState());
    unawaited(loadWatchLaterState());
    unawaited(loadComments());
    unawaited(loadRelatedVideos());
  }

  final BiliVideoDetail detail;
  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliOfflineDownloadController offlineController;
  BiliResolvedPlayback? _initialResolvedPlayback;
  final VesperExternalPlaybackController _externalPlaybackForCast =
      VesperExternalPlaybackController();
  static const int _maxPlaybackRecoveryAttempts = 3;
  static const List<Duration> _playbackRecoveryBackoff = <Duration>[
    Duration.zero,
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ];
  static const Duration _playbackRecoverySuccessWindow = Duration(seconds: 5);
  static const int _commentsPageSize = 20;
  static const int _commentRepliesPageSize = 20;

  late Future<VesperPlayerController> _controllerFuture;
  VesperPlayerController? _controller;
  int? _pendingInitialPositionMs;
  BiliVideoPageEntry _selectedPage;
  String _coinCountLabel;
  String _shareCountLabel;
  BiliResolvedPlayback? _resolvedPlayback;
  BiliVideoEngagement? _engagement;
  List<BiliVideoComment> _comments = const <BiliVideoComment>[];
  List<BiliVideoComment> _commentReplies = const <BiliVideoComment>[];
  List<BiliFeedVideo> _relatedVideos = const <BiliFeedVideo>[];
  bool _engagementLoading = false;
  bool _commentsLoading = false;
  bool _commentsLoadingMore = false;
  bool _commentsHasMore = false;
  bool _commentRepliesLoading = false;
  bool _commentRepliesLoadingMore = false;
  bool _commentRepliesHasMore = false;
  bool _commentSubmitting = false;
  bool _relatedVideosLoading = false;
  bool _watchLaterLoading = false;
  bool _isInWatchLater = false;
  bool _watchLaterKnown = false;
  int _watchLaterRequestGeneration = 0;
  BiliEngagementAction? _pendingEngagementAction;
  String? _commentsError;
  String? _commentRepliesError;
  String? _relatedVideosError;
  int _sentCoinCount = 0;
  int _commentsPage = 0;
  int _commentRepliesPage = 0;
  int? _commentRepliesRootId;
  int? _commentRepliesTotalCount;
  int _commentRepliesRequestGeneration = 0;
  int? _selectedBiliQualityId;
  BiliCodecStrategy _selectedCodecStrategy = BiliCodecStrategy.defaultStrategy;
  VesperSystemPlaybackPermissionStatus _systemPlaybackPermissionStatus =
      VesperSystemPlaybackPermissionStatus.notRequired;
  String? _castMessage;
  String? _pendingMessage;
  BiliPlaybackRecoveryNotice? _pendingPlaybackRecoveryNotice;
  bool _castPausedLocalPlayback = false;
  bool _isFullscreen = false;
  bool _isDisposed = false;
  bool _playbackRecoveryInFlight = false;
  bool _playbackRecoveryFailureReported = false;
  bool _playbackSourceTransitionInFlight = false;
  int _playbackRecoveryAttempts = 0;
  int _playbackRecoveryGeneration = 0;
  int _controllerGeneration = 0;
  VesperPlayerError? _deferredPlaybackRecoveryError;
  StreamSubscription<VesperPlayerEvent>? _controllerEventsSubscription;
  Timer? _playbackRecoverySuccessTimer;
  StreamSubscription<VesperExternalPlaybackSessionEvent>?
  _castEventsSubscription;
  late final BiliExternalPlaybackManager _dlnaManager;

  Future<VesperPlayerController> get controllerFuture => _controllerFuture;

  VesperPlayerController? get controller => _controller;

  BiliVideoPageEntry get selectedPage => _selectedPage;

  String get coinCountLabel => _coinCountLabel;

  String get shareCountLabel => _shareCountLabel;

  BiliResolvedPlayback? get resolvedPlayback => _resolvedPlayback;

  BiliVideoEngagement? get engagement => _engagement;

  List<BiliVideoComment> get comments => _comments;

  List<BiliVideoComment> get commentReplies => _commentReplies;

  List<BiliFeedVideo> get relatedVideos => _relatedVideos;

  bool get engagementLoading => _engagementLoading;

  bool get commentsLoading => _commentsLoading;

  bool get commentsLoadingMore => _commentsLoadingMore;

  bool get commentsHasMore => _commentsHasMore;

  bool get commentRepliesLoading => _commentRepliesLoading;

  bool get commentRepliesLoadingMore => _commentRepliesLoadingMore;

  bool get commentRepliesHasMore => _commentRepliesHasMore;

  bool get commentSubmitting => _commentSubmitting;

  bool get relatedVideosLoading => _relatedVideosLoading;

  BiliEngagementAction? get pendingEngagementAction => _pendingEngagementAction;

  bool get isInWatchLater => _isInWatchLater;

  bool get watchLaterLoading => _watchLaterLoading;

  bool get watchLaterKnown => _watchLaterKnown;

  String? get commentsError => _commentsError;

  String? get commentRepliesError => _commentRepliesError;

  int? get commentRepliesTotalCount => _commentRepliesTotalCount;

  String? get relatedVideosError => _relatedVideosError;

  int get sentCoinCount => _sentCoinCount;

  int? get selectedBiliQualityId => _selectedBiliQualityId;

  BiliCodecStrategy get selectedCodecStrategy => _selectedCodecStrategy;

  VesperSystemPlaybackPermissionStatus get systemPlaybackPermissionStatus =>
      _systemPlaybackPermissionStatus;

  String? get castMessage => _castMessage;

  BiliDlnaState get dlnaState => _dlnaManager.state;

  List<VesperExternalPlaybackRoute> get dlnaRoutes => _dlnaManager.routes;

  String? get dlnaMessage => _dlnaManager.message;

  BiliExternalPlaybackManager get dlnaManager => _dlnaManager;

  bool get isFullscreen => _isFullscreen;

  String get ownerSubtitle {
    if (detail.ownerMid <= 0 && detail.ownerName == '番剧') {
      return detail.pages.length > 1 ? '${detail.pages.length} 话/集' : '番剧';
    }
    final parts = <String>[
      'UP 主',
      if (detail.pages.length > 1) '${detail.pages.length} 个分 P',
    ];
    return parts.join(' · ');
  }

  String get videoMetaLine {
    final parts = <String>[
      if (detail.playCountLabel != '--') '${detail.playCountLabel}播放',
      if (detail.publishedAtLabel != null) detail.publishedAtLabel!,
      'P${_selectedPage.pageNumber}',
    ];
    return parts.isEmpty ? 'P${_selectedPage.pageNumber}' : parts.join(' · ');
  }

  String? consumePendingMessage() {
    final message = _pendingMessage;
    _pendingMessage = null;
    return message;
  }

  BiliPlaybackRecoveryNotice? consumePendingPlaybackRecoveryNotice() {
    final notice = _pendingPlaybackRecoveryNotice;
    _pendingPlaybackRecoveryNotice = null;
    return notice;
  }

  void setFullscreen(bool value) {
    if (_isFullscreen == value) {
      return;
    }
    _isFullscreen = value;
    _notify();
  }

  Future<VesperPlayerController> _createController() async {
    final generation = ++_controllerGeneration;
    VesperPlayerController? nextController;
    try {
      final initialResolved = _initialResolvedPlayback;
      _initialResolvedPlayback = null;
      final resolved =
          initialResolved != null && initialResolved.cid == _selectedPage.cid
          ? initialResolved
          : await client.resolvePlayback(
              detail: detail,
              page: _selectedPage,
              platform: defaultTargetPlatform,
            );
      _resolvedPlayback = resolved;
      _notify();

      final sourceNormalizerConfiguration =
          await biliPlayerSourceNormalizerConfiguration();
      nextController = await VesperPlayerController.create(
        initialSource: resolved.toSource(),
        resiliencePolicy: biliPlayerResiliencePolicy,
        trackPreferencePolicy: biliPlayerTrackPreferencePolicy,
        preloadBudgetPolicy: biliPlayerPreloadBudgetPolicy,
        benchmarkConfiguration: biliPlayerBenchmarkConfiguration(),
        sourceNormalizerConfiguration: sourceNormalizerConfiguration,
      );
      _resetPlaybackRecoveryState(clearPendingNotice: true);
      await _replaceControllerEventSubscription(nextController, generation);
      await nextController.initialize();
      final initialPositionMs = _pendingInitialPositionMs;
      if (initialPositionMs != null) {
        _pendingInitialPositionMs = null;
        final timeline = nextController.snapshot.timeline;
        final fallbackDurationMs = _selectedPage.durationSeconds > 0
            ? _selectedPage.durationSeconds * 1000
            : null;
        final durationMs = timeline.durationMs ?? fallbackDurationMs;
        final resumePositionMs =
            durationMs != null &&
                durationMs > 0 &&
                initialPositionMs >= durationMs - 3000
            ? 0
            : durationMs == null || durationMs <= 0
            ? initialPositionMs
            : initialPositionMs.clamp(0, durationMs - 1).toInt();
        if (resumePositionMs > 0) {
          try {
            await nextController.seekBy(resumePositionMs - timeline.positionMs);
          } catch (error) {
            _emitMessage('恢复历史播放位置失败：$error');
          }
        }
      }
      await _configureSystemPlayback(nextController, resolved);
      _controller = nextController;
      await nextController.play();
      if (nextController.snapshot.lastError case final lastError?) {
        _handleControllerError(lastError, generation);
      }

      if (_isDisposed) {
        await nextController.dispose();
      } else {
        _notify();
      }
      return nextController;
    } catch (_) {
      if (nextController != null) {
        await nextController.dispose();
      }
      if (_controllerGeneration == generation) {
        _controller = null;
      }
      rethrow;
    }
  }

  Future<void> reloadCurrentPage() async {
    _controllerGeneration += 1;
    _resetPlaybackRecoveryState(clearPendingNotice: true);
    final previous = _controller;
    final previousSnapshot = previous?.snapshot;
    _controller = null;
    if (previous != null && previousSnapshot != null) {
      if (previousSnapshot.lastError != null) {
        unawaited(_persistHistory(previousSnapshot));
      } else {
        await _persistLatestHistory(previous, fallback: previousSnapshot);
      }
    }
    if (previous != null) {
      await _disposeController(previous);
    }
    if (_isDisposed) {
      return;
    }
    _controllerFuture = _createController();
    _notify();
  }

  Future<void> loadEngagementState() async {
    if (_engagementLoading) {
      return;
    }
    _engagementLoading = true;
    _notify();
    try {
      _engagement = await client.fetchVideoEngagement(detail);
      if (_engagement?.isAuthenticated ?? false) {
        _sentCoinCount = await client.fetchVideoCoinCount(detail);
      }
    } catch (_) {
      // Engagement is optional for guests and can fail independently of playback.
    } finally {
      _engagementLoading = false;
      _notify();
    }
  }

  Future<void> loadComments() async {
    if (_commentsLoading || _commentsLoadingMore) {
      return;
    }
    _commentsLoading = true;
    _commentsError = null;
    _commentsPage = 0;
    _commentsHasMore = false;
    _notify();
    try {
      final page = await client.fetchVideoCommentPage(
        detail,
        page: 1,
        pageSize: _commentsPageSize,
      );
      _comments = page.comments;
      _commentsPage = page.page;
      _commentsHasMore = page.hasMore;
    } catch (error) {
      _commentsError = '评论加载失败：$error';
    } finally {
      _commentsLoading = false;
      _notify();
    }
  }

  Future<void> loadMoreComments() async {
    if (_commentsLoading || _commentsLoadingMore || !_commentsHasMore) {
      return;
    }
    _commentsLoadingMore = true;
    _commentsError = null;
    _notify();
    try {
      final nextPage = _commentsPage <= 0 ? 1 : _commentsPage + 1;
      final page = await client.fetchVideoCommentPage(
        detail,
        page: nextPage,
        pageSize: _commentsPageSize,
      );
      final seenIds = _comments.map((comment) => comment.id).toSet();
      final additions = page.comments
          .where((comment) => seenIds.add(comment.id))
          .toList(growable: false);
      if (additions.isEmpty) {
        _commentsHasMore = false;
      } else {
        _comments = <BiliVideoComment>[..._comments, ...additions];
        _commentsPage = page.page;
        _commentsHasMore = page.hasMore;
      }
    } catch (error) {
      _commentsError = '加载更多评论失败：$error';
    } finally {
      _commentsLoadingMore = false;
      _notify();
    }
  }

  Future<void> loadCommentReplies(BiliVideoComment rootComment) async {
    final rootReplyId = rootComment.id;
    final generation = ++_commentRepliesRequestGeneration;
    _commentRepliesRootId = rootReplyId;
    _commentReplies = rootComment.replies;
    _commentRepliesPage = 0;
    _commentRepliesTotalCount = rootComment.replyCount > 0
        ? rootComment.replyCount
        : rootComment.replies.length;
    _commentRepliesHasMore =
        _commentRepliesTotalCount! > rootComment.replies.length;
    _commentRepliesLoading = true;
    _commentRepliesLoadingMore = false;
    _commentRepliesError = null;
    _notify();
    try {
      final page = await client.fetchVideoCommentReplyPage(
        detail,
        rootReplyId: rootReplyId,
        page: 1,
        pageSize: _commentRepliesPageSize,
      );
      if (!_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        return;
      }
      _commentReplies = page.replies;
      _commentRepliesPage = page.page;
      _commentRepliesTotalCount =
          page.totalCount ??
          (rootComment.replyCount > 0
              ? rootComment.replyCount
              : page.replies.length);
      _commentRepliesHasMore = page.hasMore;
    } catch (error) {
      if (!_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        return;
      }
      _commentRepliesError = '回复加载失败：$error';
    } finally {
      if (_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        _commentRepliesLoading = false;
        _notify();
      }
    }
  }

  Future<void> loadMoreCommentReplies() async {
    final rootReplyId = _commentRepliesRootId;
    if (rootReplyId == null ||
        _commentRepliesLoading ||
        _commentRepliesLoadingMore ||
        !_commentRepliesHasMore) {
      return;
    }
    final generation = _commentRepliesRequestGeneration;
    _commentRepliesLoadingMore = true;
    _commentRepliesError = null;
    _notify();
    try {
      final nextPage = _commentRepliesPage <= 0 ? 1 : _commentRepliesPage + 1;
      final page = await client.fetchVideoCommentReplyPage(
        detail,
        rootReplyId: rootReplyId,
        page: nextPage,
        pageSize: _commentRepliesPageSize,
      );
      if (!_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        return;
      }
      final seenIds = _commentReplies.map((reply) => reply.id).toSet();
      final additions = page.replies
          .where((reply) => seenIds.add(reply.id))
          .toList(growable: false);
      if (additions.isEmpty) {
        _commentRepliesHasMore = false;
      } else {
        _commentReplies = <BiliVideoComment>[..._commentReplies, ...additions];
        _commentRepliesPage = page.page;
        _commentRepliesTotalCount = page.totalCount ?? _commentReplies.length;
        _commentRepliesHasMore = page.hasMore;
      }
    } catch (error) {
      if (!_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        return;
      }
      _commentRepliesError = '加载更多回复失败：$error';
    } finally {
      if (_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        _commentRepliesLoadingMore = false;
        _notify();
      }
    }
  }

  Future<void> retryCommentReplies(BiliVideoComment rootComment) {
    if (_commentRepliesRootId != rootComment.id || _commentRepliesPage <= 0) {
      return loadCommentReplies(rootComment);
    }
    return loadMoreCommentReplies();
  }

  void clearCommentReplies() {
    _commentRepliesRequestGeneration += 1;
    _commentRepliesRootId = null;
    _commentReplies = const <BiliVideoComment>[];
    _commentRepliesPage = 0;
    _commentRepliesTotalCount = null;
    _commentRepliesHasMore = false;
    _commentRepliesLoading = false;
    _commentRepliesLoadingMore = false;
    _commentRepliesError = null;
    _notify();
  }

  bool _isCurrentCommentRepliesRequest(int rootReplyId, int generation) {
    return !_isDisposed &&
        _commentRepliesRootId == rootReplyId &&
        _commentRepliesRequestGeneration == generation;
  }

  Future<String?> submitComment(String message) async {
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) {
      return '评论内容不能为空';
    }
    if (_commentSubmitting) {
      return null;
    }

    _commentSubmitting = true;
    _notify();
    try {
      final comment = await client.addVideoComment(
        detail: detail,
        message: normalizedMessage,
      );
      if (comment == null) {
        await loadComments();
      } else {
        _comments = <BiliVideoComment>[comment, ..._comments];
      }
      return '已发送评论';
    } catch (error) {
      return '评论发送失败：$error';
    } finally {
      _commentSubmitting = false;
      _notify();
    }
  }

  Future<void> loadRelatedVideos() async {
    if (_relatedVideosLoading) {
      return;
    }
    _relatedVideosLoading = true;
    _relatedVideosError = null;
    _notify();
    try {
      var videos = await client.fetchRelatedVideos(detail);
      if (videos.isEmpty) {
        videos = await _fetchFallbackRecommendedVideos();
      }
      _relatedVideos = videos
          .where((item) => item.bvid != detail.bvid)
          .take(12)
          .toList(growable: false);
    } catch (error) {
      try {
        _relatedVideos = await _fetchFallbackRecommendedVideos();
        if (_relatedVideos.isEmpty) {
          _relatedVideosError = '相关视频加载失败：$error';
        }
      } catch (_) {
        _relatedVideosError = '相关视频加载失败：$error';
      }
    } finally {
      _relatedVideosLoading = false;
      _notify();
    }
  }

  Future<List<BiliFeedVideo>> _fetchFallbackRecommendedVideos() async {
    final videos = await client.fetchRecommendedFeed();
    return videos
        .where((item) => item.bvid != detail.bvid)
        .take(12)
        .toList(growable: false);
  }

  Future<String?> toggleLike() {
    return _runEngagementAction(BiliEngagementAction.like, () async {
      final current = _engagement ?? await client.fetchVideoEngagement(detail);
      final nextLiked = !current.isLiked;
      _engagement = await client.setVideoLike(
        detail: detail,
        liked: nextLiked,
        current: current,
      );
      return _engagement!.isLiked ? '已点赞' : '已取消点赞';
    });
  }

  Future<String?> addCoin() {
    return _runEngagementAction(BiliEngagementAction.coin, () async {
      final current = _engagement ?? await client.fetchVideoEngagement(detail);
      final coinCount = await client.addVideoCoin(detail: detail);
      _sentCoinCount = coinCount;
      _engagement = current.copyWith(isAuthenticated: true, isLiked: true);
      if (_coinCountLabel == '--') {
        _coinCountLabel = detail.coinCountLabel;
      }
      return coinCount > 1 ? '已投 $coinCount 个币' : '已投币';
    });
  }

  Future<String?> toggleFavorite() {
    return _runEngagementAction(BiliEngagementAction.favorite, () async {
      final current = _engagement ?? await client.fetchVideoEngagement(detail);
      final nextFavorited = !current.isFavorited;
      _engagement = await client.setVideoFavorite(
        detail: detail,
        favorited: nextFavorited,
        current: current,
      );
      return _engagement!.isFavorited ? '已收藏' : '已取消收藏';
    });
  }

  Future<String?> toggleFollow() {
    return _runEngagementAction(BiliEngagementAction.follow, () async {
      final current = _engagement ?? await client.fetchVideoEngagement(detail);
      final nextFollowing = !current.isFollowingOwner;
      _engagement = await client.setOwnerFollow(
        detail: detail,
        following: nextFollowing,
        current: current,
      );
      return _engagement!.isFollowingOwner ? '已关注 UP 主' : '已取消关注';
    });
  }

  Future<void> loadWatchLaterState() async {
    final generation = ++_watchLaterRequestGeneration;
    if (_isDisposed) {
      return;
    }
    if (!client.hasAuthenticatedSession) {
      _watchLaterKnown = false;
      return;
    }
    _watchLaterLoading = true;
    _notify();
    try {
      final bvid = _selectedPage.bvid ?? detail.bvid;
      final isInWatchLater = await client.isVideoInWatchLater(
        bvid: bvid,
        aid: _selectedPage.aid ?? detail.aid,
      );
      if (_isDisposed || generation != _watchLaterRequestGeneration) {
        return;
      }
      _isInWatchLater = isInWatchLater;
      _watchLaterKnown = true;
    } catch (_) {
      // Membership is optional; an unavailable list must not block playback.
      if (!_isDisposed && generation == _watchLaterRequestGeneration) {
        _watchLaterKnown = false;
      }
    } finally {
      if (!_isDisposed && generation == _watchLaterRequestGeneration) {
        _watchLaterLoading = false;
        _notify();
      }
    }
  }

  Future<String?> toggleWatchLater() {
    return _runEngagementAction(BiliEngagementAction.watchLater, () async {
      if (!client.hasAuthenticatedSession) {
        return '请先登录 Bilibili 后使用稍后再看。';
      }
      final bvid = _selectedPage.bvid ?? detail.bvid;
      final aid = _selectedPage.aid ?? detail.aid;
      if (bvid.trim().isEmpty && aid <= 0) {
        return '缺少视频 ID，无法操作稍后再看。';
      }
      final next = !_isInWatchLater;
      if (next) {
        await client.addToWatchLater(bvid: bvid, aid: aid);
      } else {
        await client.removeFromWatchLater(bvid: bvid, aid: aid);
      }
      _isInWatchLater = next;
      _watchLaterKnown = true;
      return next ? '已加入稍后再看' : '已移出稍后再看';
    });
  }

  Future<String?> shareVideo() {
    return _runEngagementAction(BiliEngagementAction.share, () async {
      final shouldRecordShare = client.hasAuthenticatedSession;
      final shareCount = shouldRecordShare
          ? await client.recordVideoShare(detail: detail)
          : null;
      await Clipboard.setData(
        ClipboardData(
          text:
              'https://www.bilibili.com/video/${_selectedPage.bvid ?? detail.bvid}',
        ),
      );
      if (shareCount != null) {
        _shareCountLabel = biliFormatCount(shareCount.toDouble());
      }
      return shouldRecordShare ? '已分享并复制链接' : '已复制分享链接';
    });
  }

  Future<String?> _runEngagementAction(
    BiliEngagementAction action,
    Future<String?> Function() operation,
  ) async {
    if (_pendingEngagementAction != null) {
      return null;
    }
    _pendingEngagementAction = action;
    _notify();
    try {
      return await operation();
    } catch (error) {
      return '操作失败：$error';
    } finally {
      _pendingEngagementAction = null;
      _notify();
    }
  }

  Future<String?> switchPage(BiliVideoPageEntry page) async {
    final controller = _controller;
    if (controller == null || page.cid == _selectedPage.cid) {
      return null;
    }

    _playbackSourceTransitionInFlight = true;
    _resetPlaybackRecoveryState(clearPendingNotice: true);
    try {
      final currentSnapshot = controller.snapshot;
      unawaited(_persistHistory(currentSnapshot));
      final resolved = await client.resolvePlayback(
        detail: detail,
        page: page,
        platform: defaultTargetPlatform,
      );
      await controller.selectSource(resolved.toSource());
      await _configureSystemPlayback(controller, resolved);
      await controller.play();
      if (_isDisposed) {
        return null;
      }
      _selectedPage = page;
      _resolvedPlayback = resolved;
      _selectedBiliQualityId = null;
      _selectedCodecStrategy = BiliCodecStrategy.defaultStrategy;
      _isInWatchLater = false;
      _watchLaterKnown = false;
      _notify();
      unawaited(loadWatchLaterState());
      return null;
    } catch (error) {
      return '切换分 P 失败：$error';
    } finally {
      _playbackSourceTransitionInFlight = false;
    }
  }

  Future<String?> loadCurrentPageToDlna() async {
    try {
      final resolved = await _refreshCurrentResolvedPlayback();
      return _dlnaManager.loadMedia(
        resolved: resolved,
        selectedPage: _selectedPage,
        refreshResolved: _refreshCurrentResolvedPlayback,
      );
    } catch (error) {
      return '投屏播放地址刷新失败：$error';
    }
  }

  Future<BiliResolvedPlayback> _refreshCurrentResolvedPlayback() async {
    final resolved = await client.resolvePlayback(
      detail: detail,
      page: _selectedPage,
      platform: defaultTargetPlatform,
    );
    if (!_isDisposed) {
      _resolvedPlayback = resolved;
      _notify();
    }
    return resolved;
  }

  Future<void> _replaceControllerEventSubscription(
    VesperPlayerController controller,
    int generation,
  ) async {
    await _controllerEventsSubscription?.cancel();
    if (_isDisposed || generation != _controllerGeneration) {
      return;
    }
    _controllerEventsSubscription = controller.events.listen((event) {
      if (_isDisposed || generation != _controllerGeneration) {
        return;
      }
      switch (event) {
        case VesperPlayerSnapshotEvent():
          _handleControllerSnapshot(event.snapshot, generation);
        case VesperPlayerErrorEvent():
          _handleControllerError(event.error, generation);
        default:
      }
    });
  }

  void _handleControllerSnapshot(
    VesperPlayerSnapshot snapshot,
    int generation,
  ) {
    if (_isDisposed || generation != _controllerGeneration) {
      return;
    }
    if (snapshot.lastError != null) {
      _playbackRecoverySuccessTimer?.cancel();
      return;
    }
    if (_playbackRecoveryAttempts > 0 &&
        !_playbackRecoveryInFlight &&
        snapshot.playbackState == VesperPlaybackState.playing) {
      _schedulePlaybackRecoverySuccessReset(generation);
    }
  }

  void _handleControllerError(VesperPlayerError error, int generation) {
    if (_isDisposed || generation != _controllerGeneration) {
      return;
    }
    if (_playbackSourceTransitionInFlight) {
      return;
    }
    if (!_shouldAutoRecoverPlaybackSource(error)) {
      return;
    }
    _playbackRecoverySuccessTimer?.cancel();
    if (_playbackRecoveryFailureReported) {
      return;
    }
    if (_playbackRecoveryInFlight) {
      _deferredPlaybackRecoveryError = error;
      return;
    }
    if (_playbackRecoveryAttempts >= _maxPlaybackRecoveryAttempts) {
      _emitPlaybackRecoveryFailure(error.message);
      return;
    }
    unawaited(
      _attemptPlaybackRecovery(error, generation, _playbackRecoveryGeneration),
    );
  }

  bool _shouldAutoRecoverPlaybackSource(VesperPlayerError error) {
    final resolved = _resolvedPlayback;
    if (resolved == null || resolved.isLocalFile) {
      return false;
    }
    if (error.details['domain'] == 'subtitle') {
      return false;
    }
    if (error.details['keySystem'] != null ||
        error.details['domain'] == 'drm') {
      return false;
    }
    if (error.code == VesperPlayerErrorCode.invalidSource ||
        error.category == VesperPlayerErrorCategory.source) {
      return true;
    }
    if (error.code != VesperPlayerErrorCode.backendFailure ||
        (error.category != VesperPlayerErrorCategory.network &&
            error.category != VesperPlayerErrorCategory.platform)) {
      return false;
    }
    final iosHttpStatus = int.tryParse(
      '${error.details['avPlayerItemErrorStatusCode'] ?? ''}',
    );
    if (iosHttpStatus != null && iosHttpStatus >= 400 && iosHttpStatus <= 599) {
      return true;
    }
    return switch ('${error.details['errorCodeName'] ?? ''}') {
      'ERROR_CODE_IO_BAD_HTTP_STATUS' ||
      'ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE' => true,
      _ => false,
    };
  }

  Future<void> _attemptPlaybackRecovery(
    VesperPlayerError triggerError,
    int controllerGeneration,
    int recoveryGeneration,
  ) async {
    if (_isDisposed ||
        controllerGeneration != _controllerGeneration ||
        recoveryGeneration != _playbackRecoveryGeneration ||
        _playbackSourceTransitionInFlight ||
        _playbackRecoveryInFlight) {
      return;
    }
    final controller = _controller;
    final recoveryPage = _selectedPage;
    if (controller == null) {
      return;
    }

    _playbackRecoveryInFlight = true;
    _playbackRecoverySuccessTimer?.cancel();
    var lastFailureMessage = triggerError.message;
    try {
      while (!_isDisposed &&
          controllerGeneration == _controllerGeneration &&
          recoveryGeneration == _playbackRecoveryGeneration &&
          !_playbackSourceTransitionInFlight &&
          _playbackRecoveryAttempts < _maxPlaybackRecoveryAttempts) {
        final attempt = _playbackRecoveryAttempts + 1;
        _playbackRecoveryAttempts = attempt;
        _deferredPlaybackRecoveryError = null;
        final backoff = _playbackRecoveryBackoff[attempt - 1];
        if (backoff > Duration.zero) {
          await Future<void>.delayed(backoff);
          if (_isDisposed ||
              controllerGeneration != _controllerGeneration ||
              recoveryGeneration != _playbackRecoveryGeneration ||
              _playbackSourceTransitionInFlight) {
            return;
          }
        }

        final timeline = controller.snapshot.timeline;
        final resumeRatio =
            timeline.durationMs != null &&
                timeline.durationMs! > 0 &&
                timeline.positionMs > 0
            ? (timeline.positionMs / timeline.durationMs!)
                  .clamp(0.0, 1.0)
                  .toDouble()
            : null;
        try {
          final resolved = await client.resolvePlayback(
            detail: detail,
            page: recoveryPage,
            platform: defaultTargetPlatform,
          );
          if (_isDisposed ||
              controllerGeneration != _controllerGeneration ||
              recoveryGeneration != _playbackRecoveryGeneration ||
              _playbackSourceTransitionInFlight ||
              recoveryPage.cid != _selectedPage.cid) {
            return;
          }
          _resolvedPlayback = resolved;
          _notify();
          await controller.selectSource(resolved.toSource());
          await _configureSystemPlayback(controller, resolved);
          if (resumeRatio != null && resumeRatio > 0) {
            await controller.seekToRatio(resumeRatio);
          }
          await controller.play();
          if (_isDisposed ||
              controllerGeneration != _controllerGeneration ||
              recoveryGeneration != _playbackRecoveryGeneration ||
              _playbackSourceTransitionInFlight) {
            return;
          }
          await Future<void>.delayed(Duration.zero);
          final deferredError = _deferredPlaybackRecoveryError;
          if (deferredError != null) {
            lastFailureMessage = deferredError.message;
            continue;
          }
          _schedulePlaybackRecoverySuccessReset(
            controllerGeneration,
            recoveryGeneration,
          );
          return;
        } catch (error) {
          lastFailureMessage = '重新解析失败：$error';
        }
      }
    } finally {
      if (recoveryGeneration == _playbackRecoveryGeneration) {
        _playbackRecoveryInFlight = false;
      }
    }

    if (!_isDisposed &&
        controllerGeneration == _controllerGeneration &&
        recoveryGeneration == _playbackRecoveryGeneration &&
        _playbackRecoveryAttempts >= _maxPlaybackRecoveryAttempts) {
      _emitPlaybackRecoveryFailure(lastFailureMessage);
    }
  }

  void _schedulePlaybackRecoverySuccessReset(
    int controllerGeneration, [
    int? expectedRecoveryGeneration,
  ]) {
    final recoveryGeneration =
        expectedRecoveryGeneration ?? _playbackRecoveryGeneration;
    _playbackRecoverySuccessTimer?.cancel();
    _playbackRecoverySuccessTimer = Timer(_playbackRecoverySuccessWindow, () {
      if (_isDisposed ||
          controllerGeneration != _controllerGeneration ||
          recoveryGeneration != _playbackRecoveryGeneration) {
        return;
      }
      _resetPlaybackRecoveryState(clearPendingNotice: false);
      _notify();
    });
  }

  void _emitPlaybackRecoveryFailure(String failureMessage) {
    if (_playbackRecoveryFailureReported) {
      return;
    }
    _playbackRecoveryFailureReported = true;
    _pendingPlaybackRecoveryNotice = BiliPlaybackRecoveryNotice(
      title: '播放地址刷新失败',
      message: '已自动重新解析并重试 3 次，仍然无法恢复播放。\n\n$failureMessage',
    );
    _notify();
  }

  void _resetPlaybackRecoveryState({required bool clearPendingNotice}) {
    _playbackRecoveryGeneration += 1;
    _playbackRecoverySuccessTimer?.cancel();
    _playbackRecoverySuccessTimer = null;
    _playbackRecoveryInFlight = false;
    _playbackRecoveryFailureReported = false;
    _playbackRecoveryAttempts = 0;
    _deferredPlaybackRecoveryError = null;
    if (clearPendingNotice) {
      _pendingPlaybackRecoveryNotice = null;
    }
  }

  Future<void> _disposeController(VesperPlayerController controller) async {
    try {
      await controller.clearSystemPlayback();
    } catch (_) {
      // System playback is optional and may already be unavailable during tear-down.
    }
    await controller.dispose();
  }

  Future<void> _configureSystemPlayback(
    VesperPlayerController controller,
    BiliResolvedPlayback resolved,
  ) async {
    try {
      _systemPlaybackPermissionStatus = await controller
          .getSystemPlaybackPermissionStatus();
      _notify();
      await controller.configureSystemPlayback(
        biliPlayerSystemPlaybackConfiguration(
          metadata: _systemPlaybackMetadataForResolved(resolved),
        ),
      );
    } catch (error) {
      if (!_isDisposed) {
        _emitMessage('系统播放接入失败：$error');
      }
    }
  }

  Future<String?> requestSystemPlaybackPermissions(
    VesperPlayerController controller,
  ) async {
    try {
      _systemPlaybackPermissionStatus = await controller
          .requestSystemPlaybackPermissions();
      _notify();
      return null;
    } catch (error) {
      return '系统播放权限请求失败：$error';
    }
  }

  Future<void> _handleExternalPlaybackEvent(
    VesperExternalPlaybackSessionEvent event,
  ) async {
    final controller = _controller;
    final resolved = _resolvedPlayback;
    if (controller == null || resolved == null || _isDisposed) {
      return;
    }

    if (event.routeId != VesperExternalPlaybackController.castRouteId) {
      return;
    }

    switch (event.kind) {
      case VesperExternalPlaybackSessionEventKind.routeConnected:
        final result = await _externalPlaybackForCast.loadFromPlayer(
          player: controller,
          source: resolved.toSource(),
          metadata: _systemPlaybackMetadataForResolved(resolved),
        );
        if (_isDisposed) return;
        _castPausedLocalPlayback = result.isSuccess;
        _castMessage = result.isSuccess
            ? '投屏已连接：${event.routeName ?? '外部设备'}'
            : result.message ?? '当前资源暂不支持投屏。';
        _notify();
      case VesperExternalPlaybackSessionEventKind.routeDisconnected:
        if (_castPausedLocalPlayback) {
          final positionMs = event.positionMs;
          if (positionMs != null) {
            final deltaMs =
                positionMs - controller.snapshot.timeline.positionMs;
            await controller.seekBy(deltaMs);
          }
          await controller.play();
        }
        if (_isDisposed) return;
        _castPausedLocalPlayback = false;
        _castMessage = '投屏已断开，本地播放已恢复。';
        _notify();
      case VesperExternalPlaybackSessionEventKind.suspended:
        if (_isDisposed) return;
        _castMessage = '投屏连接已暂停。';
        _notify();
      default:
    }
  }

  VesperSystemPlaybackMetadata _systemPlaybackMetadataForResolved(
    BiliResolvedPlayback resolved,
  ) {
    final resolvedPage = _pageForResolvedPlayback(resolved);
    final durationSeconds = resolvedPage?.durationSeconds ?? 0;
    final durationMs = durationSeconds > 0 ? durationSeconds * 1000 : null;
    return biliPlayerSystemPlaybackMetadata(
      title: resolved.title,
      subtitle: resolved.subtitle,
      artist: detail.ownerName,
      artworkUri: _selectedPage.coverUrl ?? detail.coverUrl,
      contentUri: resolved.uri,
      durationMs: durationMs,
    );
  }

  BiliVideoPageEntry? _pageForResolvedPlayback(BiliResolvedPlayback resolved) {
    for (final page in detail.pages) {
      if (page.cid == resolved.cid) {
        return page;
      }
    }
    return null;
  }

  Future<void> _persistHistory(VesperPlayerSnapshot snapshot) {
    return historyStore.saveEntry(
      BiliPlaybackHistoryEntry(
        bvid: _selectedPage.bvid ?? detail.bvid,
        aid: _selectedPage.aid ?? detail.aid,
        cid: _selectedPage.cid,
        episodeId: _selectedPage.episodeId ?? 0,
        business: (_selectedPage.episodeId ?? 0) > 0 ? 'pgc' : null,
        videoTitle: detail.title,
        pageTitle: _selectedPage.title,
        coverUrl: _selectedPage.coverUrl ?? detail.coverUrl,
        ownerName: detail.ownerName,
        playedAtMs: DateTime.now().millisecondsSinceEpoch,
        lastPositionMs: snapshot.timeline.positionMs,
        durationMs: snapshot.timeline.durationMs,
      ),
    );
  }

  Future<void> _persistLatestHistory(
    VesperPlayerController controller, {
    required VesperPlayerSnapshot fallback,
  }) async {
    var snapshot = fallback;
    try {
      await controller.refresh();
      snapshot = controller.snapshot;
    } catch (_) {
      snapshot = fallback;
    }
    await _persistHistory(snapshot);
  }

  Future<String?> setPlaybackRate(double rate) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    try {
      await controller.setPlaybackRate(rate);
      return null;
    } catch (error) {
      return '倍速切换失败：$error';
    }
  }

  Future<String?> selectBiliQuality(int? qualityId) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final tracks = playbackSelectionTracks(controller.snapshot);
    var nextStrategy = _selectedCodecStrategy;
    String? message;
    if (qualityId != null &&
        nextStrategy != BiliCodecStrategy.defaultStrategy &&
        !hasTrackForSelection(tracks, qualityId, nextStrategy)) {
      message = '当前清晰度没有 ${_selectedCodecStrategy.label}，已使用默认策略。';
      nextStrategy = BiliCodecStrategy.defaultStrategy;
    }

    _selectedBiliQualityId = qualityId;
    _selectedCodecStrategy = nextStrategy;
    _notify();
    return await applyBiliPlaybackSelection() ?? message;
  }

  Future<String?> selectCodecStrategy(BiliCodecStrategy strategy) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final tracks = playbackSelectionTracks(controller.snapshot);
    if (strategy != BiliCodecStrategy.defaultStrategy &&
        !hasTrackForSelection(tracks, _selectedBiliQualityId, strategy)) {
      return '当前分辨率没有 ${strategy.label} 策略。';
    }

    _selectedCodecStrategy = strategy;
    _notify();
    return applyBiliPlaybackSelection();
  }

  Future<String?> applyBiliPlaybackSelection() async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    try {
      if (_selectedBiliQualityId == null &&
          _selectedCodecStrategy == BiliCodecStrategy.defaultStrategy) {
        await controller.setAbrPolicy(const VesperAbrPolicy.auto());
        return null;
      }

      final snapshot = controller.snapshot;
      final track = _selectBestTrackForPlaybackSelection(snapshot);
      if (track == null) {
        return '当前视频没有可用的清晰度轨道。';
      }
      if (_hasNativeVideoTrack(snapshot, track.id)) {
        await controller.setAbrPolicy(VesperAbrPolicy.fixedTrack(track.id));
        return null;
      }

      final bitRate = track.bitRate;
      if (snapshot.capabilities.supportsAbrConstrained &&
          bitRate != null &&
          bitRate > 0) {
        await controller.setAbrPolicy(
          VesperAbrPolicy.constrained(maxBitRate: bitRate),
        );
        return null;
      }

      await controller.setAbrPolicy(VesperAbrPolicy.fixedTrack(track.id));
      return null;
    } catch (error) {
      return '清晰度切换失败：$error';
    }
  }

  List<double> playbackRates(VesperPlayerSnapshot snapshot) {
    final rates = <double>{
      1.0,
      1.25,
      1.5,
      2.0,
      snapshot.playbackRate,
      ...snapshot.capabilities.supportedPlaybackRates,
    };
    final normalized = rates.where((value) => value > 0).toList()..sort();
    return normalized;
  }

  List<VesperMediaTrack> playbackSelectionTracks(
    VesperPlayerSnapshot snapshot,
  ) {
    final nativeTracks = snapshot.trackCatalog.videoTracks;
    if (_availableBiliQualityIds(nativeTracks).isNotEmpty) {
      return nativeTracks;
    }

    final manifestTracks =
        _resolvedPlayback?.videoTracks ?? const <VesperMediaTrack>[];
    if (manifestTracks.isNotEmpty) {
      return manifestTracks;
    }

    return nativeTracks;
  }

  List<VesperMediaTrack> subtitleTracks(VesperPlayerSnapshot snapshot) {
    return snapshot.trackCatalog.subtitleTracks;
  }

  VesperTrackSelection subtitleSelection(VesperPlayerSnapshot snapshot) {
    return snapshot.trackSelection.confirmedSubtitle;
  }

  Future<String?> selectSubtitle(VesperTrackSelection selection) async {
    final controller = _controller;
    if (controller == null) {
      return '播放器尚未准备好。';
    }
    final snapshot = controller.snapshot;
    if (!snapshot.capabilities.supportsSubtitleTrackSelection) {
      return '当前播放内核不支持字幕切换。';
    }
    try {
      await controller.setSubtitleTrackSelection(selection);
      _notify();
      return null;
    } on VesperSubtitleException catch (error) {
      return '字幕切换失败：${error.message}';
    } catch (error) {
      return '字幕切换失败：$error';
    }
  }

  List<int> availableBiliQualityIds(List<VesperMediaTrack> tracks) {
    return _availableBiliQualityIds(tracks);
  }

  bool hasTrackForSelection(
    List<VesperMediaTrack> tracks,
    int? qualityId,
    BiliCodecStrategy strategy,
  ) {
    return tracks.any((track) {
      if (qualityId != null && _biliQualityIdForTrack(track) != qualityId) {
        return false;
      }
      return _codecStrategyForTrack(track) == strategy;
    });
  }

  BiliVideoCodecPreference currentDownloadCodecPreference() {
    return switch (_selectedCodecStrategy) {
      BiliCodecStrategy.defaultStrategy => BiliVideoCodecPreference.automatic,
      BiliCodecStrategy.av1 => BiliVideoCodecPreference.av1,
      BiliCodecStrategy.hevc => BiliVideoCodecPreference.hevc,
      BiliCodecStrategy.avc => BiliVideoCodecPreference.avc,
    };
  }

  String playbackStateLabel(VesperPlayerSnapshot snapshot) {
    return switch (snapshot.playbackState) {
      VesperPlaybackState.ready => '就绪',
      VesperPlaybackState.playing => '播放中',
      VesperPlaybackState.paused => '已暂停',
      VesperPlaybackState.finished => '已结束',
    };
  }

  String? biliQualityLabelFromQualityId(int qualityId) {
    return switch (qualityId) {
      127 => '8K 超高清',
      126 => '杜比视界',
      125 => 'HDR 真彩',
      120 => '4K 超清',
      116 => '1080P60',
      112 => '1080P 高码率',
      80 => '1080P',
      74 => '720P60',
      64 => '720P',
      32 => '480P',
      16 => '360P',
      6 => '240P',
      _ => null,
    };
  }

  int? biliQualityIdForTrack(VesperMediaTrack track) {
    return _biliQualityIdForTrack(track);
  }

  bool _hasNativeVideoTrack(VesperPlayerSnapshot snapshot, String trackId) {
    return snapshot.trackCatalog.videoTracks.any(
      (track) => track.id == trackId,
    );
  }

  VesperMediaTrack? _selectBestTrackForPlaybackSelection(
    VesperPlayerSnapshot snapshot,
  ) {
    final tracks = _sortedVideoTracks(playbackSelectionTracks(snapshot));
    Iterable<VesperMediaTrack> candidates = tracks;
    final selectedQualityId = _selectedBiliQualityId;
    if (selectedQualityId != null) {
      candidates = candidates.where(
        (track) => _biliQualityIdForTrack(track) == selectedQualityId,
      );
    }

    final strategy = _selectedCodecStrategy;
    if (strategy != BiliCodecStrategy.defaultStrategy) {
      final strategyMatches = candidates
          .where((track) => _codecStrategyForTrack(track) == strategy)
          .toList(growable: false);
      if (strategyMatches.isNotEmpty) {
        return strategyMatches.first;
      }
    }

    for (final candidate in candidates) {
      return candidate;
    }
    return null;
  }

  List<int> _availableBiliQualityIds(List<VesperMediaTrack> tracks) {
    final qualityIds = <int>{};
    for (final track in tracks) {
      final qualityId = _biliQualityIdForTrack(track);
      if (qualityId != null) {
        qualityIds.add(qualityId);
      }
    }
    final sorted = qualityIds.toList();
    sorted.sort(
      (left, right) =>
          _biliQualityRank(right).compareTo(_biliQualityRank(left)),
    );
    return sorted;
  }

  int _biliQualityRank(int qualityId) {
    return switch (qualityId) {
      127 => 1200,
      126 => 1190,
      125 => 1180,
      120 => 1100,
      116 => 1000,
      112 => 990,
      80 => 900,
      74 => 800,
      64 => 700,
      32 => 600,
      16 => 500,
      6 => 400,
      _ => qualityId,
    };
  }

  List<VesperMediaTrack> _sortedVideoTracks(List<VesperMediaTrack> tracks) {
    final sorted = List<VesperMediaTrack>.of(tracks);
    sorted.sort((left, right) {
      final qualityCompare = (_biliQualityIdForTrack(right) ?? 0).compareTo(
        _biliQualityIdForTrack(left) ?? 0,
      );
      if (qualityCompare != 0) {
        return qualityCompare;
      }

      final heightCompare = (right.height ?? 0).compareTo(left.height ?? 0);
      if (heightCompare != 0) {
        return heightCompare;
      }

      final bitRateCompare = (right.bitRate ?? 0).compareTo(left.bitRate ?? 0);
      if (bitRateCompare != 0) {
        return bitRateCompare;
      }

      return _videoTrackLabel(left).compareTo(_videoTrackLabel(right));
    });
    return sorted;
  }

  BiliCodecStrategy? _codecStrategyForTrack(VesperMediaTrack track) {
    final codec = track.codec?.toLowerCase() ?? '';
    if (codec.contains('av01')) {
      return BiliCodecStrategy.av1;
    }
    if (codec.contains('hev1') ||
        codec.contains('hvc1') ||
        codec.contains('dvh1') ||
        codec.contains('dvhe')) {
      return BiliCodecStrategy.hevc;
    }
    if (codec.contains('avc1')) {
      return BiliCodecStrategy.avc;
    }

    final codecId = _biliCodecIdFromTrackId(track.id);
    return switch (codecId) {
      13 => BiliCodecStrategy.av1,
      12 => BiliCodecStrategy.hevc,
      7 => BiliCodecStrategy.avc,
      _ => null,
    };
  }

  String _videoTrackLabel(VesperMediaTrack track) {
    final parts = <String>[];
    final biliQualityLabel = _biliQualityLabelFromTrack(track);
    if (biliQualityLabel != null) {
      parts.add(biliQualityLabel);
    } else if (track.label != null && track.label!.trim().isNotEmpty) {
      parts.add(track.label!.trim());
    } else if (track.width != null && track.height != null) {
      parts.add('${track.width}x${track.height}');
    } else if (track.height != null) {
      parts.add('${track.height}p');
    }
    final codecLabel = _codecLabel(track.codec);
    if (codecLabel != null) {
      parts.add(codecLabel);
    }
    if (track.frameRate != null && track.frameRate! >= 50) {
      parts.add('${track.frameRate!.round()}fps');
    }
    if (track.bitRate != null) {
      parts.add('${(track.bitRate! / 1000).round()} kbps');
    }
    return parts.isEmpty ? track.id : parts.join(' · ');
  }

  String? _biliQualityLabelFromTrack(VesperMediaTrack track) {
    final qualityId = _biliQualityIdForTrack(track);
    return qualityId == null ? null : biliQualityLabelFromQualityId(qualityId);
  }

  int? _biliQualityIdForTrack(VesperMediaTrack track) {
    return _biliQualityIdFromTrackId(track.id) ??
        _biliQualityIdFromTrackLabel(track.label) ??
        _biliQualityIdFromTrackShape(track);
  }

  int? _biliQualityIdFromTrackId(String trackId) {
    final match = RegExp(r'^video-(\d+)-').firstMatch(trackId);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    final nestedMatch = RegExp(r':video-(\d+)-').firstMatch(trackId);
    if (nestedMatch != null) {
      return int.tryParse(nestedMatch.group(1)!);
    }
    return int.tryParse(trackId);
  }

  int? _biliQualityIdFromTrackLabel(String? label) {
    final value = label?.toLowerCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.contains('8k')) {
      return 127;
    }
    if (value.contains('4k') || value.contains('2160')) {
      return 120;
    }
    if (value.contains('1080') && value.contains('60')) {
      return 116;
    }
    if (value.contains('1080')) {
      return 80;
    }
    if (value.contains('720') && value.contains('60')) {
      return 74;
    }
    if (value.contains('720')) {
      return 64;
    }
    if (value.contains('480')) {
      return 32;
    }
    if (value.contains('360')) {
      return 16;
    }
    if (value.contains('240')) {
      return 6;
    }
    return null;
  }

  int? _biliQualityIdFromTrackShape(VesperMediaTrack track) {
    final height = track.height;
    if (height == null || height <= 0) {
      return null;
    }

    final frameRate = track.frameRate ?? 0;
    if (height >= 4320) {
      return 127;
    }
    if (height >= 2160) {
      return 120;
    }
    if (height >= 1080) {
      return frameRate >= 50 ? 116 : 80;
    }
    if (height >= 720) {
      return frameRate >= 50 ? 74 : 64;
    }
    if (height >= 480) {
      return 32;
    }
    if (height >= 360) {
      return 16;
    }
    return 6;
  }

  int? _biliCodecIdFromTrackId(String trackId) {
    final match = RegExp(r'(?:^|:)video-\d+-(\d+)-').firstMatch(trackId);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  String? _codecLabel(String? codec) {
    final value = codec?.toLowerCase() ?? '';
    if (value.contains('dvh1') || value.contains('dvhe')) {
      return 'Dolby Vision';
    }
    if (value.contains('av01')) {
      return 'AV1';
    }
    if (value.contains('hev1') || value.contains('hvc1')) {
      return 'HEVC';
    }
    if (value.contains('avc1')) {
      return 'AVC';
    }
    return null;
  }

  void _emitMessage(String message) {
    _pendingMessage = message;
    _notify();
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _playbackRecoverySuccessTimer?.cancel();
    final controller = _controller;
    final snapshot = controller?.snapshot;
    if (controller != null && snapshot != null) {
      unawaited(_persistLatestHistory(controller, fallback: snapshot));
    }
    unawaited(_controllerEventsSubscription?.cancel() ?? Future<void>.value());
    unawaited(_castEventsSubscription?.cancel() ?? Future<void>.value());
    _externalPlaybackForCast.dispose();
    _dlnaManager.dispose();
    _controller = null;
    if (controller != null) {
      unawaited(_disposeController(controller));
    }
    super.dispose();
  }
}
