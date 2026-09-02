import 'dart:io';

/// Protobuf wire reader shared by the Bilibili danmaku response parsers.
/// Message schemas stay in their responsible parser; this type only owns the
/// representation-level wire rules.
final class BiliProtobufReader {
  BiliProtobufReader(this.bytes);

  final List<int> bytes;
  int _offset = 0;

  bool get hasMore => _offset < bytes.length;

  int readVarint() {
    var result = 0;
    for (var byteIndex = 0; byteIndex < 10; byteIndex += 1) {
      final byte = _readByte();
      if (byteIndex == 9 && byte > 1) {
        throw const FormatException('protobuf varint exceeds 64 bits');
      }
      result |= (byte & 0x7F) << (byteIndex * 7);
      if (byte & 0x80 == 0) {
        return result;
      }
    }
    throw const FormatException('protobuf varint exceeds 64 bits');
  }

  List<int> readLengthDelimited() {
    final length = readVarint();
    if (length > bytes.length - _offset) {
      throw const FormatException('protobuf length-delimited field truncated');
    }
    final value = bytes.sublist(_offset, _offset + length);
    _offset += length;
    return value;
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
      case 1:
        _skip(8);
      case 2:
        readLengthDelimited();
      case 5:
        _skip(4);
      default:
        throw FormatException('unsupported protobuf wire type $wireType');
    }
  }

  int _readByte() {
    if (_offset >= bytes.length) {
      throw const FormatException('protobuf stream truncated');
    }
    return bytes[_offset++];
  }

  void _skip(int count) {
    if (count > bytes.length - _offset) {
      throw const FormatException('protobuf fixed-width field truncated');
    }
    _offset += count;
  }
}

List<int> biliDecodeOptionalGzip(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    return gzip.decode(bytes);
  }
  return bytes;
}

void biliRequireWireType(int fieldNumber, int actual, int expected) {
  if (actual != expected) {
    throw FormatException(
      'protobuf field $fieldNumber uses wire type $actual; expected $expected',
    );
  }
}
