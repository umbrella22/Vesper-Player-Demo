import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_hub_page.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_library_page.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/common/view_models/bili_hub_view_model.dart';

void main() {
  testWidgets(
    'phone library reloads a previously signed-out tab after login on another tab',
    (tester) async {
      final client = _PhoneAccountClient();
      await tester.pumpWidget(
        MaterialApp(
          home: BiliLibraryPage(
            client: client,
            onLoginTap: () async => client.restoreCookies(_session),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('请先登录 Bilibili 后查看此内容。'), findsOneWidget);
      await tester.tap(find.text('稍后再看'));
      await tester.pumpAndSettle();
      expect(client.followingCalls, 0);
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(find.text('稍后再看列表是空的。'), findsOneWidget);
      await tester.tap(find.text('关注'));
      await tester.pumpAndSettle();
      expect(find.text('测试关注'), findsOneWidget);
      expect(client.followingCalls, 1);
    },
  );

  testWidgets(
    'phone account retries a transient profile error using the saved session',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('phone-profile-retry-'),
      ))!;
      final store = BiliSessionStore(
        baseDirectory: root,
        legacyDirectory: root,
      );
      final client = _PhoneAccountClient()
        ..profiles.add(
          () async => throw const SocketException('network unavailable'),
        );
      await tester.runAsync(() => store.saveCookies(_session));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => root.delete(recursive: true));
      });
      await tester.pumpWidget(
        MaterialApp(
          home: BiliHubPage(
            client: client,
            historyStore: BiliHistoryStore(
              baseDirectory: root,
              legacyDirectory: root,
            ),
            sessionStore: store,
          ),
        ),
      );
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(finder, findsOneWidget);
      }

      final avatar = find.byKey(const ValueKey('bili-home-avatar-button'));
      await waitFor(avatar);
      await tester.tap(avatar);
      await waitFor(find.text('已保留登录信息'));
      expect(find.text('账号待确认'), findsOneWidget);
      expect(find.text('未登录'), findsNothing);
      expect(find.text('重新登录'), findsNothing);
      expect(client.hasAuthenticatedSession, isTrue);
      final enabledRetry = find.ancestor(
        of: find.text('刷新资料'),
        matching: find.byWidgetPredicate(
          (widget) => widget is TextButton && widget.onPressed != null,
        ),
      );
      await waitFor(enabledRetry);
      await tester.tap(enabledRetry);
      await waitFor(find.text('测试账号'));
      expect(client.profileCalls, 2);
      expect(client.hasAuthenticatedSession, isTrue);

      client.profiles.add(
        () async => throw const SocketException('network unavailable'),
      );
      unawaited(
        tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh(),
      );
      await waitFor(find.text('重试'));
      expect(find.text('测试账号'), findsOneWidget);
      expect(find.text('空间'), findsOneWidget);
      expect(find.text('重新登录'), findsNothing);
      expect(
        client.snapshotCookies(),
        containsPair('SESSDATA', _session['SESSDATA']),
      );

      client.profiles.add(
        () async => throw const BiliApiException('登录状态已失效', code: -101),
      );
      await tester.tap(find.text('重试'));
      await waitFor(find.text('重新登录'));
      expect(find.text('测试账号'), findsNothing);
      expect(client.hasAuthenticatedSession, isFalse);
      await waitFor(
        find.ancestor(
          of: find.text('登录'),
          matching: find.byWidgetPredicate(
            (widget) => widget is TextButton && widget.onPressed != null,
          ),
        ),
      );
      final file = File('${root.path}/bili-session.json');
      expect(await tester.runAsync(file.exists), isFalse);
    },
  );

  test(
    'phone stale profile failure cannot clear a replacement account',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'phone-refresh-session-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final store = BiliSessionStore(baseDirectory: dir, legacyDirectory: dir);
      final pending = Completer<BiliUserProfile>();
      final client = _PhoneAccountClient()
        ..restoreCookies(_session)
        ..profiles.add(() => pending.future);
      final vm = BiliHubViewModel(client: client, sessionStore: store);
      addTearDown(vm.dispose);
      Future<void> refresh() =>
          vm.refreshProfile(clearInvalidSession: true, persistIfLoggedIn: true);
      final previous = refresh();
      client.restoreCookies({..._session, 'SESSDATA': 'replacement'});
      await refresh();
      pending.completeError(
        const BiliApiException('old session expired', code: -101),
      );
      await previous;
      expect(vm.profile.value.name, '测试账号');
      expect(vm.profilePendingVerification.value, isFalse);
      expect(vm.profileErrorMessage.value, isNull);
      expect(client.hasAuthenticatedSession, isTrue);
      expect((await store.loadCookies())['SESSDATA'], 'replacement');
    },
  );

  test('phone replaced session hides the prior profile until verification and guest response clears cookies', () async {
    final dir = await Directory.systemTemp.createTemp('phone-refresh-account-');
    addTearDown(() => dir.delete(recursive: true));
    final client = _PhoneAccountClient()..restoreCookies(_session);
    final store = BiliSessionStore(baseDirectory: dir, legacyDirectory: dir);
    final vm = BiliHubViewModel(client: client, sessionStore: store);
    addTearDown(vm.dispose);
    Future<void> refresh() =>
        vm.refreshProfile(clearInvalidSession: true, persistIfLoggedIn: true);
    await refresh();
    expect(vm.profile.value.isLoggedIn, isTrue);
    client.restoreCookies({..._session, 'SESSDATA': 'replacement'});
    client.profiles.add(() async => throw const SocketException('offline'));
    await refresh();
    expect(vm.profile.value.mid, isNull);
    expect(vm.profilePendingVerification.value, isTrue);
    expect(client.hasAuthenticatedSession, isTrue);
    client.profiles.add(
      () async =>
          const BiliUserProfile(isLoggedIn: false, name: '未登录', avatarUrl: ''),
    );
    await refresh();
    expect(vm.profilePendingVerification.value, isFalse);
    expect(client.hasAuthenticatedSession, isFalse);
    expect(await store.loadCookies(), isEmpty);
  });
}

const _session = {'SESSDATA': 'test-session', 'bili_jct': 'test-csrf'};

final class _PhoneAccountClient extends BiliClient {
  int followingCalls = 0;
  int profileCalls = 0;
  final profiles = <Future<BiliUserProfile> Function()>[];

  @override
  Future<List<BiliFollowingUser>> fetchFollowingUsers({
    int? mid,
    int page = 1,
    int pageSize = 20,
  }) async {
    followingCalls++;
    return const [BiliFollowingUser(mid: 12, name: '测试关注', avatarUrl: '')];
  }

  @override
  Future<List<BiliWatchLaterEntry>> fetchWatchLater({
    int page = 1,
    int pageSize = 30,
  }) async => [];

  @override
  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) async => [];

  @override
  Future<BiliUserProfile> fetchCurrentUserProfile() async {
    profileCalls++;
    if (profiles.isNotEmpty) return profiles.removeAt(0)();
    return const BiliUserProfile(
      isLoggedIn: true,
      mid: 42,
      name: '测试账号',
      avatarUrl: '',
    );
  }
}
