/// Codec segment shared by DASH representation IDs and persisted asset IDs.
/// Keep its case, ASCII filtering and fallback stable for existing downloads.
String biliDashCodecToken(String codecs) {
  final buffer = StringBuffer();
  for (final codeUnit in codecs.codeUnits) {
    final isNumber = codeUnit >= 48 && codeUnit <= 57;
    final isUpper = codeUnit >= 65 && codeUnit <= 90;
    final isLower = codeUnit >= 97 && codeUnit <= 122;
    if (isNumber || isUpper || isLower) {
      buffer.writeCharCode(codeUnit);
    }
  }
  final value = buffer.toString();
  return value.isEmpty ? 'codec' : value;
}
