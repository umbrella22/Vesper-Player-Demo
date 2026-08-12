part of '../widget_test.dart';

void _registerPlaybackCommentsWidgetTests() {
  testWidgets(
    'playback comment replies load the next page near the list end',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        configureClient: (client) {
          client.commentReplyPages
            ..clear()
            ..[1] = List<BiliVideoComment>.generate(
              20,
              (index) => _playbackCommentReply(
                id: 700 + index,
                authorName: '楼中楼用户${index + 1}',
                message: '楼中楼第${index + 1}条',
              ),
            )
            ..[2] = <BiliVideoComment>[
              _playbackCommentReply(
                id: 720,
                authorName: '楼中楼用户21',
                message: '楼中楼第21条',
              ),
            ];
          client.commentReplyTotalCount = 21;
        },
      );

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('共3条回复 >'));
      await tester.pumpAndSettle();

      expect(harness.client.commentReplyPageRequests, <int>[1]);
      expect(find.text('相关回复共21条'), findsOneWidget);
      final repliesList = find.byKey(
        const PageStorageKey<String>('playback-comment-replies'),
      );
      final repliesScrollable = find.descendant(
        of: repliesList,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('playback-comment-reply-719')),
        400,
        scrollable: repliesScrollable,
      );
      await tester.pumpAndSettle();

      expect(harness.client.commentReplyPageRequests, <int>[1, 2]);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('playback-comment-reply-720')),
        300,
        scrollable: repliesScrollable,
      );
      expect(
        find.textContaining('楼中楼第21条', findRichText: true),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'mobile comment replies stay below the playing video',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        initialSnapshot: _playingPlaybackSnapshot,
      );

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-comments')),
        const Offset(0, -360),
      );
      await tester.pumpAndSettle();
      final modalBarrierCountBefore = find
          .byType(ModalBarrier)
          .evaluate()
          .length;
      await tester.tap(find.text('共3条回复 >'));
      await tester.pumpAndSettle();

      final stageRect = tester.getRect(
        find.byType(vesper_ui.VesperPlayerStage),
      );
      final replyHeaderRect = tester.getRect(
        find.byKey(const ValueKey<String>('playback-comment-replies-header')),
      );
      expect(
        find.byType(ModalBarrier).evaluate().length,
        modalBarrierCountBefore,
      );
      expect(replyHeaderRect.top, greaterThanOrEqualTo(stageRect.bottom));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'mobile comments keep tabs fixed and fade in collapsed playback bar',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(390, 640));

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();

      final collapsedOpacityBefore = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('继续播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-comments')),
        const Offset(0, -420),
      );
      await tester.pump();
      await tester.pump();

      final collapsedOpacityAfter = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('继续播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      expect(find.text('简介'), findsOneWidget);
      expect(find.text('评论 78'), findsOneWidget);
      expect(collapsedOpacityAfter, greaterThan(collapsedOpacityBefore));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback info tabs switch with horizontal swipes',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(390, 640));

      // 互动动作栏属于简介流，简介列表向下滚动使分 P 入口可见。
      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-related')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      expect(find.text('合集 · 共 3 个分 P'), findsOneWidget);
      expect(find.text('热门评论'), findsNothing);

      await tester.drag(find.byType(TabBarView), const Offset(-320, 0));
      await tester.pumpAndSettle();

      expect(find.text('热门评论'), findsOneWidget);
      expect(find.text('神代强丸'), findsOneWidget);

      await tester.drag(find.byType(TabBarView), const Offset(320, 0));
      await tester.pumpAndSettle();

      expect(find.text('合集 · 共 3 个分 P'), findsOneWidget);
      expect(find.text('热门评论'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback comments load more near the bottom',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        configureClient: (client) {
          client.extraComments.add(
            const BiliVideoComment(
              id: 901,
              authorName: '第二页用户',
              authorAvatarUrl: '',
              createdAtLabel: '1分钟前',
              message: '第二页评论',
              likeCountLabel: '0',
              pictures: <BiliCommentPicture>[],
              replies: <BiliVideoComment>[],
              timeLinks: <BiliCommentTimeLink>[],
            ),
          );
        },
      );

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-comments')),
        const Offset(0, -620),
      );
      await _pumpUntil(
        tester,
        () => harness.client.commentPageRequests.contains(2),
      );
      await tester.pumpAndSettle();

      expect(harness.client.commentPageRequests, contains(2));
      expect(find.text('第二页用户'), findsOneWidget);
      expect(find.text('第二页评论', findRichText: true), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'mobile playback stage stays expanded while lists scroll during playback',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        initialSnapshot: _playingPlaybackSnapshot,
      );

      final collapsedOpacityBefore = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('正在播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      final stageFinder = find.byType(vesper_ui.VesperPlayerStage);
      final stageSizeBefore = tester.getSize(stageFinder);

      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-related')),
        const Offset(0, -420),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final collapsedOpacityAfter = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('正在播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      expect(collapsedOpacityAfter, collapsedOpacityBefore);
      expect(tester.getSize(stageFinder), stageSizeBefore);

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey<String>('playback-comments')),
        const Offset(0, -420),
      );
      await tester.pump();
      await tester.pump();

      final commentsCollapsedOpacity = tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('正在播放'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;
      expect(commentsCollapsedOpacity, collapsedOpacityBefore);
      expect(tester.getSize(stageFinder), stageSizeBefore);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback comment composer is fixed and sends from keyboard action',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '好看，支持一下');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(harness.client.sentComments, <String>['好看，支持一下']);
      expect(find.text('当前用户'), findsOneWidget);
      expect(find.text('好看，支持一下', findRichText: true), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback settings omit system playback controls',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('播放设置'), findsOneWidget);
      expect(find.text('分辨率'), findsOneWidget);
      expect(find.text('离线缓存'), findsOneWidget);
      expect(find.text('系统播放'), findsNothing);
      expect(find.text('锁屏控制'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback settings select an SDK external subtitle track',
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
              id: 'subtitle:bili:3',
              kind: VesperMediaTrackKind.subtitle,
              label: '中文（中国大陆）',
              language: 'zh-CN',
              isDefault: true,
            ),
          ],
        ),
      );
      final harness = await _pumpPlaybackPage(
        tester,
        initialSnapshot: subtitleSnapshot,
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('中文（中国大陆）'));
      await tester.pump();

      expect(harness.platform.subtitleSelections, hasLength(1));
      expect(
        harness.platform.subtitleSelections.single.mode,
        VesperTrackSelectionMode.track,
      );
      expect(
        harness.platform.subtitleSelections.single.trackId,
        'subtitle:bili:3',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback settings show empty copy when resolution has no options',
    (WidgetTester tester) async {
      final base = _resolvedPlaybackFor(_playbackDetail(), _playbackPageOne);
      await _pumpPlaybackPage(
        tester,
        initialResolvedPlayback: BiliResolvedPlayback(
          bvid: base.bvid,
          cid: base.cid,
          title: base.title,
          subtitle: base.subtitle,
          uri: base.uri,
          protocol: base.protocol,
          transportLabel: base.transportLabel,
          isLocalFile: base.isLocalFile,
          videoTracks: const <VesperMediaTrack>[],
          subtitleTracks: const <BiliSubtitleTrack>[],
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('当前播放链路无可选清晰度。'), findsOneWidget);
      expect(find.text('当前视频没有可用字幕。'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback speed panel applies and restores playback rate',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1.25x'));
      await tester.pump();
      expect(harness.platform.playbackRates, <double>[1.25]);

      await tester.tap(find.text('1.0x'));
      await tester.pump();
      expect(harness.platform.playbackRates, <double>[1.25, 1.0]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback page lays out at compact phone size without overflow',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(360, 640));

      expect(find.text('播放页测试视频'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback page lays out at standard phone size without overflow',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(390, 844));

      expect(find.text('播放页测试视频'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback page lays out at wide landscape size without overflow',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(1920, 1080));

      expect(find.text('播放页测试视频'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback fullscreen locks landscape and back restores portrait',
    (WidgetTester tester) async {
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

      await _pumpPlaybackPage(tester);

      List<List<String>> orientationCalls() {
        return platformCalls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .map((call) => (call.arguments as List<Object?>).cast<String>())
            .toList();
      }

      expect(orientationCalls().last, <String>['DeviceOrientation.portraitUp']);

      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pump();

      expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
      expect(orientationCalls().last, <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
      expect(find.text('播放页测试视频'), findsWidgets);
      expect(orientationCalls().last, <String>['DeviceOrientation.portraitUp']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'dlna load failure disconnects and keeps picker open',
    (WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter/platform_views'),
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
            case 'dispose':
            case 'offset':
            case 'touch':
            case 'setDirection':
            case 'clearFocus':
              return null;
          }
          return null;
        },
      );
      final externalPlayback = _ExternalPlaybackHarness(
        loadResult: const <String, Object?>{
          'status': 'unsupported',
          'message':
              'Host-prepared relay remux v1 only accepts remote HTTP(S) DASH sources.',
        },
      )..install();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('flutter/platform_views'),
          null,
        );
        externalPlayback.uninstall();
        debugDefaultTargetPlatformOverride = null;
      });

      await _pumpPlaybackPage(tester, externalPlaybackMockInstalled: true);

      await tester.tap(find.byIcon(Icons.cast_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      await tester.tap(find.text('DLNA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      externalPlayback.emitDlnaRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));

      expect(find.text('Living Room TV'), findsOneWidget);

      await tester.tap(find.text('Living Room TV'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('DLNA 投屏'), findsOneWidget);
      expect(
        find.text(
          'Host-prepared relay remux v1 only accepts remote HTTP(S) DASH sources.',
        ),
        findsWidgets,
      );
      expect(
        externalPlayback.calls.map((call) => call.method),
        contains('disconnect'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'tv playback locks landscape and touch toggles controls',
    (WidgetTester tester) async {
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

      await _pumpPlaybackPage(
        tester,
        presentationMode: BiliPlaybackPresentationMode.tv,
      );

      List<List<String>> orientationCalls() {
        return platformCalls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .map((call) => (call.arguments as List<Object?>).cast<String>())
            .toList();
      }

      expect(orientationCalls().last, <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      expect(find.text('快退 10s'), findsNothing);

      await tester.tapAt(const Offset(600, 450));
      await tester.pump();

      expect(find.text('快退 10s'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
