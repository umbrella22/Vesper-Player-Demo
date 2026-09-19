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
    this.senderHash = '',
    this.hasServerId = true,
  });

  /// 平台提供的稳定弹幕标识，用于跨分段去重和渲染缓存。
  final String id;
  final int timeMs;
  final String text;
  final MediaDanmakuStyle style;
  final MediaDanmakuChannel channel;

  /// 发送者服务端哈希，仅用于本地精确屏蔽。为空表示源没有提供该字段。
  final String senderHash;

  /// [id] 是否为服务端记录标识（dmid）。
  ///
  /// 源缺少 dmid 时，解析层会用位置等内容合成一个稳定键：该键只能用于本地
  /// 去重与渲染，**不得**用于任何服务端操作（点赞、撤回、举报）。交互入口
  /// 必须据此禁用需要服务端标识的动作。
  final bool hasServerId;
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

/// 一次普通弹幕发送请求。
///
/// 只承载普通弹幕（滚动/顶部/底部/逆向）的声明式参数；平台层负责把它映射
/// 为自有的协议参数，壳不解释协议字段。
final class MediaDanmakuSendRequest {
  const MediaDanmakuSendRequest({
    required this.text,
    required this.positionMs,
    this.style = const MediaDanmakuStyle(),
  });

  final String text;
  final int positionMs;
  final MediaDanmakuStyle style;
}

/// 发送结果。
///
/// 成功时 [event] 是该弹幕在本地快照中的事件表示；平台层负责在成功后把
/// 事件插入当前分段——插入必须发生在服务端接受之后，否则界面会显示一条
/// 服务端并不存在的弹幕。
final class MediaDanmakuSendResult {
  const MediaDanmakuSendResult.success(this.event)
    : errorMessage = null,
      isPending = false;

  const MediaDanmakuSendResult.failure(this.errorMessage)
    : event = null,
      isPending = false;

  /// 请求已发出但结果未知（超时）。草稿应保留、由后续对账决定，不自动重发。
  const MediaDanmakuSendResult.pending()
    : event = null,
      errorMessage = null,
      isPending = true;

  final MediaDanmakuEvent? event;
  final String? errorMessage;
  final bool isPending;

  bool get isSuccess => event != null;
}

/// 可选的弹幕写能力：会话的扩展能力，不单独存在。
///
/// 未实现该接口的会话不提供发送入口——与「未声明弹幕能力就不挂载画布」
/// 保持同一约定。
abstract interface class MediaDanmakuSessionSender
    implements MediaDanmakuSession {
  /// 发送一条普通弹幕。
  ///
  /// 实现方不得自动重试：风控与限频的失败语义是「稍后再试」，
  /// 自动重发会加重限流。
  Future<MediaDanmakuSendResult> send(MediaDanmakuSendRequest request);
}

/// 互动状态独立于渲染快照，点赞不会重建整段弹幕布局。
final class MediaDanmakuInteractionState {
  const MediaDanmakuInteractionState({
    this.liked = false,
    this.pending = false,
    this.canLike = false,
    this.canRetract = false,
  });

  final bool liked;
  final bool pending;
  final bool canLike;
  final bool canRetract;
}

abstract interface class MediaDanmakuSessionInteractions
    implements MediaDanmakuSession {
  MediaDanmakuInteractionState interactionStateFor(MediaDanmakuEvent event);

  /// null 表示成功；错误文案由业务层提供，不自动重试。
  Future<String?> toggleLike(MediaDanmakuEvent event);
  Future<String?> retract(MediaDanmakuEvent event);
}

/// 弹幕能力：为当前播放目标创建会话。未声明该能力的平台不挂载 overlay。
abstract interface class MediaDanmakuProvider {
  MediaDanmakuSession openSession(MediaPlaybackTarget target);
}

/// 播放页与弹幕会话之间的发送通道。
/// 会话由弹幕层持有，播放页只持有本对象：层在打开/替换会话时绑定具备发送
/// 能力的会话，页面据此决定是否显示发送入口。[isAvailable] 为 false 时不
/// 提供入口，与「未声明能力不挂载画布」保持同一约定。
final class MediaDanmakuSendController {
  MediaDanmakuSendController();

  /// 直接绑定一个发送器，供测试与直接构造场景使用。
  MediaDanmakuSendController.forTesting(MediaDanmakuSessionSender sender)
    : _sender = sender;

  MediaDanmakuSessionSender? _sender;
  void Function()? _onAvailabilityChanged;

  bool get isAvailable => _sender != null;

  MediaDanmakuSessionInteractions? get interactions {
    final sender = _sender;
    return sender is MediaDanmakuSessionInteractions
        ? sender as MediaDanmakuSessionInteractions
        : null;
  }

  /// 可用性变化通知；弹幕层在会话切换时调用。
  set onAvailabilityChanged(void Function()? callback) {
    _onAvailabilityChanged = callback;
  }

  void bind(MediaDanmakuSession session) {
    final MediaDanmakuSessionSender? sender =
        session is MediaDanmakuSessionSender ? session : null;
    if (identical(sender, _sender)) {
      return;
    }
    _sender = sender;
    _onAvailabilityChanged?.call();
  }

  void unbind(Object session) {
    if (identical(_sender, session)) {
      _sender = null;
      _onAvailabilityChanged?.call();
    }
  }

  /// 发送一条普通弹幕；没有可用会话时返回失败结果，不抛异常。
  Future<MediaDanmakuSendResult> send(MediaDanmakuSendRequest request) {
    final sender = _sender;
    if (sender == null) {
      return Future<MediaDanmakuSendResult>.value(
        const MediaDanmakuSendResult.failure('当前没有可用的弹幕会话。'),
      );
    }
    return sender.send(request);
  }
}
