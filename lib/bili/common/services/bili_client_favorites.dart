part of 'bili_client.dart';

extension _BiliClientFavoritesImplementation on BiliClient {
  Future<List<BiliFavoriteFolder>> fetchFavoriteFolders() async {
    _requireFavoritesSession();
    final currentMid = await _resolveCurrentUserMid();
    if (currentMid == null || currentMid <= 0) {
      throw const BiliApiException('缺少当前用户 UID，无法查询收藏夹。');
    }
    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.favFolderListAll,
      params: <String, Object?>{
        'up_mid': currentMid,
        'type': biliVideoFavoriteType,
      },
      referer: biliSpaceReferer(currentMid),
    );
    return readObjectList(data['list'])
        .map(readObjectMap)
        .map(_parseFavoriteFolder)
        .whereType<BiliFavoriteFolder>()
        .toList(growable: false);
  }

  Future<BiliFavoritePage> fetchFavoriteItems({
    required int folderId,
    int page = 1,
    int pageSize = 20,
    String keyword = '',
    BiliFavoriteOrder order = BiliFavoriteOrder.recent,
  }) async {
    _requireFavoritesSession();
    if (folderId <= 0 || page <= 0 || pageSize <= 0) {
      throw ArgumentError('收藏夹 ID、页码和每页数量必须为正数。');
    }
    final searchKeyword = keyword.trim();
    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.favResourceList,
      params: <String, Object?>{
        'media_id': folderId,
        'pn': page,
        'ps': pageSize,
        'keyword': searchKeyword,
        'order': order.apiValue,
        // Search remains scoped to this folder; type=1 searches all folders.
        'type': 0,
        'tid': 0,
      },
    );
    final rawItems = readObjectList(data['medias']);
    final items = rawItems
        .map(readObjectMap)
        .map(_parseFavoriteItem)
        .whereType<BiliFavoriteItem>()
        .toList(growable: false);
    // info.media_count is the whole folder count, not the search match count.
    final totalCount = searchKeyword.isEmpty
        ? readInt(readObjectMap(data['info'])['media_count'])
        : null;
    final serverHasMore =
        readBool(data['has_more']) ??
        (totalCount == null
            ? rawItems.length >= pageSize
            : page * pageSize < totalCount);
    return BiliFavoritePage(
      items: items,
      page: page,
      pageSize: pageSize,
      totalCount: totalCount,
      hasMore: rawItems.isNotEmpty && serverHasMore,
    );
  }

  BiliFavoriteItem? _parseFavoriteItem(Map<String, Object?> value) {
    final id = readInt(value['id']);
    if (id == null || id <= 0) return null;
    final type = readInt(value['type']) ?? 0;
    final bvid = readString(value['bvid']) ?? '';
    final attr = readInt(value['attr']) ?? 0;
    final upper = readObjectMap(value['upper']);
    final count = readObjectMap(value['cnt_info']);
    final duration = readInt(value['duration']);
    return BiliFavoriteItem(
      id: id,
      type: type,
      bvid: bvid,
      title: biliStripHtmlTags(readString(value['title']) ?? '失效视频'),
      coverUrl: biliNormalizeImageUrl(readString(value['cover']) ?? ''),
      ownerName: readString(upper['name']) ?? '',
      durationLabel: duration == null
          ? '--:--'
          : biliFormatDurationSeconds(duration),
      playCountLabel: biliFormatCount(readInt(count['play'])),
      favoritedAtLabel: readPublishedAtLabel(value['fav_time']) ?? '',
      isAvailable:
          type == biliVideoFavoriteType && bvid.isNotEmpty && attr & 1 == 0,
    );
  }

  void _requireFavoritesSession() {
    if (!hasAuthenticatedSession) {
      throw const BiliApiException('请先登录 Bilibili 后查看收藏。', code: -101);
    }
  }
}
