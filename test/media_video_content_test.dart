import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_media/media/playback/media_video_content.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  for (final rect in [
    const Rect.fromLTWH(115, 0, 170, 300),
    const Rect.fromLTWH(0, 37.5, 400, 225),
  ]) {
    testWidgets('canvas and confirmed taps follow content rect $rect', (
      tester,
    ) async {
      final harness = _ContentHarness();
      await harness.pump(tester);
      harness.report(rect);
      await tester.pump();

      final painterFinder = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is MediaDanmakuPainter,
      );
      final origin = tester.getTopLeft(find.byKey(_stageKey));
      expect(tester.getTopLeft(painterFinder), origin + rect.topLeft);
      expect(tester.getSize(painterFinder), rect.size);
      expect(
        find.ancestor(of: painterFinder, matching: find.byType(ClipRect)),
        findsWidgets,
      );
      final painter =
          tester.widget<CustomPaint>(painterFinder).painter!
              as MediaDanmakuPainter;
      final point =
          painter.debugOffsetForEventAt(
            eventId: 'top',
            positionMs: 500,
            size: rect.size,
          )! +
          const Offset(8, 8);

      expect(harness.tap(rect.topLeft + point), isTrue);
      expect(harness.selected, ['top']);
      expect(
        harness.tap(const Offset(5, 5)),
        isFalse,
        reason: 'black bars cannot select',
      );
      expect(harness.tap(rect.bottomRight), isFalse);

      harness.playing = true;
      await harness.pump(tester);
      expect(harness.tap(rect.topLeft + point), isFalse);
      harness.playing = false;
      harness.enabled = false;
      await harness.pump(tester);
      expect(harness.tap(rect.topLeft + point), isFalse);
      expect(harness.selected, ['top']);
    });
  }

  testWidgets(
    'unknown geometry keeps the overlay mounted without painting or selection',
    (tester) async {
      final harness = _ContentHarness();
      await harness.pump(tester);
      expect(find.byType(MediaDanmakuOverlay), findsNothing);
      final overlay = find.byType(MediaDanmakuOverlay, skipOffstage: false);
      expect(overlay, findsOneWidget);
      final originalState = tester.state(overlay);
      expect(harness.tap(const Offset(200, 10)), isFalse);

      harness.report(const Rect.fromLTWH(0, 0, 400, 300));
      await tester.pump();
      expect(find.byType(MediaDanmakuOverlay), findsOneWidget);
      expect(tester.state(overlay), same(originalState));

      harness.geometry(null);
      await tester.pump();
      expect(find.byType(MediaDanmakuOverlay), findsNothing);
      expect(tester.state(overlay), same(originalState));
      expect(harness.tap(const Offset(200, 10)), isFalse);
    },
  );

  testWidgets(
    'resize and view replacement reject geometry from the previous view',
    (tester) async {
      final harness = _ContentHarness();
      await harness.pump(tester);
      harness.report(const Rect.fromLTWH(0, 0, 400, 300));
      await tester.pump();
      expect(find.byType(MediaDanmakuOverlay), findsOneWidget);
      harness.size = const Size(300, 400);
      await harness.pump(tester);
      expect(find.byType(MediaDanmakuOverlay), findsNothing);
      harness.report(const Rect.fromLTWH(0, 0, 300, 400));
      await tester.pump();
      expect(find.byType(MediaDanmakuOverlay), findsOneWidget);

      final oldGeometryCallback = harness.geometry;
      harness.viewKey = const ValueKey('new-view');
      await harness.pump(tester);
      oldGeometryCallback(
        const VesperVideoSurfaceGeometry(
          width: 300,
          height: 400,
          contentRect: VesperVideoRect(
            left: 0,
            top: 0,
            width: 300,
            height: 400,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MediaDanmakuOverlay), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source transition suppresses overlay until current geometry can be used',
    (tester) async {
      final harness = _ContentHarness();
      await harness.pump(tester);
      harness.report(const Rect.fromLTWH(0, 0, 400, 300));
      await tester.pump();
      harness.active = false;
      await harness.pump(tester);
      expect(find.byType(MediaDanmakuOverlay), findsNothing);
      expect(harness.tap(const Offset(200, 10)), isFalse);
      harness.geometry(null);
      harness.report(const Rect.fromLTWH(115, 0, 170, 300));
      await tester.pump();
      expect(find.byType(MediaDanmakuOverlay), findsNothing);
      harness.active = true;
      await harness.pump(tester);
      expect(
        tester.getSize(find.byType(MediaDanmakuOverlay)),
        const Size(170, 300),
      );
    },
  );
}

const _stageKey = ValueKey('test-stage');

class _ContentHarness {
  Size size = const Size(400, 300);
  Key viewKey = const ValueKey('initial-view');
  bool active = true;
  bool playing = false;
  bool enabled = true;
  final selected = <String>[];
  late ValueChanged<VesperVideoSurfaceGeometry?> geometry;
  late bool Function(Offset) tap;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: MediaVideoContent(
              key: viewKey,
              active: active,
              builder: (onGeometry, overlay, onTap) {
                geometry = onGeometry;
                tap = onTap;
                return Stack(
                  key: _stageKey,
                  fit: StackFit.expand,
                  children: [overlay!],
                );
              },
              overlayBuilder: (interaction, visible) => MediaDanmakuOverlay(
                events: const [
                  MediaDanmakuEvent(
                    id: 'top',
                    timeMs: 0,
                    text: '暂停时选择弹幕',
                    style: MediaDanmakuStyle(
                      position: MediaDanmakuPosition.top,
                    ),
                  ),
                ],
                positionMs: 500,
                playbackState: playing
                    ? VesperPlaybackState.playing
                    : VesperPlaybackState.paused,
                playbackRate: 1,
                settings: MediaDanmakuOverlaySettings(
                  enabled: visible && enabled,
                ),
                interactionController: interaction,
                onEventSelected: (event) => selected.add(event.id),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void report(Rect rect) => geometry(
    VesperVideoSurfaceGeometry(
      width: size.width,
      height: size.height,
      contentRect: VesperVideoRect(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
      ),
    ),
  );
}
