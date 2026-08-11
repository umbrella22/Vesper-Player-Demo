/// 归一化的播放历史条目。
final class MediaHistoryEntry {
  const MediaHistoryEntry({
    required this.mediaId,
    required this.entryId,
    required this.videoTitle,
    required this.pageTitle,
    required this.coverUrl,
    required this.ownerName,
    required this.playedAtMs,
    required this.lastPositionMs,
    this.durationMs,
    this.platformExtras = const <String, Object?>{},
  });

  final String mediaId;
  final String entryId;
  final String videoTitle;
  final String pageTitle;
  final String coverUrl;
  final String ownerName;
  final int playedAtMs;
  final int lastPositionMs;
  final int? durationMs;

  /// 平台私有数据（如 Bilibili aid/episodeId/business），壳不读取。
  final Map<String, Object?> platformExtras;
}

/// 历史能力：平台实现读写各自的持久化存储。
/// 未声明该能力的平台不记录观看历史。
abstract interface class MediaHistoryStore {
  Future<List<MediaHistoryEntry>> loadEntries();

  Future<void> saveEntry(MediaHistoryEntry entry);

  /// 最近一次播放进度（毫秒），用于续播；无记录时返回 null。
  Future<int?> latestPositionMsFor(String mediaId, String entryId);
}
