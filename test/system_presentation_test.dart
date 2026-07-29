import 'dart:async';

import 'package:vesper_media/app/system_presentation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app system UI mode restores visible edge-to-edge overlays', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await setBiliSystemUiMode(SystemUiMode.edgeToEdge);

    expect(calls, hasLength(3));
    expect(calls[0].method, 'SystemChrome.setEnabledSystemUIOverlays');
    expect(calls[0].arguments, <String>[
      'SystemUiOverlay.top',
      'SystemUiOverlay.bottom',
    ]);
    expect(calls[1].method, 'SystemChrome.setEnabledSystemUIMode');
    expect(calls[1].arguments, 'SystemUiMode.edgeToEdge');
    expect(calls[2].method, 'SystemChrome.restoreSystemUIOverlays');
  });

  test('immersive system UI mode does not force overlays visible', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await setBiliSystemUiMode(SystemUiMode.immersiveSticky);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'SystemChrome.setEnabledSystemUIMode');
    expect(calls.single.arguments, 'SystemUiMode.immersiveSticky');
  });

  test(
    'playback keeps light status icons and theme-aware navigation icons',
    () {
      final light = playbackSystemUiStyleForBrightness(Brightness.light);
      final dark = playbackSystemUiStyleForBrightness(Brightness.dark);

      expect(light.statusBarIconBrightness, Brightness.light);
      expect(light.systemNavigationBarIconBrightness, Brightness.dark);
      expect(dark.statusBarIconBrightness, Brightness.light);
      expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    },
  );

  test('returning from tv mode restores app system overlays', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await setBiliSystemUiMode(SystemUiMode.immersiveSticky);
    await setBiliSystemUiMode(SystemUiMode.edgeToEdge);

    expect(calls.map((call) => call.method), <String>[
      'SystemChrome.setEnabledSystemUIMode',
      'SystemChrome.setEnabledSystemUIOverlays',
      'SystemChrome.setEnabledSystemUIMode',
      'SystemChrome.restoreSystemUIOverlays',
    ]);
    expect(calls[0].arguments, 'SystemUiMode.immersiveSticky');
    expect(calls[1].arguments, <String>[
      'SystemUiOverlay.top',
      'SystemUiOverlay.bottom',
    ]);
    expect(calls[2].arguments, 'SystemUiMode.edgeToEdge');
  });

  group('app orientation policy on Android', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('locks portrait when system auto rotate is disabled', () async {
      final orientations = await resolveBiliAppPreferredOrientations(
        readAutoRotateEnabled: () async => false,
      );

      expect(orientations, biliPortraitOrientations);
    });

    test('returns control to the system when auto rotate is enabled', () async {
      final orientations = await resolveBiliAppPreferredOrientations(
        readAutoRotateEnabled: () async => true,
      );

      expect(orientations, biliAppDefaultOrientations);
    });

    test(
      'tv to app applies landscape then portrait with rotation off',
      () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              calls.add(call);
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await setBiliPreferredOrientations(biliLandscapeOrientations);
        await setBiliAppPreferredOrientations(
          readAutoRotateEnabled: () async => false,
        );

        final orientationCalls = calls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .map((call) => (call.arguments as List<Object?>).cast<String>())
            .toList();
        expect(orientationCalls, <List<String>>[
          <String>[
            'DeviceOrientation.landscapeLeft',
            'DeviceOrientation.landscapeRight',
          ],
          <String>['DeviceOrientation.portraitUp'],
        ]);
      },
    );

    test('tv to app releases orientation with rotation enabled', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await setBiliPreferredOrientations(biliLandscapeOrientations);
      await setBiliAppPreferredOrientations(
        readAutoRotateEnabled: () async => true,
      );

      final orientationCalls = calls
          .where(
            (call) => call.method == 'SystemChrome.setPreferredOrientations',
          )
          .map((call) => (call.arguments as List<Object?>).cast<String>())
          .toList();
      expect(orientationCalls.last, isEmpty);
    });

    test('stale app restore cannot override a newer tv request', () async {
      final calls = <MethodCall>[];
      final autoRotate = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final pendingRestore = setBiliAppPreferredOrientations(
        readAutoRotateEnabled: () => autoRotate.future,
      );
      await setBiliPreferredOrientations(biliLandscapeOrientations);
      autoRotate.complete(false);
      await pendingRestore;

      final orientationCalls = calls.where(
        (call) => call.method == 'SystemChrome.setPreferredOrientations',
      );
      expect(orientationCalls, hasLength(1));
      expect(orientationCalls.single.arguments, <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
    });

    test('foreground refresh preserves an active fullscreen lock', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await setBiliPreferredOrientations(biliLandscapeOrientations);
      await refreshBiliAppPreferredOrientationsIfActive(
        readAutoRotateEnabled: () async => false,
      );

      final orientationCalls = calls.where(
        (call) => call.method == 'SystemChrome.setPreferredOrientations',
      );
      expect(orientationCalls, hasLength(1));
      expect(orientationCalls.single.arguments, <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
    });
  });
}
