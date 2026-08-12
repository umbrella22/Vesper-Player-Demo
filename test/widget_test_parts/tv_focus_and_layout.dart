part of '../widget_test.dart';

void _registerTvFocusAndLayoutWidgetTests() {
  testWidgets('tv focusable responds to touch taps', (
    WidgetTester tester,
  ) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TvFocusable(
            debugLabel: 'touch_target',
            onTap: () {
              tapCount += 1;
            },
            child: const SizedBox(
              width: 160,
              height: 56,
              child: Center(child: Text('TV 操作')),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('TV 操作'));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets('tv directional scope moves focus horizontally', (
    WidgetTester tester,
  ) async {
    final leftNode = FocusNode(debugLabel: 'left');
    final rightNode = FocusNode(debugLabel: 'right');
    addTearDown(leftNode.dispose);
    addTearDown(rightNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TvDirectionalFocusScope(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvFocusable(
                  focusNode: leftNode,
                  autofocus: true,
                  onTap: () {},
                  child: const SizedBox(
                    width: 120,
                    height: 56,
                    child: Text('左侧'),
                  ),
                ),
                const SizedBox(width: 24),
                TvFocusable(
                  focusNode: rightNode,
                  onTap: () {},
                  child: const SizedBox(
                    width: 120,
                    height: 56,
                    child: Text('右侧'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(leftNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(rightNode.hasFocus, isTrue);
  });

  testWidgets('tv focusable surface exposes focused visual state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 180,
            height: 120,
            child: TvFocusableSurface(
              autofocus: true,
              onTap: () {},
              builder: (context, focused) {
                return Center(child: Text(focused ? 'focused' : 'plain'));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('focused'), findsOneWidget);
  });

  testWidgets('tv settings switch only shows return home after mode changes', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(tester);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('TV 设置'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('返回首页并切换'), findsNothing);

    await tester.tap(find.text('强制 TV 模式'));
    await _flushRealAsync(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('返回首页并切换'), findsOneWidget);

    await tester.tap(find.text('强制 TV 模式'));
    await _flushRealAsync(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('返回首页并切换'), findsNothing);
    expect(find.text('已恢复当前显示模式，无需切换首页。'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('tv mode handoff preserves the active app dependencies', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(tester);

    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.tap(find.text('强制 TV 模式'));
    await _pumpUntilFound(tester, find.text('返回首页并切换'));
    await tester.tap(find.text('返回首页并切换'));
    await _pumpUntilFound(tester, find.byType(HomePage));

    expect(find.text('显示模式已修改，点击下方按钮返回首页切换。'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    final homePage = tester.widget<HomePage>(find.byType(HomePage));
    expect(identical(homePage.client, harness.client), isTrue);
    expect(identical(homePage.historyStore, harness.historyStore), isTrue);
    expect(identical(homePage.sessionStore, harness.sessionStore), isTrue);
    expect(
      identical(homePage.offlineController, harness.offlineController),
      isTrue,
    );
    expect(identical(homePage.appSettings, harness.appSettings), isTrue);
  });

  testWidgets('tv settings about card adapts on narrow landscape', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(tester, surfaceSize: const Size(760, 430));

    for (var index = 0; index < 6; index += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 180));
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_settings');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 240));

    final aboutCard = find.byKey(
      const ValueKey<String>('bili-tv-settings-about-card'),
    );
    final forceModeCard = find.byKey(
      const ValueKey<String>('bili-tv-settings-force-mode-card'),
    );
    expect(aboutCard, findsOneWidget);
    expect(forceModeCard, findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(aboutCard).width,
      closeTo(tester.getSize(forceModeCard).width, 0.5),
    );
  });

  testWidgets('tv rail keeps logo avatar and navigation icons on one axis', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    double centerX(String key) =>
        tester.getCenter(find.byKey(ValueKey<String>(key))).dx;
    void expectAligned() {
      final logoX = centerX('bili-tv-rail-logo');
      expect(centerX('bili-tv-rail-avatar'), closeTo(logoX, 0.5));
      expect(centerX('bili-tv-rail-icon-recommend'), closeTo(logoX, 0.5));
      expect(centerX('bili-tv-rail-icon-settings'), closeTo(logoX, 0.5));
    }

    expectAligned();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 240));
    expectAligned();
  });

  testWidgets('tv recommendations use a padded vertical grid', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    final gridPadding = tester.widget<SliverPadding>(
      find.byKey(const ValueKey<String>('bili-tv-recommend-grid')),
    );
    final padding = gridPadding.padding as EdgeInsets;

    expect(
      find.byKey(const ValueKey<String>('tv-shelf-list-为你推荐')),
      findsNothing,
    );
    expect(padding.top, 16);
    expect(padding.bottom, 32);
  });

  testWidgets('tv hero keeps progress separated from playback actions', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      initialHistoryEntries: _tvHistoryEntries(1),
      skipBootstrap: true,
    );

    final progressRect = tester.getRect(
      find.byKey(const ValueKey<String>('bili-tv-hero-progress')),
    );
    final actionsRect = tester.getRect(
      find.byKey(const ValueKey<String>('bili-tv-hero-actions')),
    );

    expect(actionsRect.top - progressRect.bottom, greaterThanOrEqualTo(14));
  });

  testWidgets('tv search keyboard inset keeps left rail width stable', (
    WidgetTester tester,
  ) async {
    const surfaceSize = Size(900, 520);
    final harness = await _pumpTvHomePage(tester, surfaceSize: surfaceSize);

    await tester.tap(find.text('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 240));

    final rail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_search');
    expect(tester.getSize(rail).width, 260);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final initialRailWidth = tester.getSize(rail).width;
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_search_field');
    expect(initialRailWidth, 80);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).resizeToAvoidBottomInset,
      isFalse,
    );

    await _pumpTvHomeFrame(
      tester,
      harness,
      surfaceSize: surfaceSize,
      viewInsetsBottom: 260,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(tester.getSize(rail).width, initialRailWidth);
  });

  testWidgets('tv search suffix keeps width and stops loading after results', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(tester);
    final searchCompleter = Completer<List<BiliSearchResult>>();
    harness.client.searchCompleter = searchCompleter;

    await tester.tap(find.text('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    final suffix = find.byKey(const ValueKey<String>('bili-tv-search-suffix'));
    expect(tester.getSize(suffix), const Size(48, 48));
    expect(
      find.descendant(
        of: suffix,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    searchCompleter.complete(const <BiliSearchResult>[
      BiliSearchResult(
        aid: 1,
        bvid: 'BVSEARCH0001',
        title: '搜索结果 1',
        author: 'UP',
        coverUrl: '',
        durationLabel: '03:00',
        playCountLabel: '1万',
        danmakuCountLabel: '10',
      ),
    ]);
    await _flushRealAsync(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(tester.getSize(suffix), const Size(48, 48));
    expect(
      find.descendant(
        of: suffix,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.text('搜索结果 1'), findsOneWidget);
  });

  testWidgets('tv search waits for right before focusing the field', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 180));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 180));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 180));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_search');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.byType(TextField), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_search');
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('bili-tv-left-rail')))
          .width,
      260,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_search_field');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('bili-tv-left-rail')))
          .width,
      80,
    );
  });

  testWidgets('tv rail collapses for content and restores the last focus', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    expect(find.text('推荐视频 0'), findsWidgets);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_recommend');
    final rail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    expect(tester.getSize(rail).width, 260);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');
    expect(tester.getSize(rail).width, 80);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_details');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_recommend');
    expect(tester.getSize(rail).width, 260);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');
    expect(tester.getSize(rail).width, 80);
  });

  testWidgets('tv cover decode width stays stable while the rail animates', (
    WidgetTester tester,
  ) async {
    final feed = _tvFeedItems(18, true);
    await _pumpTvHomePage(tester, initialFeedItems: feed, skipBootstrap: true);

    final firstCard = find.byKey(ValueKey<String>('feed_${feed.first.bvid}'));
    Finder coverImage() =>
        find.descendant(of: firstCard, matching: find.byType(Image)).first;
    int cacheWidth() {
      final provider = tester.widget<Image>(coverImage()).image;
      return (provider as ResizeImage).width!;
    }

    final initialCacheWidth = cacheWidth();
    expect(tester.widget<Image>(coverImage()).gaplessPlayback, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));
    expect(cacheWidth(), initialCacheWidth);

    await tester.pump(const Duration(milliseconds: 220));
    expect(cacheWidth(), initialCacheWidth);
  });
}
