part of '../widget_test.dart';

void _registerPlaybackPlatformWidgetTests() {
  testWidgets(
    'tv playback uses dedicated stage without mobile player chrome',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      expect(find.byType(vesper_ui.VesperPlayerStage), findsNothing);
      expect(find.byType(VesperPlayerView), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Android playback selects TextureView on flagged legacy devices',
    (WidgetTester tester) async {
      const channel = MethodChannel('dev.ikaros.vesper_player/platform');
      const platformViewsChannel = MethodChannel('flutter/platform_views');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'shouldPreferTextureViewForPlayback',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        platformViewsChannel,
        (call) async {
          switch (call.method) {
            case 'create':
              return 1;
            case 'resize':
              final arguments = call.arguments as Map<Object?, Object?>;
              return <String, Object?>{
                'width': arguments['width'],
                'height': arguments['height'],
              };
            default:
              return null;
          }
        },
      );
      final externalPlayback = _ExternalPlaybackHarness()..install();
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          platformViewsChannel,
          null,
        );
        externalPlayback.uninstall();
      });

      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
        externalPlaybackMockInstalled: true,
      );
      await _flushRealAsync(tester);
      await tester.pump();

      expect(
        harness.platform.lastRenderSurfaceKind,
        VesperPlayerRenderSurfaceKind.textureView,
      );
      expect(
        harness.platform.lastSystemPlaybackConfiguration?.backgroundMode,
        VesperBackgroundPlaybackMode.disabled,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'tv playback context menu key shows controls',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      expect(find.text('快退 10s'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();

      expect(find.text('快退 10s'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback opens quality speed and page panels separately',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .ancestor(of: find.text('清晰度'), matching: find.byType(TvFocusable))
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('1080P'), findsOneWidget);
      expect(find.text('1.25x'), findsNothing);
      expect(find.textContaining('P2'), findsNothing);

      await tester.tap(
        find
            .ancestor(
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('1.25x'), findsOneWidget);
      expect(find.text('1080P'), findsNothing);
      expect(find.textContaining('P2'), findsNothing);

      await tester.tap(
        find
            .ancestor(
              of: find.text('分P').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('P2'), findsOneWidget);
      expect(find.text('P2'), findsOneWidget);
      expect(find.text('1.25x'), findsNothing);
      expect(find.text('1080P'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback quality panel keeps auto selected during adaptive playback',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(of: find.text('清晰度'), matching: find.byType(TvFocusable))
            .last,
      );
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_自动');
      expect(find.text('自动'), findsOneWidget);
      expect(find.text('1080P'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback subtitle panel selects an SDK subtitle track',
    (WidgetTester tester) async {
      final subtitleSnapshot = _playbackSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsTrackCatalog: true,
          supportsTrackSelection: true,
          supportsSubtitleTrackSelection: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[
            VesperMediaTrack(
              id: 'subtitle:bili:zh-CN',
              kind: VesperMediaTrackKind.subtitle,
              label: '中文（中国大陆）',
              language: 'zh-CN',
              isDefault: true,
            ),
            VesperMediaTrack(
              id: 'subtitle:bili:en-US',
              kind: VesperMediaTrackKind.subtitle,
              label: 'English',
              language: 'en-US',
            ),
          ],
        ),
        confirmedSubtitleSelection: const VesperTrackSelection.track(
          'subtitle:bili:zh-CN',
        ),
      );
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
        initialSnapshot: subtitleSnapshot,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(of: find.text('字幕'), matching: find.byType(TvFocusable))
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('关闭'), findsNWidgets(2));
      expect(find.text('自动'), findsOneWidget);
      expect(find.text('中文（中国大陆）'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'tv_panel_中文（中国大陆）',
      );

      await tester.tap(
        find
            .ancestor(
              of: find.text('English'),
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pump();

      expect(harness.platform.subtitleSelections, hasLength(1));
      expect(
        harness.platform.subtitleSelections.single.mode,
        VesperTrackSelectionMode.track,
      );
      expect(
        harness.platform.subtitleSelections.single.trackId,
        'subtitle:bili:en-US',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback subtitle panel exposes unavailable state',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(of: find.text('字幕'), matching: find.byType(TvFocusable))
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('当前播放内核不支持字幕切换。'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_close');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback page panel uses right drawer with focused and selected states',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('分P').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('P1'), findsOneWidget);
      expect(find.text('P2'), findsOneWidget);
      expect(find.text('P3'), findsOneWidget);

      final drawerLeft = tester.getTopLeft(find.text('分P').last).dx;
      expect(drawerLeft, greaterThan(780));

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_P1');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_P2');

      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback pgc page panel uses episode copy',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        detail: _pgcPlaybackDetail(),
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('分P').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('选集'), findsOneWidget);
      expect(find.text('第 1 集'), findsOneWidget);
      expect(find.text('第 2 集'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback control bar orders play before rewind',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();

      final playX = tester.getTopLeft(find.text('播放')).dx;
      final rewindX = tester.getTopLeft(find.text('快退 10s')).dx;
      final forwardX = tester.getTopLeft(find.text('快进 10s')).dx;
      final qualityX = tester.getTopLeft(find.text('清晰度')).dx;
      final speedX = tester.getTopLeft(find.text('倍速')).dx;
      final subtitleX = tester.getTopLeft(find.text('字幕')).dx;
      final pagesX = tester.getTopLeft(find.text('分P')).dx;

      expect(playX, lessThan(rewindX));
      expect(rewindX, lessThan(forwardX));
      expect(forwardX, lessThan(qualityX));
      expect(qualityX, lessThan(speedX));
      expect(speedX, lessThan(subtitleX));
      expect(subtitleX, lessThan(pagesX));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback panel handles left and right before seek',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('1.25x'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(harness.platform.seekRatios, isEmpty);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel?.startsWith('tv_panel_'),
        isTrue,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback panel resets scroll per function to selected option',
    (WidgetTester tester) async {
      final pages = List<BiliVideoPageEntry>.generate(
        18,
        (index) => BiliVideoPageEntry(
          cid: 900 + index,
          pageNumber: index + 1,
          title: '长列表 ${index + 1}',
          durationSeconds: 60,
        ),
      );
      final detail = BiliVideoDetail(
        aid: 5001,
        bvid: 'BV1longpages',
        title: '长选集测试',
        ownerMid: 0,
        ownerName: '番剧',
        ownerAvatarUrl: '',
        coverUrl: '',
        description: '',
        publishedAtLabel: null,
        playCountLabel: '1',
        danmakuCountLabel: '1',
        replyCountLabel: '1',
        likeCountLabel: '1',
        coinCountLabel: '1',
        favoriteCountLabel: '1',
        shareCountLabel: '1',
        pages: pages,
      );

      await _pumpPlaybackPage(
        tester,
        detail: detail,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('分P').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      final panelList = tester.widget<ListView>(
        find.byKey(const PageStorageKey<String>('tv-panel-list-pages')),
      );

      Future<void> movePanel(LogicalKeyboardKey key, int count) async {
        for (var index = 0; index < count; index++) {
          await tester.sendKeyEvent(key);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          await tester.pump(const Duration(milliseconds: 180));
        }
      }

      panelList.controller!.jumpTo(
        700.0
            .clamp(0.0, panelList.controller!.position.maxScrollExtent)
            .toDouble(),
      );
      await tester.pump();
      final downwardOffset = panelList.controller!.offset;
      expect(downwardOffset, greaterThan(0));
      final panelListRect = tester.getRect(
        find.byKey(const PageStorageKey<String>('tv-panel-list-pages')),
      );
      var focusedPageNumber = pages.length;
      while (focusedPageNumber > 1) {
        final label = find.text('第 $focusedPageNumber 集');
        if (label.evaluate().isNotEmpty &&
            tester.getRect(label).overlaps(panelListRect)) {
          break;
        }
        focusedPageNumber -= 1;
      }
      expect(focusedPageNumber, greaterThan(3));
      final focusedPage = find
          .ancestor(
            of: find.text('第 $focusedPageNumber 集'),
            matching: find.byType(TvFocusable),
          )
          .last;
      tester
          .widget<Focus>(
            find
                .descendant(of: focusedPage, matching: find.byType(Focus))
                .first,
          )
          .focusNode
          ?.requestFocus();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'tv_panel_第 $focusedPageNumber 集',
      );

      await movePanel(LogicalKeyboardKey.arrowUp, focusedPageNumber - 1);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_第 1 集');
      expect(panelList.controller!.offset, lessThan(downwardOffset));
      expect(
        tester.getRect(find.text('第 1 集')).overlaps(panelListRect),
        isTrue,
      );

      await tester.drag(find.byType(Scrollable).last, const Offset(0, -520));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .ancestor(
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_1.0x');
      expect(find.text('1.0x'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback back closes panel then controls before leaving the page',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('1.25x'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('1.25x'), findsNothing);
      expect(find.byType(BiliPlaybackPage), findsOneWidget);
      expect(find.byType(BiliTvHomePage), findsNothing);
      expect(find.text('退出 Vesper？'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('倍速'), findsNothing);
      expect(find.byType(BiliPlaybackPage), findsOneWidget);
      expect(find.byType(BiliTvHomePage), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback Android back closes one layer and restores focus',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.tapAt(const Offset(600, 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('倍速').last,
              matching: find.byType(TvFocusable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('1.25x'), findsOneWidget);

      await tester.sendKeyEvent(
        LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pump();
      expect(find.text('1.25x'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('1.25x'), findsNothing);
      expect(find.text('倍速'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_speed_button');
      expect(find.byType(BiliPlaybackPage), findsOneWidget);

      await tester.sendKeyEvent(
        LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pump();
      expect(find.text('倍速'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('倍速'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_playback');
      expect(find.byType(BiliPlaybackPage), findsOneWidget);
      expect(find.byType(BiliTvHomePage), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback back dismisses a modal notice without leaving playback',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );
      harness.platform.failSelectedSourcesRemaining = 3;
      harness.platform.emitPlaybackError(_expiredPlaybackAddressError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('播放地址刷新失败'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('bili-tv-dialog-surface')),
        findsOneWidget,
      );
      expect(find.byType(GlassDialog), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_知道了');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('播放地址刷新失败'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('播放地址刷新失败'), findsNothing);
      expect(find.byType(BiliPlaybackPage), findsOneWidget);
      expect(find.byType(BiliTvHomePage), findsNothing);
      expect(find.text('退出 Vesper？'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback root back returns to tv home',
    (WidgetTester tester) async {
      final previousPlatform = VesperPlayerPlatform.instance;
      VesperPlayerPlatform.instance = _FakePlaybackVesperPlatform();
      addTearDown(() {
        VesperPlayerPlatform.instance = previousPlatform;
      });

      final root = Directory(
        '${Directory.systemTemp.path}/bili-tv-root-back-test-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: BiliPlaybackPage(
            detail: _playbackDetail(),
            initialPage: _playbackDetail().pages.first,
            client: _FakePlaybackClient(),
            historyStore: BiliHistoryStore(baseDirectory: root),
            initialResolvedPlayback: _resolvedPlaybackFor(
              _playbackDetail(),
              _playbackDetail().pages.first,
            ),
            presentationMode: BiliPlaybackPresentationMode.tv,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(BiliTvHomePage), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback remote back pops to existing tv home without exiting',
    (WidgetTester tester) async {
      final previousPlatform = VesperPlayerPlatform.instance;
      VesperPlayerPlatform.instance = _FakePlaybackVesperPlatform();
      addTearDown(() {
        VesperPlayerPlatform.instance = previousPlatform;
      });

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

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('feed_BVTV00000000')));
      await _flushRealAsync(tester);
      await tester.pumpAndSettle();

      expect(find.byType(BiliPlaybackPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(BiliTvHomePage), findsOneWidget);
      expect(find.byType(BiliPlaybackPage), findsNothing);
      expect(find.text('退出 Vesper？'), findsNothing);
      expect(
        platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
        isEmpty,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback hidden controls use left and right for ten second seeks',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(
        harness.platform.seekRatios.single,
        closeTo(10000 / 120000, 0.001),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tv playback hidden controls keep seek and play pause shortcuts invisible',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      expect(find.text('播放'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_playback');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(harness.platform.seekRatios, hasLength(2));
      expect(harness.platform.seekRatios.first, closeTo(10000 / 120000, 0.001));
      expect(harness.platform.seekRatios.last, 0);
      expect(find.text('播放'), findsNothing);

      final playCallsBeforeShortcut = harness.platform.playCalls;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(harness.platform.playCalls, playCallsBeforeShortcut + 1);
      expect(find.text('播放'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_playback');

      harness.platform.emitSnapshot(_playingPlaybackSnapshot);
      await _flushRealAsync(tester);
      await tester.pump();
      final pauseCallsBeforeShortcut = harness.platform.pauseCalls;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(harness.platform.pauseCalls, pauseCallsBeforeShortcut + 1);
      expect(find.text('暂停'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_playback');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
