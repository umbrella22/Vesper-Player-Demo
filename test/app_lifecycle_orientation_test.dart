import 'package:vesper_media/app/system_presentation.dart';
import 'package:vesper_media/platform_app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'app resume follows auto rotate without overriding a fixed landscape',
    (tester) async {
      const platformChannel = MethodChannel(
        'dev.ikaros.vesper_player/platform',
      );
      var autoRotateEnabled = false;
      final platformMethods = <String>[];
      final systemCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        platformChannel,
        (call) async {
          platformMethods.add(call.method);
          if (call.method == 'isAutoRotateEnabled') {
            return autoRotateEnabled;
          }
          return false;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          systemCalls.add(call);
          return null;
        },
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          platformChannel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });

      Future<void> flushOrientationRequest() async {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }

      List<List<String>> orientationCalls() => systemCalls
          .where(
            (call) => call.method == 'SystemChrome.setPreferredOrientations',
          )
          .map((call) => (call.arguments as List<Object?>).cast<String>())
          .toList();

      void pauseAndResumeApp() {
        for (final state in <AppLifecycleState>[
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
      }

      await tester.pumpWidget(const PlatformApp());
      await flushOrientationRequest();

      expect(platformMethods, contains('isAutoRotateEnabled'));
      expect(orientationCalls().last, <String>['DeviceOrientation.portraitUp']);

      platformMethods.clear();
      systemCalls.clear();
      autoRotateEnabled = true;
      pauseAndResumeApp();
      await flushOrientationRequest();

      expect(platformMethods, contains('isAutoRotateEnabled'));
      expect(orientationCalls().last, isEmpty);

      await setBiliPreferredOrientations(biliLandscapeOrientations);
      platformMethods.clear();
      systemCalls.clear();
      pauseAndResumeApp();
      await flushOrientationRequest();

      expect(platformMethods, isEmpty);
      expect(orientationCalls(), isEmpty);
    },
  );
}
