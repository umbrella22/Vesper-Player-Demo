import '../../bili/common/services/bili_text.dart';
import '../models/danmaku_models.dart';

final class BiliDanmakuParser {
  const BiliDanmakuParser();

  List<BiliDanmakuEntry> parse(String xml) {
    final entries = <BiliDanmakuEntry>[];
    final matches = RegExp(
      r'<d\s+p="([^"]+)">([\s\S]*?)</d>',
      dotAll: true,
    ).allMatches(xml);

    for (final match in matches) {
      final payload = match.group(1);
      final rawText = match.group(2);
      if (payload == null || rawText == null) {
        continue;
      }

      final parts = payload.split(',');
      if (parts.length < 4) {
        continue;
      }

      final appearAtMs = ((double.tryParse(parts[0]) ?? 0) * 1000).round();
      final mode = BiliDanmakuMode.fromCode(int.tryParse(parts[1]) ?? 0);
      final fontSize = double.tryParse(parts[2]) ?? 25;
      final colorValue = int.tryParse(parts[3]) ?? 0xFFFFFF;
      final text = biliDecodeHtmlEntities(
        rawText,
      ).replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

      if (appearAtMs < 0 || text.isEmpty) {
        continue;
      }

      entries.add(
        BiliDanmakuEntry(
          appearAtMs: appearAtMs,
          mode: mode,
          fontSize: fontSize,
          colorValue: colorValue,
          text: text,
          rowId: parts.length > 7 ? parts[7] : '$appearAtMs:$text',
        ),
      );
    }

    entries.sort((left, right) => left.appearAtMs.compareTo(right.appearAtMs));
    return entries;
  }
}
