import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/platform_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('startup frame is not gated by app configuration', (
    tester,
  ) async {
    final configuration = Completer<Widget>();

    await tester.pumpWidget(
      PlatformAppBootstrap(appLoader: () => configuration.future),
    );

    expect(find.byKey(platformAppStartupFrameKey), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(platformAppStartupFrameKey), findsOneWidget);

    configuration.complete(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('configured-app'),
      ),
    );
    await tester.pump();

    expect(find.byKey(platformAppStartupFrameKey), findsNothing);
    expect(find.text('configured-app'), findsOneWidget);
  });
}
