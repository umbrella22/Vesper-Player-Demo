import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/playback/media_playback_settings_surface.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  for (final isPortrait in [true, false]) {
    testWidgets('settings react without a player tick (portrait=$isPortrait)', (
      tester,
    ) async {
      final player = _SettingsPlayer();
      final selection = signal('自动');
      addTearDown(player.snapshotListenable.dispose);
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppVisualTokens.mobileDarkTheme(),
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showMediaPlaybackSettingsSurface(
                context,
                isPortrait: isPortrait,
                controller: player,
                contentBuilder: (_, _) => Text(selection.value),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('自动'), findsOneWidget);
      selection.value = '1080P';
      await tester.pump();
      expect(find.text('1080P'), findsOneWidget);
      expect(find.text('自动'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

final class _SettingsPlayer implements VesperPlayerController {
  @override
  final snapshotListenable = ValueNotifier(
    const VesperPlayerSnapshot.initial(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
