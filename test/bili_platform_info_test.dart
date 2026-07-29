import 'package:vesper_media/bili/common/services/bili_platform_info.dart';
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
}
