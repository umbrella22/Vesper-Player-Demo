part of 'bili_client.dart';

extension BiliClientRegion on BiliClient {
  Future<List<BiliRegionVideo>> fetchRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) async {
    await _transport.ensureReady();

    if (section.apiType == BiliRegionApiType.pgc) {
      return _fetchPgcRegionVideos(section, page: page);
    }
    return _fetchRankingRegionVideos(section, page: page);
  }

  Future<List<BiliRegionVideo>> _fetchPgcRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) async {
    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/pgc/season/index/result',
      params: <String, Object?>{
        'season_version': -1,
        'area': -1,
        'is_finish': -1,
        'copyright': -1,
        'season_status': -1,
        'season_month': -1,
        'year': -1,
        'style_id': -1,
        'order': 3,
        'st': 1,
        'sort': 0,
        'page': page,
        'season_type': section.seasonType ?? 1,
        'pagesize': 20,
        'type': 1,
      },
      referer: 'https://www.bilibili.com/',
      ensureReady: false,
    );

    return _parsePgcRegionVideos(data);
  }

  Future<List<BiliRegionVideo>> _fetchRankingRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) async {
    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/ranking/v2',
      params: <String, Object?>{'rid': section.rid ?? 0, 'type': 'all'},
      referer: 'https://www.bilibili.com/',
      ensureReady: false,
    );

    return _parseRankingRegionVideos(data);
  }

  List<BiliRegionVideo> _parsePgcRegionVideos(Map<String, Object?> data) {
    return readObjectList(data['list'])
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parsePgcRegionVideo)
        .whereType<BiliRegionVideo>()
        .toList(growable: false);
  }

  List<BiliRegionVideo> _parseRankingRegionVideos(Map<String, Object?> data) {
    return readObjectList(data['list'])
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseRankingRegionVideo)
        .whereType<BiliRegionVideo>()
        .toList(growable: false);
  }

  BiliRegionVideo? _parsePgcRegionVideo(Map<String, Object?> value) {
    final title = readString(value['title']) ?? '';
    final seasonId = readInt(value['season_id']);
    if (title.isEmpty || seasonId == null) {
      return null;
    }

    final newEp = readObjectMap(value['new_ep']);
    final scoreRaw = value['score'];
    final statValue = readObjectMap(value['stat']);
    final order = readString(value['order']);
    final followCount = readDouble(statValue['follow']);

    return BiliRegionVideo(
      id: seasonId.toString(),
      title: title,
      coverUrl:
          readString(value['cover']) ??
          readString(value['horizontal_cover_16_9']) ??
          '',
      url: readString(value['link']) ?? readString(value['url']) ?? '',
      seasonId: seasonId,
      epId: readInt(readObjectMap(value['first_ep'])['ep_id']),
      subtitle:
          readString(value['subTitle']) ??
          readString(value['subtitle']) ??
          readString(value['styles']),
      scoreLabel: switch (scoreRaw) {
        num raw => raw.toStringAsFixed(1),
        String raw when raw.trim().isNotEmpty => raw.trim(),
        _ => null,
      },
      indexLabel:
          readString(value['index_show']) ?? readString(newEp['index_show']),
      followCountLabel: followCount == null
          ? order
          : biliFormatCount(followCount),
      description: readString(value['evaluate']),
    );
  }

  Future<BiliVideoDetail> fetchPgcSeasonFirstEpisodeDetail(int seasonId) async {
    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/pgc/view/web/season',
      params: <String, Object?>{'season_id': seasonId},
      referer: 'https://www.bilibili.com/',
    );

    final episodes = readObjectList(data['episodes'])
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .toList(growable: false);
    if (episodes.isEmpty) {
      throw const BiliApiException('番剧没有可缓存的剧集。');
    }

    final pages = episodes.indexed
        .map((entry) {
          final index = entry.$1;
          final value = entry.$2;
          final cid = readInt(value['cid']) ?? 0;
          if (cid == 0) {
            return null;
          }
          final title =
              readString(value['long_title']) ??
              readString(value['show_title']) ??
              readString(value['title']) ??
              '第 ${index + 1} 话';
          return BiliVideoPageEntry(
            cid: cid,
            pageNumber: index + 1,
            title: title,
            durationSeconds: (readInt(value['duration']) ?? 0) ~/ 1000,
            aid: readInt(value['aid']),
            bvid: readString(value['bvid']),
            coverUrl: biliNormalizeImageUrl(readString(value['cover']) ?? ''),
          );
        })
        .whereType<BiliVideoPageEntry>()
        .toList(growable: false);
    if (pages.isEmpty) {
      throw const BiliApiException('番剧剧集缺少播放信息。');
    }

    final first = episodes.first;
    final firstPage = pages.first;
    final aid = firstPage.aid ?? readInt(first['aid']) ?? 0;
    final bvid = firstPage.bvid ?? readString(first['bvid']) ?? '';
    if (aid == 0 && bvid.isEmpty) {
      throw const BiliApiException('番剧剧集缺少播放信息。');
    }

    final title = readString(data['title']) ?? readString(first['long_title']);
    final episodeTitle =
        readString(first['long_title']) ??
        readString(first['show_title']) ??
        readString(first['title']) ??
        '第 1 话';
    final stat = readObjectMap(data['stat']);

    return BiliVideoDetail(
      aid: aid,
      bvid: bvid,
      title: title ?? episodeTitle,
      ownerMid: 0,
      ownerName: '番剧',
      ownerAvatarUrl: '',
      coverUrl: biliNormalizeImageUrl(
        readString(data['cover']) ?? readString(first['cover']) ?? '',
      ),
      description: readString(data['evaluate']) ?? '',
      publishedAtLabel: readPublishedAtLabel(first['pub_time']),
      playCountLabel: biliFormatCount(readDouble(stat['views'])),
      danmakuCountLabel: biliFormatCount(readDouble(stat['danmakus'])),
      replyCountLabel: biliFormatCount(readDouble(stat['reply'])),
      likeCountLabel: biliFormatCount(readDouble(stat['likes'])),
      coinCountLabel: biliFormatCount(readDouble(stat['coins'])),
      favoriteCountLabel: biliFormatCount(readDouble(stat['favorites'])),
      shareCountLabel: biliFormatCount(readDouble(stat['share'])),
      pages: pages,
    );
  }

  BiliRegionVideo? _parseRankingRegionVideo(Map<String, Object?> value) {
    final bvid = readString(value['bvid']) ?? '';
    final aid = readInt(value['aid']) ?? 0;
    if (bvid.isEmpty && aid == 0) {
      return null;
    }

    final statValue = readObjectMap(value['stat']);
    final owner = readObjectMap(value['owner']);
    final viewCount =
        readDouble(statValue['view']) ?? readDouble(value['play']);

    return BiliRegionVideo(
      id: bvid.isNotEmpty ? bvid : aid.toString(),
      title: readString(value['title']) ?? '',
      coverUrl: readString(value['pic']) ?? '',
      url:
          readString(value['short_link_v2']) ??
          readString(value['short_link']) ??
          'https://www.bilibili.com/video/$bvid',
      aid: aid,
      bvid: bvid,
      cid: readInt(value['cid']),
      subtitle: readString(owner['name']) ?? readString(value['author']) ?? '',
      scoreLabel: readInt(value['pts'])?.toString(),
      indexLabel: _readRegionDurationLabel(value['duration']),
      followCountLabel: viewCount == null ? null : biliFormatCount(viewCount),
      description:
          readString(value['desc']) ?? readString(value['description']),
    );
  }

  String? _readRegionDurationLabel(Object? value) {
    final raw = readString(value);
    if (raw != null && raw.contains(':')) {
      return raw;
    }

    final seconds = readInt(value);
    if (seconds == null) {
      return raw;
    }
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
