import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
    String? secureText;
    var secureReadFailed = false;
    try {
      secureText = await secureStorage.read(key: _secureSessionKey);
    } catch (error) {
      secureReadFailed = true;
      // Keychain read failures (backup migration, key invalidation,
      // PlatformException) must not fail app bootstrap. Degrade to the
      // plain-file fallback below; a later saveCookies rewrites the key.
      // 只记录异常类型，异常消息可能携带 Keychain 内部的敏感片段。
      debugPrint(
        '[BiliSession] secure storage read failed: ${error.runtimeType}',
      );
    }
    final secureCookies = _decodeCookiesPayload(secureText);
    if (secureCookies.isNotEmpty) {
      return secureCookies;
    }

    final fileCookies = await _loadCookiesFromFile();
    if (fileCookies.isNotEmpty) {
      try {
        await secureStorage.write(
          key: _secureSessionKey,
          value: _encodeCookiesPayload(fileCookies),
        );
        // 只有本次成功读取过安全存储时才删除明文文件：读取失败可能意味着
        // Keychain 持续不可用，写入成功并不能证明下次启动能读回，删除明文
        // 会让下一次启动丢失整个会话。读取正常（迁移路径）时删除明文。
        if (!secureReadFailed) {
          await _clearSessionFile();
        }
      } catch (error) {
        // 迁移写入失败不得丢弃已恢复的会话：保留明文文件，下次启动重试。
        debugPrint(
          '[BiliSession] secure storage write failed: ${error.runtimeType}',
        );
      }
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
    try {
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
    } catch (error) {
      // A corrupt session file (interrupted write, partial migration) must
      // not fail bootstrap. Treat it as "no persisted session"; a later
      // successful login overwrites the file.
      // 只记录异常类型：FormatException 消息可能包含文件中的原始片段，
      // 而该文件可能含有 Cookie 值。
      debugPrint(
        '[BiliSession] session file read failed: ${error.runtimeType}',
      );
      return const <String, String>{};
    }
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

    try {
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
    } catch (error) {
      // A corrupt secure payload (e.g. partial migration) must not fail
      // bootstrap; the file fallback below still gets a chance to restore.
      // 只记录异常类型：消息可能携带 Keychain 返回的原始片段。
      debugPrint(
        '[BiliSession] secure payload decode failed: ${error.runtimeType}',
      );
      return const <String, String>{};
    }
  }
}
