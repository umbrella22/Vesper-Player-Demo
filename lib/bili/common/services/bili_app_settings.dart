import 'dart:convert';
import 'dart:io';

import 'bili_storage_directory.dart';

final class BiliAppSettings {
  const BiliAppSettings({Directory? baseDirectory, Directory? legacyDirectory})
    : _baseDirectory = baseDirectory,
      _legacyDirectory = legacyDirectory;

  final Directory? _baseDirectory;
  final Directory? _legacyDirectory;

  Future<Map<String, Object?>> _loadAll() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return <String, Object?>{};
    }
    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return <String, Object?>{};
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      return <String, Object?>{};
    }
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Future<void> _saveAll(Map<String, Object?> settings) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode(settings));
  }

  Future<bool> getForceTvMode() async {
    final settings = await _loadAll();
    return settings['forceTvMode'] as bool? ?? false;
  }

  Future<void> setForceTvMode(bool value) async {
    final settings = await _loadAll();
    settings['forceTvMode'] = value;
    await _saveAll(settings);
  }

  Future<File> _settingsFile() async {
    return resolveBiliStorageFile(
      fileName: 'bili-app-settings.json',
      baseDirectory: _baseDirectory,
      legacyDirectory: _legacyDirectory,
    );
  }
}
