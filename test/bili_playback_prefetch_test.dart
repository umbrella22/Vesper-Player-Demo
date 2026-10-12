import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_audio_policy.dart';
import 'package:vesper_media/bili/common/services/bili_audio_policy_controller.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_playback_prefetcher.dart';
import 'package:vesper_media/bili/common/services/bili_playback_target.dart';
import 'package:vesper_media/bili/common/services/bili_transport.dart';
import 'package:vesper_media/bili/common/services/bili_endpoints.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  BiliPlaybackPrefetchKey key(String id) => (bvid: id, cid: 1);
  const value = BiliPrefetchedPlayback(dashData: {'test': 1});

  test('cache expiry and LRU access respect the configured budgets', () async {
    var now = DateTime(2026);
    final cache = BiliPlaybackPrefetcher(capacity: 2, now: () => now);
    var loads = 0;
    Future<BiliPrefetchedPlayback?> load(bool Function() _) async {
      loads++;
      return value;
    }

    await cache.prefetch(key('a'), load);
    await cache.prefetch(key('b'), load);
    await cache.prefetch(key('a'), load); // Refresh LRU, not TTL.
    await cache.prefetch(key('c'), load);
    expect(loads, 3);
    expect(cache.take(key('b')), isNull);
    now = now.add(const Duration(seconds: 120));
    expect(cache.take(key('a')), isNull);
    expect(cache.take(key('c')), isNull);
  });

  test(
    'deduplicates work, bounds concurrency and discards late results after clear',
    () async {
      final cache = BiliPlaybackPrefetcher();
      final gates = <String, Completer<BiliPrefetchedPlayback?>>{};
      final started = <String>[];
      Future<void> enqueue(String id) => cache.prefetch(key(id), (_) {
        started.add(id);
        return (gates[id] = Completer<BiliPrefetchedPlayback?>()).future;
      });
      final a = enqueue('a');
      final duplicate = enqueue('a');
      final b = enqueue('b');
      final c = enqueue('c');
      expect(started, ['a', 'b']);
      gates['a']!.complete(value);
      await a;
      await duplicate;
      await pumpEventQueue();
      expect(started, ['a', 'b', 'c']);
      cache.clear();
      gates['b']!.complete(value);
      gates['c']!.complete(value);
      await Future.wait([b, c]);
      await pumpEventQueue();
      expect(cache.take(key('a')), isNull);
      expect(cache.take(key('b')), isNull);
      expect(cache.take(key('c')), isNull);
    },
  );

  test('click removes queued speculation and prevents late refill', () async {
    final cache = BiliPlaybackPrefetcher(concurrency: 1);
    final gate = Completer<BiliPrefetchedPlayback?>();
    final first = cache.prefetch(key('a'), (_) => gate.future);
    var secondStarted = false;
    final second = cache.prefetch(key('b'), (_) async {
      secondStarted = true;
      return value;
    });
    cache.stopPrefetching('b');
    cache.take(key('a'));
    gate.complete(value);
    await Future.wait([first, second]);
    await pumpEventQueue();
    expect(secondStarted, isFalse);
    expect(cache.take(key('a')), isNull);
  });

  test('feed parses optional positive cid without inventing one', () {
    Map<String, Object?> card(Object? cid) => {
      'bvid': 'BV1fast',
      'id': 1,
      'cid': cid,
    };
    expect(parseBiliFeedVideo(card(22))!.cid, 22);
    expect(parseBiliFeedVideo(card(null))!.cid, isNull);
    expect(parseBiliFeedVideo(card(0))!.cid, isNull);
  });

  test(
    'prefetch uses foreground parameters; raw hit short-circuits one request',
    () async {
      final client = _playbackClient();
      await client.prefetchFeedPlayback([feed()]);
      expect(client.fakeTransport.requests, hasLength(1));
      final params = client.fakeTransport.requests.single;
      final resolved = await _resolve(client);
      expect(resolved.transportLabel, contains('playurl=prefetch'));
      expect(client.fakeTransport.requests, hasLength(1));
      await _resolve(client);
      expect(client.fakeTransport.requests, hasLength(2));
      expect(client.fakeTransport.requests.last, params);
    },
  );

  test(
    'invalid cached response falls through to the complete network variant chain',
    () async {
      final client = _playbackClient();
      await client.playbackPrefetcher.prefetch(
        (bvid: detail.bvid, cid: page.cid),
        (_) async => BiliPrefetchedPlayback(
          dashData: const {},
          variant: biliDashRequestVariants.first,
        ),
      );
      client.fakeTransport.failFirstVariant = true;
      final resolved = await _resolve(client);
      expect(client.fakeTransport.requests.map((request) => request['fnval']), [
        4048,
        976,
      ]);
      expect(resolved.transportLabel, contains('web fnval=976'));
    },
  );

  test('session replacement discards cache and in-flight results', () async {
    final client = _playbackClient();
    final gate = Completer<void>();
    client.fakeTransport.playurlGate = gate;
    final pending = client.prefetchFeedPlayback([feed()]);
    await pumpEventQueue();
    client.restoreCookies({'SESSDATA': 'new-session', 'bili_jct': 'new-csrf'});
    gate.complete();
    await pending;
    await pumpEventQueue();
    client.fakeTransport.playurlGate = null;
    final resolved = await _resolve(client);
    expect(resolved.transportLabel, isNot(contains('playurl=prefetch')));
    expect(client.fakeTransport.requests, hasLength(2));
    await client.prefetchFeedPlayback([feed()]);
    client.clearSession();
    expect(
      client.playbackPrefetcher.take((bvid: detail.bvid, cid: page.cid)),
      isNull,
    );
  });

  test(
    'missing cid prefetches detail only and target lookup consumes it',
    () async {
      final client = _playbackClient();
      await client.prefetchFeedPlayback([feed(cid: null)]);
      expect(client.detailRequests, 1);
      expect(client.fakeTransport.requests, isEmpty);
      final target = await client.resolvePlaybackTarget(
        BiliPendingPlaybackTarget(bvid: detail.bvid),
      );
      expect(target.detail, same(detail));
      expect(target.initialPage, same(page));
      expect(client.detailRequests, 1);
    },
  );

  test(
    'subtitle deadline runs alongside slow playurl and late errors are observed',
    () async {
      final client = _playbackClient();
      final subtitleGate = client.subtitleGate =
          Completer<List<BiliSubtitleTrack>>();
      final playurlGate = client.fakeTransport.playurlGate = Completer<void>();
      final pending = _resolve(client);
      await pumpEventQueue();
      expect(client.subtitleRequests, 1);
      expect(client.fakeTransport.requests, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 650));
      playurlGate.complete();
      final resolved = await pending.timeout(const Duration(milliseconds: 500));
      expect(resolved.subtitleTracks, isEmpty);
      expect(resolved.subtitleError, contains('已跳过'));
      subtitleGate.completeError(StateError('late subtitle error'));
      await pumpEventQueue();
      expect(client.subtitleRequests, 1);
    },
  );

  test(
    'MPD filtering keeps FLAC; re-resolve never overwrites the active manifest',
    () async {
      final client = _playbackClient();
      final original = await _resolve(client);
      final originalText = await File.fromUri(
        Uri.parse(original.uri),
      ).readAsString();
      expect(originalText, contains('ec-3'));
      await client.audioPolicy.setOverride(BiliAudioPolicyOverride.blockDolby);
      final filtered = await _resolve(client);
      final text = await File.fromUri(Uri.parse(filtered.uri)).readAsString();
      expect(text, isNot(contains('ec-3')));
      expect(text, contains('fLaC'));
      expect(text, contains('mp4a'));
      expect(filtered.transportLabel, contains('dolby-blocked(override)'));
      expect(filtered.dolbyAudioBlocked, isTrue);
      expect(filtered.canRefreshSource, isTrue);
      expect(filtered.uri, isNot(original.uri));
      expect(
        await File.fromUri(Uri.parse(original.uri)).readAsString(),
        originalText,
      );
    },
  );
}

_TestClient _playbackClient() {
  final transport = _PlaybackTransport();
  addTearDown(() => transport.httpClient.close(force: true));
  return _TestClient(transport);
}

Future<BiliResolvedPlayback> _resolve(_TestClient client) async {
  final resolved = await client.resolvePlayback(
    detail: detail,
    page: page,
    platform: TargetPlatform.android,
  );
  addTearDown(() async {
    for (final uri in [
      resolved.uri,
      if (resolved.audioOnlySource != null) resolved.audioOnlySource!.uri,
    ]) {
      final file = File.fromUri(Uri.parse(uri));
      if (await file.exists()) await file.delete();
    }
  });
  return resolved;
}

class _TestClient extends BiliClient {
  _TestClient(this.fakeTransport)
    : super(transport: fakeTransport, audioPolicy: BiliAudioPolicyController());
  final _PlaybackTransport fakeTransport;
  int detailRequests = 0;
  int subtitleRequests = 0;
  Completer<List<BiliSubtitleTrack>>? subtitleGate;
  @override
  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async {
    detailRequests++;
    return detail;
  }

  @override
  Future<List<BiliSubtitleTrack>> fetchVideoSubtitles({
    required String bvid,
    required int cid,
    int? aid,
  }) async {
    subtitleRequests++;
    return subtitleGate?.future ?? <BiliSubtitleTrack>[];
  }
}

class _PlaybackTransport extends BiliTransport {
  final requests = <Map<String, Object?>>[];
  Completer<void>? playurlGate;
  bool failFirstVariant = false;
  @override
  String buildSessionValue() => 'test-session';
  @override
  Future<Map<String, Object?>> getData({
    required String host,
    required String path,
    Map<String, Object?> params = const {},
    bool useWbi = false,
    String referer = biliDefaultReferer,
    bool ensureReady = true,
    Set<int> allowedCodes = const {0},
  }) async {
    expect(path, '/x/player/wbi/playurl');
    expect(useWbi, isTrue);
    expect(referer, 'https://www.bilibili.com/video/${detail.bvid}');
    requests.add(params);
    await playurlGate?.future;
    if (failFirstVariant && params['fnval'] == 4048) {
      throw const BiliApiException('try compatible request');
    }
    return dashData();
  }
}

const page = BiliVideoPageEntry(
  cid: 22,
  pageNumber: 1,
  title: 'first',
  durationSeconds: 60,
);
const detail = BiliVideoDetail(
  aid: 1,
  bvid: 'BV1fast',
  title: 'Fast',
  ownerMid: 2,
  ownerName: 'UP',
  ownerAvatarUrl: '',
  coverUrl: '',
  description: '',
  publishedAtLabel: null,
  playCountLabel: '',
  danmakuCountLabel: '',
  replyCountLabel: '',
  likeCountLabel: '',
  coinCountLabel: '',
  favoriteCountLabel: '',
  shareCountLabel: '',
  pages: [page],
);
BiliFeedVideo feed({int? cid = 22}) => BiliFeedVideo(
  aid: 1,
  bvid: detail.bvid,
  cid: cid,
  title: 'Fast',
  author: 'UP',
  coverUrl: '',
  durationLabel: '',
  playCountLabel: '',
  danmakuCountLabel: '',
);
Map<String, Object?> dashData() => {
  'dash': {
    'duration': 60,
    'min_buffer_time': 1.5,
    'video': [stream(80, 'avc1.640028', video: true)],
    'audio': [stream(30280, 'mp4a.40.2')],
    'dolby': {
      'audio': [stream(30255, 'ec-3')],
    },
    'flac': {'audio': stream(30251, 'fLaC')},
  },
};
Map<String, Object?> stream(int id, String codec, {bool video = false}) => {
  'id': id,
  'base_url': 'https://example.test/$id.m4s',
  'codecs': codec,
  'bandwidth': 192000,
  'mime_type': video ? 'video/mp4' : 'audio/mp4',
  'width': video ? 1920 : null,
  'height': video ? 1080 : null,
  'SegmentBase': {'Initialization': '0-10', 'indexRange': '11-20'},
};
