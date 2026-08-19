part of '../widget_test.dart';

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

  @override
  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async => _testDetail();
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
