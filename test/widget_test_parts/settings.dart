part of '../widget_test.dart';

void _registerSettingsWidgetTests() {
  testWidgets('phone settings applies the saved interface preference', (
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
    await _pumpUntilFound(tester, find.text('始终使用 TV 界面'));

    expect(find.text('始终使用 TV 界面'), findsOneWidget);
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

  testWidgets(
    'phone settings preserves injected session and history and owns its Snackbar',
    (tester) async {
      final root = Directory(
        '${Directory.systemTemp.path}/phone-settings-route-${DateTime.now().microsecondsSinceEpoch}',
      );
      final settings = AppSettingsStore(baseDirectory: root);
      final store = BiliSessionStore(baseDirectory: root);
      final client = BiliClient()
        ..restoreCookies({'SESSDATA': 'live', 'bili_jct': 'csrf'});
      final revision = client.sessionRevision;
      final history = BiliHistoryStore(baseDirectory: root);
      final downloads = _FakeOfflineController([]);
      final theme = AppThemeController(settings: settings);
      addTearDown(theme.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
      });
      await tester.runAsync(
        () => store.saveCookies({'SESSDATA': 'old', 'bili_jct': 'csrf'}),
      );
      await tester.pumpWidget(
        AppThemeScope(
          controller: theme,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BiliSettingsPage(
                        appSettings: settings,
                        client: client,
                        historyStore: history,
                        sessionStore: store,
                        offlineController: downloads,
                      ),
                    ),
                  ),
                  child: const Text('打开设置'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开设置'));
      await _pumpUntilFound(tester, find.text('离线缓存'));
      expect(client.sessionRevision, revision);
      expect(client.snapshotCookies()['SESSDATA'], 'live');
      await tester.tap(find.text('离线缓存'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OfflineCachePage>(find.byType(OfflineCachePage))
            .historyStore,
        same(history),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('强制 TV 模式'));
      await _pumpUntilFound(tester, find.text('返回首页切换'));
      final staleAction = tester
          .widget<SnackBarAction>(find.byType(SnackBarAction))
          .onPressed;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('打开设置'), findsOneWidget);
      expect(find.byType(SnackBarAction), findsNothing);
      staleAction();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

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
    final logoutDialog = find.byKey(
      const ValueKey<String>('media-readable-glass-dialog'),
    );
    expect(logoutDialog, findsOneWidget);

    await tester.tap(
      find.descendant(of: logoutDialog, matching: find.text('退出')),
    );
    await _pumpUntil(tester, () => offlineController.pauseAllActiveCalls == 1);
    await _pumpUntilFound(tester, find.text('可在“我的”页面扫码登录'));

    expect(offlineController.pauseAllActiveCalls, 1);
    expect(client.hasAuthenticatedSession, isFalse);
    expect(await tester.runAsync(sessionStore.loadCookies), isEmpty);
    expect(find.widgetWithText(TextButton, '退出'), findsNothing);
    expect(find.text('已退出登录，离线缓存任务已暂停'), findsOneWidget);
  });

  testWidgets(
    'settings about section omits trailing divider when updates are unsupported',
    (WidgetTester tester) async {
      final root = Directory(
        '${Directory.systemTemp.path}/bili-settings-unsupported-update-${DateTime.now().microsecondsSinceEpoch}',
      );
      final appSettings = AppSettingsStore(baseDirectory: root);
      final themeController = AppThemeController(settings: appSettings);
      final updateController = AppUpdateController(
        client: _UnsupportedUpdateClient(),
        installer: _UnsupportedUpdateInstaller(),
        currentVersion: () async => '1.18.3',
      );
      addTearDown(themeController.dispose);
      addTearDown(updateController.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
      });

      await tester.runAsync(updateController.check);
      await tester.pumpWidget(
        AppUpdateScope(
          controller: updateController,
          child: AppThemeScope(
            controller: themeController,
            child: MaterialApp(
              theme: AppVisualTokens.mobileLightTheme(),
              home: BiliSettingsPage(
                appSettings: appSettings,
                client: _FakeTvHomeClient(),
                historyStore: BiliHistoryStore(baseDirectory: root),
                sessionStore: BiliSessionStore(baseDirectory: root),
                offlineController: _FakeOfflineController(
                  const <BiliOfflineDownloadEntry>[],
                ),
              ),
            ),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('Vesper'));

      expect(find.byKey(const ValueKey('app-check-for-updates')), findsNothing);
      final aboutSurface = find.ancestor(
        of: find.text('Vesper'),
        matching: find.byType(AppGroupedSurface),
      );
      expect(
        find.descendant(of: aboutSurface, matching: find.byType(Divider)),
        findsNothing,
      );
    },
  );
}

final class _UnsupportedUpdateClient implements AppUpdateClient {
  @override
  void cancelDownload() {}

  @override
  void dispose() {}

  @override
  Future<File> download(
    AppUpdateAsset asset, {
    required void Function(int received, int total) onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppUpdateRelease?> latestRelease(AppUpdatePlatform platform) async =>
      null;
}

final class _UnsupportedUpdateInstaller implements AppUpdateInstaller {
  @override
  Future<bool> canInstall() async => false;

  @override
  Future<void> export(File file) async {}

  @override
  Future<AppUpdateInstallResult> install(File file) async =>
      AppUpdateInstallResult.opened;

  @override
  Future<AppUpdatePlatform> platform() async => AppUpdatePlatform.unsupported;
}
