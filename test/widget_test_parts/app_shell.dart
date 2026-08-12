part of '../widget_test.dart';

void _registerAppShellWidgetTests() {
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
}
