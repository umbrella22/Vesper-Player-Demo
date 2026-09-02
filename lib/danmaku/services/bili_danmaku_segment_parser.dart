import 'dart:convert';

import '../models/danmaku_models.dart';
import 'bili_protobuf_reader.dart';

/// Parses the binary `DmSegMobileReply` returned by Bilibili's segmented
/// danmaku endpoint. Only fields used by the app are materialized; unknown
/// scalar and length-delimited fields are skipped according to protobuf wire
/// rules.
final class BiliDanmakuSegmentParser {
  const BiliDanmakuSegmentParser();

  List<BiliDanmakuEntry> parse(List<int> responseBytes) {
    final protobufBytes = biliDecodeOptionalGzip(responseBytes);
    final reader = BiliProtobufReader(protobufBytes);
    final entries = <BiliDanmakuEntry>[];

    while (reader.hasMore) {
      final tag = reader.readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 7;
      if (fieldNumber <= 0) {
        throw const FormatException('protobuf field number must be positive');
      }
      if (fieldNumber == 1) {
        biliRequireWireType(fieldNumber, wireType, 2);
        final entry = _parseEntry(
          BiliProtobufReader(reader.readLengthDelimited()),
        );
        if (entry != null) {
          entries.add(entry);
        }
      } else {
        reader.skipField(wireType);
      }
    }

    entries.sort((left, right) {
      final byTime = left.appearAtMs.compareTo(right.appearAtMs);
      return byTime != 0 ? byTime : left.rowId.compareTo(right.rowId);
    });
    return List<BiliDanmakuEntry>.unmodifiable(entries);
  }

  BiliDanmakuEntry? _parseEntry(BiliProtobufReader reader) {
    var id = 0;
    var progressMs = 0;
    var modeCode = 0;
    var fontSize = 25;
    var colorValue = 0xFFFFFF;
    var senderHash = '';
    var text = '';
    var weight = 0;
    var pool = 0;
    var idString = '';

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
          id = reader.readVarint();
        case 2:
          biliRequireWireType(fieldNumber, wireType, 0);
          progressMs = reader.readVarint();
        case 3:
          biliRequireWireType(fieldNumber, wireType, 0);
          modeCode = reader.readVarint();
        case 4:
          biliRequireWireType(fieldNumber, wireType, 0);
          fontSize = reader.readVarint();
        case 5:
          biliRequireWireType(fieldNumber, wireType, 0);
          colorValue = reader.readVarint();
        case 6:
          biliRequireWireType(fieldNumber, wireType, 2);
          senderHash = utf8.decode(reader.readLengthDelimited());
        case 7:
          biliRequireWireType(fieldNumber, wireType, 2);
          text = utf8
              .decode(reader.readLengthDelimited())
              .replaceAll(RegExp(r'[\r\n]+'), ' ');
        case 9:
          biliRequireWireType(fieldNumber, wireType, 0);
          weight = reader.readVarint();
        case 11:
          biliRequireWireType(fieldNumber, wireType, 0);
          pool = reader.readVarint();
        case 12:
          biliRequireWireType(fieldNumber, wireType, 2);
          idString = utf8.decode(reader.readLengthDelimited());
        default:
          reader.skipField(wireType);
      }
    }

    if (progressMs < 0 || text.trim().isEmpty) {
      return null;
    }
    final rowId = idString.isNotEmpty
        ? idString
        : id > 0
        ? id.toString()
        : '$progressMs:$modeCode:$text';
    return BiliDanmakuEntry(
      appearAtMs: progressMs,
      mode: BiliDanmakuMode.fromCode(modeCode),
      fontSize: fontSize > 0 ? fontSize.toDouble() : 25,
      colorValue: colorValue,
      text: text,
      rowId: rowId,
      weight: weight,
      pool: pool,
      senderHash: senderHash,
    );
  }
}
