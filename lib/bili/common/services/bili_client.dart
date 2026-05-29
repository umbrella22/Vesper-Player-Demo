import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vesper_player/vesper_player.dart';

import '../models/bili_models.dart';
import '../models/bili_region_models.dart';
import 'bili_api_core.dart';
import 'bili_dash_manifest_builder.dart';
import 'bili_text.dart';
import 'bili_transport.dart';
import 'bili_wbi.dart';

part 'bili_client_download.dart';
part 'bili_client_playback.dart';
part 'bili_client_region.dart';
part 'bili_client_search.dart';

class BiliClient {
  BiliClient({
    HttpClient? httpClient,
    BiliWbiSigner? signer,
    BiliDashManifestBuilder? manifestBuilder,
    BiliTransport? transport,
  }) : _transport =
           transport ?? BiliTransport(httpClient: httpClient, signer: signer),
       _manifestBuilder = manifestBuilder ?? const BiliDashManifestBuilder();

  static final BiliClient instance = BiliClient();

  final BiliTransport _transport;
  final BiliDashManifestBuilder _manifestBuilder;
  int? _currentUserMid;

  BiliTransport get transport => _transport;

  Map<String, String> snapshotCookies() => _transport.snapshotCookies();

  void restoreCookies(Map<String, String> cookies) {
    _transport.restoreCookies(cookies);
    _currentUserMid = readInt(cookies['DedeUserID']);
  }

  void clearSession() {
    _transport.clearSession();
    _currentUserMid = null;
  }

  bool get hasAuthenticatedSession => _transport.hasAuthenticatedSession;

  @visibleForTesting
  BiliDashManifestData? parseDashManifestForTesting(Map<String, Object?> data) {
    return BiliClientPlayback(this)._parseDashManifest(data).manifest;
  }

  Future<BiliResolvedPlayback> resolvePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required TargetPlatform platform,
  }) {
    return BiliClientPlayback(
      this,
    ).resolvePlayback(detail: detail, page: page, platform: platform);
  }

  Future<List<BiliSearchResult>> searchVideos(
    String keyword, {
    int page = 1,
  }) async {
    await _transport.ensureReady();

    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/wbi/search/type',
      params: <String, Object?>{
        'keyword': keyword,
        'page': page,
        'page_size': 20,
        'search_type': 'video',
      },
      useWbi: true,
    );

    return readObjectList(data['result'])
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseSearchResult)
        .whereType<BiliSearchResult>()
        .toList(growable: false);
  }

  Future<List<BiliRegionVideo>> fetchRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) {
    return BiliClientRegion(this).fetchRegionVideos(section, page: page);
  }

  Future<BiliVideoDetail> fetchPgcSeasonFirstEpisodeDetail(int seasonId) {
    return BiliClientRegion(this).fetchPgcSeasonFirstEpisodeDetail(seasonId);
  }

  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async {
    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/view',
      params: <String, Object?>{'bvid': bvid},
    );

    final pages = readObjectList(data['pages'])
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(
          (value) => BiliVideoPageEntry(
            cid: readInt(value['cid']) ?? 0,
            pageNumber: readInt(value['page']) ?? 0,
            title: biliStripHtmlTags(readString(value['part']) ?? 'P'),
            durationSeconds: readInt(value['duration']) ?? 0,
            aid: readInt(data['aid']),
            bvid: readString(data['bvid']) ?? bvid,
            coverUrl: biliNormalizeImageUrl(readString(data['pic']) ?? ''),
          ),
        )
        .toList(growable: false);

    final owner = readObjectMap(data['owner']);
    final stat = readObjectMap(data['stat']);

    return BiliVideoDetail(
      aid: readInt(data['aid']) ?? 0,
      bvid: readString(data['bvid']) ?? bvid,
      title: biliStripHtmlTags(readString(data['title']) ?? bvid),
      ownerMid: readInt(owner['mid']) ?? 0,
      ownerName: readString(owner['name']) ?? 'UP',
      ownerAvatarUrl: biliNormalizeImageUrl(readString(owner['face']) ?? ''),
      coverUrl: biliNormalizeImageUrl(readString(data['pic']) ?? ''),
      description: readString(data['desc']) ?? '',
      publishedAtLabel: readPublishedAtLabel(data['pubdate'] ?? data['ctime']),
      playCountLabel: biliFormatCount(readDouble(stat['view'])),
      danmakuCountLabel: biliFormatCount(readDouble(stat['danmaku'])),
      replyCountLabel: biliFormatCount(readDouble(stat['reply'])),
      likeCountLabel: biliFormatCount(readDouble(stat['like'])),
      coinCountLabel: biliFormatCount(readDouble(stat['coin'])),
      favoriteCountLabel: biliFormatCount(readDouble(stat['favorite'])),
      shareCountLabel: biliFormatCount(readDouble(stat['share'])),
      pages: pages,
    );
  }

  Future<BiliUserProfile> fetchCurrentUserProfile() async {
    await _transport.ensureReady();
    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/nav',
      referer: 'https://www.bilibili.com/',
      ensureReady: false,
      allowedCodes: const <int>{0, -101},
    );

    final isLogin = data['isLogin'] == true;
    final levelInfo = readObjectMap(data['level_info']);
    final vipInfo = readObjectMap(data['vip_label']);
    final walletInfo = readObjectMap(data['wallet']);
    final statInfo = isLogin
        ? await _fetchCurrentUserNavStat()
        : const <String, Object?>{};
    final userName = readString(data['uname']);
    final vipLabel = readString(vipInfo['text']);

    final profile = BiliUserProfile(
      isLoggedIn: isLogin,
      name: userName == null || userName.isEmpty ? '未登录' : userName,
      avatarUrl: biliNormalizeImageUrl(readString(data['face']) ?? ''),
      mid: readInt(data['mid']),
      level: readInt(levelInfo['current_level']),
      vipLabel: vipLabel == null || vipLabel.isEmpty ? null : vipLabel,
      bCoinBalance:
          readDouble(walletInfo['bcoin_balance']) ??
          readDouble(walletInfo['bcoinBalance']),
      coinBalance: readDouble(data['money']),
      dynamicCount:
          readInt(statInfo['dynamic_count']) ??
          readInt(statInfo['dynamicCount']),
      followingCount:
          readInt(statInfo['following']) ??
          readInt(statInfo['following_count']),
      followerCount:
          readInt(statInfo['follower']) ?? readInt(statInfo['follower_count']),
    );
    _currentUserMid = profile.mid;
    return profile;
  }

  Future<Map<String, Object?>> _fetchCurrentUserNavStat() async {
    try {
      return await _transport.getData(
        host: 'api.bilibili.com',
        path: '/x/web-interface/nav/stat',
        referer: 'https://www.bilibili.com/',
        ensureReady: false,
      );
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  Future<BiliQrLoginTicket> generateQrLoginTicket() async {
    await _transport.ensureReady();
    final response = await _transport.sendRequest(
      Uri.https(
        'passport.bilibili.com',
        '/x/passport-login/web/qrcode/generate',
      ),
      referer: 'https://www.bilibili.com/',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const BiliApiException('Unexpected QR login response.');
    }

    final map = Map<String, Object?>.from(decoded);
    final code = readInt(map['code']) ?? -1;
    if (code != 0) {
      throw BiliApiException(
        readString(map['message']) ?? 'QR login generation failed.',
        code: code,
      );
    }

    final data = readObjectMap(map['data']);
    final url = readString(data['url']) ?? '';
    final key = readString(data['qrcode_key']) ?? '';
    if (url.isEmpty || key.isEmpty) {
      throw const BiliApiException('QR login payload is incomplete.');
    }

    return BiliQrLoginTicket(url: url, qrcodeKey: key);
  }

  Future<BiliQrLoginPollResult> pollQrLogin(String qrcodeKey) async {
    final response = await _transport.sendRequest(
      Uri.https(
        'passport.bilibili.com',
        '/x/passport-login/web/qrcode/poll',
        <String, String>{'qrcode_key': qrcodeKey},
      ),
      referer: 'https://www.bilibili.com/',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const BiliApiException('Unexpected QR login poll response.');
    }

    final map = Map<String, Object?>.from(decoded);
    final code = readInt(map['code']) ?? -1;
    if (code != 0) {
      throw BiliApiException(
        readString(map['message']) ?? 'QR login poll failed.',
        code: code,
      );
    }

    final data = readObjectMap(map['data']);
    _transport.restoreCookies({
      ..._transport.cookies,
      ...parseBiliLoginCookiesFromUrl(readString(data['url'])),
    });
    final statusCode = readInt(data['code']) ?? -1;
    final status = BiliQrLoginStatus.fromCode(statusCode);
    return BiliQrLoginPollResult(
      status: status,
      message: readString(data['message']) ?? readString(map['message']) ?? '',
      timestampMs: readInt(data['timestamp']) != null
          ? readInt(data['timestamp'])! * 1000
          : null,
      refreshToken: readString(data['refresh_token']),
    );
  }

  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) async {
    await _transport.ensureReady();
    final normalizedPage = page < 1 ? 1 : page;
    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/index/top/feed/rcmd',
      params: <String, Object?>{
        'fresh_type': 4,
        'feed_version': 'V8',
        'fresh_idx': normalizedPage,
        'fresh_idx_1h': normalizedPage,
        'ps': 12,
        'homepage_ver': 1,
        'web_location': 1430650,
      },
      useWbi: true,
    );

    return readObjectList(data['item'])
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(parseBiliFeedVideo)
        .whereType<BiliFeedVideo>()
        .toList(growable: false);
  }

  Future<String> fetchDanmakuXml({
    required String bvid,
    required int cid,
  }) async {
    await _transport.ensureReady();
    final response = await _transport.sendRequest(
      Uri.https('api.bilibili.com', '/x/v1/dm/list.so', <String, String>{
        'oid': '$cid',
      }),
      referer: 'https://www.bilibili.com/video/$bvid',
      acceptHeader: 'text/xml, */*',
    );
    return response.body;
  }

  Future<BiliVideoEngagement> fetchVideoEngagement(
    BiliVideoDetail detail,
  ) async {
    await _transport.ensureReady();
    if (!_transport.hasAuthenticatedSession) {
      return const BiliVideoEngagement.guest();
    }

    final relation = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/archive/relation',
      params: <String, Object?>{'aid': detail.aid, 'bvid': detail.bvid},
      referer: 'https://www.bilibili.com/video/${detail.bvid}',
    );

    final folders = await _tryFetchFavoriteFolders(detail);
    final favoriteMediaIds = folders
        .where((folder) => folder.containsCurrentVideo)
        .map((folder) => folder.id)
        .toList(growable: false);

    return BiliVideoEngagement(
      isAuthenticated: true,
      isLiked: readBool(relation['like']) ?? false,
      isFavorited:
          (readBool(relation['favorite']) ?? false) ||
          favoriteMediaIds.isNotEmpty,
      isFollowingOwner: readBool(relation['attention']) ?? false,
      favoriteMediaIds: favoriteMediaIds,
      defaultFavoriteMediaId: folders.isEmpty ? null : folders.first.id,
    );
  }

  Future<BiliVideoEngagement> setVideoLike({
    required BiliVideoDetail detail,
    required bool liked,
    BiliVideoEngagement? current,
  }) async {
    final base = current ?? await fetchVideoEngagement(detail);
    await _transport.postData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/archive/like',
      data: <String, Object?>{
        'aid': detail.aid,
        'bvid': detail.bvid,
        'like': liked ? 1 : 2,
      },
      referer: 'https://www.bilibili.com/video/${detail.bvid}',
    );
    return _refreshEngagementAfterMutation(
      detail: detail,
      fallback: base.copyWith(isAuthenticated: true, isLiked: liked),
    );
  }

  Future<BiliVideoEngagement> setVideoFavorite({
    required BiliVideoDetail detail,
    required bool favorited,
    BiliVideoEngagement? current,
  }) async {
    final base = current ?? await fetchVideoEngagement(detail);
    final folders = await _fetchFavoriteFolders(detail);
    final currentFavoriteIds = folders
        .where((folder) => folder.containsCurrentVideo)
        .map((folder) => folder.id)
        .toList(growable: false);
    final defaultFavoriteId =
        base.defaultFavoriteMediaId ??
        (folders.isEmpty ? null : folders.first.id);

    final addIds = favorited && currentFavoriteIds.isEmpty
        ? <int>[?defaultFavoriteId]
        : const <int>[];
    final delIds = favorited
        ? const <int>[]
        : currentFavoriteIds.isNotEmpty
        ? currentFavoriteIds
        : base.favoriteMediaIds;

    if (favorited && addIds.isEmpty) {
      throw const BiliApiException('没有可用收藏夹，请先在 Bilibili 创建收藏夹。');
    }
    if (!favorited && delIds.isEmpty) {
      throw const BiliApiException('没有找到当前视频所在的收藏夹。');
    }

    await _transport.postData(
      host: 'api.bilibili.com',
      path: '/x/v3/fav/resource/deal',
      data: <String, Object?>{
        'rid': detail.aid,
        'type': biliVideoFavoriteType,
        'add_media_ids': joinIntList(addIds),
        'del_media_ids': joinIntList(delIds),
      },
      referer: 'https://www.bilibili.com/video/${detail.bvid}',
    );

    return _refreshEngagementAfterMutation(
      detail: detail,
      fallback: base.copyWith(
        isAuthenticated: true,
        isFavorited: favorited,
        favoriteMediaIds: favorited
            ? currentFavoriteIds.isEmpty
                  ? addIds
                  : currentFavoriteIds
            : const <int>[],
        defaultFavoriteMediaId: defaultFavoriteId,
      ),
    );
  }

  Future<BiliVideoEngagement> setOwnerFollow({
    required BiliVideoDetail detail,
    required bool following,
    BiliVideoEngagement? current,
  }) async {
    if (detail.ownerMid <= 0) {
      throw const BiliApiException('缺少 UP 主 UID，无法执行关注操作。');
    }

    final base = current ?? await fetchVideoEngagement(detail);
    await _transport.postData(
      host: 'api.bilibili.com',
      path: '/x/relation/modify',
      data: <String, Object?>{
        'fid': detail.ownerMid,
        'act': following ? 1 : 2,
        're_src': 14,
      },
      referer: 'https://space.bilibili.com/${detail.ownerMid}',
    );
    return _refreshEngagementAfterMutation(
      detail: detail,
      fallback: base.copyWith(
        isAuthenticated: true,
        isFollowingOwner: following,
      ),
    );
  }

  Future<int?> recordVideoShare({required BiliVideoDetail detail}) async {
    final data = await _transport.postApiData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/share/add',
      data: <String, Object?>{'aid': detail.aid, 'bvid': detail.bvid},
      referer: 'https://www.bilibili.com/video/${detail.bvid}',
    );
    final map = readObjectMap(data);
    if (map.isNotEmpty) {
      return readInt(map['share']) ??
          readInt(map['count']) ??
          readInt(map['num']);
    }
    return readInt(data);
  }

  Future<List<BiliFavoriteFolder>> _fetchFavoriteFolders(
    BiliVideoDetail detail,
  ) async {
    _transport.requireCsrfToken();
    final currentMid = await _resolveCurrentUserMid();
    if (currentMid == null || currentMid <= 0) {
      throw const BiliApiException('缺少当前用户 UID，无法查询收藏夹。');
    }
    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/x/v3/fav/folder/created/list-all',
      params: <String, Object?>{
        'rid': detail.aid,
        'up_mid': currentMid,
        'type': biliVideoFavoriteType,
      },
      referer: 'https://www.bilibili.com/video/${detail.bvid}',
    );

    final rawFolders = readObjectList(data['list']);
    return rawFolders
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseFavoriteFolder)
        .whereType<BiliFavoriteFolder>()
        .toList(growable: false);
  }

  Future<List<BiliFavoriteFolder>> _tryFetchFavoriteFolders(
    BiliVideoDetail detail,
  ) async {
    try {
      return await _fetchFavoriteFolders(detail);
    } catch (_) {
      return const <BiliFavoriteFolder>[];
    }
  }

  BiliFavoriteFolder? _parseFavoriteFolder(Map<String, Object?> value) {
    final id =
        readInt(value['id']) ??
        readInt(value['media_id']) ??
        readInt(value['fid']);
    if (id == null || id <= 0) {
      return null;
    }

    return BiliFavoriteFolder(
      id: id,
      title: readString(value['title']) ?? '默认收藏夹',
      containsCurrentVideo:
          (readInt(value['fav_state']) ?? readInt(value['favState']) ?? 0) > 0,
    );
  }

  Future<BiliVideoEngagement> _refreshEngagementAfterMutation({
    required BiliVideoDetail detail,
    required BiliVideoEngagement fallback,
  }) async {
    try {
      return await fetchVideoEngagement(detail);
    } catch (_) {
      return fallback;
    }
  }

  Future<int?> _resolveCurrentUserMid() async {
    final cached = _currentUserMid;
    if (cached != null && cached > 0) {
      return cached;
    }

    final cookieMid = readInt(_transport.cookieValue('DedeUserID'));
    if (cookieMid != null && cookieMid > 0) {
      _currentUserMid = cookieMid;
      return cookieMid;
    }

    final data = await _transport.getData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/nav',
      referer: 'https://www.bilibili.com/',
      ensureReady: false,
      allowedCodes: const <int>{0, -101},
    );
    final mid = readInt(data['mid']);
    if (mid != null && mid > 0) {
      _currentUserMid = mid;
      return mid;
    }
    return null;
  }
}

const biliDashRequestVariants = <BiliDashRequestVariant>[
  BiliDashRequestVariant(
    label: 'web fnval=4048',
    fnval: biliDashFnval,
    extraParams: <String, Object?>{
      'gaia_source': 'pre-load',
      'isGaiaAvoided': 'true',
      'from_client': 'BROWSER',
      'web_location': 1315873,
    },
  ),
  BiliDashRequestVariant(
    label: 'web fnval=976',
    fnval: biliDashCompatFnval,
    extraParams: <String, Object?>{
      'gaia_source': 'pre-load',
      'isGaiaAvoided': 'true',
      'from_client': 'BROWSER',
      'web_location': 1315873,
    },
  ),
  BiliDashRequestVariant(
    label: 'plain fnval=976',
    fnval: biliDashCompatFnval,
    extraParams: <String, Object?>{'high_quality': 1},
  ),
];
