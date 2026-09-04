part of '../widget_test.dart';

void _registerAppShellWidgetTests() {
  testWidgets('renders bilibili product shell', (WidgetTester tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const PlatformApp());
    await tester.pump();

    expect(find.byType(GlassSearchBar), findsNothing);
    expect(find.byType(GlassTabBar), findsOneWidget);
    expect(
      find.byKey(AppGlassBottomNavigation.searchButtonKey),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(AppGlassBottomNavigation.searchButtonKey))
          .shortestSide,
      greaterThanOrEqualTo(AppVisualTokens.minimumTapTarget),
    );
    final searchSemantics = tester.getSemantics(
      find.byKey(AppGlassBottomNavigation.searchButtonKey),
    );
    expect(searchSemantics.attributedLabel.string, '搜索');
    expect(searchSemantics.rect.shortestSide, greaterThanOrEqualTo(44));
    expect(
      searchSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(find.text('首页'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('bili-home-region-button')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('bili-home-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bili-home-avatar-button')),
      findsOneWidget,
    );
    final titleRect = tester.getRect(
      find.byKey(const ValueKey<String>('bili-home-title')),
    );
    final viewportWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(titleRect.center.dx, closeTo(viewportWidth / 2, 0.5));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('bili-home-region-button')),
          )
          .shortestSide,
      greaterThanOrEqualTo(AppVisualTokens.minimumTapTarget),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('bili-home-avatar-button')),
          )
          .shortestSide,
      greaterThanOrEqualTo(AppVisualTokens.minimumTapTarget),
    );
    final bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    expect(bottomBar.barHeight, AppGlassBottomNavigation.compactBarHeight);
    expect(bottomBar.searchBarHeight, AppGlassBottomNavigation.barHeight);
    expect(bottomBar.tabWidth, AppGlassBottomNavigation.tabItemWidth);
    semantics.dispose();
  });

  testWidgets(
    'mobile search expands before focus and swaps content on submit',
    (WidgetTester tester) async {
      final client = await _pumpMobileHub(
        tester,
        surfaceSize: const Size(320, 720),
        searchResults: const <BiliSearchResult>[
          BiliSearchResult(
            aid: 9001,
            bvid: 'BVSEARCH0001',
            title: '搜索命中视频',
            author: '搜索测试 UP',
            coverUrl: '',
            durationLabel: '04:12',
            playCountLabel: '2万',
            danmakuCountLabel: '20',
          ),
        ],
      );

      expect(find.text('推荐视频 0'), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);

      await tester.tap(find.byKey(AppGlassBottomNavigation.searchButtonKey));
      await _pumpBottomBarMorph(tester);

      var bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(bottomBar.isSearchActive, isTrue);
      expect(find.byType(EditableText), findsOneWidget);
      var searchField = tester.widget<EditableText>(find.byType(EditableText));
      expect(searchField.focusNode.hasFocus, isFalse);

      await tester.tap(find.byType(EditableText));
      await tester.pump();
      searchField = tester.widget<EditableText>(find.byType(EditableText));
      expect(searchField.focusNode.hasFocus, isTrue);

      await tester.enterText(find.byType(EditableText), 'flutter');
      final tabBarStateBeforeKeyboard = tester.state(find.byType(GlassTabBar));
      final fieldWidthBeforeKeyboard = tester
          .getSize(find.byType(EditableText))
          .width;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('推荐视频 0'), findsOneWidget);
      expect(find.text('搜索命中视频'), findsNothing);
      expect(
        tester.state(find.byType(GlassTabBar)),
        same(tabBarStateBeforeKeyboard),
      );
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(BiliHubPage)),
        ).bottom,
        greaterThan(0),
      );
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(GlassTabBar)),
        ).bottom,
        0,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(
        find.byKey(AppGlassBottomNavigation.searchDismissButtonKey),
        findsOneWidget,
      );
      final keyboardTop =
          tester.view.physicalSize.height / tester.view.devicePixelRatio -
          tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      final dismissRect = tester.getRect(
        find.byKey(AppGlassBottomNavigation.searchDismissButtonKey),
      );
      final exitRect = tester.getRect(
        find.byKey(AppGlassBottomNavigation.searchExitButtonKey),
      );
      final focusedFieldRect = tester.getRect(find.byType(EditableText));
      expect(focusedFieldRect.width, lessThan(fieldWidthBeforeKeyboard));
      expect(focusedFieldRect.left, greaterThan(exitRect.right));
      expect(
        dismissRect.size.shortestSide,
        greaterThanOrEqualTo(AppVisualTokens.minimumTapTarget),
      );
      expect(keyboardTop - dismissRect.bottom, inInclusiveRange(8.0, 12.0));

      await tester.tap(
        find.byKey(AppGlassBottomNavigation.searchDismissButtonKey),
      );
      await tester.pump();
      tester.view.resetViewInsets();
      await tester.pump(const Duration(milliseconds: 400));

      bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      searchField = tester.widget<EditableText>(find.byType(EditableText));
      expect(bottomBar.isSearchActive, isTrue);
      expect(searchField.focusNode.hasFocus, isFalse);
      expect(searchField.controller.text, 'flutter');

      await tester.tap(
        find.byKey(AppGlassBottomNavigation.searchClearButtonKey),
      );
      await tester.pump();
      searchField = tester.widget<EditableText>(find.byType(EditableText));
      expect(searchField.controller.text, isEmpty);
      expect(find.text('推荐视频 0'), findsOneWidget);

      final pendingSearch = Completer<List<BiliSearchResult>>();
      client.searchCompleter = pendingSearch;
      await tester.enterText(find.byType(EditableText), 'flutter');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(GlassTabBar),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text('没有搜到内容'), findsNothing);

      pendingSearch.complete(client.searchResults);
      await _flushRealAsync(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.requestedSearchKeywords, <String>['flutter']);
      expect(find.text('搜索命中视频'), findsOneWidget);
      expect(find.text('推荐视频 0'), findsNothing);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );

      await tester.tap(
        find.byKey(AppGlassBottomNavigation.searchExitButtonKey),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(bottomBar.isSearchActive, isFalse);
      expect(find.text('搜索命中视频'), findsNothing);
      expect(find.text('推荐视频 0'), findsOneWidget);
    },
  );

  testWidgets('mobile back dismisses keyboard before clearing search', (
    WidgetTester tester,
  ) async {
    await _pumpMobileHub(tester);

    await tester.tap(find.byKey(AppGlassBottomNavigation.searchButtonKey));
    await _pumpBottomBarMorph(tester);
    await tester.tap(find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), '保留的草稿');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    var bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    var searchField = tester.widget<EditableText>(find.byType(EditableText));
    expect(bottomBar.isSearchActive, isTrue);
    expect(searchField.focusNode.hasFocus, isFalse);
    expect(searchField.controller.text, '保留的草稿');

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    expect(bottomBar.isSearchActive, isFalse);
    expect(find.byType(EditableText), findsNothing);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isTrue,
    );

    await tester.tap(find.byKey(AppGlassBottomNavigation.searchButtonKey));
    await _pumpBottomBarMorph(tester);
    searchField = tester.widget<EditableText>(find.byType(EditableText));
    expect(searchField.controller.text, isEmpty);
  });

  testWidgets('search from mine returns home before expanding', (
    WidgetTester tester,
  ) async {
    await _pumpMobileHub(tester);

    await tester.tapAt(tester.getCenter(find.text('我的').last));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey<String>('bili-mine-profile-header')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AppGlassBottomNavigation.searchButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    expect(bottomBar.selectedIndex, 0);
    expect(bottomBar.isSearchActive, isTrue);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('bili-mine-profile-header')),
      findsNothing,
    );
  });

  testWidgets(
    'home and mine independently minimize and retain scroll offsets',
    (WidgetTester tester) async {
      await _pumpMobileHub(
        tester,
        surfaceSize: const Size(390, 400),
        feedItems: _tvFeedItems(40),
      );

      final homeList = find.byType(CustomScrollView);
      await tester.drag(homeList, const Offset(0, -140));
      await tester.pump(const Duration(milliseconds: 250));

      var bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(bottomBar.minimizeController!.minimized, isTrue);
      await tester.drag(homeList, const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 250));
      bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(bottomBar.minimizeController!.minimized, isFalse);

      final homeOffset = tester
          .widget<CustomScrollView>(homeList)
          .controller!
          .offset;
      expect(homeOffset, greaterThan(0));

      await tester.tapAt(tester.getCenter(find.text('我的').last));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      final mineList = find.byType(ListView);
      final mineController = tester.widget<ListView>(mineList).controller!;
      expect(mineController.offset, 0);
      expect(mineController.position.maxScrollExtent, greaterThan(40));
      expect(
        tester
            .widget<GlassTabBar>(find.byType(GlassTabBar))
            .minimizeController!
            .minimized,
        isFalse,
      );

      await tester.drag(mineList, const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 250));
      bottomBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(bottomBar.minimizeController!.minimized, isTrue);
      await tester.drag(mineList, const Offset(0, 36));
      await tester.pump(const Duration(milliseconds: 250));
      expect(bottomBar.minimizeController!.minimized, isFalse);

      final mineOffset = mineController.offset;
      expect(mineOffset, greaterThan(0));

      await tester.tapAt(tester.getCenter(find.text('首页').last));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(
        tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!
            .offset,
        moreOrLessEquals(homeOffset, epsilon: 1),
      );

      await tester.tapAt(tester.getCenter(find.text('我的').last));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        moreOrLessEquals(mineOffset, epsilon: 1),
      );
    },
  );

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
    expect(topClearance.height, 44 + 48);
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
}

Future<_FakeTvHomeClient> _pumpMobileHub(
  WidgetTester tester, {
  Size surfaceSize = const Size(390, 844),
  List<BiliFeedVideo>? feedItems,
  List<BiliSearchResult> searchResults = const <BiliSearchResult>[],
}) async {
  final root = Directory(
    '${Directory.systemTemp.path}/bili-mobile-hub-widget-test-${DateTime.now().microsecondsSinceEpoch}',
  );
  final client = _FakeTvHomeClient(
    feedItems: feedItems,
    searchResults: searchResults,
  );

  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = surfaceSize;
  addTearDown(() {
    tester.view
      ..resetDevicePixelRatio()
      ..resetPhysicalSize();
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
  });
  addTearDown(tester.view.resetViewInsets);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppVisualTokens.mobileLightTheme(),
      home: BiliHubPage(
        client: client,
        historyStore: BiliHistoryStore(
          baseDirectory: Directory('${root.path}/history'),
        ),
        sessionStore: BiliSessionStore(
          baseDirectory: Directory('${root.path}/session'),
        ),
        offlineController: _FakeOfflineController(
          const <BiliOfflineDownloadEntry>[],
        ),
      ),
    ),
  );
  await tester.pump();
  await _flushRealAsync(tester);
  await tester.pump(const Duration(milliseconds: 300));
  if (client.feedItems.isNotEmpty) {
    await _pumpUntilFound(
      tester,
      find.byKey(ValueKey<String>('${client.feedItems.first.bvid}-0')),
    );
  }
  return client;
}

Future<void> _pumpBottomBarMorph(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}
