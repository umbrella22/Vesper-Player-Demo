import 'dart:async';

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

    testWidgets('cancel ignores an in-flight confirmed result', (
      WidgetTester tester,
    ) async {
      final pollCompleter = Completer<BiliQrLoginPollResult>();
      final client = _FakeQrLoginClient()
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
        ),
      );
      await tester.pump();

      expect(client.fetchProfileCalls, 0);
      expect(confirmedCalls, 0);
    });
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
    return const BiliUserProfile(isLoggedIn: true, name: '扫码用户', avatarUrl: '');
  }

  @override
  Map<String, String> snapshotCookies() {
    return const <String, String>{'SESSDATA': 'cookie'};
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
