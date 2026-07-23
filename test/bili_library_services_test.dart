import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilibili_player/bili/app_mode/pages/bili_library_page.dart';
import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/services/bili_api_core.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  test('parses following, remote history, and watch-later payloads', () async {
    final httpClient = _LibraryHttpClient();
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final following = await client.fetchFollowingUsers();
    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(following.single.mid, 7);
    expect(following.single.avatarUrl, 'https://example.com/avatar.jpg');
    expect(history.single.bvid, 'BV1history');
    expect(history.single.durationMs, 120000);
    expect(history.single.progressMs, 45000);
    expect(history.single.viewedAtMs, 1710000000000);
    expect(watchLater.single.pageTitle, 'P2');
    expect(watchLater.single.durationMs, 90000);
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      containsAll(<String>[
        '/x/relation/followings',
        '/x/web-interface/history/cursor',
        '/x/v2/history/toview/web',
      ]),
    );
  });

  testWidgets('following list loads another ATV page on demand', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(
      multipleFollowingPages: true,
      emptyFollowingAvatars: true,
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await tester.binding.setSurfaceSize(const Size(800, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: BiliLibraryPage(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(find.text('测试 UP 51'), findsOneWidget);
    expect(
      httpClient.requestedUris
          .where((uri) => uri.path == '/x/relation/followings')
          .map((uri) => uri.queryParameters['pn']),
      <String?>['1', '2'],
    );
  });

  testWidgets('following list clears account data after logout', (
    WidgetTester tester,
  ) async {
    final httpClient = _LibraryHttpClient(emptyFollowingAvatars: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await tester.pumpWidget(MaterialApp(home: BiliLibraryPage(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('测试 UP'), findsOneWidget);

    client.clearSession();
    await tester.tap(find.text('历史播放'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();

    expect(find.text('测试 UP'), findsNothing);
    expect(find.text('请先登录 Bilibili 后查看此内容。'), findsOneWidget);
  });

  testWidgets('history auth expiry drops cloud rows but keeps local history', (
    WidgetTester tester,
  ) async {
    late final Directory root;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp(
        'bili-library-history-auth-test-',
      );
    });
    addTearDown(() => root.delete(recursive: true));
    final historyStore = BiliHistoryStore(baseDirectory: root);
    await tester.runAsync(
      () => historyStore.saveEntry(
        const BiliPlaybackHistoryEntry(
          bvid: 'BV1history',
          cid: 11,
          videoTitle: '本地历史',
          pageTitle: '本地 P1',
          coverUrl: '',
          ownerName: '本地 UP',
          playedAtMs: 100,
          lastPositionMs: 1000,
        ),
      ),
    );
    final httpClient = _LibraryHttpClient(
      historyPaginationAuthExpires: true,
      emptyHistoryCovers: true,
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: BiliLibraryPage(
          client: client,
          initialSection: BiliLibrarySection.history,
          historyStore: historyStore,
        ),
      ),
    );
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('历史视频').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('历史视频'), findsOneWidget);
    expect(find.text('本地历史'), findsNothing);
    await tester.tap(find.text('加载更多'));
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('本地历史').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('历史视频'), findsNothing);
    expect(find.text('本地历史'), findsOneWidget);
  });

  test('parses clock-formatted duration and progress fields', () async {
    final httpClient = _LibraryHttpClient(durationAsClockLabel: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.durationMs, 125000);
    expect(history.single.progressMs, 90500);
    expect(watchLater.single.durationMs, 90000);
    expect(watchLater.single.progressMs, 1500);
  });

  test('preserves explicit short millisecond duration fields', () async {
    final httpClient = _LibraryHttpClient(explicitMillisecondFields: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.durationMs, 45000);
    expect(history.single.progressMs, 12000);
    expect(watchLater.single.durationMs, 90000);
    expect(watchLater.single.progressMs, 1500);
  });

  test('returns the next web history cursor without losing units', () async {
    final httpClient = _LibraryHttpClient();
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final page = await client.fetchRemoteHistoryPage(pageSize: 30);

    expect(page.entries, hasLength(1));
    expect(page.hasMore, isTrue);
    expect(page.nextMax, 123);
    expect(page.nextViewAtMs, 1709999999000);
  });

  test('accepts legacy history and watch-later oid fields', () async {
    final httpClient = _LibraryHttpClient(legacyHistoryFields: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.aid, 101);
    expect(history.single.bvid, 'BVlegacy');
    expect(history.single.cid, 1001);
    expect(history.single.ownerName, '旧 UP');
    expect(watchLater.single.aid, 202);
    expect(watchLater.single.bvid, 'BVlegacy-later');
    expect(watchLater.single.cid, 2002);
  });

  test('does not reinterpret an episode id as a content id', () async {
    final httpClient = _LibraryHttpClient(episodeIdWithoutCid: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.cid, 0);
    expect(watchLater.single.cid, 0);
    expect(history.single.episodeId, 9001);
    expect(watchLater.single.episodeId, 9002);
    expect(history.single.aid, 101);
    expect(watchLater.single.aid, 202);
  });

  test('uses ATV legacy history endpoints when they return data', () async {
    final httpClient = _LibraryHttpClient(legacyEndpointOnly: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final history = await client.fetchRemoteHistory();
    final watchLater = await client.fetchWatchLater();

    expect(history.single.aid, 101);
    expect(watchLater.single.aid, 202);
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      containsAll(<String>['/x/v2/history', '/x/v2/history/toview']),
    );
  });

  test(
    'sends watch-later mutations with csrf and parses subtitle JSON',
    () async {
      final httpClient = _LibraryHttpClient();
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
          'DedeUserID': '42',
          'buvid3': 'b3',
          'buvid4': 'b4',
        });
      addTearDown(() => client.transport.httpClient.close(force: true));

      await client.addToWatchLater(bvid: 'BV1later');
      await client.removeFromWatchLater(bvid: 'BV1later');
      expect(await client.isVideoInWatchLater(bvid: 'BV1later'), isTrue);
      expect(await client.isVideoInWatchLater(bvid: 'BVmissing'), isFalse);
      final advertised = await client.fetchVideoSubtitleTracks(
        bvid: 'BV1subtitle',
        cid: 99,
      );

      expect(httpClient.posts, hasLength(2));
      expect(httpClient.posts.first.fields['bvid'], 'BV1later');
      expect(httpClient.posts.first.fields['csrf'], 'csrf');
      expect(advertised.single.language, 'zh-CN');
      expect(advertised.single.url, 'https://subtitle.example/track.json');
    },
  );

  test(
    'materializes Bilibili subtitle JSON as an SDK external WebVTT source',
    () async {
      final httpClient = _LibraryHttpClient();
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
          'DedeUserID': '42',
          'buvid3': 'b3',
          'buvid4': 'b4',
        });
      addTearDown(() => client.transport.httpClient.close(force: true));

      final tracks = await client.fetchVideoSubtitles(
        bvid: 'BV1subtitle',
        cid: 99,
      );
      expect(tracks, hasLength(1));
      final file = File(Uri.parse(tracks.single.url).toFilePath());
      addTearDown(() async {
        if (await file.exists()) {
          await file.delete();
        }
      });
      expect(await file.readAsString(), contains('WEBVTT'));
      expect(await file.readAsString(), contains('你好'));

      final source = BiliResolvedPlayback(
        bvid: 'BV1subtitle',
        cid: 99,
        title: '字幕测试',
        subtitle: 'P1',
        uri: 'file:///tmp/video.mpd',
        protocol: VesperPlayerSourceProtocol.dash,
        transportLabel: 'test',
        isLocalFile: true,
        subtitleTracks: tracks,
      ).toSource();
      final external = source.externalSubtitles.single;
      expect(external.id, 'subtitle:bili:3');
      expect(external.uri, tracks.single.url);
      expect(external.mimeType, VesperExternalSubtitleSource.mimeWebvtt);
      expect(external.language, 'zh-CN');
      expect(external.label, '中文（中国大陆）');
      expect(external.isDefault, isFalse);
      expect(source.toMap()['externalSubtitles'], <Object?>[
        <String, Object?>{
          'id': 'subtitle:bili:3',
          'uri': tracks.single.url,
          'mimeType': VesperExternalSubtitleSource.mimeWebvtt,
          'language': 'zh-CN',
          'label': '中文（中国大陆）',
          'headers': <String, String>{},
          'isDefault': false,
          'isForced': false,
        },
      ]);
    },
  );

  test('coalesces concurrent subtitle materialization requests', () async {
    final httpClient = _LibraryHttpClient();
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final futures = <Future<List<BiliSubtitleTrack>>>{
      client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99),
      client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99),
    };
    final results = await Future.wait(futures);

    expect(results[0], hasLength(1));
    expect(results[1], hasLength(1));
    expect(
      httpClient.requestedUris.where((uri) => uri.path == '/x/player/v2'),
      hasLength(1),
    );
    expect(
      httpClient.requestedUris.where((uri) => uri.host == 'subtitle.example'),
      hasLength(1),
    );
  });

  test('falls back to the ATV WBI subtitle endpoint', () async {
    final httpClient = _LibraryHttpClient(subtitlesOnlyOnWbi: true);
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final tracks = await client.fetchVideoSubtitleTracks(
      bvid: 'BV1subtitle',
      cid: 99,
    );

    expect(tracks, hasLength(1));
    expect(
      httpClient.requestedUris.map((uri) => uri.path),
      containsAllInOrder(<String>['/x/player/v2', '/x/player/wbi/v2']),
    );
  });

  test(
    'propagates failure when subtitle discovery cannot be confirmed',
    () async {
      final httpClient = _LibraryHttpClient(subtitleEndpointsFail: true);
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(const <String, String>{
          'SESSDATA': 'sess',
          'bili_jct': 'csrf',
          'DedeUserID': '42',
          'buvid3': 'b3',
          'buvid4': 'b4',
        });
      addTearDown(() => client.transport.httpClient.close(force: true));

      await expectLater(
        client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99),
        throwsA(isA<BiliApiException>()),
      );
    },
  );

  test('does not truncate subtitle cues at 24 hours', () async {
    final httpClient = _LibraryHttpClient(
      subtitleCueFrom: 90000,
      subtitleCueTo: 90001.5,
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final tracks = await client.fetchVideoSubtitles(
      bvid: 'BV1subtitle',
      cid: 99,
    );
    final file = File(Uri.parse(tracks.single.url).toFilePath());
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });
    expect(await file.readAsString(), contains('25:00:00.000'));
  });

  test('rejects file URLs advertised by the remote subtitle API', () async {
    final httpClient = _LibraryHttpClient(
      subtitleUrl: 'file:///tmp/untrusted-subtitle.vtt',
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final tracks = await client.fetchVideoSubtitleTracks(
      bvid: 'BV1subtitle',
      cid: 99,
    );

    expect(tracks, isEmpty);
    expect(
      httpClient.requestedUris.where((uri) => uri.path == '/x/player/v2'),
      hasLength(1),
    );
    expect(
      httpClient.requestedUris.any((uri) => uri.scheme == 'file'),
      isFalse,
    );
  });

  test('resolves root-relative subtitle URLs against the API origin', () async {
    final httpClient = _LibraryHttpClient(
      subtitleUrl: '/bfs/subtitle/track.json',
    );
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    final tracks = await client.fetchVideoSubtitleTracks(
      bvid: 'BV1subtitle',
      cid: 99,
    );

    expect(
      tracks.single.url,
      'https://api.bilibili.com/bfs/subtitle/track.json',
    );
  });

  test('does not send session cookies to a subtitle CDN', () async {
    final httpClient = _LibraryHttpClient();
    final client = BiliClient(httpClient: httpClient)
      ..restoreCookies(const <String, String>{
        'SESSDATA': 'secret-session',
        'bili_jct': 'secret-csrf',
        'DedeUserID': '42',
        'buvid3': 'b3',
        'buvid4': 'b4',
      });
    addTearDown(() => client.transport.httpClient.close(force: true));

    await client.fetchVideoSubtitles(bvid: 'BV1subtitle', cid: 99);

    final subtitleHeaders = httpClient.requestHeaders.entries
        .firstWhere((entry) => entry.key.host == 'subtitle.example')
        .value;
    final apiHeaders = httpClient.requestHeaders.entries
        .firstWhere((entry) => entry.key.path == '/x/player/v2')
        .value;
    expect(subtitleHeaders, isNot(containsPair('cookie', anything)));
    expect(apiHeaders['cookie'], contains('secret-session'));
  });
}

final class _RecordedPost {
  const _RecordedPost(this.uri, this.fields);

  final Uri uri;
  final Map<String, String> fields;
}

final class _LibraryHttpClient implements HttpClient {
  _LibraryHttpClient({
    this.durationAsClockLabel = false,
    this.explicitMillisecondFields = false,
    this.subtitleUrl = '//subtitle.example/track.json',
    this.legacyHistoryFields = false,
    this.legacyEndpointOnly = false,
    this.episodeIdWithoutCid = false,
    this.subtitlesOnlyOnWbi = false,
    this.subtitleEndpointsFail = false,
    this.subtitleCueFrom = 0,
    this.subtitleCueTo = 1.5,
    this.multipleFollowingPages = false,
    this.emptyFollowingAvatars = false,
    this.historyPaginationAuthExpires = false,
    this.emptyHistoryCovers = false,
  });

  final bool durationAsClockLabel;
  final bool explicitMillisecondFields;
  final String subtitleUrl;
  final bool legacyHistoryFields;
  final bool legacyEndpointOnly;
  final bool episodeIdWithoutCid;
  final bool subtitlesOnlyOnWbi;
  final bool subtitleEndpointsFail;
  final double subtitleCueFrom;
  final double subtitleCueTo;
  final bool multipleFollowingPages;
  final bool emptyFollowingAvatars;
  final bool historyPaginationAuthExpires;
  final bool emptyHistoryCovers;
  final List<Uri> requestedUris = <Uri>[];
  final Map<Uri, Map<String, String>> requestHeaders =
      <Uri, Map<String, String>>{};
  final List<_RecordedPost> posts = <_RecordedPost>[];
  String? _userAgent;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) => _userAgent = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUris.add(url);
    final headers = <String, String>{};
    requestHeaders[url] = headers;
    return _LibraryHttpClientRequest(
      _responseFor(url),
      onHeader: (name, value) => headers[name.toLowerCase()] = value.toString(),
    );
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    requestedUris.add(url);
    final headers = <String, String>{};
    requestHeaders[url] = headers;
    return _LibraryHttpClientRequest(
      _responseFor(url),
      onHeader: (name, value) => headers[name.toLowerCase()] = value.toString(),
      onClose: (body) {
        posts.add(_RecordedPost(url, Uri.splitQueryString(body)));
      },
    );
  }

  _LibraryHttpClientResponse _responseFor(Uri url) {
    if (url.path == '/x/web-interface/nav') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'isLogin': true,
          'mid': 42,
          'wbi_img': <String, Object?>{
            'img_url': 'https://i0.hdslb.com/bfs/wbi/img.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/sub.png',
          },
        },
      });
    }
    if (url.path == '/x/relation/followings') {
      final page = int.tryParse(url.queryParameters['pn'] ?? '') ?? 1;
      final count = multipleFollowingPages ? (page == 1 ? 50 : 1) : 1;
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'list': List<Object?>.generate(
            count,
            (index) => <String, Object?>{
              'mid': multipleFollowingPages ? page * 1000 + index : 7,
              'uname': multipleFollowingPages
                  ? '测试 UP ${(page - 1) * 50 + index + 1}'
                  : '测试 UP',
              'face': emptyFollowingAvatars ? '' : '//example.com/avatar.jpg',
              'sign': '简介',
              'official_verify': <String, Object?>{'desc': '认证'},
            },
          ),
        },
      });
    }
    if (url.path == '/x/v2/history' ||
        url.path == '/x/web-interface/history/cursor') {
      if (historyPaginationAuthExpires &&
          url.path == '/x/v2/history' &&
          url.queryParameters['pn'] == '2') {
        return _json(<String, Object?>{
          'code': -101,
          'message': '账号未登录',
          'data': null,
        });
      }
      if (legacyHistoryFields || legacyEndpointOnly || episodeIdWithoutCid) {
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'history': <String, Object?>{
                  'oid': 101,
                  'bvid': 'BVlegacy',
                  if (episodeIdWithoutCid) 'epid': 9001 else 'cid': 1001,
                  'title': '旧历史',
                  'author': <String, Object?>{'uname': '旧 UP'},
                  'cover': '//example.com/legacy.jpg',
                  'part': '旧 P',
                  'duration': 61,
                  'progress': 12,
                  'view_at': 1710000000,
                },
              },
            ],
          },
        });
      }
      if (url.path == '/x/v2/history') {
        return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
      }
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'cursor': <String, Object?>{'max': 123, 'view_at': 1709999999},
          'list': <Object?>[
            <String, Object?>{
              'aid': 1,
              'bvid': 'BV1history',
              'cid': 11,
              'title': '历史视频',
              'pic': emptyHistoryCovers ? '' : '//example.com/history.jpg',
              'author_name': 'UP',
              'part': 'P1',
              if (explicitMillisecondFields) ...<String, Object?>{
                'duration_ms': 45000,
                'progress_ms': 12000,
              } else ...<String, Object?>{
                'duration': durationAsClockLabel ? '02:05' : 120,
                'progress': durationAsClockLabel ? '01:30.5' : 45,
              },
              'view_at': 1710000000,
            },
          ],
        },
      });
    }
    if (url.path == '/x/v2/history/toview' ||
        url.path == '/x/v2/history/toview/web') {
      if (legacyHistoryFields || legacyEndpointOnly || episodeIdWithoutCid) {
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'oid': 202,
                'bvid': 'BVlegacy-later',
                if (episodeIdWithoutCid) 'episode_id': 9002 else 'cid': 2002,
                'show_title': '旧稍后',
                'cover_url': '//example.com/legacy-later.jpg',
                'author_name': '旧稍后 UP',
                'duration': 70,
                'progress': 5,
                'addAt': 1710000000,
              },
            ],
          },
        });
      }
      if (url.path == '/x/v2/history/toview') {
        return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
      }
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'aid': 2,
              'bvid': 'BV1later',
              'cid': 22,
              'title': '稍后视频',
              'pic': 'https://example.com/later.jpg',
              'page': 'P2',
              if (explicitMillisecondFields) ...<String, Object?>{
                'duration_ms': 90000,
                'progress_ms': 1500,
              } else ...<String, Object?>{
                'duration': durationAsClockLabel ? '01:30' : 90,
                'progress': durationAsClockLabel ? '00:01.5' : 0,
              },
              'owner': <String, Object?>{'name': 'UP2'},
            },
          ],
        },
      });
    }
    if (url.path == '/x/player/v2' || url.path == '/x/player/wbi/v2') {
      if (subtitleEndpointsFail) {
        return _json(<String, Object?>{
          'code': -500,
          'message': 'subtitle endpoint unavailable',
        });
      }
      final hasSubtitles =
          !subtitlesOnlyOnWbi || url.path == '/x/player/wbi/v2';
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'subtitle': <String, Object?>{
            'subtitles': hasSubtitles
                ? <Object?>[
                    <String, Object?>{
                      'id': 3,
                      'lan': 'zh-CN',
                      'lan_doc': '中文（中国大陆）',
                      'subtitle_url': subtitleUrl,
                    },
                  ]
                : const <Object?>[],
          },
        },
      });
    }
    if (url.host == 'subtitle.example') {
      return _raw(<String, Object?>{
        'body': <Object?>[
          <String, Object?>{
            'from': subtitleCueFrom,
            'to': subtitleCueTo,
            'content': '你好',
          },
        ],
      });
    }
    return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
  }

  _LibraryHttpClientResponse _json(Map<String, Object?> value) {
    return _raw(value);
  }

  _LibraryHttpClientResponse _raw(Object value) {
    return _LibraryHttpClientResponse(jsonEncode(value));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LibraryHttpClientRequest implements HttpClientRequest {
  _LibraryHttpClientRequest(
    this._response, {
    this.onClose,
    void Function(String name, Object value)? onHeader,
  }) : _headers = _LibraryHttpHeaders(onSet: onHeader);

  final _LibraryHttpClientResponse _response;
  final void Function(String body)? onClose;
  final _LibraryHttpHeaders _headers;
  final List<int> _body = <int>[];
  int _contentLength = -1;

  @override
  HttpHeaders get headers => _headers;

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) => _contentLength = value;

  @override
  void add(List<int> data) => _body.addAll(data);

  @override
  Future<HttpClientResponse> close() async {
    if (onClose != null) {
      onClose!(utf8.decode(_body));
    }
    return _response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LibraryHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _LibraryHttpClientResponse(this.body);

  final String body;
  @override
  final int statusCode = HttpStatus.ok;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  HttpHeaders get headers => _LibraryHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[
      utf8.encode(body),
    ]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LibraryHttpHeaders implements HttpHeaders {
  _LibraryHttpHeaders({this.onSet});

  final void Function(String name, Object value)? onSet;
  ContentType? _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) => _contentType = value;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    onSet?.call(name, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
