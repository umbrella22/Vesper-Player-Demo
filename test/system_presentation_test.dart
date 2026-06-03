import 'package:bilibili_player/app/system_presentation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app system UI mode restores visible status and nav overlays', () async {
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

    expect(calls, hasLength(1));
    expect(calls.single.method, 'SystemChrome.setEnabledSystemUIOverlays');
    expect(calls.single.arguments, <String>[
      'SystemUiOverlay.top',
      'SystemUiOverlay.bottom',
    ]);
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
}
