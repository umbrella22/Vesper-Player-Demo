import 'dart:convert';

import 'package:crypto/crypto.dart';

const List<int> _mixinKeyEncTab = <int>[
  46,
  47,
  18,
  2,
  53,
  8,
  23,
  32,
  15,
  50,
  10,
  31,
  58,
  3,
  45,
  35,
  27,
  43,
  5,
  49,
  33,
  9,
  42,
  19,
  29,
  28,
  14,
  39,
  12,
  38,
  41,
  13,
  37,
  48,
  7,
  16,
  24,
  55,
  40,
  61,
  26,
  17,
  0,
  1,
  60,
  51,
  30,
  4,
  22,
  25,
  54,
  21,
  56,
  59,
  6,
  63,
  57,
  62,
  11,
  36,
  20,
  34,
  44,
  52,
];

final class BiliWbiSigner {
  const BiliWbiSigner();

  Map<String, String> sign({
    required Map<String, Object?> params,
    required String imgKey,
    required String subKey,
    int? timestamp,
  }) {
    final wts = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final normalized = <String, String>{};

    for (final entry in params.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      normalized[entry.key] = _sanitizeValue(value.toString());
    }
    normalized['wts'] = '$wts';

    final sortedKeys = normalized.keys.toList()..sort();
    final encoded = sortedKeys
        .map(
          (key) =>
              '${Uri.encodeQueryComponent(key)}='
              '${Uri.encodeQueryComponent(normalized[key]!)}',
        )
        .join('&');

    final mixinKey = _getMixinKey(imgKey, subKey);
    final wRid = md5.convert(utf8.encode('$encoded$mixinKey')).toString();

    return <String, String>{...normalized, 'w_rid': wRid};
  }

  String getMixinKey(String imgKey, String subKey) {
    return _getMixinKey(imgKey, subKey);
  }

  String _getMixinKey(String imgKey, String subKey) {
    final combined = imgKey + subKey;
    final mixed = _mixinKeyEncTab
        .where((index) => index < combined.length)
        .map((index) => combined[index])
        .join();
    return mixed.substring(0, 32);
  }

  String _sanitizeValue(String value) {
    return value.replaceAll(RegExp(r"[!'()*]"), '');
  }
}
