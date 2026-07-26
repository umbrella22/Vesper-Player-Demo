import 'dart:convert';
import 'dart:io';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'bili_storage_directory.dart';

final class BiliAppSettings {
  const BiliAppSettings({Directory? baseDirectory, Directory? legacyDirectory})
    : _baseDirectory = baseDirectory,
      _legacyDirectory = legacyDirectory;

  final Directory? _baseDirectory;
  final Directory? _legacyDirectory;

  static final Map<String, Future<void>> _writeQueues =
      <String, Future<void>>{};

  Future<Map<String, Object?>> _loadAll() async {
    final file = await _settingsFile();
    return _loadAllFrom(file);
  }

  Future<Map<String, Object?>> _loadAllFrom(File file) async {
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
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> _saveAllTo(File file, Map<String, Object?> settings) async {
    await file.writeAsString(jsonEncode(settings));
  }

  Future<bool> getForceTvMode() async {
    final settings = await _loadAll();
    return settings['forceTvMode'] as bool? ?? false;
  }

  Future<void> setForceTvMode(bool value) async {
    await _update((settings) => settings['forceTvMode'] = value);
  }

  Future<GlassQuality?> getGlassQuality() async {
    final settings = await _loadAll();
    final value = settings['glassQuality'];
    if (value is! String) {
      return null;
    }
    for (final quality in GlassQuality.values) {
      if (quality.name == value) {
        return quality;
      }
    }
    return null;
  }

  Future<void> setGlassQuality(GlassQuality value) async {
    await _update((settings) => settings['glassQuality'] = value.name);
  }

  Future<void> _update(
    void Function(Map<String, Object?> settings) update,
  ) async {
    final file = await _settingsFile();
    final path = file.path;
    final previous = _writeQueues[path] ?? Future<void>.value();
    final operation = previous.then((_) async {
      final settings = await _loadAllFrom(file);
      update(settings);
      await _saveAllTo(file, settings);
    });
    _writeQueues[path] = operation.then<void>((_) {}, onError: (_, _) {});
    await operation;
  }

  Future<File> _settingsFile() async {
    return resolveBiliStorageFile(
      fileName: 'bili-app-settings.json',
      baseDirectory: _baseDirectory,
      legacyDirectory: _legacyDirectory,
    );
  }
}
