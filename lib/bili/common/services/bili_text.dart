import 'package:vesper_media/media/media.dart';

String biliStripHtmlTags(String raw) {
  return biliDecodeHtmlEntities(
    raw.replaceAll(RegExp(r'<[^>]+>'), ''),
  ).replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? biliExtractBvid(String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return null;
  }

  final directMatch = RegExp(
    r'(BV[0-9A-Za-z]{10})',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (directMatch != null) {
    final match = directMatch.group(1)!;
    return 'BV${match.substring(2)}';
  }

  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    return null;
  }

  for (final segment in uri.pathSegments) {
    final match = RegExp(
      r'BV[0-9A-Za-z]{10}',
      caseSensitive: false,
    ).firstMatch(segment);
    if (match != null) {
      final value = match.group(0)!;
      return 'BV${value.substring(2)}';
    }
  }

  return null;
}

String biliNormalizeImageUrl(String raw) {
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return raw;
  }
  if (raw.startsWith('//')) {
    return 'https:$raw';
  }
  return raw;
}

String biliFormatCount(num? count) {
  if (count == null) {
    return '--';
  }
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
  if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
  return count.toStringAsFixed(count % 1 == 0 ? 0 : 1);
}

String biliFormatDurationSeconds(int seconds) {
  return mediaFormatDurationSeconds(seconds);
}

String biliDecodeHtmlEntities(String raw) {
  return raw
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
}
