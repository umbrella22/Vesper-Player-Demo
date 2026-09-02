import 'dart:convert';

import '../models/danmaku_models.dart';
import 'bili_protobuf_reader.dart';

/// Parses the declared subset of Bilibili's `DmWebViewReply` metadata.
final class BiliDanmakuViewParser {
  const BiliDanmakuViewParser();

  BiliDanmakuView parse(List<int> responseBytes) {
    final reader = BiliProtobufReader(biliDecodeOptionalGzip(responseBytes));
    var state = 0;
    var segmentPageSizeMs = 0;
    var totalSegments = 0;
    final specialResourceUrls = <String>[];

    while (reader.hasMore) {
      final tag = reader.readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 7;
      if (fieldNumber <= 0) {
        throw const FormatException('protobuf field number must be positive');
      }
      switch (fieldNumber) {
        case 1:
          biliRequireWireType(fieldNumber, wireType, 0);
          state = reader.readVarint();
        case 4:
          biliRequireWireType(fieldNumber, wireType, 2);
          final segment = _parseSegmentConfig(
            BiliProtobufReader(reader.readLengthDelimited()),
          );
          segmentPageSizeMs = segment.$1;
          totalSegments = segment.$2;
        case 6:
          biliRequireWireType(fieldNumber, wireType, 2);
          final url = utf8.decode(reader.readLengthDelimited());
          if (url.isNotEmpty && !specialResourceUrls.contains(url)) {
            specialResourceUrls.add(url);
          }
        default:
          reader.skipField(wireType);
      }
    }

    return BiliDanmakuView(
      state: state,
      segmentPageSizeMs: segmentPageSizeMs,
      totalSegments: totalSegments,
      specialResourceUrls: List<String>.unmodifiable(specialResourceUrls),
    );
  }

  (int, int) _parseSegmentConfig(BiliProtobufReader reader) {
    var pageSizeMs = 0;
    var total = 0;
    while (reader.hasMore) {
      final tag = reader.readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 7;
      if (fieldNumber <= 0) {
        throw const FormatException('protobuf field number must be positive');
      }
      switch (fieldNumber) {
        case 1:
          biliRequireWireType(fieldNumber, wireType, 0);
          pageSizeMs = reader.readVarint();
        case 2:
          biliRequireWireType(fieldNumber, wireType, 0);
          total = reader.readVarint();
        default:
          reader.skipField(wireType);
      }
    }
    return (pageSizeMs, total);
  }
}
