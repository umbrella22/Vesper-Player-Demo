/// 一条评论的点赞状态：本地乐观值或服务端值。
///
/// 状态按评论 ID 共享，因为同一条评论会同时出现在主列表与楼中楼的回复里，
/// 两处必须显示同一个状态。
///
/// [pending] 表示写请求进行中。原始计数与展示文案分别保存；
/// 没有原始计数时只更新点赞状态。
final class BiliCommentLikeState {
  const BiliCommentLikeState({
    required this.liked,
    required this.likeCountLabel,
    this.pending = false,
    this.likeCount,
  });

  final bool liked;
  final String likeCountLabel;
  final int? likeCount;
  final bool pending;
}
