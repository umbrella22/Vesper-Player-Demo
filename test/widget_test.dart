import 'dart:async';
import 'dart:io';

import 'package:bilibili_player/app/app.dart';
import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/models/bili_region_models.dart';
import 'package:bilibili_player/bili/common/pages/bili_playback_page.dart';
import 'package:bilibili_player/bili/app_mode/pages/bili_region_video_page.dart';
import 'package:bilibili_player/bili/app_mode/pages/bili_settings_page.dart';
import 'package:bilibili_player/bili/common/services/bili_app_settings.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:bilibili_player/bili/common/services/bili_session_store.dart';
import 'package:bilibili_player/bili/common/widgets/bili_cache_download_panel.dart';
import 'package:bilibili_player/bili/common/widgets/bili_qr_login_sheet.dart';
import 'package:bilibili_player/bili/tv_mode/pages/bili_tv_home_page.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_directional_focus_scope.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_focusable.dart';
import 'package:bilibili_player/download/download.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_ui/vesper_player_ui.dart' as vesper_ui;

final class _FakeOfflineController extends BiliOfflineDownloadController {
  _FakeOfflineController(
    this._entries, {
    this.storageUsage = const BiliOfflineStorageUsage(
      cacheBytes: 0,
      freeBytes: 0,
      totalBytes: 0,
    ),
  }) : super(client: BiliClient());

  final List<BiliOfflineDownloadEntry> _entries;
  final BiliOfflineStorageUsage storageUsage;
  final List<String> removedAssetIds = <String>[];
  final List<int> pausedTaskIds = <int>[];
  final List<int> resumedTaskIds = <int>[];
  var pauseAllActiveCalls = 0;
  Completer<void>? pauseCompleter;
  Completer<void>? resumeCompleter;

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  List<BiliOfflineDownloadEntry> get entries => _entries;

  @override
  Future<BiliOfflineStorageUsage> resolveStorageUsage() async {
    return storageUsage;
  }

  @override
  Future<void> removeEntry(BiliOfflineDownloadEntry entry) async {
    removedAssetIds.add(entry.metadata.assetId);
    _entries.removeWhere(
      (current) => current.metadata.assetId == entry.metadata.assetId,
    );
    notifyListeners();
  }

  @override
  Future<void> pause(int taskId) async {
    pausedTaskIds.add(taskId);
    final completer = pauseCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> pauseAllActive() async {
    pauseAllActiveCalls += 1;
  }

  @override
  Future<void> resume(int taskId) async {
    resumedTaskIds.add(taskId);
    final completer = resumeCompleter;
    if (completer != null) {
      await completer.future;
    }
  }
}

final class _FakeCacheController extends BiliOfflineDownloadController {
  _FakeCacheController({required this.options}) : super(client: BiliClient());

  final BiliDownloadOptions options;
  final List<int> enqueuedCids = <int>[];
  final List<int> enqueuedQualityIds = <int>[];
  Completer<BiliDownloadOptions>? resolveCompleter;
  Completer<BiliOfflineDownloadEntry>? enqueueCompleter;
  Object? resolveError;
  Object? enqueueError;

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<BiliDownloadOptions> resolveOptions({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
  }) async {
    if (resolveError case final error?) {
      throw error;
    }
    final completer = resolveCompleter;
    if (completer != null) {
      return completer.future;
    }
    return options;
  }

  @override
  Future<BiliOfflineStorageUsage> resolveStorageUsage() async {
    return const BiliOfflineStorageUsage(
      cacheBytes: 0,
      freeBytes: 8 * 1024 * 1024,
      totalBytes: 8 * 1024 * 1024,
    );
  }

  @override
  Future<BiliOfflineDownloadEntry> enqueueBiliPage({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required int qualityId,
    BiliVideoCodecPreference codecPreference =
        BiliVideoCodecPreference.automatic,
    BiliDownloadOptions? options,
  }) async {
    enqueuedCids.add(page.cid);
    enqueuedQualityIds.add(qualityId);
    if (enqueueError case final error?) {
      throw error;
    }
    final completer = enqueueCompleter;
    if (completer != null) {
      return completer.future;
    }
    return BiliOfflineDownloadEntry(
      metadata: BiliOfflineDownloadMetadata(
        assetId: 'asset-${page.cid}',
        taskId: page.cid,
        bvid: detail.bvid,
        cid: page.cid,
        videoTitle: detail.title,
        pageTitle: 'P${page.pageNumber} · ${page.title}',
        coverUrl: detail.coverUrl,
        qualityLabel: '1080P',
        createdAtMs: 100,
      ),
    );
  }
}

final class _FakeQrLoginClient extends BiliClient {
  final List<BiliQrLoginPollResult> pollResults = <BiliQrLoginPollResult>[];
  final List<String> polledKeys = <String>[];
  int generatedTickets = 0;
  Object? generateError;
  Object? pollError;

  @override
  Future<BiliQrLoginTicket> generateQrLoginTicket() async {
    if (generateError case final error?) {
      throw error;
    }
    generatedTickets += 1;
    return BiliQrLoginTicket(
      url: 'https://example.test/qr/$generatedTickets',
      qrcodeKey: 'key-$generatedTickets',
    );
  }

  @override
  Future<BiliQrLoginPollResult> pollQrLogin(String qrcodeKey) async {
    polledKeys.add(qrcodeKey);
    if (pollError case final error?) {
      throw error;
    }
    if (pollResults.isNotEmpty) {
      return pollResults.removeAt(0);
    }
    return const BiliQrLoginPollResult(
      status: BiliQrLoginStatus.waitingForScan,
      message: '等待扫码',
    );
  }

  @override
  Future<BiliUserProfile> fetchCurrentUserProfile() async {
    return const BiliUserProfile(
      isLoggedIn: true,
      name: '扫码用户',
      avatarUrl: '',
      mid: 42,
    );
  }

  @override
  Map<String, String> snapshotCookies() {
    return const <String, String>{'SESSDATA': 'cookie'};
  }
}

final class _FakeRegionClient extends BiliClient {
  final List<int> requestedPages = <int>[];
  final Map<int, List<BiliRegionVideo>> pageItems =
      <int, List<BiliRegionVideo>>{
        1: _regionVideos(page: 1, count: 20),
        2: _regionVideos(page: 2, count: 3),
      };
  Object? firstPageError;

  @override
  Future<List<BiliRegionVideo>> fetchRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) async {
    requestedPages.add(page);
    final firstPageError = this.firstPageError;
    if (page == 1 && firstPageError != null) {
      throw firstPageError;
    }
    return pageItems[page] ?? const <BiliRegionVideo>[];
  }
}

const _testPage = BiliVideoPageEntry(
  cid: 11,
  pageNumber: 1,
  title: '正片',
  durationSeconds: 60,
);

BiliVideoDetail _testDetail() {
  return const BiliVideoDetail(
    aid: 1,
    bvid: 'BV1xx411c7mD',
    title: '首页视频',
    ownerMid: 2,
    ownerName: '测试UP',
    ownerAvatarUrl: '',
    coverUrl: '',
    description: '',
    publishedAtLabel: null,
    playCountLabel: '1.2万',
    danmakuCountLabel: '34',
    replyCountLabel: '5',
    likeCountLabel: '6',
    coinCountLabel: '7',
    favoriteCountLabel: '8',
    shareCountLabel: '9',
    pages: <BiliVideoPageEntry>[
      _testPage,
      BiliVideoPageEntry(
        cid: 12,
        pageNumber: 2,
        title: '花絮',
        durationSeconds: 45,
      ),
    ],
  );
}

BiliDownloadOptions _testDownloadOptions(BiliVideoDetail detail) {
  const segmentInfo = BiliDashSegmentInfo(
    initialization: '0-10',
    indexRange: '11-20',
  );
  const video = BiliDashStream(
    id: 80,
    baseUrl: 'https://example.test/video.m4s',
    mimeType: 'video/mp4',
    codecs: 'avc1.640028',
    bandwidth: 1000,
    segmentInfo: segmentInfo,
    representationId: 'video-80-7-1000-0',
    qualityLabel: '1080P',
  );
  const video720 = BiliDashStream(
    id: 64,
    baseUrl: 'https://example.test/video-720.m4s',
    mimeType: 'video/mp4',
    codecs: 'avc1.640028',
    bandwidth: 800,
    segmentInfo: segmentInfo,
    representationId: 'video-64-7-800-0',
    qualityLabel: '720P',
  );
  const audio = BiliDashStream(
    id: 30280,
    baseUrl: 'https://example.test/audio.m4s',
    mimeType: 'audio/mp4',
    codecs: 'mp4a.40.2',
    bandwidth: 128000,
    segmentInfo: segmentInfo,
    representationId: 'audio-30280-30280-128000-0',
  );
  return BiliDownloadOptions(
    bvid: detail.bvid,
    cid: _testPage.cid,
    videoTitle: detail.title,
    pageTitle: 'P1 · 正片',
    coverUrl: detail.coverUrl,
    referer: 'https://www.bilibili.com/video/${detail.bvid}',
    headers: const <String, String>{},
    manifest: const BiliDashManifestData(
      durationMs: 60000,
      minBufferTimeMs: 1500,
      videoStreams: <BiliDashStream>[video],
      audioStreams: <BiliDashStream>[audio],
    ),
    qualities: const <BiliDownloadQualityOption>[
      BiliDownloadQualityOption(
        qualityId: 80,
        label: '1080P',
        videoStreams: <BiliDashStream>[video],
      ),
      BiliDownloadQualityOption(
        qualityId: 64,
        label: '720P',
        videoStreams: <BiliDashStream>[video720],
      ),
    ],
    variantLabel: 'test',
  );
}

List<BiliRegionVideo> _regionVideos({required int page, required int count}) {
  return List<BiliRegionVideo>.generate(
    count,
    (index) => BiliRegionVideo(
      id: 'region-$page-$index',
      title: '分区视频 $page-$index',
      coverUrl: '',
      url: 'https://example.test/region/$page/$index',
      bvid: 'BVREGION$page${index.toString().padLeft(4, '0')}',
      subtitle: '测试分区',
      followCountLabel: '${index + 1}万播放',
    ),
  );
}

const _testRegionSection = BiliRegionSection(
  id: 'douga',
  name: '动画',
  icon: 'A',
  apiType: BiliRegionApiType.ranking,
  rid: 1,
);

const _playbackPageOne = BiliVideoPageEntry(
  cid: 101,
  pageNumber: 1,
  title: '正片',
  durationSeconds: 120,
);

const _playbackPageTwo = BiliVideoPageEntry(
  cid: 102,
  pageNumber: 2,
  title: '花絮',
  durationSeconds: 90,
);

const _playbackPageThree = BiliVideoPageEntry(
  cid: 103,
  pageNumber: 3,
  title: '访谈',
  durationSeconds: 80,
);

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

const _playbackSnapshot = VesperPlayerSnapshot(
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

final class _FakePlaybackClient extends BiliClient {
  _FakePlaybackClient();

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
  final resolvedPlaybackRequests = <int>[];

  @override
  Future<BiliResolvedPlayback> resolvePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required TargetPlatform platform,
  }) async {
    resolvedPlaybackRequests.add(page.cid);
    return _resolvedPlaybackFor(detail, page);
  }

  @override
  Future<BiliVideoEngagement> fetchVideoEngagement(
    BiliVideoDetail detail,
  ) async {
    return engagement;
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
  final selectedSources = <VesperPlayerSource>[];
  final seekRatios = <double>[];
  VesperSourceNormalizerConfiguration? lastSourceNormalizerConfiguration;
  VesperFrameProcessorConfiguration? lastFrameProcessorConfiguration;
  VesperNativeFramePipelineConfiguration? lastNativeFramePipelineConfiguration;
  int playCalls = 0;
  int pauseCalls = 0;

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
  }) async {
    lastSourceNormalizerConfiguration = sourceNormalizerConfiguration;
    lastFrameProcessorConfiguration = frameProcessorConfiguration;
    lastNativeFramePipelineConfiguration = nativeFramePipelineConfiguration;
    return const VesperPlatformCreateResult(
      playerId: 'playback-test-player',
      snapshot: _playbackSnapshot,
    );
  }

  @override
  Stream<VesperPlayerEvent> eventsFor(String playerId) {
    return const Stream<VesperPlayerEvent>.empty();
  }

  @override
  Future<void> initialize(String playerId) async {}

  @override
  Future<void> dispose(String playerId) async {}

  @override
  Future<void> refreshPlayer(String playerId) async {}

  @override
  Future<void> selectSource(String playerId, VesperPlayerSource source) async {
    selectedSources.add(source);
  }

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
  Future<void> seekBy(String playerId, int deltaMs) async {}

  @override
  Future<void> seekToRatio(String playerId, double ratio) async {
    seekRatios.add(ratio);
  }

  @override
  Future<void> seekToLiveEdge(String playerId) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double rate) async {}

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
  ) async {}

  @override
  Future<void> setAbrPolicy(String playerId, VesperAbrPolicy policy) async {}

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
  ) async {}

  @override
  Future<void> clearSystemPlayback(String playerId) async {}

  @override
  Future<VesperSystemPlaybackPermissionStatus>
  getSystemPlaybackPermissionStatus() async {
    return VesperSystemPlaybackPermissionStatus.notRequired;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<BiliFeedVideo> _tvFeedItems([int count = 18]) {
  return List<BiliFeedVideo>.generate(
    count,
    (index) => BiliFeedVideo(
      aid: 5000 + index,
      bvid: 'BVTV${index.toString().padLeft(8, '0')}',
      title: '推荐视频 $index',
      author: 'UP $index',
      coverUrl: '',
      durationLabel: '03:${index.toString().padLeft(2, '0')}',
      playCountLabel: '${index + 1}万',
      danmakuCountLabel: '${index + 10}',
    ),
  );
}

final class _FakeTvHomeClient extends BiliClient {
  _FakeTvHomeClient({List<BiliFeedVideo>? feedItems})
    : feedItems = feedItems ?? _tvFeedItems();

  final List<BiliFeedVideo> feedItems;
  final List<BiliRegionSection> requestedSections = <BiliRegionSection>[];
  Completer<List<BiliSearchResult>>? searchCompleter;

  @override
  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) async {
    return page == 1 ? feedItems : const <BiliFeedVideo>[];
  }

  @override
  Future<BiliUserProfile> fetchCurrentUserProfile() async {
    return const BiliUserProfile(isLoggedIn: false, name: '未登录', avatarUrl: '');
  }

  @override
  Future<List<BiliSearchResult>> searchVideos(
    String keyword, {
    int page = 1,
  }) async {
    final completer = searchCompleter;
    if (page == 1 && completer != null) {
      searchCompleter = null;
      return completer.future;
    }
    return const <BiliSearchResult>[];
  }

  @override
  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async {
    return _playbackDetail();
  }

  @override
  Future<List<BiliRegionVideo>> fetchRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) async {
    requestedSections.add(section);
    if (page != 1) {
      return const <BiliRegionVideo>[];
    }
    return List<BiliRegionVideo>.generate(
      12,
      (index) => BiliRegionVideo(
        id: '${section.id}-$index',
        title: '${section.name}内容 $index',
        coverUrl: '',
        url: 'https://example.test/${section.id}/$index',
        bvid: section.apiType == BiliRegionApiType.ranking
            ? 'BVREGION${index.toString().padLeft(4, '0')}'
            : null,
        seasonId: section.apiType == BiliRegionApiType.pgc
            ? 7000 + index
            : null,
        subtitle: section.name,
        indexLabel: '更新至 ${index + 1}',
        scoreLabel: '9.$index',
        followCountLabel: '${index + 2}万追番',
      ),
    );
  }

  @override
  Future<BiliVideoDetail> fetchPgcSeasonFirstEpisodeDetail(int seasonId) async {
    return _pgcPlaybackDetail();
  }
}

final class _PlaybackHarness {
  const _PlaybackHarness({required this.client, required this.platform});

  final _FakePlaybackClient client;
  final _FakePlaybackVesperPlatform platform;
}

final class _ExternalPlaybackHarness {
  _ExternalPlaybackHarness({
    this.loadResult = const <String, Object?>{
      'status': 'success',
      'routeId': 'uuid:tv',
      'relayEnabled': true,
    },
  });

  static const channel = MethodChannel(
    'io.github.ikaros.vesper_player_external_playback',
  );
  static const routesChannel = EventChannel(
    'io.github.ikaros.vesper_player_external_playback/routes',
  );
  static const eventsChannel = EventChannel(
    'io.github.ikaros.vesper_player_external_playback/events',
  );

  final Map<String, Object?> loadResult;
  final calls = <MethodCall>[];
  late dynamic _routesSink;
  late dynamic _eventsSink;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'startDiscovery':
            case 'stopDiscovery':
              return null;
            case 'connect':
              return <String, Object?>{
                'status': 'success',
                'routeId': 'uuid:tv',
              };
            case 'load':
              return loadResult;
            case 'disconnect':
              return <String, Object?>{'status': 'success'};
          }
          return <String, Object?>{
            'status': 'failed',
            'message': 'Unexpected method ${call.method}',
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          routesChannel,
          MockStreamHandler.inline(
            onListen: (_, events) {
              _routesSink = events;
            },
          ),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          eventsChannel,
          MockStreamHandler.inline(
            onListen: (_, events) {
              _eventsSink = events;
            },
          ),
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(routesChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventsChannel, null);
  }

  void emitDlnaRoute() {
    _routesSink.success(<Object?>[
      <String, Object?>{
        'routeId': 'uuid:tv',
        'name': 'Living Room TV',
        'kind': 'dlna',
      },
    ]);
  }

  void emitEvent(Object? event) {
    _eventsSink.success(event);
  }
}

final class _TvHomeHarness {
  const _TvHomeHarness({
    required this.client,
    required this.historyStore,
    required this.sessionStore,
    required this.offlineController,
    required this.appSettings,
  });

  final _FakeTvHomeClient client;
  final BiliHistoryStore historyStore;
  final BiliSessionStore sessionStore;
  final _FakeOfflineController offlineController;
  final BiliAppSettings appSettings;
}

Future<_PlaybackHarness> _pumpPlaybackPage(
  WidgetTester tester, {
  BiliVideoDetail? detail,
  BiliVideoPageEntry? initialPage,
  BiliPlaybackPresentationMode presentationMode =
      BiliPlaybackPresentationMode.phone,
  List<String> sourceNormalizerPluginPaths = const <String>[],
}) async {
  final previousPlatform = VesperPlayerPlatform.instance;
  final platform = _FakePlaybackVesperPlatform();
  VesperPlayerPlatform.instance = platform;
  addTearDown(() {
    VesperPlayerPlatform.instance = previousPlatform;
  });
  const playerPluginsChannel = MethodChannel(
    'dev.ikaros.bilibili_player/player_plugins',
  );
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    playerPluginsChannel,
    (call) async {
      switch (call.method) {
        case 'bundledSourceNormalizerPluginLibraryPaths':
          return sourceNormalizerPluginPaths;
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      playerPluginsChannel,
      null,
    );
  });

  final playbackDetail = detail ?? _playbackDetail();
  final page = initialPage ?? playbackDetail.pages.first;
  final client = _FakePlaybackClient();
  final historyRoot = Directory(
    '${Directory.systemTemp.path}/bili-playback-widget-test-${DateTime.now().microsecondsSinceEpoch}',
  );
  addTearDown(() async {
    if (await historyRoot.exists()) {
      await historyRoot.delete(recursive: true);
    }
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });

  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: BiliPlaybackPage(
        detail: playbackDetail,
        initialPage: page,
        client: client,
        historyStore: BiliHistoryStore(baseDirectory: historyRoot),
        initialResolvedPlayback: _resolvedPlaybackFor(playbackDetail, page),
        presentationMode: presentationMode,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  return _PlaybackHarness(client: client, platform: platform);
}

Future<_TvHomeHarness> _pumpTvHomePage(
  WidgetTester tester, {
  bool initialForceTvMode = false,
  Size surfaceSize = const Size(1280, 720),
  double viewInsetsBottom = 0,
  List<BiliFeedVideo>? initialFeedItems,
  bool skipBootstrap = false,
}) async {
  final root = Directory(
    '${Directory.systemTemp.path}/bili-tv-home-widget-test-${DateTime.now().microsecondsSinceEpoch}',
  );
  final settings = BiliAppSettings(baseDirectory: root);
  await tester.runAsync(() => settings.setForceTvMode(initialForceTvMode));

  final harness = _TvHomeHarness(
    client: _FakeTvHomeClient(),
    historyStore: BiliHistoryStore(
      baseDirectory: Directory('${root.path}/history'),
    ),
    sessionStore: BiliSessionStore(
      baseDirectory: Directory('${root.path}/session'),
    ),
    offlineController: _FakeOfflineController(<BiliOfflineDownloadEntry>[]),
    appSettings: settings,
  );

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
  });

  await _pumpTvHomeFrame(
    tester,
    harness,
    surfaceSize: surfaceSize,
    viewInsetsBottom: viewInsetsBottom,
    initialFeedItems: initialFeedItems,
    skipBootstrap: skipBootstrap,
  );
  await _flushRealAsync(tester);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return harness;
}

Future<void> _flushRealAsync(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (predicate()) {
      return;
    }
  }
}

Future<void> _pumpTvHomeFrame(
  WidgetTester tester,
  _TvHomeHarness harness, {
  required Size surfaceSize,
  double viewInsetsBottom = 0,
  List<BiliFeedVideo>? initialFeedItems,
  bool skipBootstrap = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: surfaceSize,
          viewInsets: EdgeInsets.only(bottom: viewInsetsBottom),
        ),
        child: BiliTvHomePage(
          key: const ValueKey<String>('bili-tv-home-test-page'),
          client: harness.client,
          historyStore: harness.historyStore,
          sessionStore: harness.sessionStore,
          offlineController: harness.offlineController,
          appSettings: harness.appSettings,
          initialFeedItems: initialFeedItems ?? const <BiliFeedVideo>[],
          skipBootstrap: skipBootstrap,
        ),
      ),
    ),
  );
}

BiliOfflineDownloadEntry _offlineEntry({
  required String assetId,
  required int taskId,
  required String title,
  required VesperDownloadState state,
  int createdAtMs = 100,
}) {
  return BiliOfflineDownloadEntry(
    metadata: BiliOfflineDownloadMetadata(
      assetId: assetId,
      taskId: taskId,
      bvid: 'BV$taskId',
      cid: taskId,
      videoTitle: title,
      pageTitle: 'P$taskId · 正片',
      coverUrl: '',
      qualityLabel: '1080P',
      createdAtMs: createdAtMs,
    ),
    task: VesperDownloadTaskSnapshot(
      taskId: taskId,
      assetId: assetId,
      source: VesperDownloadSource(
        source: VesperPlayerSource(
          uri: 'vesper-generated://dash/$taskId/manifest.mpd',
          label: title,
          kind: VesperPlayerSourceKind.local,
          protocol: VesperPlayerSourceProtocol.dash,
        ),
        contentFormat: VesperDownloadContentFormat.dashSegments,
      ),
      profile: const VesperDownloadProfile(
        targetOutputFormat: VesperDownloadOutputFormat.mp4,
      ),
      state: state,
      progress: const VesperDownloadProgressSnapshot(
        receivedBytes: 512,
        totalBytes: 1024,
      ),
      assetIndex: const VesperDownloadAssetIndex(
        contentFormat: VesperDownloadContentFormat.dashSegments,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders bilibili product shell', (WidgetTester tester) async {
    await tester.pumpWidget(const BilibiliPlayerApp());
    await tester.pump();

    expect(find.text('搜索视频、BV 号或链接'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('tv focusable responds to touch taps', (
    WidgetTester tester,
  ) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TvFocusable(
            debugLabel: 'touch_target',
            onTap: () {
              tapCount += 1;
            },
            child: const SizedBox(
              width: 160,
              height: 56,
              child: Center(child: Text('TV 操作')),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('TV 操作'));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets('tv directional scope moves focus horizontally', (
    WidgetTester tester,
  ) async {
    final leftNode = FocusNode(debugLabel: 'left');
    final rightNode = FocusNode(debugLabel: 'right');
    addTearDown(leftNode.dispose);
    addTearDown(rightNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TvDirectionalFocusScope(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvFocusable(
                  focusNode: leftNode,
                  autofocus: true,
                  onTap: () {},
                  child: const SizedBox(
                    width: 120,
                    height: 56,
                    child: Text('左侧'),
                  ),
                ),
                const SizedBox(width: 24),
                TvFocusable(
                  focusNode: rightNode,
                  onTap: () {},
                  child: const SizedBox(
                    width: 120,
                    height: 56,
                    child: Text('右侧'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(leftNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(rightNode.hasFocus, isTrue);
  });

  testWidgets('tv focusable surface exposes focused visual state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 180,
            height: 120,
            child: TvFocusableSurface(
              autofocus: true,
              onTap: () {},
              builder: (context, focused) {
                return Center(child: Text(focused ? 'focused' : 'plain'));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('focused'), findsOneWidget);
  });

  testWidgets('tv settings switch only shows return home after mode changes', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(tester);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('TV 设置'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('返回首页并切换'), findsNothing);

    await tester.tap(find.text('强制 TV 模式'));
    await _flushRealAsync(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('返回首页并切换'), findsOneWidget);

    await tester.tap(find.text('强制 TV 模式'));
    await _flushRealAsync(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('返回首页并切换'), findsNothing);
  });

  testWidgets('tv settings about card adapts on narrow landscape', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(tester, surfaceSize: const Size(760, 430));

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final aboutCard = find.byKey(
      const ValueKey<String>('bili-tv-settings-about-card'),
    );
    expect(aboutCard, findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(aboutCard).width, greaterThan(0));
  });

  testWidgets('tv search keyboard inset keeps left rail width stable', (
    WidgetTester tester,
  ) async {
    const surfaceSize = Size(900, 520);
    final harness = await _pumpTvHomePage(tester, surfaceSize: surfaceSize);

    await tester.tap(find.text('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final rail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    final initialRailWidth = tester.getSize(rail).width;
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).resizeToAvoidBottomInset,
      isFalse,
    );

    await _pumpTvHomeFrame(
      tester,
      harness,
      surfaceSize: surfaceSize,
      viewInsetsBottom: 260,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(tester.getSize(rail).width, initialRailWidth);
  });

  testWidgets('tv search suffix keeps width and stops loading after results', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(tester);
    final searchCompleter = Completer<List<BiliSearchResult>>();
    harness.client.searchCompleter = searchCompleter;

    await tester.tap(find.text('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    final suffix = find.byKey(const ValueKey<String>('bili-tv-search-suffix'));
    expect(tester.getSize(suffix), const Size(48, 48));
    expect(
      find.descendant(
        of: suffix,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    searchCompleter.complete(const <BiliSearchResult>[
      BiliSearchResult(
        aid: 1,
        bvid: 'BVSEARCH0001',
        title: '搜索结果 1',
        author: 'UP',
        coverUrl: '',
        durationLabel: '03:00',
        playCountLabel: '1万',
        danmakuCountLabel: '10',
      ),
    ]);
    await _flushRealAsync(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(tester.getSize(suffix), const Size(48, 48));
    expect(
      find.descendant(
        of: suffix,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.text('搜索结果 1'), findsOneWidget);
  });

  testWidgets('tv home moves focus from rail into video grid', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    expect(find.text('推荐视频 0'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_recommend');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel?.startsWith('video_'),
      isTrue,
    );
  });

  testWidgets('tv rail focused item has stronger visual state', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    final focusedItem = find
        .ancestor(of: find.text('为你推荐'), matching: find.byType(TvFocusable))
        .last;
    final focusedContainer = tester.widget<AnimatedContainer>(
      find
          .descendant(of: focusedItem, matching: find.byType(AnimatedContainer))
          .at(1),
    );
    final decoration = focusedContainer.decoration! as BoxDecoration;
    final borderColor = decoration.border?.top.color;
    final fillColor = decoration.color;

    expect(borderColor?.a, greaterThan(0));
    expect(fillColor?.a, greaterThan(0));
  });

  testWidgets('tv home grid keeps vertical focus inside content area', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video_推荐视频 0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel?.startsWith('video_'),
      isTrue,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel?.startsWith('nav_'),
      isFalse,
    );
  });

  testWidgets('tv home regions nav loads section videos', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_regions');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(harness.client.requestedSections, isNotEmpty);
    expect(find.text('番剧'), findsWidgets);
    expect(find.text('番剧内容 0'), findsOneWidget);

    await tester.tap(
      find
          .ancestor(of: find.text('国创'), matching: find.byType(TvFocusable))
          .last,
    );
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(harness.client.requestedSections.last.id, 'guochuang');
    expect(find.text('国创内容 0'), findsOneWidget);
  });

  testWidgets(
    'tv home clipped cards do not leave focused overlay outside grid',
    (WidgetTester tester) async {
      await _pumpTvHomePage(
        tester,
        initialFeedItems: _tvFeedItems(),
        skipBootstrap: true,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();

      expect(find.text('推荐视频 0'), findsWidgets);
    },
  );

  testWidgets('tv home back opens exit confirmation dialog', (
    WidgetTester tester,
  ) async {
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('退出应用'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('退出应用'), findsNothing);
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();

    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isNotEmpty,
    );
  });

  testWidgets(
    'playback page places collection directly under intro',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester);

      expect(find.text('播放页测试视频'), findsWidgets);
      expect(find.text('这是一段播放页说明，下面应直接显示合集列表。'), findsOneWidget);
      expect(find.text('合集 · 共 3 个分 P'), findsOneWidget);
      expect(find.text('P1'), findsOneWidget);
      expect(find.text('正片'), findsOneWidget);
      expect(find.text('P2'), findsOneWidget);
      expect(find.text('花絮'), findsOneWidget);
      expect(find.text('P3'), findsOneWidget);
      expect(find.text('访谈'), findsOneWidget);
      expect(find.text('简介'), findsNothing);
      expect(find.text('播放 SDK'), findsNothing);
      expect(find.text('Manifest'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'android playback enables source normalizer without frame processor',
    (WidgetTester tester) async {
      const pluginPath =
          '/data/app/lib/arm64/libplayer_source_normalizer_ffmpeg.so';

      final harness = await _pumpPlaybackPage(
        tester,
        sourceNormalizerPluginPaths: const <String>[pluginPath],
      );

      expect(
        harness.platform.lastSourceNormalizerConfiguration?.mode,
        VesperSourceNormalizerMode.preferNormalized,
      );
      expect(
        harness.platform.lastSourceNormalizerConfiguration?.pluginLibraryPaths,
        <String>[pluginPath],
      );
      expect(
        harness.platform.lastFrameProcessorConfiguration?.mode,
        VesperFrameProcessorMode.disabled,
      );
      expect(
        harness.platform.lastFrameProcessorConfiguration?.pluginLibraryPaths,
        isEmpty,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'pgc playback page hides engagement actions and owner summary',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, detail: _pgcPlaybackDetail());

      expect(find.text('番剧播放页测试'), findsWidgets);
      expect(find.text('番剧简介下方应直接显示剧集。'), findsOneWidget);
      expect(find.text('剧集 · 共 3 话/集'), findsOneWidget);
      expect(find.text('第 1 话'), findsOneWidget);
      expect(find.text('第 2 话'), findsOneWidget);
      expect(find.text('第 3 话'), findsOneWidget);
      expect(find.text('点赞'), findsNothing);
      expect(find.text('硬币'), findsNothing);
      expect(find.text('收藏'), findsNothing);
      expect(find.text('分享'), findsNothing);
      expect(find.widgetWithText(FilledButton, '关注'), findsNothing);
      expect(find.text('播放页UP'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback engagement actions are visible and pending disables follow',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);
      final followCompleter = Completer<BiliVideoEngagement>();
      harness.client.followCompleter = followCompleter;

      expect(find.text('点赞'), findsOneWidget);
      expect(find.text('硬币'), findsOneWidget);
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('分享'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '关注'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '关注'))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.widgetWithText(FilledButton, '关注'));
      await tester.pump();

      expect(harness.client.followRequests, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '关注'))
            .onPressed,
        isNull,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(FilledButton, '关注'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      followCompleter.complete(
        harness.client.engagement.copyWith(isFollowingOwner: true),
      );
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback settings omit system playback controls',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('播放设置'), findsOneWidget);
      expect(find.text('分辨率'), findsOneWidget);
      expect(find.text('离线缓存'), findsOneWidget);
      expect(find.text('系统播放'), findsNothing);
      expect(find.text('锁屏控制'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback fullscreen locks landscape and back restores portrait',
    (WidgetTester tester) async {
      final platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await _pumpPlaybackPage(tester);

      List<List<String>> orientationCalls() {
        return platformCalls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .map((call) => (call.arguments as List<Object?>).cast<String>())
            .toList();
      }

      expect(orientationCalls().last, <String>['DeviceOrientation.portraitUp']);

      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pump();

      expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
      expect(orientationCalls().last, <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
      expect(find.text('播放页测试视频'), findsWidgets);
      expect(orientationCalls().last, <String>['DeviceOrientation.portraitUp']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'dlna load failure disconnects and keeps picker open',
    (WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter/platform_views'),
        (call) async {
          switch (call.method) {
            case 'create':
              return 1;
            case 'dispose':
            case 'resize':
            case 'offset':
            case 'touch':
            case 'setDirection':
            case 'clearFocus':
              return null;
          }
          return null;
        },
      );
      final externalPlayback = _ExternalPlaybackHarness(
        loadResult: const <String, Object?>{
          'status': 'unsupported',
          'message':
              'Host-prepared relay remux v1 only accepts remote HTTP(S) DASH sources.',
        },
      )..install();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('flutter/platform_views'),
          null,
        );
        externalPlayback.uninstall();
        debugDefaultTargetPlatformOverride = null;
      });

      await _pumpPlaybackPage(tester);

      await tester.tap(find.byIcon(Icons.cast_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      await tester.tap(find.text('DLNA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      externalPlayback.emitDlnaRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));

      expect(find.text('Living Room TV'), findsOneWidget);

      await tester.tap(find.text('Living Room TV'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('DLNA 投屏'), findsOneWidget);
      expect(
        find.text(
          'Host-prepared relay remux v1 only accepts remote HTTP(S) DASH sources.',
        ),
        findsWidgets,
      );
      expect(
        externalPlayback.calls.map((call) => call.method),
        contains('disconnect'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'tv playback locks landscape and touch toggles controls',
    (WidgetTester tester) async {
      final platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      List<List<String>> orientationCalls() {
        return platformCalls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .map((call) => (call.arguments as List<Object?>).cast<String>())
            .toList();
      }

      expect(orientationCalls().last, <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      expect(find.text('快退 10s'), findsNothing);

      await tester.tapAt(const Offset(600, 450));
      await tester.pump();

      expect(find.text('快退 10s'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'tv playback uses dedicated stage without mobile player chrome',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      expect(find.byType(vesper_ui.VesperPlayerStage), findsNothing);
      expect(find.byType(VesperPlayerView), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback context menu key shows controls',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      expect(find.text('快退 10s'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();

      expect(find.text('快退 10s'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback opens quality speed and page panels separately',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .ancestor(of: find.text('清晰度'), matching: find.byType(TvFocusable))
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('1080P'), findsOneWidget);
      expect(find.text('1.25x'), findsNothing);
      expect(find.textContaining('P2'), findsNothing);

      await tester.tap(
        find
            .ancestor(
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('1.25x'), findsOneWidget);
      expect(find.text('1080P'), findsNothing);
      expect(find.textContaining('P2'), findsNothing);

      await tester.tap(
        find
            .ancestor(
              of: find.text('分P').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('P2'), findsOneWidget);
      expect(find.text('P2'), findsOneWidget);
      expect(find.text('1.25x'), findsNothing);
      expect(find.text('1080P'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback quality panel marks effective playing quality',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(of: find.text('清晰度'), matching: find.byType(TvFocusable))
            .last,
      );
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_1080P');
      expect(find.text('1080P'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback page panel uses right drawer with focused and selected states',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('分P').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('P1'), findsOneWidget);
      expect(find.text('P2'), findsOneWidget);
      expect(find.text('P3'), findsOneWidget);

      final drawerLeft = tester.getTopLeft(find.text('分P').last).dx;
      expect(drawerLeft, greaterThan(780));

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_P1');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_P2');

      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback pgc page panel uses episode copy',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        detail: _pgcPlaybackDetail(),
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('分P').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('选集'), findsOneWidget);
      expect(find.text('第 1 集'), findsOneWidget);
      expect(find.text('第 2 集'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback control bar orders play before rewind',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();

      final playX = tester.getTopLeft(find.text('播放')).dx;
      final rewindX = tester.getTopLeft(find.text('快退 10s')).dx;
      final forwardX = tester.getTopLeft(find.text('快进 10s')).dx;
      final qualityX = tester.getTopLeft(find.text('清晰度')).dx;
      final speedX = tester.getTopLeft(find.text('倍速')).dx;
      final pagesX = tester.getTopLeft(find.text('分P')).dx;

      expect(playX, lessThan(rewindX));
      expect(rewindX, lessThan(forwardX));
      expect(forwardX, lessThan(qualityX));
      expect(qualityX, lessThan(speedX));
      expect(speedX, lessThan(pagesX));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback panel handles left and right before seek',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('1.25x'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(harness.platform.seekRatios, isEmpty);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel?.startsWith('tv_panel_'),
        isTrue,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback panel resets scroll per function to selected option',
    (WidgetTester tester) async {
      final pages = List<BiliVideoPageEntry>.generate(
        18,
        (index) => BiliVideoPageEntry(
          cid: 900 + index,
          pageNumber: index + 1,
          title: '长列表 ${index + 1}',
          durationSeconds: 60,
        ),
      );
      final detail = BiliVideoDetail(
        aid: 5001,
        bvid: 'BV1longpages',
        title: '长选集测试',
        ownerMid: 0,
        ownerName: '番剧',
        ownerAvatarUrl: '',
        coverUrl: '',
        description: '',
        publishedAtLabel: null,
        playCountLabel: '1',
        danmakuCountLabel: '1',
        replyCountLabel: '1',
        likeCountLabel: '1',
        coinCountLabel: '1',
        favoriteCountLabel: '1',
        shareCountLabel: '1',
        pages: pages,
      );

      await _pumpPlaybackPage(
        tester,
        detail: detail,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('分P').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -520));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .ancestor(
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_1.0x');
      expect(find.text('1.0x'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback root back returns to tv home',
    (WidgetTester tester) async {
      final previousPlatform = VesperPlayerPlatform.instance;
      VesperPlayerPlatform.instance = _FakePlaybackVesperPlatform();
      addTearDown(() {
        VesperPlayerPlatform.instance = previousPlatform;
      });

      final root = Directory(
        '${Directory.systemTemp.path}/bili-tv-root-back-test-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: BiliPlaybackPage(
            detail: _playbackDetail(),
            initialPage: _playbackDetail().pages.first,
            client: _FakePlaybackClient(),
            historyStore: BiliHistoryStore(baseDirectory: root),
            initialResolvedPlayback: _resolvedPlaybackFor(
              _playbackDetail(),
              _playbackDetail().pages.first,
            ),
            presentationMode: BiliPlaybackPresentationMode.tv,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(BiliTvHomePage), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback remote back pops to existing tv home without exiting',
    (WidgetTester tester) async {
      final previousPlatform = VesperPlayerPlatform.instance;
      VesperPlayerPlatform.instance = _FakePlaybackVesperPlatform();
      addTearDown(() {
        VesperPlayerPlatform.instance = previousPlatform;
      });

      final platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await _pumpTvHomePage(
        tester,
        initialFeedItems: _tvFeedItems(),
        skipBootstrap: true,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('feed_BVTV00000000')));
      await _flushRealAsync(tester);
      await tester.pumpAndSettle();

      expect(find.byType(BiliPlaybackPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(BiliTvHomePage), findsOneWidget);
      expect(find.byType(BiliPlaybackPage), findsNothing);
      expect(
        platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
        isEmpty,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback hidden controls use left and right for ten second seeks',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(
        harness.platform.seekRatios.single,
        closeTo(10000 / 120000, 0.001),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('offline cache page renders active task progress', (
    WidgetTester tester,
  ) async {
    final controller = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[
        BiliOfflineDownloadEntry(
          metadata: const BiliOfflineDownloadMetadata(
            assetId: 'asset-1',
            taskId: 1,
            bvid: 'BV1',
            cid: 11,
            videoTitle: '缓存视频',
            pageTitle: 'P1 · 正片',
            coverUrl: '',
            qualityLabel: '1080P',
            createdAtMs: 100,
          ),
          task: const VesperDownloadTaskSnapshot(
            taskId: 1,
            assetId: 'asset-1',
            source: VesperDownloadSource(
              source: VesperPlayerSource(
                uri: 'vesper-generated://dash/manifest.mpd',
                label: '缓存视频',
                kind: VesperPlayerSourceKind.local,
                protocol: VesperPlayerSourceProtocol.dash,
              ),
              contentFormat: VesperDownloadContentFormat.dashSegments,
            ),
            profile: VesperDownloadProfile(
              targetOutputFormat: VesperDownloadOutputFormat.mp4,
            ),
            state: VesperDownloadState.downloading,
            progress: VesperDownloadProgressSnapshot(
              receivedBytes: 512,
              totalBytes: 1024,
            ),
            assetIndex: VesperDownloadAssetIndex(
              contentFormat: VesperDownloadContentFormat.dashSegments,
            ),
          ),
        ),
      ],
      storageUsage: const BiliOfflineStorageUsage(
        cacheBytes: 2 * 1024 * 1024,
        freeBytes: 8 * 1024 * 1024,
        totalBytes: 10 * 1024 * 1024,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await tester.pump();

    expect(find.text('离线缓存'), findsOneWidget);
    expect(find.text('存储空间'), findsOneWidget);
    expect(find.text('缓存占用'), findsOneWidget);
    expect(find.text('剩余空间'), findsOneWidget);
    expect(find.text('正在缓存'), findsOneWidget);
    expect(find.text('缓存视频'), findsOneWidget);
    expect(find.textContaining('缓存中'), findsOneWidget);
  });

  testWidgets('offline cache task action pending state is per task', (
    WidgetTester tester,
  ) async {
    final pauseCompleter = Completer<void>();
    final controller = _FakeOfflineController(<BiliOfflineDownloadEntry>[
      _offlineEntry(
        assetId: 'asset-1',
        taskId: 1,
        title: '缓存视频 A',
        state: VesperDownloadState.downloading,
        createdAtMs: 200,
      ),
      _offlineEntry(
        assetId: 'asset-2',
        taskId: 2,
        title: '缓存视频 B',
        state: VesperDownloadState.downloading,
        createdAtMs: 100,
      ),
    ])..pauseCompleter = pauseCompleter;

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('offline-task-action-1')),
    );
    await tester.pump();

    expect(controller.pausedTaskIds, <int>[1]);
    expect(
      find.byKey(const ValueKey<String>('offline-task-action-pending-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('offline-task-action-pending-2')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('offline-task-action-2')),
        matching: find.byIcon(Icons.pause_rounded),
      ),
      findsOneWidget,
    );

    await tester.runAsync(() async {
      pauseCompleter.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('offline-task-action-pending-1')),
      findsNothing,
    );
  });

  testWidgets('offline cache page deletes item on right swipe', (
    WidgetTester tester,
  ) async {
    final controller = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[
        BiliOfflineDownloadEntry(
          metadata: const BiliOfflineDownloadMetadata(
            assetId: 'asset-1',
            taskId: 1,
            bvid: 'BV1',
            cid: 11,
            videoTitle: '缓存视频',
            pageTitle: 'P1 · 正片',
            coverUrl: '',
            qualityLabel: '1080P',
            createdAtMs: 100,
          ),
          task: const VesperDownloadTaskSnapshot(
            taskId: 1,
            assetId: 'asset-1',
            source: VesperDownloadSource(
              source: VesperPlayerSource(
                uri: 'file:///tmp/offline.mp4',
                label: '缓存视频',
                kind: VesperPlayerSourceKind.local,
                protocol: VesperPlayerSourceProtocol.file,
              ),
              contentFormat: VesperDownloadContentFormat.singleFile,
            ),
            profile: VesperDownloadProfile(
              targetOutputFormat: VesperDownloadOutputFormat.mp4,
            ),
            state: VesperDownloadState.completed,
            progress: VesperDownloadProgressSnapshot(
              receivedBytes: 1024,
              totalBytes: 1024,
            ),
            assetIndex: VesperDownloadAssetIndex(
              contentFormat: VesperDownloadContentFormat.singleFile,
              completedPath: '/tmp/offline.mp4',
            ),
          ),
        ),
      ],
      storageUsage: const BiliOfflineStorageUsage(
        cacheBytes: 1024,
        freeBytes: 8 * 1024 * 1024,
        totalBytes: 8 * 1024 * 1024,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await tester.pump();

    await tester.drag(find.byType(Dismissible), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(controller.removedAssetIds, <String>['asset-1']);
    expect(find.text('缓存视频'), findsNothing);
    expect(find.text('还没有离线缓存'), findsOneWidget);
  });

  testWidgets('offline cache item opens action sheet from more button', (
    WidgetTester tester,
  ) async {
    final controller = _FakeOfflineController(<BiliOfflineDownloadEntry>[
      BiliOfflineDownloadEntry(
        metadata: const BiliOfflineDownloadMetadata(
          assetId: 'asset-1',
          taskId: 1,
          bvid: 'BV1',
          cid: 11,
          videoTitle: '缓存视频',
          pageTitle: 'P1 · 正片',
          coverUrl: '',
          qualityLabel: '1080P',
          outputPath: '/tmp/offline.mp4',
          createdAtMs: 100,
        ),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('导出到相册'), findsOneWidget);
    expect(find.text('导出为可在任意播放器中播放的 MP4'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('app settings reads and toggles force TV mode', (
    WidgetTester tester,
  ) async {
    final root = Directory(
      '${Directory.systemTemp.path}/bili-settings-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    final settings = BiliAppSettings(baseDirectory: root);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    await tester.runAsync(() => settings.setForceTvMode(false));
    await tester.pumpWidget(
      MaterialApp(
        home: BiliSettingsPage(
          appSettings: settings,
          sessionStore: BiliSessionStore(baseDirectory: root),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('当前：根据设备自动选择'));

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('当前：根据设备自动选择'), findsOneWidget);
    expect(find.text('返回首页并切换'), findsNothing);

    await tester.tap(find.text('强制 TV 模式'));
    await _pumpUntilFound(tester, find.text('当前：TV 模式界面'));

    expect(find.text('当前：TV 模式界面'), findsOneWidget);
    expect(find.text('返回首页并切换'), findsOneWidget);
    expect(await tester.runAsync(settings.getForceTvMode), isTrue);
  });

  testWidgets('app settings logout clears cookies and pauses offline cache', (
    WidgetTester tester,
  ) async {
    final root = Directory(
      '${Directory.systemTemp.path}/bili-settings-logout-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    final client = BiliClient();
    final sessionStore = BiliSessionStore(baseDirectory: root);
    final offlineController = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    await tester.runAsync(() async {
      await sessionStore.saveCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BiliSettingsPage(
          appSettings: BiliAppSettings(baseDirectory: root),
          client: client,
          sessionStore: sessionStore,
          offlineController: offlineController,
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('退出登录'));

    expect(find.text('当前已保存本地登录 cookie'), findsOneWidget);

    await tester.tap(find.text('退出登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '退出'),
      ),
    );
    await _pumpUntil(tester, () => offlineController.pauseAllActiveCalls == 1);
    await _pumpUntilFound(tester, find.text('当前未保存本地登录 cookie'));

    expect(offlineController.pauseAllActiveCalls, 1);
    expect(client.hasAuthenticatedSession, isFalse);
    expect(await tester.runAsync(sessionStore.loadCookies), isEmpty);
    expect(find.widgetWithText(TextButton, '退出登录'), findsNothing);
    expect(find.text('已退出登录，离线缓存任务已暂停'), findsOneWidget);
  });

  testWidgets('QR login sheet refreshes expired ticket', (
    WidgetTester tester,
  ) async {
    final client = _FakeQrLoginClient()
      ..pollResults.addAll(const <BiliQrLoginPollResult>[
        BiliQrLoginPollResult(
          status: BiliQrLoginStatus.expired,
          message: '二维码已过期',
          timestampMs: 1000,
        ),
        BiliQrLoginPollResult(
          status: BiliQrLoginStatus.scannedAwaitingConfirm,
          message: '已扫码',
          timestampMs: 2000,
        ),
      ]);
    final root = Directory(
      '${Directory.systemTemp.path}/bili-qr-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () async {
                  await showModalBottomSheet<BiliUserProfile>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => BiliQrLoginSheet(
                      client: client,
                      sessionStore: BiliSessionStore(baseDirectory: root),
                    ),
                  );
                },
                child: const Text('登录'),
              ),
            );
          },
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.text('登录'));
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('二维码已失效，刷新后重新扫码。'), findsOneWidget);
    expect(find.textContaining('状态更新时间'), findsOneWidget);
    expect(client.generatedTickets, 1);

    await tester.tap(find.text('刷新二维码'));
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('已经扫到码了，等手机端确认。'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('已扫码，继续等待'), findsOneWidget);
    expect(client.generatedTickets, 2);
    expect(client.polledKeys, <String>['key-1', 'key-2']);
  });

  testWidgets('QR login sheet pops profile after confirmed login', (
    WidgetTester tester,
  ) async {
    final client = _FakeQrLoginClient()
      ..pollResults.add(
        const BiliQrLoginPollResult(
          status: BiliQrLoginStatus.confirmed,
          message: '登录成功',
          timestampMs: 3000,
        ),
      );
    final root = Directory(
      '${Directory.systemTemp.path}/bili-qr-confirm-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    BiliUserProfile? poppedProfile;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () async {
                  poppedProfile = await showModalBottomSheet<BiliUserProfile>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => BiliQrLoginSheet(
                      client: client,
                      sessionStore: BiliSessionStore(baseDirectory: root),
                    ),
                  );
                },
                child: const Text('登录'),
              ),
            );
          },
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.text('登录'));
    await tester.pump();
    await _flushRealAsync(tester);
    await _pumpUntilAbsent(tester, find.text('扫码登录哔哩哔哩'));

    expect(find.text('扫码登录哔哩哔哩'), findsNothing);
    expect(poppedProfile?.name, '扫码用户');
    final cookies = await tester.runAsync(
      () => BiliSessionStore(baseDirectory: root).loadCookies(),
    );
    expect(cookies, {'SESSDATA': 'cookie'});
  });

  testWidgets('region video page loads, retries, and paginates', (
    WidgetTester tester,
  ) async {
    final client = _FakeRegionClient()..firstPageError = '首屏失败';

    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: BiliRegionVideoPage(
          section: _testRegionSection,
          client: client,
          historyStore: const BiliHistoryStore(),
          offlineController: _FakeOfflineController(
            <BiliOfflineDownloadEntry>[],
          ),
        ),
      ),
    );
    await _flushRealAsync(tester);
    await tester.pump();

    expect(find.text('首屏失败'), findsOneWidget);
    expect(client.requestedPages, <int>[1]);

    client.firstPageError = null;
    await tester.tap(find.text('重试'));
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.text('分区视频 1-0'), findsOneWidget);
    expect(client.requestedPages, <int>[1, 1]);

    await tester.drag(find.byType(GridView), const Offset(0, -1600));
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(client.requestedPages, contains(2));
    expect(find.text('分区视频 2-2'), findsOneWidget);
  });

  testWidgets('cache download panel enqueues selected page', (
    WidgetTester tester,
  ) async {
    final detail = _testDetail();
    final controller = _FakeCacheController(
      options: _testDownloadOptions(detail),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: BiliCacheDownloadPanel(
              detail: detail,
              currentPage: detail.pages.first,
              selectedQualityId: null,
              codecPreference: BiliVideoCodecPreference.automatic,
              controller: controller,
              onMessage: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('下载缓存'), findsOneWidget);
    expect(find.text('合集'), findsOneWidget);

    await tester.tap(find.text('720P'));
    await tester.pump();
    await tester.tap(find.text('正片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.enqueuedCids, <int>[11]);
    expect(controller.enqueuedQualityIds, <int>[64]);
  });

  testWidgets('cache download panel shows loading, error, and retry states', (
    WidgetTester tester,
  ) async {
    final detail = _testDetail();
    final resolveCompleter = Completer<BiliDownloadOptions>();
    final controller = _FakeCacheController(
      options: _testDownloadOptions(detail),
    )..resolveCompleter = resolveCompleter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BiliCacheDownloadPanel(
            detail: detail,
            currentPage: detail.pages.first,
            selectedQualityId: null,
            codecPreference: BiliVideoCodecPreference.automatic,
            controller: controller,
            onMessage: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    resolveCompleter.completeError('options failed');
    await _flushRealAsync(tester);
    await tester.pump();

    expect(find.text('options failed'), findsOneWidget);

    controller
      ..resolveCompleter = null
      ..resolveError = null;
    await tester.tap(find.text('重试'));
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.text('1080P'), findsOneWidget);
    expect(find.text('合集'), findsOneWidget);
  });

  testWidgets('cache download panel scopes pending state per episode', (
    WidgetTester tester,
  ) async {
    final detail = _testDetail();
    final enqueueCompleter = Completer<BiliOfflineDownloadEntry>();
    final messages = <String>[];
    final controller = _FakeCacheController(
      options: _testDownloadOptions(detail),
    )..enqueueCompleter = enqueueCompleter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BiliCacheDownloadPanel(
            detail: detail,
            currentPage: detail.pages.first,
            selectedQualityId: null,
            codecPreference: BiliVideoCodecPreference.automatic,
            controller: controller,
            onMessage: messages.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('正片'));
    await tester.pump();

    expect(controller.enqueuedCids, <int>[11]);
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('正片'), matching: find.byType(InkWell))
            .first,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('花絮'), matching: find.byType(InkWell))
            .first,
        matching: find.byIcon(Icons.download_rounded),
      ),
      findsOneWidget,
    );

    enqueueCompleter.complete(
      BiliOfflineDownloadEntry(
        metadata: const BiliOfflineDownloadMetadata(
          assetId: 'asset-11',
          taskId: 11,
          bvid: 'BV1xx411c7mD',
          cid: 11,
          videoTitle: '首页视频',
          pageTitle: 'P1 · 正片',
          coverUrl: '',
          qualityLabel: '1080P',
          createdAtMs: 100,
        ),
      ),
    );
    await _flushRealAsync(tester);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(messages, <String>['已加入缓存：P1']);
  });

  testWidgets('cache panel opens offline cache page', (
    WidgetTester tester,
  ) async {
    final detail = _testDetail();
    final controller = _FakeCacheController(
      options: _testDownloadOptions(detail),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: BiliCacheDownloadPanel(
              detail: detail,
              currentPage: detail.pages.first,
              selectedQualityId: null,
              codecPreference: BiliVideoCodecPreference.automatic,
              controller: controller,
              onMessage: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看缓存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('离线缓存'), findsOneWidget);
    expect(find.text('存储空间'), findsOneWidget);
  });
}
