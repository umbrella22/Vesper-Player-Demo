import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_player/vesper_player.dart';

import 'package:vesper_media/bili/bili_media_platform_adapter.dart';
import 'package:vesper_media/download/services/offline_download_controller.dart';
import 'package:vesper_media/media/media.dart';
import '../models/bili_models.dart';
import '../services/bili_api_core.dart';
import '../services/bili_client.dart';
import '../services/bili_history_store.dart';
import '../services/bili_media_mapper.dart';
import '../services/bili_platform_info.dart';
import '../services/bili_quality_mapping.dart';
import '../services/bili_text.dart';

enum BiliEngagementAction { like, coin, favorite, share, follow, watchLater }

enum BiliCodecStrategy {
  defaultStrategy('默认'),
  av1('AV1'),
  hevc('HEVC'),
  avc('AVC');

  const BiliCodecStrategy(this.label);

  final String label;
}

/// Bilibili 播放页 view model（薄包装层）。
///
/// 播放编排（控制器生命周期、解析/恢复、清晰度/倍速/字幕、DLNA、系统播放、
/// 历史）委托给 [MediaPlaybackViewModel]；本类保留 B 站内容状态——互动、
/// 评论、相关视频、稍后再看——以及面向播放页的 B 站 API 形态
/// （清晰度 ID、codec 策略枚举）。
final class BiliPlaybackViewModel {
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
       _coinCountLabel = signal(detail.coinCountLabel),
       _shareCountLabel = signal(detail.shareCountLabel),
       _engagement = signal<BiliVideoEngagement?>(null),
       _comments = signal<List<BiliVideoComment>>(const <BiliVideoComment>[]),
       _commentReplies =
           signal<List<BiliVideoComment>>(const <BiliVideoComment>[]),
       _relatedVideos = signal<List<BiliFeedVideo>>(const <BiliFeedVideo>[]) {
    final adapter = BiliMediaPlatformAdapter(
      client: client,
      historyStore: historyStore,
    );
    _playback = MediaPlaybackViewModel(
      detail: BiliMediaMapper.toGenericDetail(detail),
      initialEntry: BiliMediaMapper.toGenericEntry(
        initialPage,
        fallbackAid: detail.aid,
        fallbackBvid: detail.bvid,
      ),
      adapter: adapter,
      initialResolvedPlayback: initialResolvedPlayback == null
          ? null
          : BiliMediaMapper.toResolvedPlayback(initialResolvedPlayback),
      initialPositionMs: initialPositionMs,
      preferTextureViewForPlayback: _usesLegacyAndroidPlaybackCompatibility,
    );
    // 互动能力经 adapter 槽位消费（壳渲染动作栏）；构造完成后回填，
    // 规避 adapter 与 view model 之间的构造循环。
    adapter.attachEngagement(this);
    unawaited(loadEngagementState());
    unawaited(loadWatchLaterState());
    unawaited(loadComments());
    unawaited(loadRelatedVideos());
  }

  final BiliVideoDetail detail;
  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliOfflineDownloadController offlineController;
  late final MediaPlaybackViewModel _playback;

  /// 内部播放编排 VM（供壳页面消费；生命周期随本类 dispose）。
  MediaPlaybackViewModel get playbackViewModel => _playback;

  static const int _commentsPageSize = 20;
  static const int _commentRepliesPageSize = 20;

  final Signal<String> _coinCountLabel;
  final Signal<String> _shareCountLabel;
  final Signal<BiliVideoEngagement?> _engagement;
  final Signal<List<BiliVideoComment>> _comments;
  final Signal<List<BiliVideoComment>> _commentReplies;
  final Signal<List<BiliFeedVideo>> _relatedVideos;
  final Signal<bool> _engagementLoading = Signal<bool>(false);
  final Signal<bool> _commentsLoading = Signal<bool>(false);
  final Signal<bool> _commentsLoadingMore = Signal<bool>(false);
  final Signal<bool> _commentsHasMore = Signal<bool>(false);
  final Signal<bool> _commentRepliesLoading = Signal<bool>(false);
  final Signal<bool> _commentRepliesLoadingMore = Signal<bool>(false);
  final Signal<bool> _commentRepliesHasMore = Signal<bool>(false);
  final Signal<bool> _commentSubmitting = Signal<bool>(false);
  final Signal<bool> _relatedVideosLoading = Signal<bool>(false);
  final Signal<bool> _watchLaterLoading = Signal<bool>(false);
  final Signal<bool> _isInWatchLater = Signal<bool>(false);
  final Signal<bool> _watchLaterKnown = Signal<bool>(false);
  int _watchLaterRequestGeneration = 0;
  final Signal<BiliEngagementAction?> _pendingEngagementAction =
      Signal<BiliEngagementAction?>(null);
  final Signal<String?> _commentsError = Signal<String?>(null);
  final Signal<String?> _commentRepliesError = Signal<String?>(null);
  final Signal<String?> _relatedVideosError = Signal<String?>(null);
  final Signal<int> _sentCoinCount = Signal<int>(0);
  int _commentsPage = 0;
  int _commentRepliesPage = 0;
  int? _commentRepliesRootId;
  final Signal<int?> _commentRepliesTotalCount = Signal<int?>(null);
  int _commentRepliesRequestGeneration = 0;
  bool _isDisposed = false;
  Future<bool>? _legacyAndroidPlaybackCompatibilityFuture;

  // ---- 播放编排（委托泛化 view model） ----

  Future<VesperPlayerController> get controllerFuture =>
      _playback.controllerFuture;

  VesperPlayerController? get controller => _playback.controller;

  BiliVideoPageEntry get selectedPage =>
      BiliMediaMapper.toBiliEntry(_playback.selectedEntry);

  BiliResolvedPlayback? get resolvedPlayback => BiliMediaMapper.toBiliResolved(
        _playback.resolvedPlayback,
        bvid: BiliMediaMapper.toBiliEntry(_playback.selectedEntry).bvid ??
            detail.bvid,
        cid: int.tryParse(_playback.selectedEntry.entryId) ?? 0,
      );

  int? get selectedBiliQualityId =>
      int.tryParse(_playback.selectedQualityOptionId ?? '');

  BiliCodecStrategy get selectedCodecStrategy {
    return switch (_playback.selectedCodecIdentity) {
      'AV1' => BiliCodecStrategy.av1,
      // Dolby Vision 轨道在策略上归入 HEVC（与 _codecStrategyForTrack 一致）。
      'HEVC' || 'Dolby Vision' => BiliCodecStrategy.hevc,
      'AVC' => BiliCodecStrategy.avc,
      _ => BiliCodecStrategy.defaultStrategy,
    };
  }

  VesperSystemPlaybackPermissionStatus get systemPlaybackPermissionStatus =>
      _playback.systemPlaybackPermissionStatus;

  String? get castMessage => _playback.castMessage;

  MediaDlnaState get dlnaState => _playback.dlnaState;

  List<VesperExternalPlaybackRoute> get dlnaRoutes => _playback.dlnaRoutes;

  String? get dlnaMessage => _playback.dlnaMessage;

  MediaExternalPlaybackManager get dlnaManager => _playback.dlnaManager;

  bool get isFullscreen => _playback.isFullscreen;

  String? consumePendingMessage() => _playback.consumePendingMessage();

  MediaPlaybackRecoveryNotice? consumePendingPlaybackRecoveryNotice() =>
      _playback.consumePendingPlaybackRecoveryNotice();

  void setFullscreen(bool value) {
    _playback.setFullscreen(value);
  }

  Future<void> reloadCurrentPage() => _playback.reloadCurrentPage();

  Future<String?> switchPage(BiliVideoPageEntry page) async {
    final previousEntryId = _playback.selectedEntry.entryId;
    final result = await _playback.switchEntry(
      BiliMediaMapper.toGenericEntry(
        page,
        fallbackAid: detail.aid,
        fallbackBvid: detail.bvid,
      ),
    );
    if (result == null && _playback.selectedEntry.entryId != previousEntryId) {
      _isInWatchLater.value = false;
      _watchLaterKnown.value = false;
      unawaited(loadWatchLaterState());
    }
    return result;
  }

  Future<String?> loadCurrentPageToDlna() => _playback.loadCurrentEntryToDlna();

  Future<String?> requestSystemPlaybackPermissions(
    VesperPlayerController controller,
  ) {
    return _playback.requestSystemPlaybackPermissions(controller);
  }

  Future<String?> setPlaybackRate(double rate) =>
      _playback.setPlaybackRate(rate);

  Future<String?> selectBiliQuality(int? qualityId) {
    return _playback.selectQualityOption(qualityId?.toString());
  }

  Future<String?> selectCodecStrategy(BiliCodecStrategy strategy) {
    return _playback.selectCodecIdentity(
      strategy == BiliCodecStrategy.defaultStrategy ? null : strategy.label,
    );
  }

  Future<String?> applyBiliPlaybackSelection() {
    return _playback.applyPlaybackSelection();
  }

  Future<String?> selectSubtitle(VesperTrackSelection selection) {
    return _playback.selectSubtitle(selection);
  }

  List<double> playbackRates(VesperPlayerSnapshot snapshot) {
    return _playback.playbackRates(snapshot);
  }

  List<VesperMediaTrack> playbackSelectionTracks(
    VesperPlayerSnapshot snapshot,
  ) {
    return _playback.playbackSelectionTracks(snapshot);
  }

  List<VesperMediaTrack> subtitleTracks(VesperPlayerSnapshot snapshot) {
    return _playback.subtitleTracks(snapshot);
  }

  VesperTrackSelection subtitleSelection(VesperPlayerSnapshot snapshot) {
    return _playback.subtitleSelection(snapshot);
  }

  String playbackStateLabel(VesperPlayerSnapshot snapshot) {
    return _playback.playbackStateLabel(snapshot);
  }

  /// 当前解析结果提供的清晰度选项（适配器已分组，通用形态）。
  List<MediaQualityOption> availableQualityOptions() {
    return _playback.availableQualityOptions();
  }

  /// 是否支持 codec 细分选择（平台声明）。
  bool get supportsCodecSelection => _playback.supportsCodecSelection;

  List<int> availableBiliQualityIds(List<VesperMediaTrack> tracks) {
    final qualityIds = <int>{};
    for (final track in tracks) {
      final qualityId = BiliQualityMapping.qualityIdForTrack(track);
      if (qualityId != null) {
        qualityIds.add(qualityId);
      }
    }
    final sorted = qualityIds.toList();
    sorted.sort(
      (left, right) =>
          biliQualityRank(right).compareTo(biliQualityRank(left)),
    );
    return sorted;
  }

  bool hasTrackForSelection(
    List<VesperMediaTrack> tracks,
    int? qualityId,
    BiliCodecStrategy strategy,
  ) {
    return tracks.any((track) {
      if (qualityId != null &&
          BiliQualityMapping.qualityIdForTrack(track) != qualityId) {
        return false;
      }
      return _codecStrategyForTrack(track) == strategy;
    });
  }

  BiliCodecStrategy? _codecStrategyForTrack(VesperMediaTrack track) {
    final label = BiliQualityMapping.codecLabelForTrack(track);
    // Dolby Vision 轨道在策略上归入 HEVC（与历史行为一致）。
    return switch (label) {
      'AV1' => BiliCodecStrategy.av1,
      'HEVC' || 'Dolby Vision' => BiliCodecStrategy.hevc,
      'AVC' => BiliCodecStrategy.avc,
      _ => null,
    };
  }

  String? biliQualityLabelFromQualityId(int qualityId) {
    return biliQualityLabelForId(qualityId);
  }

  int? biliQualityIdForTrack(VesperMediaTrack track) {
    return BiliQualityMapping.qualityIdForTrack(track);
  }

  BiliVideoCodecPreference currentDownloadCodecPreference() {
    return switch (selectedCodecStrategy) {
      BiliCodecStrategy.defaultStrategy => BiliVideoCodecPreference.automatic,
      BiliCodecStrategy.av1 => BiliVideoCodecPreference.av1,
      BiliCodecStrategy.hevc => BiliVideoCodecPreference.hevc,
      BiliCodecStrategy.avc => BiliVideoCodecPreference.avc,
    };
  }

  Future<bool> _usesLegacyAndroidPlaybackCompatibility() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future<bool>.value(false);
    }
    return _legacyAndroidPlaybackCompatibilityFuture ??= BiliPlatformInfo
        .instance
        .shouldPreferTextureViewForPlayback();
  }

  // ---- 内容状态（B 站专属，保留在包装层） ----

  String get coinCountLabel => _coinCountLabel.value;

  String get shareCountLabel => _shareCountLabel.value;

  BiliVideoEngagement? get engagement => _engagement.value;

  List<BiliVideoComment> get comments => _comments.value;

  List<BiliVideoComment> get commentReplies => _commentReplies.value;

  List<BiliFeedVideo> get relatedVideos => _relatedVideos.value;

  bool get engagementLoading => _engagementLoading.value;

  bool get commentsLoading => _commentsLoading.value;

  bool get commentsLoadingMore => _commentsLoadingMore.value;

  bool get commentsHasMore => _commentsHasMore.value;

  bool get commentRepliesLoading => _commentRepliesLoading.value;

  bool get commentRepliesLoadingMore => _commentRepliesLoadingMore.value;

  bool get commentRepliesHasMore => _commentRepliesHasMore.value;

  bool get commentSubmitting => _commentSubmitting.value;

  bool get relatedVideosLoading => _relatedVideosLoading.value;

  BiliEngagementAction? get pendingEngagementAction =>
      _pendingEngagementAction.value;

  bool get isInWatchLater => _isInWatchLater.value;

  bool get watchLaterLoading => _watchLaterLoading.value;

  bool get watchLaterKnown => _watchLaterKnown.value;

  String? get commentsError => _commentsError.value;

  String? get commentRepliesError => _commentRepliesError.value;

  int? get commentRepliesTotalCount => _commentRepliesTotalCount.value;

  String? get relatedVideosError => _relatedVideosError.value;

  int get sentCoinCount => _sentCoinCount.value;

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
      'P${selectedPage.pageNumber}',
    ];
    return parts.isEmpty
        ? 'P${selectedPage.pageNumber}'
        : parts.join(' · ');
  }

  Future<void> loadEngagementState() async {
    if (_isDisposed || _engagementLoading.value) {
      return;
    }
    _engagementLoading.value = true;
    try {
      final engagement = await client.fetchVideoEngagement(detail);
      if (_isDisposed) {
        return;
      }
      _engagement.value = engagement;
      if (engagement.isAuthenticated) {
        final sentCoinCount = await client.fetchVideoCoinCount(detail);
        if (_isDisposed) {
          return;
        }
        _sentCoinCount.value = sentCoinCount;
      }
    } catch (_) {
      // Engagement is optional for guests and can fail independently of playback.
    } finally {
      if (!_isDisposed) {
        _engagementLoading.value = false;
      }
    }
  }

  Future<void> loadComments() async {
    if (_isDisposed || _commentsLoading.value || _commentsLoadingMore.value) {
      return;
    }
    _commentsLoading.value = true;
    _commentsError.value = null;
    _commentsPage = 0;
    _commentsHasMore.value = false;
    try {
      final page = await client.fetchVideoCommentPage(
        detail,
        page: 1,
        pageSize: _commentsPageSize,
      );
      if (_isDisposed) {
        return;
      }
      _comments.value = page.comments;
      _commentsPage = page.page;
      _commentsHasMore.value = page.hasMore;
    } catch (error) {
      if (!_isDisposed) {
        _commentsError.value = '评论加载失败：${biliErrorMessage(error)}';
      }
    } finally {
      if (!_isDisposed) {
        _commentsLoading.value = false;
      }
    }
  }

  Future<void> loadMoreComments() async {
    if (_isDisposed ||
        _commentsLoading.value ||
        _commentsLoadingMore.value ||
        !_commentsHasMore.value) {
      return;
    }
    _commentsLoadingMore.value = true;
    _commentsError.value = null;
    try {
      final nextPage = _commentsPage <= 0 ? 1 : _commentsPage + 1;
      final page = await client.fetchVideoCommentPage(
        detail,
        page: nextPage,
        pageSize: _commentsPageSize,
      );
      if (_isDisposed) {
        return;
      }
      final seenIds = _comments.value.map((comment) => comment.id).toSet();
      final additions = page.comments
          .where((comment) => seenIds.add(comment.id))
          .toList(growable: false);
      if (additions.isEmpty) {
        _commentsHasMore.value = false;
      } else {
        _comments.value = <BiliVideoComment>[..._comments.value, ...additions];
        _commentsPage = page.page;
        _commentsHasMore.value = page.hasMore;
      }
    } catch (error) {
      if (!_isDisposed) {
        _commentsError.value = '加载更多评论失败：${biliErrorMessage(error)}';
      }
    } finally {
      if (!_isDisposed) {
        _commentsLoadingMore.value = false;
      }
    }
  }

  Future<void> loadCommentReplies(BiliVideoComment rootComment) async {
    if (_isDisposed) {
      return;
    }
    final rootReplyId = rootComment.id;
    final generation = ++_commentRepliesRequestGeneration;
    _commentRepliesRootId = rootReplyId;
    _commentReplies.value = rootComment.replies;
    _commentRepliesPage = 0;
    _commentRepliesTotalCount.value = rootComment.replyCount > 0
        ? rootComment.replyCount
        : rootComment.replies.length;
    _commentRepliesHasMore.value =
        _commentRepliesTotalCount.value! > rootComment.replies.length;
    _commentRepliesLoading.value = true;
    _commentRepliesLoadingMore.value = false;
    _commentRepliesError.value = null;
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
      _commentReplies.value = page.replies;
      _commentRepliesPage = page.page;
      _commentRepliesTotalCount.value =
          page.totalCount ??
          (rootComment.replyCount > 0
              ? rootComment.replyCount
              : page.replies.length);
      _commentRepliesHasMore.value = page.hasMore;
    } catch (error) {
      if (!_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        return;
      }
      _commentRepliesError.value = '回复加载失败：${biliErrorMessage(error)}';
    } finally {
      if (_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        _commentRepliesLoading.value = false;
      }
    }
  }

  Future<void> loadMoreCommentReplies() async {
    final rootReplyId = _commentRepliesRootId;
    if (_isDisposed ||
        rootReplyId == null ||
        _commentRepliesLoading.value ||
        _commentRepliesLoadingMore.value ||
        !_commentRepliesHasMore.value) {
      return;
    }
    final generation = _commentRepliesRequestGeneration;
    _commentRepliesLoadingMore.value = true;
    _commentRepliesError.value = null;
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
      final seenIds = _commentReplies.value.map((reply) => reply.id).toSet();
      final additions = page.replies
          .where((reply) => seenIds.add(reply.id))
          .toList(growable: false);
      if (additions.isEmpty) {
        _commentRepliesHasMore.value = false;
      } else {
        _commentReplies.value = <BiliVideoComment>[
          ..._commentReplies.value,
          ...additions,
        ];
        _commentRepliesPage = page.page;
        _commentRepliesTotalCount.value =
            page.totalCount ?? _commentReplies.value.length;
        _commentRepliesHasMore.value = page.hasMore;
      }
    } catch (error) {
      if (!_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        return;
      }
      _commentRepliesError.value = '加载更多回复失败：${biliErrorMessage(error)}';
    } finally {
      if (_isCurrentCommentRepliesRequest(rootReplyId, generation)) {
        _commentRepliesLoadingMore.value = false;
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
    if (_isDisposed) {
      return;
    }
    _commentRepliesRequestGeneration += 1;
    _commentRepliesRootId = null;
    _commentReplies.value = const <BiliVideoComment>[];
    _commentRepliesPage = 0;
    _commentRepliesTotalCount.value = null;
    _commentRepliesHasMore.value = false;
    _commentRepliesLoading.value = false;
    _commentRepliesLoadingMore.value = false;
    _commentRepliesError.value = null;
  }

  bool _isCurrentCommentRepliesRequest(int rootReplyId, int generation) {
    return !_isDisposed &&
        _commentRepliesRootId == rootReplyId &&
        _commentRepliesRequestGeneration == generation;
  }

  Future<String?> submitComment(String message) async {
    if (_isDisposed) {
      return null;
    }
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) {
      return '评论内容不能为空';
    }
    if (_commentSubmitting.value) {
      return null;
    }

    _commentSubmitting.value = true;
    try {
      final comment = await client.addVideoComment(
        detail: detail,
        message: normalizedMessage,
      );
      if (_isDisposed) {
        return null;
      }
      if (comment == null) {
        await loadComments();
      } else {
        _comments.value = <BiliVideoComment>[comment, ..._comments.value];
      }
      return '已发送评论';
    } catch (error) {
      return _isDisposed ? null : '评论发送失败：${biliErrorMessage(error)}';
    } finally {
      if (!_isDisposed) {
        _commentSubmitting.value = false;
      }
    }
  }

  Future<void> loadRelatedVideos() async {
    if (_isDisposed || _relatedVideosLoading.value) {
      return;
    }
    _relatedVideosLoading.value = true;
    _relatedVideosError.value = null;
    try {
      var videos = await client.fetchRelatedVideos(detail);
      if (_isDisposed) {
        return;
      }
      if (videos.isEmpty) {
        videos = await _fetchFallbackRecommendedVideos();
        if (_isDisposed) {
          return;
        }
      }
      _relatedVideos.value = videos
          .where((item) => item.bvid != detail.bvid)
          .take(12)
          .toList(growable: false);
    } catch (error) {
      try {
        final fallbackVideos = await _fetchFallbackRecommendedVideos();
        if (_isDisposed) {
          return;
        }
        _relatedVideos.value = fallbackVideos;
        if (_relatedVideos.value.isEmpty) {
          _relatedVideosError.value = '相关视频加载失败：${biliErrorMessage(error)}';
        }
      } catch (_) {
        if (!_isDisposed) {
          _relatedVideosError.value = '相关视频加载失败：${biliErrorMessage(error)}';
        }
      }
    } finally {
      if (!_isDisposed) {
        _relatedVideosLoading.value = false;
      }
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
      var current = _engagement.value;
      if (current == null) {
        current = await client.fetchVideoEngagement(detail);
        if (_isDisposed) {
          return null;
        }
      }
      final nextLiked = !current.isLiked;
      final nextEngagement = await client.setVideoLike(
        detail: detail,
        liked: nextLiked,
        current: current,
      );
      if (_isDisposed) {
        return null;
      }
      _engagement.value = nextEngagement;
      return nextEngagement.isLiked ? '已点赞' : '已取消点赞';
    });
  }

  Future<String?> addCoin() {
    return _runEngagementAction(BiliEngagementAction.coin, () async {
      var current = _engagement.value;
      if (current == null) {
        current = await client.fetchVideoEngagement(detail);
        if (_isDisposed) {
          return null;
        }
      }
      final coinCount = await client.addVideoCoin(detail: detail);
      if (_isDisposed) {
        return null;
      }
      _sentCoinCount.value = coinCount;
      _engagement.value = current.copyWith(
        isAuthenticated: true,
        isLiked: true,
      );
      if (_coinCountLabel.value == '--') {
        _coinCountLabel.value = detail.coinCountLabel;
      }
      return coinCount > 1 ? '已投 $coinCount 个币' : '已投币';
    });
  }

  Future<String?> toggleFavorite() {
    return _runEngagementAction(BiliEngagementAction.favorite, () async {
      var current = _engagement.value;
      if (current == null) {
        current = await client.fetchVideoEngagement(detail);
        if (_isDisposed) {
          return null;
        }
      }
      final nextFavorited = !current.isFavorited;
      final nextEngagement = await client.setVideoFavorite(
        detail: detail,
        favorited: nextFavorited,
        current: current,
      );
      if (_isDisposed) {
        return null;
      }
      _engagement.value = nextEngagement;
      return nextEngagement.isFavorited ? '已收藏' : '已取消收藏';
    });
  }

  Future<String?> toggleFollow() {
    return _runEngagementAction(BiliEngagementAction.follow, () async {
      var current = _engagement.value;
      if (current == null) {
        current = await client.fetchVideoEngagement(detail);
        if (_isDisposed) {
          return null;
        }
      }
      final nextFollowing = !current.isFollowingOwner;
      final nextEngagement = await client.setOwnerFollow(
        detail: detail,
        following: nextFollowing,
        current: current,
      );
      if (_isDisposed) {
        return null;
      }
      _engagement.value = nextEngagement;
      return nextEngagement.isFollowingOwner ? '已关注 UP 主' : '已取消关注';
    });
  }

  Future<void> loadWatchLaterState() async {
    final generation = ++_watchLaterRequestGeneration;
    if (_isDisposed) {
      return;
    }
    if (!client.hasAuthenticatedSession) {
      _watchLaterKnown.value = false;
      return;
    }
    _watchLaterLoading.value = true;
    try {
      final bvid = _playback.selectedEntry.platformExtras['bvid'] as String? ??
          detail.bvid;
      final aid =
          _playback.selectedEntry.platformExtras['aid'] as int? ?? detail.aid;
      final isInWatchLater = await client.isVideoInWatchLater(
        bvid: bvid,
        aid: aid,
      );
      if (_isDisposed || generation != _watchLaterRequestGeneration) {
        return;
      }
      _isInWatchLater.value = isInWatchLater;
      _watchLaterKnown.value = true;
    } catch (_) {
      // Membership is optional; an unavailable list must not block playback.
      if (!_isDisposed && generation == _watchLaterRequestGeneration) {
        _watchLaterKnown.value = false;
      }
    } finally {
      if (!_isDisposed && generation == _watchLaterRequestGeneration) {
        _watchLaterLoading.value = false;
      }
    }
  }

  Future<String?> toggleWatchLater() {
    return _runEngagementAction(BiliEngagementAction.watchLater, () async {
      if (!client.hasAuthenticatedSession) {
        return '请先登录 Bilibili 后使用稍后再看。';
      }
      final bvid = _playback.selectedEntry.platformExtras['bvid'] as String? ??
          detail.bvid;
      final aid =
          _playback.selectedEntry.platformExtras['aid'] as int? ?? detail.aid;
      if (bvid.trim().isEmpty && aid <= 0) {
        return '缺少视频 ID，无法操作稍后再看。';
      }
      final next = !_isInWatchLater.value;
      if (next) {
        await client.addToWatchLater(bvid: bvid, aid: aid);
      } else {
        await client.removeFromWatchLater(bvid: bvid, aid: aid);
      }
      if (_isDisposed) {
        return null;
      }
      _isInWatchLater.value = next;
      _watchLaterKnown.value = true;
      return next ? '已加入稍后再看' : '已移出稍后再看';
    });
  }

  Future<String?> shareVideo() {
    return _runEngagementAction(BiliEngagementAction.share, () async {
      final shouldRecordShare = client.hasAuthenticatedSession;
      final shareCount = shouldRecordShare
          ? await client.recordVideoShare(detail: detail)
          : null;
      if (_isDisposed) {
        return null;
      }
      await Clipboard.setData(
        ClipboardData(
          text:
              'https://www.bilibili.com/video/'
              '${_playback.selectedEntry.platformExtras['bvid'] as String? ?? detail.bvid}',
        ),
      );
      if (_isDisposed) {
        return null;
      }
      if (shareCount != null) {
        _shareCountLabel.value = biliFormatCount(shareCount.toDouble());
      }
      return shouldRecordShare ? '已分享并复制链接' : '已复制分享链接';
    });
  }

  Future<String?> _runEngagementAction(
    BiliEngagementAction action,
    Future<String?> Function() operation,
  ) async {
    if (_isDisposed || _pendingEngagementAction.value != null) {
      return null;
    }
    _pendingEngagementAction.value = action;
    try {
      return await operation();
    } catch (error) {
      return _isDisposed ? null : '操作失败：${biliErrorMessage(error)}';
    } finally {
      if (!_isDisposed) {
        _pendingEngagementAction.value = null;
      }
    }
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _commentRepliesRequestGeneration += 1;
    _watchLaterRequestGeneration += 1;
    _playback.dispose();
    _coinCountLabel.dispose();
    _shareCountLabel.dispose();
    _engagement.dispose();
    _comments.dispose();
    _commentReplies.dispose();
    _relatedVideos.dispose();
    _engagementLoading.dispose();
    _commentsLoading.dispose();
    _commentsLoadingMore.dispose();
    _commentsHasMore.dispose();
    _commentRepliesLoading.dispose();
    _commentRepliesLoadingMore.dispose();
    _commentRepliesHasMore.dispose();
    _commentSubmitting.dispose();
    _relatedVideosLoading.dispose();
    _watchLaterLoading.dispose();
    _isInWatchLater.dispose();
    _watchLaterKnown.dispose();
    _pendingEngagementAction.dispose();
    _commentsError.dispose();
    _commentRepliesError.dispose();
    _relatedVideosError.dispose();
    _sentCoinCount.dispose();
    _commentRepliesTotalCount.dispose();
  }
}
