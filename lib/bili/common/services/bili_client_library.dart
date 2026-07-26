part of 'bili_client.dart';

/// APIs backing the account library surfaces (following, history and watch
/// later).  These endpoints are deliberately kept separate from playback and
/// engagement so a failed library request cannot prevent a video from opening.
extension BiliClientLibrary on BiliClient {
  Future<List<BiliFollowingUser>> fetchFollowingUsers({
    int? mid,
    int page = 1,
    int pageSize = 20,
  }) async {
    await _transport.ensureReady();
    final resolvedMid = mid ?? await _resolveCurrentUserMid();
    if (resolvedMid == null || resolvedMid <= 0) {
      throw const BiliApiException('请先登录 Bilibili 后查看关注列表。', code: -101);
    }

    final normalizedPage = page < 1 ? 1 : page;
    final normalizedPageSize = pageSize.clamp(1, 50).toInt();
    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.relationFollowings,
      params: <String, Object?>{
        'vmid': resolvedMid,
        'pn': normalizedPage,
        'ps': normalizedPageSize,
        'order': 'desc',
        'order_type': 'attention',
        'jsonp': 'jsonp',
      },
      referer: biliFansFollowReferer(resolvedMid),
    );

    final rawUsers = _firstList(data, const <String>['list', 'items']);
    return rawUsers
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseFollowingUser)
        .whereType<BiliFollowingUser>()
        .toList(growable: false);
  }

  /// Alias retained for call sites that use the endpoint's terminology.
  Future<List<BiliFollowingUser>> fetchFollowing({
    int? mid,
    int page = 1,
    int pageSize = 20,
  }) {
    return fetchFollowingUsers(mid: mid, page: page, pageSize: pageSize);
  }

  /// Fetches the server-side history list.  The cursor endpoint uses `max`
  /// and `view_at` instead of a conventional page number; callers that need
  /// cursor pagination can pass the values returned by Bilibili directly.
  Future<List<BiliRemoteHistoryEntry>> fetchRemoteHistory({
    int page = 1,
    int pageSize = 20,
    int max = 0,
    int viewAtMs = 0,
  }) async {
    final result = await fetchRemoteHistoryPage(
      page: page,
      pageSize: pageSize,
      max: max,
      viewAtMs: viewAtMs,
    );
    return result.entries;
  }

  Future<BiliRemoteHistoryPage> fetchRemoteHistoryPage({
    int page = 1,
    int pageSize = 20,
    int max = 0,
    int viewAtMs = 0,
  }) async {
    await _transport.ensureReady();
    final normalizedPageSize = pageSize.clamp(1, 30).toInt();
    // ATV-Bilibili-demo still uses the older page endpoint. Prefer it when
    // available, then fall back to the cursor endpoint used by the web app.
    // An empty legacy page is not treated as authoritative because older
    // servers can return an empty envelope for an unsupported business value.
    final legacy = await _tryFetchRemoteHistoryLegacy(
      page: page,
      pageSize: normalizedPageSize,
    );
    if (legacy != null && legacy.isNotEmpty) {
      return BiliRemoteHistoryPage(
        entries: legacy,
        hasMore: legacy.length >= normalizedPageSize,
      );
    }

    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.historyCursor,
      params: <String, Object?>{
        'max': max,
        'view_at': viewAtMs <= 0 ? 0 : viewAtMs ~/ 1000,
        'business': 'all',
        'ps': normalizedPageSize,
      },
      referer: biliHistoryReferer,
    );
    final entries = _parseRemoteHistoryList(data);
    final cursor = readObjectMap(data['cursor']);
    final nextMax = readInt(cursor['max']) ?? 0;
    final nextViewAtMs = _timestampToMs(readInt(cursor['view_at']));
    return BiliRemoteHistoryPage(
      entries: entries,
      hasMore: entries.isNotEmpty && (nextMax > 0 || nextViewAtMs > 0),
      nextMax: nextMax,
      nextViewAtMs: nextViewAtMs,
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
  }) async {
    await _transport.ensureReady();
    final normalizedPage = page < 1 ? 1 : page;
    final legacy = await _tryFetchWatchLaterLegacy(
      page: normalizedPage,
      pageSize: pageSize,
    );
    if (legacy != null && legacy.isNotEmpty) {
      return legacy;
    }
    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.historyToviewWeb,
      params: <String, Object?>{
        'pn': normalizedPage,
        'ps': pageSize.clamp(1, 30).toInt(),
      },
      referer: biliWatchlaterReferer,
    );

    return _parseWatchLaterList(data);
  }

  Future<List<BiliRemoteHistoryEntry>?> _tryFetchRemoteHistoryLegacy({
    required int page,
    required int pageSize,
  }) async {
    try {
      final data = await _transport.getApiData(
        host: biliApiHost,
        path: BiliApiPaths.historyV2,
        params: <String, Object?>{
          'pn': page < 1 ? 1 : page,
          'ps': pageSize.clamp(1, 30).toInt(),
          'business': 'all',
        },
        referer: biliHistoryReferer,
        ensureReady: false,
      );
      return _parseRemoteHistoryValue(data);
    } on BiliApiException catch (error) {
      // Authentication errors should remain visible to the library page;
      // other legacy endpoint failures can use the cursor fallback.
      if (error.code == -101) {
        rethrow;
      }
      return null;
    } on IOException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<List<BiliWatchLaterEntry>?> _tryFetchWatchLaterLegacy({
    required int page,
    required int pageSize,
  }) async {
    try {
      final data = await _transport.getApiData(
        host: biliApiHost,
        path: BiliApiPaths.historyToview,
        params: <String, Object?>{
          'pn': page,
          'ps': pageSize.clamp(1, 30).toInt(),
        },
        referer: biliWatchlaterReferer,
        ensureReady: false,
      );
      return _parseWatchLaterValue(data);
    } on BiliApiException catch (error) {
      if (error.code == -101) {
        rethrow;
      }
      return null;
    } on IOException {
      return null;
    } on FormatException {
      return null;
    }
  }

  List<BiliRemoteHistoryEntry> _parseRemoteHistoryList(
    Map<String, Object?> data,
  ) {
    final rawItems = _firstList(data, const <String>[
      'list',
      'history',
      'items',
    ]);
    return rawItems
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseRemoteHistoryEntry)
        .whereType<BiliRemoteHistoryEntry>()
        .toList(growable: false);
  }

  List<BiliRemoteHistoryEntry> _parseRemoteHistoryValue(Object? value) {
    if (value is List) {
      return value
          .whereType<Map<Object?, Object?>>()
          .map(readObjectMap)
          .map(_parseRemoteHistoryEntry)
          .whereType<BiliRemoteHistoryEntry>()
          .toList(growable: false);
    }
    return _parseRemoteHistoryList(readObjectMap(value));
  }

  List<BiliWatchLaterEntry> _parseWatchLaterList(Map<String, Object?> data) {
    final rawItems = _firstList(data, const <String>['list', 'items']);
    return rawItems
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseWatchLaterEntry)
        .whereType<BiliWatchLaterEntry>()
        .toList(growable: false);
  }

  List<BiliWatchLaterEntry> _parseWatchLaterValue(Object? value) {
    if (value is List) {
      return value
          .whereType<Map<Object?, Object?>>()
          .map(readObjectMap)
          .map(_parseWatchLaterEntry)
          .whereType<BiliWatchLaterEntry>()
          .toList(growable: false);
    }
    return _parseWatchLaterList(readObjectMap(value));
  }

  Future<void> addToWatchLater({required String bvid, int? aid}) async {
    final normalizedBvid = bvid.trim();
    if (normalizedBvid.isEmpty && (aid == null || aid <= 0)) {
      throw const BiliApiException('缺少视频 ID，无法加入稍后再看。');
    }
    await _transport.postData(
      host: biliApiHost,
      path: BiliApiPaths.historyToviewAdd,
      data: <String, Object?>{
        if (normalizedBvid.isNotEmpty) 'bvid': normalizedBvid,
        if (aid != null && aid > 0) 'aid': aid,
      },
      referer: biliDefaultReferer,
    );
  }

  Future<void> removeFromWatchLater({String? bvid, int? aid}) async {
    final normalizedBvid = bvid?.trim() ?? '';
    if (normalizedBvid.isEmpty && (aid == null || aid <= 0)) {
      throw const BiliApiException('缺少视频 ID，无法移出稍后再看。');
    }
    await _transport.postData(
      host: biliApiHost,
      path: BiliApiPaths.historyToviewDel,
      data: <String, Object?>{
        if (normalizedBvid.isNotEmpty) 'bvid': normalizedBvid,
        if (aid != null && aid > 0) 'aid': aid,
      },
      referer: biliWatchlaterReferer,
    );
  }

  /// Best-effort membership check for the current video.  Bilibili does not
  /// expose a stable per-video watch-later endpoint, so this checks the first
  /// server page and leaves the mutation endpoints as the source of truth.
  Future<bool> isVideoInWatchLater({required String bvid, int? aid}) async {
    final normalizedBvid = bvid.trim();
    final normalizedAid = aid != null && aid > 0 ? aid : null;
    if (normalizedBvid.isEmpty && normalizedAid == null) {
      return false;
    }
    final entries = await fetchWatchLater(pageSize: 30);
    return entries.any(
      (entry) =>
          (normalizedBvid.isNotEmpty && entry.bvid == normalizedBvid) ||
          (normalizedAid != null && entry.aid == normalizedAid),
    );
  }

  /// Alias used by UI callers that prefer the shorter name.
  Future<bool> isInWatchLater({required String bvid, int? aid}) {
    return isVideoInWatchLater(bvid: bvid, aid: aid);
  }

  /// Returns subtitle renditions advertised by Bilibili's player-v2 endpoint
  /// without downloading their JSON bodies. Both the current `/x/player/v2`
  /// route and ATV's WBI-signed `/x/player/wbi/v2` route are supported. A
  /// fallback request failure is propagated so callers do not mistake an
  /// unknown subtitle state for a confirmed empty list.
  Future<List<BiliSubtitleTrack>> fetchVideoSubtitleTracks({
    required String bvid,
    required int cid,
    int? aid,
  }) async {
    await _transport.ensureReady();
    final params = <String, Object?>{
      'bvid': bvid,
      'cid': cid,
      if (aid != null && aid > 0) 'avid': aid,
      'qn': 80,
      'fnval': 4048,
      'fourk': 1,
    };
    List<BiliSubtitleTrack> current = const <BiliSubtitleTrack>[];
    try {
      final data = await _transport.getData(
        host: biliApiHost,
        path: BiliApiPaths.playerV2,
        params: params,
        referer: biliVideoReferer(bvid),
      );
      current = _parseSubtitleTracks(data);
    } on BiliApiException {
      // Try the WBI route below; subtitle availability is optional.
    } on IOException {
      // Try the WBI route below; subtitle availability is optional.
    } on FormatException {
      // Try the WBI route below; subtitle availability is optional.
    }
    if (current.isNotEmpty) {
      return current;
    }

    final data = await _transport.getData(
      host: biliApiHost,
      path: BiliApiPaths.playerWbiV2,
      params: params,
      useWbi: true,
      referer: biliVideoReferer(bvid),
    );
    return _parseSubtitleTracks(data);
  }

  /// Fetches subtitle JSON and materializes each rendition as local WebVTT.
  /// Failed optional subtitle downloads are omitted while the video itself
  /// remains playable.
  Future<List<BiliSubtitleTrack>> fetchVideoSubtitles({
    required String bvid,
    required int cid,
    int? aid,
  }) async {
    final cacheKey = _subtitleCacheKey(bvid: bvid, cid: cid, aid: aid);
    final cached = _subtitleRequests[cacheKey];
    if (cached != null) {
      return cached;
    }

    final request = _fetchVideoSubtitlesUncached(
      bvid: bvid,
      cid: cid,
      aid: aid,
    );
    _subtitleRequests[cacheKey] = request;
    // Do not retain a transient network/API failure. The Future returned to
    // the caller still completes with the original error, while a later
    // playback attempt can retry the request.
    request.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_subtitleRequests[cacheKey], request)) {
          _subtitleRequests.remove(cacheKey);
        }
      },
    );
    return request;
  }

  Future<List<BiliSubtitleTrack>> _fetchVideoSubtitlesUncached({
    required String bvid,
    required int cid,
    int? aid,
  }) async {
    final advertised = await fetchVideoSubtitleTracks(
      bvid: bvid,
      cid: cid,
      aid: aid,
    );
    if (advertised.isEmpty) {
      return advertised;
    }

    final materialized = <BiliSubtitleTrack>[];
    for (final track in advertised) {
      try {
        final local = await _materializeSubtitleTrack(
          track,
          bvid: bvid,
          cid: cid,
        );
        materialized.add(local);
      } catch (_) {
        // A missing/expired subtitle must not fail playback resolution.
      }
    }
    if (materialized.isEmpty) {
      throw const BiliApiException('字幕正文加载失败。');
    }
    return materialized;
  }

  String _subtitleCacheKey({required String bvid, required int cid, int? aid}) {
    return '${bvid.trim()}\u0000$cid\u0000${aid ?? 0}';
  }

  List<Object?> _firstList(Map<String, Object?> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is List<Object?>) {
        return value;
      }
    }
    return const <Object?>[];
  }

  BiliFollowingUser? _parseFollowingUser(Map<String, Object?> value) {
    final mid = readInt(value['mid']) ?? readInt(value['uid']);
    final name = readString(value['uname']) ?? readString(value['name']);
    if (mid == null || mid <= 0 || name == null || name.isEmpty) {
      return null;
    }
    final official = readObjectMap(value['official_verify']);
    final vip = readObjectMap(value['vip']);
    final officialLabel = readString(official['desc']);
    final vipLabel =
        readString(vip['label']) ?? readString(vip['nickname_color']);
    return BiliFollowingUser(
      mid: mid,
      name: name,
      avatarUrl: biliNormalizeImageUrl(
        readString(value['face']) ?? readString(value['avatar']) ?? '',
      ),
      sign: readString(value['sign']) ?? '',
      officialLabel: officialLabel == null || officialLabel.isEmpty
          ? null
          : officialLabel,
      vipLabel: vipLabel == null || vipLabel.isEmpty ? null : vipLabel,
      isSpecial:
          readBool(value['special']) ?? readBool(value['is_special']) ?? false,
    );
  }

  BiliRemoteHistoryEntry? _parseRemoteHistoryEntry(Map<String, Object?> value) {
    final nestedHistory = readObjectMap(value['history']);
    final source = nestedHistory.isEmpty
        ? value
        : <String, Object?>{...value, ...nestedHistory};
    final bvid =
        readString(source['bvid']) ??
        readString(value['bvid']) ??
        readString(source['bv']) ??
        '';
    final business =
        readString(source['business']) ?? readString(value['business']);
    // `oid` is an avid for archive history, but a different identity for PGC
    // and other businesses. Reinterpreting an episode id as an avid would open
    // the wrong resource.
    final legacyArchiveAid = business == null || business == 'archive'
        ? readInt(source['oid']) ?? readInt(value['oid'])
        : null;
    final aid =
        readInt(source['aid']) ??
        readInt(source['avid']) ??
        readInt(value['aid']) ??
        legacyArchiveAid ??
        0;
    final cid =
        readInt(source['cid']) ??
        readInt(source['page_cid']) ??
        readInt(value['cid']) ??
        0;
    final episodeId =
        readInt(source['epid']) ??
        readInt(source['episode_id']) ??
        readInt(source['ep_id']) ??
        readInt(value['epid']) ??
        readInt(value['episode_id']) ??
        readInt(value['ep_id']) ??
        0;
    if (bvid.isEmpty && aid <= 0 && episodeId <= 0) {
      return null;
    }
    final ownerValue = readObjectMap(value['owner']);
    final owner = ownerValue.isEmpty
        ? readObjectMap(source['owner'])
        : ownerValue;
    final authorValue = readObjectMap(value['author']);
    final author = authorValue.isEmpty
        ? readObjectMap(source['author'])
        : authorValue;
    final durationMs = _readDurationMilliseconds(source, value);
    final progressMs = _readProgressMilliseconds(
      source,
      value,
      durationMs: durationMs,
    );
    final viewedAt =
        readInt(source['view_at']) ??
        readInt(source['viewAt']) ??
        readInt(source['last_view_at']) ??
        readInt(value['view_at']) ??
        readInt(value['viewAt']) ??
        0;
    return BiliRemoteHistoryEntry(
      aid: aid,
      bvid: bvid,
      cid: cid,
      episodeId: episodeId,
      title: biliStripHtmlTags(
        readString(value['title']) ?? readString(source['title']) ?? bvid,
      ),
      pageTitle:
          readString(source['part']) ??
          readString(source['page']) ??
          readString(source['page_title']) ??
          '正片',
      coverUrl: biliNormalizeImageUrl(
        readString(value['pic']) ??
            readString(value['cover']) ??
            readString(value['cover_url']) ??
            readString(source['pic']) ??
            readString(source['cover']) ??
            '',
      ),
      ownerName:
          readString(value['author_name']) ??
          readString(owner['name']) ??
          readString(author['name']) ??
          readString(author['uname']) ??
          readString(source['author']) ??
          readString(source['author_name']) ??
          'UP',
      durationMs: durationMs,
      progressMs: progressMs,
      viewedAtMs: _timestampToMs(viewedAt),
      business: business,
    );
  }

  BiliWatchLaterEntry? _parseWatchLaterEntry(Map<String, Object?> value) {
    final nestedHistory = readObjectMap(value['history']);
    final source = nestedHistory.isEmpty
        ? value
        : <String, Object?>{...value, ...nestedHistory};
    final bvid =
        readString(source['bvid']) ??
        readString(value['bvid']) ??
        readString(source['bv']) ??
        '';
    final business =
        readString(source['business']) ?? readString(value['business']);
    final legacyArchiveAid = business == null || business == 'archive'
        ? readInt(source['oid']) ?? readInt(value['oid'])
        : null;
    final aid =
        readInt(source['aid']) ??
        readInt(source['avid']) ??
        readInt(value['aid']) ??
        legacyArchiveAid ??
        0;
    final cid =
        readInt(source['cid']) ??
        readInt(source['first_cid']) ??
        readInt(source['page_cid']) ??
        readInt(value['cid']) ??
        readInt(value['first_cid']) ??
        0;
    final episodeId =
        readInt(source['epid']) ??
        readInt(source['episode_id']) ??
        readInt(source['ep_id']) ??
        readInt(value['epid']) ??
        readInt(value['episode_id']) ??
        readInt(value['ep_id']) ??
        0;
    if (bvid.isEmpty && aid <= 0 && episodeId <= 0) {
      return null;
    }
    final ownerValue = readObjectMap(value['owner']);
    final owner = ownerValue.isEmpty
        ? readObjectMap(source['owner'])
        : ownerValue;
    final authorValue = readObjectMap(value['author']);
    final author = authorValue.isEmpty
        ? readObjectMap(source['author'])
        : authorValue;
    final durationMs = _readDurationMilliseconds(source, value);
    return BiliWatchLaterEntry(
      aid: aid,
      bvid: bvid,
      cid: cid,
      episodeId: episodeId,
      title: biliStripHtmlTags(
        readString(value['title']) ??
            readString(value['show_title']) ??
            readString(source['title']) ??
            bvid,
      ),
      pageTitle:
          readString(value['page']) ??
          readString(value['part']) ??
          readString(source['page_title']) ??
          '正片',
      coverUrl: biliNormalizeImageUrl(
        readString(value['pic']) ??
            readString(value['cover']) ??
            readString(value['cover_url']) ??
            readString(source['pic']) ??
            readString(source['cover']) ??
            '',
      ),
      ownerName:
          readString(owner['name']) ??
          readString(owner['uname']) ??
          readString(author['name']) ??
          readString(author['uname']) ??
          readString(value['author_name']) ??
          readString(source['author']) ??
          'UP',
      durationMs: durationMs,
      progressMs: _readProgressMilliseconds(
        source,
        value,
        durationMs: durationMs,
      ),
      addedAtMs: _timestampToMs(
        readInt(value['add_at']) ??
            readInt(value['addAt']) ??
            readInt(source['add_at']),
      ),
      business: business,
    );
  }

  int _readDurationMilliseconds(
    Map<String, Object?> source,
    Map<String, Object?> value,
  ) {
    final explicitMilliseconds = source['duration_ms'] ?? value['duration_ms'];
    if (explicitMilliseconds != null) {
      return _parseMilliseconds(explicitMilliseconds);
    }
    return _parseSecondsDuration(
      source['duration'] ??
          source['duration_seconds'] ??
          value['duration'] ??
          value['duration_seconds'],
    );
  }

  int _readProgressMilliseconds(
    Map<String, Object?> source,
    Map<String, Object?> value, {
    required int durationMs,
  }) {
    final explicitMilliseconds = source['progress_ms'] ?? value['progress_ms'];
    final seconds =
        source['progress'] ??
        source['progress_seconds'] ??
        value['progress'] ??
        value['progress_seconds'];
    final raw = explicitMilliseconds ?? seconds;
    final numeric = readDouble(raw);
    if (numeric != null && numeric < 0) {
      return durationMs;
    }
    return explicitMilliseconds != null
        ? _parseMilliseconds(explicitMilliseconds)
        : _parseSecondsDuration(seconds);
  }

  int _parseMilliseconds(Object? raw) {
    final numeric = readDouble(raw);
    if (numeric == null ||
        numeric.isNaN ||
        numeric.isInfinite ||
        numeric <= 0) {
      return 0;
    }
    return numeric.round();
  }

  int _parseSecondsDuration(Object? raw) {
    final numeric = readDouble(raw);
    if (numeric != null) {
      if (numeric.isNaN || numeric.isInfinite || numeric <= 0) {
        return 0;
      }
      return (numeric * 1000).round();
    }

    final text = readString(raw);
    if (text == null || text.isEmpty) {
      return 0;
    }
    final parts = text.split(':');
    if (parts.length < 2 || parts.length > 3) {
      return 0;
    }
    final values = parts.map(double.tryParse).toList(growable: false);
    if (values.any(
      (value) => value == null || value.isNaN || value.isInfinite,
    )) {
      return 0;
    }
    final seconds = parts.length == 2
        ? values[0]! * 60 + values[1]!
        : values[0]! * 3600 + values[1]! * 60 + values[2]!;
    return seconds <= 0 ? 0 : (seconds * 1000).round();
  }

  int _timestampToMs(int? timestamp) {
    if (timestamp == null || timestamp <= 0) {
      return 0;
    }
    return timestamp < 100000000000 ? timestamp * 1000 : timestamp;
  }

  List<BiliSubtitleTrack> _parseSubtitleTracks(Map<String, Object?> data) {
    final subtitle = readObjectMap(data['subtitle']);
    final rawItems = _firstList(subtitle, const <String>['subtitles', 'list']);
    final seenIds = <String>{};
    return rawItems
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(_parseSubtitleTrack)
        .whereType<BiliSubtitleTrack>()
        .where((track) => seenIds.add(track.id))
        .toList(growable: false);
  }

  BiliSubtitleTrack? _parseSubtitleTrack(Map<String, Object?> value) {
    final url = _normalizeSubtitleUrl(
      readString(value['subtitle_url']) ??
          readString(value['subtitleUrl']) ??
          readString(value['url']),
    );
    final id = readString(value['id']) ?? readString(value['sid']);
    final language = readString(value['lan']) ?? readString(value['language']);
    if (url == null || url.isEmpty || id == null || id.isEmpty) {
      return null;
    }
    final label =
        readString(value['lan_doc']) ??
        readString(value['language_doc']) ??
        language ??
        '字幕';
    return BiliSubtitleTrack(
      id: id,
      language: language ?? 'und',
      languageLabel: label,
      url: url,
      isDefault:
          readBool(value['is_default']) ??
          readBool(value['isDefault']) ??
          false,
    );
  }

  String? _normalizeSubtitleUrl(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      return null;
    }
    // The API has historically returned absolute, network-relative (`//`),
    // and occasionally root-relative subtitle URLs. Resolve the latter two
    // against the API origin before enforcing the remote HTTP(S) contract.
    final uri = parsed.hasScheme
        ? parsed
        : Uri.parse(biliApiBaseUrl).resolve(value);
    final scheme = uri.scheme.toLowerCase();
    if (uri.host.isEmpty || (scheme != 'http' && scheme != 'https')) {
      return null;
    }
    return uri.toString();
  }

  Future<BiliSubtitleTrack> _materializeSubtitleTrack(
    BiliSubtitleTrack track, {
    required String bvid,
    required int cid,
  }) async {
    final response = await _transport.sendRequest(
      Uri.parse(track.url),
      referer: biliVideoReferer(bvid),
      acceptHeader: 'application/json, text/vtt, */*',
      includeCookies: false,
    );
    final webVtt = _subtitleBodyToWebVtt(response.body);
    if (webVtt == null || webVtt.trim().isEmpty) {
      throw const BiliApiException('字幕响应为空。');
    }
    final directory = Directory(
      '${Directory.systemTemp.path}/bilibili-player-subtitles',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/${sanitizeAssetPart(bvid)}-$cid-${sanitizeAssetPart(track.id)}.vtt',
    );
    final temp = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-$pid',
    );
    await temp.writeAsString(webVtt, flush: true);
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    }
    return BiliSubtitleTrack(
      id: 'subtitle:bili:${track.id}',
      language: track.language,
      languageLabel: track.languageLabel,
      url: file.uri.toString(),
      isDefault: track.isDefault,
    );
  }

  String? _subtitleBodyToWebVtt(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('WEBVTT')) {
      return trimmed.endsWith('\n') ? trimmed : '$trimmed\n';
    }
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
    final map = readObjectMap(decoded);
    final rawBody = readObjectList(map['body']);
    if (rawBody.isEmpty) {
      return null;
    }
    final buffer = StringBuffer('WEBVTT\n\n');
    var cue = 1;
    for (final raw in rawBody) {
      final item = readObjectMap(raw);
      final from = readDouble(item['from']) ?? readDouble(item['start']);
      final to = readDouble(item['to']) ?? readDouble(item['end']);
      final content = biliDecodeHtmlEntities(
        readString(item['content']) ?? readString(item['text']) ?? '',
      );
      if (from == null || to == null || content.isEmpty) {
        continue;
      }
      buffer
        ..writeln(cue)
        ..writeln('${_formatWebVttTime(from)} --> ${_formatWebVttTime(to)}')
        ..writeln(content.replaceAll('\r', '').replaceAll('\n', '\n'))
        ..writeln();
      cue += 1;
    }
    return cue == 1 ? null : buffer.toString();
  }

  String _formatWebVttTime(double seconds) {
    final millis = !seconds.isFinite || seconds <= 0
        ? 0
        : (seconds * 1000).round();
    final hours = millis ~/ 3600000;
    final minutes = (millis % 3600000) ~/ 60000;
    final secs = (millis % 60000) ~/ 1000;
    final remainder = millis % 1000;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${remainder.toString().padLeft(3, '0')}';
  }
}
