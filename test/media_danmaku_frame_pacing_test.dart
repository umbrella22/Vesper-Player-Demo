import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  for (final hz in [60, 120, 144]) {
    for (final scenario in ['ordinary', '5000-loaded', 'advanced-hidden']) {
      testWidgets('$hz Hz follows vsync for $scenario', (tester) async {
        tester.view.display.refreshRate = hz.toDouble();
        addTearDown(tester.view.display.resetRefreshRate);
        await tester.pumpWidget(_overlay(scenario: scenario));
        final painter = _painter(tester);
        var count = 0;
        void repaint() => count++;
        painter.addListener(repaint);
        await _pumpFrames(tester, hz, hz);
        expect(count, hz);
        painter.removeListener(repaint);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('sustained expensive visible frames reduce cadence and recover', (
    tester,
  ) async {
    tester.view.display.refreshRate = 120;
    addTearDown(tester.view.display.resetRefreshRate);
    await tester.pumpWidget(_overlay());
    final painter = _painter(tester);
    var count = 0;
    void repaint() => count++;
    painter.addListener(repaint);
    _reportFrames(tester, 29, 10000);
    await _pumpFrames(tester, 120, 12);
    expect(count, 12, reason: 'A short spike does not change cadence');
    _reportFrames(tester, 1, 10000);
    count = 0;
    await _pumpFrames(tester, 120, 12);
    expect(count, 6);
    _reportFrames(tester, 120, 1000);
    count = 0;
    await _pumpFrames(tester, 120, 12);
    expect(count, 12, reason: 'Sustained headroom restores native cadence');
    painter.removeListener(repaint);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'invisible loaded items do not respond to unrelated slow frames',
    (tester) async {
      tester.view.display.refreshRate = 144;
      addTearDown(tester.view.display.resetRefreshRate);
      await tester.pumpWidget(_overlay(visible: false));
      final painter = _painter(tester);
      var count = 0;
      void repaint() => count++;
      painter.addListener(repaint);
      _reportFrames(tester, 60, 40000);
      await _pumpFrames(tester, 144, 24);
      expect(count, 24);
      painter.removeListener(repaint);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disabled or paused danmaku stops the animation driver', (
    tester,
  ) async {
    await tester.pumpWidget(_overlay());
    final painter = _painter(tester);
    var count = 0;
    void repaint() => count++;
    painter.addListener(repaint);
    await tester.pumpWidget(_overlay(state: VesperPlaybackState.paused));
    count = 0;
    await _pumpFrames(tester, 60, 12);
    expect(count, 0);
    await tester.pumpWidget(_overlay(enabled: false));
    count = 0;
    await _pumpFrames(tester, 60, 12);
    expect(count, 0);
    painter.removeListener(repaint);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _overlay({
  String scenario = 'ordinary',
  bool visible = true,
  bool enabled = true,
  VesperPlaybackState state = VesperPlaybackState.playing,
}) {
  return MaterialApp(
    home: MediaDanmakuOverlay(
      events: [
        MediaDanmakuEvent(
          id: 'ordinary',
          timeMs: visible ? 0 : 100000,
          text: 'test',
        ),
        if (scenario == '5000-loaded')
          for (var i = 1; i < 5000; i++)
            MediaDanmakuEvent(
              id: 'future-$i',
              timeMs: 100000 + i,
              text: 'future',
            ),
      ],
      advancedEvents: scenario == 'advanced-hidden'
          ? const [
              MediaAdvancedDanmakuEvent(
                id: 'advanced',
                timeMs: 100000,
                text: 'hidden',
                path: [MediaDanmakuPoint(1, 0), MediaDanmakuPoint(0, 0)],
                durationMs: 5000,
                motionDurationMs: 5000,
                motionDelayMs: 0,
                alphaFrom: 1,
                alphaTo: 1,
                rotationZDegrees: 0,
                rotationYDegrees: 0,
              ),
            ]
          : [],
      positionMs: 1000,
      playbackState: state,
      playbackRate: 1,
      settings: MediaDanmakuOverlaySettings(
        enabled: enabled,
        showAdvanced: false,
      ),
    ),
  );
}

CustomPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is MediaDanmakuPainter,
      ),
    )
    .painter!;

Future<void> _pumpFrames(WidgetTester tester, int hz, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(Duration(microseconds: (1000000 / hz).ceil()));
  }
}

void _reportFrames(WidgetTester tester, int count, int workUs) {
  tester.binding.platformDispatcher.onReportTimings?.call([
    for (var i = 0; i < count; i++)
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: workUs,
        rasterStart: workUs,
        rasterFinish: workUs * 2,
        rasterFinishWallTime: workUs * 2,
      ),
  ]);
}
