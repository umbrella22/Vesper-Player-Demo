part of '../widget_test.dart';

void _registerRegionAndCacheWidgetTests() {
  testWidgets('region card menus line up with their covers and subtitles', (
    tester,
  ) async {
    const items = [
      BiliRegionVideo(
        id: '1',
        title: '春',
        subtitle: '甲',
        coverUrl: '',
        url: '',
      ),
      BiliRegionVideo(
        id: '2',
        title: '一段在手机分区卡片上需要省略的长标题',
        subtitle: '一个很长的作者名称',
        coverUrl: '',
        url: '',
      ),
    ];
    final client = _FakeRegionClient()..pageItems[1] = items;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final (scale, theme, surface) in [
      (1.0, AppVisualTokens.mobileLightTheme(), Colors.white),
      (1.5, AppVisualTokens.mobileDarkTheme(), AppVisualTheme.dark.surface),
    ]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: BiliRegionVideoPage(
            section: _testRegionSection,
            client: client,
          ),
        ),
      );
      await tester.pump();

      final covers = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(AspectRatio),
      );
      for (final (index, item) in items.indexed) {
        final cover = tester.getRect(covers.at(index));
        final menu = find.byTooltip('缓存').at(index);
        final target = tester.getRect(menu);
        final title = tester.getRect(find.text(item.title));
        final subtitle = tester.getRect(find.text(item.subtitle!));
        expect(target.right, closeTo(cover.right, 0.01), reason: item.title);
        final card = find
            .ancestor(of: covers.at(index), matching: find.byType(Material))
            .first;
        expect(tester.widget<Material>(card).color, surface);
        expect(
          tester.getRect(card).bottom,
          greaterThanOrEqualTo(subtitle.bottom),
        );
        expect(title.left - cover.left, closeTo(8, 0.01));
        expect(cover.right - title.right, closeTo(8, 0.01));
        expect(target.overlaps(title), isFalse);
        expect(subtitle.right, lessThanOrEqualTo(target.left + 0.01));
        expect(subtitle.top - title.bottom, lessThan(subtitle.height));
        final dots = find.descendant(
          of: menu,
          matching: find.byIcon(AppIcons.moreFill),
        );
        expect(tester.getCenter(dots).dy, closeTo(subtitle.center.dy, 1));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'phone region cards retain cache targets and section artwork ratios',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final (section, ratio) in [
        (_testRegionSection, 16 / 9),
        (const BiliRegionSection(id: 'pgc', name: '番剧', icon: 'P'), 150 / 210),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: BiliRegionVideoPage(
              key: ValueKey(section.id),
              section: section,
              client: _FakeRegionClient(),
              offlineController: _FakeCacheController(
                options: _testDownloadOptions(_testDetail()),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.getSize(find.byTooltip('缓存').first), const Size(48, 48));
        final cover = find
            .descendant(
              of: find.byType(GridView),
              matching: find.byWidgetPredicate(
                (w) => w is AspectRatio && w.aspectRatio == ratio,
              ),
            )
            .first;
        final size = tester.getSize(cover);
        expect(size.width / size.height, closeTo(ratio, 0.035));
        final target = find.byTooltip('缓存').first;
        await tester.tapAt(tester.getTopLeft(target) + const Offset(4, 4));
        await _pumpUntilFound(tester, find.byType(BiliCacheDownloadPanel));
        expect(find.byType(BiliCacheDownloadPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(BiliCacheDownloadPanel))).pop();
        await tester.pumpAndSettle();
      }
    },
  );

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

  testWidgets('landscape region cache drawer uses an opaque readable surface', (
    WidgetTester tester,
  ) async {
    final client = _FakeRegionClient();
    final detail = _testDetail();
    final controller = _FakeCacheController(
      options: _testDownloadOptions(detail),
    );

    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.mobileLightTheme(),
        home: BiliRegionVideoPage(
          section: _testRegionSection,
          client: client,
          historyStore: const BiliHistoryStore(),
          offlineController: controller,
        ),
      ),
    );
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('缓存').first);
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    final drawer = find.byKey(
      const ValueKey<String>('media-readable-region-cache-drawer'),
    );
    expect(drawer, findsOneWidget);
    expect(
      tester.widget<Material>(drawer).color,
      AppVisualTheme.light.opaqueGlassFallback,
    );
    expect(find.text('下载缓存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text fits the directory and keeps poster labels apart', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final client = _FakeRegionClient()
      ..pageItems[1] = const [
        BiliRegionVideo(
          id: 'poster',
          title: '海报',
          coverUrl: '',
          url: '',
          seasonId: 1,
          scoreLabel: '9.8',
          followCountLabel: '1321.5万追番',
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(home: BiliRegionHubPage(client: client)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('番剧'));
    await tester.pumpAndSettle();
    final cover = tester.getRect(find.byType(AspectRatio).first);
    final badge = tester.getRect(find.text('9.8'));
    final audience = tester.getRect(find.text('1321.5万追番'));
    expect(badge.right, lessThan(audience.left));
    expect(audience.right, lessThanOrEqualTo(cover.right));
    expect(tester.takeException(), isNull);
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

  testWidgets('cache download panel keeps readable colors in dark mode', (
    WidgetTester tester,
  ) async {
    final detail = _testDetail();
    final controller = _FakeCacheController(
      options: _testDownloadOptions(detail),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.mobileDarkTheme(),
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
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('下载缓存')).style?.color,
      AppVisualTheme.dark.textPrimary,
    );
    expect(
      tester.widget<Text>(find.text('选择清晰度后，点击合集中的分P开始缓存。')).style?.color,
      AppVisualTheme.dark.textSecondary,
    );
    expect(
      tester.widget<Text>(find.text('正片')).style?.color,
      AppVisualTheme.dark.textPrimary,
    );
    expect(
      tester.widget<Text>(find.text('720P')).style?.color,
      AppVisualTheme.dark.textPrimary,
    );
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
        matching: find.byIcon(AppIcons.downloadLine),
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

  testWidgets(
    'cache download panel shows per-episode cache status and handles P100 at 1.5x text scale',
    (WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final pages = <BiliVideoPageEntry>[
        const BiliVideoPageEntry(
          cid: 11,
          pageNumber: 1,
          title: '第一集',
          durationSeconds: 120,
        ),
        const BiliVideoPageEntry(
          cid: 12,
          pageNumber: 2,
          title: '第二集',
          durationSeconds: 120,
        ),
        const BiliVideoPageEntry(
          cid: 13,
          pageNumber: 3,
          title: '第三集',
          durationSeconds: 120,
        ),
        const BiliVideoPageEntry(
          cid: 14,
          pageNumber: 100,
          title: '第一百集',
          durationSeconds: 120,
        ),
      ];
      final detail = BiliVideoDetail(
        aid: 1,
        bvid: 'BV1xx411c7mD',
        title: '合集视频',
        ownerMid: 2,
        ownerName: 'UP',
        ownerAvatarUrl: '',
        coverUrl: '',
        description: '',
        publishedAtLabel: null,
        playCountLabel: '',
        danmakuCountLabel: '',
        replyCountLabel: '',
        likeCountLabel: '',
        coinCountLabel: '',
        favoriteCountLabel: '',
        shareCountLabel: '',
        pages: pages,
      );
      final controller = _FakeCacheController(
        options: _testDownloadOptions(detail),
        fakeEntries: [
          BiliOfflineDownloadEntry(
            metadata: const BiliOfflineDownloadMetadata(
              assetId: 'bili-BV1xx411c7mD-11-q64-avc-aac',
              taskId: 11,
              bvid: 'BV1xx411c7mD',
              cid: 11,
              videoTitle: '合集视频',
              pageTitle: 'P1 · 第一集',
              coverUrl: '',
              qualityLabel: '720P',
              createdAtMs: 100,
              outputPath: '/tmp/p1.mp4',
            ),
          ),
          BiliOfflineDownloadEntry(
            metadata: const BiliOfflineDownloadMetadata(
              assetId: 'bili-BV1xx411c7mD-12-q80-avc-aac',
              taskId: 12,
              bvid: 'BV1xx411c7mD',
              cid: 12,
              videoTitle: '合集视频',
              pageTitle: 'P2 · 第二集',
              coverUrl: '',
              qualityLabel: '1080P',
              createdAtMs: 101,
            ),
            task: const VesperDownloadTaskSnapshot(
              taskId: 12,
              assetId: 'bili-BV1xx411c7mD-12-q80-avc-aac',
              source: VesperDownloadSource(
                source: VesperPlayerSource(
                  uri: 'vesper-generated://dash/manifest.mpd',
                  label: '第二集',
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
                receivedBytes: 50,
                totalBytes: 100,
              ),
              assetIndex: VesperDownloadAssetIndex(
                contentFormat: VesperDownloadContentFormat.dashSegments,
              ),
            ),
          ),
          BiliOfflineDownloadEntry(
            metadata: const BiliOfflineDownloadMetadata(
              assetId: 'bili-BV1xx411c7mD-13-q80-avc-aac',
              taskId: 13,
              bvid: 'BV1xx411c7mD',
              cid: 13,
              videoTitle: '合集视频',
              pageTitle: 'P3 · 第三集',
              coverUrl: '',
              qualityLabel: '1080P',
              createdAtMs: 102,
            ),
            task: const VesperDownloadTaskSnapshot(
              taskId: 13,
              assetId: 'bili-BV1xx411c7mD-13-q80-avc-aac',
              source: VesperDownloadSource(
                source: VesperPlayerSource(
                  uri: 'vesper-generated://dash/manifest.mpd',
                  label: '第三集',
                  kind: VesperPlayerSourceKind.local,
                  protocol: VesperPlayerSourceProtocol.dash,
                ),
                contentFormat: VesperDownloadContentFormat.dashSegments,
              ),
              profile: VesperDownloadProfile(
                targetOutputFormat: VesperDownloadOutputFormat.mp4,
              ),
              state: VesperDownloadState.paused,
              progress: VesperDownloadProgressSnapshot(
                receivedBytes: 25,
                totalBytes: 100,
              ),
              assetIndex: VesperDownloadAssetIndex(
                contentFormat: VesperDownloadContentFormat.dashSegments,
              ),
            ),
          ),
          BiliOfflineDownloadEntry(
            metadata: const BiliOfflineDownloadMetadata(
              assetId: 'bili-BV1xx411c7mD-14-q80-avc-aac',
              taskId: 14,
              bvid: 'BV1xx411c7mD',
              cid: 14,
              videoTitle: '合集视频',
              pageTitle: 'P100 · 第一百集',
              coverUrl: '',
              qualityLabel: '1080P',
              createdAtMs: 103,
              errorMessage: '网络超时',
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: BiliCacheDownloadPanel(
                  detail: detail,
                  currentPage: pages.first,
                  selectedQualityId: 80,
                  codecPreference: BiliVideoCodecPreference.automatic,
                  controller: controller,
                  onMessage: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已缓存 720P'), findsOneWidget);
      expect(find.text('缓存中'), findsOneWidget);
      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('缓存失败'), findsOneWidget);
      expect(find.text('P100'), findsOneWidget);
      expect(find.byIcon(AppIcons.download2Line), findsOneWidget);
      expect(find.byIcon(AppIcons.playFill), findsOneWidget);
      expect(find.byIcon(AppIcons.refreshLine), findsOneWidget);
      expect(find.byIcon(AppIcons.checkboxCircleFill), findsNothing);

      await tester.tap(find.text('720P'));
      await tester.pump();
      expect(find.text('已缓存'), findsOneWidget);
      expect(find.byIcon(AppIcons.checkboxCircleFill), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cache download sheet pins heading and view cache button over long episode list',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pages = <BiliVideoPageEntry>[
        for (var i = 1; i <= 25; i += 1)
          BiliVideoPageEntry(
            cid: 100 + i,
            pageNumber: i,
            title: '第 $i 集长列表测试',
            durationSeconds: 180,
          ),
      ];
      final detail = BiliVideoDetail(
        aid: 202,
        bvid: 'BV1longcache',
        title: '长合集缓存测试',
        ownerMid: 1,
        ownerName: 'UP',
        ownerAvatarUrl: '',
        coverUrl: '',
        description: '',
        publishedAtLabel: '2026-05-12',
        playCountLabel: '1万',
        danmakuCountLabel: '10',
        replyCountLabel: '1',
        likeCountLabel: '2',
        coinCountLabel: '3',
        favoriteCountLabel: '4',
        shareCountLabel: '5',
        pages: pages,
      );
      final controller = _FakeCacheController(
        options: _testDownloadOptions(detail),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppVisualTokens.mobileLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => unawaited(
                  showMediaGlassSheet<void>(
                    context: context,
                    appearance: MediaGlassSheetAppearance.readable,
                    contentHandlesScrolling: true,
                    contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                    builder: (_) => BiliCacheDownloadPanel(
                      detail: detail,
                      currentPage: pages.first,
                      selectedQualityId: null,
                      codecPreference: BiliVideoCodecPreference.automatic,
                      controller: controller,
                      onMessage: (_) {},
                    ),
                  ),
                ),
                child: const Text('打开缓存面板'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开缓存面板'));
      await tester.pumpAndSettle();

      final headingRect = tester.getRect(find.text('下载缓存'));
      final ctaRect = tester.getRect(find.widgetWithText(FilledButton, '查看缓存'));
      expect(headingRect.top, greaterThanOrEqualTo(0));
      expect(ctaRect.bottom, lessThanOrEqualTo(844));
      expect(tester.takeException(), isNull);
    },
  );
}
