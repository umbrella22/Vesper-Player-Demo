part of '../widget_test.dart';

void _registerTvLibraryWidgetTests() {
  testWidgets('tv following uploads share the recommendation focus card', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
    );

    TvFocusableSurface focusSurfaceOf(Finder card) {
      expect(card, findsOneWidget);
      expect(tester.widget(card), isA<BiliTvVideoCard>());
      return tester.widget<TvFocusableSurface>(
        find.descendant(of: card, matching: find.byType(TvFocusableSurface)),
      );
    }

    final recommendSurface = focusSurfaceOf(
      find.byKey(const ValueKey<String>('feed_BVTV00000000')),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
    );

    final followingSurface = focusSurfaceOf(
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
    );
    final followingGrid = tester.widget<GridView>(
      find.byKey(const ValueKey<String>('bili-tv-space-video-grid')),
    );
    final followingGridDelegate =
        followingGrid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;

    for (final surface in <TvFocusableSurface>[
      recommendSurface,
      followingSurface,
    ]) {
      expect(surface.useOverlayLift, isTrue);
      expect(surface.scale, BiliTvVideoCard.focusScale);
      expect(surface.focusPadding, BiliTvVideoCard.focusPadding);
      expect(surface.borderRadius, BiliTvVideoCard.surfaceBorderRadius);
    }
    expect(
      followingGrid.padding,
      const EdgeInsets.all(BiliTvVideoGridLayout.focusInset),
    );
    expect(
      followingGridDelegate.mainAxisSpacing,
      BiliTvVideoGridLayout.mainAxisSpacing,
    );
    expect(
      followingGridDelegate.crossAxisSpacing,
      BiliTvVideoGridLayout.crossAxisSpacing,
    );
    expect(
      followingGridDelegate.childAspectRatio,
      BiliTvVideoGridLayout.childAspectRatio,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('tv_following_'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    for (var motionStep = 0; motionStep < 10; motionStep += 1) {
      await tester.pump(const Duration(milliseconds: 18));
      expect(
        tester.takeException(),
        isNull,
        reason: 'TV card focus motion failed at step $motionStep',
      );
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_space_video_BV1space0001',
    );
    expect(
      find.byKey(const ValueKey<String>('tv-content-glass-overlay')),
      findsOneWidget,
    );
  });

  testWidgets('tv home keeps the nested following browser alive', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
    );
    final recommendScrollElement = tester.element(
      find.byKey(const ValueKey<String>('bili-tv-recommend-scroll')),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
    );

    expect(
      find.byKey(const ValueKey<String>('bili-tv-home-following-pane')),
      findsOneWidget,
    );
    expect(harness.client.followingRequests, 1);
    expect(harness.client.spaceProfileRequests, 1);
    expect(harness.client.spaceVideoRequests, 1);

    final mainRail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    await tester.pump(AppVisualTokens.overlayDuration);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(tester.getSize(mainRail).width, 260);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('tv_following_'),
    );
    expect(tester.getSize(mainRail).width, 80);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('bili-tv-following-user-7')),
    );
    await tester.pump(AppVisualTokens.tvFocusDuration);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_following_user_7',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('tv_space_'),
    );
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(AppVisualTokens.overlayDuration);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(tester.getSize(mainRail).width, 260);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    expect(find.text('推荐视频 0'), findsWidgets);
    expect(
      tester.element(
        find.byKey(const ValueKey<String>('bili-tv-recommend-scroll')),
      ),
      same(recommendScrollElement),
    );
    expect(harness.client.recommendedFeedRequests, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
      findsOneWidget,
    );
    expect(harness.client.followingRequests, 1);
    expect(harness.client.spaceProfileRequests, 1);
    expect(harness.client.spaceVideoRequests, 1);
  });

  testWidgets('tv nested following rails fit compact landscape', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      surfaceSize: const Size(760, 430),
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
    );

    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );
    final mainRail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    final followingRail = find.byKey(
      const ValueKey<String>('bili-tv-following-rail'),
    );
    final contentArea = find.byKey(
      const ValueKey<String>('bili-tv-following-content-area'),
    );
    await tester.pump(AppVisualTokens.overlayDuration);
    final compactContentWidth = tester.getRect(contentArea).width;
    final compactMainRect = tester.getRect(mainRail);
    final compactFollowingRect = tester.getRect(followingRail);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(tester.getSize(mainRail).width, 260);
    expect(compactFollowingRect.left - compactMainRect.right, closeTo(12, 0.5));
    expect(compactFollowingRect.top, closeTo(compactMainRect.top, 0.5));
    expect(compactFollowingRect.bottom, closeTo(compactMainRect.bottom, 0.5));
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('tv_following_'),
    );
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(mainRail).width, 80);
    final expandedMainRect = tester.getRect(mainRail);
    final expandedFollowingRect = tester.getRect(followingRail);
    expect(
      expandedFollowingRect.left - expandedMainRect.right,
      closeTo(12, 0.5),
    );
    expect(expandedFollowingRect.top, closeTo(expandedMainRect.top, 0.5));
    expect(expandedFollowingRect.bottom, closeTo(expandedMainRect.bottom, 0.5));
    expect(
      tester.getRect(contentArea).width,
      closeTo(compactContentWidth, 0.5),
    );
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );
    expect(
      tester.getRect(contentArea).width,
      closeTo(compactContentWidth, 0.5),
    );
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.overlayDuration);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );
    expect(tester.getSize(mainRail).width, 260);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tv primary rail items share icon and label alignment', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    final iconRects = <Rect>[];
    final labelRects = <Rect>[];
    for (final item in <String>['recommend', 'following', 'regions']) {
      iconRects.add(
        tester.getRect(find.byKey(ValueKey<String>('bili-tv-rail-icon-$item'))),
      );
      labelRects.add(
        tester.getRect(
          find.byKey(ValueKey<String>('bili-tv-rail-label-$item')),
        ),
      );
    }
    for (var index = 1; index < iconRects.length; index += 1) {
      expect(
        iconRects[index].center.dx,
        closeTo(iconRects.first.center.dx, 0.5),
      );
      expect(labelRects[index].left, closeTo(labelRects.first.left, 0.5));
    }
  });

  testWidgets(
    'tv following pane resets when the authenticated session changes',
    (WidgetTester tester) async {
      final harness = await _pumpTvHomePage(
        tester,
        initialFeedItems: _tvFeedItems(),
        skipBootstrap: true,
        loggedIn: true,
        authenticatedSession: true,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
      );
      final oldPaneElement = tester.element(
        find.byKey(const ValueKey<String>('bili-tv-following-pane')),
      );
      expect(
        find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
        findsOneWidget,
      );

      harness.client.clearSession();
      await _pumpTvHomeFrame(
        tester,
        harness,
        surfaceSize: const Size(1280, 720),
        initialFeedItems: _tvFeedItems(),
        skipBootstrap: true,
      );
      await _pumpUntilFound(tester, find.text('暂时无法显示'));
      expect(
        find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
        findsNothing,
      );
      expect(
        tester.element(
          find.byKey(const ValueKey<String>('bili-tv-following-pane')),
        ),
        isNot(same(oldPaneElement)),
      );
    },
  );

  testWidgets('tv embedded following login state keeps home rail focus', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntilFound(tester, find.text('暂时无法显示'));

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_following');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tv empty following rail exposes a compact refresh action', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
      emptyFollowing: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntilFound(tester, find.text('选择一位 UP 主'));
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_following_refresh',
    );
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tv primary pages keep a twelve pixel rail gap', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      initialHistoryEntries: _tvHistoryEntries(2),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
    );

    final rail = find.byKey(const ValueKey<String>('bili-tv-left-rail'));
    final content = find.byKey(const ValueKey<String>('bili-tv-content-area'));

    void expectRailGap(double railWidth) {
      final railRect = tester.getRect(rail);
      final contentRect = tester.getRect(content);
      expect(railRect.width, closeTo(railWidth, 0.5));
      expect(contentRect.left - railRect.right, closeTo(12, 0.5));
    }

    Future<void> selectPrimaryNav(String item) async {
      final state = find.byKey(
        ValueKey<String>('tv-glass-selectable-state-nav_$item'),
      );
      final focusable = find
          .ancestor(of: state, matching: find.byType(TvFocusable))
          .last;
      tester
          .widget<Focus>(
            find.descendant(of: focusable, matching: find.byType(Focus)).first,
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.pump(AppVisualTokens.overlayDuration);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await _flushRealAsync(tester);
      await tester.pump(AppVisualTokens.overlayDuration);
    }

    for (final item in <String>[
      'regions',
      'search',
      'history',
      'mine',
      'settings',
    ]) {
      await selectPrimaryNav(item);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav_$item');
      expectRailGap(260);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(AppVisualTokens.overlayDuration);
      expectRailGap(80);
    }
  });

  testWidgets('tv embedded following does not reload after playback returns', (
    WidgetTester tester,
  ) async {
    final previousPlatform = VesperPlayerPlatform.instance;
    final platform = _FakePlaybackVesperPlatform(
      initialSnapshot: _playbackSnapshot,
    );
    VesperPlayerPlatform.instance = platform;
    addTearDown(() => VesperPlayerPlatform.instance = previousPlatform);
    addTearDown(platform.closeEvents);
    final externalPlayback = _ExternalPlaybackHarness()..install();
    addTearDown(externalPlayback.uninstall);

    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
      loggedIn: true,
      authenticatedSession: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    final video = find.byKey(
      const ValueKey<String>('bili-tv-space-video-BV1space0001'),
    );
    await _pumpUntilFound(tester, video);
    final followingRequests = harness.client.followingRequests;
    final profileRequests = harness.client.spaceProfileRequests;
    final videoRequests = harness.client.spaceVideoRequests;

    await tester.tap(video);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BiliPlaybackPage), findsOneWidget);

    Navigator.of(tester.element(find.byType(BiliPlaybackPage))).pop();
    await tester.pump();
    await _flushRealAsync(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(video, findsOneWidget);
    expect(harness.client.followingRequests, followingRequests);
    expect(harness.client.spaceProfileRequests, profileRequests);
    expect(harness.client.spaceVideoRequests, videoRequests);
  });

  testWidgets('tv hero focus update is debounced and does not load details', (
    WidgetTester tester,
  ) async {
    final harness = await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );
    Text heroTitle() => tester.widget<Text>(
      find.byKey(const ValueKey<String>('bili-tv-hero-title')),
    );

    expect(heroTitle().data, '推荐视频 0');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video_推荐视频 0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(heroTitle().data, '推荐视频 0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video_推荐视频 2');
    await tester.pump(const Duration(milliseconds: 119));
    expect(heroTitle().data, '推荐视频 0');
    expect(harness.client.requestedVideoDetails, isEmpty);

    await tester.pump(const Duration(milliseconds: 2));
    expect(heroTitle().data, '推荐视频 2');
    expect(harness.client.requestedVideoDetails, isEmpty);
  });

  testWidgets('tv mine keeps its two library actions aligned', (
    WidgetTester tester,
  ) async {
    await _pumpTvHomePage(
      tester,
      initialFeedItems: _tvFeedItems(),
      skipBootstrap: true,
    );

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      find.byKey(
        const ValueKey<String>('tv-glass-selectable-state-nav_following'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('bili-tv-content-area')),
        matching: find.text('关注列表'),
      ),
      findsNothing,
    );
    final historyAction = find
        .ancestor(of: find.text('历史播放'), matching: find.byType(TvFocusable))
        .last;
    final watchLaterAction = find
        .ancestor(of: find.text('稍后再看'), matching: find.byType(TvFocusable))
        .last;
    expect(historyAction, findsOneWidget);
    expect(watchLaterAction, findsOneWidget);

    final historyRect = tester.getRect(historyAction);
    final watchLaterRect = tester.getRect(watchLaterAction);
    expect(historyRect.center.dy, closeTo(watchLaterRect.center.dy, 0.5));
    expect(historyRect.overlaps(watchLaterRect), isFalse);
  });
}
