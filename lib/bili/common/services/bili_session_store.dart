import 'dart:convert';
import 'dart:io';

import 'bili_storage_directory.dart';

final class BiliSessionStore {
  const BiliSessionStore({Directory? baseDirectory, Directory? legacyDirectory})
    : _baseDirectory = baseDirectory,
      _legacyDirectory = legacyDirectory;

  final Directory? _baseDirectory;
  final Directory? _legacyDirectory;

  Future<Map<String, String>> loadCookies() async {
    final file = await _sessionFile();
    if (!await file.exists()) {
      return const <String, String>{};
    }

    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return const <String, String>{};
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      return const <String, String>{};
    }

    final rawCookies = decoded['cookies'];
    if (rawCookies is! Map) {
      return const <String, String>{};
    }

    return rawCookies.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  Future<void> saveCookies(Map<String, String> cookies) async {
    final file = await _sessionFile();
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'savedAtMs': DateTime.now().millisecondsSinceEpoch,
        'cookies': cookies,
      }),
    );
  }

  Future<void> clear() async {
    await clearBiliStorageFile(
      fileName: 'bili-session.json',
      baseDirectory: _baseDirectory,
      legacyDirectory: _legacyDirectory,
    );
  }

  Future<File> _sessionFile() async {
    return resolveBiliStorageFile(
      fileName: 'bili-session.json',
      baseDirectory: _baseDirectory,
      legacyDirectory: _legacyDirectory,
    );
  }
}
