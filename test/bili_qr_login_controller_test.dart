import 'dart:async';
import 'dart:io';

import 'package:vesper_media/bili/common/services/bili_api_core.dart';

import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/common/widgets/bili_qr_login_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BiliQrLoginController', () {
    testWidgets('failed terminal state allows refreshing the QR code', (
      WidgetTester tester,
    ) async {
      final client = _FakeQrLoginClient()
        ..pollSteps.add(
          () async => const BiliQrLoginPollResult(
            status: BiliQrLoginStatus.failed,
            message: '登录失败',
          ),
        );
      final controller = _buildController(client);
      addTearDown(controller.dispose);

      await controller.start();
      await tester.pump();

      expect(controller.pollResult.value?.status, BiliQrLoginStatus.failed);
      expect(controller.canRefresh, isTrue);
    });

    testWidgets(
      'successful manual check clears an error and resumes automatic polling',
      (WidgetTester tester) async {
        final client = _FakeQrLoginClient()
          ..pollSteps.addAll(<_PollStep>[
            () async => throw StateError('poll failed'),
            () async => const BiliQrLoginPollResult(
              status: BiliQrLoginStatus.waitingForScan,
              message: '等待扫码',
            ),
            () async => const BiliQrLoginPollResult(
              status: BiliQrLoginStatus.scannedAwaitingConfirm,
              message: '已扫码',
            ),
          ]);
        final controller = _buildController(client);
        addTearDown(controller.dispose);

        try {
          await controller.start();
          await tester.pump();

          expect(client.pollCalls, 1);
          expect(controller.errorMessage.value, contains('poll failed'));

          await controller.checkNow();

          expect(client.pollCalls, 2);
          expect(controller.errorMessage.value, isNull);
          expect(
            controller.pollResult.value?.status,
            BiliQrLoginStatus.waitingForScan,
          );

          await tester.pump(const Duration(seconds: 2));
          await tester.pump();

          expect(client.pollCalls, 3);
          expect(
            controller.pollResult.value?.status,
            BiliQrLoginStatus.scannedAwaitingConfirm,
          );
        } finally {
          controller.cancel();
        }
      },
    );

    testWidgets('automatic network retries back off and leave buttons stable', (
      tester,
    ) async {
      final inFlight = Completer<BiliQrLoginPollResult>();
      final client = _FakeQrLoginClient()
        ..pollSteps.addAll([
          () => inFlight.future,
          () async =>
              throw const BiliApiException('timeout', outcomeUnknown: true),
          () async => const BiliQrLoginPollResult(
            status: BiliQrLoginStatus.scannedAwaitingConfirm,
            message: '',
          ),
          () async => const BiliQrLoginPollResult(
            status: BiliQrLoginStatus.expired,
            message: '',
          ),
        ]);
      final controller = _buildController(client);
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.checkLabel, '立即检查状态');
      expect(controller.canCheck, isTrue);
      expect(controller.canRefresh, isTrue);
      final manual = controller.checkNow();
      expect(controller.checkLabel, '检查中');
      expect(client.pollCalls, 1);
      inFlight.completeError(const SocketException('offline'));
      await manual;
      expect(controller.statusMessage, contains('自动重试'));
      await tester.pump(const Duration(seconds: 3));
      expect(client.pollCalls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(client.pollCalls, 2);
      await tester.pump(const Duration(seconds: 7));
      expect(client.pollCalls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.errorMessage.value, isNull);
      expect(controller.canRefresh, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.canCheck, isFalse);
      await tester.pump(const Duration(minutes: 1));
      expect(client.pollCalls, 4);
    });

    testWidgets('an API refusal stops automatic retries', (tester) async {
      final client = _FakeQrLoginClient()
        ..pollSteps.add(
          () async => throw const BiliApiException('拒绝', code: 403),
        );
      final controller = _buildController(client);
      addTearDown(controller.dispose);
      await controller.start();
      await tester.pump(const Duration(minutes: 1));
      expect(client.pollCalls, 1);
      expect(controller.errorMessage.value, contains('拒绝'));
    });

    for (final mode in [
      'reject profile',
      'profile error',
      'cancel',
      'other account',
    ]) {
      testWidgets(
        'confirmed ticket respects $mode during profile verification',
        (tester) async {
          final profile = Completer<BiliUserProfile>();
          final client = _FakeQrLoginClient()
            ..restoreCookies({'SESSDATA': 'old'})
            ..profile = profile.future
            ..pollSteps.add(
              () async => const BiliQrLoginPollResult(
                status: BiliQrLoginStatus.confirmed,
                message: '',
                cookieUpdates: {'SESSDATA': 'new'},
              ),
            );
          var completions = 0;
          final controller = _buildController(
            client,
            onConfirmed: (_) => completions++,
          );
          addTearDown(controller.dispose);
          await controller.start();
          await tester.pump();
          expect(client.transport.cookieValue('SESSDATA'), 'new');
          if (mode == 'cancel') controller.cancel();
          if (mode == 'other account') {
            client.restoreCookies({'SESSDATA': 'other'});
          }
          if (mode == 'profile error') {
            profile.completeError(const SocketException('offline'));
          } else {
            profile.complete(
              BiliUserProfile(
                isLoggedIn: mode != 'reject profile',
                name: '',
                avatarUrl: '',
              ),
            );
          }
          await tester.pump();
          expect(completions, 0);
          expect(
            client.transport.cookieValue('SESSDATA'),
            mode == 'other account' ? 'other' : 'old',
          );
          if (mode != 'cancel') expect(controller.canRefresh, isTrue);
        },
      );
    }

    test('failed secure write rolls back confirmed credentials and never reports success', () async {
      final dir = await Directory.systemTemp.createTemp('phone-qr-write-');
      addTearDown(() => dir.delete(recursive: true));
      final storage = _FailFirstWriteStorage();
      final client = _FakeQrLoginClient()..restoreCookies({'SESSDATA': 'old'});
      final poll = Completer<BiliQrLoginPollResult>();
      client.pollSteps.add(() => poll.future);
      final store = BiliSessionStore(
        baseDirectory: dir,
        legacyDirectory: dir,
        secureStorage: storage,
      );
      var completions = 0;
      final controller = BiliQrLoginController(
        client: client,
        sessionStore: store,
        onConfirmed: (_) => completions++,
      );
      addTearDown(controller.dispose);
      await controller.start();
      final finished = controller.checkNow();
      poll.complete(
        const BiliQrLoginPollResult(
          status: BiliQrLoginStatus.confirmed,
          message: '',
          cookieUpdates: {'SESSDATA': 'new'},
        ),
      );
      await finished;
      expect(controller.pollResult.value?.status, BiliQrLoginStatus.failed);
      expect(controller.canRefresh, isTrue);
      expect(completions, 0);
      expect(controller.errorMessage.value, contains('无法保存登录信息'));
      expect(client.snapshotCookies()['SESSDATA'], 'old');
      expect(await store.loadCookies(), {'SESSDATA': 'old'});
    });

    testWidgets('cancel ignores an in-flight confirmed result', (
      WidgetTester tester,
    ) async {
      final pollCompleter = Completer<BiliQrLoginPollResult>();
      final client = _FakeQrLoginClient()
        ..restoreCookies(const <String, String>{'SESSDATA': 'existing-session'})
        ..pollSteps.add(() => pollCompleter.future);
      var confirmedCalls = 0;
      final controller = _buildController(
        client,
        onConfirmed: (_) => confirmedCalls += 1,
      );
      addTearDown(controller.dispose);

      await controller.start();
      expect(client.pollCalls, 1);

      controller.cancel();
      pollCompleter.complete(
        const BiliQrLoginPollResult(
          status: BiliQrLoginStatus.confirmed,
          message: '登录成功',
          cookieUpdates: <String, String?>{'SESSDATA': 'cancelled-session'},
        ),
      );
      await tester.pump();

      expect(client.fetchProfileCalls, 0);
      expect(confirmedCalls, 0);
      expect(client.transport.cookieValue('SESSDATA'), 'existing-session');
    });

    testWidgets('refresh rejects credentials from the previous QR attempt', (
      WidgetTester tester,
    ) async {
      final oldPoll = Completer<BiliQrLoginPollResult>();
      final newPoll = Completer<BiliQrLoginPollResult>();
      final client = _FakeQrLoginClient()
        ..pollSteps.addAll([() => oldPoll.future, () => newPoll.future]);
      final controller = _buildController(client);
      addTearDown(controller.dispose);

      await controller.start();
      await controller.refresh();
      newPoll.complete(
        const BiliQrLoginPollResult(
          status: BiliQrLoginStatus.confirmed,
          message: '登录成功',
          cookieUpdates: <String, String?>{'SESSDATA': 'current-session'},
        ),
      );
      await tester.pump();
      expect(client.fetchProfileCalls, 1);
      expect(client.transport.cookieValue('SESSDATA'), 'current-session');

      oldPoll.complete(
        const BiliQrLoginPollResult(
          status: BiliQrLoginStatus.confirmed,
          message: '登录成功',
          cookieUpdates: <String, String?>{'SESSDATA': 'old-session'},
        ),
      );
      await tester.pump();
      expect(client.fetchProfileCalls, 1);
      expect(client.transport.cookieValue('SESSDATA'), 'current-session');
    });

    testWidgets(
      'empty failed message falls back cleanly and TLS handshake triggers transient retry',
      (WidgetTester tester) async {
        final client = _FakeQrLoginClient()
          ..pollSteps.addAll(<_PollStep>[
            () async => throw const HandshakeException('tls reset'),
            () async => const BiliQrLoginPollResult(
              status: BiliQrLoginStatus.failed,
              message: '',
            ),
          ]);
        final controller = _buildController(client);
        addTearDown(controller.dispose);

        await controller.start();
        await tester.pump();
        expect(controller.statusMessage, '连接中断，将自动重试。');

        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(controller.pollResult.value?.status, BiliQrLoginStatus.failed);
        expect(controller.statusMessage, '登录失败，请刷新二维码重试。');
      },
    );
  });
}

typedef _PollStep = Future<BiliQrLoginPollResult> Function();

BiliQrLoginController _buildController(
  _FakeQrLoginClient client, {
  void Function(BiliUserProfile)? onConfirmed,
}) {
  return BiliQrLoginController(
    client: client,
    sessionStore: const BiliSessionStore(
      secureStorage: _MemorySessionSecureStorage(),
    ),
    onConfirmed: onConfirmed ?? (_) {},
  );
}

final class _FakeQrLoginClient extends BiliClient {
  final List<_PollStep> pollSteps = <_PollStep>[];
  int pollCalls = 0;
  int fetchProfileCalls = 0;
  Future<BiliUserProfile>? profile;

  @override
  Future<BiliQrLoginTicket> generateQrLoginTicket() async {
    return const BiliQrLoginTicket(
      url: 'https://example.test/qr',
      qrcodeKey: 'qr-key',
    );
  }

  @override
  Future<BiliQrLoginPollResult> pollQrLogin(String qrcodeKey) {
    pollCalls += 1;
    if (pollSteps.isEmpty) {
      return Future<BiliQrLoginPollResult>.value(
        const BiliQrLoginPollResult(
          status: BiliQrLoginStatus.waitingForScan,
          message: '等待扫码',
        ),
      );
    }
    return pollSteps.removeAt(0)();
  }

  @override
  Future<BiliUserProfile> fetchCurrentUserProfile() async {
    fetchProfileCalls += 1;
    if (profile != null) return profile!;
    return const BiliUserProfile(isLoggedIn: true, name: '扫码用户', avatarUrl: '');
  }
}

final class _MemorySessionSecureStorage implements BiliSessionSecureStorage {
  const _MemorySessionSecureStorage();

  @override
  Future<void> delete({required String key}) async {}

  @override
  Future<String?> read({required String key}) async => null;

  @override
  Future<void> write({required String key, required String value}) async {}
}

final class _FailFirstWriteStorage implements BiliSessionSecureStorage {
  String? payload = '{"cookies":{"SESSDATA":"old"}}';
  var failNextWrite = true;
  @override
  Future<String?> read({required String key}) async => payload;
  @override
  Future<void> delete({required String key}) async {
    payload = null;
  }

  @override
  Future<void> write({required String key, required String value}) async {
    payload = value;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('secure write failed');
    }
  }
}
