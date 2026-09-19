import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_favorites_page.dart';
import 'package:vesper_media/bili/common/models/bili_favorites_models.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';

void main() {
  testWidgets('folder cards open contents and back returns to the overview', (
    tester,
  ) async {
    final client = _FavoritesClient();
    await _pumpPage(tester, client, openFirstFolder: false);
    expect(find.text('默认收藏夹'), findsOneWidget);
    expect(find.text('3 个内容'), findsOneWidget);
    expect(find.text('学习'), findsWidgets);
    expect(find.text('全部'), findsNothing);
    expect(find.text('0 个内容'), findsNothing);
    expect(find.text('第一条收藏'), findsNothing);
    expect(client.requests, isEmpty);
    await tester.tap(find.byKey(const ValueKey('favorite-folder-1')));
    await tester.pumpAndSettle();
    expect(find.text('第一条收藏'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-folder-1')), findsOneWidget);

    final pending = Completer<BiliFavoritePage>();
    client.loadItems = (_) => pending.future;
    await tester.tap(find.byKey(const ValueKey('favorite-folder-2')));
    await tester.pump();
    expect(find.text('第一条收藏'), findsNothing);
    expect(client.requests.last.folderId, 2);
    pending.complete(_page(items: [_item(2, title: '学习收藏')]));
    await tester.pumpAndSettle();
    expect(find.text('学习收藏'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('draft waits for submit and sort keeps the submitted keyword', (
    tester,
  ) async {
    final client = _FavoritesClient();
    await _pumpPage(tester, client);
    final search = find.byKey(const ValueKey('bili-favorites-search'));
    await tester.enterText(search, '音乐');
    await tester.pump();
    expect(client.requests, hasLength(1));
    expect(find.text('第一条收藏'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(client.requests.last.keyword, '音乐');
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byKey(const ValueKey('bili-favorites-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最多播放'));
    await tester.pumpAndSettle();
    expect(client.requests.last.order, BiliFavoriteOrder.mostPlayed);
    expect(client.requests.last.keyword, '音乐');
    expect(client.requests.last.page, 1);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(client.requests.last.keyword, isEmpty);
    expect(client.requests.last.order, BiliFavoriteOrder.mostPlayed);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pagination error preserves items and retries the same page', (
    tester,
  ) async {
    final client = _FavoritesClient();
    await _pumpPage(tester, client);
    client.loadItems = (_) async => throw const BiliApiException('网络暂不可用');
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('第一条收藏'), findsOneWidget);
    expect(find.text('加载更多失败：网络暂不可用'), findsOneWidget);

    client.loadItems = (request) async => _page(
      items: [_item(2, title: '第二条收藏')],
      page: request.page,
      hasMore: false,
    );
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(client.requests.map((request) => request.page), [1, 2, 2]);
    expect(find.text('第一条收藏'), findsOneWidget);
    expect(find.text('第二条收藏'), findsOneWidget);
    expect(find.text('重试加载'), findsNothing);
    expect(find.text('加载更多'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('login is required before loading and reloads after login', (
    tester,
  ) async {
    final client = _FavoritesClient()..authenticated = false;
    var loginCalls = 0;
    await _pumpPage(
      tester,
      client,
      onLogin: () async {
        loginCalls++;
        client.authenticated = true;
      },
    );
    expect(find.text('登录后查看收藏'), findsOneWidget);
    expect(client.folderRequests, 0);
    expect(client.requests, isEmpty);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(loginCalls, 1);
    expect(find.byKey(const ValueKey('favorite-folder-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-folder-1')));
    await tester.pumpAndSettle();
    expect(find.text('第一条收藏'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('first load error can retry and empty search is distinct', (
    tester,
  ) async {
    final client = _FavoritesClient()
      ..loadItems = (_) async => throw const BiliApiException('加载超时');
    await _pumpPage(tester, client);
    expect(find.text('加载失败：加载超时'), findsOneWidget);
    client.loadItems = (_) async => _page(items: [], hasMore: false);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('这个收藏夹还是空的。'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('bili-favorites-search')),
      '不存在',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的收藏内容。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'unavailable media is inert and a pending open cannot duplicate',
    (tester) async {
      final client = _FavoritesClient()
        ..loadItems = (_) async => _page(
          items: [
            _item(1, title: '失效收藏', available: false),
            _item(2, title: '可播放收藏'),
          ],
          hasMore: false,
        );
      await _pumpPage(tester, client);
      expect(find.text('视频已失效'), findsOneWidget);
      await tester.tap(find.text('失效收藏'));
      await tester.pump();
      expect(client.detailRequests, isEmpty);

      await tester.tap(find.text('可播放收藏'));
      await tester.pump();
      await tester.tap(find.text('可播放收藏'));
      await tester.pump();
      expect(client.detailRequests, ['BV2']);
      client.pendingDetail.completeError(const BiliApiException('视频已失效'));
      await tester.pumpAndSettle();
      expect(find.text('打开视频失败：视频已失效'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('narrow screen with keyboard, large text and contrast fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _FavoritesClient();
    await _pumpPage(
      tester,
      client,
      mediaQuery: const MediaQueryData(
        size: Size(320, 640),
        viewInsets: EdgeInsets.only(bottom: 260),
        padding: EdgeInsets.only(top: 24, bottom: 24),
        textScaler: TextScaler.linear(1.5),
        highContrast: true,
        disableAnimations: true,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('bili-favorites-search')),
      '一个很长的搜索关键词',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('removing one row confirms, drops the row and decrements count', (
    tester,
  ) async {
    final client = _FavoritesClient();
    await _pumpPage(tester, client);
    await tester.tap(find.byKey(const ValueKey('favorite-remove-2-1')));
    await tester.pumpAndSettle();
    expect(find.text('移出收藏夹？'), findsOneWidget);
    // 取消不提交。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(client.removals, isEmpty);
    expect(find.text('第一条收藏'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('favorite-remove-2-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    expect(client.removals.single.folderId, 1);
    expect(client.removals.single.resourceIds, ['1:2']);
    expect(find.text('第一条收藏'), findsNothing);
    expect(find.text('已移出 1 个内容'), findsOneWidget);
    await tester.tap(find.byTooltip('返回收藏夹'));
    await tester.pumpAndSettle();
    expect(find.text('2 个内容'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('removal failure keeps the row and the selection', (
    tester,
  ) async {
    final client = _FavoritesClient()
      ..removeError = const BiliApiException('风控校验失败');
    await _pumpPage(tester, client);
    await tester.longPress(find.text('第一条收藏'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);
    await tester.tap(find.text('第一条收藏'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('bili-favorites-remove-selected')),
    );
    await tester.pumpAndSettle();
    // AppBar 与确认弹窗各有一个「移出」，后者在树上更靠后。
    await tester.tap(find.text('移出').last);
    await tester.pumpAndSettle();
    expect(find.text('移出失败：风控校验失败'), findsOneWidget);
    expect(find.text('第一条收藏'), findsOneWidget);
    // 失败后仍在多选态，选择未丢失，可直接重试。
    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('multi-select allows zero items and back exits it first', (
    tester,
  ) async {
    final client = _FavoritesClient();
    await _pumpPage(tester, client);
    await tester.longPress(find.text('第一条收藏'));
    await tester.pumpAndSettle();
    // 进入多选即为「已选 0 项」，移出按钮禁用。
    expect(find.text('已选 0 项'), findsOneWidget);
    final removeButton = tester.widget<TextButton>(
      find.byKey(const ValueKey('bili-favorites-remove-selected')),
    );
    expect(removeButton.onPressed, isNull);

    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);

    // 返回键先退出多选，不弹出页面。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('默认收藏夹'), findsOneWidget);
    expect(find.text('已选 0 项'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-folder-1')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('creating a folder adds a card with its real count', (
    tester,
  ) async {
    final client = _FavoritesClient();
    await _pumpPage(tester, client, openFirstFolder: false);
    await tester.tap(
      find.byKey(const ValueKey('bili-favorites-create-folder')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bili-favorites-folder-title')),
      '  新收藏夹  ',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(client.createdTitles, ['新收藏夹']);
    expect(find.text('已创建收藏夹「新收藏夹」'), findsOneWidget);
    expect(find.text('新收藏夹'), findsOneWidget);
    expect(find.text('0 个内容'), findsOneWidget);
    expect(
      client.previewRequests.every((request) => request.folderId < 100),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reopening the page after playback refreshes the list', (
    tester,
  ) async {
    final client = _FavoritesClient()
      ..detailResult = Future<BiliVideoDetail>.value(_detail());
    var playbackOpened = 0;
    var itemTitle = '第一条收藏';
    await _pumpPage(
      tester,
      client,
      openPlayback: (detail) async {
        playbackOpened++;
        // 模拟在播放页取消收藏后返回。
        itemTitle = '服务端已移出';
      },
    );
    client.loadItems = (_) async =>
        _page(items: [_item(1, title: itemTitle)], hasMore: false);
    await tester.tap(find.text('第一条收藏'));
    await tester.pumpAndSettle();
    expect(playbackOpened, 1);
    expect(find.text('服务端已移出'), findsOneWidget);
    expect(client.requests, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('folder cards use the first video cover with one preview item', (
    tester,
  ) async {
    final client = _FavoritesClient()
      ..loadPreview = (request) async => _page(
        items: [
          _item(
            1,
            title: '首条视频',
            coverUrl: 'https://example.test/first-${request.folderId}.jpg',
          ),
        ],
      );
    await _pumpPage(tester, client, openFirstFolder: false);
    expect(client.requests, isEmpty);
    expect(client.previewRequests.map((request) => request.folderId), [1, 2]);
    for (final request in client.previewRequests) {
      expect(request.page, 1);
      expect(request.pageSize, 1);
      expect(request.keyword, isEmpty);
      expect(request.order, BiliFavoriteOrder.recent);
    }
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('favorite-folder-1')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (image.image as NetworkImage).url,
      'https://example.test/first-1.jpg',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed cover does not prevent opening a folder', (tester) async {
    final client = _FavoritesClient()
      ..loadPreview = (_) async => throw const BiliApiException('封面读取失败');
    await _pumpPage(tester, client, openFirstFolder: false);
    expect(find.byKey(const ValueKey('favorite-folder-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-folder-1')));
    await tester.pumpAndSettle();
    expect(find.text('第一条收藏'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late preview after refresh cannot replace the new cover', (
    tester,
  ) async {
    final pending = Completer<BiliFavoritePage>();
    final client = _FavoritesClient()..loadPreview = (_) => pending.future;
    await _pumpPage(tester, client, openFirstFolder: false);
    client.loadPreview = (_) async => _page(
      items: [_item(2, title: '新首条', coverUrl: 'https://example.test/new.jpg')],
    );
    await tester.tap(find.byTooltip('刷新收藏'));
    await tester.pumpAndSettle();
    pending.complete(
      _page(
        items: [
          _item(1, title: '旧首条', coverUrl: 'https://example.test/old.jpg'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      expect((image.image as NetworkImage).url, 'https://example.test/new.jpg');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FavoritesClient client, {
  Future<void> Function()? onLogin,
  Future<void> Function(BiliVideoDetail detail)? openPlayback,
  MediaQueryData? mediaQuery,
  bool openFirstFolder = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: mediaQuery == null
          ? null
          : (context, child) => MediaQuery(data: mediaQuery, child: child!),
      home: BiliFavoritesPage(
        client: client,
        onLoginTap: onLogin,
        openPlayback: openPlayback,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (openFirstFolder && client.authenticated) {
    await tester.tap(find.byKey(const ValueKey('favorite-folder-1')));
    await tester.pumpAndSettle();
  }
}

typedef _FavoriteRequest = ({
  int folderId,
  int page,
  int pageSize,
  String keyword,
  BiliFavoriteOrder order,
});

typedef _RemovalRequest = ({int folderId, List<String> resourceIds});

class _FavoritesClient extends BiliClient {
  bool authenticated = true;
  int folderRequests = 0;
  final requests = <_FavoriteRequest>[];
  final previewRequests = <_FavoriteRequest>[];
  final detailRequests = <String>[];
  final removals = <_RemovalRequest>[];
  final createdTitles = <String>[];
  final pendingDetail = Completer<BiliVideoDetail>();
  Future<BiliVideoDetail>? detailResult;
  Object? removeError;
  final removed = <int, Set<String>>{};
  Future<BiliFavoritePage> Function(_FavoriteRequest)? loadItems;
  Future<BiliFavoritePage> Function(_FavoriteRequest)? loadPreview;

  @override
  bool get hasAuthenticatedSession => authenticated;

  @override
  Future<List<BiliFavoriteFolder>> fetchFavoriteFolders() async {
    folderRequests++;
    return [
      BiliFavoriteFolder(
        id: 1,
        title: '默认收藏夹',
        containsCurrentVideo: false,
        mediaCount: 3 - (removed[1]?.length ?? 0),
        coverUrl: 'https://example.test/folder-cover.jpg',
      ),
      const BiliFavoriteFolder(id: 2, title: '学习', containsCurrentVideo: false),
      for (final title in createdTitles)
        BiliFavoriteFolder(
          id: 100 + createdTitles.indexOf(title),
          title: title,
          containsCurrentVideo: false,
          mediaCount: 0,
        ),
    ];
  }

  @override
  Future<BiliFavoritePage> fetchFavoriteItems({
    required int folderId,
    int page = 1,
    int pageSize = 20,
    String keyword = '',
    BiliFavoriteOrder order = BiliFavoriteOrder.recent,
  }) async {
    final request = (
      folderId: folderId,
      page: page,
      pageSize: pageSize,
      keyword: keyword,
      order: order,
    );
    if (pageSize == 1) {
      previewRequests.add(request);
      return loadPreview?.call(request) ??
          _page(items: [_item(1, title: '封面视频')]);
    }
    requests.add(request);
    return loadItems?.call(request) ??
        _page(
          items: [
            if (removed[folderId]?.contains('1:2') != true)
              _item(1, title: '第一条收藏'),
          ],
        );
  }

  @override
  Future<void> removeFavoriteItems({
    required int folderId,
    required List<String> resourceIds,
  }) async {
    removals.add((folderId: folderId, resourceIds: resourceIds));
    final error = removeError;
    if (error != null) throw error;
    (removed[folderId] ??= {}).addAll(resourceIds);
  }

  @override
  Future<int> createFavoriteFolder({
    required String title,
    required bool isPrivate,
  }) async {
    createdTitles.add(title);
    return 100 + createdTitles.length;
  }

  @override
  Future<BiliVideoDetail> fetchVideoDetail(String bvid) {
    detailRequests.add(bvid);
    return detailResult ?? pendingDetail.future;
  }
}

BiliFavoritePage _page({
  required List<BiliFavoriteItem> items,
  int page = 1,
  bool hasMore = true,
}) =>
    BiliFavoritePage(items: items, page: page, pageSize: 20, hasMore: hasMore);

BiliFavoriteItem _item(
  int id, {
  required String title,
  bool available = true,
  String coverUrl = '',
}) => BiliFavoriteItem(
  id: id,
  bvid: 'BV$id',
  title: title,
  coverUrl: coverUrl,
  ownerName: 'UP 主',
  durationLabel: '12:34',
  playCountLabel: '1.2万',
  favoritedAtLabel: '09-16',
  isAvailable: available,
);

BiliVideoDetail _detail() => const BiliVideoDetail(
  aid: 1,
  bvid: 'BV1',
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
