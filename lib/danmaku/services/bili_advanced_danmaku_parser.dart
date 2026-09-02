import 'dart:convert';

import 'package:vesper_media/media/media.dart';

import '../models/danmaku_models.dart';

const int biliAdvancedDanmakuMaximumDurationMs = 12000;

/// Renderer budget for a single legacy `M/L` path. Longer paths are rejected
/// as unsupported instead of being truncated and changing their meaning.
const int biliAdvancedDanmakuMaximumPathPoints = 256;

/// Parses the declarative mode-7 JSON array. It deliberately has no mode-8
/// code or mode-9 BAS execution path.
final class BiliAdvancedDanmakuParser {
  const BiliAdvancedDanmakuParser();

  MediaAdvancedDanmakuEvent? tryParse(BiliDanmakuEntry entry) {
    if (entry.mode != BiliDanmakuMode.advanced) {
      return null;
    }
    try {
      final decoded = jsonDecode(entry.text);
      if (decoded is! List<Object?> || decoded.length < 5) {
        return null;
      }
      final start = _point(
        decoded[0],
        decoded[1],
        preserveRelativeNumberKind: true,
      );
      final alpha = _alpha(decoded[2]);
      final lifetimeSeconds = _finiteNumber(decoded[3]);
      final textValue = decoded[4];
      if (start == null ||
          alpha == null ||
          lifetimeSeconds == null ||
          lifetimeSeconds <= 0 ||
          lifetimeSeconds * 1000 > biliAdvancedDanmakuMaximumDurationMs ||
          textValue is! String ||
          textValue.isEmpty) {
        return null;
      }

      final rotationZ = decoded.length > 5 ? _finiteNumber(decoded[5]) : 0.0;
      final rotationY = decoded.length > 6 ? _finiteNumber(decoded[6]) : 0.0;
      if (rotationZ == null || rotationY == null) {
        return null;
      }

      var path = <MediaDanmakuPoint>[start];
      if (decoded.length > 14 && decoded[14] is String) {
        final parsedPath = _parsePath(decoded[14]! as String);
        if (parsedPath == null) {
          return null;
        }
        if (parsedPath.isNotEmpty) {
          path = parsedPath;
        }
      } else if (decoded.length > 8 && decoded[7] != '' && decoded[8] != '') {
        final target = _point(
          decoded[7],
          decoded[8],
          preserveRelativeNumberKind: true,
        );
        if (target == null) {
          return null;
        }
        path = <MediaDanmakuPoint>[start, target];
      }

      final motionDurationMs = _milliseconds(
        decoded.length > 9 ? decoded[9] : null,
        fallback: 500,
      );
      final motionDelayMs = _milliseconds(
        decoded.length > 10 ? decoded[10] : null,
        fallback: 0,
      );
      if (motionDurationMs == null || motionDelayMs == null) {
        return null;
      }

      return MediaAdvancedDanmakuEvent(
        id: entry.rowId,
        timeMs: entry.appearAtMs,
        text: textValue.replaceAll('/n', '\n'),
        path: List<MediaDanmakuPoint>.unmodifiable(path),
        durationMs: (lifetimeSeconds * 1000).round(),
        motionDurationMs: motionDurationMs,
        motionDelayMs: motionDelayMs,
        alphaFrom: alpha.$1,
        alphaTo: alpha.$2,
        rotationZDegrees: rotationZ,
        rotationYDegrees: rotationY,
        color: entry.colorValue,
        fontSizeScale: entry.fontSize > 0 ? entry.fontSize / 25 : 1,
      );
    } on FormatException {
      return null;
    }
  }

  (double, double)? _alpha(Object? value) {
    if (value is num) {
      final alpha = _finiteNumber(value);
      return alpha != null && alpha >= 0 && alpha <= 1 ? (alpha, alpha) : null;
    }
    if (value is! String) {
      return null;
    }
    final parts = value.split('-');
    if (parts.length != 2) {
      return null;
    }
    final from = double.tryParse(parts[0]);
    final to = double.tryParse(parts[1]);
    if (from == null ||
        to == null ||
        !from.isFinite ||
        !to.isFinite ||
        from < 0 ||
        from > 1 ||
        to < 0 ||
        to > 1) {
      return null;
    }
    return (from, to);
  }

  MediaDanmakuPoint? _point(
    Object? x,
    Object? y, {
    required bool preserveRelativeNumberKind,
  }) {
    final normalizedX = _coordinate(
      x,
      axisExtent: 672,
      preserveRelativeNumberKind: preserveRelativeNumberKind,
    );
    final normalizedY = _coordinate(
      y,
      axisExtent: 438,
      preserveRelativeNumberKind: preserveRelativeNumberKind,
    );
    if (normalizedX == null || normalizedY == null) {
      return null;
    }
    return MediaDanmakuPoint(normalizedX, normalizedY);
  }

  double? _coordinate(
    Object? value, {
    required double axisExtent,
    required bool preserveRelativeNumberKind,
  }) {
    if (value is int) {
      return value / axisExtent;
    }
    if (value is double && value.isFinite) {
      return preserveRelativeNumberKind ? value : value / axisExtent;
    }
    return null;
  }

  List<MediaDanmakuPoint>? _parsePath(String source) {
    if (source.isEmpty) {
      return const <MediaDanmakuPoint>[];
    }
    final commandPattern = RegExp(
      r'([ML])\s*(-?(?:\d+(?:\.\d+)?|\.\d+))\s*[, ]\s*'
      r'(-?(?:\d+(?:\.\d+)?|\.\d+))',
    );
    final matches = commandPattern.allMatches(source).toList(growable: false);
    if (matches.isEmpty || matches.first.group(1) != 'M') {
      return null;
    }
    final points = <MediaDanmakuPoint>[];
    var consumed = 0;
    for (final match in matches) {
      if (source.substring(consumed, match.start).trim().isNotEmpty ||
          points.length >= biliAdvancedDanmakuMaximumPathPoints) {
        return null;
      }
      final x = double.tryParse(match.group(2)!);
      final y = double.tryParse(match.group(3)!);
      if (x == null || y == null || !x.isFinite || !y.isFinite) {
        return null;
      }
      points.add(MediaDanmakuPoint(x / 672, y / 438));
      consumed = match.end;
    }
    if (source.substring(consumed).trim().isNotEmpty) {
      return null;
    }
    return points;
  }

  int? _milliseconds(Object? value, {required int fallback}) {
    if (value == null || value == '') {
      return fallback;
    }
    final number = _finiteNumber(value);
    if (number == null || number < 0) {
      return null;
    }
    return number.round();
  }

  double? _finiteNumber(Object? value) {
    if (value is! num) {
      return null;
    }
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }
}
