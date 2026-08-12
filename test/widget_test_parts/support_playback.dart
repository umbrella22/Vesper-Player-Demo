part of '../widget_test.dart';

BiliVideoDetail _playbackDetail() {
  return const BiliVideoDetail(
    aid: 1001,
    bvid: 'BV1playback01',
    title: '播放页测试视频',
    ownerMid: 2002,
    ownerName: '播放页UP',
    ownerAvatarUrl: '',
    coverUrl: '',
    description: '这是一段播放页说明，下面应直接显示合集列表。',
    publishedAtLabel: '2026-05-11',
    playCountLabel: '12.3万',
    danmakuCountLabel: '456',
    replyCountLabel: '78',
    likeCountLabel: '1.1万',
    coinCountLabel: '234',
    favoriteCountLabel: '345',
    shareCountLabel: '56',
    pages: <BiliVideoPageEntry>[
      _playbackPageOne,
      _playbackPageTwo,
      _playbackPageThree,
    ],
  );
}

BiliVideoDetail _playbackDetailWith({String? title, String? description}) {
  final base = _playbackDetail();
  return BiliVideoDetail(
    aid: base.aid,
    bvid: base.bvid,
    title: title ?? base.title,
    ownerMid: base.ownerMid,
    ownerName: base.ownerName,
    ownerAvatarUrl: base.ownerAvatarUrl,
    coverUrl: base.coverUrl,
    description: description ?? base.description,
    publishedAtLabel: base.publishedAtLabel,
    playCountLabel: base.playCountLabel,
    danmakuCountLabel: base.danmakuCountLabel,
    replyCountLabel: base.replyCountLabel,
    likeCountLabel: base.likeCountLabel,
    coinCountLabel: base.coinCountLabel,
    favoriteCountLabel: base.favoriteCountLabel,
    shareCountLabel: base.shareCountLabel,
    pages: base.pages,
  );
}

BiliVideoDetail _pgcPlaybackDetail() {
  return const BiliVideoDetail(
    aid: 3001,
    bvid: 'BV1pgcplay01',
    title: '番剧播放页测试',
    ownerMid: 0,
    ownerName: '番剧',
    ownerAvatarUrl: '',
    coverUrl: '',
    description: '番剧简介下方应直接显示剧集。',
    publishedAtLabel: '2026-05-10',
    playCountLabel: '99.9万',
    danmakuCountLabel: '1234',
    replyCountLabel: '0',
    likeCountLabel: '1',
    coinCountLabel: '2',
    favoriteCountLabel: '3',
    shareCountLabel: '4',
    pages: <BiliVideoPageEntry>[
      _playbackPageOne,
      _playbackPageTwo,
      _playbackPageThree,
    ],
  );
}

BiliResolvedPlayback _resolvedPlaybackFor(
  BiliVideoDetail detail,
  BiliVideoPageEntry page,
) {
  return BiliResolvedPlayback(
    bvid: page.bvid ?? detail.bvid,
    cid: page.cid,
    title: detail.title,
    subtitle: 'P${page.pageNumber} · ${page.title}',
    uri: 'https://example.test/${page.cid}.mp4',
    protocol: VesperPlayerSourceProtocol.progressive,
    transportLabel: 'test',
    isLocalFile: false,
    videoTracks: const <VesperMediaTrack>[
      VesperMediaTrack(
        id: 'video-80-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'avc1.640028',
        bitRate: 1000000,
        width: 1920,
        height: 1080,
      ),
      VesperMediaTrack(
        id: 'video-64-7-800-0',
        kind: VesperMediaTrackKind.video,
        label: '720P',
        codec: 'avc1.640028',
        bitRate: 800000,
        width: 1280,
        height: 720,
      ),
    ],
  );
}

final _playbackSnapshot = VesperPlayerSnapshot(
  title: '播放页测试视频',
  subtitle: 'P1 · 正片',
  sourceLabel: 'test',
  playbackState: VesperPlaybackState.ready,
  playbackRate: 1,
  isBuffering: false,
  isInterrupted: false,
  hasVideoSurface: true,
  timeline: VesperTimeline(
    kind: VesperTimelineKind.vod,
    isSeekable: true,
    seekableRange: null,
    liveEdgeMs: null,
    positionMs: 0,
    durationMs: 120000,
  ),
  trackCatalog: VesperTrackCatalog(
    tracks: <VesperMediaTrack>[
      VesperMediaTrack(
        id: 'video-80-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'avc1.640028',
        bitRate: 1000000,
        width: 1920,
        height: 1080,
      ),
      VesperMediaTrack(
        id: 'video-64-7-800-0',
        kind: VesperMediaTrackKind.video,
        label: '720P',
        codec: 'avc1.640028',
        bitRate: 800000,
        width: 1280,
        height: 720,
      ),
    ],
    adaptiveVideo: true,
  ),
  effectiveVideoTrackId: 'video-80-7-1000-0',
);

final _playingPlaybackSnapshot = VesperPlayerSnapshot(
  title: '播放页测试视频',
  subtitle: 'P1 · 正片',
  sourceLabel: 'test',
  playbackState: VesperPlaybackState.playing,
  playbackRate: 1,
  isBuffering: false,
  isInterrupted: false,
  hasVideoSurface: true,
  timeline: VesperTimeline(
    kind: VesperTimelineKind.vod,
    isSeekable: true,
    seekableRange: null,
    liveEdgeMs: null,
    positionMs: 0,
    durationMs: 120000,
  ),
  trackCatalog: VesperTrackCatalog(
    tracks: <VesperMediaTrack>[
      VesperMediaTrack(
        id: 'video-80-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'avc1.640028',
        bitRate: 1000000,
        width: 1920,
        height: 1080,
      ),
      VesperMediaTrack(
        id: 'video-64-7-800-0',
        kind: VesperMediaTrackKind.video,
        label: '720P',
        codec: 'avc1.640028',
        bitRate: 800000,
        width: 1280,
        height: 720,
      ),
    ],
    adaptiveVideo: true,
  ),
  effectiveVideoTrackId: 'video-80-7-1000-0',
);

const _expiredPlaybackAddressError = VesperPlayerError(
  message: 'Source error: HTTP 403',
  code: VesperPlayerErrorCode.backendFailure,
  category: VesperPlayerErrorCategory.network,
  retriable: true,
  details: <String, Object?>{'errorCodeName': 'ERROR_CODE_IO_BAD_HTTP_STATUS'},
);

const _iosExpiredPlaybackAddressError = VesperPlayerError(
  message: 'The requested URL returned error: 403',
  code: VesperPlayerErrorCode.backendFailure,
  category: VesperPlayerErrorCategory.platform,
  retriable: false,
  details: <String, Object?>{
    'avPlayerItemErrorStatusCode': '403',
    'avPlayerItemErrorDomain': 'CoreMediaErrorDomain',
  },
);

BiliVideoComment _playbackCommentReply({
  required int id,
  required String authorName,
  required String message,
}) {
  return BiliVideoComment(
    id: id,
    authorName: authorName,
    authorAvatarUrl: '',
    createdAtLabel: '刚刚',
    message: message,
    likeCountLabel: '0',
    pictures: const <BiliCommentPicture>[],
    replies: const <BiliVideoComment>[],
    timeLinks: const <BiliCommentTimeLink>[],
  );
}

final class _FakePlaybackClient extends BiliClient {
  _FakePlaybackClient();

  /// 测试可覆盖的解析结果；非空时优先于 [_resolvedPlaybackFor]。
  BiliResolvedPlayback Function()? resolveOverride;

  final List<BiliFeedVideo> relatedVideos = const <BiliFeedVideo>[
    BiliFeedVideo(
      aid: 9001,
      bvid: 'BV1related01',
      title: '相关视频 1',
      author: '相关UP',
      coverUrl: '',
      durationLabel: '04:20',
      playCountLabel: '8.8万',
      danmakuCountLabel: '321',
    ),
    BiliFeedVideo(
      aid: 9002,
      bvid: 'BV1related02',
      title: '相关视频 2',
      author: '相关UP',
      coverUrl: '',
      durationLabel: '01:12',
      playCountLabel: '1.2万',
      danmakuCountLabel: '45',
    ),
  ];
  BiliVideoEngagement engagement = const BiliVideoEngagement(
    isAuthenticated: true,
    isLiked: false,
    isFavorited: false,
    isFollowingOwner: false,
    favoriteMediaIds: <int>[],
    defaultFavoriteMediaId: 99,
  );
  Completer<BiliVideoEngagement>? followCompleter;
  var followRequests = 0;
  var coinRequests = 0;
  final sentComments = <String>[];
  final commentPageRequests = <int>[];
  final commentReplyPageRequests = <int>[];
  final resolvedPlaybackRequests = <int>[];
  final blockedPlaybackResolutions = <int, Completer<BiliResolvedPlayback>>{};
  final extraComments = <BiliVideoComment>[];
  final Map<int, List<BiliVideoComment>>
  commentReplyPages = <int, List<BiliVideoComment>>{
    1: <BiliVideoComment>[
      _playbackCommentReply(id: 502, authorName: '立在哪里无寒冬', message: '删了让我发'),
      _playbackCommentReply(id: 503, authorName: '楼中楼用户二', message: '第二条完整回复'),
      _playbackCommentReply(id: 504, authorName: '楼中楼用户三', message: '第三条完整回复'),
    ],
  };
  int commentReplyTotalCount = 3;
  final List<BiliVideoComment> comments = const <BiliVideoComment>[
    BiliVideoComment(
      id: 501,
      authorName: '神代强丸',
      authorAvatarUrl: '',
      authorLevelLabel: 'LV6',
      createdAtLabel: '3小时前',
      message: '01:00 不像韩女，因为你俩一看就是没整过的天然美人儿',
      likeCountLabel: '135',
      replyCount: 3,
      pictures: <BiliCommentPicture>[
        BiliCommentPicture(
          url: 'https://example.test/comment.jpg',
          width: 1280,
          height: 720,
        ),
      ],
      replies: <BiliVideoComment>[
        BiliVideoComment(
          id: 502,
          authorName: '立在哪里无寒冬',
          authorAvatarUrl: '',
          createdAtLabel: '2小时前',
          message: '删了让我发',
          likeCountLabel: '1',
          pictures: <BiliCommentPicture>[],
          replies: <BiliVideoComment>[],
          timeLinks: <BiliCommentTimeLink>[],
        ),
      ],
      timeLinks: <BiliCommentTimeLink>[
        BiliCommentTimeLink(label: '01:00', seconds: 60, start: 0, end: 5),
      ],
    ),
  ];

  @override
  Future<BiliResolvedPlayback> resolvePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required TargetPlatform platform,
  }) async {
    resolvedPlaybackRequests.add(page.cid);
    final override = resolveOverride;
    if (override != null) {
      return override();
    }
    final blockedResolution = blockedPlaybackResolutions.remove(page.cid);
    if (blockedResolution != null) {
      return blockedResolution.future;
    }
    return _resolvedPlaybackFor(detail, page);
  }

  @override
  Future<List<BiliFeedVideo>> fetchRelatedVideos(
    BiliVideoDetail detail, {
    int limit = 12,
  }) async {
    return relatedVideos.take(limit).toList(growable: false);
  }

  @override
  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) async {
    return page == 1 ? relatedVideos : const <BiliFeedVideo>[];
  }

  @override
  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async {
    final base = _playbackDetail();
    return BiliVideoDetail(
      aid: 9100,
      bvid: bvid,
      title: '打开的相关视频',
      ownerMid: base.ownerMid,
      ownerName: base.ownerName,
      ownerAvatarUrl: base.ownerAvatarUrl,
      coverUrl: base.coverUrl,
      description: base.description,
      publishedAtLabel: base.publishedAtLabel,
      playCountLabel: base.playCountLabel,
      danmakuCountLabel: base.danmakuCountLabel,
      replyCountLabel: base.replyCountLabel,
      likeCountLabel: base.likeCountLabel,
      coinCountLabel: base.coinCountLabel,
      favoriteCountLabel: base.favoriteCountLabel,
      shareCountLabel: base.shareCountLabel,
      pages: base.pages,
    );
  }

  @override
  Future<BiliVideoEngagement> fetchVideoEngagement(
    BiliVideoDetail detail,
  ) async {
    return engagement;
  }

  @override
  Future<int> fetchVideoCoinCount(BiliVideoDetail detail) async {
    return coinRequests;
  }

  @override
  Future<List<BiliVideoComment>> fetchVideoComments(
    BiliVideoDetail detail, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final commentPage = await fetchVideoCommentPage(
      detail,
      page: page,
      pageSize: pageSize,
    );
    return commentPage.comments;
  }

  @override
  Future<BiliVideoCommentPage> fetchVideoCommentPage(
    BiliVideoDetail detail, {
    int page = 1,
    int pageSize = 20,
  }) async {
    commentPageRequests.add(page);
    final pageComments = switch (page) {
      1 => comments.take(pageSize).toList(growable: false),
      2 => extraComments.take(pageSize).toList(growable: false),
      _ => const <BiliVideoComment>[],
    };
    final totalCount = comments.length + extraComments.length;
    return BiliVideoCommentPage(
      comments: pageComments,
      page: page,
      pageSize: pageSize,
      totalCount: totalCount,
      hasMore: page == 1 && extraComments.isNotEmpty,
    );
  }

  @override
  Future<BiliVideoCommentReplyPage> fetchVideoCommentReplyPage(
    BiliVideoDetail detail, {
    required int rootReplyId,
    int page = 1,
    int pageSize = 20,
  }) async {
    commentReplyPageRequests.add(page);
    final replies = commentReplyPages[page] ?? const <BiliVideoComment>[];
    return BiliVideoCommentReplyPage(
      replies: replies.take(pageSize).toList(growable: false),
      page: page,
      pageSize: pageSize,
      totalCount: commentReplyTotalCount,
      hasMore: replies.isNotEmpty && page * pageSize < commentReplyTotalCount,
    );
  }

  @override
  Future<BiliVideoComment?> addVideoComment({
    required BiliVideoDetail detail,
    required String message,
  }) async {
    sentComments.add(message);
    return BiliVideoComment(
      id: 700 + sentComments.length,
      authorName: '当前用户',
      authorAvatarUrl: '',
      createdAtLabel: '刚刚',
      message: message,
      likeCountLabel: '0',
      pictures: const <BiliCommentPicture>[],
      replies: const <BiliVideoComment>[],
      timeLinks: const <BiliCommentTimeLink>[],
    );
  }

  @override
  Future<BiliVideoEngagement> setVideoLike({
    required BiliVideoDetail detail,
    required bool liked,
    BiliVideoEngagement? current,
  }) async {
    engagement = (current ?? engagement).copyWith(isLiked: liked);
    return engagement;
  }

  @override
  Future<int> addVideoCoin({
    required BiliVideoDetail detail,
    int multiply = 1,
    bool selectLike = true,
  }) async {
    coinRequests += multiply;
    if (selectLike) {
      engagement = engagement.copyWith(isLiked: true);
    }
    return coinRequests;
  }

  @override
  Future<BiliVideoEngagement> setVideoFavorite({
    required BiliVideoDetail detail,
    required bool favorited,
    BiliVideoEngagement? current,
  }) async {
    engagement = (current ?? engagement).copyWith(isFavorited: favorited);
    return engagement;
  }

  @override
  Future<BiliVideoEngagement> setOwnerFollow({
    required BiliVideoDetail detail,
    required bool following,
    BiliVideoEngagement? current,
  }) async {
    followRequests += 1;
    final completer = followCompleter;
    if (completer != null) {
      engagement = await completer.future;
      return engagement;
    }
    engagement = (current ?? engagement).copyWith(isFollowingOwner: following);
    return engagement;
  }

  @override
  Future<int?> recordVideoShare({required BiliVideoDetail detail}) async {
    return null;
  }
}

final class _FakePlaybackVesperPlatform extends VesperPlayerPlatform {
  _FakePlaybackVesperPlatform({VesperPlayerSnapshot? initialSnapshot})
    : initialSnapshot = initialSnapshot ?? _playbackSnapshot,
      _currentSnapshot = initialSnapshot ?? _playbackSnapshot;

  final VesperPlayerSnapshot initialSnapshot;
  final StreamController<VesperPlayerEvent> _eventsController =
      StreamController<VesperPlayerEvent>.broadcast();
  VesperPlayerSnapshot _currentSnapshot;
  final selectedSources = <VesperPlayerSource>[];
  final seekRatios = <double>[];
  final seekDeltas = <int>[];
  final playbackRates = <double>[];
  final subtitleSelections = <VesperTrackSelection>[];
  VesperSourceNormalizerConfiguration? lastSourceNormalizerConfiguration;
  VesperFrameProcessorConfiguration? lastFrameProcessorConfiguration;
  VesperNativeFramePipelineConfiguration? lastNativeFramePipelineConfiguration;
  VesperPlayerRenderSurfaceKind? lastRenderSurfaceKind;
  VesperSystemPlaybackConfiguration? lastSystemPlaybackConfiguration;
  int playCalls = 0;
  int pauseCalls = 0;
  int refreshCalls = 0;
  int disposeCalls = 0;
  int clearSystemPlaybackCalls = 0;
  int failSelectedSourcesRemaining = 0;
  VesperPlayerError selectedSourceFailure = _expiredPlaybackAddressError;
  VesperPlayerSnapshot? selectedSourceSuccessSnapshot;

  @override
  Future<VesperPlatformCreateResult> createPlayer({
    VesperPlayerSource? initialSource,
    VesperPlayerRenderSurfaceKind renderSurfaceKind =
        VesperPlayerRenderSurfaceKind.auto,
    VesperPlaybackResiliencePolicy resiliencePolicy =
        const VesperPlaybackResiliencePolicy(),
    VesperTrackPreferencePolicy trackPreferencePolicy =
        const VesperTrackPreferencePolicy(),
    VesperPreloadBudgetPolicy preloadBudgetPolicy =
        const VesperPreloadBudgetPolicy(),
    bool keepScreenOnDuringPlayback = true,
    VesperBenchmarkConfiguration benchmarkConfiguration =
        const VesperBenchmarkConfiguration.disabled(),
    VesperSourceNormalizerConfiguration sourceNormalizerConfiguration =
        const VesperSourceNormalizerConfiguration(),
    VesperFrameProcessorConfiguration frameProcessorConfiguration =
        const VesperFrameProcessorConfiguration(),
    VesperNativeFramePipelineConfiguration nativeFramePipelineConfiguration =
        const VesperNativeFramePipelineConfiguration(),
    VesperPipelineEventHookConfiguration pipelineEventHookConfiguration =
        const VesperPipelineEventHookConfiguration(),
  }) async {
    lastRenderSurfaceKind = renderSurfaceKind;
    lastSourceNormalizerConfiguration = sourceNormalizerConfiguration;
    lastFrameProcessorConfiguration = frameProcessorConfiguration;
    lastNativeFramePipelineConfiguration = nativeFramePipelineConfiguration;
    return VesperPlatformCreateResult(
      playerId: 'playback-test-player',
      snapshot: initialSnapshot,
    );
  }

  @override
  Stream<VesperPlayerEvent> eventsFor(String playerId) {
    return _eventsController.stream;
  }

  @override
  Future<void> initialize(String playerId) async {}

  @override
  Future<void> dispose(String playerId) async {
    disposeCalls += 1;
  }

  @override
  Future<void> refreshPlayer(String playerId) async {
    refreshCalls += 1;
  }

  @override
  Future<void> selectSource(String playerId, VesperPlayerSource source) async {
    selectedSources.add(source);
    if (failSelectedSourcesRemaining > 0) {
      failSelectedSourcesRemaining -= 1;
      scheduleMicrotask(() => emitPlaybackError(selectedSourceFailure));
      return;
    }
    final successSnapshot = selectedSourceSuccessSnapshot;
    if (successSnapshot != null) {
      scheduleMicrotask(() => emitSnapshot(successSnapshot));
    }
  }

  void emitSnapshot(VesperPlayerSnapshot snapshot) {
    _currentSnapshot = snapshot;
    _eventsController.add(
      VesperPlayerSnapshotEvent(
        playerId: 'playback-test-player',
        snapshot: snapshot,
      ),
    );
  }

  void emitPlaybackError(VesperPlayerError error) {
    final snapshot = _currentSnapshot.copyWith(lastError: error);
    _currentSnapshot = snapshot;
    _eventsController.add(
      VesperPlayerErrorEvent(
        playerId: 'playback-test-player',
        error: error,
        snapshot: snapshot,
      ),
    );
  }

  Future<void> closeEvents() => _eventsController.close();

  @override
  Future<void> play(String playerId) async {
    playCalls += 1;
  }

  @override
  Future<void> pause(String playerId) async {
    pauseCalls += 1;
  }

  @override
  Future<void> togglePause(String playerId) async {}

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> seekBy(String playerId, int deltaMs) async {
    seekDeltas.add(deltaMs);
  }

  @override
  Future<void> seekToRatio(String playerId, double ratio) async {
    seekRatios.add(ratio);
  }

  @override
  Future<void> seekToLiveEdge(String playerId) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double rate) async {
    playbackRates.add(rate);
  }

  @override
  Future<void> setVideoTrackSelection(
    String playerId,
    VesperTrackSelection selection,
  ) async {}

  @override
  Future<void> setAudioTrackSelection(
    String playerId,
    VesperTrackSelection selection,
  ) async {}

  @override
  Future<void> setSubtitleTrackSelection(
    String playerId,
    VesperTrackSelection selection,
  ) async {
    subtitleSelections.add(selection);
  }

  @override
  Future<void> setAbrPolicy(
    String playerId,
    VesperAbrPolicy policy, {
    int? expectedCatalogRevision,
  }) async {}

  @override
  Future<void> setResiliencePolicy(
    String playerId,
    VesperPlaybackResiliencePolicy policy,
  ) async {}

  @override
  Future<void> updateViewport(
    String playerId,
    VesperPlayerViewport viewport,
  ) async {}

  @override
  Future<void> clearViewport(String playerId) async {}

  @override
  Future<void> configureSystemPlayback(
    String playerId,
    VesperSystemPlaybackConfiguration configuration,
  ) async {
    lastSystemPlaybackConfiguration = configuration;
  }

  @override
  Future<void> clearSystemPlayback(String playerId) async {
    clearSystemPlaybackCalls += 1;
  }

  @override
  Future<VesperSystemPlaybackPermissionStatus>
  getSystemPlaybackPermissionStatus() async {
    return VesperSystemPlaybackPermissionStatus.notRequired;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<BiliFeedVideo> _tvFeedItems([int count = 18, bool withCovers = false]) {
  return List<BiliFeedVideo>.generate(
    count,
    (index) => BiliFeedVideo(
      aid: 5000 + index,
      bvid: 'BVTV${index.toString().padLeft(8, '0')}',
      title: '推荐视频 $index',
      author: 'UP $index',
      coverUrl: withCovers ? 'https://example.test/tv-cover-$index.jpg' : '',
      durationLabel: '03:${index.toString().padLeft(2, '0')}',
      playCountLabel: '${index + 1}万',
      danmakuCountLabel: '${index + 10}',
    ),
  );
}

List<BiliPlaybackHistoryEntry> _tvHistoryEntries([int count = 18]) {
  return List<BiliPlaybackHistoryEntry>.generate(
    count,
    (index) => BiliPlaybackHistoryEntry(
      bvid: 'BVHISTORY${index.toString().padLeft(6, '0')}',
      aid: 7000 + index,
      cid: 8000 + index,
      videoTitle: '历史视频 $index',
      pageTitle: '第 ${index + 1} 集',
      coverUrl: '',
      ownerName: '历史 UP $index',
      playedAtMs: 1000 - index,
      lastPositionMs: 30 * 1000,
      durationMs: 180 * 1000,
    ),
  );
}
