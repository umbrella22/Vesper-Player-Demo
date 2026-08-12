part of '../widget_test.dart';

void _registerPlaybackRecoveryWidgetTests() {
  testWidgets(
    'playback reparses an expired address three times before showing a dialog',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);
      harness.platform.failSelectedSourcesRemaining = 3;

      harness.platform.emitPlaybackError(_expiredPlaybackAddressError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
        _playbackPageOne.cid,
        _playbackPageOne.cid,
      ]);
      expect(harness.platform.selectedSources, hasLength(3));
      expect(find.text('播放地址刷新失败'), findsOneWidget);
      expect(find.textContaining('重试 3 次'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GlassDialog),
          matching: find.text('重新解析'),
        ),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'manual reparse does not reuse the expired initial address',
    (WidgetTester tester) async {
      const decodeError = VesperPlayerError(
        message: 'decoder failed',
        code: VesperPlayerErrorCode.decodeFailure,
        category: VesperPlayerErrorCategory.decode,
        retriable: false,
      );
      final harness = await _pumpPlaybackPage(
        tester,
        initialSnapshot: _playbackSnapshot.copyWith(lastError: decodeError),
      );

      await tester.tap(find.text('重新解析'));
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt += 1) {
          if (harness.client.resolvedPlaybackRequests.isNotEmpty) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      expect(harness.platform.refreshCalls, 0);
      expect(harness.platform.clearSystemPlaybackCalls, 1);
      expect(harness.platform.disposeCalls, 1);
      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'iOS HTTP failure evidence triggers Bilibili address reparse',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitPlaybackError(_iosExpiredPlaybackAddressError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(seconds: 5));

      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
      ]);
      expect(harness.platform.selectedSources, hasLength(1));
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'unrelated iOS platform failures do not trigger address reparse',
    (WidgetTester tester) async {
      const platformError = VesperPlayerError(
        message: 'platform channel failed',
        code: VesperPlayerErrorCode.backendFailure,
        category: VesperPlayerErrorCategory.platform,
        retriable: false,
      );
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitPlaybackError(platformError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(harness.client.resolvedPlaybackRequests, isEmpty);
      expect(harness.platform.selectedSources, isEmpty);
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'transient network failures do not trigger address reparse',
    (WidgetTester tester) async {
      const networkError = VesperPlayerError(
        message: 'network timeout',
        code: VesperPlayerErrorCode.backendFailure,
        category: VesperPlayerErrorCategory.network,
        retriable: true,
        details: <String, Object?>{
          'errorCodeName': 'ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT',
        },
      );
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitPlaybackError(networkError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(harness.client.resolvedPlaybackRequests, isEmpty);
      expect(harness.platform.selectedSources, isEmpty);
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'FairPlay license failures do not trigger media address reparse',
    (WidgetTester tester) async {
      const licenseError = VesperPlayerError(
        message: 'FairPlay license request failed',
        code: VesperPlayerErrorCode.backendFailure,
        category: VesperPlayerErrorCategory.network,
        retriable: true,
        details: <String, Object?>{
          'keySystem': 'fairPlay',
          'httpStatusCode': '503',
        },
      );
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitPlaybackError(licenseError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(harness.client.resolvedPlaybackRequests, isEmpty);
      expect(harness.platform.selectedSources, isEmpty);
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'switching pages invalidates an in-flight address recovery',
    (WidgetTester tester) async {
      final blockedRecovery = Completer<BiliResolvedPlayback>();
      final harness = await _pumpPlaybackPage(
        tester,
        configureClient: (client) {
          client.blockedPlaybackResolutions[_playbackPageOne.cid] =
              blockedRecovery;
        },
      );

      harness.platform.emitPlaybackError(_expiredPlaybackAddressError);
      await tester.pump();
      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
      ]);

      await tester.tap(find.text('合集 · 共 3 个分 P'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P2'));
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt += 1) {
          if (harness.client.resolvedPlaybackRequests.contains(
            _playbackPageTwo.cid,
          )) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();

      expect(harness.client.resolvedPlaybackRequests, <int>[
        _playbackPageOne.cid,
        _playbackPageTwo.cid,
      ]);
      expect(
        harness.platform.selectedSources.map((source) => source.uri),
        <String>['https://example.test/${_playbackPageTwo.cid}.mp4'],
      );

      blockedRecovery.complete(
        _resolvedPlaybackFor(_playbackDetail(), _playbackPageOne),
      );
      await tester.pump();
      await tester.pump();

      expect(
        harness.platform.selectedSources.map((source) => source.uri),
        <String>['https://example.test/${_playbackPageTwo.cid}.mp4'],
      );
      expect(find.text('播放地址刷新失败'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback page opens page collection from a bottom sheet',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester);

      expect(find.text('播放页测试视频'), findsWidgets);
      expect(find.text('这是一段播放页说明，下面应直接显示合集列表。'), findsOneWidget);
      expect(find.text('合集 · 共 3 个分 P'), findsOneWidget);
      expect(find.text('P1 · 正片'), findsOneWidget);
      expect(find.text('P2'), findsNothing);
      expect(find.text('简介'), findsOneWidget);
      expect(find.text('相关推荐'), findsOneWidget);
      expect(find.text('相关视频 1'), findsOneWidget);
      expect(find.text('播放 SDK'), findsNothing);
      expect(find.text('Manifest'), findsNothing);

      await tester.tap(find.text('合集 · 共 3 个分 P'));
      await tester.pumpAndSettle();

      expect(find.text('P2'), findsOneWidget);
      expect(find.text('花絮'), findsOneWidget);
      expect(find.text('P3'), findsOneWidget);
      expect(find.text('访谈'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback engagement stays in the intro stream below the context tabs',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester);

      expect(
        find.byKey(const ValueKey<String>('playback-shell-engagement-bar')),
        findsNothing,
      );
      final tabsRect = tester.getRect(find.byType(TabBar));
      final engagementRect = tester.getRect(
        find.byKey(const ValueKey<String>('bili-intro-engagement-bar')),
      );
      final titleRect = tester.getRect(
        find.byKey(const ValueKey<String>('playback-intro-title')),
      );
      expect(engagementRect.top, greaterThan(tabsRect.bottom));
      expect(engagementRect.top, greaterThan(titleRect.bottom));
      final actionRects = <Rect>[
        for (final action in <String>[
          'like',
          'coin',
          'favorite',
          'share',
          'watchLater',
        ])
          tester.getRect(find.byKey(ValueKey<String>('engagement-$action'))),
      ];
      final actionRowTop = actionRects.first.top;
      final actionWidth = actionRects.first.width;
      for (final action in <String>[
        'coin',
        'favorite',
        'share',
        'watchLater',
      ]) {
        final rect = tester.getRect(
          find.byKey(ValueKey<String>('engagement-$action')),
        );
        expect(rect.top, closeTo(actionRowTop, 0.5));
        expect(rect.width, closeTo(actionWidth, 0.5));
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback context tabs center labels and use a compact leading inset',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, surfaceSize: const Size(390, 640));

      final tabBarFinder = find.byType(TabBar);
      final introTabFinder = find.byKey(
        const ValueKey<String>('playback-intro-tab'),
      );
      final commentsTabFinder = find.byKey(
        const ValueKey<String>('playback-comments-tab'),
      );
      final tabBar = tester.widget<TabBar>(tabBarFinder);

      expect(tabBar.tabAlignment, TabAlignment.start);
      expect(tabBar.labelPadding, const EdgeInsets.symmetric(horizontal: 12));
      expect(
        tester.getCenter(find.text('简介')).dx,
        closeTo(tester.getCenter(introTabFinder).dx, 0.5),
      );
      expect(
        tester.getCenter(find.text('评论 78')).dx,
        closeTo(tester.getCenter(commentsTabFinder).dx, 0.5),
      );
      expect(
        tester.getTopLeft(introTabFinder).dx -
            tester.getTopLeft(tabBarFinder).dx,
        lessThan(24),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'mobile playback surfaces and text follow the dark visual theme',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        theme: AppVisualTokens.mobileDarkTheme(),
      );

      final bottomSurface = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey<String>('playback-bottom-surface')),
      );
      final bottomDecoration = bottomSurface.decoration as BoxDecoration;
      final collapsedBar = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey<String>('playback-collapsed-bar')),
      );
      final collapsedDecoration = collapsedBar.decoration as BoxDecoration;
      final title = tester.widget<Text>(
        find.byKey(const ValueKey<String>('playback-intro-title')),
      );

      expect(bottomDecoration.color, AppVisualTokens.darkSurface);
      expect(collapsedDecoration.color, AppVisualTokens.darkSurface);
      expect(title.style?.color, AppVisualTokens.darkTextPrimary);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback intro hides expand control for empty and fitting descriptions',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        detail: _playbackDetailWith(description: ''),
      );

      expect(
        find.byKey(const ValueKey<String>('playback-intro-expand')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        detail: _playbackDetailWith(description: '当前空间可以完整展示的简短简介。'),
      );

      expect(
        find.byKey(const ValueKey<String>('playback-intro-expand')),
        findsNothing,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback intro expand aligns with title first line and toggles overflow',
    (WidgetTester tester) async {
      final detail = _playbackDetailWith(
        title: '这是一个会换到第二行但展开按钮仍需对齐第一行的播放页测试标题',
        description:
            '这是一段需要折叠的长简介内容，用来验证简介在三行空间不足时才显示展开按钮。'
            '继续补充足够多的文字，让它在手机宽度下稳定超过三行，同时确保展开后可以展示全部内容。'
            '最后再增加一段文字，避免不同字体度量导致简介刚好落在三行以内。',
      );
      await _pumpPlaybackPage(
        tester,
        surfaceSize: const Size(390, 640),
        detail: detail,
      );

      final titleFinder = find.byKey(
        const ValueKey<String>('playback-intro-title'),
      );
      final expandFinder = find.byKey(
        const ValueKey<String>('playback-intro-expand'),
      );
      final descriptionFinder = find.byKey(
        const ValueKey<String>('playback-intro-description'),
      );
      final iconFinder = find.descendant(
        of: expandFinder,
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      );
      final iconButtonFinder = find.descendant(
        of: expandFinder,
        matching: find.byType(IconButton),
      );
      expect(expandFinder, findsOneWidget);
      expect(tester.widget<Text>(descriptionFinder).maxLines, 3);
      expect(tester.getSize(iconButtonFinder), const Size(40, 40));

      final titleContext = tester.element(titleFinder);
      final titleStyle = tester.widget<Text>(titleFinder).style;
      final titleLinePainter = TextPainter(
        text: TextSpan(text: 'M', style: titleStyle),
        maxLines: 1,
        textDirection: Directionality.of(titleContext),
        textScaler: MediaQuery.textScalerOf(titleContext),
        locale: Localizations.maybeLocaleOf(titleContext),
      )..layout();
      final expectedIconCenterY =
          tester.getTopLeft(titleFinder).dy +
          titleLinePainter.preferredLineHeight / 2;
      expect(
        tester.getCenter(iconFinder).dy,
        closeTo(expectedIconCenterY, 0.5),
      );
      expect(
        tester.getCenter(iconButtonFinder).dy,
        closeTo(expectedIconCenterY, 0.5),
      );

      await tester.tap(iconButtonFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(descriptionFinder).maxLines, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: expandFinder,
                matching: find.byType(IconButton),
              ),
            )
            .tooltip,
        '收起简介',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback resumes an unfinished history position before autoplay',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester, initialPositionMs: 45000);

      expect(harness.platform.seekDeltas, <int>[45000]);
      expect(harness.platform.playCalls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback exit records the current progress into history',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      harness.platform.emitSnapshot(
        _playingPlaybackSnapshot.copyWith(
          timeline: const VesperTimeline(
            kind: VesperTimelineKind.vod,
            isSeekable: true,
            seekableRange: null,
            liveEdgeMs: null,
            positionMs: 30000,
            durationMs: 120000,
          ),
        ),
      );
      await tester.pump();
      await _flushRealAsync(tester);

      // 退出播放页：dispose 路径持久化当前进度。
      await tester.pumpWidget(const SizedBox.shrink());
      List<BiliPlaybackHistoryEntry> entries =
          const <BiliPlaybackHistoryEntry>[];
      for (var attempt = 0; attempt < 10 && entries.isEmpty; attempt += 1) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        entries =
            await tester.runAsync(() => harness.historyStore.loadEntries()) ??
            const <BiliPlaybackHistoryEntry>[];
      }

      expect(entries, hasLength(1));
      expect(entries.single.bvid, 'BV1playback01');
      expect(entries.single.cid, 101);
      expect(entries.single.lastPositionMs, 30000);
      expect(entries.single.durationMs, 120000);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'android playback enables source normalizer without frame processor',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      expect(
        harness.platform.lastSourceNormalizerConfiguration?.mode,
        VesperSourceNormalizerMode.preferNormalized,
      );
      expect(
        harness.platform.lastSourceNormalizerConfiguration?.pluginReferences,
        <VesperPluginReference>[
          VesperBundledPluginReferences.sourceNormalizerFfmpeg,
        ],
      );
      expect(
        harness.platform.lastFrameProcessorConfiguration?.mode,
        VesperFrameProcessorMode.disabled,
      );
      expect(
        harness.platform.lastFrameProcessorConfiguration?.pluginReferences,
        isEmpty,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'pgc playback page hides engagement actions and owner summary',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester, detail: _pgcPlaybackDetail());

      expect(find.text('番剧播放页测试'), findsWidgets);
      expect(find.text('番剧简介下方应直接显示剧集。'), findsOneWidget);
      expect(find.text('剧集 · 共 3 话/集'), findsOneWidget);
      expect(find.text('第 1 话 · 正片'), findsOneWidget);
      expect(find.text('第 2 话'), findsNothing);
      expect(find.text('点赞'), findsNothing);
      expect(find.text('硬币'), findsNothing);
      expect(find.text('收藏'), findsNothing);
      expect(find.text('分享'), findsNothing);
      // PGC 保留图标化的稍后再看入口（互动动作栏仅声明 watchLater）。
      expect(
        find.byKey(const ValueKey<String>('engagement-watchLater')),
        findsOneWidget,
      );
      expect(find.text('加入稍后再看'), findsNothing);
      expect(find.widgetWithText(FilledButton, '关注'), findsNothing);
      expect(find.text('播放页UP'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback engagement actions are icon-only and pending disables follow',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);
      final followCompleter = Completer<BiliVideoEngagement>();
      harness.client.followCompleter = followCompleter;

      for (final action in <String>[
        'like',
        'coin',
        'favorite',
        'share',
        'watchLater',
      ]) {
        expect(
          find.byKey(ValueKey<String>('engagement-$action')),
          findsOneWidget,
        );
      }
      for (final label in <String>['点赞', '硬币', '收藏', '分享', '加入稍后再看']) {
        expect(find.text(label), findsNothing);
      }
      final semantics = tester.ensureSemantics();
      for (final label in <String>[
        '点赞 1.1万',
        '硬币 234',
        '收藏 345',
        '分享 56',
        '加入稍后再看',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('点赞 1.1万')),
        matchesSemantics(
          label: '点赞 1.1万',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
        ),
      );
      semantics.dispose();
      expect(find.widgetWithText(FilledButton, '关注'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '关注'))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.widgetWithText(FilledButton, '关注'));
      await tester.pump();

      expect(harness.client.followRequests, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '关注'))
            .onPressed,
        isNull,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(FilledButton, '关注'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      followCompleter.complete(
        harness.client.engagement.copyWith(isFollowingOwner: true),
      );
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback coin action posts through the view model',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      await tester.tap(find.byKey(const ValueKey<String>('engagement-coin')));
      await tester.pump();

      expect(harness.client.coinRequests, 1);
      expect(harness.client.engagement.isLiked, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback watch later prompts for login before mutating',
    (WidgetTester tester) async {
      await _pumpPlaybackPage(tester);

      expect(find.text('加入稍后再看'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey<String>('engagement-watchLater')),
      );
      await tester.pump();

      expect(find.text('请先登录 Bilibili 后使用稍后再看。'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback comments render nested replies and seek time links',
    (WidgetTester tester) async {
      final harness = await _pumpPlaybackPage(tester);

      await tester.tap(find.text('评论 78'));
      await tester.pumpAndSettle();

      expect(find.text('热门评论'), findsOneWidget);
      expect(find.text('神代强丸'), findsOneWidget);
      expect(find.textContaining('不像韩女', findRichText: true), findsOneWidget);
      expect(find.textContaining('立在哪里无寒冬'), findsOneWidget);
      expect(find.text('共3条回复 >'), findsOneWidget);

      final replyPreview = find.ancestor(
        of: find.text('共3条回复 >'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material &&
              widget.color == AppVisualTokens.mobileSurfaceMuted,
        ),
      );
      final commentRow = find.ancestor(
        of: find.text('共3条回复 >'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Row &&
              widget.crossAxisAlignment == CrossAxisAlignment.start,
        ),
      );
      expect(replyPreview, findsOneWidget);
      expect(commentRow, findsOneWidget);
      expect(
        tester.getSize(replyPreview).width,
        closeTo(tester.getSize(commentRow).width - 50, 0.1),
      );
      final modalBarrierCountBefore = find
          .byType(ModalBarrier)
          .evaluate()
          .length;

      await tester.tap(find.text('共3条回复 >'));
      await tester.pumpAndSettle();

      expect(find.text('评论详情'), findsOneWidget);
      expect(find.text('相关回复共3条'), findsOneWidget);
      expect(
        find.byType(ModalBarrier).evaluate().length,
        modalBarrierCountBefore,
      );

      await tester.tap(find.byTooltip('关闭评论详情'));
      await tester.pumpAndSettle();

      final messageFinder = find.textContaining(
        '01:00 不像韩女',
        findRichText: true,
      );
      await tester.tapAt(tester.getTopLeft(messageFinder) + const Offset(8, 8));
      await tester.pump();

      expect(harness.platform.seekRatios, isNotEmpty);
      expect(harness.platform.seekRatios.last, moreOrLessEquals(0.5));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
