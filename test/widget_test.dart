import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vesper_media/platform_app.dart';
import 'package:vesper_media/app/home_page.dart';
import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/app/design/app_theme_controller.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_hub_page.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/models/bili_region_models.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_library_page.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_page.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_region_hub_page.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_region_video_page.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_settings_page.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/common/widgets/bili_cache_download_panel.dart';
import 'package:vesper_media/bili/common/widgets/bili_qr_login_sheet.dart';
import 'package:vesper_media/bili/tv_mode/pages/bili_tv_home_page.dart';
import 'package:vesper_media/bili/tv_mode/widgets/bili_tv_qr_login_dialog.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_directional_focus_scope.dart';
import 'package:vesper_media/media/tv/media_tv_focusable.dart';
import 'package:vesper_media/download/download.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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
  Future<String?> resolvePlayableCachePath(
    BiliOfflineDownloadEntry entry,
  ) async {
    for (final path in <String?>[
      entry.metadata.outputPath,
      entry.task?.assetIndex.completedPath,
    ]) {
      if (path != null && path.isNotEmpty && await File(path).exists()) {
        return path;
      }
    }
    return null;
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
  bool get hasAuthenticatedSession => true;

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

final class _UnauthenticatedRegionClient extends BiliClient {
  bool fetchCalled = false;

  @override
  bool get hasAuthenticatedSession => false;

  @override
  Future<List<BiliRegionVideo>> fetchRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) async {
    fetchCalled = true;
    return const <BiliRegionVideo>[];
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

final class _FakeTvHomeClient extends BiliClient {
  factory _FakeTvHomeClient({
    List<BiliFeedVideo>? feedItems,
    bool emptyFollowing = false,
  }) {
    final libraryHttpClient = _FakeTvHomeLibraryHttpClient(
      emptyFollowing: emptyFollowing,
    );
    return _FakeTvHomeClient._(libraryHttpClient, feedItems: feedItems);
  }

  _FakeTvHomeClient._(this.libraryHttpClient, {List<BiliFeedVideo>? feedItems})
    : feedItems = feedItems ?? _tvFeedItems(),
      super(httpClient: libraryHttpClient);

  final List<BiliFeedVideo> feedItems;
  final _FakeTvHomeLibraryHttpClient libraryHttpClient;
  final List<BiliRegionSection> requestedSections = <BiliRegionSection>[];
  final List<String> requestedVideoDetails = <String>[];
  var recommendedFeedRequests = 0;
  Completer<List<BiliSearchResult>>? searchCompleter;
  bool loggedIn = false;
  int generatedQrTickets = 0;

  int get followingRequests =>
      libraryHttpClient.requestCount('/x/relation/followings');

  int get spaceProfileRequests =>
      libraryHttpClient.requestCount('/x/web-interface/card');

  int get spaceVideoRequests =>
      libraryHttpClient.requestCount('/x/space/wbi/arc/search');

  @override
  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) async {
    recommendedFeedRequests += 1;
    return page == 1 ? feedItems : const <BiliFeedVideo>[];
  }

  @override
  Future<BiliUserProfile> fetchCurrentUserProfile() async {
    return BiliUserProfile(
      isLoggedIn: loggedIn,
      name: loggedIn ? '测试用户' : '未登录',
      avatarUrl: '',
      mid: loggedIn ? 42 : null,
    );
  }

  @override
  Future<BiliQrLoginTicket> generateQrLoginTicket() async {
    generatedQrTickets += 1;
    return BiliQrLoginTicket(
      url: 'https://example.test/tv-qr/$generatedQrTickets',
      qrcodeKey: 'tv-key-$generatedQrTickets',
    );
  }

  @override
  Future<BiliQrLoginPollResult> pollQrLogin(String qrcodeKey) async {
    return const BiliQrLoginPollResult(
      status: BiliQrLoginStatus.waitingForScan,
      message: '等待扫码',
    );
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
    requestedVideoDetails.add(bvid);
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

final class _FakeTvHomeLibraryHttpClient implements HttpClient {
  _FakeTvHomeLibraryHttpClient({this.emptyFollowing = false});

  final bool emptyFollowing;
  final List<Uri> requestedUris = <Uri>[];
  String? _userAgent;

  int requestCount(String path) =>
      requestedUris.where((uri) => uri.path == path).length;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) => _userAgent = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUris.add(url);
    return _FakeTvHomeHttpRequest(_responseFor(url));
  }

  _FakeTvHomeHttpResponse _responseFor(Uri url) {
    if (url.path == '/x/web-interface/nav') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'isLogin': true,
          'mid': 42,
          'wbi_img': <String, Object?>{
            'img_url': 'https://i0.hdslb.com/bfs/wbi/img.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/sub.png',
          },
        },
      });
    }
    if (url.path == '/x/relation/followings') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'list': emptyFollowing
              ? const <Object?>[]
              : <Object?>[
                  <String, Object?>{
                    'mid': 7,
                    'uname': '测试 UP',
                    'face': '',
                    'sign': '简介',
                  },
                ],
        },
      });
    }
    if (url.path == '/x/web-interface/card') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'card': <String, Object?>{
            'mid': 7,
            'name': '测试 UP 空间',
            'face': '',
            'sign': '空间简介',
            'fans': 12000,
          },
          'follower': 12000,
          'archive_count': 1,
        },
      });
    }
    if (url.path == '/x/space/wbi/arc/search') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'list': <String, Object?>{
            'vlist': <Object?>[
              <String, Object?>{
                'aid': 70,
                'bvid': 'BV1space0001',
                'title': '空间视频',
                'pic': '',
                'length': '02:03',
                'created': 1786291200,
                'play': 12000,
                'mid': 7,
                'author': '测试 UP 空间',
              },
            ],
          },
          'page': <String, Object?>{'pn': 1, 'ps': 30, 'count': 1},
        },
      });
    }
    return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
  }

  _FakeTvHomeHttpResponse _json(Map<String, Object?> value) {
    return _FakeTvHomeHttpResponse(jsonEncode(value));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeTvHomeHttpRequest implements HttpClientRequest {
  _FakeTvHomeHttpRequest(this.response);

  final _FakeTvHomeHttpResponse response;
  final HttpHeaders _headers = _FakeTvHomeHttpHeaders();
  int _contentLength = -1;

  @override
  HttpHeaders get headers => _headers;

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) => _contentLength = value;

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeTvHomeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  const _FakeTvHomeHttpResponse(this.body);

  final String body;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  HttpHeaders get headers => _FakeTvHomeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeTvHomeHttpHeaders implements HttpHeaders {
  ContentType? _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) => _contentType = value;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PlaybackHarness {
  _PlaybackHarness({
    required this.client,
    required this.platform,
    required this.historyStore,
  });

  final _FakePlaybackClient client;
  final _FakePlaybackVesperPlatform platform;
  final BiliHistoryStore historyStore;
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
  final AppSettingsStore appSettings;
}

Future<_PlaybackHarness> _pumpPlaybackPage(
  WidgetTester tester, {
  BiliVideoDetail? detail,
  BiliVideoPageEntry? initialPage,
  BiliPlaybackPresentationMode presentationMode =
      BiliPlaybackPresentationMode.phone,
  Size surfaceSize = const Size(1200, 900),
  VesperPlayerSnapshot? initialSnapshot,
  int initialPositionMs = 0,
  void Function(_FakePlaybackClient client)? configureClient,
  BiliResolvedPlayback? initialResolvedPlayback,
  ThemeData? theme,
  bool externalPlaybackMockInstalled = false,
}) async {
  final previousPlatform = VesperPlayerPlatform.instance;
  final platform = _FakePlaybackVesperPlatform(
    initialSnapshot: initialSnapshot ?? _playbackSnapshot,
  );
  VesperPlayerPlatform.instance = platform;
  addTearDown(() {
    VesperPlayerPlatform.instance = previousPlatform;
  });
  addTearDown(platform.closeEvents);
  const externalPlaybackEventsChannel = EventChannel(
    'io.github.ikaros.vesper_player_external_playback/events',
  );
  if (!externalPlaybackMockInstalled &&
      defaultTargetPlatform == TargetPlatform.android) {
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      externalPlaybackEventsChannel,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        externalPlaybackEventsChannel,
        null,
      );
    });
  }

  final playbackDetail = detail ?? _playbackDetail();
  final page = initialPage ?? playbackDetail.pages.first;
  final client = _FakePlaybackClient();
  configureClient?.call(client);
  final historyRoot = Directory(
    '${Directory.systemTemp.path}/bili-playback-widget-test-${DateTime.now().microsecondsSinceEpoch}',
  );
  final historyStore = BiliHistoryStore(baseDirectory: historyRoot);
  addTearDown(() async {
    if (await historyRoot.exists()) {
      await historyRoot.delete(recursive: true);
    }
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: BiliPlaybackPage(
        detail: playbackDetail,
        initialPage: page,
        client: client,
        historyStore: historyStore,
        initialResolvedPlayback:
            initialResolvedPlayback ??
            _resolvedPlaybackFor(playbackDetail, page),
        initialPositionMs: initialPositionMs,
        presentationMode: presentationMode,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await _flushRealAsync(tester);
  await tester.pump();

  return _PlaybackHarness(
    client: client,
    platform: platform,
    historyStore: historyStore,
  );
}

Future<_TvHomeHarness> _pumpTvHomePage(
  WidgetTester tester, {
  bool initialForceTvMode = false,
  Size surfaceSize = const Size(1280, 720),
  double viewInsetsBottom = 0,
  List<BiliFeedVideo>? initialFeedItems,
  List<BiliPlaybackHistoryEntry> initialHistoryEntries =
      const <BiliPlaybackHistoryEntry>[],
  bool skipBootstrap = false,
  bool loggedIn = false,
  bool authenticatedSession = false,
  bool emptyFollowing = false,
}) async {
  final root = Directory(
    '${Directory.systemTemp.path}/bili-tv-home-widget-test-${DateTime.now().microsecondsSinceEpoch}',
  );
  final settings = AppSettingsStore(baseDirectory: root);
  await tester.runAsync(() => settings.setForceTvMode(initialForceTvMode));

  final harness = _TvHomeHarness(
    client: _FakeTvHomeClient(emptyFollowing: emptyFollowing),
    historyStore: BiliHistoryStore(
      baseDirectory: Directory('${root.path}/history'),
    ),
    sessionStore: BiliSessionStore(
      baseDirectory: Directory('${root.path}/session'),
    ),
    offlineController: _FakeOfflineController(<BiliOfflineDownloadEntry>[]),
    appSettings: settings,
  );
  harness.client.loggedIn = loggedIn;
  if (authenticatedSession) {
    harness.client.restoreCookies(const <String, String>{
      'SESSDATA': 'sess',
      'bili_jct': 'csrf',
      'DedeUserID': '42',
      'buvid3': 'b3',
      'buvid4': 'b4',
    });
  }

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
    initialHistoryEntries: initialHistoryEntries,
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
  List<BiliPlaybackHistoryEntry> initialHistoryEntries =
      const <BiliPlaybackHistoryEntry>[],
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
          initialHistoryEntries: initialHistoryEntries,
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
    await tester.pumpWidget(const PlatformApp());
    await tester.pump();

    expect(find.text('搜索视频、BV 号或链接'), findsOneWidget);
    expect(find.byType(GlassTabBar), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
  });

  testWidgets('PlatformApp fallback mode uses the injected app settings', (
    WidgetTester tester,
  ) async {
    const secureStorageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorageChannel,
      (_) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        secureStorageChannel,
        null,
      );
    });
    final root = Directory(
      '${Directory.systemTemp.path}/vesper-app-mode-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    final settings = AppSettingsStore(baseDirectory: root);
    final client = _FakeTvHomeClient();
    final offlineController = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[],
    );
    await tester.runAsync(() => settings.setForceTvMode(true));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    await tester.pumpWidget(
      PlatformApp(
        appSettings: settings,
        client: client,
        offlineController: offlineController,
      ),
    );
    await tester.pump();

    final homePage = tester.widget<HomePage>(find.byType(HomePage));
    await tester.runAsync(() => homePage.uiModeController!.refresh());
    await tester.pump();

    expect(find.byType(BiliTvHomePage), findsOneWidget);
  });

  testWidgets('HomePage fallback mode uses the injected app settings', (
    WidgetTester tester,
  ) async {
    final root = Directory(
      '${Directory.systemTemp.path}/home-page-mode-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    final settings = AppSettingsStore(baseDirectory: root);
    final client = _FakeTvHomeClient();
    final historyStore = BiliHistoryStore(
      baseDirectory: Directory('${root.path}/history'),
    );
    final sessionStore = BiliSessionStore(
      baseDirectory: Directory('${root.path}/session'),
    );
    final offlineController = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[],
    );
    await tester.runAsync(() => settings.setForceTvMode(true));
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
        home: HomePage(
          appSettings: settings,
          client: client,
          historyStore: historyStore,
          sessionStore: sessionStore,
          offlineController: offlineController,
        ),
      ),
    );
    await tester.pump();

    final hubPage = tester.widget<BiliHubPage>(find.byType(BiliHubPage));
    await tester.runAsync(() => hubPage.uiModeController!.refresh());
    await tester.pump();

    expect(find.byType(BiliTvHomePage), findsOneWidget);
  });

  testWidgets('mobile shell keeps content and liquid tabs inside safe areas', (
    WidgetTester tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844)
      ..padding = const FakeViewPadding(top: 44, bottom: 24);
    addTearDown(() {
      tester.view
        ..resetDevicePixelRatio()
        ..resetPhysicalSize()
        ..resetPadding();
    });

    await tester.pumpWidget(const PlatformApp());
    await tester.pump();

    final contentRect = tester.getRect(find.byType(CustomScrollView).first);
    final bottomBarRect = tester.getRect(find.byType(GlassTabBar));
    final bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView).first,
    );
    final clearanceSliver = scrollView.slivers.last as SliverToBoxAdapter;
    final clearance = clearanceSliver.child as SizedBox;
    final topClearanceSliver = scrollView.slivers.first as SliverToBoxAdapter;
    final topClearance = topClearanceSliver.child as SizedBox;

    expect(contentRect.top, 0);
    expect(contentRect.bottom, greaterThan(bottomBarRect.top));
    expect(topClearance.height, 44 + 44);
    // ignore: experimental_member_use
    expect(find.byType(GlassAdaptiveScope), findsNothing);
    expect(bottomBar.quality, isNull);
    expect(bottomBar.settings, isNotNull);
    expect(bottomBar.settings!.blur, 12);
    expect(bottomBar.settings!.thickness, 14);
    expect(bottomBar.settings!.glassColor, AppVisualTheme.light.glassTint);
    expect(bottomBar.indicatorSettings, isNull);
    expect(bottomBar.indicatorColor, AppVisualTokens.neutralSelection);
    expect(bottomBar.selectedIconColor, AppVisualTokens.textPrimary);
    expect(bottomBar.selectedLabelColor, AppVisualTokens.textPrimary);
    expect(bottomBar.interactionGlowColor, const Color(0x1FFFFFFF));
    expect(bottomBarRect.height, AppGlassBottomNavigation.extent);
    expect(bottomBarRect.bottom, lessThanOrEqualTo(844 - 24));
    expect(
      clearance.height,
      AppGlassBottomNavigation.extent +
          24 +
          AppGlassBottomNavigation.contentSpacing,
    );
    expect(
      find.byKey(const ValueKey<String>('app-glass-bottom-navigation')),
      findsOneWidget,
    );
  });

  testWidgets('mobile mine uses neutral glass shortcuts and solid settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PlatformApp());
    await tester.pump();

    await tester.tapAt(tester.getCenter(find.text('我的').last));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      find.byKey(const ValueKey<String>('bili-mine-profile-header')),
      findsOneWidget,
    );
    final shortcuts = find.byKey(
      const ValueKey<String>('bili-mine-shortcuts-glass'),
    );
    expect(shortcuts, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('bili-mine-settings-surface')),
      findsOneWidget,
    );
    final shortcutIcons = tester
        .widgetList<Icon>(
          find.descendant(of: shortcuts, matching: find.byType(Icon)),
        )
        .toList(growable: false);
    expect(shortcutIcons, hasLength(4));
    expect(
      shortcutIcons.every((icon) => icon.color == AppVisualTokens.textPrimary),
      isTrue,
    );
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
    expect(find.text('已恢复当前显示模式，无需切换首页。'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('tv mode handoff preserves the active app dependencies', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(tester);

    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.tap(find.text('强制 TV 模式'));
    await _pumpUntilFound(tester, find.text('返回首页并切换'));
    await tester.tap(find.text('返回首页并切换'));
    await _pumpUntilFound(tester, find.byType(HomePage));

    expect(find.text('显示模式已修改，点击下方按钮返回首页切换。'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    final homePage = tester.widget<HomePage>(find.byType(HomePage));
    expect(identical(homePage.client, harness.client), isTrue);
    expect(identical(homePage.historyStore, harness.historyStore), isTrue);
    expect(identical(homePage.sessionStore, harness.sessionStore), isTrue);
    expect(
      identical(homePage.offlineController, harness.offlineController),
      isTrue,
    );
    expect(identical(homePage.appSettings, harness.appSettings), isTrue);
  });

  testWidgets('tv settings about card adapts on narrow landscape', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(tester, surfaceSize: const Size(760, 430));

    for (var index = 0; index < 6; index += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 180));
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_settings');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 240));

    final aboutCard = find.byKey(
      const ValueKey<String>('bili-tv-settings-about-card'),
    );
    final forceModeCard = find.byKey(
      const ValueKey<String>('bili-tv-settings-force-mode-card'),
    );
    expect(aboutCard, findsOneWidget);
    expect(forceModeCard, findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(aboutCard).width,
      closeTo(tester.getSize(forceModeCard).width, 0.5),
    );
  });

  testWidgets('tv rail keeps logo avatar and navigation icons on one axis', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    double centerX(String key) =>
        tester.getCenter(find.byKey(ValueKey<String>(key))).dx;
    void expectAligned() {
      final logoX = centerX('bili-tv-rail-logo');
      expect(centerX('bili-tv-rail-avatar'), closeTo(logoX, 0.5));
      expect(centerX('bili-tv-rail-icon-recommend'), closeTo(logoX, 0.5));
      expect(centerX('bili-tv-rail-icon-settings'), closeTo(logoX, 0.5));
    }

    expectAligned();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 240));
    expectAligned();
  });

  testWidgets('tv recommendations use a padded vertical grid', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    final gridPadding = tester.widget<SliverPadding>(
      find.byKey(const ValueKey<String>('bili-tv-recommend-grid')),
    );
    final padding = gridPadding.padding as EdgeInsets;

    expect(
      find.byKey(const ValueKey<String>('tv-shelf-list-为你推荐')),
      findsNothing,
    );
    expect(padding.top, 16);
    expect(padding.bottom, 32);
  });

  testWidgets('tv hero keeps progress separated from playback actions', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      initialHistoryEntries: _tvHistoryEntries(1),
      skipBootstrap: true,
    );

    final progressRect = tester.getRect(
      find.byKey(const ValueKey<String>('bili-tv-hero-progress')),
    );
    final actionsRect = tester.getRect(
      find.byKey(const ValueKey<String>('bili-tv-hero-actions')),
    );

    expect(actionsRect.top - progressRect.bottom, greaterThanOrEqualTo(14));
  });

  testWidgets('tv search keyboard inset keeps left rail width stable', (
    WidgetTester tester,
  ) async {
    const surfaceSize = Size(900, 520);
    final harness = await _pumpTvHomePage(tester, surfaceSize: surfaceSize);

    await tester.tap(find.text('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 240));

    final rail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    final initialRailWidth = tester.getSize(rail).width;
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_search_field');
    expect(initialRailWidth, 80);
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

  testWidgets('tv search focuses the field and rail right restores it', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 180));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 180));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 180));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_search');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.byType(TextField), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_search_field');
    expect(tester.testTextInput.isVisible, isTrue);

    final searchRailItem = find
        .ancestor(
          of: find.byKey(
            const ValueKey<String>('tv-glass-selectable-state-nav_search'),
          ),
          matching: find.byType(TvFocusable),
        )
        .last;
    tester
        .widget<Focus>(
          find
              .descendant(of: searchRailItem, matching: find.byType(Focus))
              .first,
        )
        .focusNode
        ?.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_search');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 180));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_search_field');
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('tv rail collapses for content and restores the last focus', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    expect(find.text('推荐视频 0'), findsWidgets);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_recommend');
    final rail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    expect(tester.getSize(rail).width, 260);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');
    expect(tester.getSize(rail).width, 80);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_details');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_recommend');
    expect(tester.getSize(rail).width, 260);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');
    expect(tester.getSize(rail).width, 80);
  });

  testWidgets('tv cover decode width stays stable while the rail animates', (
    WidgetTester tester,
  ) async {
    final feed = _tvFeedItems(18, true);
    await _pumpTvHomePage(tester, initialFeedItems: feed, skipBootstrap: true);

    final firstCard = find.byKey(ValueKey<String>('feed_${feed.first.bvid}'));
    Finder coverImage() =>
        find.descendant(of: firstCard, matching: find.byType(Image)).first;
    int cacheWidth() {
      final provider = tester.widget<Image>(coverImage()).image;
      return (provider as ResizeImage).width!;
    }

    final initialCacheWidth = cacheWidth();
    expect(tester.widget<Image>(coverImage()).gaplessPlayback, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));
    expect(cacheWidth(), initialCacheWidth);

    await tester.pump(const Duration(milliseconds: 220));
    expect(cacheWidth(), initialCacheWidth);
  });

  testWidgets('tv home keeps the nested following browser alive', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
    );
    final recommendScrollElement = tester.element(
      find.byKey(const ValueKey<String>('bili-tv-recommend-scroll')),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
    );

    expect(
      find.byKey(const ValueKey<String>('bili-tv-home-following-pane')),
      findsOneWidget,
    );
    expect(harness.client.followingRequests, 1);
    expect(harness.client.spaceProfileRequests, 1);
    expect(harness.client.spaceVideoRequests, 1);

    final mainRail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    await tester.pump(AppVisualTokens.overlayDuration);
    expect(tester.getSize(mainRail).width, 80);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(tester.getSize(mainRail).width, 260);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('tv_following_'),
    );
    expect(tester.getSize(mainRail).width, 80);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('bili-tv-following-user-7')),
    );
    await tester.pump(AppVisualTokens.tvFocusDuration);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_following_user_7',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('tv_space_'),
    );
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(tester.getSize(mainRail).width, 80);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(tester.getSize(mainRail).width, 80);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    expect(find.text('推荐视频 0'), findsWidgets);
    expect(
      tester.element(
        find.byKey(const ValueKey<String>('bili-tv-recommend-scroll')),
      ),
      same(recommendScrollElement),
    );
    expect(harness.client.recommendedFeedRequests, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
      findsOneWidget,
    );
    expect(harness.client.followingRequests, 1);
    expect(harness.client.spaceProfileRequests, 1);
    expect(harness.client.spaceVideoRequests, 1);
  });

  testWidgets('tv nested following rails fit compact landscape', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      surfaceSize: const Size(760, 430),
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
    );

    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );
    final mainRail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    final followingRail = find.byKey(
      const ValueKey<String>('bili-tv-following-rail'),
    );
    final contentArea = find.byKey(
      const ValueKey<String>('bili-tv-following-content-area'),
    );
    await tester.pump(AppVisualTokens.overlayDuration);
    final compactContentWidth = tester.getRect(contentArea).width;
    final compactMainRect = tester.getRect(mainRail);
    final compactFollowingRect = tester.getRect(followingRail);
    expect(tester.getSize(mainRail).width, 80);
    expect(compactFollowingRect.left - compactMainRect.right, closeTo(12, 0.5));
    expect(compactFollowingRect.top, closeTo(compactMainRect.top, 0.5));
    expect(compactFollowingRect.bottom, closeTo(compactMainRect.bottom, 0.5));
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(tester.getSize(mainRail).width, 260);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('tv_following_'),
    );
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(mainRail).width, 80);
    final expandedMainRect = tester.getRect(mainRail);
    final expandedFollowingRect = tester.getRect(followingRail);
    expect(
      expandedFollowingRect.left - expandedMainRect.right,
      closeTo(12, 0.5),
    );
    expect(expandedFollowingRect.top, closeTo(expandedMainRect.top, 0.5));
    expect(expandedFollowingRect.bottom, closeTo(expandedMainRect.bottom, 0.5));
    expect(
      tester.getRect(contentArea).width,
      closeTo(compactContentWidth, 0.5),
    );
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );
    expect(
      tester.getRect(contentArea).width,
      closeTo(compactContentWidth, 0.5),
    );
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );
    expect(tester.getSize(mainRail).width, 260);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(mainRail).width, 80);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tv primary rail items share icon and label alignment', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    final iconRects = <Rect>[];
    final labelRects = <Rect>[];
    for (final item in <String>['recommend', 'following', 'regions']) {
      iconRects.add(
        tester.getRect(find.byKey(ValueKey<String>('bili-tv-rail-icon-$item'))),
      );
      labelRects.add(
        tester.getRect(
          find.byKey(ValueKey<String>('bili-tv-rail-label-$item')),
        ),
      );
    }
    for (var index = 1; index < iconRects.length; index += 1) {
      expect(
        iconRects[index].center.dx,
        closeTo(iconRects.first.center.dx, 0.5),
      );
      expect(labelRects[index].left, closeTo(labelRects.first.left, 0.5));
    }
  });

  testWidgets(
    'tv following pane resets when the authenticated session changes',
    (WidgetTester tester) async {
      final harness = await _pumpTvHomePage(
        tester,
        initialFeedItems: _tvFeedItems(),
        skipBootstrap: true,
        loggedIn: true,
        authenticatedSession: true,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
      );
      final oldPaneElement = tester.element(
        find.byKey(const ValueKey<String>('bili-tv-following-pane')),
      );
      expect(
        find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
        findsOneWidget,
      );

      harness.client.clearSession();
      await _pumpTvHomeFrame(
        tester,
        harness,
        surfaceSize: const Size(1280, 720),
        initialFeedItems: _tvFeedItems(),
        skipBootstrap: true,
      );
      await _pumpUntilFound(tester, find.text('暂时无法显示'));
      expect(
        find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
        findsNothing,
      );
      expect(
        tester.element(
          find.byKey(const ValueKey<String>('bili-tv-following-pane')),
        ),
        isNot(same(oldPaneElement)),
      );
    },
  );

  testWidgets('tv embedded following login state keeps home rail focus', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntilFound(tester, find.text('暂时无法显示'));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tv empty following rail exposes a compact refresh action', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
      emptyFollowing: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntilFound(tester, find.text('选择一位 UP 主'));
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_following_refresh',
    );
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tv embedded following does not reload after playback returns', (
    WidgetTester tester,
  ) async {
    final previousPlatform = VesperPlayerPlatform.instance;
    final platform = _FakePlaybackVesperPlatform(
      initialSnapshot: _playbackSnapshot,
    );
    VesperPlayerPlatform.instance = platform;
    addTearDown(() => VesperPlayerPlatform.instance = previousPlatform);
    addTearDown(platform.closeEvents);
    final externalPlayback = _ExternalPlaybackHarness()..install();
    addTearDown(externalPlayback.uninstall);

    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    final video = find.byKey(
      const ValueKey<String>('bili-tv-space-video-BV1space0001'),
    );
    await _pumpUntilFound(tester, video);
    final followingRequests = harness.client.followingRequests;
    final profileRequests = harness.client.spaceProfileRequests;
    final videoRequests = harness.client.spaceVideoRequests;

    await tester.tap(video);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BiliPlaybackPage), findsOneWidget);

    Navigator.of(tester.element(find.byType(BiliPlaybackPage))).pop();
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(video, findsOneWidget);
    expect(harness.client.followingRequests, followingRequests);
    expect(harness.client.spaceProfileRequests, profileRequests);
    expect(harness.client.spaceVideoRequests, videoRequests);
  });

  testWidgets('tv hero focus update is debounced and does not load details', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );
    Text heroTitle() => tester.widget<Text>(
      find.byKey(const ValueKey<String>('bili-tv-hero-title')),
    );

    expect(heroTitle().data, '推荐视频 0');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video_推荐视频 0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(heroTitle().data, '推荐视频 0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video_推荐视频 2');
    await tester.pump(const Duration(milliseconds: 119));
    expect(heroTitle().data, '推荐视频 0');
    expect(harness.client.requestedVideoDetails, isEmpty);

    await tester.pump(const Duration(milliseconds: 2));
    expect(heroTitle().data, '推荐视频 2');
    expect(harness.client.requestedVideoDetails, isEmpty);
  });

  testWidgets('tv mine keeps its two library actions aligned', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      find.byKey(
        const ValueKey<String>('tv-glass-selectable-state-nav_following'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('bili-tv-content-area')),
        matching: find.text('关注列表'),
      ),
      findsNothing,
    );
    final historyAction = find
        .ancestor(of: find.text('历史播放'), matching: find.byType(TvFocusable))
        .last;
    final watchLaterAction = find
        .ancestor(of: find.text('稍后再看'), matching: find.byType(TvFocusable))
        .last;
    expect(historyAction, findsOneWidget);
    expect(watchLaterAction, findsOneWidget);

    final historyRect = tester.getRect(historyAction);
    final watchLaterRect = tester.getRect(watchLaterAction);
    expect(historyRect.center.dy, closeTo(watchLaterRect.center.dy, 0.5));
    expect(historyRect.overlaps(watchLaterRect), isFalse);
  });

  testWidgets('tv home only builds a bounded visible feed subset', (
    WidgetTester tester,
  ) async {
    final items = _tvFeedItems(400);
    await _pumpTvHomePage(tester, initialFeedItems: items, skipBootstrap: true);

    final builtFeedCards = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('feed_');
    });
    final builtCardCount = builtFeedCards.evaluate().length;

    expect(builtCardCount, greaterThan(0));
    expect(builtCardCount, lessThan(80));
    expect(
      find.byKey(ValueKey<String>('feed_${items.last.bvid}')),
      findsNothing,
    );
  });

  testWidgets('tv rail separates neutral focus lens from selection marker', (
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
      find.byKey(
        const ValueKey<String>('tv-glass-selectable-state-nav_recommend'),
      ),
    );
    final decoration = focusedContainer.decoration! as BoxDecoration;
    final borderColor = decoration.border?.top.color;
    final fillColor = decoration.color;

    expect(borderColor?.a, greaterThan(0));
    expect(fillColor?.a, 0);
    expect(
      find.descendant(
        of: focusedItem,
        matching: find.byWidgetPredicate((widget) {
          final markerDecoration = widget is AnimatedContainer
              ? widget.decoration
              : null;
          return markerDecoration is BoxDecoration &&
              markerDecoration.color == AppVisualTokens.primaryBlue;
        }),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tv shelves scroll and restore focus in all directions', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      surfaceSize: const Size(900, 520),
      initialFeedItems: _tvFeedItems(60),
      initialHistoryEntries: _tvHistoryEntries(24),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');

    Future<void> move(LogicalKeyboardKey key, int count) async {
      for (var index = 0; index < count; index++) {
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump(const Duration(milliseconds: 180));
      }
    }

    Future<List<String?>> moveUntil(
      LogicalKeyboardKey key,
      String debugLabel, {
      int attempts = 24,
    }) async {
      final visited = <String?>[];
      for (var index = 0; index < attempts; index += 1) {
        final current = FocusManager.instance.primaryFocus?.debugLabel;
        visited.add(current);
        if (current == debugLabel) {
          return visited;
        }
        await move(key, 1);
      }
      visited.add(FocusManager.instance.primaryFocus?.debugLabel);
      return visited;
    }

    await move(LogicalKeyboardKey.arrowDown, 1);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history_历史视频 0');

    final historyList = tester.widget<ListView>(
      find.byKey(const ValueKey<String>('tv-shelf-list-继续观看')),
    );
    await moveUntil(LogicalKeyboardKey.arrowRight, 'history_历史视频 12');
    final rightwardOffset = historyList.controller!.offset;
    expect(rightwardOffset, greaterThan(0));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history_历史视频 12');

    final leftVisited = await moveUntil(
      LogicalKeyboardKey.arrowLeft,
      'history_历史视频 0',
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'history_历史视频 0',
      reason: 'Visited ${leftVisited.join(' -> ')}',
    );
    expect(historyList.controller!.offset, lessThan(rightwardOffset));

    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey<String>('bili-tv-recommend-scroll')),
    );
    final beforeDown = scrollView.controller!.offset;
    await move(LogicalKeyboardKey.arrowDown, 1);
    final downwardOffset = scrollView.controller!.offset;

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video_推荐视频 0');
    expect(downwardOffset, greaterThan(beforeDown));

    await move(LogicalKeyboardKey.arrowUp, 1);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history_历史视频 0');
    expect(scrollView.controller!.offset, lessThanOrEqualTo(downwardOffset));

    expect(scrollView.controller!.offset, greaterThan(0));
    await move(LogicalKeyboardKey.arrowUp, 1);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');
    expect(scrollView.controller!.offset, 0);
  });

  testWidgets('tv home regions nav loads section videos', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      loggedIn: true,
    );
    await _pumpUntil(tester, () => find.text('测试用户').evaluate().isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
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

  testWidgets('tv region categories keep focus separate from the first row', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      surfaceSize: const Size(3008, 1692),
      initialFeedItems: _tvFeedItems(),
      loggedIn: true,
    );
    await _pumpUntil(tester, () => find.text('测试用户').evaluate().isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    if (FocusManager.instance.primaryFocus?.debugLabel == 'nav_regions') {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'region_bangumi');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'region_guochuang');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'region_guochuang');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('video_国创内容'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'region_guochuang');
  });

  testWidgets('tv home regions prompt for login before loading', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(find.text('需要登录'), findsOneWidget);
    expect(harness.client.requestedSections, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-dialog-surface')),
      findsOneWidget,
    );
    expect(find.byType(GlassDialog), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_取消');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_登录');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 240));
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('需要登录'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-qr-login-surface')),
      findsOneWidget,
    );
    expect(find.byType(GlassSheet), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_qr_login_refresh',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      find.byKey(const ValueKey<String>('bili-tv-qr-login-surface')),
      findsNothing,
    );
    expect(harness.client.generatedQrTickets, 1);
  });

  testWidgets('tv logout asks for confirmation before clearing the account', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      loggedIn: true,
    );
    await _pumpUntil(tester, () => find.text('测试用户').evaluate().isNotEmpty);

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.tap(find.text('退出登录'));
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('退出登录？'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_取消');

    // Android TV sends KEYCODE_BACK through the key channel before asking the
    // current route to pop. The key phase must not dismiss the dialog early,
    // otherwise the route pop would reach the TV home page and open Exit App.
    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pumpAndSettle();
    expect(find.text('退出登录？'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('退出登录？'), findsNothing);
    expect(find.text('退出 Vesper？'), findsNothing);
    expect(find.text('退出登录'), findsOneWidget);

    await tester.tap(find.text('退出登录'));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_退出登录');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await _pumpUntilFound(tester, find.text('扫码登录'));

    expect(find.text('退出登录？'), findsNothing);
    expect(find.text('扫码登录'), findsOneWidget);
  });

  testWidgets('tv QR login keeps its default action visible at compact height', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory(
      '${Directory.systemTemp.path}/bili-tv-qr-compact-${DateTime.now().microsecondsSinceEpoch}',
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
        theme: AppVisualTokens.darkTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showBiliTvQrLoginDialog(
              context: context,
              client: _FakeQrLoginClient(),
              sessionStore: BiliSessionStore(baseDirectory: root),
            ),
            child: const Text('打开 TV 登录'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开 TV 登录'));
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_qr_login_refresh',
    );
    final refreshRect = tester.getRect(
      find.byKey(const ValueKey<String>('bili-tv-dialog-action-刷新二维码')),
    );
    expect(refreshRect.top, greaterThanOrEqualTo(0));
    expect(refreshRect.bottom, lessThanOrEqualTo(360));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
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

    expect(find.text('退出 Vesper？'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bili-tv-dialog-surface')),
      findsOneWidget,
    );
    final exitSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('bili-tv-dialog-surface')),
    );
    final exitDecoration = exitSurface.decoration as BoxDecoration;
    expect(exitDecoration.color, const Color(0xF21B1E24));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('bili-tv-dialog-surface')))
          .width,
      690,
    );
    expect(
      tester.widget<Text>(find.text('退出 Vesper？')).style?.color,
      Colors.white,
    );
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_继续观看');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('退出 Vesper？'), findsNothing);
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_退出应用');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isNotEmpty,
    );
  });

  testWidgets('tv home Android back opens one persistent exit dialog', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pump();

    expect(find.text('退出 Vesper？'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('退出 Vesper？'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_继续观看');

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('退出 Vesper？'), findsOneWidget);
  });

  testWidgets('tv library Android back returns one level without exit dialog', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.tap(find.text('历史播放'));
    await tester.pumpAndSettle();

    expect(find.byType(BiliLibraryPage), findsOneWidget);
    expect(find.byType(BiliTvHomePage, skipOffstage: false), findsOneWidget);

    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pump();
    expect(find.byType(BiliLibraryPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(BiliLibraryPage), findsNothing);
    expect(find.byType(BiliTvHomePage), findsOneWidget);
    expect(find.text('退出 Vesper？'), findsNothing);
  });

  testWidgets(
    'playback reparses an expired address three times before showing a dialog',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);
      harness.platform.failSelectedSourcesRemaining = 3;

      harness.platform.emitPlaybackError(_expiredPlaybackAddressError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
        _playbackPageOne.cid,
        _playbackPageOne.cid,
      ]);
      expect(harness.platform.selectedSources, hasLength(3));
      expect(find.text('播放地址刷新失败'), findsOneWidget);
      expect(find.textContaining('重试 3 次'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GlassDialog),
          matching: find.text('重新解析'),
        ),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'manual reparse does not reuse the expired initial address',
    (WidgetTester tester) async {
      const decodeError = VesperPlayerError(
        message: 'decoder failed',
        code: VesperPlayerErrorCode.decodeFailure,
        category: VesperPlayerErrorCategory.decode,
        retriable: false,
      );
      final harness = await _pumpPlaybackPage(
        tester,
        initialSnapshot: _playbackSnapshot.copyWith(lastError: decodeError),
      );

      await tester.tap(find.text('重新解析'));
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt += 1) {
          if (harness.client.resolvedPlaybackRequests.isNotEmpty) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      expect(harness.platform.refreshCalls, 0);
      expect(harness.platform.clearSystemPlaybackCalls, 1);
      expect(harness.platform.disposeCalls, 1);
      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'iOS HTTP failure evidence triggers Bilibili address reparse',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitPlaybackError(_iosExpiredPlaybackAddressError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(seconds: 5));

      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
      ]);
      expect(harness.platform.selectedSources, hasLength(1));
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'unrelated iOS platform failures do not trigger address reparse',
    (WidgetTester tester) async {
      const platformError = VesperPlayerError(
        message: 'platform channel failed',
        code: VesperPlayerErrorCode.backendFailure,
        category: VesperPlayerErrorCategory.platform,
        retriable: false,
      );
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitPlaybackError(platformError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(harness.client.resolvedPlaybackRequests, isEmpty);
      expect(harness.platform.selectedSources, isEmpty);
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'transient network failures do not trigger address reparse',
    (WidgetTester tester) async {
      const networkError = VesperPlayerError(
        message: 'network timeout',
        code: VesperPlayerErrorCode.backendFailure,
        category: VesperPlayerErrorCategory.network,
        retriable: true,
        details: <String, Object?>{
          'errorCodeName': 'ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT',
        },
      );
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitPlaybackError(networkError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(harness.client.resolvedPlaybackRequests, isEmpty);
      expect(harness.platform.selectedSources, isEmpty);
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'FairPlay license failures do not trigger media address reparse',
    (WidgetTester tester) async {
      const licenseError = VesperPlayerError(
        message: 'FairPlay license request failed',
        code: VesperPlayerErrorCode.backendFailure,
        category: VesperPlayerErrorCategory.network,
        retriable: true,
        details: <String, Object?>{
          'keySystem': 'fairPlay',
          'httpStatusCode': '503',
        },
      );
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitPlaybackError(licenseError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(harness.client.resolvedPlaybackRequests, isEmpty);
      expect(harness.platform.selectedSources, isEmpty);
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'switching pages invalidates an in-flight address recovery',
    (WidgetTester tester) async {
      final blockedRecovery = Completer<BiliResolvedPlayback>();
      final harness = await _pumpPlaybackPage(
        tester,
        configureClient: (client) {
          client.blockedPlaybackResolutions[_playbackPageOne.cid] =
              blockedRecovery;
        },
      );

      harness.platform.emitPlaybackError(_expiredPlaybackAddressError);
      await tester.pump();
      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
      ]);

      await tester.tap(find.text('合集 · 共 3 个分 P'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P2'));
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt += 1) {
          if (harness.client.resolvedPlaybackRequests.contains(
            _playbackPageTwo.cid,
          )) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();

      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
        _playbackPageTwo.cid,
      ]);
      expect(
        harness.platform.selectedSources.map((source) => source.uri),
        <String>['https://example.test/${_playbackPageTwo.cid}.mp4'],
      );

      blockedRecovery.complete(
        _resolvedPlaybackFor(_playbackDetail(), _playbackPageOne),
      );
      await tester.pump();
      await tester.pump();

      expect(
        harness.platform.selectedSources.map((source) => source.uri),
        <String>['https://example.test/${_playbackPageTwo.cid}.mp4'],
      );
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback page opens page collection from a bottom sheet',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester);

      expect(find.text('播放页测试视频'), findsWidgets);
      expect(find.text('这是一段播放页说明，下面应直接显示合集列表。'), findsOneWidget);
      expect(find.text('合集 · 共 3 个分 P'), findsOneWidget);
      expect(find.text('P1 · 正片'), findsOneWidget);
      expect(find.text('P2'), findsNothing);
      expect(find.text('简介'), findsOneWidget);
      expect(find.text('相关推荐'), findsOneWidget);
      expect(find.text('相关视频 1'), findsOneWidget);
      expect(find.text('播放 SDK'), findsNothing);
      expect(find.text('Manifest'), findsNothing);

      await tester.tap(find.text('合集 · 共 3 个分 P'));
      await tester.pumpAndSettle();

      expect(find.text('P2'), findsOneWidget);
      expect(find.text('花絮'), findsOneWidget);
      expect(find.text('P3'), findsOneWidget);
      expect(find.text('访谈'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback engagement stays in the intro stream below the context tabs',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester);

      expect(
        find.byKey(const ValueKey<String>('playback-shell-engagement-bar')),
        findsNothing,
      );
      final tabsRect = tester.getRect(find.byType(TabBar));
      final engagementRect = tester.getRect(
        find.byKey(const ValueKey<String>('bili-intro-engagement-bar')),
      );
      final titleRect = tester.getRect(
        find.byKey(const ValueKey<String>('playback-intro-title')),
      );
      expect(engagementRect.top, greaterThan(tabsRect.bottom));
      expect(engagementRect.top, greaterThan(titleRect.bottom));
      final actionRects = <Rect>[
        for (final action in <String>[
          'like',
          'coin',
          'favorite',
          'share',
          'watchLater',
        ])
          tester.getRect(find.byKey(ValueKey<String>('engagement-$action'))),
      ];
      final actionRowTop = actionRects.first.top;
      final actionWidth = actionRects.first.width;
      for (final action in <String>[
        'coin',
        'favorite',
        'share',
        'watchLater',
      ]) {
        final rect = tester.getRect(
          find.byKey(ValueKey<String>('engagement-$action')),
        );
        expect(rect.top, closeTo(actionRowTop, 0.5));
        expect(rect.width, closeTo(actionWidth, 0.5));
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback context tabs center labels and use a compact leading inset',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(390, 640));

      final tabBarFinder = find.byType(TabBar);
      final introTabFinder = find.byKey(
        const ValueKey<String>('playback-intro-tab'),
      );
      final commentsTabFinder = find.byKey(
        const ValueKey<String>('playback-comments-tab'),
      );
      final tabBar = tester.widget<TabBar>(tabBarFinder);

      expect(tabBar.tabAlignment, TabAlignment.start);
      expect(tabBar.labelPadding, const EdgeInsets.symmetric(horizontal: 12));
      expect(
        tester.getCenter(find.text('简介')).dx,
        closeTo(tester.getCenter(introTabFinder).dx, 0.5),
      );
      expect(
        tester.getCenter(find.text('评论 78')).dx,
        closeTo(tester.getCenter(commentsTabFinder).dx, 0.5),
      );
      expect(
        tester.getTopLeft(introTabFinder).dx -
            tester.getTopLeft(tabBarFinder).dx,
        lessThan(24),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'mobile playback surfaces and text follow the dark visual theme',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        theme: AppVisualTokens.mobileDarkTheme(),
      );

      final bottomSurface = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey<String>('playback-bottom-surface')),
      );
      final bottomDecoration = bottomSurface.decoration as BoxDecoration;
      final collapsedBar = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey<String>('playback-collapsed-bar')),
      );
      final collapsedDecoration = collapsedBar.decoration as BoxDecoration;
      final title = tester.widget<Text>(
        find.byKey(const ValueKey<String>('playback-intro-title')),
      );

      expect(bottomDecoration.color, AppVisualTokens.darkSurface);
      expect(collapsedDecoration.color, AppVisualTokens.darkSurface);
      expect(title.style?.color, AppVisualTokens.darkTextPrimary);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback intro hides expand control for empty and fitting descriptions',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        detail: _playbackDetailWith(description: ''),
      );

      expect(
        find.byKey(const ValueKey<String>('playback-intro-expand')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        detail: _playbackDetailWith(description: '当前空间可以完整展示的简短简介。'),
      );

      expect(
        find.byKey(const ValueKey<String>('playback-intro-expand')),
        findsNothing,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback intro expand aligns with title first line and toggles overflow',
    (WidgetTester tester) async {
      final detail = _playbackDetailWith(
        title: '这是一个会换到第二行但展开按钮仍需对齐第一行的播放页测试标题',
        description:
            '这是一段需要折叠的长简介内容，用来验证简介在三行空间不足时才显示展开按钮。'
            '继续补充足够多的文字，让它在手机宽度下稳定超过三行，同时确保展开后可以展示全部内容。'
            '最后再增加一段文字，避免不同字体度量导致简介刚好落在三行以内。',
      );
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        detail: detail,
      );

      final titleFinder = find.byKey(
        const ValueKey<String>('playback-intro-title'),
      );
      final expandFinder = find.byKey(
        const ValueKey<String>('playback-intro-expand'),
      );
      final descriptionFinder = find.byKey(
        const ValueKey<String>('playback-intro-description'),
      );
      final iconFinder = find.descendant(
        of: expandFinder,
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      );
      final iconButtonFinder = find.descendant(
        of: expandFinder,
        matching: find.byType(IconButton),
      );
      expect(expandFinder, findsOneWidget);
      expect(tester.widget<Text>(descriptionFinder).maxLines, 3);
      expect(tester.getSize(iconButtonFinder), const Size(40, 40));

      final titleContext = tester.element(titleFinder);
      final titleStyle = tester.widget<Text>(titleFinder).style;
      final titleLinePainter = TextPainter(
        text: TextSpan(text: 'M', style: titleStyle),
        maxLines: 1,
        textDirection: Directionality.of(titleContext),
        textScaler: MediaQuery.textScalerOf(titleContext),
        locale: Localizations.maybeLocaleOf(titleContext),
      )..layout();
      final expectedIconCenterY =
          tester.getTopLeft(titleFinder).dy +
          titleLinePainter.preferredLineHeight / 2;
      expect(
        tester.getCenter(iconFinder).dy,
        closeTo(expectedIconCenterY, 0.5),
      );
      expect(
        tester.getCenter(iconButtonFinder).dy,
        closeTo(expectedIconCenterY, 0.5),
      );

      await tester.tap(iconButtonFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(descriptionFinder).maxLines, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: expandFinder,
                matching: find.byType(IconButton),
              ),
            )
            .tooltip,
        '收起简介',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback resumes an unfinished history position before autoplay',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester, initialPositionMs: 45000);

      expect(harness.platform.seekDeltas, <int>[45000]);
      expect(harness.platform.playCalls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback exit records the current progress into history',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitSnapshot(
        _playingPlaybackSnapshot.copyWith(
          timeline: const VesperTimeline(
            kind: VesperTimelineKind.vod,
            isSeekable: true,
            seekableRange: null,
            liveEdgeMs: null,
            positionMs: 30000,
            durationMs: 120000,
          ),
        ),
      );
      await tester.pump();
      await _flushRealAsync(tester);

      // 退出播放页：dispose 路径持久化当前进度。
      await tester.pumpWidget(const SizedBox.shrink());
      List<BiliPlaybackHistoryEntry> entries =
          const <BiliPlaybackHistoryEntry>[];
      for (var attempt = 0; attempt < 10 && entries.isEmpty; attempt += 1) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        entries =
            await tester.runAsync(() => harness.historyStore.loadEntries()) ??
            const <BiliPlaybackHistoryEntry>[];
      }

      expect(entries, hasLength(1));
      expect(entries.single.bvid, 'BV1playback01');
      expect(entries.single.cid, 101);
      expect(entries.single.lastPositionMs, 30000);
      expect(entries.single.durationMs, 120000);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'android playback enables source normalizer without frame processor',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      expect(
        harness.platform.lastSourceNormalizerConfiguration?.mode,
        VesperSourceNormalizerMode.preferNormalized,
      );
      expect(
        harness.platform.lastSourceNormalizerConfiguration?.pluginReferences,
        <VesperPluginReference>[
          VesperBundledPluginReferences.sourceNormalizerFfmpeg,
        ],
      );
      expect(
        harness.platform.lastFrameProcessorConfiguration?.mode,
        VesperFrameProcessorMode.disabled,
      );
      expect(
        harness.platform.lastFrameProcessorConfiguration?.pluginReferences,
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
      expect(find.text('第 1 话 · 正片'), findsOneWidget);
      expect(find.text('第 2 话'), findsNothing);
      expect(find.text('点赞'), findsNothing);
      expect(find.text('硬币'), findsNothing);
      expect(find.text('收藏'), findsNothing);
      expect(find.text('分享'), findsNothing);
      // PGC 保留图标化的稍后再看入口（互动动作栏仅声明 watchLater）。
      expect(
        find.byKey(const ValueKey<String>('engagement-watchLater')),
        findsOneWidget,
      );
      expect(find.text('加入稍后再看'), findsNothing);
      expect(find.widgetWithText(FilledButton, '关注'), findsNothing);
      expect(find.text('播放页UP'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback engagement actions are icon-only and pending disables follow',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);
      final followCompleter = Completer<BiliVideoEngagement>();
      harness.client.followCompleter = followCompleter;

      for (final action in <String>[
        'like',
        'coin',
        'favorite',
        'share',
        'watchLater',
      ]) {
        expect(
          find.byKey(ValueKey<String>('engagement-$action')),
          findsOneWidget,
        );
      }
      for (final label in <String>['点赞', '硬币', '收藏', '分享', '加入稍后再看']) {
        expect(find.text(label), findsNothing);
      }
      final semantics = tester.ensureSemantics();
      for (final label in <String>[
        '点赞 1.1万',
        '硬币 234',
        '收藏 345',
        '分享 56',
        '加入稍后再看',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('点赞 1.1万')),
        matchesSemantics(
          label: '点赞 1.1万',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
        ),
      );
      semantics.dispose();
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
    'playback coin action posts through the view model',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      await tester.tap(find.byKey(const ValueKey<String>('engagement-coin')));
      await tester.pump();

      expect(harness.client.coinRequests, 1);
      expect(harness.client.engagement.isLiked, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback watch later prompts for login before mutating',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester);

      expect(find.text('加入稍后再看'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey<String>('engagement-watchLater')),
      );
      await tester.pump();

      expect(find.text('请先登录 Bilibili 后使用稍后再看。'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback comments render nested replies and seek time links',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();

      expect(find.text('热门评论'), findsOneWidget);
      expect(find.text('神代强丸'), findsOneWidget);
      expect(find.textContaining('不像韩女', findRichText: true), findsOneWidget);
      expect(find.textContaining('立在哪里无寒冬'), findsOneWidget);
      expect(find.text('共3条回复 >'), findsOneWidget);

      final replyPreview = find.ancestor(
        of: find.text('共3条回复 >'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material &&
              widget.color == AppVisualTokens.mobileSurfaceMuted,
        ),
      );
      final commentRow = find.ancestor(
        of: find.text('共3条回复 >'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Row &&
              widget.crossAxisAlignment == CrossAxisAlignment.start,
        ),
      );
      expect(replyPreview, findsOneWidget);
      expect(commentRow, findsOneWidget);
      expect(
        tester.getSize(replyPreview).width,
        closeTo(tester.getSize(commentRow).width - 50, 0.1),
      );
      final modalBarrierCountBefore = find
          .byType(ModalBarrier)
          .evaluate()
          .length;

      await tester.tap(find.text('共3条回复 >'));
      await tester.pumpAndSettle();

      expect(find.text('评论详情'), findsOneWidget);
      expect(find.text('相关回复共3条'), findsOneWidget);
      expect(
        find.byType(ModalBarrier).evaluate().length,
        modalBarrierCountBefore,
      );

      await tester.tap(find.byTooltip('关闭评论详情'));
      await tester.pumpAndSettle();

      final messageFinder = find.textContaining(
        '01:00 不像韩女',
        findRichText: true,
      );
      await tester.tapAt(tester.getTopLeft(messageFinder) + const Offset(8, 8));
      await tester.pump();

      expect(harness.platform.seekRatios, isNotEmpty);
      expect(harness.platform.seekRatios.last, moreOrLessEquals(0.5));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback comment replies load the next page near the list end',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        configureClient: (client) {
          client.commentReplyPages
            ..clear()
            ..[1] = List<BiliVideoComment>.generate(
              20,
              (index) => _playbackCommentReply(
                id: 700 + index,
                authorName: '楼中楼用户${index + 1}',
                message: '楼中楼第${index + 1}条',
              ),
            )
            ..[2] = <BiliVideoComment>[
              _playbackCommentReply(
                id: 720,
                authorName: '楼中楼用户21',
                message: '楼中楼第21条',
              ),
            ];
          client.commentReplyTotalCount = 21;
        },
      );

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('共3条回复 >'));
      await tester.pumpAndSettle();

      expect(harness.client.commentReplyPageRequests, <int>[1]);
      expect(find.text('相关回复共21条'), findsOneWidget);
      final repliesList = find.byKey(
        const PageStorageKey<String>('playback-comment-replies'),
      );
      final repliesScrollable = find.descendant(
        of: repliesList,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('playback-comment-reply-719')),
        400,
        scrollable: repliesScrollable,
      );
      await tester.pumpAndSettle();

      expect(harness.client.commentReplyPageRequests, <int>[1, 2]);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('playback-comment-reply-720')),
        300,
        scrollable: repliesScrollable,
      );
      expect(
        find.textContaining('楼中楼第21条', findRichText: true),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'mobile comment replies stay below the playing video',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        initialSnapshot: _playingPlaybackSnapshot,
      );

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-comments')),
        const Offset(0, -360),
      );
      await tester.pumpAndSettle();
      final modalBarrierCountBefore = find
          .byType(ModalBarrier)
          .evaluate()
          .length;
      await tester.tap(find.text('共3条回复 >'));
      await tester.pumpAndSettle();

      final stageRect = tester.getRect(
        find.byType(vesper_ui.VesperPlayerStage),
      );
      final replyHeaderRect = tester.getRect(
        find.byKey(const ValueKey<String>('playback-comment-replies-header')),
      );
      expect(
        find.byType(ModalBarrier).evaluate().length,
        modalBarrierCountBefore,
      );
      expect(replyHeaderRect.top, greaterThanOrEqualTo(stageRect.bottom));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'mobile comments keep tabs fixed and fade in collapsed playback bar',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(390, 640));

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();

      final collapsedOpacityBefore = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('继续播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-comments')),
        const Offset(0, -420),
      );
      await tester.pump();
      await tester.pump();

      final collapsedOpacityAfter = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('继续播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      expect(find.text('简介'), findsOneWidget);
      expect(find.text('评论 78'), findsOneWidget);
      expect(collapsedOpacityAfter, greaterThan(collapsedOpacityBefore));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback info tabs switch with horizontal swipes',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(390, 640));

      // 互动动作栏属于简介流，简介列表向下滚动使分 P 入口可见。
      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-related')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      expect(find.text('合集 · 共 3 个分 P'), findsOneWidget);
      expect(find.text('热门评论'), findsNothing);

      await tester.drag(find.byType(TabBarView), const Offset(-320, 0));
      await tester.pumpAndSettle();

      expect(find.text('热门评论'), findsOneWidget);
      expect(find.text('神代强丸'), findsOneWidget);

      await tester.drag(find.byType(TabBarView), const Offset(320, 0));
      await tester.pumpAndSettle();

      expect(find.text('合集 · 共 3 个分 P'), findsOneWidget);
      expect(find.text('热门评论'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback comments load more near the bottom',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        configureClient: (client) {
          client.extraComments.add(
            const BiliVideoComment(
              id: 901,
              authorName: '第二页用户',
              authorAvatarUrl: '',
              createdAtLabel: '1分钟前',
              message: '第二页评论',
              likeCountLabel: '0',
              pictures: <BiliCommentPicture>[],
              replies: <BiliVideoComment>[],
              timeLinks: <BiliCommentTimeLink>[],
            ),
          );
        },
      );

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-comments')),
        const Offset(0, -620),
      );
      await _pumpUntil(
        tester,
        () => harness.client.commentPageRequests.contains(2),
      );
      await tester.pumpAndSettle();

      expect(harness.client.commentPageRequests, contains(2));
      expect(find.text('第二页用户'), findsOneWidget);
      expect(find.text('第二页评论', findRichText: true), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'mobile playback stage stays expanded while lists scroll during playback',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        initialSnapshot: _playingPlaybackSnapshot,
      );

      final collapsedOpacityBefore = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('正在播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      final stageFinder = find.byType(vesper_ui.VesperPlayerStage);
      final stageSizeBefore = tester.getSize(stageFinder);

      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-related')),
        const Offset(0, -420),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final collapsedOpacityAfter = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('正在播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      expect(collapsedOpacityAfter, collapsedOpacityBefore);
      expect(tester.getSize(stageFinder), stageSizeBefore);

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-comments')),
        const Offset(0, -420),
      );
      await tester.pump();
      await tester.pump();

      final commentsCollapsedOpacity = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('正在播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;
      expect(commentsCollapsedOpacity, collapsedOpacityBefore);
      expect(tester.getSize(stageFinder), stageSizeBefore);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback comment composer is fixed and sends from keyboard action',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '好看，支持一下');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(harness.client.sentComments, <String>['好看，支持一下']);
      expect(find.text('当前用户'), findsOneWidget);
      expect(find.text('好看，支持一下', findRichText: true), findsOneWidget);
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
    'playback settings select an SDK external subtitle track',
    (WidgetTester tester) async {
      final subtitleSnapshot = _playbackSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsTrackCatalog: true,
          supportsTrackSelection: true,
          supportsSubtitleTrackSelection: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[
            VesperMediaTrack(
              id: 'subtitle:bili:3',
              kind: VesperMediaTrackKind.subtitle,
              label: '中文（中国大陆）',
              language: 'zh-CN',
              isDefault: true,
            ),
          ],
        ),
      );
      final harness = await _pumpPlaybackPage(
        tester,
        initialSnapshot: subtitleSnapshot,
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('中文（中国大陆）'));
      await tester.pump();

      expect(harness.platform.subtitleSelections, hasLength(1));
      expect(
        harness.platform.subtitleSelections.single.mode,
        VesperTrackSelectionMode.track,
      );
      expect(
        harness.platform.subtitleSelections.single.trackId,
        'subtitle:bili:3',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback settings show empty copy when resolution has no options',
    (WidgetTester tester) async {
      final base = _resolvedPlaybackFor(_playbackDetail(), _playbackPageOne);
      await _pumpPlaybackPage(
        tester,
        initialResolvedPlayback: BiliResolvedPlayback(
          bvid: base.bvid,
          cid: base.cid,
          title: base.title,
          subtitle: base.subtitle,
          uri: base.uri,
          protocol: base.protocol,
          transportLabel: base.transportLabel,
          isLocalFile: base.isLocalFile,
          videoTracks: const <VesperMediaTrack>[],
          subtitleTracks: const <BiliSubtitleTrack>[],
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('当前播放链路无可选清晰度。'), findsOneWidget);
      expect(find.text('当前视频没有可用字幕。'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback speed panel applies and restores playback rate',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1.25x'));
      await tester.pump();
      expect(harness.platform.playbackRates, <double>[1.25]);

      await tester.tap(find.text('1.0x'));
      await tester.pump();
      expect(harness.platform.playbackRates, <double>[1.25, 1.0]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback page lays out at compact phone size without overflow',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(360, 640));

      expect(find.text('播放页测试视频'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback page lays out at standard phone size without overflow',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(390, 844));

      expect(find.text('播放页测试视频'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback page lays out at wide landscape size without overflow',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(1920, 1080));

      expect(find.text('播放页测试视频'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
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
            case 'resize':
              final arguments = call.arguments as Map<Object?, Object?>;
              return <String, Object?>{
                'width': arguments['width'],
                'height': arguments['height'],
              };
            case 'dispose':
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

      await _pumpPlaybackPage(tester, externalPlaybackMockInstalled: true);

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
    'Android playback selects TextureView on flagged legacy devices',
    (WidgetTester tester) async {
      const channel = MethodChannel('dev.ikaros.vesper_player/platform');
      const platformViewsChannel = MethodChannel('flutter/platform_views');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'shouldPreferTextureViewForPlayback',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        platformViewsChannel,
        (call) async {
          switch (call.method) {
            case 'create':
              return 1;
            case 'resize':
              final arguments = call.arguments as Map<Object?, Object?>;
              return <String, Object?>{
                'width': arguments['width'],
                'height': arguments['height'],
              };
            default:
              return null;
          }
        },
      );
      final externalPlayback = _ExternalPlaybackHarness()..install();
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          platformViewsChannel,
          null,
        );
        externalPlayback.uninstall();
      });

      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
        externalPlaybackMockInstalled: true,
      );
      await _flushRealAsync(tester);
      await tester.pump();

      expect(
        harness.platform.lastRenderSurfaceKind,
        VesperPlayerRenderSurfaceKind.textureView,
      );
      expect(
        harness.platform.lastSystemPlaybackConfiguration?.backgroundMode,
        VesperBackgroundPlaybackMode.disabled,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
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
    'tv playback quality panel keeps auto selected during adaptive playback',
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

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_自动');
      expect(find.text('自动'), findsOneWidget);
      expect(find.text('1080P'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback subtitle panel selects an SDK subtitle track',
    (WidgetTester tester) async {
      final subtitleSnapshot = _playbackSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsTrackCatalog: true,
          supportsTrackSelection: true,
          supportsSubtitleTrackSelection: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[
            VesperMediaTrack(
              id: 'subtitle:bili:zh-CN',
              kind: VesperMediaTrackKind.subtitle,
              label: '中文（中国大陆）',
              language: 'zh-CN',
              isDefault: true,
            ),
            VesperMediaTrack(
              id: 'subtitle:bili:en-US',
              kind: VesperMediaTrackKind.subtitle,
              label: 'English',
              language: 'en-US',
            ),
          ],
        ),
        confirmedSubtitleSelection: const VesperTrackSelection.track(
          'subtitle:bili:zh-CN',
        ),
      );
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
        initialSnapshot: subtitleSnapshot,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(of: find.text('字幕'), matching: find.byType(TvFocusable))
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('关闭'), findsNWidgets(2));
      expect(find.text('自动'), findsOneWidget);
      expect(find.text('中文（中国大陆）'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'tv_panel_中文（中国大陆）',
      );

      await tester.tap(
        find
            .ancestor(
              of: find.text('English'),
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pump();

      expect(harness.platform.subtitleSelections, hasLength(1));
      expect(
        harness.platform.subtitleSelections.single.mode,
        VesperTrackSelectionMode.track,
      );
      expect(
        harness.platform.subtitleSelections.single.trackId,
        'subtitle:bili:en-US',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback subtitle panel exposes unavailable state',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(of: find.text('字幕'), matching: find.byType(TvFocusable))
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('当前播放内核不支持字幕切换。'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_close');
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
      final subtitleX = tester.getTopLeft(find.text('字幕')).dx;
      final pagesX = tester.getTopLeft(find.text('分P')).dx;

      expect(playX, lessThan(rewindX));
      expect(rewindX, lessThan(forwardX));
      expect(forwardX, lessThan(qualityX));
      expect(qualityX, lessThan(speedX));
      expect(speedX, lessThan(subtitleX));
      expect(subtitleX, lessThan(pagesX));
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
      final panelList = tester.widget<ListView>(
        find.byKey(const PageStorageKey<String>('tv-panel-list-pages')),
      );

      Future<void> movePanel(LogicalKeyboardKey key, int count) async {
        for (var index = 0; index < count; index++) {
          await tester.sendKeyEvent(key);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          await tester.pump(const Duration(milliseconds: 180));
        }
      }

      panelList.controller!.jumpTo(
        700.0
            .clamp(0.0, panelList.controller!.position.maxScrollExtent)
            .toDouble(),
      );
      await tester.pump();
      final downwardOffset = panelList.controller!.offset;
      expect(downwardOffset, greaterThan(0));
      final panelListRect = tester.getRect(
        find.byKey(const PageStorageKey<String>('tv-panel-list-pages')),
      );
      var focusedPageNumber = pages.length;
      while (focusedPageNumber > 1) {
        final label = find.text('第 $focusedPageNumber 集');
        if (label.evaluate().isNotEmpty &&
            tester.getRect(label).overlaps(panelListRect)) {
          break;
        }
        focusedPageNumber -= 1;
      }
      expect(focusedPageNumber, greaterThan(3));
      final focusedPage = find
          .ancestor(
            of: find.text('第 $focusedPageNumber 集'),
            matching: find.byType(TvFocusable),
          )
          .last;
      tester
          .widget<Focus>(
            find
                .descendant(of: focusedPage, matching: find.byType(Focus))
                .first,
          )
          .focusNode
          ?.requestFocus();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'tv_panel_第 $focusedPageNumber 集',
      );

      await movePanel(LogicalKeyboardKey.arrowUp, focusedPageNumber - 1);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_第 1 集');
      expect(panelList.controller!.offset, lessThan(downwardOffset));
      expect(
        tester.getRect(find.text('第 1 集')).overlaps(panelListRect),
        isTrue,
      );

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
    'tv playback back closes panel then controls before leaving the page',
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
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('1.25x'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('1.25x'), findsNothing);
      expect(find.byType(BiliPlaybackPage), findsOneWidget);
      expect(find.byType(BiliTvHomePage), findsNothing);
      expect(find.text('退出 Vesper？'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('倍速'), findsNothing);
      expect(find.byType(BiliPlaybackPage), findsOneWidget);
      expect(find.byType(BiliTvHomePage), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback Android back closes one layer and restores focus',
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
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('1.25x'), findsOneWidget);

      await tester.sendKeyEvent(
        LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pump();
      expect(find.text('1.25x'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('1.25x'), findsNothing);
      expect(find.text('倍速'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_speed_button');
      expect(find.byType(BiliPlaybackPage), findsOneWidget);

      await tester.sendKeyEvent(
        LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pump();
      expect(find.text('倍速'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('倍速'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_playback');
      expect(find.byType(BiliPlaybackPage), findsOneWidget);
      expect(find.byType(BiliTvHomePage), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback back dismisses a modal notice without leaving playback',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );
      harness.platform.failSelectedSourcesRemaining = 3;
      harness.platform.emitPlaybackError(_expiredPlaybackAddressError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('播放地址刷新失败'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('bili-tv-dialog-surface')),
        findsOneWidget,
      );
      expect(find.byType(GlassDialog), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_知道了');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('播放地址刷新失败'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('播放地址刷新失败'), findsNothing);
      expect(find.byType(BiliPlaybackPage), findsOneWidget);
      expect(find.byType(BiliTvHomePage), findsNothing);
      expect(find.text('退出 Vesper？'), findsNothing);
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
      expect(find.text('退出 Vesper？'), findsNothing);
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

  testWidgets(
    'tv playback hidden controls keep seek and play pause shortcuts invisible',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      expect(find.text('播放'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_playback');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(harness.platform.seekRatios, hasLength(2));
      expect(harness.platform.seekRatios.first, closeTo(10000 / 120000, 0.001));
      expect(harness.platform.seekRatios.last, 0);
      expect(find.text('播放'), findsNothing);

      final playCallsBeforeShortcut = harness.platform.playCalls;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(harness.platform.playCalls, playCallsBeforeShortcut + 1);
      expect(find.text('播放'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_playback');

      harness.platform.emitSnapshot(_playingPlaybackSnapshot);
      await _flushRealAsync(tester);
      await tester.pump();
      final pauseCallsBeforeShortcut = harness.platform.pauseCalls;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(harness.platform.pauseCalls, pauseCallsBeforeShortcut + 1);
      expect(find.text('暂停'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_playback');
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
    final settings = AppSettingsStore(baseDirectory: root);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    await tester.runAsync(() => settings.setForceTvMode(false));
    final themeController = AppThemeController(settings: settings);
    final client = _FakeTvHomeClient();
    final historyStore = BiliHistoryStore(
      baseDirectory: Directory('${root.path}/history'),
    );
    final sessionStore = BiliSessionStore(baseDirectory: root);
    final offlineController = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[],
    );
    addTearDown(themeController.dispose);
    await tester.pumpWidget(
      AppThemeScope(
        controller: themeController,
        child: MaterialApp(
          theme: AppVisualTokens.mobileLightTheme(),
          home: BiliSettingsPage(
            appSettings: settings,
            client: client,
            historyStore: historyStore,
            sessionStore: sessionStore,
            offlineController: offlineController,
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('根据设备自动选择界面'));

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('根据设备自动选择界面'), findsOneWidget);
    expect(find.text('返回首页并切换'), findsNothing);

    await tester.tap(find.text('强制 TV 模式'));
    await _pumpUntilFound(tester, find.text('返回首页后切换为 TV 界面'));

    expect(find.text('返回首页后切换为 TV 界面'), findsOneWidget);
    expect(find.text('返回首页并切换'), findsOneWidget);
    expect(await tester.runAsync(settings.getForceTvMode), isTrue);
    expect(find.text('TV 模式已开启'), findsOneWidget);

    await tester.tap(find.text('返回首页并切换'));
    await _pumpUntilFound(tester, find.byType(HomePage));
    expect(find.text('TV 模式已开启'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    final homePage = tester.widget<HomePage>(find.byType(HomePage));
    expect(identical(homePage.client, client), isTrue);
    expect(identical(homePage.historyStore, historyStore), isTrue);
    expect(identical(homePage.sessionStore, sessionStore), isTrue);
    expect(identical(homePage.offlineController, offlineController), isTrue);
    expect(identical(homePage.appSettings, settings), isTrue);
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
    final appSettings = AppSettingsStore(baseDirectory: root);
    final themeController = AppThemeController(settings: appSettings);
    addTearDown(themeController.dispose);
    await tester.pumpWidget(
      AppThemeScope(
        controller: themeController,
        child: MaterialApp(
          theme: AppVisualTokens.mobileLightTheme(),
          home: BiliSettingsPage(
            appSettings: appSettings,
            client: client,
            sessionStore: sessionStore,
            offlineController: offlineController,
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.widgetWithText(TextButton, '退出'));

    expect(find.text('登录信息仅保存在本机'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '退出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.byType(GlassDialog), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(GlassDialog), matching: find.text('退出')),
    );
    await _pumpUntil(tester, () => offlineController.pauseAllActiveCalls == 1);
    await _pumpUntilFound(tester, find.text('可在“我的”页面扫码登录'));

    expect(offlineController.pauseAllActiveCalls, 1);
    expect(client.hasAuthenticatedSession, isFalse);
    expect(await tester.runAsync(sessionStore.loadCookies), isEmpty);
    expect(find.widgetWithText(TextButton, '退出'), findsNothing);
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
                  await showBiliQrLoginSheet(
                    context: context,
                    client: client,
                    sessionStore: BiliSessionStore(baseDirectory: root),
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
    expect(
      find.byKey(const ValueKey<String>('media-readable-glass-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bili-qr-code-surface')),
      findsOneWidget,
    );
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

  testWidgets('QR login sheet keeps readable contrast in dark mode', (
    WidgetTester tester,
  ) async {
    final client = _FakeQrLoginClient();
    final root = Directory(
      '${Directory.systemTemp.path}/bili-qr-dark-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.darkTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showBiliQrLoginSheet(
              context: context,
              client: client,
              sessionStore: BiliSessionStore(baseDirectory: root),
            ),
            child: const Text('登录'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('登录'));
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));

    final sheet = tester.widget<GlassSheet>(
      find.byKey(const ValueKey<String>('media-readable-glass-sheet')),
    );
    final title = tester.widget<Text>(find.text('扫码登录哔哩哔哩'));
    final qrSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('bili-qr-code-surface')),
    );
    final qrDecoration = qrSurface.decoration as BoxDecoration;

    expect(
      sheet.settings?.glassColor,
      AppVisualTheme.dark.surface.withValues(alpha: 0.96),
    );
    expect(title.style?.color, AppVisualTheme.dark.textPrimary);
    expect(qrDecoration.color, Colors.white);
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
                  poppedProfile = await showBiliQrLoginSheet(
                    context: context,
                    client: client,
                    sessionStore: BiliSessionStore(baseDirectory: root),
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
    const pagedSection = BiliRegionSection(
      id: 'bangumi',
      name: '番剧',
      icon: 'P',
      apiType: BiliRegionApiType.pgc,
      seasonType: 1,
    );

    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: BiliRegionVideoPage(
          section: pagedSection,
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

  testWidgets('region video page blocks unauthenticated direct access', (
    WidgetTester tester,
  ) async {
    final client = _UnauthenticatedRegionClient();

    await tester.pumpWidget(
      MaterialApp(
        home: BiliRegionVideoPage(
          section: _testRegionSection,
          client: client,
          historyStore: const BiliHistoryStore(),
        ),
      ),
    );
    await _flushRealAsync(tester);
    await tester.pump();

    expect(find.text('需要登录后查看分区内容'), findsOneWidget);
    expect(find.text('重新检查登录状态'), findsOneWidget);
    expect(client.fetchCalled, isFalse);
  });

  testWidgets('region video page turns an expired session into login state', (
    WidgetTester tester,
  ) async {
    final client = _FakeRegionClient()
      ..firstPageError = const BiliApiException('账号未登录', code: -101);

    await tester.pumpWidget(
      MaterialApp(
        home: BiliRegionVideoPage(
          section: _testRegionSection,
          client: client,
          historyStore: const BiliHistoryStore(),
        ),
      ),
    );
    await _flushRealAsync(tester);
    await tester.pump();

    expect(find.text('需要登录后查看分区内容'), findsOneWidget);
    expect(find.textContaining('账号未登录'), findsNothing);
    expect(client.requestedPages, <int>[1]);
  });

  testWidgets('region hub hides category grid for unauthenticated access', (
    WidgetTester tester,
  ) async {
    final client = _UnauthenticatedRegionClient();

    await tester.pumpWidget(
      MaterialApp(home: BiliRegionHubPage(client: client)),
    );
    await tester.pump();

    expect(find.text('需要登录后查看分区内容'), findsOneWidget);
    expect(find.text(_testRegionSection.name), findsNothing);
    expect(client.fetchCalled, isFalse);
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
