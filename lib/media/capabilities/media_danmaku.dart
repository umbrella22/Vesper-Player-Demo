import 'dart:async';

import '../models/media_playback_target.dart';

/// 弹幕渲染位置。
enum MediaDanmakuPosition { roll, top, bottom, reverse }

/// 归一化的弹幕样式。平台特有样式（如 B 站彩色弹幕）在此映射为通用值。
final class MediaDanmakuStyle {
  const MediaDanmakuStyle({
    this.color,
    this.position = MediaDanmakuPosition.roll,
    this.fontSizeScale = 1.0,
  });

  final int? color;
  final MediaDanmakuPosition position;

  /// 相对默认字号的缩放。
  final double fontSizeScale;
}

/// 归一化的弹幕事件。平台解析层负责把自有协议转换为该模型，
/// 壳内的通用 overlay 只消费事件流。
final class MediaDanmakuEvent {
  const MediaDanmakuEvent({
    required this.timeMs,
    required this.text,
    this.style = const MediaDanmakuStyle(),
  });

  final int timeMs;
  final String text;
  final MediaDanmakuStyle style;
}

/// 弹幕能力：提供归一化事件流。未声明该能力的平台不挂载弹幕 overlay。
abstract interface class MediaDanmakuProvider {
  Stream<MediaDanmakuEvent> danmakuFor(MediaPlaybackTarget target);
}
