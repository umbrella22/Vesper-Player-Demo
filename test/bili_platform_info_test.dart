import 'dart:io';

import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/bili/common/services/bili_platform_info.dart';
import 'package:vesper_media/bili/common/services/bili_ui_mode_resolver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('auto rotate status is read fresh from the Android platform', () async {
    const channel = MethodChannel('dev.ikaros.vesper_player/platform');
    var enabled = false;
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return enabled;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(await BiliPlatformInfo.instance.isAutoRotateEnabled(), isFalse);
    enabled = true;
    expect(await BiliPlatformInfo.instance.isAutoRotateEnabled(), isTrue);
    expect(methods, <String>['isAutoRotateEnabled', 'isAutoRotateEnabled']);
  });

  test('HCPP support is read from the Android platform', () async {
    const channel = MethodChannel('dev.ikaros.vesper_player/platform');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return call.method == 'isHcppPlatformSupported';
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(await BiliPlatformInfo.instance.isHcppPlatformSupported(), isTrue);
    expect(methods, <String>['isHcppPlatformSupported']);
  });

  test('playback surface compatibility is read from Android', () async {
    const channel = MethodChannel('dev.ikaros.vesper_player/platform');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return call.method == 'shouldPreferTextureViewForPlayback';
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      await BiliPlatformInfo.instance.shouldPreferTextureViewForPlayback(),
      isTrue,
    );
    expect(methods, <String>['shouldPreferTextureViewForPlayback']);
  });

  test('tablet form factors default to the TV interface', () async {
    const channel = MethodChannel('dev.ikaros.vesper_player/platform');
    final root = Directory(
      '${Directory.systemTemp.path}/bili-tablet-mode-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return call.method == 'isTablet';
        });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final resolver = BiliUiModeResolver(
      appSettings: AppSettingsStore(baseDirectory: root),
    );

    expect(await resolver.resolveEffectiveUiMode(), BiliUiMode.tv);
    expect(methods, <String>['isTv', 'isTablet']);
  });
}
