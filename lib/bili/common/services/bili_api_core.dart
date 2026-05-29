import 'dart:io';

import '../models/bili_models.dart';
import 'bili_text.dart';

const String biliUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/136.0.0.0 Safari/537.36';

const String biliMediaReferer = 'https://www.bilibili.com';
const String biliBackupMediaHost = 'upos-sz-mirrorcoso1.bilivideo.com';

const int biliRiskControlCode = -352;
const int biliVideoFavoriteType = 2;
const int biliMaxVideoQuality = 127;
const int biliDashFnval = 4048;
const int biliDashCompatFnval = 976;

final class BiliApiException implements Exception {
  const BiliApiException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() {
    if (code == null) {
      return message;
    }
    return '[$code] $message';
  }
}

final class BiliDashRequestVariant {
  const BiliDashRequestVariant({
    required this.label,
    required this.fnval,
    required this.extraParams,
  });

  final String label;
  final int fnval;
  final Map<String, Object?> extraParams;
}

final class BiliDashParseResult {
  const BiliDashParseResult.success(this.manifest) : reason = 'ok';

  const BiliDashParseResult.failure(this.reason) : manifest = null;

  final BiliDashManifestData? manifest;
  final String reason;
}

String? readString(Object? value) {
  return switch (value) {
    null => null,
    String raw => raw.trim().isEmpty ? null : raw.trim(),
    num raw => raw.toString(),
    bool raw => raw.toString(),
    _ => null,
  };
}

int? readInt(Object? value) {
  return switch (value) {
    num raw => raw.toInt(),
    String raw => int.tryParse(raw.trim()),
    _ => null,
  };
}

double? readDouble(Object? value) {
  return switch (value) {
    num raw => raw.toDouble(),
    String raw => double.tryParse(raw.trim()),
    _ => null,
  };
}

bool? readBool(Object? value) {
  return switch (value) {
    bool raw => raw,
    num raw => raw != 0,
    String raw => switch (raw.trim().toLowerCase()) {
      '1' || 'true' || 'yes' => true,
      '0' || 'false' || 'no' => false,
      _ => null,
    },
    _ => null,
  };
}

Map<String, Object?> readObjectMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return const <String, Object?>{};
  }

  final result = <String, Object?>{};
  for (final entry in value.entries) {
    result[entry.key.toString()] = entry.value;
  }
  return result;
}

List<Object?> readObjectList(Object? value) {
  return value is List<Object?> ? value : const <Object?>[];
}

double? parseDashFrameRate(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }

  final separator = raw.indexOf('/');
  if (separator > 0 && separator < raw.length - 1) {
    final numerator = double.tryParse(raw.substring(0, separator));
    final denominator = double.tryParse(raw.substring(separator + 1));
    if (numerator != null && denominator != null && denominator > 0) {
      return numerator / denominator;
    }
  }

  return double.tryParse(raw);
}

String joinIntList(Iterable<int> values) {
  return values.map((value) => value.toString()).join(',');
}

String sanitizeAssetPart(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  return sanitized
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

String readDurationLabel(Object? value) {
  if (value is num) {
    return biliFormatDurationSeconds(value.toInt());
  }

  final raw = readString(value);
  if (raw == null || raw.isEmpty) {
    return '--:--';
  }
  if (raw.contains(':')) {
    return raw;
  }

  final seconds = int.tryParse(raw);
  return seconds == null ? raw : biliFormatDurationSeconds(seconds);
}

String? readRecommendationReason(Object? value) {
  final map = readObjectMap(value);
  if (map.isNotEmpty) {
    final content =
        readString(map['content']) ??
        readString(map['reason_name']) ??
        readString(map['reason']) ??
        readString(map['text']);
    if (content == null || content.isEmpty) {
      return null;
    }
    return biliStripHtmlTags(content);
  }

  final raw = readString(value);
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return biliStripHtmlTags(raw);
}

String? readPublishedAtLabel(Object? value) {
  final unixSeconds = readInt(value);
  if (unixSeconds == null || unixSeconds <= 0) {
    return null;
  }

  return DateTime.fromMillisecondsSinceEpoch(
    unixSeconds * 1000,
  ).toLocal().toString().split(' ').first;
}

List<String> readStringList(Object? value) {
  if (value is List<Object?>) {
    return value
        .map(readString)
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final single = readString(value);
  return single == null || single.isEmpty ? const <String>[] : <String>[single];
}

List<String> readDashMediaUrlCandidates(Map<String, Object?> value) {
  final seen = <String>{};
  final result = <String>[];
  void addAll(Iterable<String> values) {
    for (final value in values) {
      if (value.isNotEmpty && seen.add(value)) {
        result.add(value);
      }
    }
  }

  addAll(readStringList(value['baseUrl']));
  addAll(readStringList(value['base_url']));
  addAll(readStringList(value['backupUrl']));
  addAll(readStringList(value['backup_url']));
  return result;
}

List<String> sortBiliMediaUrlCandidates(List<String> urls) {
  final seen = <String>{};
  final direct = <String>[];
  final pcdn = <String>[];

  for (final url in urls) {
    if (url.isEmpty || !seen.add(url)) {
      continue;
    }
    if (isPcdnMediaUrl(url)) {
      pcdn.add(url);
    } else {
      direct.add(url);
    }
  }

  final sorted = <String>[...direct, ...pcdn];
  if (direct.isEmpty && pcdn.isNotEmpty) {
    final rewritten = replaceMediaHost(pcdn.first, biliBackupMediaHost);
    if (rewritten != null && seen.add(rewritten)) {
      sorted.insert(0, rewritten);
    }
  }
  return sorted;
}

String? selectPreferredDashMediaUrl(List<String> urls) {
  final sorted = sortBiliMediaUrlCandidates(urls);
  if (sorted.isEmpty) {
    return null;
  }
  return sorted.first;
}

bool isPcdnMediaUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.hasPort;
}

String? replaceMediaHost(String url, String host) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: host,
    path: uri.path,
    query: uri.hasQuery ? uri.query : null,
    fragment: uri.hasFragment ? uri.fragment : null,
  ).toString();
}

bool isStaleMediaStatus(int statusCode) {
  return statusCode == HttpStatus.unauthorized ||
      statusCode == HttpStatus.forbidden ||
      statusCode == HttpStatus.notFound ||
      statusCode == HttpStatus.gone;
}

String originFromReferer(String referer) {
  final uri = Uri.tryParse(referer);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'https://www.bilibili.com';
  }
  return uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
}

String formatKeys(Map<String, Object?> value) {
  if (value.isEmpty) {
    return 'none';
  }
  return value.keys.take(10).join(',');
}

String formatRejectReasons(Map<String, int> reasons) {
  if (reasons.isEmpty) {
    return 'none';
  }
  return reasons.entries
      .map((entry) => '${entry.key} x${entry.value}')
      .join(', ');
}

BiliDashStream? rejectDashStream(
  Map<String, int> rejectReasons,
  String reason,
) {
  rejectReasons.update(reason, (count) => count + 1, ifAbsent: () => 1);
  return null;
}

Map<String, String> parseBiliLoginCookiesFromUrl(String? url) {
  if (url == null || url.trim().isEmpty) {
    return const <String, String>{};
  }

  final uri = Uri.tryParse(url);
  final query = uri?.query ?? '';
  if (query.isEmpty) {
    return const <String, String>{};
  }

  const loginCookieNames = <String>{
    'DedeUserID',
    'DedeUserID__ckMd5',
    'SESSDATA',
    'bili_jct',
    'sid',
    'bili_ticket',
    'bili_ticket_expires',
  };
  final cookies = <String, String>{};
  for (final part in query.split('&')) {
    final separator = part.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final key = Uri.decodeQueryComponent(part.substring(0, separator));
    if (!loginCookieNames.contains(key)) {
      continue;
    }
    final value = part.substring(separator + 1);
    if (value.isNotEmpty) {
      cookies[key] = value;
    }
  }
  return cookies;
}

BiliFeedVideo? parseBiliFeedVideo(Map<String, Object?> value) {
  final bvid = readString(value['bvid']);
  if (bvid == null || bvid.isEmpty) {
    return null;
  }

  final owner = readObjectMap(value['owner']);
  final stat = readObjectMap(value['stat']);
  final reason = readRecommendationReason(value['rcmd_reason']);
  final publishedAtLabel = readPublishedAtLabel(
    value['pubdate'] ?? value['ctime'],
  );

  return BiliFeedVideo(
    aid: readInt(value['id']) ?? readInt(value['aid']) ?? 0,
    bvid: bvid,
    title: biliStripHtmlTags(readString(value['title']) ?? bvid),
    author:
        readString(owner['name']) ??
        readString(value['owner_name']) ??
        readString(value['author']) ??
        'UP',
    coverUrl: biliNormalizeImageUrl(
      readString(value['pic']) ?? readString(value['cover']) ?? '',
    ),
    durationLabel: readDurationLabel(value['duration']),
    playCountLabel: biliFormatCount(
      readDouble(stat['view']) ?? readDouble(value['play']),
    ),
    danmakuCountLabel: biliFormatCount(
      readDouble(stat['danmaku']) ?? readDouble(value['danmaku']),
    ),
    description: reason,
    publishedAtLabel: publishedAtLabel,
  );
}
