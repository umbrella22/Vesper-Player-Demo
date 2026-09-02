import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/danmaku/danmaku.dart';

List<int> _varint(int value) {
  final output = <int>[];
  var remaining = value;
  while (true) {
    final byte = remaining & 0x7F;
    remaining >>= 7;
    if (remaining == 0) {
      output.add(byte);
      return output;
    }
    output.add(byte | 0x80);
  }
}

List<int> _tag(int field, int wireType) => _varint(field << 3 | wireType);

List<int> _varintField(int field, int value) => <int>[
  ..._tag(field, 0),
  ..._varint(value),
];

List<int> _bytesField(int field, List<int> bytes) => <int>[
  ..._tag(field, 2),
  ..._varint(bytes.length),
  ...bytes,
];

List<int> _fixed32Field(int field, int value) => <int>[
  ..._tag(field, 5),
  for (var shift = 0; shift < 32; shift += 8) (value >> shift) & 0xFF,
];

List<int> _fixed64Field(int field, int value) => <int>[
  ..._tag(field, 1),
  for (var shift = 0; shift < 64; shift += 8) (value >> shift) & 0xFF,
];

List<int> _entry({
  int id = 0,
  required int progressMs,
  int mode = 1,
  int fontSize = 25,
  int color = 0xFFFFFF,
  required String text,
  int weight = 0,
  int pool = 0,
  String senderHash = '',
  String idString = '',
}) {
  return <int>[
    if (id > 0) ..._varintField(1, id),
    ..._varintField(2, progressMs),
    ..._varintField(3, mode),
    ..._varintField(4, fontSize),
    ..._varintField(5, color),
    if (senderHash.isNotEmpty) ..._bytesField(6, utf8.encode(senderHash)),
    ..._bytesField(7, utf8.encode(text)),
    ..._varintField(9, weight),
    ..._varintField(11, pool),
    if (idString.isNotEmpty) ..._bytesField(12, utf8.encode(idString)),
  ];
}

void main() {
  const parser = BiliDanmakuSegmentParser();

  group('BiliDanmakuSegmentParser', () {
    test('解码渲染所需字段并保留普通空格', () {
      final reply = _bytesField(
        1,
        _entry(
          id: 1844674407,
          progressMs: 61000,
          mode: 1,
          fontSize: 30,
          color: 0x12ABEF,
          text: ' 你好  弹幕\n第二行 ',
          weight: 6,
          pool: 1,
          senderHash: 'sender Hash 原样',
          idString: 'stable-id',
        ),
      );

      final entries = parser.parse(reply);

      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.appearAtMs, 61000);
      expect(entry.mode, BiliDanmakuMode.scroll);
      expect(entry.fontSize, 30);
      expect(entry.colorValue, 0x12ABEF);
      expect(entry.text, ' 你好  弹幕 第二行 ');
      expect(entry.weight, 6);
      expect(entry.pool, 1);
      expect(entry.senderHash, 'sender Hash 原样');
      expect(entry.rowId, 'stable-id');
    });

    test('按时间排序并跳过所有受支持 wire type 的未知字段', () {
      final later = <int>[
        ..._entry(progressMs: 2000, text: 'later'),
        ..._varintField(90, 7),
        ..._bytesField(91, utf8.encode('future')),
        ..._fixed32Field(92, 0x12345678),
        ..._fixed64Field(93, 0x12345678),
      ];
      final earlier = _entry(progressMs: 1000, text: 'earlier');
      final reply = <int>[
        ..._bytesField(1, later),
        ..._varintField(20, 1),
        ..._bytesField(1, earlier),
      ];

      final entries = parser.parse(reply);

      expect(entries.map((entry) => entry.text), <String>['earlier', 'later']);
    });

    test('支持 gzip 响应体', () {
      final reply = _bytesField(
        1,
        _entry(id: 7, progressMs: 1234, text: 'compressed'),
      );

      final entries = parser.parse(gzip.encode(reply));

      expect(entries.single.rowId, '7');
      expect(entries.single.text, 'compressed');
    });

    test('缺少服务端 id 时生成稳定且可区分模式的键', () {
      final entries = parser.parse(
        _bytesField(1, _entry(progressMs: 1000, mode: 5, text: 'no id')),
      );

      expect(entries.single.rowId, '1000:5:no id');
    });

    test('保留 BAS 模式供业务层统一过滤，并丢弃空文本', () {
      final reply = <int>[
        ..._bytesField(1, _entry(progressMs: 3000, mode: 9, text: 'script')),
        ..._bytesField(1, _entry(progressMs: 4000, text: '  \n  ')),
      ];

      final entries = parser.parse(reply);

      expect(entries, hasLength(1));
      expect(entries.single.mode, BiliDanmakuMode.bas);
    });

    test('拒绝错误 wire type', () {
      expect(
        () => parser.parse(_varintField(1, 1)),
        throwsA(isA<FormatException>()),
      );
    });

    test('拒绝截断的 length-delimited 字段', () {
      expect(
        () => parser.parse(<int>[..._tag(1, 2), 5, 8]),
        throwsA(isA<FormatException>()),
      );
    });

    test('拒绝无效 UTF-8 文本', () {
      final entry = <int>[
        ..._varintField(2, 1000),
        ..._varintField(3, 1),
        ..._bytesField(7, <int>[0xFF]),
      ];

      expect(
        () => parser.parse(_bytesField(1, entry)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
