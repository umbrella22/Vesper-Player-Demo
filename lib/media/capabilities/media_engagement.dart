/// 互动动作类型。壳只按声明渲染，不做平台判断——
/// 没有投币概念的平台（如抖音）直接不声明 [MediaEngagementActionId.coin]。
enum MediaEngagementActionId { like, coin, favorite, share, follow, watchLater }

/// 互动动作栏由谁决定在播放页中的位置。
enum MediaEngagementPlacement { shell, intro }

/// 适配器声明的互动动作（当前状态快照 + 执行回调）。
///
/// 每次读取 [MediaPlatformAdapter.engagement] 都会拿到最新快照；
/// 壳在信号追踪的 build 栈内读取，状态变化（计数/选中/执行中）由
/// 平台自己的信号驱动重建。
final class MediaEngagementActionSpec {
  const MediaEngagementActionSpec({
    required this.id,
    required this.label,
    required this.perform,
    this.count,
    this.countLabel,
    this.selected = false,
    this.busy = false,
  });

  final MediaEngagementActionId id;

  /// 平台文案（如 "投币" / "点赞" / "喜欢"），壳不硬编码。
  final String label;

  /// 动作计数（如 1234）；无计数展示需求时为 null。
  final int? count;

  /// 计数展示文案（如 "1.1万"）；与 [count] 二选一，平台按其数据源提供。
  final String? countLabel;

  /// 是否处于选中态（如已点赞）。
  final bool selected;

  /// 是否执行中（按钮禁用）。
  final bool busy;

  /// 执行动作；返回值是提示语（null = 不提示），壳负责展示。
  final Future<String?> Function() perform;
}

/// 互动能力声明：壳按 [actions] 的顺序渲染动作栏。
final class MediaEngagementCapability {
  const MediaEngagementCapability({
    required this.actions,
    this.placement = MediaEngagementPlacement.shell,
  });

  final List<MediaEngagementActionSpec> actions;

  /// 平台内容 UX 需要把动作栏放进简介流时声明 [intro]；缺省由壳渲染。
  final MediaEngagementPlacement placement;
}
