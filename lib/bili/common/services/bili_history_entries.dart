import '../models/bili_models.dart';

String _playbackIdentity(int aid, String bvid, int cid, int episodeId) {
  if (episodeId > 0) return 'episode:$episodeId';
  if (cid > 0) return 'cid:$cid';
  if (bvid.isNotEmpty) return 'bvid:$bvid';
  return 'aid:$aid';
}

extension BiliLocalHistoryMapping on BiliPlaybackHistoryEntry {
  String get playbackIdentity => _playbackIdentity(aid, bvid, cid, episodeId);

  BiliRemoteHistoryEntry toRemoteHistoryEntry() => BiliRemoteHistoryEntry(
    aid: aid,
    bvid: bvid,
    cid: cid,
    episodeId: episodeId,
    title: videoTitle,
    pageTitle: pageTitle,
    coverUrl: coverUrl,
    ownerName: ownerName,
    durationMs: durationMs ?? 0,
    progressMs: lastPositionMs,
    viewedAtMs: playedAtMs,
    business: business,
  );
}

extension BiliRemoteHistoryMapping on BiliRemoteHistoryEntry {
  String get playbackIdentity => _playbackIdentity(aid, bvid, cid, episodeId);

  BiliPlaybackHistoryEntry toPlaybackHistoryEntry() => BiliPlaybackHistoryEntry(
    aid: aid,
    bvid: bvid,
    cid: cid,
    episodeId: episodeId,
    videoTitle: title,
    pageTitle: pageTitle,
    coverUrl: coverUrl,
    ownerName: ownerName,
    durationMs: durationMs > 0 ? durationMs : null,
    lastPositionMs: progressMs,
    playedAtMs: viewedAtMs,
    business: business,
  );
}

extension BiliWatchLaterIdentity on BiliWatchLaterEntry {
  String get playbackIdentity => _playbackIdentity(aid, bvid, cid, episodeId);
}

/// Keeps server order and appends local-only rows, retaining the first identity.
/// The same rule also deduplicates consecutive server pages before local merge.
List<T> mergeBiliHistory<T>(
  Iterable<T> primary,
  Iterable<T> fallback,
  String Function(T) identityFor,
) {
  final seen = <String>{};
  return <T>[
    for (final entry in primary.followedBy(fallback))
      if (seen.add(identityFor(entry))) entry,
  ];
}
