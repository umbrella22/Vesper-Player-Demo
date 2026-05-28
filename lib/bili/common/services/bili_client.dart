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

    final rawResults = data['result'];
    if (rawResults is! List) {
      return const <BiliSearchResult>[];
    }

    return rawResults
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
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

    final pages = (data['pages'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .map(
          (value) => BiliVideoPageEntry(
            cid: (value['cid'] as num?)?.toInt() ?? 0,
            pageNumber: (value['page'] as num?)?.toInt() ?? 0,
            title: biliStripHtmlTags(value['part'] as String? ?? 'P'),
            durationSeconds: (value['duration'] as num?)?.toInt() ?? 0,
            aid: (data['aid'] as num?)?.toInt(),
            bvid: data['bvid'] as String? ?? bvid,
            coverUrl: biliNormalizeImageUrl(data['pic'] as String? ?? ''),
          ),
        )
        .toList(growable: false);

    final owner = Map<String, Object?>.from(
      data['owner'] as Map? ?? const <String, Object?>{},
    );
    final stat = Map<String, Object?>.from(
      data['stat'] as Map? ?? const <String, Object?>{},
    );

    return BiliVideoDetail(
      aid: (data['aid'] as num?)?.toInt() ?? 0,
      bvid: data['bvid'] as String? ?? bvid,
      title: biliStripHtmlTags(data['title'] as String? ?? bvid),
      ownerMid: readInt(owner['mid']) ?? 0,
      ownerName: owner['name'] as String? ?? 'UP',
      ownerAvatarUrl: biliNormalizeImageUrl(owner['face'] as String? ?? ''),
      coverUrl: biliNormalizeImageUrl(data['pic'] as String? ?? ''),
      description: (data['desc'] as String? ?? '').trim(),
      publishedAtLabel: readPublishedAtLabel(data['pubdate'] ?? data['ctime']),
      playCountLabel: biliFormatCount((stat['view'] as num?)?.toDouble()),
      danmakuCountLabel: biliFormatCount((stat['danmaku'] as num?)?.toDouble()),
      replyCountLabel: biliFormatCount((stat['reply'] as num?)?.toDouble()),
      likeCountLabel: biliFormatCount((stat['like'] as num?)?.toDouble()),
      coinCountLabel: biliFormatCount((stat['coin'] as num?)?.toDouble()),
      favoriteCountLabel: biliFormatCount(
        (stat['favorite'] as num?)?.toDouble(),
      ),
      shareCountLabel: biliFormatCount((stat['share'] as num?)?.toDouble()),
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
    final levelInfo = Map<String, Object?>.from(
      data['level_info'] as Map? ?? const <String, Object?>{},
    );
    final vipInfo = Map<String, Object?>.from(
      data['vip_label'] as Map? ?? const <String, Object?>{},
    );
    final walletInfo = Map<String, Object?>.from(
      data['wallet'] as Map? ?? const <String, Object?>{},
    );
    final statInfo = isLogin
        ? await _fetchCurrentUserNavStat()
        : const <String, Object?>{};

    final profile = BiliUserProfile(
      isLoggedIn: isLogin,
      name: (data['uname'] as String? ?? '').trim().isEmpty
          ? '未登录'
          : (data['uname'] as String).trim(),
      avatarUrl: biliNormalizeImageUrl(data['face'] as String? ?? ''),
      mid: (data['mid'] as num?)?.toInt(),
      level: (levelInfo['current_level'] as num?)?.toInt(),
      vipLabel: (vipInfo['text'] as String?)?.trim().isEmpty ?? true
          ? null
          : (vipInfo['text'] as String).trim(),
      bCoinBalance:
          (walletInfo['bcoin_balance'] as num?)?.toDouble() ??
          (walletInfo['bcoinBalance'] as num?)?.toDouble(),
      coinBalance: (data['money'] as num?)?.toDouble(),
      dynamicCount:
          (statInfo['dynamic_count'] as num?)?.toInt() ??
          (statInfo['dynamicCount'] as num?)?.toInt(),
      followingCount:
          (statInfo['following'] as num?)?.toInt() ??
          (statInfo['following_count'] as num?)?.toInt(),
      followerCount:
          (statInfo['follower'] as num?)?.toInt() ??
          (statInfo['follower_count'] as num?)?.toInt(),
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
    final code = (map['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw BiliApiException(
        map['message'] as String? ?? 'QR login generation failed.',
        code: code,
      );
    }

    final data = Map<String, Object?>.from(
      map['data'] as Map? ?? const <String, Object?>{},
    );
    final url = data['url'] as String? ?? '';
    final key = data['qrcode_key'] as String? ?? '';
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
    final code = (map['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw BiliApiException(
        map['message'] as String? ?? 'QR login poll failed.',
        code: code,
      );
    }

    final data = Map<String, Object?>.from(
      map['data'] as Map? ?? const <String, Object?>{},
    );
    _transport.restoreCookies({
      ..._transport.cookies,
      ...parseBiliLoginCookiesFromUrl(data['url'] as String?),
    });
    final statusCode = (data['code'] as num?)?.toInt() ?? -1;
    final status = BiliQrLoginStatus.fromCode(statusCode);
    return BiliQrLoginPollResult(
      status: status,
      message: data['message'] as String? ?? map['message'] as String? ?? '',
      timestampMs: ((data['timestamp'] as num?)?.toInt()) != null
          ? ((data['timestamp'] as num).toInt()) * 1000
          : null,
      refreshToken: data['refresh_token'] as String?,
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

    final rawItems = data['item'];
    if (rawItems is! List) {
      return const <BiliFeedVideo>[];
    }

    return rawItems
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
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
    if (data is Map) {
      final map = Map<String, Object?>.from(data);
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

    final rawFolders = data['list'] as List<dynamic>? ?? const <dynamic>[];
    return rawFolders
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
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
