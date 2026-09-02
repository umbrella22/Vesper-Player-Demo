import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vesper_media/danmaku/danmaku.dart';
import 'package:vesper_media/media/media.dart';

import 'app_settings_store.dart';

/// Owns the app-wide danmaku preferences and persists optimistic updates.
final class DanmakuSettingsController {
  DanmakuSettingsController({
    this.store,
    BiliDanmakuSettings initialSettings = const BiliDanmakuSettings(),
  }) : _settings = ValueNotifier<BiliDanmakuSettings>(
         _freezeSettings(initialSettings),
       ),
       _overlay = ValueNotifier<MediaDanmakuOverlaySettings>(
         _freezeSettings(initialSettings).overlay,
       ),
       _sourceFilter = ValueNotifier<BiliDanmakuSourceFilterSettings>(
         _freezeSettings(initialSettings).sourceFilter,
       );

  final AppSettingsStore? store;
  final ValueNotifier<BiliDanmakuSettings> _settings;
  final ValueNotifier<MediaDanmakuOverlaySettings> _overlay;
  final ValueNotifier<BiliDanmakuSourceFilterSettings> _sourceFilter;
  bool _disposed = false;

  BiliDanmakuSettings get value => _settings.value;
  ValueListenable<BiliDanmakuSettings> get listenable => _settings;
  ValueListenable<MediaDanmakuOverlaySettings> get overlayListenable =>
      _overlay;
  ValueListenable<BiliDanmakuSourceFilterSettings> get sourceFilterListenable =>
      _sourceFilter;

  Future<bool> setOverlay(MediaDanmakuOverlaySettings overlay) {
    return setValue(value.copyWith(overlay: overlay));
  }

  Future<bool> setSourceFilter(BiliDanmakuSourceFilterSettings sourceFilter) {
    return setValue(value.copyWith(sourceFilter: sourceFilter));
  }

  Future<bool> setValue(BiliDanmakuSettings nextValue) async {
    if (_disposed) {
      return false;
    }
    final next = _freezeSettings(nextValue);
    final previous = value;
    if (previous == next) {
      return true;
    }
    _publish(next);
    final persistence = store;
    if (persistence == null) {
      return true;
    }
    try {
      await persistence.setDanmakuSettings(next);
      return true;
    } catch (_) {
      if (!_disposed && value == next) {
        _publish(previous);
      }
      return false;
    }
  }

  void _publish(BiliDanmakuSettings value) {
    _settings.value = value;
    if (_overlay.value != value.overlay) {
      _overlay.value = value.overlay;
    }
    if (_sourceFilter.value != value.sourceFilter) {
      _sourceFilter.value = value.sourceFilter;
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _settings.dispose();
    _overlay.dispose();
    _sourceFilter.dispose();
  }
}

class DanmakuSettingsScope extends InheritedWidget {
  const DanmakuSettingsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final DanmakuSettingsController controller;

  static DanmakuSettingsController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DanmakuSettingsScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(DanmakuSettingsScope oldWidget) {
    return oldWidget.controller != controller;
  }
}

BiliDanmakuSettings _freezeSettings(BiliDanmakuSettings value) {
  return BiliDanmakuSettings(
    overlay: value.overlay.copyWith(
      blockedKeywords: List<String>.unmodifiable(value.overlay.blockedKeywords),
    ),
    sourceFilter: value.sourceFilter.copyWith(
      blockedSenderHashes: List<String>.unmodifiable(
        value.sourceFilter.blockedSenderHashes,
      ),
    ),
  );
}
