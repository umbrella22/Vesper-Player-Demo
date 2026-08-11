import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';

/// 抽取计划 §6.4 弹幕测试：fake provider 推入归一化事件，
/// 断言 overlay 渲染与滚动行为。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const target = MediaPlaybackTarget(
    detail: MediaDetail(
      mediaId: 'BV1TEST',
      title: '测试视频',
      coverUrl: '',
      pages: <MediaPlaybackEntry>[
        MediaPlaybackEntry(entryId: '11', pageNumber: 1, title: 'P1', durationSeconds: 120),
      ],
    ),
    entry: MediaPlaybackEntry(entryId: '11', pageNumber: 1, title: 'P1', durationSeconds: 120),
  );

  testWidgets('事件流驱动滚动弹幕上屏', (tester) async {
    final provider = _FakeDanmakuProvider(<MediaDanmakuEvent>[
      MediaDanmakuEvent(
        timeMs: 0,
        text: '弹幕一号',
        style: const MediaDanmakuStyle(color: 0xFFFFFF),
      ),
      MediaDanmakuEvent(
        timeMs: 0,
        text: '顶部弹幕',
        style: const MediaDanmakuStyle(
          color: 0xFF00FF00,
          position: MediaDanmakuPosition.top,
        ),
      ),
      MediaDanmakuEvent(
        timeMs: 0,
        text: '底部弹幕',
        style: const MediaDanmakuStyle(
          color: 0xFF0000FF,
          position: MediaDanmakuPosition.bottom,
        ),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: MediaDanmakuLayer(
        provider: provider,
        target: target,
        positionMs: 500,
        playbackState: VesperPlaybackState.playing,
        playbackRate: 1.0,
      )),
    );
    await tester.pump();

    expect(find.text('弹幕一号'), findsOneWidget);
    expect(find.text('顶部弹幕'), findsOneWidget);
    expect(find.text('底部弹幕'), findsOneWidget);
  });

  testWidgets('未到时的事件不上屏，位置推进后出现', (tester) async {
    final provider = _FakeDanmakuProvider(<MediaDanmakuEvent>[
      MediaDanmakuEvent(timeMs: 5000, text: '五秒后的弹幕'),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: MediaDanmakuLayer(
        provider: provider,
        target: target,
        positionMs: 1000,
        playbackState: VesperPlaybackState.paused,
        playbackRate: 1.0,
      )),
    );
    await tester.pump();
    expect(find.text('五秒后的弹幕'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(home: MediaDanmakuLayer(
        provider: provider,
        target: target,
        positionMs: 6000,
        playbackState: VesperPlaybackState.paused,
        playbackRate: 1.0,
      )),
    );
    await tester.pump();
    expect(find.text('五秒后的弹幕'), findsOneWidget);
  });

  testWidgets('disabled 设置不渲染', (tester) async {
    final provider = _FakeDanmakuProvider(<MediaDanmakuEvent>[
      MediaDanmakuEvent(timeMs: 0, text: '不显示'),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: MediaDanmakuLayer(
        provider: provider,
        target: target,
        positionMs: 100,
        playbackState: VesperPlaybackState.playing,
        playbackRate: 1.0,
        settings: const MediaDanmakuOverlaySettings(enabled: false),
      )),
    );
    await tester.pump();
    expect(find.text('不显示'), findsNothing);
  });

  testWidgets('播放暂停时弹幕静止，恢复播放后继续滚动', (tester) async {
    final provider = _FakeDanmakuProvider(<MediaDanmakuEvent>[
      MediaDanmakuEvent(timeMs: 0, text: '滚动弹幕'),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: MediaDanmakuLayer(
        provider: provider,
        target: target,
        positionMs: 0,
        playbackState: VesperPlaybackState.playing,
        playbackRate: 1.0,
      )),
    );
    await tester.pump();
    expect(find.text('滚动弹幕'), findsOneWidget);
    final firstLeft = tester.getTopLeft(find.text('滚动弹幕')).dx;

    // 播放中：位置随播放时钟推进，弹幕持续滚动。
    await tester.pump(const Duration(milliseconds: 500));
    final playingLeft = tester.getTopLeft(find.text('滚动弹幕')).dx;
    expect(playingLeft, lessThan(firstLeft));

    // 暂停：位置冻结，弹幕不再移动。
    await tester.pumpWidget(
      MaterialApp(home: MediaDanmakuLayer(
        provider: provider,
        target: target,
        positionMs: 0,
        playbackState: VesperPlaybackState.paused,
        playbackRate: 1.0,
      )),
    );
    await tester.pump();
    final pausedLeft = tester.getTopLeft(find.text('滚动弹幕')).dx;
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getTopLeft(find.text('滚动弹幕')).dx, pausedLeft);

    // 恢复播放：重新开始推进。
    await tester.pumpWidget(
      MaterialApp(home: MediaDanmakuLayer(
        provider: provider,
        target: target,
        positionMs: 0,
        playbackState: VesperPlaybackState.playing,
        playbackRate: 1.0,
      )),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getTopLeft(find.text('滚动弹幕')).dx, lessThan(pausedLeft));
  });
}

final class _FakeDanmakuProvider implements MediaDanmakuProvider {
  _FakeDanmakuProvider(this.events);

  final List<MediaDanmakuEvent> events;

  @override
  Stream<MediaDanmakuEvent> danmakuFor(MediaPlaybackTarget target) async* {
    for (final event in events) {
      yield event;
    }
  }
}
