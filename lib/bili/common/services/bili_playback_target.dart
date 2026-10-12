import '../models/bili_models.dart';

final class BiliPendingPlaybackTarget {
  const BiliPendingPlaybackTarget({
    this.bvid = '',
    this.aid,
    this.cid,
    this.episodeId,
  });
  final String bvid;
  final int? aid;
  final int? cid;
  final int? episodeId;
}

final class BiliPlaybackTarget {
  const BiliPlaybackTarget({required this.detail, required this.initialPage});
  final BiliVideoDetail detail;
  final BiliVideoPageEntry initialPage;
}
