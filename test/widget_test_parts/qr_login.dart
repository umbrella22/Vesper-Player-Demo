part of '../widget_test.dart';

void _registerQrLoginWidgetTests() {
  testWidgets('QR login sheet refreshes expired ticket', (
    WidgetTester tester,
  ) async {
    final client = _FakeQrLoginClient()
      ..pollResults.addAll(const <BiliQrLoginPollResult>[
        BiliQrLoginPollResult(
          status: BiliQrLoginStatus.expired,
          message: '二维码已过期',
          timestampMs: 1000,
        ),
        BiliQrLoginPollResult(
          status: BiliQrLoginStatus.scannedAwaitingConfirm,
          message: '已扫码',
          timestampMs: 2000,
        ),
      ]);
    final root = Directory(
      '${Directory.systemTemp.path}/bili-qr-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
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
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () async {
                  await showBiliQrLoginSheet(
                    context: context,
                    client: client,
                    sessionStore: BiliSessionStore(baseDirectory: root),
                  );
                },
                child: const Text('登录'),
              ),
            );
          },
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.text('登录'));
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('二维码已失效，刷新后重新扫码。'), findsOneWidget);
    expect(find.textContaining('状态更新时间'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('media-readable-glass-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bili-qr-code-surface')),
      findsOneWidget,
    );
    expect(client.generatedTickets, 1);

    await tester.tap(find.text('刷新二维码'));
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('已经扫到码了，等手机端确认。'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('已扫码，继续等待'), findsOneWidget);
    expect(client.generatedTickets, 2);
    expect(client.polledKeys, <String>['key-1', 'key-2']);
  });

  testWidgets('QR login sheet keeps readable contrast in dark mode', (
    WidgetTester tester,
  ) async {
    final client = _FakeQrLoginClient();
    final root = Directory(
      '${Directory.systemTemp.path}/bili-qr-dark-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.darkTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showBiliQrLoginSheet(
              context: context,
              client: client,
              sessionStore: BiliSessionStore(baseDirectory: root),
            ),
            child: const Text('登录'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('登录'));
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));

    final sheet = tester.widget<GlassSheet>(
      find.byKey(const ValueKey<String>('media-readable-glass-sheet')),
    );
    final title = tester.widget<Text>(find.text('扫码登录哔哩哔哩'));
    final qrSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('bili-qr-code-surface')),
    );
    final qrDecoration = qrSurface.decoration as BoxDecoration;

    expect(
      sheet.settings?.glassColor,
      AppVisualTheme.dark.surface.withValues(alpha: 0.96),
    );
    expect(title.style?.color, AppVisualTheme.dark.textPrimary);
    expect(qrDecoration.color, Colors.white);
  });

  testWidgets('QR login sheet pops profile after confirmed login', (
    WidgetTester tester,
  ) async {
    final client = _FakeQrLoginClient()
      ..pollResults.add(
        const BiliQrLoginPollResult(
          status: BiliQrLoginStatus.confirmed,
          message: '登录成功',
          timestampMs: 3000,
        ),
      );
    final root = Directory(
      '${Directory.systemTemp.path}/bili-qr-confirm-widget-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
    });

    BiliUserProfile? poppedProfile;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () async {
                  poppedProfile = await showBiliQrLoginSheet(
                    context: context,
                    client: client,
                    sessionStore: BiliSessionStore(baseDirectory: root),
                  );
                },
                child: const Text('登录'),
              ),
            );
          },
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.text('登录'));
    await tester.pump();
    await _flushRealAsync(tester);
    await _pumpUntilAbsent(tester, find.text('扫码登录哔哩哔哩'));

    expect(find.text('扫码登录哔哩哔哩'), findsNothing);
    expect(poppedProfile?.name, '扫码用户');
    final cookies = await tester.runAsync(
      () => BiliSessionStore(baseDirectory: root).loadCookies(),
    );
    expect(cookies, {'SESSDATA': 'cookie'});
  });
}
