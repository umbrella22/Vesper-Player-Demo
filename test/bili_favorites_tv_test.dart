import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_favorites_page.dart';
import 'package:vesper_media/bili/common/models/bili_favorites_models.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';

void main() {
  testWidgets('an account without folders can create one with the remote', (
    tester,
  ) async {
    final client = _TvFavoritesClient()..emptyFolders = true;
    await _pumpTvFavorites(tester, client);
    expect(
      find.byKey(const ValueKey('bili-tv-favorites-rail-create')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bili-favorites-folder-title')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('bili-favorites-folder-title')),
      '首个收藏夹',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(client.createdTitle, '首个收藏夹');
    expect(find.text('首个收藏夹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rail lists real folders with counts and selects on tap', (
    tester,
  ) async {
    final client = _TvFavoritesClient();
    await _pumpTvFavorites(tester, client);

    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('默认收藏夹'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);
    // 计数缺失的收藏夹不显示数字。
    expect(find.text('3'), findsOneWidget);
    expect(find.text('收藏视频 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bili-tv-favorites-folder-2')));
    await tester.pumpAndSettle();
    expect(client.requests.last.folderId, 2);
    expect(find.text('收藏视频 2'), findsOneWidget);
  });

  testWidgets('manage mode allows zero selection then batch removal', (
    tester,
  ) async {
    final client = _TvFavoritesClient();
    await _pumpTvFavorites(tester, client);

    await tester.tap(find.byKey(const ValueKey('bili-tv-favorites-manage')));
    await tester.pumpAndSettle();
    // 遥控器没有长按，进入管理即为「已选 0 项」。
    expect(find.text('已选 0 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bili-tv-favorite-card-1:2')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bili-tv-favorites-remove')));
    await tester.pumpAndSettle();
    // 顶栏与确认弹窗各有一个「移出」，后者在树上更靠后。
    await tester.tap(find.text('移出').last);
    await tester.pumpAndSettle();
    expect(client.removals.single.resourceIds, ['1:2']);
    expect(find.text('收藏视频 1'), findsNothing);
  });

  testWidgets('removal failure keeps rows and selection for retry', (
    tester,
  ) async {
    final client = _TvFavoritesClient()
      ..removeError = const BiliApiException('风控校验失败');
    await _pumpTvFavorites(tester, client);
    await tester.tap(find.byKey(const ValueKey('bili-tv-favorites-manage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bili-tv-favorite-card-1:2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bili-tv-favorites-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出').last);
    await tester.pumpAndSettle();

    expect(find.text('移出失败：风控校验失败'), findsOneWidget);
    expect(find.text('收藏视频 1'), findsOneWidget);
    expect(find.text('已选 1 项'), findsOneWidget);
  });

  testWidgets('back exits manage mode before leaving the page', (tester) async {
    final client = _TvFavoritesClient();
    await _pumpTvFavorites(tester, client);
    await tester.tap(find.byKey(const ValueKey('bili-tv-favorites-manage')));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsNothing);
    expect(find.text('收藏内容'), findsOneWidget);
  });

  testWidgets('logging out turns the rail into a login prompt', (tester) async {
    final client = _TvFavoritesClient()..authenticated = false;
    await _pumpTvFavorites(tester, client);
    expect(find.text('登录后查看收藏'), findsOneWidget);
    expect(client.requests, isEmpty);
    // 焦点抬升层会再渲染一份 builder，因此按「至少一个」断言。
    expect(find.text('登录'), findsWidgets);
  });

  testWidgets('empty folder and load more states stay actionable', (
    tester,
  ) async {
    final client = _TvFavoritesClient()
      ..loadItems = (_) async => const BiliFavoritePage(
        items: [],
        page: 1,
        pageSize: 20,
        hasMore: false,
      );
    await _pumpTvFavorites(tester, client);
    expect(find.text('这个收藏夹还是空的。'), findsOneWidget);

    client.loadItems = (request) async => BiliFavoritePage(
      items: [_item(request.folderId)],
      page: request.page,
      pageSize: 20,
      hasMore: request.page == 1,
    );
    await tester.tap(find.byKey(const ValueKey('bili-tv-favorites-refresh')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bili-tv-favorites-load-more')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpTvFavorites(
  WidgetTester tester,
  _TvFavoritesClient client,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppVisualTokens.tvTheme(),
      home: Scaffold(
        body: BiliFavoritesTvView(client: client, onLoginTap: () async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

typedef _TvFavoriteRequest = ({
  int folderId,
  int page,
  String keyword,
  BiliFavoriteOrder order,
});

class _TvFavoritesClient extends BiliClient {
  bool authenticated = true;
  final requests = <_TvFavoriteRequest>[];
  final removals = <({int folderId, List<String> resourceIds})>[];
  Object? removeError;
  final removed = <int, Set<String>>{};
  bool emptyFolders = false;
  String? createdTitle;
  Future<BiliFavoritePage> Function(_TvFavoriteRequest)? loadItems;

  @override
  bool get hasAuthenticatedSession => authenticated;

  @override
  Future<List<BiliFavoriteFolder>> fetchFavoriteFolders() async {
    if (emptyFolders) return [];
    if (createdTitle case final title?) {
      return [
        BiliFavoriteFolder(
          id: 1,
          title: title,
          containsCurrentVideo: false,
          mediaCount: 0,
        ),
      ];
    }
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
  Future<int> createFavoriteFolder({
    required String title,
    required bool isPrivate,
  }) async {
    createdTitle = title;
    emptyFolders = false;
    return 1;
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
    return loadItems?.call(request) ??
        BiliFavoritePage(
          items: [
            if (removed[folderId]?.contains('$folderId:2') != true)
              _item(folderId),
          ],
          page: page,
          pageSize: pageSize,
          hasMore: false,
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
}

BiliFavoriteItem _item(int folderId) => BiliFavoriteItem(
  id: folderId,
  bvid: 'BV$folderId',
  title: '收藏视频 $folderId',
  coverUrl: '',
  ownerName: 'UP 主',
  durationLabel: '12:34',
  playCountLabel: '1.2万',
  favoritedAtLabel: '09-16',
  isAvailable: true,
);
