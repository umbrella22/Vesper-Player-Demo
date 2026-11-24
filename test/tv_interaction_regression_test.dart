import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/app/design/app_theme_controller.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/app/system_presentation.dart';
import 'package:vesper_media/app/updates/app_update_controller.dart';
import 'package:vesper_media/app/updates/app_update_widgets.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_library_page.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/models/bili_region_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/tv_mode/pages/bili_tv_home_page.dart';
import 'package:vesper_media/bili/tv_mode/widgets/bili_tv_qr_login_dialog.dart';
import 'package:vesper_media/media/playback/media_playback_tv_widgets.dart';
import 'package:vesper_media/media/tv/media_tv_focusable.dart';

import 'support/app_update_fakes.dart';

const _feed = [
  BiliFeedVideo(
    aid: 1,
    bvid: 'BVtest',
    title: '测试',
    author: '测试',
    coverUrl: '',
    durationLabel: '1:00',
    playCountLabel: '',
    danmakuCountLabel: '',
  ),
];

String? get _focus => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _openNav(WidgetTester tester, String name) async {
  for (var step = 0; step < 7 && _focus != 'nav_$name'; step++) {
    await _press(tester, LogicalKeyboardKey.arrowDown);
  }
  expect(_focus, 'nav_$name');
  await _press(tester, LogicalKeyboardKey.select);
}

class _TvClient extends BiliClient {
  final regions = <Completer<List<BiliRegionVideo>>>[];
  final tickets = <Completer<BiliQrLoginTicket>>[];
  int polls = 0;
  bool interruptNextPoll = false;

  @override
  bool get hasAuthenticatedSession => true;

  @override
  Future<List<BiliRegionVideo>> fetchRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) {
    final request = Completer<List<BiliRegionVideo>>();
    regions.add(request);
    return request.future;
  }

  @override
  Future<BiliQrLoginTicket> generateQrLoginTicket() {
    final request = Completer<BiliQrLoginTicket>();
    tickets.add(request);
    return request.future;
  }

  @override
  Future<BiliQrLoginPollResult> pollQrLogin(String qrcodeKey) async {
    polls++;
    if (interruptNextPoll) {
      interruptNextPoll = false;
      throw TimeoutException('poll timed out');
    }
    return const BiliQrLoginPollResult(
      status: BiliQrLoginStatus.expired,
      message: 'expired',
    );
  }

  @override
  Future<List<BiliWatchLaterEntry>> fetchWatchLater({
    int page = 1,
    int pageSize = 20,
  }) async => List.generate(
    12,
    (i) => BiliWatchLaterEntry(
      aid: i + 1,
      bvid: 'BV$i',
      cid: i + 1,
      title: '视频 $i',
      pageTitle: '',
      coverUrl: '',
      ownerName: 'UP',
      durationMs: 200,
      progressMs: 0,
    ),
  );
}

void main() {
  testWidgets(
    'TV regions keep empty results and retry once from the category D-pad',
    (tester) async {
      final client = _TvClient();
      await tester.pumpWidget(
        MaterialApp(
          home: BiliTvHomePage(
            client: client,
            skipBootstrap: true,
            initialFeedItems: _feed,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openNav(tester, 'regions');
      expect(client.regions, hasLength(1));
      client.regions.single.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focus, 'region_bangumi');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focus, 'tv_region_retry');
      await _press(tester, LogicalKeyboardKey.select);
      expect(client.regions, hasLength(2));
      client.regions.last.complete([]);
      // Bound the pump count so a regression reports the extra request immediately.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('暂无内容'), findsOneWidget);
      expect(client.regions, hasLength(2));
    },
  );

  testWidgets(
    'TV changing region ignores a late error from the previous category',
    (tester) async {
      final client = _TvClient();
      await tester.pumpWidget(
        MaterialApp(
          home: BiliTvHomePage(
            client: client,
            skipBootstrap: true,
            initialFeedItems: _feed,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openNav(tester, 'regions');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focus, 'region_guochuang');
      await _press(tester, LogicalKeyboardKey.select);
      expect(client.regions, hasLength(2));
      client.regions.last.complete([]);
      client.regions.first.completeError(StateError('stale'));
      await tester.pumpAndSettle();
      expect(find.text('暂无内容'), findsOneWidget);
      expect(find.text('重新加载'), findsNothing);
    },
  );

  testWidgets(
    'TV settings update can be opened and dismissed from the remote',
    (tester) async {
      final client = FakeUpdateClient();
      final update = AppUpdateController(
        client: client,
        installer: FakeUpdateInstaller(),
        currentVersion: () async => '1.14.0',
      );
      addTearDown(update.dispose);
      await tester.pumpWidget(
        AppUpdateScope(
          controller: update,
          child: MaterialApp(
            home: BiliTvHomePage(
              client: _TvClient(),
              skipBootstrap: true,
              initialFeedItems: _feed,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openNav(tester, 'settings');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      if (_focus == 'tv_settings_force_mode') {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(_focus, 'tv_settings_update');
      await _press(tester, LogicalKeyboardKey.select);
      expect(client.checks, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      bool focused(String text) =>
          Focus.of(tester.element(find.text(text))).hasPrimaryFocus;
      expect(focused('稍后'), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused('下载并安装'), isTrue);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
      expect(_focus, 'tv_settings_update');
      await _press(tester, LogicalKeyboardKey.select);
      await _press(tester, LogicalKeyboardKey.select);
      expect(find.byType(AlertDialog), findsNothing);
      expect(client.downloads, 0);
    },
  );

  for (final (pref, brightness, expected) in [
    (AppThemePreference.light, Brightness.dark, biliAppSystemUiStyle),
    (AppThemePreference.dark, Brightness.light, biliDarkSurfaceSystemUiStyle),
    (AppThemePreference.system, Brightness.dark, biliDarkSurfaceSystemUiStyle),
    (AppThemePreference.system, Brightness.light, biliAppSystemUiStyle),
  ]) {
    testWidgets(
      'TV exit restores $pref app bars at $brightness system brightness',
      (tester) async {
        final styles = <Object?>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        const device = MethodChannel('dev.ikaros.vesper_player/platform');
        messenger.setMockMethodCallHandler(device, (_) async => true);
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            styles.add(call.arguments);
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          messenger.setMockMethodCallHandler(device, null);
        });
        final theme = AppThemeController(
          settings: const AppSettingsStore(),
          initialPreference: pref,
        );
        addTearDown(theme.dispose);
        await tester.pumpWidget(
          AppThemeScope(
            controller: theme,
            child: MaterialApp(
              theme: ThemeData.dark(),
              home: MediaQuery(
                data: MediaQueryData(platformBrightness: brightness),
                child: BiliTvHomePage(
                  client: _TvClient(),
                  skipBootstrap: true,
                  initialFeedItems: _feed,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // A test MaterialApp may publish its own per-frame overlay while TV is on
        // screen. Start both cases from a distinct style and observe the exit.
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(statusBarColor: Color(0xFF123456)),
        );
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(
          styles.last,
          containsPair(
            'statusBarIconBrightness',
            expected.statusBarIconBrightness.toString(),
          ),
        );
        expect(
          styles.last,
          containsPair(
            'systemNavigationBarIconBrightness',
            expected.systemNavigationBarIconBrightness.toString(),
          ),
        );
      },
    );
  }

  testWidgets(
    'TV QR cancel works while obtaining a ticket and during a refresh, expired badge matches status',
    (tester) async {
      final client = _TvClient();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBiliTvQrLoginDialog(
                context: context,
                client: client,
                sessionStore: const BiliSessionStore(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      const ticket = BiliQrLoginTicket(
        url: 'https://example.test/qr',
        qrcodeKey: 'unit',
      );
      await open();
      expect(_focus, 'tv_qr_login_cancel');
      await _press(tester, LogicalKeyboardKey.select);
      client.tickets.first.complete(ticket);
      await tester.pumpAndSettle();
      expect(client.polls, 0);
      await open();
      client.interruptNextPoll = true;
      client.tickets.last.complete(ticket);
      await tester.pumpAndSettle();
      expect(find.text('扫码状态暂不可用'), findsOneWidget);
      expect(find.text('二维码已失效'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('二维码已失效'), findsOneWidget);
      expect(find.text('二维码有效，请使用手机扫码'), findsNothing);
      expect(_focus, 'tv_qr_login_refresh');
      await _press(tester, LogicalKeyboardKey.select);
      expect(client.tickets, hasLength(3));
      expect(_focus, 'tv_qr_login_cancel');
      await _press(tester, LogicalKeyboardKey.select);
      client.tickets.last.complete(ticket);
      await tester.pumpAndSettle();
      expect(find.byType(BiliTvQrLoginDialog), findsNothing);
      expect(client.polls, 2);
    },
  );

  testWidgets(
    'TV late selected episode is visible, focused and navigable after a list change',
    (tester) async {
      var activated = -1;
      Widget panel(int count, int selected) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 270,
            child: TvPanelOptionList(
              panelKey: 'pages',
              options: List.generate(
                count,
                (i) => TvPanelOption(
                  label: 'P$i',
                  subtitle: '很长的分集标题 ' * (i % 4 + 1),
                  selected: i == selected,
                  onTap: () => activated = i,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(panel(120, 96));
      await tester.pumpAndSettle();
      expect(_focus, 'tv_panel_P96');
      expect(find.text('P96').hitTestable(), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.select);
      expect(activated, 97);
      await tester.pumpWidget(panel(60, 42));
      await tester.pumpAndSettle();
      expect(_focus, 'tv_panel_P42');
      expect(find.text('P42').hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'TV focus rebinding keeps parent nodes alive and transfers traversal metadata',
    (tester) async {
      final first = FocusNode(debugLabel: 'first');
      final second = FocusNode(debugLabel: 'second');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var taps = 0;
      Widget surface(FocusNode? node) => MaterialApp(
        home: TvFocusGroupScope(
          group: 'group',
          child: TvFocusable(
            focusNode: node,
            autofocus: true,
            focusArea: TvFocusArea.content,
            onTap: () => taps++,
            child: const Text('target'),
          ),
        ),
      );
      await tester.pumpWidget(surface(first));
      await tester.pumpAndSettle();
      for (final node in [second, null, first]) {
        final previous = FocusManager.instance.primaryFocus!;
        await tester.pumpWidget(surface(node));
        await tester.pumpAndSettle();
        final current = FocusManager.instance.primaryFocus!;
        if (node != null) expect(current, same(node));
        expect(current, isNot(same(previous)));
        expect(tvFocusAreaOf(current), TvFocusArea.content);
        expect(tvFocusGroupOf(current), 'group');
        expect(tvFocusAreaOf(previous), isNull);
        await _press(tester, LogicalKeyboardKey.select);
      }
      await tester.pumpWidget(surface(null));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(taps, 3);
      // A parent can still register a listener after the child is gone.
      first.addListener(() {});
      second.addListener(() {});
    },
  );

  testWidgets('TV ungrouped content returns to the last active rail item', (
    tester,
  ) async {
    Widget target(String label, TvFocusArea area, {bool autofocus = false}) =>
        TvFocusable(
          debugLabel: label,
          focusArea: area,
          autofocus: autofocus,
          onTap: () {},
          child: Text(label),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 16,
                top: 16,
                child: target('first', TvFocusArea.rail),
              ),
              Positioned(
                left: 16,
                top: 160,
                child: target('active', TvFocusArea.rail, autofocus: true),
              ),
              Positioned(
                left: 300,
                top: 16,
                child: target('content', TvFocusArea.content),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_focus, 'active');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focus, 'content');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focus, 'active');
  });

  testWidgets(
    'TV watch later arrows traverse videos and keep removal reachable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BiliLibraryPage(
            client: _TvClient(),
            initialSection: BiliLibrarySection.watchLater,
            presentationMode: BiliPlaybackPresentationMode.tv,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_focus, 'tv_library_watch_later_cid:1');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focus, 'tv_library_watch_later_cid:2');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focus, startsWith('tv_library_watch_later_cid:'));
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_focus, 'tv_library_watch_later_cid:2');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_focus, 'tv_library_remove_watch_later');
      await _press(tester, LogicalKeyboardKey.select);
      expect(find.text('移出稍后再看？'), findsOneWidget);
      expect(_focus, 'tv_dialog_取消');
    },
  );
}
