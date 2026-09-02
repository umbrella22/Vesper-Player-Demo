import 'dart:async';

import '../models/media_playback_target.dart';

/// 弹幕渲染位置。
enum MediaDanmakuPosition { roll, top, bottom, reverse }

/// 弹幕内容通道。字幕弹幕使用独立通道，渲染层可以让它固定显示而不与
/// 普通滚动弹幕争抢车道。
enum MediaDanmakuChannel { standard, caption }

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
/// 壳内的通用 overlay 只消费会话快照。
final class MediaDanmakuEvent {
  const MediaDanmakuEvent({
    required this.id,
    required this.timeMs,
    required this.text,
    this.style = const MediaDanmakuStyle(),
    this.channel = MediaDanmakuChannel.standard,
  });

  /// 平台提供的稳定弹幕标识，用于跨分段去重和渲染缓存。
  final String id;
  final int timeMs;
  final String text;
  final MediaDanmakuStyle style;
  final MediaDanmakuChannel channel;
}

/// 高级弹幕路径中的归一化坐标。坐标以视频画布宽高为 1；允许位于画布外，
/// 由渲染层裁剪，避免平台解析层擅自改变原始运动轨迹。
final class MediaDanmakuPoint {
  const MediaDanmakuPoint(this.x, this.y);

  final double x;
  final double y;
}

/// 不包含脚本能力的高级弹幕事件。
///
/// 平台层只能将声明式坐标、线段路径和样式映射到此模型。代码弹幕与 BAS
/// 不得伪装成该事件，也不会由通用画布执行。
final class MediaAdvancedDanmakuEvent {
  const MediaAdvancedDanmakuEvent({
    required this.id,
    required this.timeMs,
    required this.text,
    required this.path,
    required this.durationMs,
    required this.motionDurationMs,
    required this.motionDelayMs,
    required this.alphaFrom,
    required this.alphaTo,
    required this.rotationZDegrees,
    required this.rotationYDegrees,
    this.color,
    this.fontSizeScale = 1.0,
  });

  final String id;
  final int timeMs;
  final String text;

  /// 至少包含一个点；多点路径按相邻线段匀速播放。
  final List<MediaDanmakuPoint> path;
  final int durationMs;
  final int motionDurationMs;
  final int motionDelayMs;
  final double alphaFrom;
  final double alphaTo;
  final double rotationZDegrees;
  final double rotationYDegrees;
  final int? color;
  final double fontSizeScale;
}

/// 一次弹幕加载状态。事件列表始终不可变，并按 [MediaDanmakuEvent.timeMs]
/// 升序排列。
final class MediaDanmakuSnapshot {
  const MediaDanmakuSnapshot({
    this.events = const <MediaDanmakuEvent>[],
    this.advancedEvents = const <MediaAdvancedDanmakuEvent>[],
    this.isLoading = false,
    this.error,
  });

  final List<MediaDanmakuEvent> events;
  final List<MediaAdvancedDanmakuEvent> advancedEvents;
  final bool isLoading;
  final Object? error;
}

/// 单次播放目标的弹幕会话。平台自行解释播放位置对应的分段规则，通用
/// 播放壳只负责持续同步当前位置。
abstract interface class MediaDanmakuSession {
  Stream<MediaDanmakuSnapshot> get snapshots;

  void updatePosition(int positionMs);

  Future<void> close();
}

/// 弹幕能力：为当前播放目标创建会话。未声明该能力的平台不挂载 overlay。
abstract interface class MediaDanmakuProvider {
  MediaDanmakuSession openSession(MediaPlaybackTarget target);
}
