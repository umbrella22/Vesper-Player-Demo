import 'package:material_ui/material_ui.dart';

enum BiliDanmakuMode {
  scroll,
  bottom,
  top,
  reverse,
  unsupported;

  static BiliDanmakuMode fromCode(int code) {
    return switch (code) {
      1 || 2 || 3 => BiliDanmakuMode.scroll,
      4 => BiliDanmakuMode.bottom,
      5 => BiliDanmakuMode.top,
      6 => BiliDanmakuMode.reverse,
      _ => BiliDanmakuMode.unsupported,
    };
  }

  bool get isSupported => this != BiliDanmakuMode.unsupported;
}

final class BiliDanmakuEntry {
  const BiliDanmakuEntry({
    required this.appearAtMs,
    required this.mode,
    required this.fontSize,
    required this.colorValue,
    required this.text,
    required this.rowId,
  });

  final int appearAtMs;
  final BiliDanmakuMode mode;
  final double fontSize;
  final int colorValue;
  final String text;
  final String rowId;

  Color get color {
    final normalized = colorValue.clamp(0, 0xFFFFFF).toInt();
    return Color(0xFF000000 | normalized);
  }
}

final class DanmakuOverlaySettings {
  const DanmakuOverlaySettings({
    this.enabled = true,
    this.opacity = 0.82,
    this.density = 0.6,
  });

  final bool enabled;
  final double opacity;
  final double density;

  DanmakuOverlaySettings copyWith({
    bool? enabled,
    double? opacity,
    double? density,
  }) {
    return DanmakuOverlaySettings(
      enabled: enabled ?? this.enabled,
      opacity: opacity ?? this.opacity,
      density: density ?? this.density,
    );
  }
}
