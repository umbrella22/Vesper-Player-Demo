import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/playback/media_playback_settings_surface.dart';
import 'package:vesper_media/media/player/media_glass_sheet.dart';

void main() {
  for (final appearance in MediaGlassSheetAppearance.values) {
    testWidgets('$appearance sheet follows keyboard opening and resizing', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppVisualTokens.mobileLightTheme(),
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showMediaGlassSheet<void>(
                context: context,
                appearance: appearance,
                builder: (_) => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(autofocus: true),
                    SizedBox(height: 180),
                    Text('表单底部'),
                  ],
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final sheet = appearance == MediaGlassSheetAppearance.readable
          ? find.byKey(const ValueKey<String>('media-readable-glass-sheet'))
          : find.byType(GlassSheet);
      for (final keyboardHeight in [300.0, 440.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(sheet).bottom,
          closeTo(844 - keyboardHeight - 8, 1),
        );
        expect(tester.getRect(sheet).top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'a short landscape sheet can scroll its actions above an open keyboard',
    (tester) async {
      _setViewport(tester, const Size(740, 360));
      tester.view.viewInsets = const FakeViewPadding(bottom: 190);
      var submitted = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppVisualTokens.mobileDarkTheme(),
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showMediaGlassSheet<void>(
                context: context,
                appearance: MediaGlassSheetAppearance.readable,
                builder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const TextField(autofocus: true),
                    const SizedBox(height: 300),
                    FilledButton(
                      onPressed: () => submitted = true,
                      child: const Text('提交'),
                    ),
                  ],
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final sheet = find.byKey(
        const ValueKey<String>('media-readable-glass-sheet'),
      );
      await tester.scrollUntilVisible(
        find.text('提交'),
        80,
        scrollable: find
            .descendant(of: sheet, matching: find.byType(Scrollable))
            .first,
      );
      expect(tester.getRect(sheet).bottom, lessThanOrEqualTo(170));
      expect(tester.getRect(find.text('提交')).bottom, lessThan(170));
      await tester.tap(find.text('提交'));
      expect(submitted, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('side drawer reveals a focused lower field above the keyboard', (
    tester,
  ) async {
    _setViewport(tester, const Size(900, 600));
    const fieldKey = ValueKey<String>('drawer-input');
    const drawerKey = ValueKey<String>('test-drawer');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.mobileDarkTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showMediaPlaybackSideDrawer<void>(
              context,
              side: MediaPlaybackDrawerSide.trailing,
              surfaceKey: drawerKey,
              builder: (_) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 370),
                  TextField(key: fieldKey),
                  SizedBox(height: 600),
                ],
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(fieldKey));
    await tester.enterText(find.byKey(fieldKey), 'keyword');
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(drawerKey)).bottom,
      lessThanOrEqualTo(350),
    );
    expect(tester.getRect(find.byKey(fieldKey)).bottom, lessThanOrEqualTo(350));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}
