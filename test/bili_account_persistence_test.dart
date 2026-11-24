import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';

void main() {
  late Directory current, legacy;
  setUp(() async {
    current = await Directory.systemTemp.createTemp('phone-account-');
    legacy = await Directory.systemTemp.createTemp('legacy-account-');
  });
  tearDown(() async {
    await current.delete(recursive: true);
    await legacy.delete(recursive: true);
  });

  test(
    'corrupt history bytes and malformed records do not block subsequent saves',
    () async {
      final store = BiliHistoryStore(
        baseDirectory: current,
        legacyDirectory: legacy,
      );
      final file = File('${current.path}/bili-playback-history.json');
      for (final contents in [
        [0xff, 0xfe],
        utf8.encode('{'),
      ]) {
        await file.writeAsBytes(contents);
        expect(await store.loadEntries(), isEmpty);
      }
      await file.writeAsString(
        '[{"bvid":"old","cid":1},{"bvid":"bad","cid":"oops"}]',
      );
      await store.saveEntry(
        BiliPlaybackHistoryEntry.fromJson({
          'bvid': 'new',
          'cid': 2,
          'playedAtMs': 2,
        }),
      );
      expect((await store.loadEntries()).map((entry) => entry.bvid), [
        'new',
        'old',
      ]);
    },
  );

  test('logout deletes current and legacy plaintext even when secure deletion fails', () async {
    final storage = _ControlledSecureStorage()..failDelete = true;
    final store = BiliSessionStore(
      baseDirectory: current,
      legacyDirectory: legacy,
      secureStorage: storage,
    );
    final files = [
      for (final dir in [current, legacy])
        File('${dir.path}/bili-session.json'),
    ];
    for (final file in files) {
      await file.writeAsString('{"cookies":{"SESSDATA":"legacy"}}');
    }
    await expectLater(store.clear(), throwsStateError);
    for (final file in files) {
      expect(await file.exists(), isFalse);
    }
    expect(await store.loadCookies(), isEmpty);
  });

  test(
    'an unreadable secure session is left intact when QR tries to replace it',
    () async {
      final storage = _ControlledSecureStorage();
      final store = BiliSessionStore(
        baseDirectory: current,
        legacyDirectory: legacy,
        secureStorage: storage,
      );
      await store.saveCookies({'SESSDATA': 'old'});
      storage.failRead = true;
      await expectLater(
        store.saveCookiesWhileCurrent({
          'SESSDATA': 'new',
        }, isCurrent: () => true),
        throwsStateError,
      );
      storage.failRead = false;
      expect(await store.loadCookies(), {'SESSDATA': 'old'});
    },
  );

  for (final logout in [false, true]) {
    test(
      'cancelled QR persistence preserves prior session with queued logout=$logout',
      () async {
        final storage = _ControlledSecureStorage();
        final store = BiliSessionStore(
          baseDirectory: current,
          legacyDirectory: legacy,
          secureStorage: storage,
        );
        await store.saveCookies({'SESSDATA': 'old'});
        storage.writeGate = Completer<void>();
        var currentAttempt = true;
        final write = store.saveCookiesWhileCurrent({
          'SESSDATA': 'new',
        }, isCurrent: () => currentAttempt);
        await storage.enteredWrite.future;
        currentAttempt = false;
        final pendingLogout = logout ? store.clear() : Future<void>.value();
        storage.writeGate!.complete();
        await write;
        await pendingLogout;
        expect(
          await store.loadCookies(),
          logout ? isEmpty : {'SESSDATA': 'old'},
        );
      },
    );
  }
}

final class _ControlledSecureStorage implements BiliSessionSecureStorage {
  String? payload;
  bool failDelete = false;
  bool failRead = false;
  Completer<void>? writeGate;
  final enteredWrite = Completer<void>();
  @override
  Future<void> delete({required String key}) async {
    if (failDelete) throw StateError('secure storage unavailable');
    payload = null;
  }

  @override
  Future<String?> read({required String key}) async {
    if (failRead) throw StateError('secure storage unreadable');
    return payload;
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final gate = writeGate;
    if (gate != null && !enteredWrite.isCompleted) {
      enteredWrite.complete();
      await gate.future;
    }
    payload = value;
  }
}
