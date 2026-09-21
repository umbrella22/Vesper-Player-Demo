import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/models/bili_favorites_models.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_endpoints.dart';
import 'package:vesper_media/bili/common/services/bili_transport.dart';
import 'package:vesper_media/bili/common/view_models/bili_favorites_view_model.dart';

void main() {
  group('favorite API contracts', () {
    late _FavoritesTransport transport;
    late BiliClient client;

    setUp(() {
      transport = _FavoritesTransport();
      client = BiliClient(transport: transport)
        ..restoreCookies(const {
          'SESSDATA': 'test-session',
          'bili_jct': 'test-csrf',
          'DedeUserID': '42',
        });
    });

    tearDown(() => transport.httpClient.close(force: true));

    test('folder metadata preserves unknown counts and real zero', () async {
      transport.folders = {
        'list': [
          {'id': 1, 'title': '收藏 & 学习', 'media_count': 0, 'attr': 1},
          {
            'id': 2,
            'title': '影视',
            'cover': '//example.com/cover.jpg',
            'attr': 0,
          },
          {'id': 3, 'title': '其他'},
        ],
      };
      final folders = await client.fetchFavoriteFolders();
      expect(folders[0].mediaCount, 0);
      expect(folders[0].title, '收藏 & 学习');
      expect(folders[0].isPrivate, isTrue);
      expect(folders[1].mediaCount, isNull);
      expect(folders[1].coverUrl, 'https://example.com/cover.jpg');
      expect(folders[1].isPrivate, isFalse);
      expect(folders[2].isPrivate, isNull);
      expect(transport.requests.single.params['up_mid'], 42);
      expect(transport.requests.single.params.containsKey('rid'), isFalse);
    });

    test('keeps unavailable videos and other resource kinds visible', () async {
      transport.resources = {
        'info': {'media_count': 4},
        'has_more': false,
        'medias': [
          _rawItem(1),
          {..._rawItem(2), 'attr': 9, 'title': '已失效视频'},
          {..._rawItem(3), 'type': 12},
          {..._rawItem(4), 'bvid': ''},
        ],
      };
      final result = await client.fetchFavoriteItems(folderId: 9);
      expect(result.items, hasLength(4));
      expect(result.items.first.isAvailable, isTrue);
      expect(result.items.skip(1).every((item) => !item.isAvailable), isTrue);
      expect(result.items.first.durationLabel, '02:03');
      expect(result.items.first.playCountLabel, '1.2万');
      expect(result.items.first.ownerName, '测试 UP');
      expect(result.items.first.favoritedAtLabel, isNotEmpty);
      expect(result.totalCount, 4);
      expect(result.hasMore, isFalse);
    });

    test('search and sort are folder scoped and trust has_more', () async {
      transport.resources = {
        'info': {'media_count': 100},
        'has_more': 0,
        'medias': [_rawItem(1)],
      };
      final result = await client.fetchFavoriteItems(
        folderId: 9,
        page: 2,
        keyword: '  Flutter & Dart  ',
        order: BiliFavoriteOrder.newestPublished,
      );
      expect(transport.requests.single.params, {
        'media_id': 9,
        'pn': 2,
        'ps': 20,
        'keyword': 'Flutter & Dart',
        'order': 'pubtime',
        'type': 0,
        'tid': 0,
      });
      expect(result.totalCount, isNull);
      expect(result.hasMore, isFalse);
    });

    test(
      'missing search has_more uses raw page size, not folder count',
      () async {
        transport.resources = {
          'info': {'media_count': 100},
          'medias': [_rawItem(1)],
        };
        expect(
          (await client.fetchFavoriteItems(folderId: 9, keyword: 'x')).hasMore,
          isFalse,
        );
        transport.resources = {
          'medias': [
            _rawItem(1),
            {'id': 0},
          ],
        };
        final page = await client.fetchFavoriteItems(folderId: 9, pageSize: 2);
        expect(page.items, hasLength(1));
        expect(page.hasMore, isTrue);
      },
    );

    test('rejects missing login and invalid folder before requests', () async {
      await expectLater(
        client.fetchFavoriteItems(folderId: 0),
        throwsArgumentError,
      );
      client.clearSession();
      final authError = isA<BiliApiException>().having(
        (e) => e.code,
        'code',
        -101,
      );
      await expectLater(client.fetchFavoriteFolders(), throwsA(authError));
      await expectLater(
        client.fetchFavoriteItems(folderId: 9),
        throwsA(authError),
      );
      expect(transport.requests, isEmpty);
    });

    test(
      'empty raw pages terminate even when server has_more is stale',
      () async {
        transport.resources = {'medias': [], 'has_more': true};
        final result = await client.fetchFavoriteItems(folderId: 9);
        expect(result.hasMore, isFalse);
      },
    );

    test('batch removal sends folder-scoped resource ids', () async {
      await client.removeFavoriteItems(
        folderId: 9,
        resourceIds: const ['123:2', '456:2'],
      );
      expect(transport.posts.single.path, BiliApiPaths.favResourceBatchDel);
      expect(transport.posts.single.data, {
        'resources': '123:2,456:2',
        'media_id': 9,
      });
    });

    test('batch removal rejects malformed ids and empty requests', () async {
      await expectLater(
        client.removeFavoriteItems(folderId: 9, resourceIds: const ['abc']),
        throwsArgumentError,
      );
      await expectLater(
        client.removeFavoriteItems(folderId: 0, resourceIds: const ['1:2']),
        throwsArgumentError,
      );
      await client.removeFavoriteItems(folderId: 9, resourceIds: const []);
      expect(transport.posts, isEmpty);
    });

    test('folder creation trims the title and maps privacy', () async {
      transport.postResult = {'id': 77};
      final id = await client.createFavoriteFolder(
        title: '  学习  ',
        isPrivate: true,
      );
      expect(id, 77);
      expect(transport.posts.single.path, BiliApiPaths.favFolderAdd);
      expect(transport.posts.single.data, {'title': '学习', 'privacy': 1});

      await expectLater(
        client.createFavoriteFolder(title: '   ', isPrivate: false),
        throwsA(isA<BiliApiException>()),
      );
      expect(transport.posts, hasLength(1));
    });

    test('folder creation surfaces a missing server id', () async {
      transport.postResult = const <String, Object?>{};
      await expectLater(
        client.createFavoriteFolder(title: '学习', isPrivate: false),
        throwsA(isA<BiliApiException>()),
      );
    });

    test('favorite selection submits only the requested difference', () async {
      // 取消收藏只移出用户显式取消的收藏夹，其余归属保持不变。
      transport.folders = {
        'list': [
          {'id': 1, 'title': '默认', 'fav_state': 1, 'media_count': 2},
          {'id': 2, 'title': '学习', 'fav_state': 1, 'media_count': 1},
        ],
      };
      transport.relation = {'like': false, 'favorite': true};
      final current = BiliVideoEngagement(
        isAuthenticated: true,
        isLiked: false,
        isFavorited: true,
        isFollowingOwner: false,
        favoriteMediaIds: const [1, 2],
      );
      final result = await client.applyVideoFavoriteSelection(
        detail: _detail(),
        current: current,
        selection: const BiliFavoriteSelection(
          addFolderIds: [],
          removeFolderIds: [1],
        ),
      );
      final deal = transport.posts.single;
      expect(deal.path, BiliApiPaths.favResourceDeal);
      expect(deal.data['del_media_ids'], '1');
      expect(deal.data['add_media_ids'], '');
      // 服务端在重新读取时仍报告两个归属，以服务端结果为准。
      expect(result.isFavorited, isTrue);
      expect(result.favoriteMediaIds, [1, 2]);
    });

    test(
      'a failed refetch falls back to the requested difference, not "empty"',
      () async {
        final current = BiliVideoEngagement(
          isAuthenticated: true,
          isLiked: false,
          isFavorited: true,
          isFollowingOwner: false,
          favoriteMediaIds: const [1, 2],
        );
        // relation 未配置 -> fetchVideoEngagement 抛错 -> 走回退分支。
        final result = await client.applyVideoFavoriteSelection(
          detail: _detail(),
          current: current,
          selection: const BiliFavoriteSelection(
            addFolderIds: [],
            removeFolderIds: [1],
          ),
        );
        expect(result.isFavorited, isTrue);
        expect(result.favoriteMediaIds, [2]);
      },
    );

    test('an empty selection performs no write request', () async {
      final base = BiliVideoEngagement(
        isAuthenticated: true,
        isLiked: false,
        isFavorited: true,
        isFollowingOwner: false,
        favoriteMediaIds: const [1],
      );
      final result = await client.applyVideoFavoriteSelection(
        detail: _detail(),
        current: base,
        selection: const BiliFavoriteSelection(
          addFolderIds: [],
          removeFolderIds: [],
        ),
      );
      expect(transport.posts, isEmpty);
      expect(result.favoriteMediaIds, [1]);
    });

    test('favorite diff reports additions and removals', () {
      final selection = BiliFavoriteSelection.diff(
        current: const [1, 2],
        target: const [2, 3],
      );
      expect(selection.addFolderIds, [3]);
      expect(selection.removeFolderIds, [1]);
      expect(selection.isEmpty, isFalse);
      expect(
        BiliFavoriteSelection.diff(
          current: const [1],
          target: const [1],
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('favorite view model', () {
    late _FavoritesClient client;
    late BiliFavoritesViewModel model;

    setUp(() {
      client = _FavoritesClient();
      model = BiliFavoritesViewModel(client: client);
    });
    tearDown(() {
      model.dispose();
      client.transport.httpClient.close(force: true);
    });

    test(
      'explicit refresh retries missing covers before cards are rebuilt',
      () async {
        model.dispose();
        model = BiliFavoritesViewModel(
          client: client,
          autoSelectFirstFolder: false,
        );
        final emptyPage = Completer<BiliFavoritePage>()..complete(_page([]));
        client.nextFirstPage = emptyPage;
        expect(await client.favoriteCovers.coverFor(_folder1), isEmpty);
        expect(client.requests, hasLength(1));
        await model.initialize();
        expect(await client.favoriteCovers.coverFor(_folder1), isEmpty);
        expect(client.requests, hasLength(1));
        await model.refresh();
        final restoredPage = Completer<BiliFavoritePage>()..complete(_page([]));
        client.nextFirstPage = restoredPage;
        await client.favoriteCovers.coverFor(_folder1);
        expect(client.requests, hasLength(2));
      },
    );

    test(
      'logged out and empty folder states do not request contents',
      () async {
        client.authenticated = false;
        await model.initialize();
        expect(model.authenticationRequired.value, isTrue);
        expect(client.folderRequests, 0);
        expect(client.requests, isEmpty);
        client.authenticated = true;
        client.folders = [];
        await model.refresh();
        expect(model.authenticationRequired.value, isFalse);
        expect(model.activeFolderId.value, isNull);
        expect(model.items.value, isEmpty);
        expect(model.isLoading.value, isFalse);
        expect(client.requests, isEmpty);
      },
    );

    test(
      'switching folders rejects stale page and keeps current busy state',
      () async {
        await model.initialize();
        final oldPage = model.loadMore();
        final oldRequest = client.requests.last;
        final newFirstPage = Completer<BiliFavoritePage>();
        client.nextFirstPage = newFirstPage;
        final switching = model.selectFolder(2);
        expect(model.items.value, isEmpty);
        expect(model.isLoading.value, isTrue);
        oldRequest.completer.complete(_page([_item(99)], page: 2));
        await oldPage;
        expect(model.items.value, isEmpty);
        expect(model.isLoading.value, isTrue);
        newFirstPage.complete(_page([_item(2)]));
        await switching;
        expect(model.items.value.single.id, 2);
        expect(model.activeFolder.value?.id, 2);
        expect(model.isLoading.value, isFalse);
      },
    );

    test(
      'search and sort invalidate old requests and retain folder scope',
      () async {
        await model.initialize();
        final oldSearchResult = Completer<BiliFavoritePage>();
        client.nextFirstPage = oldSearchResult;
        final oldSearch = model.search(' earlier ');
        await model.search(' latest ');
        oldSearchResult.completeError(const BiliApiException('旧搜索失败'));
        await oldSearch;
        expect(model.keyword.value, 'latest');
        expect(model.errorMessage.value, isNull);
        await model.setOrder(BiliFavoriteOrder.mostPlayed);
        expect(client.requests.last.order, BiliFavoriteOrder.mostPlayed);
        expect(client.requests.last.keyword, 'latest');
        await model.selectFolder(2);
        expect(client.requests.last.folderId, 2);
        expect(client.requests.last.keyword, 'latest');
        await model.search('');
        expect(client.requests.last.keyword, isEmpty);
      },
    );

    test(
      'pagination failure keeps rows and retries same page without duplicates',
      () async {
        await model.initialize();
        final pending = model.loadMore();
        await model.loadMore();
        expect(
          client.requests.where((request) => request.page == 2),
          hasLength(1),
        );
        client.requests.last.completer.completeError(
          const BiliApiException('暂时失败'),
        );
        await pending;
        expect(model.items.value.single.id, 1);
        expect(model.loadMoreErrorMessage.value, isNotNull);
        final retry = model.loadMore();
        expect(client.requests.last.page, 2);
        client.requests.last.completer.complete(
          _page([_item(1), _item(2)], page: 2, hasMore: false),
        );
        await retry;
        expect(model.items.value.map((item) => item.id), [1, 2]);
        expect(model.loadMoreErrorMessage.value, isNull);
        expect(model.hasMore.value, isFalse);
      },
    );

    test(
      'refresh preserves selection or selects first remaining folder',
      () async {
        await model.initialize();
        await model.selectFolder(2);
        await model.refresh();
        expect(model.activeFolderId.value, 2);
        client.folders = const [_folder1];
        await model.refresh();
        expect(model.activeFolderId.value, 1);
        expect(client.requests.last.folderId, 1);
      },
    );

    test(
      'expired login clears protected rows after pagination error',
      () async {
        await model.initialize();
        final pending = model.loadMore();
        client.requests.last.completer.completeError(
          const BiliApiException('未登录', code: -101),
        );
        await pending;
        expect(model.authenticationRequired.value, isTrue);
        expect(model.items.value, isEmpty);
        expect(model.folders.value, isEmpty);
        expect(model.isLoadingMore.value, isFalse);
      },
    );

    test('logout during request cannot restore private contents', () async {
      await model.initialize();
      final pending = model.loadMore();
      client.authenticated = false;
      client.requests.last.completer.complete(_page([_item(2)], page: 2));
      await pending;
      expect(model.authenticationRequired.value, isTrue);
      expect(model.items.value, isEmpty);
    });

    test(
      'logout followed by ordinary request error still clears private rows',
      () async {
        await model.initialize();
        final pending = model.loadMore();
        client.authenticated = false;
        client.requests.last.completer.completeError(
          TimeoutException('offline'),
        );
        await pending;
        expect(model.authenticationRequired.value, isTrue);
        expect(model.items.value, isEmpty);
        expect(model.loadMoreErrorMessage.value, isNull);
      },
    );

    test(
      'account replacement invalidates pending results without expiring new login',
      () async {
        await model.initialize();
        final pending = model.loadMore();
        client.restoreCookies(const {'DedeUserID': 'another-account'});
        client.requests.last.completer.complete(_page([_item(2)], page: 2));
        await pending;
        expect(model.authenticationRequired.value, isFalse);
        expect(model.items.value, isEmpty);
        expect(model.errorMessage.value, contains('登录账号已变化'));
        await model.refresh();
        expect(model.items.value, isNotEmpty);
        expect(model.errorMessage.value, isNull);
      },
    );

    test(
      'account replacement before pagination does not query old folder',
      () async {
        await model.initialize();
        final requestsBefore = client.requests.length;
        client.restoreCookies(const {'DedeUserID': 'another-account'});
        await model.loadMore();
        expect(client.requests.length, requestsBefore);
        expect(model.items.value, isEmpty);
      },
    );

    test(
      'duplicate pages terminate pagination without losing unavailable rows',
      () async {
        await model.initialize();
        final pending = model.loadMore();
        client.requests.last.completer.complete(_page([_item(1)], page: 2));
        await pending;
        expect(model.items.value.single.id, 1);
        expect(model.hasMore.value, isFalse);
        final requestCount = client.requests.length;
        await model.loadMore();
        expect(client.requests.length, requestCount);
      },
    );
  });
}

BiliVideoDetail _detail() => const BiliVideoDetail(
  aid: 55,
  bvid: 'BV55',
  title: '收藏视频',
  ownerMid: 7,
  ownerName: 'UP 主',
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
  pages: [
    BiliVideoPageEntry(
      cid: 11,
      pageNumber: 1,
      title: 'P1',
      durationSeconds: 60,
    ),
  ],
);

Map<String, Object?> _rawItem(int id) => {
  'id': id,
  'type': 2,
  'bvid': 'BV$id',
  'title': '收藏视频 $id',
  'cover': '//example.com/$id.jpg',
  'duration': 123,
  'fav_time': 1710000000,
  'upper': {'name': '测试 UP'},
  'cnt_info': {'play': 12000},
  'attr': 0,
};

final class _FavoritesTransport extends BiliTransport {
  Map<String, Object?> folders = {};
  Map<String, Object?> resources = {};
  Map<String, Object?>? relation;
  final requests = <({String path, Map<String, Object?> params})>[];
  final posts = <({String path, Map<String, Object?> data})>[];
  Map<String, Object?> postResult = const <String, Object?>{};

  /// 测试不建立真实的 buvid/WBI 前置请求，直接放行。
  @override
  Future<void> ensureReady() async {}

  @override
  Future<Map<String, Object?>> getData({
    required String host,
    required String path,
    Map<String, Object?> params = const {},
    bool useWbi = false,
    String referer = biliDefaultReferer,
    bool ensureReady = true,
    Set<int> allowedCodes = const {0},
  }) async {
    requests.add((path: path, params: params));
    return switch (path) {
      BiliApiPaths.favFolderListAll => folders,
      BiliApiPaths.favResourceList => resources,
      BiliApiPaths.archiveRelation =>
        relation ?? (throw StateError('relation not configured')),
      _ => throw StateError('Unexpected endpoint: $path'),
    };
  }

  @override
  Future<Map<String, Object?>> postData({
    required String host,
    required String path,
    Map<String, Object?> data = const <String, Object?>{},
    String referer = biliDefaultReferer,
    bool ensureReady = true,
  }) async {
    posts.add((path: path, data: data));
    return postResult;
  }
}

const _folder1 = BiliFavoriteFolder(
  id: 1,
  title: '默认',
  containsCurrentVideo: false,
);
const _folder2 = BiliFavoriteFolder(
  id: 2,
  title: '学习',
  containsCurrentVideo: false,
);

BiliFavoriteItem _item(int id) => BiliFavoriteItem(
  id: id,
  bvid: 'BV$id',
  title: '收藏视频 $id',
  coverUrl: '',
  ownerName: 'UP',
  durationLabel: '01:00',
  playCountLabel: '1',
  favoritedAtLabel: '',
  isAvailable: true,
);

BiliFavoritePage _page(
  List<BiliFavoriteItem> items, {
  int page = 1,
  bool hasMore = true,
}) =>
    BiliFavoritePage(items: items, page: page, pageSize: 20, hasMore: hasMore);

final class _FavoriteRequest {
  _FavoriteRequest(
    this.folderId,
    this.page,
    this.keyword,
    this.order,
    this.completer,
  );
  final int folderId;
  final int page;
  final String keyword;
  final BiliFavoriteOrder order;
  final Completer<BiliFavoritePage> completer;
}

final class _FavoritesClient extends BiliClient {
  bool authenticated = true;
  int folderRequests = 0;
  List<BiliFavoriteFolder> folders = [_folder1, _folder2];
  Completer<BiliFavoritePage>? nextFirstPage;
  final requests = <_FavoriteRequest>[];

  @override
  bool get hasAuthenticatedSession => authenticated;

  @override
  Future<List<BiliFavoriteFolder>> fetchFavoriteFolders() async {
    folderRequests++;
    return folders;
  }

  @override
  Future<BiliFavoritePage> fetchFavoriteItems({
    required int folderId,
    int page = 1,
    int pageSize = 20,
    String keyword = '',
    BiliFavoriteOrder order = BiliFavoriteOrder.recent,
  }) {
    final completer = page == 1
        ? nextFirstPage ?? Completer<BiliFavoritePage>()
        : Completer<BiliFavoritePage>();
    final delayedFirstPage = nextFirstPage != null;
    nextFirstPage = null;
    requests.add(_FavoriteRequest(folderId, page, keyword, order, completer));
    if (page == 1 && !delayedFirstPage) {
      completer.complete(_page([_item(folderId)]));
    }
    return completer.future;
  }
}
