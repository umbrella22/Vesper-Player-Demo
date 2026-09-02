import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';

/// 弹幕层使用 CustomPainter，测试直接检查确定性的渲染计划，不依赖逐条 Text widget。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const target = MediaPlaybackTarget(
    detail: MediaDetail(
      mediaId: 'BV1TEST',
      title: '测试视频',
      coverUrl: '',
      pages: <MediaPlaybackEntry>[
        MediaPlaybackEntry(
          entryId: '11',
          pageNumber: 1,
          title: 'P1',
          durationSeconds: 120,
        ),
      ],
    ),
    entry: MediaPlaybackEntry(
      entryId: '11',
      pageNumber: 1,
      title: 'P1',
      durationSeconds: 120,
    ),
  );

  group('MediaDanmakuOverlaySettings', () {
    test('分别过滤普通位置、字幕、高级和彩色弹幕', () {
      const scroll = MediaDanmakuEvent(id: 'scroll', timeMs: 0, text: 'scroll');
      const top = MediaDanmakuEvent(
        id: 'top',
        timeMs: 0,
        text: 'top',
        style: MediaDanmakuStyle(position: MediaDanmakuPosition.top),
      );
      const bottom = MediaDanmakuEvent(
        id: 'bottom',
        timeMs: 0,
        text: 'bottom',
        style: MediaDanmakuStyle(position: MediaDanmakuPosition.bottom),
      );
      const reverse = MediaDanmakuEvent(
        id: 'reverse',
        timeMs: 0,
        text: 'reverse',
        style: MediaDanmakuStyle(position: MediaDanmakuPosition.reverse),
      );
      const caption = MediaDanmakuEvent(
        id: 'caption',
        timeMs: 0,
        text: 'caption',
        channel: MediaDanmakuChannel.caption,
      );
      const coloredCaption = MediaDanmakuEvent(
        id: 'colored-caption',
        timeMs: 0,
        text: 'colored caption',
        channel: MediaDanmakuChannel.caption,
        style: MediaDanmakuStyle(color: 0x00FF00),
      );
      final advanced = _advancedEvent(id: 'advanced');

      const settings = MediaDanmakuOverlaySettings(
        showScroll: false,
        showTop: false,
        showBottom: false,
        showReverse: false,
        showCaption: false,
        showAdvanced: false,
      );
      expect(settings.allowsStandardEvent(scroll), isFalse);
      expect(settings.allowsStandardEvent(top), isFalse);
      expect(settings.allowsStandardEvent(bottom), isFalse);
      expect(settings.allowsStandardEvent(reverse), isFalse);
      expect(settings.allowsStandardEvent(caption), isFalse);
      expect(settings.allowsAdvancedEvent(advanced), isFalse);

      const monochrome = MediaDanmakuOverlaySettings(showColor: false);
      expect(monochrome.allowsStandardEvent(caption), isTrue);
      expect(monochrome.allowsStandardEvent(coloredCaption), isFalse);
      expect(
        monochrome.allowsStandardEvent(
          const MediaDanmakuEvent(
            id: 'white',
            timeMs: 0,
            text: 'white',
            style: MediaDanmakuStyle(color: 0xFFFFFF),
          ),
        ),
        isTrue,
      );
      expect(
        monochrome.allowsAdvancedEvent(
          _advancedEvent(id: 'colored-advanced', color: 0xFF0000),
        ),
        isFalse,
      );
    });

    test('关键词按大小写敏感的原样子串匹配', () {
      const settings = MediaDanmakuOverlaySettings(
        blockedKeywords: <String>[' Foo ', '弹 幕', 'Ａ'],
      );

      bool allows(String text) => settings.allowsStandardEvent(
        MediaDanmakuEvent(id: text, timeMs: 0, text: text),
      );

      expect(allows('before Foo after'), isFalse);
      expect(allows('before foo after'), isTrue);
      expect(allows('这里有弹 幕空格'), isFalse);
      expect(allows('这里有弹幕但无空格'), isTrue);
      expect(allows('全角Ａ'), isFalse);
      expect(allows('半角A'), isTrue);
    });
  });

  testWidgets('会话快照驱动滚动与固定弹幕上屏', (tester) async {
    final provider = _FakeDanmakuProvider(<MediaDanmakuEvent>[
      const MediaDanmakuEvent(
        id: 'roll',
        timeMs: 0,
        text: '弹幕一号',
        style: MediaDanmakuStyle(color: 0xFFFFFF),
      ),
      const MediaDanmakuEvent(
        id: 'top',
        timeMs: 0,
        text: '顶部弹幕',
        style: MediaDanmakuStyle(
          color: 0x00FF00,
          position: MediaDanmakuPosition.top,
        ),
      ),
      const MediaDanmakuEvent(
        id: 'bottom',
        timeMs: 0,
        text: '底部弹幕',
        style: MediaDanmakuStyle(
          color: 0x0000FF,
          position: MediaDanmakuPosition.bottom,
        ),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaDanmakuLayer(
          provider: provider,
          target: target,
          positionMs: 500,
          playbackState: VesperPlaybackState.playing,
          playbackRate: 1,
        ),
      ),
    );
    await tester.pump();

    final (painter, size) = _painterAndSize(tester);
    expect(
      painter.debugVisibleEventIdsAt(positionMs: 500, size: size),
      containsAll(<String>['roll', 'top', 'bottom']),
    );
    expect(provider.lastSession.positions, <int>[500]);
  });

  testWidgets('未到时的事件不上屏，位置推进后出现', (tester) async {
    final provider = _FakeDanmakuProvider(<MediaDanmakuEvent>[
      const MediaDanmakuEvent(id: 'future', timeMs: 5000, text: '五秒后的弹幕'),
    ]);

    Widget buildLayer(int positionMs) {
      return MaterialApp(
        home: MediaDanmakuLayer(
          provider: provider,
          target: target,
          positionMs: positionMs,
          playbackState: VesperPlaybackState.paused,
          playbackRate: 1,
        ),
      );
    }

    await tester.pumpWidget(buildLayer(1000));
    await tester.pump();
    var (painter, size) = _painterAndSize(tester);
    expect(
      painter.debugVisibleEventIdsAt(positionMs: 1000, size: size),
      isNot(contains('future')),
    );

    await tester.pumpWidget(buildLayer(6000));
    await tester.pump();
    (painter, size) = _painterAndSize(tester);
    expect(
      painter.debugVisibleEventIdsAt(positionMs: 6000, size: size),
      contains('future'),
    );
    expect(provider.lastSession.positions, <int>[1000, 6000]);
  });

  testWidgets('disabled 设置不挂载弹幕画布', (tester) async {
    final provider = _FakeDanmakuProvider(<MediaDanmakuEvent>[
      const MediaDanmakuEvent(id: 'hidden', timeMs: 0, text: '不显示'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaDanmakuLayer(
          provider: provider,
          target: target,
          positionMs: 100,
          playbackState: VesperPlaybackState.playing,
          playbackRate: 1,
          settings: const MediaDanmakuOverlaySettings(enabled: false),
        ),
      ),
    );
    await tester.pump();

    expect(_danmakuPaintFinder, findsNothing);
  });

  testWidgets('播放进度推动正向与逆向弹幕沿相反方向移动', (tester) async {
    final provider = _FakeDanmakuProvider(<MediaDanmakuEvent>[
      const MediaDanmakuEvent(id: 'roll', timeMs: 0, text: '滚动弹幕'),
      const MediaDanmakuEvent(
        id: 'reverse',
        timeMs: 0,
        text: '逆向弹幕',
        style: MediaDanmakuStyle(position: MediaDanmakuPosition.reverse),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaDanmakuLayer(
          provider: provider,
          target: target,
          positionMs: 0,
          playbackState: VesperPlaybackState.paused,
          playbackRate: 1,
        ),
      ),
    );
    await tester.pump();

    final (painter, size) = _painterAndSize(tester);
    final rollAtStart = painter.debugOffsetForEventAt(
      eventId: 'roll',
      positionMs: 0,
      size: size,
    );
    final rollLater = painter.debugOffsetForEventAt(
      eventId: 'roll',
      positionMs: 500,
      size: size,
    );
    final reverseAtStart = painter.debugOffsetForEventAt(
      eventId: 'reverse',
      positionMs: 0,
      size: size,
    );
    final reverseLater = painter.debugOffsetForEventAt(
      eventId: 'reverse',
      positionMs: 500,
      size: size,
    );

    expect(rollLater!.dx, lessThan(rollAtStart!.dx));
    expect(reverseLater!.dx, greaterThan(reverseAtStart!.dx));
  });

  testWidgets('高级弹幕使用独立计划并按延迟后的折线路径插值', (tester) async {
    final provider = _FakeDanmakuProvider(
      const <MediaDanmakuEvent>[
        MediaDanmakuEvent(id: 'standard', timeMs: 0, text: '普通弹幕'),
      ],
      advancedEvents: <MediaAdvancedDanmakuEvent>[
        _advancedEvent(
          id: 'advanced',
          durationMs: 3000,
          motionDurationMs: 2000,
          motionDelayMs: 500,
          path: const <MediaDanmakuPoint>[
            MediaDanmakuPoint(0.1, 0.2),
            MediaDanmakuPoint(0.5, 0.2),
            MediaDanmakuPoint(0.5, 0.8),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaDanmakuLayer(
          provider: provider,
          target: target,
          positionMs: 1000,
          playbackState: VesperPlaybackState.paused,
          playbackRate: 1,
        ),
      ),
    );
    await tester.pump();

    final (painter, size) = _painterAndSize(tester);
    expect(
      painter.debugVisibleEventIdsAt(positionMs: 1000, size: size),
      <String>['standard'],
    );
    expect(
      painter.debugVisibleAdvancedEventIdsAt(positionMs: 1000, size: size),
      <String>['advanced'],
    );

    final beforeMotion = painter.debugAdvancedOffsetForEventAt(
      eventId: 'advanced',
      positionMs: 500,
      size: size,
    );
    final middleTurn = painter.debugAdvancedOffsetForEventAt(
      eventId: 'advanced',
      positionMs: 1500,
      size: size,
    );
    final end = painter.debugAdvancedOffsetForEventAt(
      eventId: 'advanced',
      positionMs: 2500,
      size: size,
    );
    expect(beforeMotion!.dx, closeTo(size.width * 0.1, 0.01));
    expect(beforeMotion.dy, closeTo(size.height * 0.2, 0.01));
    expect(middleTurn!.dx, closeTo(size.width * 0.5, 0.01));
    expect(middleTurn.dy, closeTo(size.height * 0.2, 0.01));
    expect(end!.dx, closeTo(size.width * 0.5, 0.01));
    expect(end.dy, closeTo(size.height * 0.8, 0.01));
  });

  testWidgets('显示区域、密度和字号设置改变确定性渲染计划', (tester) async {
    final events = <MediaDanmakuEvent>[
      const MediaDanmakuEvent(
        id: 'bottom',
        timeMs: 0,
        text: '底部',
        style: MediaDanmakuStyle(position: MediaDanmakuPosition.bottom),
      ),
      const MediaDanmakuEvent(id: 'font', timeMs: 0, text: '字号变化测试'),
      for (var index = 0; index < 20; index += 1)
        MediaDanmakuEvent(
          id: 'top-$index',
          timeMs: 0,
          text: '顶部 $index',
          style: const MediaDanmakuStyle(position: MediaDanmakuPosition.top),
        ),
    ];
    final provider = _FakeDanmakuProvider(events);

    Widget build(MediaDanmakuOverlaySettings settings) => MaterialApp(
      home: MediaDanmakuLayer(
        provider: provider,
        target: target,
        positionMs: 1000,
        playbackState: VesperPlaybackState.paused,
        playbackRate: 1,
        settings: settings,
      ),
    );

    await tester.pumpWidget(
      build(
        const MediaDanmakuOverlaySettings(
          displayArea: 0.25,
          density: 0.2,
          fontScale: 0.6,
        ),
      ),
    );
    await tester.pump();
    var (painter, size) = _painterAndSize(tester);
    final compactBottom = painter.debugOffsetForEventAt(
      eventId: 'bottom',
      positionMs: 1000,
      size: size,
    );
    final compactFont = painter.debugOffsetForEventAt(
      eventId: 'font',
      positionMs: 1000,
      size: size,
    );
    final compactTopCount = painter
        .debugVisibleEventIdsAt(positionMs: 1000, size: size)
        .where((id) => id.startsWith('top-'))
        .length;

    await tester.pumpWidget(
      build(
        const MediaDanmakuOverlaySettings(
          displayArea: 1,
          density: 1,
          fontScale: 1.6,
        ),
      ),
    );
    await tester.pump();
    (painter, size) = _painterAndSize(tester);
    final expandedBottom = painter.debugOffsetForEventAt(
      eventId: 'bottom',
      positionMs: 1000,
      size: size,
    );
    final expandedFont = painter.debugOffsetForEventAt(
      eventId: 'font',
      positionMs: 1000,
      size: size,
    );
    final expandedTopCount = painter
        .debugVisibleEventIdsAt(positionMs: 1000, size: size)
        .where((id) => id.startsWith('top-'))
        .length;

    expect(expandedBottom!.dy, greaterThan(compactBottom!.dy));
    expect(expandedTopCount, greaterThan(compactTopCount));
    expect(expandedFont!.dx, lessThan(compactFont!.dx));
  });

  testWidgets('替换播放目标会关闭旧会话并打开新会话', (tester) async {
    final provider = _FakeDanmakuProvider(const <MediaDanmakuEvent>[]);

    Widget buildLayer(MediaPlaybackTarget value) {
      return MaterialApp(
        home: MediaDanmakuLayer(
          provider: provider,
          target: value,
          positionMs: 0,
          playbackState: VesperPlaybackState.paused,
          playbackRate: 1,
        ),
      );
    }

    await tester.pumpWidget(buildLayer(target));
    final firstSession = provider.lastSession;
    await tester.pumpWidget(
      buildLayer(
        const MediaPlaybackTarget(
          detail: MediaDetail(
            mediaId: 'BV2TEST',
            title: '另一个视频',
            coverUrl: '',
            pages: <MediaPlaybackEntry>[],
          ),
          entry: MediaPlaybackEntry(
            entryId: '22',
            pageNumber: 1,
            title: 'P1',
            durationSeconds: 120,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(firstSession.closed, isTrue);
    expect(provider.sessions, hasLength(2));
  });
}

final Finder _danmakuPaintFinder = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is MediaDanmakuPainter,
);

(MediaDanmakuPainter, Size) _painterAndSize(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(_danmakuPaintFinder);
  return (
    customPaint.painter! as MediaDanmakuPainter,
    tester.getSize(_danmakuPaintFinder),
  );
}

MediaAdvancedDanmakuEvent _advancedEvent({
  required String id,
  int? color,
  int durationMs = 4000,
  int motionDurationMs = 1000,
  int motionDelayMs = 0,
  List<MediaDanmakuPoint> path = const <MediaDanmakuPoint>[
    MediaDanmakuPoint(0.5, 0.5),
  ],
}) {
  return MediaAdvancedDanmakuEvent(
    id: id,
    timeMs: 0,
    text: id,
    path: path,
    durationMs: durationMs,
    motionDurationMs: motionDurationMs,
    motionDelayMs: motionDelayMs,
    alphaFrom: 1,
    alphaTo: 1,
    rotationZDegrees: 0,
    rotationYDegrees: 0,
    color: color,
  );
}

final class _FakeDanmakuProvider implements MediaDanmakuProvider {
  _FakeDanmakuProvider(
    this.events, {
    this.advancedEvents = const <MediaAdvancedDanmakuEvent>[],
  });

  final List<MediaDanmakuEvent> events;
  final List<MediaAdvancedDanmakuEvent> advancedEvents;
  final List<_FakeDanmakuSession> sessions = <_FakeDanmakuSession>[];

  _FakeDanmakuSession get lastSession => sessions.last;

  @override
  MediaDanmakuSession openSession(MediaPlaybackTarget target) {
    final session = _FakeDanmakuSession(events, advancedEvents);
    sessions.add(session);
    return session;
  }
}

final class _FakeDanmakuSession implements MediaDanmakuSession {
  _FakeDanmakuSession(this.events, this.advancedEvents);

  final List<MediaDanmakuEvent> events;
  final List<MediaAdvancedDanmakuEvent> advancedEvents;
  final List<int> positions = <int>[];
  final StreamController<MediaDanmakuSnapshot> _controller =
      StreamController<MediaDanmakuSnapshot>.broadcast(sync: true);
  bool _emitted = false;
  bool closed = false;

  @override
  Stream<MediaDanmakuSnapshot> get snapshots => _controller.stream;

  @override
  void updatePosition(int positionMs) {
    positions.add(positionMs);
    if (!_emitted) {
      _emitted = true;
      _controller.add(
        MediaDanmakuSnapshot(
          events: List<MediaDanmakuEvent>.unmodifiable(events),
          advancedEvents: List<MediaAdvancedDanmakuEvent>.unmodifiable(
            advancedEvents,
          ),
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    await _controller.close();
  }
}
