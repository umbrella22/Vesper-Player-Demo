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

  final directMatch = RegExp(r'(BV[0-9A-Za-z]{10})').firstMatch(normalized);
  if (directMatch != null) {
    return directMatch.group(1);
  }

  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    return null;
  }

  for (final segment in uri.pathSegments) {
    final match = RegExp(r'BV[0-9A-Za-z]{10}').firstMatch(segment);
    if (match != null) {
      return match.group(0);
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
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainingSeconds.toString().padLeft(2, '0')}';
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
