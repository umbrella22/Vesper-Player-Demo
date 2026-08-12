part of '../widget_test.dart';

void _registerTvContentWidgetTests() {
  testWidgets('tv home only builds a bounded visible feed subset', (
    WidgetTester tester,
  ) async {
    final items = _tvFeedItems(400);
    await _pumpTvHomePage(tester, initialFeedItems: items, skipBootstrap: true);

    final builtFeedCards = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('feed_');
    });
    final builtCardCount = builtFeedCards.evaluate().length;

    expect(builtCardCount, greaterThan(0));
    expect(builtCardCount, lessThan(80));
    expect(
      find.byKey(ValueKey<String>('feed_${items.last.bvid}')),
      findsNothing,
    );
  });

  testWidgets('tv rail separates neutral focus lens from selection marker', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    final focusedItem = find
        .ancestor(of: find.text('为你推荐'), matching: find.byType(TvFocusable))
        .last;
    final focusedContainer = tester.widget<AnimatedContainer>(
      find.byKey(
        const ValueKey<String>('tv-glass-selectable-state-nav_recommend'),
      ),
    );
    final decoration = focusedContainer.decoration! as BoxDecoration;
    final borderColor = decoration.border?.top.color;
    final fillColor = decoration.color;

    expect(borderColor?.a, greaterThan(0));
    expect(fillColor?.a, 0);
    expect(
      find.descendant(
        of: focusedItem,
        matching: find.byWidgetPredicate((widget) {
          final markerDecoration = widget is AnimatedContainer
              ? widget.decoration
              : null;
          return markerDecoration is BoxDecoration &&
              markerDecoration.color == AppVisualTokens.primaryBlue;
        }),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tv shelves scroll and restore focus in all directions', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      surfaceSize: const Size(900, 520),
      initialFeedItems: _tvFeedItems(60),
      initialHistoryEntries: _tvHistoryEntries(24),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');

    Future<void> move(LogicalKeyboardKey key, int count) async {
      for (var index = 0; index < count; index++) {
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump(const Duration(milliseconds: 180));
      }
    }

    Future<List<String?>> moveUntil(
      LogicalKeyboardKey key,
      String debugLabel, {
      int attempts = 24,
    }) async {
      final visited = <String?>[];
      for (var index = 0; index < attempts; index += 1) {
        final current = FocusManager.instance.primaryFocus?.debugLabel;
        visited.add(current);
        if (current == debugLabel) {
          return visited;
        }
        await move(key, 1);
      }
      visited.add(FocusManager.instance.primaryFocus?.debugLabel);
      return visited;
    }

    await move(LogicalKeyboardKey.arrowDown, 1);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history_历史视频 0');

    final historyList = tester.widget<ListView>(
      find.byKey(const ValueKey<String>('tv-shelf-list-继续观看')),
    );
    await moveUntil(LogicalKeyboardKey.arrowRight, 'history_历史视频 12');
    final rightwardOffset = historyList.controller!.offset;
    expect(rightwardOffset, greaterThan(0));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history_历史视频 12');

    final leftVisited = await moveUntil(
      LogicalKeyboardKey.arrowLeft,
      'history_历史视频 0',
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'history_历史视频 0',
      reason: 'Visited ${leftVisited.join(' -> ')}',
    );
    expect(historyList.controller!.offset, lessThan(rightwardOffset));

    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey<String>('bili-tv-recommend-scroll')),
    );
    final beforeDown = scrollView.controller!.offset;
    await move(LogicalKeyboardKey.arrowDown, 1);
    final downwardOffset = scrollView.controller!.offset;

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video_推荐视频 0');
    expect(downwardOffset, greaterThan(beforeDown));

    await move(LogicalKeyboardKey.arrowUp, 1);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history_历史视频 0');
    expect(scrollView.controller!.offset, lessThanOrEqualTo(downwardOffset));

    expect(scrollView.controller!.offset, greaterThan(0));
    await move(LogicalKeyboardKey.arrowUp, 1);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');
    expect(scrollView.controller!.offset, 0);
  });

  testWidgets('tv home regions nav loads section videos', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      loggedIn: true,
    );
    await _pumpUntil(tester, () => find.text('测试用户').evaluate().isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_regions');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_regions');
    expect(harness.client.requestedSections, isNotEmpty);
    expect(find.text('番剧'), findsWidgets);
    expect(find.text('番剧内容 0'), findsOneWidget);

    await tester.tap(
      find
          .ancestor(of: find.text('国创'), matching: find.byType(TvFocusable))
          .last,
    );
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(harness.client.requestedSections.last.id, 'guochuang');
    expect(find.text('国创内容 0'), findsOneWidget);
  });

  testWidgets('tv region categories keep focus separate from the first row', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      surfaceSize: const Size(3008, 1692),
      initialFeedItems: _tvFeedItems(),
      loggedIn: true,
    );
    await _pumpUntil(tester, () => find.text('测试用户').evaluate().isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_regions');
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('bili-tv-left-rail')))
          .width,
      300,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(AppVisualTokens.overlayDuration);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'region_bangumi');
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('bili-tv-left-rail')))
          .width,
      88,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'region_guochuang');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'region_guochuang');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('video_国创内容'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'region_guochuang');
  });

  testWidgets('tv home regions prompt for login before loading', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(find.text('需要登录'), findsOneWidget);
    expect(harness.client.requestedSections, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-dialog-surface')),
      findsOneWidget,
    );
    expect(find.byType(GlassDialog), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_取消');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_登录');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 240));
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('需要登录'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-qr-login-surface')),
      findsOneWidget,
    );
    expect(find.byType(GlassSheet), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_qr_login_refresh',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      find.byKey(const ValueKey<String>('bili-tv-qr-login-surface')),
      findsNothing,
    );
    expect(harness.client.generatedQrTickets, 1);
  });

  testWidgets('tv logout asks for confirmation before clearing the account', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      loggedIn: true,
    );
    await _pumpUntil(tester, () => find.text('测试用户').evaluate().isNotEmpty);

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.tap(find.text('退出登录'));
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('退出登录？'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_取消');

    // Android TV sends KEYCODE_BACK through the key channel before asking the
    // current route to pop. The key phase must not dismiss the dialog early,
    // otherwise the route pop would reach the TV home page and open Exit App.
    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pumpAndSettle();
    expect(find.text('退出登录？'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('退出登录？'), findsNothing);
    expect(find.text('退出 Vesper？'), findsNothing);
    expect(find.text('退出登录'), findsOneWidget);

    await tester.tap(find.text('退出登录'));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_退出登录');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await _pumpUntilFound(tester, find.text('扫码登录'));

    expect(find.text('退出登录？'), findsNothing);
    expect(find.text('扫码登录'), findsOneWidget);
  });

  testWidgets('tv QR login keeps its default action visible at compact height', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory(
      '${Directory.systemTemp.path}/bili-tv-qr-compact-${DateTime.now().microsecondsSinceEpoch}',
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
        theme: AppVisualTokens.darkTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showBiliTvQrLoginDialog(
              context: context,
              client: _FakeQrLoginClient(),
              sessionStore: BiliSessionStore(baseDirectory: root),
            ),
            child: const Text('打开 TV 登录'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开 TV 登录'));
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_qr_login_refresh',
    );
    final refreshRect = tester.getRect(
      find.byKey(const ValueKey<String>('bili-tv-dialog-action-刷新二维码')),
    );
    expect(refreshRect.top, greaterThanOrEqualTo(0));
    expect(refreshRect.bottom, lessThanOrEqualTo(360));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'tv home clipped cards do not leave focused overlay outside grid',
    (WidgetTester tester) async {
      await _pumpTvHomePage(
        tester,
        initialFeedItems: _tvFeedItems(),
        skipBootstrap: true,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();

      expect(find.text('推荐视频 0'), findsWidgets);
    },
  );

  testWidgets('tv home back opens exit confirmation dialog', (
    WidgetTester tester,
  ) async {
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('退出 Vesper？'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bili-tv-dialog-surface')),
      findsOneWidget,
    );
    final exitSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('bili-tv-dialog-surface')),
    );
    final exitDecoration = exitSurface.decoration as BoxDecoration;
    expect(exitDecoration.color, const Color(0xF21B1E24));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('bili-tv-dialog-surface')))
          .width,
      690,
    );
    expect(
      tester.widget<Text>(find.text('退出 Vesper？')).style?.color,
      Colors.white,
    );
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_继续观看');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('退出 Vesper？'), findsNothing);
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_退出应用');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isNotEmpty,
    );
  });

  testWidgets('tv home Android back opens one persistent exit dialog', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pump();

    expect(find.text('退出 Vesper？'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('退出 Vesper？'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_继续观看');

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('退出 Vesper？'), findsOneWidget);
  });

  testWidgets('tv library Android back returns one level without exit dialog', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.tap(find.text('历史播放'));
    await tester.pumpAndSettle();

    expect(find.byType(BiliLibraryPage), findsOneWidget);
    expect(find.byType(BiliTvHomePage, skipOffstage: false), findsOneWidget);

    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pump();
    expect(find.byType(BiliLibraryPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(BiliLibraryPage), findsNothing);
    expect(find.byType(BiliTvHomePage), findsOneWidget);
    expect(find.text('退出 Vesper？'), findsNothing);
  });
}
