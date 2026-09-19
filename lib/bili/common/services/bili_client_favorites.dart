part of 'bili_client.dart';

/// 收藏资源标识 `<类型 id>:<资源类型>`，与 [BiliFavoriteItem.resourceKey] 一致。
final RegExp _favoriteResourceIdPattern = RegExp(r'^\d+:\d+$');

/// 服务端收藏夹标题上限；超长请求会被拒绝，先在本地拦截以免产生无意义的写请求。
const int _maxFavoriteFolderTitleLength = 40;

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

  /// 从单个收藏夹移出资源，不校验其他收藏夹的归属。
  ///
  /// [resourceIds] 使用 `<id>:<type>` 形态，与列表项的 `resourceKey` 一致。
  Future<void> removeFavoriteItems({
    required int folderId,
    required List<String> resourceIds,
  }) async {
    _requireFavoritesSession();
    if (folderId <= 0) {
      throw ArgumentError('收藏夹 ID 必须为正数。');
    }
    if (resourceIds.isEmpty) return;
    for (final resourceId in resourceIds) {
      if (!_favoriteResourceIdPattern.hasMatch(resourceId)) {
        throw ArgumentError('收藏资源标识格式无效：$resourceId');
      }
    }
    await _transport.postData(
      host: biliApiHost,
      path: BiliApiPaths.favResourceBatchDel,
      data: <String, Object?>{
        'resources': resourceIds.join(','),
        'media_id': folderId,
      },
    );
  }

  /// 新建收藏夹；返回服务端分配的收藏夹 ID。
  Future<int> createFavoriteFolder({
    required String title,
    required bool isPrivate,
  }) async {
    _requireFavoritesSession();
    final folderTitle = title.trim();
    if (folderTitle.isEmpty) {
      throw const BiliApiException('收藏夹名称不能为空。');
    }
    if (folderTitle.runes.length > _maxFavoriteFolderTitleLength) {
      throw const BiliApiException('收藏夹名称过长，请缩短后重试。');
    }
    final data = await _transport.postData(
      host: biliApiHost,
      path: BiliApiPaths.favFolderAdd,
      data: <String, Object?>{
        'title': folderTitle,
        'privacy': isPrivate ? 1 : 0,
      },
    );
    final id =
        readInt(data['id']) ??
        readInt(data['media_id']) ??
        readInt(readObjectMap(data['folder'])['id']);
    if (id == null || id <= 0) {
      throw const BiliApiException('收藏夹已创建，但服务端未返回收藏夹 ID。');
    }
    return id;
  }

  /// 读取某视频的收藏夹归属。
  ///
  /// 这是收藏夹选择器唯一的数据来源：`fav_state` 只在带 `rid` 的请求里有意义。
  Future<List<BiliFavoriteFolder>> fetchVideoFavoriteFolders(
    BiliVideoDetail detail,
  ) async {
    _requireFavoritesSession();
    return _fetchFavoriteFolders(detail);
  }

  /// 按显式差异提交收藏夹归属变更。
  ///
  /// 取消收藏只移出 [selection] 中的收藏夹；未被选中的归属保持不变。
  Future<BiliVideoEngagement> applyVideoFavoriteSelection({
    required BiliVideoDetail detail,
    required BiliFavoriteSelection selection,
    BiliVideoEngagement? current,
  }) async {
    _requireFavoritesSession();
    final base = current ?? await fetchVideoEngagement(detail);
    if (selection.isEmpty) {
      return base;
    }
    await _transport.postData(
      host: biliApiHost,
      path: BiliApiPaths.favResourceDeal,
      data: <String, Object?>{
        'rid': detail.aid,
        'type': biliVideoFavoriteType,
        'add_media_ids': joinIntList(selection.addFolderIds),
        'del_media_ids': joinIntList(selection.removeFolderIds),
      },
      referer: biliVideoReferer(detail.bvid),
    );

    // 服务端可能因权限或收藏夹上限只接受部分目标，因此以重新读取的归属为准。
    // 重新读取失败时退回按差异推导的预期集合——`_tryFetchFavoriteFolders`
    // 用空列表表示失败，直接采信会把「已收藏」误报成「未收藏」。
    final expectedIds = <int>{
      ...base.favoriteMediaIds,
      ...selection.addFolderIds,
    }..removeAll(selection.removeFolderIds);
    return _refreshEngagementAfterMutation(
      detail: detail,
      fallback: base.copyWith(
        isAuthenticated: true,
        isFavorited: expectedIds.isNotEmpty,
        favoriteMediaIds: expectedIds.toList(growable: false),
      ),
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
