import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bili_storage_directory.dart';

const String _sessionFileName = 'bili-session.json';
const String _secureSessionKey = 'bili-session-cookies-v1';

abstract interface class BiliSessionSecureStorage {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

final class BiliFlutterSessionSecureStorage
    implements BiliSessionSecureStorage {
  const BiliFlutterSessionSecureStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}

final class BiliSessionStore {
  const BiliSessionStore({
    Directory? baseDirectory,
    Directory? legacyDirectory,
    BiliSessionSecureStorage? secureStorage,
  }) : _baseDirectory = baseDirectory,
       _legacyDirectory = legacyDirectory,
       _secureStorage = secureStorage;

  final Directory? _baseDirectory;
  final Directory? _legacyDirectory;
  final BiliSessionSecureStorage? _secureStorage;

  bool get _usesPlainFileStorage =>
      _secureStorage == null &&
      (_baseDirectory != null || _legacyDirectory != null);

  Future<Map<String, String>> loadCookies() async {
    if (_usesPlainFileStorage) {
      return _loadCookiesFromFile();
    }

    final secureStorage =
        _secureStorage ?? const BiliFlutterSessionSecureStorage();
    final secureCookies = _decodeCookiesPayload(
      await secureStorage.read(key: _secureSessionKey),
    );
    if (secureCookies.isNotEmpty) {
      return secureCookies;
    }

    final fileCookies = await _loadCookiesFromFile();
    if (fileCookies.isNotEmpty) {
      await secureStorage.write(
        key: _secureSessionKey,
        value: _encodeCookiesPayload(fileCookies),
      );
      await _clearSessionFile();
    }
    return fileCookies;
  }

  Future<void> saveCookies(Map<String, String> cookies) async {
    if (_usesPlainFileStorage) {
      await _saveCookiesToFile(cookies);
      return;
    }

    final secureStorage =
        _secureStorage ?? const BiliFlutterSessionSecureStorage();
    await secureStorage.write(
      key: _secureSessionKey,
      value: _encodeCookiesPayload(cookies),
    );
    await _clearSessionFile();
  }

  Future<void> clear() async {
    if (!_usesPlainFileStorage) {
      final secureStorage =
          _secureStorage ?? const BiliFlutterSessionSecureStorage();
      await secureStorage.delete(key: _secureSessionKey);
    }
    await _clearSessionFile();
  }

  Future<Map<String, String>> _loadCookiesFromFile() async {
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

  Future<void> _saveCookiesToFile(Map<String, String> cookies) async {
    final file = await _sessionFile();
    await file.writeAsString(_encodeCookiesPayload(cookies));
  }

  Future<void> _clearSessionFile() async {
    await clearBiliStorageFile(
      fileName: _sessionFileName,
      baseDirectory: _baseDirectory,
      legacyDirectory: _legacyDirectory,
    );
  }

  Future<File> _sessionFile() async {
    return resolveBiliStorageFile(
      fileName: _sessionFileName,
      baseDirectory: _baseDirectory,
      legacyDirectory: _legacyDirectory,
    );
  }

  String _encodeCookiesPayload(Map<String, String> cookies) {
    return jsonEncode(<String, Object?>{
      'savedAtMs': DateTime.now().millisecondsSinceEpoch,
      'cookies': cookies,
    });
  }

  Map<String, String> _decodeCookiesPayload(String? text) {
    if (text == null || text.trim().isEmpty) {
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
}
