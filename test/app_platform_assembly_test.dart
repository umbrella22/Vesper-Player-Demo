import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/app/app.dart';

void main() {
  testWidgets('VesperApp renders a provider-neutral injected home', (
    tester,
  ) async {
    final tvMode = ValueNotifier<bool>(false);
    addTearDown(tvMode.dispose);

    await tester.pumpWidget(
      VesperApp(
        host: VesperAppHost(
          appTitle: 'Example Media',
          tvModeListenable: tvMode,
          homeBuilder: (_) => const Scaffold(
            body: Center(child: Text('example-provider-home')),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('example-provider-home'), findsOneWidget);

    tvMode.value = true;
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Example Media');
    expect(app.themeMode, ThemeMode.dark);
  });

  test('main and generic app shell do not import a concrete provider', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final appSource = File('lib/app/app.dart').readAsStringSync();

    expect(mainSource, contains("import 'platform_app.dart';"));
    expect(mainSource, isNot(contains('/bili/')));
    expect(appSource, isNot(contains('/bili/')));
    expect(appSource, isNot(contains('BiliClient')));
    expect(appSource, isNot(contains('BiliUiModeController')));
  });
}
