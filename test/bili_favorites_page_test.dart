import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_favorites_page.dart';
import 'package:vesper_media/bili/common/models/bili_favorites_models.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';

void main() {
  testWidgets(
    'only real folders appear and selecting clears previous content',
    (tester) async {
      final client = _FavoritesClient();
      await _pumpPage(tester, client);
      expect(find.text('默认收藏夹 3'), findsWidgets);
      expect(find.text('学习'), findsWidgets);
      expect(find.text('全部'), findsNothing);
      expect(find.text('学习 0'), findsNothing);
      expect(find.text('第一条收藏'), findsOneWidget);

      final pending = Completer<BiliFavoritePage>();
      client.loadItems = (_) => pending.future;
      await tester.tap(find.text('学习').first);
      await tester.pump();
      expect(find.text('第一条收藏'), findsNothing);
      expect(client.requests.last.folderId, 2);
      pending.complete(_page(items: [_item(2, title: '学习收藏')]));
      await tester.pumpAndSettle();
      expect(find.text('学习收藏'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FavoritesClient client, {
  Future<void> Function()? onLogin,
  MediaQueryData? mediaQuery,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: mediaQuery == null
          ? null
          : (context, child) => MediaQuery(data: mediaQuery, child: child!),
      home: BiliFavoritesPage(client: client, onLoginTap: onLogin),
    ),
  );
  await tester.pumpAndSettle();
}

typedef _FavoriteRequest = ({
  int folderId,
  int page,
  String keyword,
  BiliFavoriteOrder order,
});

class _FavoritesClient extends BiliClient {
  bool authenticated = true;
  int folderRequests = 0;
  final requests = <_FavoriteRequest>[];
  final detailRequests = <String>[];
  final pendingDetail = Completer<BiliVideoDetail>();
  Future<BiliFavoritePage> Function(_FavoriteRequest)? loadItems;

  @override
  bool get hasAuthenticatedSession => authenticated;

  @override
  Future<List<BiliFavoriteFolder>> fetchFavoriteFolders() async {
    folderRequests++;
    return const [
      BiliFavoriteFolder(
        id: 1,
        title: '默认收藏夹',
        containsCurrentVideo: false,
        mediaCount: 3,
      ),
      BiliFavoriteFolder(id: 2, title: '学习', containsCurrentVideo: false),
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
      keyword: keyword,
      order: order,
    );
    requests.add(request);
    return loadItems?.call(request) ?? _page(items: [_item(1, title: '第一条收藏')]);
  }

  @override
  Future<BiliVideoDetail> fetchVideoDetail(String bvid) {
    detailRequests.add(bvid);
    return pendingDetail.future;
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
}) => BiliFavoriteItem(
  id: id,
  bvid: 'BV$id',
  title: title,
  coverUrl: '',
  ownerName: 'UP 主',
  durationLabel: '12:34',
  playCountLabel: '1.2万',
  favoritedAtLabel: '09-16',
  isAvailable: available,
);
