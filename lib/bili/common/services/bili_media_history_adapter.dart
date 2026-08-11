import 'package:vesper_media/media/media.dart';

import '../models/bili_models.dart';
import 'bili_history_store.dart';

/// [MediaHistoryStore] 适配器：把 B 站自有历史存储暴露为通用契约。
///
/// 通用条目经 [MediaHistoryEntry.platformExtras] 无损携带 B 站字段
/// （aid/bvid/episodeId/business），持久化格式保持 B 站 JSON schema 不变。
final class BiliMediaHistoryStoreAdapter implements MediaHistoryStore {
  BiliMediaHistoryStoreAdapter(this._store);

  final BiliHistoryStore _store;

  @override
  Future<List<MediaHistoryEntry>> loadEntries() async {
    final entries = await _store.loadEntries();
    return entries.map(_toMediaHistoryEntry).toList(growable: false);
  }

  @override
  Future<void> saveEntry(MediaHistoryEntry entry) async {
    await _store.saveEntry(_toBiliHistoryEntry(entry));
  }

  @override
  Future<int?> latestPositionMsFor(String mediaId, String entryId) async {
    final entries = await _store.loadEntries();
    for (final entry in entries) {
      if (entry.bvid == mediaId && entry.cid.toString() == entryId) {
        return entry.lastPositionMs;
      }
    }
    return null;
  }

  BiliPlaybackHistoryEntry _toBiliHistoryEntry(MediaHistoryEntry entry) {
    final extras = entry.platformExtras;
    final episodeId = extras['episodeId'] as int? ?? 0;
    return BiliPlaybackHistoryEntry(
      bvid: extras['bvid'] as String? ?? entry.mediaId,
      aid: extras['aid'] as int? ?? 0,
      episodeId: episodeId,
      business: episodeId > 0
          ? 'pgc'
          : extras['business'] as String?,
      cid: int.tryParse(entry.entryId) ?? 0,
      videoTitle: entry.videoTitle,
      pageTitle: entry.pageTitle,
      coverUrl: entry.coverUrl,
      ownerName: entry.ownerName,
      playedAtMs: entry.playedAtMs,
      lastPositionMs: entry.lastPositionMs,
      durationMs: entry.durationMs,
    );
  }

  MediaHistoryEntry _toMediaHistoryEntry(BiliPlaybackHistoryEntry entry) {
    return MediaHistoryEntry(
      mediaId: entry.bvid,
      entryId: entry.cid.toString(),
      videoTitle: entry.videoTitle,
      pageTitle: entry.pageTitle,
      coverUrl: entry.coverUrl,
      ownerName: entry.ownerName,
      playedAtMs: entry.playedAtMs,
      lastPositionMs: entry.lastPositionMs,
      durationMs: entry.durationMs,
      platformExtras: <String, Object?>{
        'aid': entry.aid,
        'bvid': entry.bvid,
        'episodeId': entry.episodeId,
        'business': entry.business,
      },
    );
  }
}
