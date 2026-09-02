import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:vesper_media/common/storage/application_storage.dart';
import 'package:vesper_media/common/storage/atomic_file_writer.dart';
import 'package:vesper_media/danmaku/danmaku.dart';
import 'package:vesper_media/media/media.dart';

enum AppThemePreference { system, light, dark }

@immutable
final class AppSettingsSnapshot {
  const AppSettingsSnapshot({
    this.forceTvMode = false,
    this.glassQuality,
    this.themePreference = AppThemePreference.system,
    this.danmakuSettings = const BiliDanmakuSettings(),
  });

  static const defaults = AppSettingsSnapshot();

  final bool forceTvMode;
  final GlassQuality? glassQuality;
  final AppThemePreference themePreference;
  final BiliDanmakuSettings danmakuSettings;
}

final class AppSettingsStore {
  const AppSettingsStore({this.baseDirectory, this.legacyDirectory});

  final Directory? baseDirectory;
  final Directory? legacyDirectory;

  static final Map<String, Future<void>> _writeQueues =
      <String, Future<void>>{};

  Future<bool> getForceTvMode() async {
    return (await loadSnapshot()).forceTvMode;
  }

  Future<void> setForceTvMode(bool value) async {
    await _update((settings) => settings['forceTvMode'] = value);
  }

  Future<GlassQuality?> getGlassQuality() async {
    return (await loadSnapshot()).glassQuality;
  }

  Future<void> setGlassQuality(GlassQuality value) async {
    await _update((settings) => settings['glassQuality'] = value.name);
  }

  Future<AppThemePreference> getThemePreference() async {
    return (await loadSnapshot()).themePreference;
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    await _update((settings) => settings['themePreference'] = value.name);
  }

  Future<BiliDanmakuSettings> getDanmakuSettings() async {
    return (await loadSnapshot()).danmakuSettings;
  }

  Future<AppSettingsSnapshot> loadSnapshot() async {
    final settings = await _loadAll();
    return AppSettingsSnapshot(
      forceTvMode: _boolValue(settings['forceTvMode'], false),
      glassQuality: _glassQualityValue(settings['glassQuality']),
      themePreference: _themePreferenceValue(settings['themePreference']),
      danmakuSettings: _danmakuSettingsValue(settings['danmaku']),
    );
  }

  BiliDanmakuSettings _danmakuSettingsValue(Object? value) {
    if (value is! Map) {
      return const BiliDanmakuSettings();
    }
    final source = value.map((key, value) => MapEntry(key.toString(), value));
    final defaults = const BiliDanmakuSettings();
    final overlayDefaults = defaults.overlay;
    return BiliDanmakuSettings(
      overlay: MediaDanmakuOverlaySettings(
        enabled: _boolValue(source['enabled'], overlayDefaults.enabled),
        opacity: _doubleValue(
          source['opacity'],
          overlayDefaults.opacity,
          minimum: 0,
          maximum: 1,
        ),
        density: _doubleValue(
          source['density'],
          overlayDefaults.density,
          minimum: 0,
          maximum: 1,
        ),
        fontScale: _doubleValue(
          source['fontScale'],
          overlayDefaults.fontScale,
          minimum: 0.6,
          maximum: 1.6,
        ),
        displayArea: _doubleValue(
          source['displayArea'],
          overlayDefaults.displayArea,
          minimum: 0.25,
          maximum: 1,
        ),
        showScroll: _boolValue(
          source['showScroll'],
          overlayDefaults.showScroll,
        ),
        showTop: _boolValue(source['showTop'], overlayDefaults.showTop),
        showBottom: _boolValue(
          source['showBottom'],
          overlayDefaults.showBottom,
        ),
        showReverse: _boolValue(
          source['showReverse'],
          overlayDefaults.showReverse,
        ),
        showCaption: _boolValue(
          source['showCaption'],
          overlayDefaults.showCaption,
        ),
        showAdvanced: _boolValue(
          source['showAdvanced'],
          overlayDefaults.showAdvanced,
        ),
        showColor: _boolValue(source['showColor'], overlayDefaults.showColor),
        blockedKeywords: _exactStringList(source['blockedKeywords']),
      ),
      sourceFilter: BiliDanmakuSourceFilterSettings(
        minimumWeight: _intValue(
          source['minimumWeight'],
          defaults.sourceFilter.minimumWeight,
          minimum: 0,
          maximum: 10,
        ),
        blockedSenderHashes: _exactStringList(source['blockedSenderHashes']),
      ),
    );
  }

  Future<void> setDanmakuSettings(BiliDanmakuSettings value) async {
    await _update((settings) {
      settings['danmaku'] = <String, Object?>{
        'enabled': value.overlay.enabled,
        'opacity': value.overlay.opacity,
        'density': value.overlay.density,
        'fontScale': value.overlay.fontScale,
        'displayArea': value.overlay.displayArea,
        'showScroll': value.overlay.showScroll,
        'showTop': value.overlay.showTop,
        'showBottom': value.overlay.showBottom,
        'showReverse': value.overlay.showReverse,
        'showCaption': value.overlay.showCaption,
        'showAdvanced': value.overlay.showAdvanced,
        'showColor': value.overlay.showColor,
        'blockedKeywords': value.overlay.blockedKeywords,
        'minimumWeight': value.sourceFilter.minimumWeight,
        'blockedSenderHashes': value.sourceFilter.blockedSenderHashes,
      };
    });
  }

  Future<Map<String, Object?>> _loadAll() async {
    final file = await _settingsFile();
    return _loadAllFrom(file);
  }

  Future<Map<String, Object?>> _loadAllFrom(File file) async {
    try {
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
    } on FormatException catch (error) {
      debugPrint('[AppSettings] settings read failed: ${error.runtimeType}');
      return <String, Object?>{};
    }
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
      await writeStringAtomically(file, jsonEncode(settings));
    });
    _writeQueues[path] = operation.then<void>((_) {}, onError: (_, _) {});
    await operation;
  }

  Future<File> _settingsFile() async {
    return resolveApplicationStorageFile(
      fileName: 'vesper-app-settings.json',
      baseDirectory: baseDirectory,
      legacyDirectory: legacyDirectory,
    );
  }
}

GlassQuality? _glassQualityValue(Object? value) {
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

AppThemePreference _themePreferenceValue(Object? value) {
  if (value is String) {
    for (final preference in AppThemePreference.values) {
      if (preference.name == value) {
        return preference;
      }
    }
  }
  return AppThemePreference.system;
}

bool _boolValue(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

double _doubleValue(
  Object? value,
  double fallback, {
  required double minimum,
  required double maximum,
}) {
  if (value is! num) {
    return fallback;
  }
  final number = value.toDouble();
  return number.isFinite && number >= minimum && number <= maximum
      ? number
      : fallback;
}

int _intValue(
  Object? value,
  int fallback, {
  required int minimum,
  required int maximum,
}) {
  return value is int && value >= minimum && value <= maximum
      ? value
      : fallback;
}

List<String> _exactStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return List<String>.unmodifiable(
    value.whereType<String>().where((item) => item.isNotEmpty),
  );
}
