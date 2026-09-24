import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/app/design/app_theme_controller.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/app/services/danmaku_settings_controller.dart';
import 'package:vesper_media/danmaku/danmaku.dart';
import 'package:vesper_media/common/state/optimistic_value.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppSettingsStore failingStore;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vesper-settings-failure-');
    final blocker = File('${root.path}/blocked');
    await blocker.writeAsString('not a directory');
    failingStore = AppSettingsStore(baseDirectory: Directory(blocker.path));
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'failed consecutive theme writes restore the saved preference',
    () async {
      final controller = AppThemeController(settings: failingStore);
      addTearDown(controller.dispose);
      final first = controller.setPreference(AppThemePreference.dark);
      final second = controller.setPreference(AppThemePreference.light);
      await Future.wait([
        expectLater(first, throwsA(isA<FileSystemException>())),
        expectLater(second, throwsA(isA<FileSystemException>())),
      ]);
      expect(controller.preference, AppThemePreference.system);
    },
  );

  test(
    'failed consecutive danmaku writes restore the saved settings',
    () async {
      final controller = DanmakuSettingsController(store: failingStore);
      addTearDown(controller.dispose);
      const saved = BiliDanmakuSettings();
      final first = controller.setOverlay(saved.overlay.copyWith(opacity: 0.3));
      final second = controller.setOverlay(
        saved.overlay.copyWith(opacity: 0.6),
      );
      expect(await Future.wait([first, second]), [false, false]);
      expect(controller.value, saved);
    },
  );

  test(
    'a failed write after theme disposal preserves the storage error',
    () async {
      final controller = AppThemeController(settings: failingStore);
      final result = controller.setPreference(AppThemePreference.dark);
      controller.dispose();
      await expectLater(result, throwsA(isA<FileSystemException>()));
    },
  );

  test(
    'an earlier failure cannot replace a newer edit with the same value',
    () async {
      final writes = <String>[];
      final gates = List.generate(3, (_) => Completer<void>());
      final published = <String>[];
      final value = OptimisticValue(
        initialValue: 'saved',
        persist: (String next) {
          writes.add(next);
          return gates[writes.length - 1].future;
        },
        onChanged: published.add,
      );
      addTearDown(value.dispose);
      final first = value.setValue('A');
      final middle = value.setValue('B');
      final last = value.setValue('A');
      final firstFailure = expectLater(first, throwsStateError);
      final lastFailure = expectLater(last, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(writes, ['A']);
      gates[0].completeError(StateError('first failed'));
      await firstFailure;
      expect(value.value, 'A');
      expect(published, ['A', 'B', 'A']);
      gates[1].complete();
      await middle;
      gates[2].completeError(StateError('last failed'));
      await lastFailure;
      expect(writes, ['A', 'B', 'A']);
      expect(value.value, 'B');
      expect(published, ['A', 'B', 'A', 'B']);
    },
  );

  test(
    'queued saves survive disposal without publishing further values',
    () async {
      final gate = Completer<void>();
      final published = <int>[];
      final value = OptimisticValue(
        initialValue: 0,
        persist: (int _) => gate.future,
        onChanged: published.add,
      );
      final failure = expectLater(value.setValue(1), throwsStateError);
      value.dispose();
      gate.completeError(StateError('save failed'));
      await failure;
      await value.setValue(2);
      expect(published, [1]);
    },
  );
}
