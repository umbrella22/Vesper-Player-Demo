part of '../widget_test.dart';

void _registerRegionAndCacheWidgetTests() {
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
