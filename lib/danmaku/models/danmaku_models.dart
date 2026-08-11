import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/media.dart';

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

/// 兼容别名：弹幕 overlay 设置已泛化为 [MediaDanmakuOverlaySettings]（lib/media）。
typedef DanmakuOverlaySettings = MediaDanmakuOverlaySettings;
