part of '../widget_test.dart';

void _registerSettingsWidgetTests() {
  testWidgets('app settings reads and toggles force TV mode', (
    WidgetTester tester,
  ) async {
    final root = Directory(
      '${Directory.systemTemp.path}/bili-settings-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    final settings = AppSettingsStore(baseDirectory: root);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    await tester.runAsync(() => settings.setForceTvMode(false));
    final themeController = AppThemeController(settings: settings);
    final client = _FakeTvHomeClient();
    final historyStore = BiliHistoryStore(
      baseDirectory: Directory('${root.path}/history'),
    );
    final sessionStore = BiliSessionStore(baseDirectory: root);
    final offlineController = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[],
    );
    addTearDown(themeController.dispose);
    await tester.pumpWidget(
      AppThemeScope(
        controller: themeController,
        child: MaterialApp(
          theme: AppVisualTokens.mobileLightTheme(),
          home: BiliSettingsPage(
            appSettings: settings,
            client: client,
            historyStore: historyStore,
            sessionStore: sessionStore,
            offlineController: offlineController,
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('根据设备自动选择界面'));

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('根据设备自动选择界面'), findsOneWidget);
    expect(find.text('返回首页并切换'), findsNothing);

    await tester.tap(find.text('强制 TV 模式'));
    await _pumpUntilFound(tester, find.text('返回首页后切换为 TV 界面'));

    expect(find.text('返回首页后切换为 TV 界面'), findsOneWidget);
    expect(find.text('返回首页并切换'), findsOneWidget);
    expect(await tester.runAsync(settings.getForceTvMode), isTrue);
    expect(find.text('TV 模式已开启'), findsOneWidget);

    await tester.tap(find.text('返回首页并切换'));
    await _pumpUntilFound(tester, find.byType(HomePage));
    expect(find.text('TV 模式已开启'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    final homePage = tester.widget<HomePage>(find.byType(HomePage));
    expect(identical(homePage.client, client), isTrue);
    expect(identical(homePage.historyStore, historyStore), isTrue);
    expect(identical(homePage.sessionStore, sessionStore), isTrue);
    expect(identical(homePage.offlineController, offlineController), isTrue);
    expect(identical(homePage.appSettings, settings), isTrue);
  });

  testWidgets('app settings logout clears cookies and pauses offline cache', (
    WidgetTester tester,
  ) async {
    final root = Directory(
      '${Directory.systemTemp.path}/bili-settings-logout-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    final client = BiliClient();
    final sessionStore = BiliSessionStore(baseDirectory: root);
    final offlineController = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    await tester.runAsync(() async {
      await sessionStore.saveCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
      });
    });
    final appSettings = AppSettingsStore(baseDirectory: root);
    final themeController = AppThemeController(settings: appSettings);
    addTearDown(themeController.dispose);
    await tester.pumpWidget(
      AppThemeScope(
        controller: themeController,
        child: MaterialApp(
          theme: AppVisualTokens.mobileLightTheme(),
          home: BiliSettingsPage(
            appSettings: appSettings,
            client: client,
            sessionStore: sessionStore,
            offlineController: offlineController,
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.widgetWithText(TextButton, '退出'));

    expect(find.text('登录信息仅保存在本机'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '退出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.byType(GlassDialog), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(GlassDialog), matching: find.text('退出')),
    );
    await _pumpUntil(tester, () => offlineController.pauseAllActiveCalls == 1);
    await _pumpUntilFound(tester, find.text('可在“我的”页面扫码登录'));

    expect(offlineController.pauseAllActiveCalls, 1);
    expect(client.hasAuthenticatedSession, isFalse);
    expect(await tester.runAsync(sessionStore.loadCookies), isEmpty);
    expect(find.widgetWithText(TextButton, '退出'), findsNothing);
    expect(find.text('已退出登录，离线缓存任务已暂停'), findsOneWidget);
  });
}
