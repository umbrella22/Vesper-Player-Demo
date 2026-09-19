import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_danmaku_composer.dart';
import 'package:vesper_media/media/media.dart';

void main() {
  testWidgets('synthetic events cannot expose server actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DanmakuEventSheet(
            event: MediaDanmakuEvent(
              id: 'local:100',
              timeMs: 100,
              text: '本地弹幕',
              hasServerId: false,
              senderHash: 'sender',
            ),
            senderBlocked: false,
            interaction: MediaDanmakuInteractionState(
              canLike: true,
              canRetract: true,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('danmaku-action-like')), findsNothing);
    expect(find.byKey(const ValueKey('danmaku-action-retract')), findsNothing);
    expect(find.byKey(const ValueKey('danmaku-action-copy')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('danmaku-action-block-sender')),
      findsOneWidget,
    );
  });

  testWidgets('own event menu disables writes while a request is pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DanmakuEventSheet(
            event: MediaDanmakuEvent(id: '701', timeMs: 100, text: '我的弹幕'),
            senderBlocked: false,
            interaction: MediaDanmakuInteractionState(
              canLike: true,
              canRetract: true,
              liked: true,
              pending: true,
            ),
          ),
        ),
      ),
    );
    for (final key in ['danmaku-action-like', 'danmaku-action-retract']) {
      final action = tester.widget<DanmakuSheetAction>(
        find.byKey(ValueKey(key)),
      );
      expect(action.onTap, isNull);
    }
    expect(find.text('处理中…'), findsOneWidget);
  });

  testWidgets('successful send clears the draft and reports it', (
    tester,
  ) async {
    final sender = _FakeSender();
    await _pumpComposer(tester, sender);
    await tester.enterText(_input, '测试弹幕');
    await tester.tap(find.byKey(const ValueKey('bili-danmaku-send')));
    await tester.pumpAndSettle();

    expect(sender.requests.single.text, '测试弹幕');
    expect(sender.requests.single.positionMs, 4200);
    expect(_input, findsNothing);
    expect(find.text('弹幕已发送'), findsOneWidget);
    await tester.tap(_entry);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(_input);
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('failure keeps the draft for retry', (tester) async {
    final sender = _FakeSender()..errorMessage = '弹幕发送过于频繁';
    await _pumpComposer(tester, sender);
    await tester.enterText(_input, '失败弹幕');
    await tester.tap(find.byKey(const ValueKey('bili-danmaku-send')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(_input);
    expect(field.controller!.text, '失败弹幕');
    expect(find.text('弹幕发送过于频繁'), findsOneWidget);
  });

  testWidgets('an unknown result keeps the draft and does not resend', (
    tester,
  ) async {
    final sender = _FakeSender()..pending = true;
    await _pumpComposer(tester, sender);
    await tester.enterText(_input, '超时弹幕');
    await tester.tap(find.byKey(const ValueKey('bili-danmaku-send')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(_input);
    expect(field.controller!.text, '超时弹幕');
    expect(find.textContaining('请稍后在弹幕列表中确认'), findsOneWidget);
    // 只提交一次，不自动重发。
    expect(sender.requests, hasLength(1));
  });

  testWidgets('rapid taps do not submit twice', (tester) async {
    final sender = _FakeSender()..delay = Completer<void>();
    await _pumpComposer(tester, sender);
    await tester.enterText(_input, '连点弹幕');
    await tester.tap(find.byKey(const ValueKey('bili-danmaku-send')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bili-danmaku-send')));
    await tester.pump();
    expect(sender.requests, hasLength(1));

    sender.delay!.complete();
    await tester.pumpAndSettle();
    expect(sender.requests, hasLength(1));
  });

  testWidgets('empty draft is not submitted', (tester) async {
    final sender = _FakeSender();
    await _pumpComposer(tester, sender);
    await tester.enterText(_input, '   ');
    await tester.tap(find.byKey(const ValueKey('bili-danmaku-send')));
    await tester.pumpAndSettle();
    expect(sender.requests, isEmpty);
  });

  testWidgets('entry opens focused input and reopening preserves the draft', (
    tester,
  ) async {
    final sender = _FakeSender();
    await _pumpComposer(tester, sender, openInput: false);
    expect(_input, findsNothing);
    expect(find.text('点我发弹幕'), findsOneWidget);
    await tester.tap(_entry);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(_input, '暂存弹幕');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_input, findsNothing);
    expect(sender.requests, isEmpty);
    await tester.tap(_entry);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_input).controller!.text, '暂存弹幕');
  });

  testWidgets('send reads the playback position after typing', (tester) async {
    final sender = _FakeSender();
    var positionMs = 4200;
    await _pumpComposer(tester, sender, currentPositionMs: () => positionMs);
    await tester.enterText(_input, '当前时间');
    positionMs = 9100;
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(sender.requests.single.positionMs, 9100);
  });

  for (final size in [const Size(320, 640), const Size(640, 360)]) {
    testWidgets('input stays above the keyboard at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await _pumpComposer(tester, _FakeSender());
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      final inputBar = tester.getRect(
        find.byKey(const ValueKey('bili-danmaku-input-bar')),
      );
      expect(inputBar.bottom, lessThanOrEqualTo(size.height - 200));
      expect(inputBar.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  }
}

final Finder _input = find.byKey(const ValueKey('bili-danmaku-input'));
final Finder _entry = find.byKey(const ValueKey('bili-danmaku-entry'));

Future<void> _pumpComposer(
  WidgetTester tester,
  _FakeSender sender, {
  bool openInput = true,
  int Function()? currentPositionMs,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BiliDanmakuComposer(
          sendController: MediaDanmakuSendController.forTesting(sender),
          currentPositionMs: currentPositionMs ?? () => 4200,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (openInput) {
    await tester.tap(_entry);
    await tester.pumpAndSettle();
  }
}

final class _FakeSender implements MediaDanmakuSessionSender {
  final requests = <MediaDanmakuSendRequest>[];
  String? errorMessage;
  bool pending = false;
  Completer<void>? delay;

  @override
  Stream<MediaDanmakuSnapshot> get snapshots =>
      const Stream<MediaDanmakuSnapshot>.empty();

  @override
  void updatePosition(int positionMs) {}

  @override
  Future<void> close() async {}

  @override
  Future<MediaDanmakuSendResult> send(MediaDanmakuSendRequest request) async {
    requests.add(request);
    final waiting = delay;
    if (waiting != null) {
      await waiting.future;
    }
    if (pending) {
      return const MediaDanmakuSendResult.pending();
    }
    final error = errorMessage;
    if (error != null) {
      return MediaDanmakuSendResult.failure(error);
    }
    return MediaDanmakuSendResult.success(
      MediaDanmakuEvent(
        id: 'dmid',
        timeMs: request.positionMs,
        text: request.text,
      ),
    );
  }
}
