import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_library_page.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/media/tv/media_tv_focusable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:vesper_player/vesper_player.dart';

const _librarySessionCookies = <String, String>{
  'SESSDATA': 'sess',
  'bili_jct': 'csrf',
  'DedeUserID': '42',
  'buvid3': 'b3',
  'buvid4': 'b4',
};

void main() {
  test('parses following, remote history, and watch-later payloads', () async {
    final httpClient = _LibraryHttpClient();
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final following = await client.fetchFollowingUsers();
    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(following.single.mid, 7);
    expect(following.single.avatarUrl, 'https://example.com/avatar.jpg');
    expect(history.single.bvid, 'BV1history');
    expect(history.single.durationMs, 120000);
    expect(history.single.progressMs, 45000);
    expect(history.single.viewedAtMs, 1710000000000);
    expect(watchLater.single.pageTitle, 'P2');
    expect(watchLater.single.durationMs, 90000);
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      containsAll(<String>[
        '/x/relation/followings',
        '/x/web-interface/history/cursor',
        '/x/v2/history/toview/web',
      ]),
    );
  });

  test(
    'account-only follow and space APIs reject before transport warm-up',
    () async {
      final httpClient = _LibraryHttpClient();
      final client = BiliClient(httpClient: httpClient);
      addTearDown(() => client.transport.httpClient.close(force: true));

      final matcher = isA<BiliApiException>().having(
        (error) => error.code,
        'code',
        -101,
      );
      await expectLater(client.fetchFollowingUsers(), throwsA(matcher));
      await expectLater(client.fetchUserSpaceProfile(7), throwsA(matcher));
      await expectLater(client.fetchUserSpaceVideos(mid: 7), throwsA(matcher));
      await expectLater(
        client.fetchUserSpaceVideoByBvid(mid: 7, bvid: 'BV1space0001'),
        throwsA(matcher),
      );

      expect(httpClient.requestedUris, isEmpty);
    },
  );

  test('parses user-space profile and archive list', () async {
    final httpClient = _LibraryHttpClient();
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final profile = await client.fetchUserSpaceProfile(7);
    final page = await client.fetchUserSpaceVideos(mid: 7, keyword: '空间');

    expect(profile.name, '测试 UP 空间');
    expect(profile.followerCount, 12000);
    expect(profile.archiveCount, 3);
    expect(page.videos.single.bvid, 'BV1space0001');
    expect(page.videos.single.durationLabel, '02:03');
    expect(page.videos.single.playCountLabel, '1.2万');
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      containsAll(<String>['/x/web-interface/card', '/x/space/wbi/arc/search']),
    );
  });

  test('exact BV lookup rejects a video owned by another UP', () async {
    final httpClient = _LibraryHttpClient(spaceVideoOwnerMid: 999);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final result = await client.fetchUserSpaceVideoByBvid(
      mid: 7,
      bvid: 'BV1space0001',
    );

    expect(result, isNull);
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      contains('/x/web-interface/view'),
    );
  });

  testWidgets('following list loads another ATV page on demand', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(
      multipleFollowingPages: true,
      emptyFollowingAvatars: true,
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await tester.binding.setSurfaceSize(const Size(800, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: BiliLibraryPage(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(find.text('测试 UP 51'), findsOneWidget);
    expect(
      httpClient.requestedUris
          .where((uri) => uri.path == '/x/relation/followings')
          .map((uri) => uri.queryParameters['pn']),
      <String?>['1', '2'],
    );
  });

  testWidgets('tapping a followed UP opens its mobile space page', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(emptyFollowingAvatars: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await tester.pumpWidget(MaterialApp(home: BiliLibraryPage(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试 UP'));

    await _pumpLibraryUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-user-space-video-search')),
    );

    expect(find.text('UP 主空间'), findsOneWidget);
    expect(find.text('测试 UP 空间'), findsOneWidget);
    expect(find.text('空间视频'), findsOneWidget);
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      containsAll(<String>['/x/web-interface/card', '/x/space/wbi/arc/search']),
    );
  });

  testWidgets('mobile space routes title and BV searches to separate APIs', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(emptyFollowingAvatars: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await tester.pumpWidget(MaterialApp(home: BiliLibraryPage(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试 UP'));
    final search = find.byKey(
      const ValueKey<String>('bili-user-space-video-search'),
    );
    await _pumpLibraryUntilFound(tester, search);

    await tester.enterText(search, '空间');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpLibraryUntilFound(tester, find.text('搜索结果'));
    final archiveRequests = httpClient.requestedUris
        .where((uri) => uri.path == '/x/space/wbi/arc/search')
        .toList(growable: false);
    expect(archiveRequests.last.queryParameters['keyword'], '空间');

    await tester.enterText(search, 'BV1other0001');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpLibraryUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-user-space-content')),
    );
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      contains('/x/web-interface/view'),
    );
  });

  testWidgets('TV following browser collapses and restores its UP rail', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(emptyFollowingAvatars: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.tvTheme(),
        home: Scaffold(body: BiliLibraryPage.tvFollowingPane(client: client)),
      ),
    );
    await _pumpLibraryUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
    );
    final videoGrid = find.byKey(
      const ValueKey<String>('bili-tv-space-video-grid'),
    );
    expect(tester.widget<GridView>(videoGrid).clipBehavior, Clip.none);
    final videoSearch = find.byKey(
      const ValueKey<String>('bili-tv-space-video-search'),
    );
    final videoFocusScope = find.byKey(
      const ValueKey<String>('bili-tv-space-video-focus-scope'),
    );
    expect(
      tester.widget<TvFocusOverlayScope>(videoFocusScope).clipBehavior,
      Clip.hardEdge,
    );
    expect(
      tester.getTopLeft(videoFocusScope).dy,
      greaterThan(tester.getBottomLeft(videoSearch).dy),
    );

    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );
    final userFinder = find.byKey(
      const ValueKey<String>('bili-tv-following-user-7'),
    );
    await tester.tap(userFinder);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    final followingSearch = find.byKey(
      const ValueKey<String>('bili-tv-following-search'),
    );
    final followingFocusScope = find.byKey(
      const ValueKey<String>('bili-tv-following-list-focus-scope'),
    );
    expect(
      tester.widget<TvFocusOverlayScope>(followingFocusScope).clipBehavior,
      Clip.hardEdge,
    );
    expect(
      tester.getTopLeft(followingFocusScope).dy,
      greaterThan(tester.getBottomLeft(followingSearch).dy),
    );
    await tester.enterText(followingSearch, '测试');
    await tester.tap(userFinder);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();

    int requestCount(String path) =>
        httpClient.requestedUris.where((uri) => uri.path == path).length;
    final followingRequests = requestCount('/x/relation/followings');
    final profileRequests = requestCount('/x/web-interface/card');
    final archiveRequests = requestCount('/x/space/wbi/arc/search');
    expect(followingRequests, 1);
    expect(profileRequests, 1);
    expect(archiveRequests, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-collapsed')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(AppVisualTokens.tvFocusDuration);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('bili-tv-following-rail-expanded')),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(followingSearch).controller?.text, '测试');
    expect(
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
      findsOneWidget,
    );
    expect(requestCount('/x/relation/followings'), followingRequests);
    expect(requestCount('/x/web-interface/card'), profileRequests);
    expect(requestCount('/x/space/wbi/arc/search'), archiveRequests);
  });

  testWidgets('TV following login clears an UP removed by the refreshed list', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(emptyFollowingAvatars: true)
      ..spaceAuthenticationFailuresRemaining = 1;
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(_librarySessionCookies);
    addTearDown(() => client.transport.httpClient.close(force: true));
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.tvTheme(),
        home: Scaffold(
          body: BiliLibraryPage.tvFollowingPane(
            client: client,
            onLoginTap: () async {
              httpClient.followingEmpty = true;
              client.restoreCookies(_librarySessionCookies);
            },
          ),
        ),
      ),
    );
    await _pumpLibraryUntilFound(tester, find.text('需要重新登录'));

    await tester.tap(find.text('登录'));
    await _pumpLibraryUntilFound(tester, find.text('选择一位 UP 主'));

    expect(
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
      findsNothing,
    );
    expect(httpClient.requestedSpaceMids, <int>[7]);
  });

  testWidgets('TV following login requests only the refreshed first UP', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(emptyFollowingAvatars: true)
      ..spaceAuthenticationFailuresRemaining = 1;
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(_librarySessionCookies);
    addTearDown(() => client.transport.httpClient.close(force: true));
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.tvTheme(),
        home: Scaffold(
          body: BiliLibraryPage.tvFollowingPane(
            client: client,
            onLoginTap: () async {
              httpClient.followingMid = 8;
              client.restoreCookies(_librarySessionCookies);
            },
          ),
        ),
      ),
    );
    await _pumpLibraryUntilFound(tester, find.text('需要重新登录'));

    await tester.tap(find.text('登录'));
    await _pumpLibraryUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0008')),
    );

    expect(
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space0001')),
      findsNothing,
    );
    expect(httpClient.requestedProfileMids, <int>[7, 8]);
    expect(httpClient.requestedSpaceMids, <int>[7, 8]);
  });

  testWidgets('TV following skips stale UP videos after switching users', (
    WidgetTester tester,
  ) async {
    final staleProfileGate = Completer<void>();
    final httpClient = _LibraryHttpClient(
      multipleFollowingPages: true,
      emptyFollowingAvatars: true,
      profileGates: <int, Future<void>>{1000: staleProfileGate.future},
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(_librarySessionCookies);
    addTearDown(() => client.transport.httpClient.close(force: true));
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.tvTheme(),
        home: Scaffold(body: BiliLibraryPage.tvFollowingPane(client: client)),
      ),
    );
    final nextUser = find.byKey(
      const ValueKey<String>('bili-tv-following-user-1001'),
    );
    await _pumpLibraryUntilFound(tester, nextUser);

    await tester.tap(nextUser);
    await _pumpLibraryUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-tv-space-video-BV1space1001')),
    );
    expect(httpClient.requestedProfileMids, <int>[1000, 1001]);
    expect(httpClient.requestedSpaceMids, <int>[1001]);

    staleProfileGate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(httpClient.requestedSpaceMids, <int>[1001]);
  });

  testWidgets('phone library aligns its selected glass tabs with content', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(emptyFollowingAvatars: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: BiliLibraryPage(client: client),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppGlassSectionTabs), findsOneWidget);
    final tabs = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    expect(tabs.quality, isNull);
    expect(tabs.indicatorColor, AppVisualTokens.neutralSelection);
    expect(tabs.selectedLabelColor, AppVisualTokens.textPrimary);

    final toolbarRect = tester.getRect(
      find.byKey(const ValueKey<String>('bili-library-phone-toolbar')),
    );
    final sectionTabsRect = tester.getRect(find.byType(AppGlassSectionTabs));
    final contentRect = tester.getRect(
      find.byKey(const ValueKey<String>('bili-library-phone-content')),
    );
    expect(toolbarRect.top, 24);
    expect(sectionTabsRect.top - toolbarRect.bottom, 12);
    expect(contentRect.top - sectionTabsRect.bottom, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('following list clears account data after logout', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(emptyFollowingAvatars: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await tester.pumpWidget(MaterialApp(home: BiliLibraryPage(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('测试 UP'), findsOneWidget);

    client.clearSession();
    await tester.tap(find.text('历史播放').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('关注').first);
    await tester.pumpAndSettle();

    expect(find.text('测试 UP'), findsNothing);
    expect(find.text('请先登录 Bilibili 后查看此内容。'), findsOneWidget);
  });

  testWidgets('tv history library keeps its dark grid without following', (
    WidgetTester tester,
  ) async {
    final historyRoot = Directory(
      '${Directory.systemTemp.path}/bili-tv-library-history-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      if (await historyRoot.exists()) {
        await historyRoot.delete(recursive: true);
      }
    });
    final httpClient = _LibraryHttpClient(emptyHistoryCovers: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.tvTheme(),
        home: BiliLibraryPage(
          client: client,
          initialSection: BiliLibrarySection.history,
          historyStore: BiliHistoryStore(baseDirectory: historyRoot),
          presentationMode: BiliPlaybackPresentationMode.tv,
        ),
      ),
    );
    await _pumpLibraryUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bili-tv-library-card-history-cid:11')),
    );
    await tester.pump(AppVisualTokens.tvFocusDuration);

    final root = tester.widget<Scaffold>(
      find.byKey(const ValueKey<String>('bili-tv-library-root')),
    );
    expect(root.backgroundColor, AppVisualTokens.tvBackground);
    expect(
      find.byKey(const ValueKey<String>('bili-tv-library-grid-history')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bili-tv-library-card-history-cid:11')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bili-tv-library-tab-following')),
      findsNothing,
    );
    expect(find.text('关注'), findsNothing);

    final selectedSurface = tester.widget<AnimatedContainer>(
      find.byKey(
        const ValueKey<String>('tv-glass-selectable-state-tv_library_tab_历史播放'),
      ),
    );
    final selectedDecoration = selectedSurface.decoration! as BoxDecoration;
    expect(selectedDecoration.color!.a, 0);

    final marker = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('bili-tv-library-tab-marker-历史播放')),
    );
    final markerDecoration = marker.decoration! as BoxDecoration;
    expect(markerDecoration.color, AppVisualTokens.primaryBlue);
    expect(
      find.byKey(const ValueKey<String>('tv-content-glass-overlay')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv_library_history_cid:11',
    );
  });

  testWidgets('tv watch later removal requires confirmation', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(emptyWatchLaterCovers: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.tvTheme(),
        home: BiliLibraryPage(
          client: client,
          initialSection: BiliLibrarySection.watchLater,
          presentationMode: BiliPlaybackPresentationMode.tv,
        ),
      ),
    );
    final card = find.byKey(
      const ValueKey<String>('bili-tv-library-card-watchLater-cid:22'),
    );
    await _pumpLibraryUntilFound(tester, card);

    expect(
      find.byKey(const ValueKey<String>('bili-tv-library-grid-watchLater')),
      findsOneWidget,
    );
    expect(card, findsOneWidget);
    final remove = find.byKey(
      const ValueKey<String>('bili-tv-library-remove-cid:22'),
    );
    expect(remove, findsOneWidget);
    expect(
      find.descendant(of: remove, matching: find.byType(TvFocusableSurface)),
      findsOneWidget,
    );

    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('移出稍后再看？'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_dialog_取消');
    expect(httpClient.posts, isEmpty);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('移出稍后再看？'), findsNothing);
    expect(httpClient.posts, isEmpty);

    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();

    expect(
      httpClient.posts.where(
        (request) => request.uri.path == '/x/v2/history/toview/del',
      ),
      hasLength(1),
    );
  });

  testWidgets('history auth expiry drops cloud rows but keeps local history', (
    WidgetTester tester,
  ) async {
    late final Directory root;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp(
        'bili-library-history-auth-test-',
      );
    });
    addTearDown(() => root.delete(recursive: true));
    final historyStore = BiliHistoryStore(baseDirectory: root);
    await tester.runAsync(
      () => historyStore.saveEntry(
        const BiliPlaybackHistoryEntry(
          bvid: 'BV1history',
          cid: 11,
          videoTitle: '本地历史',
          pageTitle: '本地 P1',
          coverUrl: '',
          ownerName: '本地 UP',
          playedAtMs: 100,
          lastPositionMs: 1000,
        ),
      ),
    );
    final httpClient = _LibraryHttpClient(
      historyPaginationAuthExpires: true,
      emptyHistoryCovers: true,
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: BiliLibraryPage(
          client: client,
          initialSection: BiliLibrarySection.history,
          historyStore: historyStore,
        ),
      ),
    );
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('历史视频').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('历史视频'), findsOneWidget);
    expect(find.text('本地历史'), findsNothing);
    await tester.tap(find.text('加载更多'));
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('本地历史').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('历史视频'), findsNothing);
    expect(find.text('本地历史'), findsOneWidget);
  });

  test('parses clock-formatted duration and progress fields', () async {
    final httpClient = _LibraryHttpClient(durationAsClockLabel: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.durationMs, 125000);
    expect(history.single.progressMs, 90500);
    expect(watchLater.single.durationMs, 90000);
    expect(watchLater.single.progressMs, 1500);
  });

  test('preserves explicit short millisecond duration fields', () async {
    final httpClient = _LibraryHttpClient(explicitMillisecondFields: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.durationMs, 45000);
    expect(history.single.progressMs, 12000);
    expect(watchLater.single.durationMs, 90000);
    expect(watchLater.single.progressMs, 1500);
  });

  test('returns the next web history cursor without losing units', () async {
    final httpClient = _LibraryHttpClient();
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final page = await client.fetchRemoteHistoryPage(pageSize: 30);

    expect(page.entries, hasLength(1));
    expect(page.hasMore, isTrue);
    expect(page.nextMax, 123);
    expect(page.nextViewAtMs, 1709999999000);
  });

  test('accepts legacy history and watch-later oid fields', () async {
    final httpClient = _LibraryHttpClient(legacyHistoryFields: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.aid, 101);
    expect(history.single.bvid, 'BVlegacy');
    expect(history.single.cid, 1001);
    expect(history.single.ownerName, '旧 UP');
    expect(watchLater.single.aid, 202);
    expect(watchLater.single.bvid, 'BVlegacy-later');
    expect(watchLater.single.cid, 2002);
  });

  test('does not reinterpret an episode id as a content id', () async {
    final httpClient = _LibraryHttpClient(episodeIdWithoutCid: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.cid, 0);
    expect(watchLater.single.cid, 0);
    expect(history.single.episodeId, 9001);
    expect(watchLater.single.episodeId, 9002);
    expect(history.single.aid, 101);
    expect(watchLater.single.aid, 202);
  });

  test('uses ATV legacy history endpoints when they return data', () async {
    final httpClient = _LibraryHttpClient(legacyEndpointOnly: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.aid, 101);
    expect(watchLater.single.aid, 202);
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      containsAll(<String>['/x/v2/history', '/x/v2/history/toview']),
    );
  });

  test(
    'sends watch-later mutations with csrf and parses subtitle JSON',
    () async {
      final httpClient = _LibraryHttpClient();
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
          'DedeUserID': '42',
          'buvid3': 'b3',
          'buvid4': 'b4',
        });
      addTearDown(() => client.transport.httpClient.close(force: true));

      await client.addToWatchLater(bvid: 'BV1later');
      await client.removeFromWatchLater(bvid: 'BV1later');
      expect(await client.isVideoInWatchLater(bvid: 'BV1later'), isTrue);
      expect(await client.isVideoInWatchLater(bvid: 'BVmissing'), isFalse);
      final advertised = await client.fetchVideoSubtitleTracks(
        bvid: 'BV1subtitle',
        cid: 99,
      );

      expect(httpClient.posts, hasLength(2));
      expect(httpClient.posts.first.fields['bvid'], 'BV1later');
      expect(httpClient.posts.first.fields['csrf'], 'csrf');
      final addRequest = httpClient.requestHeaders.entries.singleWhere(
        (entry) => entry.key.path == '/x/v2/history/toview/add',
      );
      expect(addRequest.value['cookie'], contains('SESSDATA=sess'));
      expect(advertised.single.language, 'zh-CN');
      expect(advertised.single.url, 'https://subtitle.example/track.json');
    },
  );

  test(
    'materializes Bilibili subtitle JSON as an SDK external WebVTT source',
    () async {
      final httpClient = _LibraryHttpClient();
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
          'DedeUserID': '42',
          'buvid3': 'b3',
          'buvid4': 'b4',
        });
      addTearDown(() => client.transport.httpClient.close(force: true));

      final tracks = await client.fetchVideoSubtitles(
        bvid: 'BV1subtitle',
        cid: 99,
      );
      expect(tracks, hasLength(1));
      final file = File(Uri.parse(tracks.single.url).toFilePath());
      addTearDown(() async {
        if (await file.exists()) {
          await file.delete();
        }
      });
      expect(await file.readAsString(), contains('WEBVTT'));
      expect(await file.readAsString(), contains('你好'));

      final source = BiliResolvedPlayback(
        bvid: 'BV1subtitle',
        cid: 99,
        title: '字幕测试',
        subtitle: 'P1',
        uri: 'file:///tmp/video.mpd',
        protocol: VesperPlayerSourceProtocol.dash,
        transportLabel: 'test',
        isLocalFile: true,
        subtitleTracks: tracks,
      ).toSource();
      final external = source.externalSubtitles.single;
      expect(external.id, 'subtitle:bili:3');
      expect(external.uri, tracks.single.url);
      expect(external.mimeType, VesperExternalSubtitleSource.mimeWebvtt);
      expect(external.language, 'zh-CN');
      expect(external.label, '中文（中国大陆）');
      expect(external.isDefault, isFalse);
      expect(source.toMap()['externalSubtitles'], <Object?>[
        <String, Object?>{
          'id': 'subtitle:bili:3',
          'uri': tracks.single.url,
          'mimeType': VesperExternalSubtitleSource.mimeWebvtt,
          'language': 'zh-CN',
          'label': '中文（中国大陆）',
          'headers': <String, String>{},
          'isDefault': false,
          'isForced': false,
        },
      ]);
    },
  );

  test('coalesces concurrent subtitle materialization requests', () async {
    final httpClient = _LibraryHttpClient();
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final futures = <Future<List<BiliSubtitleTrack>>>{
      client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99),
      client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99),
    };
    final results = await Future.wait(futures);

    expect(results[0], hasLength(1));
    expect(results[1], hasLength(1));
    expect(
      httpClient.requestedUris.where((uri) => uri.path == '/x/player/v2'),
      hasLength(1),
    );
    expect(
      httpClient.requestedUris.where((uri) => uri.host == 'subtitle.example'),
      hasLength(1),
    );
  });

  test(
    're-fetches subtitles when the cached VTT file was cleaned up',
    () async {
      final httpClient = _LibraryHttpClient();
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
          'DedeUserID': '42',
          'buvid3': 'b3',
          'buvid4': 'b4',
        });
      addTearDown(() => client.transport.httpClient.close(force: true));

      final first = await client.fetchVideoSubtitles(
        bvid: 'BV1subtitle',
        cid: 99,
      );
      final firstUrl = first.single.url;
      final firstFile = File(Uri.parse(firstUrl).toFilePath());
      addTearDown(() async {
        if (await firstFile.exists()) {
          await firstFile.delete();
        }
      });
      // Simulate _cleanupStaleSubtitleFiles removing the materialized file
      // while the in-memory cache still points at it.
      await firstFile.delete();

      final second = await client.fetchVideoSubtitles(
        bvid: 'BV1subtitle',
        cid: 99,
      );
      expect(second.single.id, first.single.id);
      expect(
        File(Uri.parse(second.single.url).toFilePath()).existsSync(),
        isTrue,
      );
      expect(
        httpClient.requestedUris.where((uri) => uri.host == 'subtitle.example'),
        hasLength(2),
      );
    },
  );

  test('cache trim never evicts an in-flight subtitle request', () async {
    final gate = Completer<void>();
    final httpClient = _LibraryHttpClient(
      subtitleGates: <Future<void>>[gate.future],
      subtitleBvids: const <String>{'BV1inflight'},
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    // Start one materialization and hold its subtitle-body request open.
    final inFlight = client.fetchVideoSubtitles(bvid: 'BV1inflight', cid: 1);
    await pumpEventQueue();
    // Fill the request cache past its bound with completed requests.
    for (var i = 0; i < 24; i++) {
      await client.fetchVideoSubtitles(bvid: 'BV1done$i', cid: 1000 + i);
    }
    gate.complete();
    final tracks = await inFlight;
    expect(tracks, hasLength(1));
    addTearDown(() async {
      final file = File(Uri.parse(tracks.single.url).toFilePath());
      if (await file.exists()) {
        await file.delete();
      }
    });

    // The trim triggered by the completed requests must not have evicted the
    // then-in-flight entry: a follow-up lookup is served from the cache.
    final playerV2Count = httpClient.requestedUris
        .where((uri) => uri.path == '/x/player/v2')
        .length;
    final again = await client.fetchVideoSubtitles(bvid: 'BV1inflight', cid: 1);
    expect(again.single.id, tracks.single.id);
    expect(
      httpClient.requestedUris.where((uri) => uri.path == '/x/player/v2'),
      hasLength(playerV2Count),
    );
  });

  test(
    'two callers invalidate the same stale subtitle entry exactly once',
    () async {
      final httpClient = _LibraryHttpClient();
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
          'DedeUserID': '42',
          'buvid3': 'b3',
          'buvid4': 'b4',
        });
      addTearDown(() => client.transport.httpClient.close(force: true));

      final first = await client.fetchVideoSubtitles(
        bvid: 'BV1subtitle',
        cid: 99,
      );
      final file = File(Uri.parse(first.single.url).toFilePath());
      addTearDown(() async {
        if (await file.exists()) {
          await file.delete();
        }
      });
      await file.delete();

      // 两个调用方同时命中同一个已失效的缓存条目：两者都必须拿到新拉取
      // 的结果，且只允许发出一次重拉（player-v2 与字幕 body 各一次）。
      final results = await Future.wait(<Future<List<BiliSubtitleTrack>>>[
        client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99),
        client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99),
      ]);
      expect(results[0].single.id, first.single.id);
      expect(results[1].single.id, first.single.id);
      expect(
        File(Uri.parse(results[0].single.url).toFilePath()).existsSync(),
        isTrue,
      );
      expect(
        httpClient.requestedUris.where((uri) => uri.path == '/x/player/v2'),
        hasLength(2),
      );
      expect(
        httpClient.requestedUris.where((uri) => uri.host == 'subtitle.example'),
        hasLength(2),
      );
    },
  );

  test(
    'a stale session future cannot mark a fresh in-flight request completed',
    () async {
      // 会话切换（restoreCookies 清空缓存）后，旧会话挂起的 Future 完成时
      // 不得把新会话的 in-flight 条目标记为 completed——否则 trim 会把它
      // 当成已完成条目驱逐，正在等待的调用方就会失去共享的请求。
      final staleGate = Completer<void>();
      final freshGate = Completer<void>();
      final httpClient = _LibraryHttpClient(
        subtitleGates: <Future<void>>[staleGate.future, freshGate.future],
        subtitleBvids: const <String>{'BV1inflight'},
      );
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
          'DedeUserID': '42',
          'buvid3': 'b3',
          'buvid4': 'b4',
        });
      addTearDown(() => client.transport.httpClient.close(force: true));

      // 旧会话请求挂起（结果由 gate 控制，不需要持有）。
      unawaited(client.fetchVideoSubtitles(bvid: 'BV1inflight', cid: 1));
      await pumpEventQueue();
      // 会话切换：旧 Future 仍挂着，但缓存已被清空。
      client.restoreCookies(const <String, String>{
        'SESSDATA': 'sess2',
        'bili_jct': 'csrf2',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
      // 新会话的同 key 请求挂起（freshGate）。
      final fresh = client.fetchVideoSubtitles(bvid: 'BV1inflight', cid: 1);
      await pumpEventQueue();
      // 填满其他视频的已完成条目，使下一次完成触发 trim。
      for (var i = 0; i < 24; i++) {
        await client.fetchVideoSubtitles(bvid: 'BV1done$i', cid: 1000 + i);
      }
      // 旧请求先完成：不得标记新请求。
      staleGate.complete();
      await pumpEventQueue();
      // 再完成一个其他视频：trim 溢出，若旧请求错误标记了新请求，正在
      // in-flight 的 fresh 就会被驱逐。
      await client.fetchVideoSubtitles(bvid: 'BV1done-last', cid: 9999);
      freshGate.complete();
      final tracks = await fresh;
      expect(tracks, hasLength(1));
      addTearDown(() async {
        final file = File(Uri.parse(tracks.single.url).toFilePath());
        if (await file.exists()) {
          await file.delete();
        }
      });

      // fresh 未被驱逐：再次请求命中缓存，不再发 player-v2。
      final playerV2Count = httpClient.requestedUris
          .where((uri) => uri.path == '/x/player/v2')
          .length;
      final again = await client.fetchVideoSubtitles(
        bvid: 'BV1inflight',
        cid: 1,
      );
      expect(again.single.id, tracks.single.id);
      expect(
        httpClient.requestedUris.where((uri) => uri.path == '/x/player/v2'),
        hasLength(playerV2Count),
      );
    },
  );

  test('falls back to the ATV WBI subtitle endpoint', () async {
    final httpClient = _LibraryHttpClient(subtitlesOnlyOnWbi: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final tracks = await client.fetchVideoSubtitleTracks(
      bvid: 'BV1subtitle',
      cid: 99,
    );

    expect(tracks, hasLength(1));
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      containsAllInOrder(<String>['/x/player/v2', '/x/player/wbi/v2']),
    );
  });

  test(
    'propagates failure when subtitle discovery cannot be confirmed',
    () async {
      final httpClient = _LibraryHttpClient(subtitleEndpointsFail: true);
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
          'DedeUserID': '42',
          'buvid3': 'b3',
          'buvid4': 'b4',
        });
      addTearDown(() => client.transport.httpClient.close(force: true));

      await expectLater(
        client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99),
        throwsA(isA<BiliApiException>()),
      );
    },
  );

  test('does not truncate subtitle cues at 24 hours', () async {
    final httpClient = _LibraryHttpClient(
      subtitleCueFrom: 90000,
      subtitleCueTo: 90001.5,
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final tracks = await client.fetchVideoSubtitles(
      bvid: 'BV1subtitle',
      cid: 99,
    );
    final file = File(Uri.parse(tracks.single.url).toFilePath());
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });
    expect(await file.readAsString(), contains('25:00:00.000'));
  });

  test('rejects file URLs advertised by the remote subtitle API', () async {
    final httpClient = _LibraryHttpClient(
      subtitleUrl: 'file:///tmp/untrusted-subtitle.vtt',
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final tracks = await client.fetchVideoSubtitleTracks(
      bvid: 'BV1subtitle',
      cid: 99,
    );

    expect(tracks, isEmpty);
    expect(
      httpClient.requestedUris.where((uri) => uri.path == '/x/player/v2'),
      hasLength(1),
    );
    expect(
      httpClient.requestedUris.any((uri) => uri.scheme == 'file'),
      isFalse,
    );
  });

  test('resolves root-relative subtitle URLs against the API origin', () async {
    final httpClient = _LibraryHttpClient(
      subtitleUrl: '/bfs/subtitle/track.json',
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final tracks = await client.fetchVideoSubtitleTracks(
      bvid: 'BV1subtitle',
      cid: 99,
    );

    expect(
      tracks.single.url,
      'https://api.bilibili.com/bfs/subtitle/track.json',
    );
  });

  test('does not send session cookies to a subtitle CDN', () async {
    final httpClient = _LibraryHttpClient();
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'secret-session',
        'bili_jct': 'secret-csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99);

    final subtitleHeaders = httpClient.requestHeaders.entries
        .firstWhere((entry) => entry.key.host == 'subtitle.example')
        .value;
    final apiHeaders = httpClient.requestHeaders.entries
        .firstWhere((entry) => entry.key.path == '/x/player/v2')
        .value;
    expect(subtitleHeaders, isNot(containsPair('cookie', anything)));
    expect(apiHeaders['cookie'], contains('secret-session'));
  });
}

Future<void> _pumpLibraryUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

final class _RecordedPost {
  const _RecordedPost(this.uri, this.fields);

  final Uri uri;
  final Map<String, String> fields;
}

final class _LibraryHttpClient implements HttpClient {
  _LibraryHttpClient({
    this.durationAsClockLabel = false,
    this.explicitMillisecondFields = false,
    this.subtitleUrl = '//subtitle.example/track.json',
    this.legacyHistoryFields = false,
    this.legacyEndpointOnly = false,
    this.episodeIdWithoutCid = false,
    this.subtitlesOnlyOnWbi = false,
    this.subtitleEndpointsFail = false,
    this.subtitleCueFrom = 0,
    this.subtitleCueTo = 1.5,
    this.multipleFollowingPages = false,
    this.emptyFollowingAvatars = false,
    this.spaceVideoOwnerMid = 7,
    this.historyPaginationAuthExpires = false,
    this.emptyHistoryCovers = false,
    this.emptyWatchLaterCovers = false,
    this.subtitleGates = const <Future<void>>[],
    this.subtitleBvids,
    this.profileGates = const <int, Future<void>>{},
  });

  final bool durationAsClockLabel;
  final bool explicitMillisecondFields;
  final String subtitleUrl;
  final bool legacyHistoryFields;
  final bool legacyEndpointOnly;
  final bool episodeIdWithoutCid;
  final bool subtitlesOnlyOnWbi;
  final bool subtitleEndpointsFail;
  final double subtitleCueFrom;
  final double subtitleCueTo;
  final bool multipleFollowingPages;
  final bool emptyFollowingAvatars;
  bool followingEmpty = false;
  int followingMid = 7;
  int spaceAuthenticationFailuresRemaining = 0;
  final int spaceVideoOwnerMid;
  final bool historyPaginationAuthExpires;
  final bool emptyHistoryCovers;
  final bool emptyWatchLaterCovers;

  /// When non-empty, subtitle body requests (host `subtitle.example`) wait on
  /// the next gate future (consumed per request, queue order) before
  /// responding. Used to hold individual materializations in flight.
  final List<Future<void>> subtitleGates;

  /// When non-null, only player-v2 responses for these bvids advertise
  /// subtitles. Keeps gated requests from blocking unrelated materializations.
  final Set<String>? subtitleBvids;
  final Map<int, Future<void>> profileGates;
  final List<Uri> requestedUris = <Uri>[];
  final Map<Uri, Map<String, String>> requestHeaders =
      <Uri, Map<String, String>>{};
  final List<_RecordedPost> posts = <_RecordedPost>[];
  String? _userAgent;

  List<int> get requestedProfileMids => requestedUris
      .where((uri) => uri.path == '/x/web-interface/card')
      .map((uri) => int.tryParse(uri.queryParameters['mid'] ?? ''))
      .whereType<int>()
      .toList(growable: false);

  List<int> get requestedSpaceMids => requestedUris
      .where((uri) => uri.path == '/x/space/wbi/arc/search')
      .map((uri) => int.tryParse(uri.queryParameters['mid'] ?? ''))
      .whereType<int>()
      .toList(growable: false);

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) => _userAgent = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUris.add(url);
    final headers = <String, String>{};
    requestHeaders[url] = headers;
    if (url.path == '/x/web-interface/card') {
      final mid = int.tryParse(url.queryParameters['mid'] ?? '');
      final gate = mid == null ? null : profileGates[mid];
      if (gate != null) {
        await gate;
      }
    }
    if (url.host == 'subtitle.example' && subtitleGates.isNotEmpty) {
      await subtitleGates.removeAt(0);
    }
    return _LibraryHttpClientRequest(
      _responseFor(url),
      onHeader: (name, value) => headers[name.toLowerCase()] = value.toString(),
    );
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    requestedUris.add(url);
    final headers = <String, String>{};
    requestHeaders[url] = headers;
    return _LibraryHttpClientRequest(
      _responseFor(url),
      onHeader: (name, value) => headers[name.toLowerCase()] = value.toString(),
      onClose: (body) {
        posts.add(_RecordedPost(url, Uri.splitQueryString(body)));
      },
    );
  }

  _LibraryHttpClientResponse _responseFor(Uri url) {
    if (url.path == '/x/web-interface/nav') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'isLogin': true,
          'mid': 42,
          'wbi_img': <String, Object?>{
            'img_url': 'https://i0.hdslb.com/bfs/wbi/img.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/sub.png',
          },
        },
      });
    }
    if (url.path == '/x/relation/followings') {
      final page = int.tryParse(url.queryParameters['pn'] ?? '') ?? 1;
      final count = followingEmpty
          ? 0
          : multipleFollowingPages
          ? (page == 1 ? 50 : 1)
          : 1;
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'list': List<Object?>.generate(
            count,
            (index) => <String, Object?>{
              'mid': multipleFollowingPages
                  ? page * 1000 + index
                  : followingMid,
              'uname': multipleFollowingPages
                  ? '测试 UP ${(page - 1) * 50 + index + 1}'
                  : '测试 UP',
              'face': emptyFollowingAvatars ? '' : '//example.com/avatar.jpg',
              'sign': '简介',
              'official_verify': <String, Object?>{'desc': '认证'},
            },
          ),
        },
      });
    }
    if (url.path == '/x/web-interface/card') {
      final mid =
          int.tryParse(url.queryParameters['mid'] ?? '') ?? followingMid;
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'card': <String, Object?>{
            'mid': mid,
            'name': mid == 7 ? '测试 UP 空间' : '测试 UP $mid 空间',
            'face': emptyFollowingAvatars
                ? ''
                : '//example.com/space-avatar.jpg',
            'sign': '空间简介',
            'friend': 12,
            'fans': 12000,
            'official_verify': <String, Object?>{'desc': '认证'},
          },
          'follower': 12000,
          'archive_count': 3,
        },
      });
    }
    if (url.path == '/x/space/wbi/arc/search') {
      final mid =
          int.tryParse(url.queryParameters['mid'] ?? '') ?? followingMid;
      if (spaceAuthenticationFailuresRemaining > 0) {
        spaceAuthenticationFailuresRemaining -= 1;
        return _json(<String, Object?>{'code': -101, 'message': '账号未登录'});
      }
      final keyword = url.queryParameters['keyword'] ?? '';
      final hasMatch = keyword.isEmpty || keyword.contains('空间');
      final bvid = mid == 7
          ? 'BV1space0001'
          : 'BV1space${mid.toString().padLeft(4, '0')}';
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'list': <String, Object?>{
            'vlist': hasMatch
                ? <Object?>[
                    <String, Object?>{
                      'aid': mid * 10,
                      'bvid': bvid,
                      'title': mid == 7 ? '空间视频' : '空间视频 $mid',
                      'pic': emptyFollowingAvatars
                          ? ''
                          : '//example.com/space-video.jpg',
                      'length': '02:03',
                      'created': 1710000000,
                      'play': 12000,
                      'mid': mid,
                      'author': mid == 7 ? '测试 UP 空间' : '测试 UP $mid 空间',
                      'description': '投稿简介',
                    },
                  ]
                : const <Object?>[],
          },
          'page': <String, Object?>{
            'pn': int.tryParse(url.queryParameters['pn'] ?? '') ?? 1,
            'ps': int.tryParse(url.queryParameters['ps'] ?? '') ?? 30,
            'count': hasMatch ? 1 : 0,
          },
        },
      });
    }
    if (url.path == '/x/web-interface/view') {
      final bvid = url.queryParameters['bvid'] ?? 'BV1space0001';
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'aid': 70,
          'bvid': bvid,
          'title': '空间视频',
          'pic': '//example.com/space-video.jpg',
          'desc': '投稿简介',
          'pubdate': 1710000000,
          'owner': <String, Object?>{
            'mid': spaceVideoOwnerMid,
            'name': '测试 UP 空间',
            'face': '//example.com/space-avatar.jpg',
          },
          'stat': <String, Object?>{'view': 12000},
          'pages': <Object?>[
            <String, Object?>{
              'cid': 701,
              'page': 1,
              'part': 'P1',
              'duration': 123,
            },
          ],
        },
      });
    }
    if (url.path == '/x/v2/history' ||
        url.path == '/x/web-interface/history/cursor') {
      if (historyPaginationAuthExpires &&
          url.path == '/x/v2/history' &&
          url.queryParameters['pn'] == '2') {
        return _json(<String, Object?>{
          'code': -101,
          'message': '账号未登录',
          'data': null,
        });
      }
      if (legacyHistoryFields || legacyEndpointOnly || episodeIdWithoutCid) {
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'history': <String, Object?>{
                  'oid': 101,
                  'bvid': 'BVlegacy',
                  if (episodeIdWithoutCid) 'epid': 9001 else 'cid': 1001,
                  'title': '旧历史',
                  'author': <String, Object?>{'uname': '旧 UP'},
                  'cover': '//example.com/legacy.jpg',
                  'part': '旧 P',
                  'duration': 61,
                  'progress': 12,
                  'view_at': 1710000000,
                },
              },
            ],
          },
        });
      }
      if (url.path == '/x/v2/history') {
        return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
      }
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'cursor': <String, Object?>{'max': 123, 'view_at': 1709999999},
          'list': <Object?>[
            <String, Object?>{
              'aid': 1,
              'bvid': 'BV1history',
              'cid': 11,
              'title': '历史视频',
              'pic': emptyHistoryCovers ? '' : '//example.com/history.jpg',
              'author_name': 'UP',
              'part': 'P1',
              if (explicitMillisecondFields) ...<String, Object?>{
                'duration_ms': 45000,
                'progress_ms': 12000,
              } else ...<String, Object?>{
                'duration': durationAsClockLabel ? '02:05' : 120,
                'progress': durationAsClockLabel ? '01:30.5' : 45,
              },
              'view_at': 1710000000,
            },
          ],
        },
      });
    }
    if (url.path == '/x/v2/history/toview' ||
        url.path == '/x/v2/history/toview/web') {
      if (legacyHistoryFields || legacyEndpointOnly || episodeIdWithoutCid) {
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'oid': 202,
                'bvid': 'BVlegacy-later',
                if (episodeIdWithoutCid) 'episode_id': 9002 else 'cid': 2002,
                'show_title': '旧稍后',
                'cover_url': '//example.com/legacy-later.jpg',
                'author_name': '旧稍后 UP',
                'duration': 70,
                'progress': 5,
                'addAt': 1710000000,
              },
            ],
          },
        });
      }
      if (url.path == '/x/v2/history/toview') {
        return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
      }
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'aid': 2,
              'bvid': 'BV1later',
              'cid': 22,
              'title': '稍后视频',
              'pic': emptyWatchLaterCovers
                  ? ''
                  : 'https://example.com/later.jpg',
              'page': 'P2',
              if (explicitMillisecondFields) ...<String, Object?>{
                'duration_ms': 90000,
                'progress_ms': 1500,
              } else ...<String, Object?>{
                'duration': durationAsClockLabel ? '01:30' : 90,
                'progress': durationAsClockLabel ? '00:01.5' : 0,
              },
              'owner': <String, Object?>{'name': 'UP2'},
            },
          ],
        },
      });
    }
    if (url.path == '/x/player/v2' || url.path == '/x/player/wbi/v2') {
      if (subtitleEndpointsFail) {
        return _json(<String, Object?>{
          'code': -500,
          'message': 'subtitle endpoint unavailable',
        });
      }
      final subtitleBvids = this.subtitleBvids;
      final hasSubtitles =
          (subtitleBvids == null ||
              subtitleBvids.contains(url.queryParameters['bvid'])) &&
          (!subtitlesOnlyOnWbi || url.path == '/x/player/wbi/v2');
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'subtitle': <String, Object?>{
            'subtitles': hasSubtitles
                ? <Object?>[
                    <String, Object?>{
                      'id': 3,
                      'lan': 'zh-CN',
                      'lan_doc': '中文（中国大陆）',
                      'subtitle_url': subtitleUrl,
                    },
                  ]
                : const <Object?>[],
          },
        },
      });
    }
    if (url.host == 'subtitle.example') {
      return _raw(<String, Object?>{
        'body': <Object?>[
          <String, Object?>{
            'from': subtitleCueFrom,
            'to': subtitleCueTo,
            'content': '你好',
          },
        ],
      });
    }
    return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
  }

  _LibraryHttpClientResponse _json(Map<String, Object?> value) {
    return _raw(value);
  }

  _LibraryHttpClientResponse _raw(Object value) {
    return _LibraryHttpClientResponse(jsonEncode(value));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LibraryHttpClientRequest implements HttpClientRequest {
  _LibraryHttpClientRequest(this._response, {this.onClose, this._onHeader});

  final _LibraryHttpClientResponse _response;
  final void Function(String body)? onClose;
  final void Function(String name, Object value)? _onHeader;
  bool _headersMutable = true;
  late final _LibraryHttpHeaders _headers = _LibraryHttpHeaders(
    onSet: _onHeader,
    isMutable: () => _headersMutable,
  );
  final List<int> _body = <int>[];
  int _contentLength = -1;

  @override
  HttpHeaders get headers => _headers;

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) {
    if (!_headersMutable) {
      throw const HttpException('HTTP headers are not mutable');
    }
    _contentLength = value;
  }

  @override
  void add(List<int> data) {
    _headersMutable = false;
    _body.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() async {
    if (onClose != null) {
      onClose!(utf8.decode(_body));
    }
    return _response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LibraryHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _LibraryHttpClientResponse(this.body);

  final String body;
  @override
  final int statusCode = HttpStatus.ok;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  HttpHeaders get headers => _LibraryHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[
      utf8.encode(body),
    ]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LibraryHttpHeaders implements HttpHeaders {
  _LibraryHttpHeaders({this.onSet, this.isMutable});

  final void Function(String name, Object value)? onSet;
  final bool Function()? isMutable;
  ContentType? _contentType;

  void _ensureMutable() {
    if (isMutable?.call() == false) {
      throw const HttpException('HTTP headers are not mutable');
    }
  }

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) {
    _ensureMutable();
    _contentType = value;
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _ensureMutable();
    onSet?.call(name, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
