part of 'bili_client.dart';

extension _BiliClientPrefetchImplementation on BiliClient {
  Future<void> prefetchFeedPlayback(List<BiliFeedVideo> items) async {
    await Future.wait(
      items.take(6).map((item) {
        final cid = item.cid;
        return playbackPrefetcher.prefetch((bvid: item.bvid, cid: cid), (
          isCurrent,
        ) async {
          if (cid == null) {
            final detail = await fetchVideoDetail(item.bvid);
            return BiliPrefetchedPlayback(detail: detail);
          }
          for (final variant in biliDashRequestVariants) {
            if (!isCurrent()) return null;
            try {
              final data = await _requestDashData(
                aid: item.aid,
                bvid: item.bvid,
                cid: cid,
                variant: variant,
              );
              if (!isCurrent()) return null;
              if (const BiliDashManifestParser().parse(data).manifest != null) {
                return BiliPrefetchedPlayback(dashData: data, variant: variant);
              }
            } catch (_) {
              // Same request order as foreground resolution; no user-visible error.
            }
          }
          return null;
        });
      }),
    );
  }

  Future<Map<String, Object?>> _requestDashData({
    required int aid,
    required String bvid,
    required int cid,
    required BiliDashRequestVariant variant,
  }) => _transport.getData(
    host: biliApiHost,
    path: BiliApiPaths.playerWbiPlayUrl,
    params: buildBiliDashPlayUrlParamsForTarget(
      aid: aid,
      bvid: bvid,
      cid: cid,
      variant: variant,
      session: _transport.buildSessionValue(),
    ),
    useWbi: true,
    referer: biliVideoReferer(bvid),
  );

  Future<BiliPlaybackTarget> resolvePlaybackTarget(
    BiliPendingPlaybackTarget target,
  ) async {
    final bvid = target.bvid.trim();
    final aid = target.aid;
    final episodeId = target.episodeId;
    if (bvid.isEmpty &&
        (aid == null || aid <= 0) &&
        (episodeId == null || episodeId <= 0)) {
      throw const BiliApiException('无法识别该视频。');
    }
    final revision = sessionRevision;
    playbackPrefetcher.stopPrefetching(bvid);
    final cached = playbackPrefetcher.take((bvid: bvid, cid: null));
    final detail = episodeId != null && episodeId > 0
        ? await fetchPgcEpisodeDetail(episodeId)
        : cached?.detail ??
              (bvid.isNotEmpty
                  ? await fetchVideoDetail(bvid)
                  : await fetchVideoDetailByAid(aid!));
    if (revision != sessionRevision) {
      throw const BiliApiException('登录状态已变更，请重试。');
    }
    if (detail.pages.isEmpty) throw const BiliApiException('这个视频没有可播放分 P。');
    final page = episodeId != null && episodeId > 0
        ? detail.pages.firstWhere(
            (page) => page.episodeId == episodeId,
            orElse: () => throw const BiliApiException('无法找到对应的番剧分集。'),
          )
        : detail.pages.firstWhere(
            (page) => page.cid == target.cid,
            orElse: () => detail.pages.first,
          );
    return BiliPlaybackTarget(detail: detail, initialPage: page);
  }
}
