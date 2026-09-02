import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vesper_media/common/storage/atomic_file_writer.dart';
import 'package:vesper_media/common/storage/generated_file_cleanup.dart';
import 'package:vesper_player/vesper_player.dart';

import '../models/bili_models.dart';
import '../models/bili_region_models.dart';
import 'bili_api_core.dart';
import 'bili_dash_api.dart';
import 'bili_dash_manifest_builder.dart';
import 'bili_dash_manifest_parser.dart';
import 'bili_endpoints.dart';
import 'bili_listen_audio_selector.dart';
import 'bili_text.dart';
import 'bili_transport.dart';
import 'bili_wbi.dart';

export 'bili_dash_api.dart' show biliDashRequestVariants;

part 'bili_client_download.dart';
part 'bili_client_library.dart';
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
  // Subtitle materialization is shared by all DASH request variants for the
  // same page. Keep the in-flight/completed Future so concurrent resolution
  // cannot issue duplicate player-v2 and subtitle-body requests.
  final Map<String, Future<List<BiliSubtitleTrack>>> _subtitleRequests =
      <String, Future<List<BiliSubtitleTrack>>>{};
  // Keys of [_subtitleRequests] whose Future has completed successfully.
  // Cache trimming only drops these; an in-flight request's Future is still
  // shared with concurrent callers and must not be evicted underneath them.
  final Set<String> _completedSubtitleRequests = <String>{};
  int? _currentUserMid;

  BiliTransport get transport => _transport;

  Map<String, String> snapshotCookies() => _transport.snapshotCookies();

  void restoreCookies(Map<String, String> cookies) {
    _transport.restoreCookies(cookies);
    _currentUserMid = readInt(cookies['DedeUserID']);
    _subtitleRequests.clear();
    _completedSubtitleRequests.clear();
  }

  void clearSession() {
    _transport.clearSession();
    _currentUserMid = null;
    _subtitleRequests.clear();
    _completedSubtitleRequests.clear();
  }

  bool get hasAuthenticatedSession => _transport.hasAuthenticatedSession;

  @visibleForTesting
  BiliDashManifestData? parseDashManifestForTesting(Map<String, Object?> data) {
    return const BiliDashManifestParser().parse(data).manifest;
  }

  Future<BiliResolvedPlayback> resolvePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required TargetPlatform platform,
  }) {
    return _BiliClientPlaybackImplementation(
      this,
    ).resolvePlayback(detail: detail, page: page, platform: platform);
  }

  Future<BiliDownloadOptions> resolveDownloadOptions({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
  }) {
    return _BiliClientDownloadImplementation(
      this,
    ).resolveDownloadOptions(detail: detail, page: page);
  }

  BiliPreparedDownloadAsset prepareDownloadAsset({
    required BiliDownloadOptions options,
    required int qualityId,
    BiliVideoCodecPreference codecPreference =
        BiliVideoCodecPreference.automatic,
    String? targetDirectory,
  }) {
    return _BiliClientDownloadImplementation(this).prepareDownloadAsset(
      options: options,
      qualityId: qualityId,
      codecPreference: codecPreference,
      targetDirectory: targetDirectory,
    );
  }

  Future<BiliPreparedDownloadAsset> prepareVerifiedDownloadAsset({
    required BiliDownloadOptions options,
    required int qualityId,
    BiliVideoCodecPreference codecPreference =
        BiliVideoCodecPreference.automatic,
    String? targetDirectory,
  }) {
    return _BiliClientDownloadImplementation(this).prepareVerifiedDownloadAsset(
      options: options,
      qualityId: qualityId,
      codecPreference: codecPreference,
      targetDirectory: targetDirectory,
    );
  }

  Future<List<BiliFollowingUser>> fetchFollowingUsers({
    int? mid,
    int page = 1,
    int pageSize = 20,
  }) {
    return _BiliClientLibraryImplementation(
      this,
    ).fetchFollowingUsers(mid: mid, page: page, pageSize: pageSize);
  }

  Future<List<BiliFollowingUser>> fetchFollowing({
    int? mid,
    int page = 1,
    int pageSize = 20,
  }) {
    return fetchFollowingUsers(mid: mid, page: page, pageSize: pageSize);
  }

  Future<BiliUserSpaceProfile> fetchUserSpaceProfile(int mid) {
    return _BiliClientLibraryImplementation(this).fetchUserSpaceProfile(mid);
  }

  Future<BiliUserSpaceVideoPage> fetchUserSpaceVideos({
    required int mid,
    int page = 1,
    int pageSize = 30,
    String keyword = '',
  }) {
    return _BiliClientLibraryImplementation(this).fetchUserSpaceVideos(
      mid: mid,
      page: page,
      pageSize: pageSize,
      keyword: keyword,
    );
  }

  Future<BiliUserSpaceVideo?> fetchUserSpaceVideoByBvid({
    required int mid,
    required String bvid,
  }) {
    return _BiliClientLibraryImplementation(
      this,
    ).fetchUserSpaceVideoByBvid(mid: mid, bvid: bvid);
  }

  Future<List<BiliRemoteHistoryEntry>> fetchRemoteHistory({
    int page = 1,
    int pageSize = 20,
    int max = 0,
    int viewAtMs = 0,
  }) {
    return _BiliClientLibraryImplementation(this).fetchRemoteHistory(
      page: page,
      pageSize: pageSize,
      max: max,
      viewAtMs: viewAtMs,
    );
  }

  Future<BiliRemoteHistoryPage> fetchRemoteHistoryPage({
    int page = 1,
    int pageSize = 20,
    int max = 0,
    int viewAtMs = 0,
  }) {
    return _BiliClientLibraryImplementation(this).fetchRemoteHistoryPage(
      page: page,
      pageSize: pageSize,
      max: max,
      viewAtMs: viewAtMs,
    );
  }

  Future<List<BiliRemoteHistoryEntry>> fetchPlaybackHistory({
    int page = 1,
    int pageSize = 20,
  }) {
    return fetchRemoteHistory(page: page, pageSize: pageSize);
  }

  Future<List<BiliWatchLaterEntry>> fetchWatchLater({
    int page = 1,
    int pageSize = 20,
  }) {
    return _BiliClientLibraryImplementation(
      this,
    ).fetchWatchLater(page: page, pageSize: pageSize);
  }

  Future<void> addToWatchLater({required String bvid, int? aid}) {
    return _BiliClientLibraryImplementation(
      this,
    ).addToWatchLater(bvid: bvid, aid: aid);
  }

  Future<void> removeFromWatchLater({String? bvid, int? aid}) {
    return _BiliClientLibraryImplementation(
      this,
    ).removeFromWatchLater(bvid: bvid, aid: aid);
  }

  Future<bool> isVideoInWatchLater({required String bvid, int? aid}) {
    return _BiliClientLibraryImplementation(
      this,
    ).isVideoInWatchLater(bvid: bvid, aid: aid);
  }

  Future<bool> isInWatchLater({required String bvid, int? aid}) {
    return isVideoInWatchLater(bvid: bvid, aid: aid);
  }

  Future<List<BiliSubtitleTrack>> fetchVideoSubtitleTracks({
    required String bvid,
    required int cid,
    int? aid,
  }) {
    return _BiliClientLibraryImplementation(
      this,
    ).fetchVideoSubtitleTracks(bvid: bvid, cid: cid, aid: aid);
  }

  Future<List<BiliSubtitleTrack>> fetchVideoSubtitles({
    required String bvid,
    required int cid,
    int? aid,
  }) {
    return _BiliClientLibraryImplementation(
      this,
    ).fetchVideoSubtitles(bvid: bvid, cid: cid, aid: aid);
  }

  Future<List<BiliSearchResult>> searchVideos(
    String keyword, {
    int page = 1,
  }) async {
    await _transport.ensureReady();

    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.searchType,
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
    return _BiliClientRegionImplementation(
      this,
    ).fetchRegionVideos(section, page: page);
  }

  Future<BiliVideoDetail> fetchPgcSeasonFirstEpisodeDetail(int seasonId) {
    return _BiliClientRegionImplementation(
      this,
    ).fetchPgcSeasonFirstEpisodeDetail(seasonId);
  }

  Future<BiliVideoDetail> fetchPgcEpisodeDetail(int episodeId) {
    return _BiliClientRegionImplementation(
      this,
    ).fetchPgcEpisodeDetail(episodeId);
  }

  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async {
    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.videoView,
      params: <String, Object?>{'bvid': bvid},
    );

    return _parseVideoDetail(data, fallbackBvid: bvid);
  }

  /// Resolves a history/watch-later row that only carries an avid/oid.
  /// Older Bilibili clients did not always include a BV id in those payloads.
  Future<BiliVideoDetail> fetchVideoDetailByAid(int aid) async {
    if (aid <= 0) {
      throw const BiliApiException('缺少有效的视频 AV 号。');
    }
    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.videoView,
      params: <String, Object?>{'aid': aid},
    );

    return _parseVideoDetail(data, fallbackBvid: 'av$aid');
  }

  BiliVideoDetail _parseVideoDetail(
    Map<String, Object?> data, {
    required String fallbackBvid,
  }) {
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
            bvid: readString(data['bvid']) ?? fallbackBvid,
            coverUrl: biliNormalizeImageUrl(readString(data['pic']) ?? ''),
          ),
        )
        .toList(growable: false);

    final owner = readObjectMap(data['owner']);
    final stat = readObjectMap(data['stat']);

    return BiliVideoDetail(
      aid: readInt(data['aid']) ?? 0,
      bvid: readString(data['bvid']) ?? fallbackBvid,
      title: biliStripHtmlTags(readString(data['title']) ?? fallbackBvid),
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
      host: biliApiHost,
      path: BiliApiPaths.nav,
      referer: biliDefaultReferer,
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
        host: biliApiHost,
        path: BiliApiPaths.navStat,
        referer: biliDefaultReferer,
        ensureReady: false,
      );
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  Future<BiliQrLoginTicket> generateQrLoginTicket() async {
    await _transport.ensureReady();
    final response = await _transport.sendRequest(
      Uri.https(biliPassportHost, BiliApiPaths.qrcodeGenerate),
      referer: biliDefaultReferer,
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
      Uri.https(biliPassportHost, BiliApiPaths.qrcodePoll, <String, String>{
        'qrcode_key': qrcodeKey,
      }),
      referer: biliDefaultReferer,
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
      host: biliApiHost,
      path: BiliApiPaths.feedRcmd,
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

  Future<List<BiliFeedVideo>> fetchRelatedVideos(
    BiliVideoDetail detail, {
    int limit = 12,
  }) async {
    if (detail.aid <= 0) {
      return const <BiliFeedVideo>[];
    }

    await _transport.ensureReady();
    final response = await _transport.sendRequest(
      Uri.https(biliApiHost, BiliApiPaths.archiveRelated, {
        'aid': '${detail.aid}',
        'bvid': detail.bvid,
      }),
      referer: biliVideoReferer(detail.bvid),
    );
    final decoded = _transport.decodeApiData(response.body);
    final rawItems = switch (decoded) {
      List<Object?> items => items,
      Map<Object?, Object?> map => readObjectList(readObjectMap(map)['items']),
      _ => const <Object?>[],
    };

    return rawItems
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(parseBiliFeedVideo)
        .whereType<BiliFeedVideo>()
        .where((item) => item.bvid != detail.bvid)
        .take(limit)
        .toList(growable: false);
  }

  Future<List<BiliVideoComment>> fetchVideoComments(
    BiliVideoDetail detail, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final result = await fetchVideoCommentPage(
      detail,
      page: page,
      pageSize: pageSize,
    );
    return result.comments;
  }

  Future<BiliVideoCommentPage> fetchVideoCommentPage(
    BiliVideoDetail detail, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (detail.aid <= 0) {
      return BiliVideoCommentPage(
        comments: const <BiliVideoComment>[],
        page: page < 1 ? 1 : page,
        pageSize: pageSize.clamp(1, 49).toInt(),
        hasMore: false,
      );
    }

    final normalizedPage = page < 1 ? 1 : page;
    final normalizedPageSize = pageSize.clamp(1, 49).toInt();
    await _transport.ensureReady();
    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.replyList,
      params: <String, Object?>{
        'type': 1,
        'oid': detail.aid,
        'sort': 1,
        'nohot': 0,
        'pn': normalizedPage,
        'ps': normalizedPageSize,
      },
      referer: biliVideoReferer(detail.bvid),
    );

    final seenIds = <int>{};
    final comments = <BiliVideoComment>[];
    void appendComments(Object? value) {
      for (final raw in readObjectList(value)) {
        final comment = _parseVideoComment(readObjectMap(raw));
        if (comment != null && seenIds.add(comment.id)) {
          comments.add(comment);
        }
      }
    }

    if (normalizedPage <= 1) {
      appendComments(data['hots']);
    }
    appendComments(data['replies']);
    final pageComments = comments
        .take(normalizedPageSize)
        .toList(growable: false);
    final pageInfo = readObjectMap(data['page']);
    final responsePage = readInt(pageInfo['num']) ?? normalizedPage;
    final responsePageSize = readInt(pageInfo['size']) ?? normalizedPageSize;
    final totalCount =
        readInt(pageInfo['count']) ??
        readInt(pageInfo['acount']) ??
        readInt(pageInfo['total']);
    final hasMore = totalCount == null
        ? pageComments.length >= normalizedPageSize
        : responsePage * responsePageSize < totalCount;
    return BiliVideoCommentPage(
      comments: pageComments,
      page: responsePage,
      pageSize: responsePageSize,
      totalCount: totalCount,
      hasMore: pageComments.isNotEmpty && hasMore,
    );
  }

  Future<BiliVideoCommentReplyPage> fetchVideoCommentReplyPage(
    BiliVideoDetail detail, {
    required int rootReplyId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    final normalizedPageSize = pageSize.clamp(1, 49).toInt();
    if (detail.aid <= 0 || rootReplyId <= 0) {
      return BiliVideoCommentReplyPage(
        replies: const <BiliVideoComment>[],
        page: normalizedPage,
        pageSize: normalizedPageSize,
        hasMore: false,
      );
    }

    await _transport.ensureReady();
    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.replyReply,
      params: <String, Object?>{
        'type': 1,
        'oid': detail.aid,
        'root': rootReplyId,
        'pn': normalizedPage,
        'ps': normalizedPageSize,
      },
      referer: biliVideoReferer(detail.bvid),
    );

    final seenIds = <int>{};
    final replies = readObjectList(data['replies'])
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseVideoComment)
        .whereType<BiliVideoComment>()
        .where((reply) => seenIds.add(reply.id))
        .toList(growable: false);
    final pageInfo = readObjectMap(data['page']);
    final responsePage = readInt(pageInfo['num']) ?? normalizedPage;
    final responsePageSize = readInt(pageInfo['size']) ?? normalizedPageSize;
    final totalCount =
        readInt(pageInfo['count']) ??
        readInt(pageInfo['acount']) ??
        readInt(pageInfo['total']);
    final hasMore = totalCount == null
        ? replies.length >= normalizedPageSize
        : responsePage * responsePageSize < totalCount;
    return BiliVideoCommentReplyPage(
      replies: replies,
      page: responsePage,
      pageSize: responsePageSize,
      totalCount: totalCount,
      hasMore: replies.isNotEmpty && hasMore,
    );
  }

  Future<String> fetchDanmakuXml({
    required String bvid,
    required int cid,
  }) async {
    await _transport.ensureReady();
    final response = await _transport.sendRequest(
      Uri.https(biliApiHost, BiliApiPaths.danmakuList, <String, String>{
        'oid': '$cid',
      }),
      referer: biliVideoReferer(bvid),
      acceptHeader: 'text/xml, */*',
    );
    return response.body;
  }

  Future<List<int>> fetchDanmakuSegment({
    required String bvid,
    required int cid,
    required int aid,
    required int segmentIndex,
  }) {
    return _transport.getBinaryData(
      host: biliApiHost,
      path: BiliApiPaths.danmakuSegWeb,
      params: <String, Object?>{
        'type': 1,
        'oid': cid,
        'segment_index': segmentIndex,
        if (aid > 0) 'pid': aid,
      },
      useWbi: true,
      referer: biliVideoReferer(bvid),
    );
  }

  Future<List<int>> fetchDanmakuView({
    required String bvid,
    required int cid,
    required int aid,
  }) {
    return _transport.getBinaryData(
      host: biliApiHost,
      path: BiliApiPaths.danmakuViewWeb,
      params: <String, Object?>{'type': 1, 'oid': cid, if (aid > 0) 'pid': aid},
      useWbi: true,
      referer: biliVideoReferer(bvid),
    );
  }

  Future<List<int>> fetchDanmakuSpecialResource({
    required String bvid,
    required String resourceUrl,
  }) {
    final uri = Uri.tryParse(resourceUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !_isAllowedBiliDanmakuResourceHost(uri.host)) {
      final rejectedHost = uri == null || uri.host.isEmpty
          ? '<none>'
          : uri.host;
      debugPrint('[BiliDanmaku] rejected special resource host: $rejectedHost');
      throw const FormatException('unsupported danmaku resource URL');
    }
    return _transport
        .sendRequest(
          uri,
          referer: biliVideoReferer(bvid),
          acceptHeader: 'application/octet-stream, */*',
          includeCookies: false,
        )
        .then((response) => response.bodyBytes);
  }

  Future<BiliVideoEngagement> fetchVideoEngagement(
    BiliVideoDetail detail,
  ) async {
    await _transport.ensureReady();
    if (!_transport.hasAuthenticatedSession) {
      return const BiliVideoEngagement.guest();
    }

    final relation = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.archiveRelation,
      params: <String, Object?>{'aid': detail.aid, 'bvid': detail.bvid},
      referer: biliVideoReferer(detail.bvid),
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
      host: biliApiHost,
      path: BiliApiPaths.archiveLike,
      data: <String, Object?>{
        'aid': detail.aid,
        'bvid': detail.bvid,
        'like': liked ? 1 : 2,
      },
      referer: biliVideoReferer(detail.bvid),
    );
    return _refreshEngagementAfterMutation(
      detail: detail,
      fallback: base.copyWith(isAuthenticated: true, isLiked: liked),
    );
  }

  Future<int> fetchVideoCoinCount(BiliVideoDetail detail) async {
    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.archiveCoins,
      params: <String, Object?>{'aid': detail.aid, 'bvid': detail.bvid},
      referer: biliVideoReferer(detail.bvid),
    );
    return readInt(data['multiply']) ??
        readInt(data['coins']) ??
        readInt(data['count']) ??
        0;
  }

  Future<int> addVideoCoin({
    required BiliVideoDetail detail,
    int multiply = 1,
    bool selectLike = true,
  }) async {
    final normalizedMultiply = multiply.clamp(1, 2).toInt();
    await _transport.postData(
      host: biliApiHost,
      path: BiliApiPaths.coinAdd,
      data: <String, Object?>{
        'aid': detail.aid,
        'bvid': detail.bvid,
        'multiply': normalizedMultiply,
        'select_like': selectLike ? 1 : 0,
      },
      referer: biliVideoReferer(detail.bvid),
    );
    try {
      return await fetchVideoCoinCount(detail);
    } catch (_) {
      return normalizedMultiply;
    }
  }

  Future<BiliVideoComment?> addVideoComment({
    required BiliVideoDetail detail,
    required String message,
  }) async {
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) {
      throw const BiliApiException('评论内容不能为空。');
    }

    final data = await _transport.postApiData(
      host: biliApiHost,
      path: BiliApiPaths.replyAdd,
      data: <String, Object?>{
        'type': 1,
        'oid': detail.aid,
        'message': normalizedMessage,
        'plat': 1,
      },
      referer: biliVideoReferer(detail.bvid),
    );
    final map = readObjectMap(data);
    final reply = readObjectMap(map['reply']);
    if (reply.isNotEmpty) {
      return _parseVideoComment(reply);
    }
    return _parseVideoComment(map);
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
      host: biliApiHost,
      path: BiliApiPaths.favResourceDeal,
      data: <String, Object?>{
        'rid': detail.aid,
        'type': biliVideoFavoriteType,
        'add_media_ids': joinIntList(addIds),
        'del_media_ids': joinIntList(delIds),
      },
      referer: biliVideoReferer(detail.bvid),
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
      host: biliApiHost,
      path: BiliApiPaths.relationModify,
      data: <String, Object?>{
        'fid': detail.ownerMid,
        'act': following ? 1 : 2,
        're_src': 14,
      },
      referer: biliSpaceReferer(detail.ownerMid),
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
      host: biliApiHost,
      path: BiliApiPaths.shareAdd,
      data: <String, Object?>{'aid': detail.aid, 'bvid': detail.bvid},
      referer: biliVideoReferer(detail.bvid),
    );
    final map = readObjectMap(data);
    if (map.isNotEmpty) {
      return readInt(map['share']) ??
          readInt(map['count']) ??
          readInt(map['num']);
    }
    return readInt(data);
  }

  BiliVideoComment? _parseVideoComment(Map<String, Object?> value) {
    final id = readInt(value['rpid']) ?? readInt(value['id']) ?? 0;
    if (id <= 0) {
      return null;
    }

    final member = readObjectMap(value['member']);
    final levelInfo = readObjectMap(member['level_info']);
    final content = readObjectMap(value['content']);
    final message = _readBiliCommentMessage(content['message']);
    final replies = readObjectList(value['replies'])
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseVideoComment)
        .whereType<BiliVideoComment>()
        .toList(growable: false);
    final level = readInt(levelInfo['current_level']);
    final pictures = readObjectList(content['pictures'])
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseCommentPicture)
        .whereType<BiliCommentPicture>()
        .toList(growable: false);

    return BiliVideoComment(
      id: id,
      authorName:
          readString(member['uname']) ??
          readString(member['name']) ??
          readString(member['mid']) ??
          '用户',
      authorAvatarUrl: biliNormalizeImageUrl(
        readString(member['avatar']) ?? readString(member['face']) ?? '',
      ),
      authorLevelLabel: level == null || level <= 0 ? null : 'LV$level',
      createdAtLabel: _readCommentCreatedAtLabel(value['ctime']),
      message: message,
      likeCountLabel: biliFormatCount(readDouble(value['like'])),
      replyCount:
          readInt(value['rcount']) ?? readInt(value['count']) ?? replies.length,
      liked: (readInt(value['action']) ?? 0) > 0,
      pictures: pictures,
      replies: replies,
      timeLinks: _parseCommentTimeLinks(
        message,
        jumpUrl: readObjectMap(content['jump_url']),
      ),
    );
  }

  BiliCommentPicture? _parseCommentPicture(Map<String, Object?> value) {
    final url =
        readString(value['img_src']) ??
        readString(value['src']) ??
        readString(value['url']);
    if (url == null || url.isEmpty) {
      return null;
    }
    return BiliCommentPicture(
      url: biliNormalizeImageUrl(url),
      width: readInt(value['img_width']) ?? readInt(value['width']),
      height: readInt(value['img_height']) ?? readInt(value['height']),
    );
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
      host: biliApiHost,
      path: BiliApiPaths.favFolderListAll,
      params: <String, Object?>{
        'rid': detail.aid,
        'up_mid': currentMid,
        'type': biliVideoFavoriteType,
      },
      referer: biliVideoReferer(detail.bvid),
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
      host: biliApiHost,
      path: BiliApiPaths.nav,
      referer: biliDefaultReferer,
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

bool _isAllowedBiliDanmakuResourceHost(String host) {
  final normalized = host.toLowerCase();
  return _biliDanmakuResourceDomains.any(
    (domain) => normalized == domain || normalized.endsWith('.$domain'),
  );
}

const _biliDanmakuResourceDomains = <String>['bilibili.com', 'hdslb.com'];

String _readBiliCommentMessage(Object? value) {
  final raw = readString(value) ?? '';
  return biliDecodeHtmlEntities(
    raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
  ).trim();
}

String _readCommentCreatedAtLabel(Object? value) {
  final unixSeconds = readInt(value);
  if (unixSeconds == null || unixSeconds <= 0) {
    return '';
  }

  final publishedAt = DateTime.fromMillisecondsSinceEpoch(
    unixSeconds * 1000,
  ).toLocal();
  final now = DateTime.now();
  final difference = now.difference(publishedAt);
  if (!difference.isNegative) {
    if (difference.inMinutes < 1) {
      return '刚刚';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    }
  }
  return publishedAt.toString().split(' ').first;
}

List<BiliCommentTimeLink> _parseCommentTimeLinks(
  String message, {
  Map<String, Object?> jumpUrl = const <String, Object?>{},
}) {
  final links = <BiliCommentTimeLink>[];
  final seen = <String>{};
  void addLink(BiliCommentTimeLink link) {
    final key = '${link.label}:${link.seconds}:${link.start}:${link.end}';
    if (seen.add(key)) {
      links.add(link);
    }
  }

  for (final match in _commentTimePattern.allMatches(message)) {
    final label = match.group(0)!;
    final seconds = _parseCommentTimeSeconds(label);
    if (seconds != null) {
      addLink(
        BiliCommentTimeLink(
          label: label,
          seconds: seconds,
          start: match.start,
          end: match.end,
        ),
      );
    }
  }

  for (final entry in jumpUrl.entries) {
    final item = readObjectMap(entry.value);
    final title = readString(item['title']) ?? readString(entry.key);
    if (title == null) {
      continue;
    }
    for (final match in _commentTimePattern.allMatches(title)) {
      final label = match.group(0)!;
      final seconds = _parseCommentTimeSeconds(label);
      if (seconds == null) {
        continue;
      }
      final inline = links.any(
        (link) => link.label == label && link.seconds == seconds,
      );
      if (!inline) {
        addLink(BiliCommentTimeLink(label: label, seconds: seconds));
      }
    }
  }

  links.sort((left, right) {
    final leftStart = left.start ?? 1 << 30;
    final rightStart = right.start ?? 1 << 30;
    return leftStart.compareTo(rightStart);
  });
  return links;
}

final RegExp _commentTimePattern = RegExp(
  r'(?<!\d)(\d{1,2}:\d{2}(?::\d{2})?)(?!\d)',
);

int? _parseCommentTimeSeconds(String label) {
  final parts = label.split(':').map(int.tryParse).toList(growable: false);
  if (parts.any((part) => part == null)) {
    return null;
  }
  if (parts.length == 2) {
    final minutes = parts[0]!;
    final seconds = parts[1]!;
    if (seconds >= 60) {
      return null;
    }
    return minutes * 60 + seconds;
  }
  if (parts.length == 3) {
    final hours = parts[0]!;
    final minutes = parts[1]!;
    final seconds = parts[2]!;
    if (minutes >= 60 || seconds >= 60) {
      return null;
    }
    return hours * 3600 + minutes * 60 + seconds;
  }
  return null;
}
