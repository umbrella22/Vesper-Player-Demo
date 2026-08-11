/// 平台无关的媒体详情，播放页与播放编排只消费该模型。
///
/// [platformExtras] 是适配器私有的不透明数据（如 Bilibili 的 aid / ownerMid），
/// 壳不读取，只由所属适配器在解析与能力调用时还原。缺省为空 map。
final class MediaDetail {
  const MediaDetail({
    required this.mediaId,
    required this.title,
    required this.coverUrl,
    required this.pages,
    this.isEpisodic = false,
    this.ownerName,
    this.replyCountLabel,
    this.danmakuCountLabel,
    this.platformExtras = const <String, Object?>{},
  });

  /// 稳定媒体标识（如 Bilibili bvid），供历史、弹幕等能力作为 key。
  final String mediaId;

  final String title;
  final String coverUrl;

  /// 分 P / 剧集条目；单视频平台只有一个条目。
  final List<MediaPlaybackEntry> pages;

  /// 是否为连续剧集内容（影响选集面板文案）。由适配器判定，壳不做平台判断。
  final bool isEpisodic;

  /// 作者/UP 主名称（系统播放元数据、历史条目使用），平台不提供时为空。
  final String? ownerName;

  /// 评论/弹幕计数文案（tab 角标），平台不提供时为空。
  final String? replyCountLabel;
  final String? danmakuCountLabel;

  final Map<String, Object?> platformExtras;

  MediaPlaybackEntry get firstEntry => pages.first;
}

/// 一个分 P / 剧集条目。
final class MediaPlaybackEntry {
  const MediaPlaybackEntry({
    required this.entryId,
    required this.pageNumber,
    required this.title,
    required this.durationSeconds,
    this.coverUrl,
    this.platformExtras = const <String, Object?>{},
  });

  /// 条目标识（如 Bilibili cid 的字符串形式），只由所属适配器解释。
  final String entryId;

  final int pageNumber;
  final String title;
  final int durationSeconds;
  final String? coverUrl;

  final Map<String, Object?> platformExtras;
}
