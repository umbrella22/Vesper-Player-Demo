import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/danmaku/danmaku.dart';

BiliDanmakuEntry _entry(
  String payload, {
  BiliDanmakuMode mode = BiliDanmakuMode.advanced,
  double fontSize = 30,
  int color = 0x12ABEF,
}) {
  return BiliDanmakuEntry(
    appearAtMs: 1234,
    mode: mode,
    fontSize: fontSize,
    colorValue: color,
    text: payload,
    rowId: 'advanced-id',
    weight: 5,
    pool: 0,
  );
}

void main() {
  const parser = BiliAdvancedDanmakuParser();

  group('BiliAdvancedDanmakuParser', () {
    test('解析绝对坐标、终点、透明度、旋转和运动时间', () {
      final event = parser.tryParse(
        _entry(
          jsonEncode(<Object?>[
            336,
            219,
            '0.2-0.8',
            5,
            '第一行/n第二行',
            30,
            60,
            672,
            438,
            2000,
            500,
          ]),
        ),
      );

      expect(event, isNotNull);
      expect(event!.id, 'advanced-id');
      expect(event.timeMs, 1234);
      expect(event.text, '第一行\n第二行');
      expect(event.path, hasLength(2));
      expect(event.path.first.x, closeTo(0.5, 0.0001));
      expect(event.path.first.y, closeTo(0.5, 0.0001));
      expect(event.path.last.x, closeTo(1, 0.0001));
      expect(event.path.last.y, closeTo(1, 0.0001));
      expect(event.durationMs, 5000);
      expect(event.motionDurationMs, 2000);
      expect(event.motionDelayMs, 500);
      expect(event.alphaFrom, 0.2);
      expect(event.alphaTo, 0.8);
      expect(event.rotationZDegrees, 30);
      expect(event.rotationYDegrees, 60);
      expect(event.color, 0x12ABEF);
      expect(event.fontSizeScale, closeTo(1.2, 0.0001));
    });

    test('浮点坐标按相对值处理，并接受单值透明度', () {
      final event = parser.tryParse(_entry('[0.25,0.75,0.6,2,"relative"]'));

      expect(event, isNotNull);
      expect(event!.path.single.x, 0.25);
      expect(event.path.single.y, 0.75);
      expect(event.alphaFrom, 0.6);
      expect(event.alphaTo, 0.6);
      expect(event.motionDurationMs, 500);
      expect(event.motionDelayMs, 0);
    });

    test('解析 M/L 折线路径且路径优先于终点字段', () {
      final payload = <Object?>[
        10,
        20,
        '1-1',
        4,
        'path',
        0,
        0,
        100,
        200,
        3000,
        100,
        '',
        '',
        '',
        'M0,0 L672,0 L672,438',
      ];

      final event = parser.tryParse(_entry(jsonEncode(payload)));

      expect(event, isNotNull);
      expect(event!.path, hasLength(3));
      expect(event.path[0].x, 0);
      expect(event.path[0].y, 0);
      expect(event.path[1].x, 1);
      expect(event.path[1].y, 0);
      expect(event.path[2].x, 1);
      expect(event.path[2].y, 1);
    });

    test('最多接受 256 个路径点，超出时拒绝而不截断', () {
      String pathWithPoints(int count) => List<String>.generate(
        count,
        (index) => '${index == 0 ? 'M' : 'L'}$index,$index',
      ).join();

      List<Object?> payload(String path) => <Object?>[
        0,
        0,
        '1-1',
        4,
        'path',
        0,
        0,
        '',
        '',
        1000,
        0,
        '',
        '',
        '',
        path,
      ];

      final accepted = parser.tryParse(
        _entry(jsonEncode(payload(pathWithPoints(256)))),
      );
      final rejected = parser.tryParse(
        _entry(jsonEncode(payload(pathWithPoints(257)))),
      );

      expect(accepted?.path, hasLength(256));
      expect(rejected, isNull);
    });

    test('拒绝损坏、越界或带未声明路径命令的 payload', () {
      final invalidPayloads = <String>[
        '{"x": 1}',
        '[0,0,"1-1",4]',
        '["0",0,"1-1",4,"text"]',
        '[0,0,"-0.1-1",4,"text"]',
        '[0,0,"1-2",4,"text"]',
        '[0,0,"1-1",0,"text"]',
        '[0,0,"1-1",12.001,"text"]',
        '[0,0,"1-1",4,""]',
        '[0,0,"1-1",4,"text",0,0,1,1,-1,0]',
        '[0,0,"1-1",4,"text",0,0,"","",1,-1]',
        '[0,0,"1-1",4,"text",0,0,"","",1,0,"","","","C0,0"]',
        '[0,0,"1-1",1e999,"text"]',
      ];

      for (final payload in invalidPayloads) {
        expect(parser.tryParse(_entry(payload)), isNull, reason: payload);
      }
    });

    test('mode 8、mode 9 和未知模式绝不进入高级事件', () {
      const payload = '[0,0,"1-1",4,"do not execute"]';

      expect(
        parser.tryParse(_entry(payload, mode: BiliDanmakuMode.code)),
        isNull,
      );
      expect(
        parser.tryParse(_entry(payload, mode: BiliDanmakuMode.bas)),
        isNull,
      );
      expect(
        parser.tryParse(_entry(payload, mode: BiliDanmakuMode.unsupported)),
        isNull,
      );
    });
  });
}
