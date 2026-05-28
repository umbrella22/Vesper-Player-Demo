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
    final list = data['list'];
    if (list is! List) {
      return const <BiliRegionVideo>[];
    }

    return list
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .map(_parsePgcRegionVideo)
        .whereType<BiliRegionVideo>()
        .toList(growable: false);
  }

  List<BiliRegionVideo> _parseRankingRegionVideos(Map<String, Object?> data) {
    final list = data['list'];
    if (list is! List) {
      return const <BiliRegionVideo>[];
    }

    return list
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .map(_parseRankingRegionVideo)
        .whereType<BiliRegionVideo>()
        .toList(growable: false);
  }

  BiliRegionVideo? _parsePgcRegionVideo(Map<String, Object?> value) {
    final title = value['title'] as String? ?? '';
    final seasonId = (value['season_id'] as num?)?.toInt();
    if (title.isEmpty || seasonId == null) {
      return null;
    }

    final newEp = value['new_ep'] as Map<String, Object?>?;
    final scoreRaw = value['score'];
    final statValue = value['stat'] as Map<String, Object?>?;
    final order = readString(value['order']);

    return BiliRegionVideo(
      id: seasonId.toString(),
      title: title,
      coverUrl:
          value['cover'] as String? ??
          value['horizontal_cover_16_9'] as String? ??
          '',
      url: value['link'] as String? ?? value['url'] as String? ?? '',
      seasonId: seasonId,
      epId: readInt((value['first_ep'] as Map?)?['ep_id']),
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
          readString(value['index_show']) ?? readString(newEp?['index_show']),
      followCountLabel: statValue?['follow'] is num
          ? biliFormatCount((statValue?['follow'] as num).toDouble())
          : order,
      description: value['evaluate'] as String?,
    );
  }

  Future<BiliVideoDetail> fetchPgcSeasonFirstEpisodeDetail(int seasonId) async {
    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/pgc/view/web/season',
      params: <String, Object?>{'season_id': seasonId},
      referer: 'https://www.bilibili.com/',
    );

    final episodes = (data['episodes'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
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
    final stat = Map<String, Object?>.from(
      data['stat'] as Map? ?? const <String, Object?>{},
    );

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
    final bvid = value['bvid'] as String? ?? '';
    final aid = (value['aid'] as num?)?.toInt() ?? 0;
    if (bvid.isEmpty && aid == 0) {
      return null;
    }

    final statValue = value['stat'] as Map<String, Object?>?;

    return BiliRegionVideo(
      id: bvid.isNotEmpty ? bvid : aid.toString(),
      title: value['title'] as String? ?? '',
      coverUrl: value['pic'] as String? ?? '',
      url:
          value['short_link_v2'] as String? ??
          value['short_link'] as String? ??
          'https://www.bilibili.com/video/$bvid',
      aid: aid,
      bvid: bvid,
      cid: (value['cid'] as num?)?.toInt(),
      subtitle: value['owner'] is Map
          ? (value['owner'] as Map)['name'] as String? ?? ''
          : value['author'] as String? ?? '',
      scoreLabel: (value['pts'] as num?)?.toInt().toString(),
      indexLabel: value['duration'] is String
          ? value['duration'] as String?
          : value['duration'] is num
          ? '${(value['duration'] as num) ~/ 60}:${((value['duration'] as num) % 60).toString().padLeft(2, '0')}'
          : null,
      followCountLabel: statValue?['view'] is num
          ? biliFormatCount((statValue?['view'] as num).toDouble())
          : value['play'] is num
          ? biliFormatCount((value['play'] as num).toDouble())
          : null,
      description: value['desc'] as String? ?? value['description'] as String?,
    );
  }
}
