import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/danmaku/danmaku.dart';

List<int> _varint(int value) {
  final bytes = <int>[];
  var remaining = value;
  while (true) {
    final byte = remaining & 0x7F;
    remaining >>= 7;
    if (remaining == 0) {
      bytes.add(byte);
      return bytes;
    }
    bytes.add(byte | 0x80);
  }
}

List<int> _tag(int field, int wireType) => _varint(field << 3 | wireType);

List<int> _varintField(int field, int value) => <int>[
  ..._tag(field, 0),
  ..._varint(value),
];

List<int> _bytesField(int field, List<int> value) => <int>[
  ..._tag(field, 2),
  ..._varint(value.length),
  ...value,
];

List<int> _fixed32Field(int field, int value) => <int>[
  ..._tag(field, 5),
  for (var shift = 0; shift < 32; shift += 8) (value >> shift) & 0xFF,
];

List<int> _fixed64Field(int field, int value) => <int>[
  ..._tag(field, 1),
  for (var shift = 0; shift < 64; shift += 8) (value >> shift) & 0xFF,
];

void main() {
  const parser = BiliDanmakuViewParser();

  group('BiliDanmakuViewParser', () {
    test('解析分段配置和特殊包 URL，并保持服务端顺序去重', () {
      final segmentConfig = <int>[
        ..._varintField(1, 360000),
        ..._varintField(2, 8),
      ];
      final bytes = <int>[
        ..._varintField(1, 2),
        ..._bytesField(4, segmentConfig),
        ..._bytesField(6, utf8.encode('https://a.hdslb.com/one.bin')),
        ..._bytesField(6, utf8.encode('https://b.hdslb.com/two.bin')),
        ..._bytesField(6, utf8.encode('https://a.hdslb.com/one.bin')),
      ];

      final view = parser.parse(bytes);

      expect(view.state, 2);
      expect(view.segmentPageSizeMs, 360000);
      expect(view.totalSegments, 8);
      expect(view.specialResourceUrls, <String>[
        'https://a.hdslb.com/one.bin',
        'https://b.hdslb.com/two.bin',
      ]);
      expect(
        () => view.specialResourceUrls.add('https://c.hdslb.com/three.bin'),
        throwsUnsupportedError,
      );
    });

    test('支持 gzip，并跳过所有受支持 wire type 的未知字段', () {
      final bytes = <int>[
        ..._varintField(1, 1),
        ..._varintField(80, 7),
        ..._fixed64Field(81, 0x12345678),
        ..._bytesField(82, utf8.encode('future')),
        ..._fixed32Field(83, 0x12345678),
        ..._bytesField(4, <int>[
          ..._varintField(1, 180000),
          ..._varintField(2, 3),
          ..._bytesField(70, utf8.encode('nested-future')),
        ]),
      ];

      final view = parser.parse(gzip.encode(bytes));

      expect(view.state, 1);
      expect(view.segmentPageSizeMs, 180000);
      expect(view.totalSegments, 3);
      expect(view.specialResourceUrls, isEmpty);
    });

    test('拒绝已知字段的错误 wire type', () {
      expect(
        () => parser.parse(_bytesField(1, const <int>[1])),
        throwsFormatException,
      );
      expect(() => parser.parse(_varintField(4, 1)), throwsFormatException);
      expect(() => parser.parse(_varintField(6, 1)), throwsFormatException);
    });

    test('拒绝零字段号、截断字段和无效 UTF-8 URL', () {
      expect(() => parser.parse(const <int>[0]), throwsFormatException);
      expect(
        () => parser.parse(<int>[..._tag(6, 2), 4, 0x61]),
        throwsFormatException,
      );
      expect(
        () => parser.parse(_bytesField(6, const <int>[0xFF])),
        throwsFormatException,
      );
    });
  });
}
