import 'package:bilibili_player/app/system_presentation.dart';
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
}
