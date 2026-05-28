import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilibili_player/bili/app_mode/pages/bili_hub_page.dart';
import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:bilibili_player/bili/common/services/bili_session_store.dart';
import 'package:bilibili_player/bili/common/view_models/bili_hub_view_model.dart';
import 'package:bilibili_player/download/download.dart';
import 'package:bilibili_player/download/services/offline_media_exporter.dart';
import 'package:bilibili_player/download/view_models/offline_cache_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  group('OfflineCacheViewModel', () {
    test('initializes storage and deletes entries', () async {
      final entry = _offlineEntry();
      final controller = _FakeOfflineController(
        <BiliOfflineDownloadEntry>[entry],
        storageUsage: const BiliOfflineStorageUsage(
          cacheBytes: 2048,
          freeBytes: 4096,
          totalBytes: 6144,
        ),
      );
      final viewModel = OfflineCacheViewModel(controller: controller);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();

      expect(viewModel.loading.value, isFalse);
      expect(viewModel.storageUsage.value?.cacheBytes, 2048);
      expect(viewModel.completedEntries.value, hasLength(1));

      final result = await viewModel.deleteEntry(entry);

      expect(result.deleted, isTrue);
      expect(result.message, '已删除缓存');
      expect(controller.removedAssetIds, <String>[entry.metadata.assetId]);
      expect(viewModel.entries.value, isEmpty);
    });

    test('reports delete failures without removing entry', () async {
      final entry = _offlineEntry();
      final controller = _FakeOfflineController(<BiliOfflineDownloadEntry>[
        entry,
      ], failRemove: true);
      final viewModel = OfflineCacheViewModel(controller: controller);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();
      final result = await viewModel.deleteEntry(entry);

      expect(result.deleted, isFalse);
      expect(result.message, contains('删除失败'));
      expect(viewModel.entries.value, <BiliOfflineDownloadEntry>[entry]);
    });

    test('opens completed cache with offline playback route data', () async {
      final directory = await Directory.systemTemp.createTemp(
        'bili-offline-vm-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/video.mp4');
      await file.writeAsBytes(<int>[0, 1, 2]);
      final entry = _offlineEntry(outputPath: file.path);
      final controller = _FakeOfflineController(<BiliOfflineDownloadEntry>[
        entry,
      ]);
      final viewModel = OfflineCacheViewModel(
        controller: controller,
        client: BiliClient(httpClient: _FakeBiliHttpClient()),
      );
      addTearDown(viewModel.dispose);

      await viewModel.initialize();
      final result = await viewModel.openEntry(entry);

      expect(result, isNotNull);
      expect(result!.detail.bvid, 'BV1xx411c7mD');
      expect(result.page.cid, 11);
      expect(result.message, isNull);
      expect(result.initialResolvedPlayback?.isLocalFile, isTrue);
      expect(
        result.initialResolvedPlayback?.protocol,
        VesperPlayerSourceProtocol.file,
      );
      expect(result.initialResolvedPlayback?.debugPath, file.path);
    });

    test('exports completed mp4 cache to gallery', () async {
      final directory = await Directory.systemTemp.createTemp(
        'bili-offline-export-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/video.mp4');
      await file.writeAsBytes(<int>[0, 1, 2]);
      final entry = _offlineEntry(outputPath: file.path);
      final exporter = _FakeMediaExporter();
      final viewModel = OfflineCacheViewModel(
        controller: _FakeOfflineController(<BiliOfflineDownloadEntry>[entry]),
        mediaExporter: exporter,
      );
      addTearDown(viewModel.dispose);

      await viewModel.initialize();
      final result = await viewModel.exportEntry(entry);

      expect(result.exported, isTrue);
      expect(result.message, '已导出到相册');
      expect(exporter.sourcePath, file.path);
      expect(exporter.displayName, endsWith('.mp4'));
    });
  });

  group('BiliHubViewModel', () {
    test(
      'clears search state and resolves direct BV playback target',
      () async {
        final viewModel = BiliHubViewModel(
          client: BiliClient(httpClient: _FakeBiliHttpClient()),
        );
        addTearDown(viewModel.dispose);

        viewModel.updateQuery('https://www.bilibili.com/video/BV1xx411c7mD');

        expect(viewModel.directBvid.value, 'BV1xx411c7mD');

        final target = await viewModel.resolvePlaybackTarget(
          'BV1xx411c7mD',
          cid: 11,
        );

        expect(target.detail.title, '离线视频');
        expect(target.initialPage.cid, 11);

        viewModel.clearSearch();

        expect(viewModel.query.value, isEmpty);
        expect(viewModel.results.value, isEmpty);
        expect(viewModel.activeSearchKeyword.value, isNull);
      },
    );

    test('tracks search loading, results, and feed refresh state', () async {
      final client = _FakeBiliHubClient();
      final viewModel = BiliHubViewModel(client: client);
      addTearDown(viewModel.dispose);

      viewModel.updateQuery('flutter');
      final search = viewModel.runSearch();

      expect(viewModel.isSearching.value, isTrue);
      expect(viewModel.activeSearchKeyword.value, 'flutter');

      await search;

      expect(viewModel.isSearching.value, isFalse);
      expect(viewModel.results.value, hasLength(1));
      expect(viewModel.hasMoreSearch.value, isTrue);

      await viewModel.loadFeed();

      expect(viewModel.isRefreshingFeed.value, isFalse);
      expect(viewModel.feedItems.value, hasLength(1));
      expect(viewModel.feedErrorMessage.value, isNull);
    });

    test('logout clears session and pauses offline cache', () async {
      final root = await Directory.systemTemp.createTemp(
        'bili-hub-logout-vm-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final client = _FakeBiliHubClient()
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
        });
      final sessionStore = BiliSessionStore(baseDirectory: root);
      await sessionStore.saveCookies(client.snapshotCookies());
      final offlineController = _FakeOfflineController(
        <BiliOfflineDownloadEntry>[],
      );
      final viewModel = BiliHubViewModel(
        client: client,
        sessionStore: sessionStore,
        historyStore: BiliHistoryStore(
          baseDirectory: Directory('${root.path}/history'),
        ),
        offlineController: offlineController,
      );
      addTearDown(viewModel.dispose);

      await viewModel.logout();

      expect(offlineController.pauseAllActiveCalls, 1);
      expect(client.hasAuthenticatedSession, isFalse);
      expect(await sessionStore.loadCookies(), isEmpty);
      expect(viewModel.profile.value.isLoggedIn, isFalse);
      expect(viewModel.profileErrorMessage.value, isNull);
    });
  });

  group('responsive helpers', () {
    test('home grid increases columns on wide surfaces', () {
      expect(biliHomeGridCrossAxisCountForWidth(390), 2);
      expect(biliHomeGridCrossAxisCountForWidth(900), greaterThan(2));
      expect(biliHomeGridCrossAxisCountForWidth(1400), 5);
    });
  });
}

BiliOfflineDownloadEntry _offlineEntry({String? outputPath}) {
  return BiliOfflineDownloadEntry(
    metadata: BiliOfflineDownloadMetadata(
      assetId: 'BV1xx411c7mD-c11-q80-avc-test',
      bvid: 'BV1xx411c7mD',
      cid: 11,
      videoTitle: '离线视频',
      pageTitle: 'P1 · 正片',
      coverUrl: '',
      qualityLabel: '1080P',
      outputPath: outputPath,
      createdAtMs: 100,
    ),
  );
}

final class _FakeOfflineController extends BiliOfflineDownloadController {
  _FakeOfflineController(
    this._entries, {
    this.failRemove = false,
    this.storageUsage = const BiliOfflineStorageUsage(
      cacheBytes: 0,
      freeBytes: 0,
      totalBytes: 0,
    ),
  }) : super(client: BiliClient());

  final List<BiliOfflineDownloadEntry> _entries;
  final bool failRemove;
  final BiliOfflineStorageUsage storageUsage;
  final List<String> removedAssetIds = <String>[];
  var pauseAllActiveCalls = 0;

  @override
  bool get isInitialized => true;

  @override
  List<BiliOfflineDownloadEntry> get entries => _entries;

  @override
  Future<void> initialize() async {}

  @override
  Future<BiliOfflineStorageUsage> resolveStorageUsage() async {
    return storageUsage;
  }

  @override
  Future<void> removeEntry(BiliOfflineDownloadEntry entry) async {
    if (failRemove) {
      throw const BiliOfflineDownloadException('remove failed');
    }
    removedAssetIds.add(entry.metadata.assetId);
    _entries.removeWhere(
      (current) => current.metadata.assetId == entry.metadata.assetId,
    );
    notifyListeners();
  }

  @override
  Future<void> pauseAllActive() async {
    pauseAllActiveCalls += 1;
  }
}

final class _FakeMediaExporter extends BiliOfflineMediaExporter {
  _FakeMediaExporter();

  String? sourcePath;
  String? displayName;

  @override
  Future<String?> exportMp4ToGallery({
    required String sourcePath,
    required String displayName,
  }) async {
    this.sourcePath = sourcePath;
    this.displayName = displayName;
    return 'gallery://video';
  }
}

final class _FakeBiliHubClient extends BiliClient {
  @override
  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) async {
    return page == 1
        ? const <BiliFeedVideo>[
            BiliFeedVideo(
              aid: 1,
              bvid: 'BV1feed0000',
              title: '推荐视频',
              author: '测试UP',
              coverUrl: '',
              durationLabel: '03:00',
              playCountLabel: '1万',
              danmakuCountLabel: '2',
            ),
          ]
        : const <BiliFeedVideo>[];
  }

  @override
  Future<List<BiliSearchResult>> searchVideos(
    String keyword, {
    int page = 1,
  }) async {
    return page == 1
        ? const <BiliSearchResult>[
            BiliSearchResult(
              aid: 2,
              bvid: 'BV1search0',
              title: '搜索视频',
              author: '测试UP',
              coverUrl: '',
              durationLabel: '03:00',
              playCountLabel: '1万',
              danmakuCountLabel: '3',
            ),
          ]
        : const <BiliSearchResult>[];
  }
}

final class _FakeBiliHttpClient implements HttpClient {
  String? _userAgent;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) {
    _userAgent = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeHttpClientRequest(_responseFor(url));
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return _FakeHttpClientRequest(_responseFor(url));
  }

  _FakeHttpClientResponse _responseFor(Uri url) {
    return _FakeHttpClientResponse(_videoDetailJson());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._response);

  final _FakeHttpClientResponse _response;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();
  int _contentLength = -1;

  @override
  HttpHeaders get headers => _headers;

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) {
    _contentLength = value;
  }

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this.body);

  final String body;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[
      utf8.encode(body),
    ]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> values = <String, List<String>>{};
  ContentType? _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) {
    _contentType = value;
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = <String>[value.toString()];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _videoDetailJson() {
  return jsonEncode(<String, Object?>{
    'code': 0,
    'message': '0',
    'data': <String, Object?>{
      'aid': 1,
      'bvid': 'BV1xx411c7mD',
      'title': '离线视频',
      'pic': '',
      'desc': '',
      'owner': <String, Object?>{'mid': 2, 'name': '测试UP', 'face': ''},
      'stat': <String, Object?>{
        'view': 100,
        'danmaku': 2,
        'reply': 3,
        'like': 4,
        'coin': 5,
        'favorite': 6,
        'share': 7,
      },
      'pages': <Object?>[
        <String, Object?>{'cid': 11, 'page': 1, 'part': '正片', 'duration': 60},
      ],
    },
  });
}
