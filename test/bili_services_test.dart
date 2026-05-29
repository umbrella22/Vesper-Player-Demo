import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/models/bili_region_models.dart';
import 'package:bilibili_player/bili/common/services/bili_api_core.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_dash_manifest_builder.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:bilibili_player/bili/common/services/bili_session_store.dart';
import 'package:bilibili_player/bili/common/services/bili_text.dart';
import 'package:bilibili_player/bili/common/services/bili_transport.dart';
import 'package:bilibili_player/bili/common/services/bili_wbi.dart';
import 'package:bilibili_player/danmaku/danmaku.dart';
import 'package:bilibili_player/download/download.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_player/vesper_player.dart';

Map<String, Object?> _dashStreamJson({
  required int id,
  required String baseUrl,
  required String codecs,
  required int bandwidth,
  String mimeType = 'video/mp4',
  List<String> backupUrls = const <String>[],
  int? codecid,
  int? size,
}) {
  return <String, Object?>{
    'id': id,
    'base_url': baseUrl,
    'backup_url': backupUrls,
    'mime_type': mimeType,
    'codecs': codecs,
    'bandwidth': bandwidth,
    'codecid': codecid,
    'size': size,
    'width': mimeType.startsWith('video/') ? 1920 : null,
    'height': mimeType.startsWith('video/') ? 1080 : null,
    'frame_rate': mimeType.startsWith('video/') ? '60' : null,
    'audio_sampling_rate': mimeType.startsWith('audio/') ? '48000' : null,
    'SegmentBase': <String, Object?>{
      'Initialization': '0-10',
      'indexRange': '11-20',
    },
  };
}

void main() {
  group('BiliWbiSigner', () {
    test('builds mixin key from img and sub keys', () {
      const signer = BiliWbiSigner();

      expect(
        signer.getMixinKey(
          '7cd084941338484aae1ad9425b84077c',
          '4932caff0ff746eab6f01bf08b70ac45',
        ),
        'ea1db124af3c7062474693fa704f4ff8',
      );
    });

    test('does not throw when WBI keys are shorter than expected', () {
      const signer = BiliWbiSigner();

      expect(signer.getMixinKey('a', 'b'), 'ab');
    });

    test('signs parameters using documented sample', () {
      const signer = BiliWbiSigner();

      final signed = signer.sign(
        params: <String, Object?>{'foo': '114', 'bar': '514', 'baz': 1919810},
        imgKey: '7cd084941338484aae1ad9425b84077c',
        subKey: '4932caff0ff746eab6f01bf08b70ac45',
        timestamp: 1702204169,
      );

      expect(signed['wts'], '1702204169');
      expect(signed['w_rid'], '6149fdadf571698ca7e6a567265cd0ee');
    });
  });

  group('BiliTransport API decoding', () {
    test('times out requests that never complete', () async {
      final transport = BiliTransport(
        httpClient: _NeverCompletingHttpClient(),
        requestTimeout: const Duration(milliseconds: 10),
      );

      expect(
        transport.sendRequest(
          Uri.https('api.bilibili.com', '/x/test'),
          referer: 'https://www.bilibili.com/',
        ),
        throwsA(
          isA<BiliApiException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('stores only trusted non-expired Bilibili cookies', () async {
      final httpClient = _CookieHttpClient();
      final transport = BiliTransport(httpClient: httpClient);

      httpClient.cookies = <Cookie>[
        Cookie('SESSDATA', 'trusted')
          ..domain = '.bilibili.com'
          ..path = '/',
        Cookie('scoped_out', 'ignored')
          ..domain = '.bilibili.com'
          ..path = '/passport',
      ];
      await transport.sendRequest(
        Uri.https('api.bilibili.com', '/x/test'),
        referer: 'https://www.bilibili.com/',
      );

      expect(transport.cookieValue('SESSDATA'), 'trusted');
      expect(transport.cookieValue('scoped_out'), isNull);

      httpClient.cookies = <Cookie>[
        Cookie('SESSDATA', 'media-overwrite')..domain = '.bilivideo.com',
      ];
      await transport.sendRequest(
        Uri.https('upos-sz-mirrorcoso1.bilivideo.com', '/video.m4s'),
        referer: 'https://www.bilibili.com/video/BV1xx411c7mD',
      );
      expect(transport.cookieValue('SESSDATA'), 'trusted');

      httpClient.cookies = <Cookie>[
        Cookie('SESSDATA', '')
          ..domain = '.bilibili.com'
          ..maxAge = 0,
      ];
      await transport.sendRequest(
        Uri.https('api.bilibili.com', '/x/test'),
        referer: 'https://www.bilibili.com/',
      );
      expect(transport.cookieValue('SESSDATA'), isNull);
    });

    test('can read unauthenticated nav data that still carries WBI keys', () {
      final transport = BiliTransport();
      addTearDown(() => transport.httpClient.close(force: true));
      final body = jsonEncode(<String, Object?>{
        'code': -101,
        'message': '账号未登录',
        'ttl': 1,
        'data': <String, Object?>{
          'isLogin': false,
          'wbi_img': <String, Object?>{
            'img_url':
                'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
            'sub_url':
                'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
          },
        },
      });

      final data = transport.decodeDataResponse(
        body,
        allowedCodes: const <int>{0, -101},
      );
      final wbiImg = Map<String, Object?>.from(data['wbi_img'] as Map);

      expect(data['isLogin'], isFalse);
      expect(wbiImg['img_url'], contains('7cd084941338484aae1ad9425b84077c'));
      expect(wbiImg['sub_url'], contains('4932caff0ff746eab6f01bf08b70ac45'));
    });

    test('rejects unauthenticated nav data unless the caller opts in', () {
      final transport = BiliTransport();
      addTearDown(() => transport.httpClient.close(force: true));
      final body = jsonEncode(<String, Object?>{
        'code': -101,
        'message': '账号未登录',
        'data': <String, Object?>{'isLogin': false},
      });

      expect(
        () => transport.decodeDataResponse(body),
        throwsA(
          isA<BiliApiException>()
              .having((error) => error.code, 'code', -101)
              .having((error) => error.message, 'message', '账号未登录'),
        ),
      );
    });

    test('surfaces captcha-required risk responses clearly', () {
      final transport = BiliTransport();
      addTearDown(() => transport.httpClient.close(force: true));
      final body = jsonEncode(<String, Object?>{
        'code': biliRiskControlCode,
        'message': '-352',
        'data': <String, Object?>{'v_voucher': 'voucher'},
      });

      expect(
        () => transport.decodeDataResponse(body),
        throwsA(
          isA<BiliApiException>()
              .having((error) => error.code, 'code', biliRiskControlCode)
              .having((error) => error.message, 'message', contains('验证码')),
        ),
      );
    });
  });

  group('BiliClient region videos', () {
    test('parses PGC season index payload after transport decoding', () async {
      final client = BiliClient(httpClient: _FakeRegionHttpClient());
      addTearDown(() => client.transport.httpClient.close(force: true));

      final videos = await client.fetchRegionVideos(
        const BiliRegionSection(
          id: 'bangumi',
          name: '番剧',
          icon: '',
          apiType: BiliRegionApiType.pgc,
          seasonType: 1,
        ),
      );

      expect(videos, hasLength(1));
      expect(videos.single.title, '测试番剧');
      expect(videos.single.seasonId, 12345);
      expect(videos.single.indexLabel, '更新至第 1 话');
      expect(videos.single.followCountLabel, '1.2万');
    });

    test('parses ranking payload after transport decoding', () async {
      final httpClient = _FakeRegionHttpClient();
      final client = BiliClient(httpClient: httpClient);
      addTearDown(() => client.transport.httpClient.close(force: true));

      final videos = await client.fetchRegionVideos(
        const BiliRegionSection(
          id: 'game',
          name: '游戏',
          icon: '',
          apiType: BiliRegionApiType.ranking,
          rid: 4,
        ),
      );

      expect(videos, hasLength(1));
      expect(videos.single.title, '测试排行榜视频');
      expect(videos.single.bvid, 'BV1xx411c7mD');
      expect(videos.single.cid, 22);
      expect(videos.single.indexLabel, '2:05');
      expect(httpClient.requestedUris.last.queryParameters['rid'], '4');
    });

    test('maps PGC season episodes into playback pages', () async {
      final client = BiliClient(httpClient: _FakeRegionHttpClient());
      addTearDown(() => client.transport.httpClient.close(force: true));

      final detail = await client.fetchPgcSeasonFirstEpisodeDetail(12345);

      expect(detail.title, '测试番剧');
      expect(detail.pages, hasLength(2));
      expect(detail.pages.first.bvid, 'BV1111111111');
      expect(detail.pages.first.aid, 101);
      expect(detail.pages.first.cid, 1001);
      expect(detail.pages.first.title, '第一话');
      expect(detail.pages.last.bvid, 'BV2222222222');
      expect(detail.pages.last.cid, 1002);
      expect(detail.pages.last.coverUrl, 'https://example.com/ep2.jpg');
    });

    test('refreshes browser cookies and retries ranking after risk', () async {
      final httpClient = _FakeRegionHttpClient(riskFirstRanking: true);
      final client = BiliClient(httpClient: httpClient);
      addTearDown(() => client.transport.httpClient.close(force: true));

      final videos = await client.fetchRegionVideos(
        const BiliRegionSection(
          id: 'game',
          name: '游戏',
          icon: '',
          apiType: BiliRegionApiType.ranking,
          rid: 4,
        ),
      );

      expect(videos, hasLength(1));
      expect(
        httpClient.requestedUris.where(
          (uri) => uri.path == '/x/web-interface/ranking/v2',
        ),
        hasLength(2),
      );
      expect(
        httpClient.requestedUris.where(
          (uri) => uri.path == '/x/frontend/finger/spi',
        ),
        hasLength(greaterThanOrEqualTo(2)),
      );
    });

    test(
      'parses video detail and search fields without throwing on type drift',
      () async {
        final httpClient = _TypeDriftHttpClient();
        final client = BiliClient(httpClient: httpClient)
          ..restoreCookies(const <String, String>{
            'buvid3': 'fake-buvid3',
            'buvid4': 'fake-buvid4',
          });
        addTearDown(() => client.transport.httpClient.close(force: true));

        final detail = await client.fetchVideoDetail('BV1xx411c7mD');
        final results = await client.searchVideos('typedrift');

        expect(detail.title, '12345');
        expect(detail.ownerName, '99');
        expect(detail.pages.single.title, '1');
        expect(results.single.title, '67890');
        expect(results.single.author, '42');
        expect(results.single.durationLabel, '02:05');
      },
    );
  });

  group('bili text helpers', () {
    test('extracts BV id from urls and raw text', () {
      expect(
        biliExtractBvid('https://www.bilibili.com/video/BV1xx411c7mD'),
        'BV1xx411c7mD',
      );
      expect(biliExtractBvid('BV1Q541167Qg'), 'BV1Q541167Qg');
      expect(biliExtractBvid('not-a-video'), isNull);
    });

    test('strips html tags and decodes basic entities', () {
      expect(biliStripHtmlTags('<em class="keyword">测试</em>&amp;播放'), '测试&播放');
    });

    test('decodes raw html entities', () {
      expect(biliDecodeHtmlEntities('&lt;弹幕&gt;&amp;Test'), '<弹幕>&Test');
    });
  });

  group('Bili media URL helpers', () {
    test('sorts non-PCDN URLs before PCDN URLs', () {
      expect(
        sortBiliMediaUrlCandidates(<String>[
          'https://pcdn.example.com:4483/video.m4s',
          'https://upos.example.com/video.m4s',
          'https://upos.example.com/video.m4s',
        ]),
        <String>[
          'https://upos.example.com/video.m4s',
          'https://pcdn.example.com:4483/video.m4s',
        ],
      );
    });

    test('adds fixed upos fallback when every candidate is PCDN', () {
      expect(
        sortBiliMediaUrlCandidates(<String>[
          'https://pcdn.example.com:4483/video.m4s?expires=1',
        ]),
        <String>[
          'https://upos-sz-mirrorcoso1.bilivideo.com/video.m4s?expires=1',
          'https://pcdn.example.com:4483/video.m4s?expires=1',
        ],
      );
    });
  });

  group('BiliDashManifestBuilder', () {
    test('builds a valid static mpd snippet', () {
      const builder = BiliDashManifestBuilder();
      const manifest = BiliDashManifestData(
        durationMs: 123456,
        minBufferTimeMs: 1500,
        videoStreams: <BiliDashStream>[
          BiliDashStream(
            id: 80,
            baseUrl: 'https://example.com/video.m4s',
            mimeType: 'video/mp4',
            codecs: 'avc1.640028',
            bandwidth: 1200000,
            segmentInfo: BiliDashSegmentInfo(
              initialization: '0-999',
              indexRange: '1000-1999',
            ),
            width: 1920,
            height: 1080,
            frameRate: '16000/672',
            startWithSap: 1,
          ),
        ],
        audioStreams: <BiliDashStream>[
          BiliDashStream(
            id: 30280,
            baseUrl: 'https://example.com/audio.m4s',
            mimeType: 'audio/mp4',
            codecs: 'mp4a.40.2',
            bandwidth: 192000,
            segmentInfo: BiliDashSegmentInfo(
              initialization: '0-888',
              indexRange: '889-1666',
            ),
            audioSamplingRate: '44100',
            startWithSap: 1,
          ),
        ],
      );

      final xml = builder.build(manifest);

      expect(xml, contains('mediaPresentationDuration="PT123.456S"'));
      expect(xml, contains('<AdaptationSet id="0" contentType="video"'));
      expect(xml, contains('<AdaptationSet id="1" contentType="audio"'));
      expect(xml, isNot(contains('<AdaptationSet id="video"')));
      expect(xml, contains('https://example.com/video.m4s'));
      expect(xml, contains('https://example.com/audio.m4s'));
    });

    test('uses explicit representation ids for duplicate qualities', () {
      const builder = BiliDashManifestBuilder();
      const manifest = BiliDashManifestData(
        durationMs: 1000,
        minBufferTimeMs: 1500,
        videoStreams: <BiliDashStream>[
          BiliDashStream(
            id: 80,
            representationId: 'video-80-7-1200000-0',
            baseUrl: 'https://example.com/video-avc.m4s',
            mimeType: 'video/mp4',
            codecs: 'avc1.640028',
            bandwidth: 1200000,
            segmentInfo: BiliDashSegmentInfo(
              initialization: '0-10',
              indexRange: '11-20',
            ),
          ),
          BiliDashStream(
            id: 80,
            representationId: 'video-80-12-1100000-1',
            baseUrl: 'https://example.com/video-hevc.m4s',
            mimeType: 'video/mp4',
            codecs: 'hev1.1.6.L120.90',
            bandwidth: 1100000,
            segmentInfo: BiliDashSegmentInfo(
              initialization: '0-10',
              indexRange: '11-20',
            ),
          ),
        ],
        audioStreams: <BiliDashStream>[
          BiliDashStream(
            id: 30280,
            baseUrl: 'https://example.com/audio.m4s',
            mimeType: 'audio/mp4',
            codecs: 'mp4a.40.2',
            bandwidth: 192000,
            segmentInfo: BiliDashSegmentInfo(
              initialization: '0-10',
              indexRange: '11-20',
            ),
          ),
        ],
      );

      final xml = builder.build(manifest);

      expect(xml, contains('id="video-80-7-1200000-0"'));
      expect(xml, contains('id="video-80-12-1100000-1"'));
    });

    test('writes backup BaseURL entries for player fallback', () {
      const builder = BiliDashManifestBuilder();
      const manifest = BiliDashManifestData(
        durationMs: 1000,
        minBufferTimeMs: 1500,
        videoStreams: <BiliDashStream>[
          BiliDashStream(
            id: 80,
            baseUrl: 'https://upos.example.com/video.m4s',
            backupUrls: <String>['https://pcdn.example.com:4483/video.m4s'],
            mimeType: 'video/mp4',
            codecs: 'avc1.640028',
            bandwidth: 1200000,
            segmentInfo: BiliDashSegmentInfo(
              initialization: '0-10',
              indexRange: '11-20',
            ),
          ),
        ],
        audioStreams: <BiliDashStream>[],
      );

      final xml = builder.build(manifest);

      expect(
        xml,
        contains('<BaseURL>https://upos.example.com/video.m4s</BaseURL>'),
      );
      expect(
        xml,
        contains('<BaseURL>https://pcdn.example.com:4483/video.m4s</BaseURL>'),
      );
    });
  });

  group('BiliClient DASH parser', () {
    test('accepts Bilibili SegmentBase Initialization fields', () {
      final client = BiliClient();

      final manifest = client.parseDashManifestForTesting(<String, Object?>{
        'support_formats': <Object?>[
          <String, Object?>{'quality': 80, 'new_description': '1080P 高清'},
        ],
        'dash': <String, Object?>{
          'duration': 12.34,
          'min_buffer_time': 1.5,
          'video': <Object?>[
            <String, Object?>{
              'id': 80,
              'base_url': 'https://example.com/video.m4s',
              'mime_type': 'video/mp4',
              'codecs': 'avc1.640028',
              'bandwidth': 1200000,
              'width': '1920',
              'height': 1080,
              'frame_rate': '30.000',
              'SegmentBase': <String, Object?>{
                'Initialization': '0-999',
                'indexRange': '1000-1999',
              },
            },
          ],
          'audio': <Object?>[],
          'dolby': <String, Object?>{
            'audio': <String, Object?>{
              'id': 30250,
              'baseUrl': 'https://example.com/audio.m4s',
              'mimeType': 'audio/mp4',
              'codecs': 'mp4a.40.2',
              'bandwidth': 192000,
              'audioSamplingRate': '48000',
              'SegmentBase': <String, Object?>{
                'Initialization': '0-888',
                'indexRange': '889-1666',
              },
            },
          },
        },
      });

      expect(manifest, isNotNull);
      expect(manifest!.durationMs, 12340);
      expect(manifest.videoStreams.single.qualityLabel, '1080P 高清');
      expect(manifest.videoStreams.single.segmentInfo.initialization, '0-999');
      expect(manifest.audioStreams.single.id, 30250);
      expect(manifest.audioStreams.single.segmentInfo.indexRange, '889-1666');
    });

    test('preserves dash protocol for generated local MPD sources', () {
      const resolved = BiliResolvedPlayback(
        bvid: 'BV1xx411c7mD',
        cid: 11,
        title: '测试视频',
        subtitle: 'P1',
        uri: 'file:///tmp/local.mpd',
        protocol: VesperPlayerSourceProtocol.dash,
        transportLabel: 'DASH',
        isLocalFile: true,
        headers: <String, String>{
          HttpHeaders.refererHeader:
              'https://www.bilibili.com/video/BV1xx411c7mD',
        },
      );

      final source = resolved.toSource();

      expect(source.kind, VesperPlayerSourceKind.local);
      expect(source.protocol, VesperPlayerSourceProtocol.dash);
      expect(
        source.headers[HttpHeaders.refererHeader],
        'https://www.bilibili.com/video/BV1xx411c7mD',
      );
    });

    test(
      'keeps Dolby Vision, duplicate codecs, Dolby audio, FLAC, and sizes',
      () {
        final client = BiliClient();

        final manifest = client.parseDashManifestForTesting(<String, Object?>{
          'support_formats': <Object?>[
            <String, Object?>{'quality': 126, 'new_description': '杜比视界'},
            <String, Object?>{'quality': 80, 'new_description': '1080P 高清'},
          ],
          'dash': <String, Object?>{
            'duration': 60,
            'video': <Object?>[
              _dashStreamJson(
                id: 126,
                baseUrl: 'https://example.com/dv-hevc.m4s',
                codecs: 'dvh1.05.06',
                codecid: 12,
                bandwidth: 4000000,
                size: 1000,
              ),
              _dashStreamJson(
                id: 126,
                baseUrl: 'https://example.com/dv-avc.m4s',
                codecs: 'avc1.640032',
                codecid: 7,
                bandwidth: 3000000,
                size: 900,
              ),
              _dashStreamJson(
                id: 80,
                baseUrl: 'https://example.com/1080.m4s',
                codecs: 'hev1.1.6.L120.90',
                codecid: 12,
                bandwidth: 2000000,
              ),
            ],
            'audio': <Object?>[
              _dashStreamJson(
                id: 30280,
                baseUrl: 'https://example.com/audio.m4s',
                mimeType: 'audio/mp4',
                codecs: 'mp4a.40.2',
                bandwidth: 192000,
                size: 111,
              ),
            ],
            'dolby': <String, Object?>{
              'audio': <Object?>[
                _dashStreamJson(
                  id: 30250,
                  baseUrl: 'https://example.com/dolby.m4s',
                  mimeType: 'audio/mp4',
                  codecs: 'ec-3',
                  bandwidth: 448000,
                  size: 222,
                ),
              ],
            },
            'flac': <String, Object?>{
              'audio': _dashStreamJson(
                id: 30251,
                baseUrl: 'https://example.com/flac.m4s',
                mimeType: 'audio/mp4',
                codecs: 'fLaC',
                bandwidth: 900000,
                size: 333,
              ),
            },
          },
        });

        expect(manifest, isNotNull);
        expect(
          manifest!.videoStreams.where((stream) => stream.id == 126),
          hasLength(2),
        );
        expect(manifest.videoStreams.first.qualityLabel, '杜比视界');
        expect(manifest.videoStreams.first.sizeBytes, 1000);
        expect(
          manifest.audioStreams.map((stream) => stream.id),
          containsAll(<int>[30280, 30250, 30251]),
        );
        expect(
          manifest.audioStreams
              .singleWhere((stream) => stream.id == 30251)
              .sizeBytes,
          333,
        );
      },
    );

    test('prefers backup DASH urls when primary media url is PCDN', () {
      final client = BiliClient();

      final manifest = client.parseDashManifestForTesting(<String, Object?>{
        'support_formats': <Object?>[
          <String, Object?>{'quality': 80, 'new_description': '1080P 高清'},
        ],
        'dash': <String, Object?>{
          'duration': 60,
          'video': <Object?>[
            _dashStreamJson(
              id: 80,
              baseUrl: 'https://pcdn.example.com:4483/video.m4s',
              backupUrls: <String>['https://upos.example.com/video.m4s'],
              codecs: 'avc1.640028',
              bandwidth: 1200000,
            ),
          ],
          'audio': <Object?>[
            _dashStreamJson(
              id: 30280,
              baseUrl: 'https://pcdn.example.com:4483/audio.m4s',
              backupUrls: <String>['https://upos.example.com/audio.m4s'],
              mimeType: 'audio/mp4',
              codecs: 'mp4a.40.2',
              bandwidth: 192000,
            ),
          ],
        },
      });

      expect(manifest, isNotNull);
      expect(
        manifest!.videoStreams.single.baseUrl,
        'https://upos.example.com/video.m4s',
      );
      expect(
        manifest.videoStreams.single.backupUrls,
        contains('https://pcdn.example.com:4483/video.m4s'),
      );
    });

    test('rewrites all-PCDN DASH candidates to a fixed upos fallback', () {
      final client = BiliClient();

      final manifest = client.parseDashManifestForTesting(<String, Object?>{
        'dash': <String, Object?>{
          'duration': 60,
          'video': <Object?>[
            _dashStreamJson(
              id: 80,
              baseUrl: 'https://pcdn.example.com:4483/video.m4s?token=1',
              codecs: 'avc1.640028',
              bandwidth: 1200000,
            ),
          ],
          'audio': <Object?>[
            _dashStreamJson(
              id: 30280,
              baseUrl: 'https://pcdn.example.com:4483/audio.m4s?token=1',
              mimeType: 'audio/mp4',
              codecs: 'mp4a.40.2',
              bandwidth: 192000,
            ),
          ],
        },
      });

      expect(manifest, isNotNull);
      expect(
        manifest!.videoStreams.single.baseUrl,
        'https://upos-sz-mirrorcoso1.bilivideo.com/video.m4s?token=1',
      );
      expect(
        manifest.videoStreams.single.backupUrls,
        contains('https://pcdn.example.com:4483/video.m4s?token=1'),
      );
    });

    test(
      'verified DASH download picks the first reachable media url',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) {
            if (request.uri.path.contains('bad')) {
              request.response.statusCode = HttpStatus.forbidden;
              unawaited(request.response.close());
              return;
            }
            request.response
              ..statusCode = HttpStatus.partialContent
              ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-0/1234')
              ..headers.contentLength = 1
              ..add(<int>[0]);
            unawaited(request.response.close());
          }),
        );
        final origin = 'http://${server.address.host}:${server.port}';
        final client = BiliClient();
        final video = BiliDashStream(
          id: 80,
          baseUrl: '$origin/bad-video.m4s',
          backupUrls: <String>['$origin/good-video.m4s'],
          mimeType: 'video/mp4',
          codecs: 'avc1.640028',
          bandwidth: 1200000,
          representationId: 'video-80-7-1200000-0',
          segmentInfo: const BiliDashSegmentInfo(
            initialization: '0-10',
            indexRange: '11-20',
          ),
        );
        final audio = BiliDashStream(
          id: 30280,
          baseUrl: '$origin/good-audio.m4s',
          mimeType: 'audio/mp4',
          codecs: 'mp4a.40.2',
          bandwidth: 192000,
          representationId: 'audio-30280-mp4a402-192000-0',
          segmentInfo: const BiliDashSegmentInfo(
            initialization: '0-10',
            indexRange: '11-20',
          ),
        );
        final options = BiliDownloadOptions(
          bvid: 'BV1xx411c7mD',
          cid: 11,
          videoTitle: '测试视频',
          pageTitle: 'P1 · 正片',
          coverUrl: '',
          referer: 'https://www.bilibili.com/video/BV1xx411c7mD',
          headers: const <String, String>{
            HttpHeaders.refererHeader: 'https://www.bilibili.com',
          },
          manifest: BiliDashManifestData(
            durationMs: 1000,
            minBufferTimeMs: 1500,
            videoStreams: <BiliDashStream>[video],
            audioStreams: <BiliDashStream>[audio],
          ),
          qualities: <BiliDownloadQualityOption>[
            BiliDownloadQualityOption(
              qualityId: 80,
              label: '1080P 高清',
              videoStreams: <BiliDashStream>[video],
            ),
          ],
          variantLabel: 'test',
        );

        final prepared = await client.prepareVerifiedDownloadAsset(
          options: options,
          qualityId: 80,
        );

        expect(prepared.selectedVideo.baseUrl, '$origin/good-video.m4s');
        expect(prepared.selectedVideo.sizeBytes, 1234);
        expect(prepared.selectedAudio.sizeBytes, 1234);
        expect(prepared.assetIndex.totalSizeBytes, 2468);
        final videoResource = prepared.assetIndex.resources.singleWhere(
          (resource) => resource.resourceId.startsWith('dash-video-'),
        );
        final audioResource = prepared.assetIndex.resources.singleWhere(
          (resource) => resource.resourceId.startsWith('dash-audio-'),
        );
        expect(videoResource.byteRange, isNull);
        expect(audioResource.byteRange, isNull);
        expect(videoResource.sizeBytes, 1234);
        expect(audioResource.sizeBytes, 1234);
      },
    );

    test(
      'iOS verified DASH download keeps generated manifest for SDK target write',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
        });
        final targetDirectory = await Directory.systemTemp.createTemp(
          'bili-offline-cache-test-',
        );
        addTearDown(() => targetDirectory.delete(recursive: true));
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        unawaited(
          server.forEach((request) {
            request.response
              ..statusCode = HttpStatus.partialContent
              ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-0/1234')
              ..headers.contentLength = 1
              ..add(<int>[0]);
            unawaited(request.response.close());
          }),
        );
        final origin = 'http://${server.address.host}:${server.port}';
        final client = BiliClient();
        final video = BiliDashStream(
          id: 80,
          baseUrl: '$origin/video.m4s',
          mimeType: 'video/mp4',
          codecs: 'avc1.640028',
          bandwidth: 1200000,
          representationId: 'video-80-7-1200000-0',
          segmentInfo: const BiliDashSegmentInfo(
            initialization: '0-10',
            indexRange: '11-20',
          ),
        );
        final audio = BiliDashStream(
          id: 30280,
          baseUrl: '$origin/audio.m4s',
          mimeType: 'audio/mp4',
          codecs: 'mp4a.40.2',
          bandwidth: 192000,
          representationId: 'audio-30280-mp4a402-192000-0',
          segmentInfo: const BiliDashSegmentInfo(
            initialization: '0-10',
            indexRange: '11-20',
          ),
        );
        final options = BiliDownloadOptions(
          bvid: 'BV1xx411c7mD',
          cid: 11,
          videoTitle: '测试视频',
          pageTitle: 'P1 · 正片',
          coverUrl: '',
          referer: 'https://www.bilibili.com/video/BV1xx411c7mD',
          headers: const <String, String>{
            HttpHeaders.refererHeader: 'https://www.bilibili.com',
          },
          manifest: BiliDashManifestData(
            durationMs: 1000,
            minBufferTimeMs: 1500,
            videoStreams: <BiliDashStream>[video],
            audioStreams: <BiliDashStream>[audio],
          ),
          qualities: <BiliDownloadQualityOption>[
            BiliDownloadQualityOption(
              qualityId: 80,
              label: '1080P 高清',
              videoStreams: <BiliDashStream>[video],
            ),
          ],
          variantLabel: 'test',
        );

        final prepared = await client.prepareVerifiedDownloadAsset(
          options: options,
          qualityId: 80,
          targetDirectory: targetDirectory.path,
        );

        final manifestResource = prepared.assetIndex.resources.singleWhere(
          (resource) => resource.resourceId == 'dash-manifest',
        );
        expect(manifestResource.uri, 'vesper-generated://dash/manifest.mpd');
        expect(
          manifestResource.relativePath,
          '${targetDirectory.path}/manifest.mpd',
        );
        expect(manifestResource.sizeBytes, isNull);
        final manifestText = manifestResource.generatedText;
        expect(manifestText, isNotNull);
        expect(manifestText, contains('media/video-q80-avc.m4s'));
        expect(manifestText, contains('media/audio-30280-audio30280.m4s'));
        expect(prepared.assetIndex.totalSizeBytes, 2468);
      },
    );

    test('builds prepared DASH download asset with MP4 target output', () {
      final client = BiliClient();
      const videoHevc = BiliDashStream(
        id: 126,
        baseUrl: 'https://example.com/dv-hevc.m4s',
        mimeType: 'video/mp4',
        codecs: 'dvh1.05.06',
        bandwidth: 4000000,
        codecid: 12,
        representationId: 'video-126-12-4000000-0',
        qualityLabel: '杜比视界',
        sizeBytes: 1000,
        segmentInfo: BiliDashSegmentInfo(
          initialization: '0-10',
          indexRange: '11-20',
        ),
      );
      const videoAvc = BiliDashStream(
        id: 126,
        baseUrl: 'https://example.com/dv-avc.m4s',
        mimeType: 'video/mp4',
        codecs: 'avc1.640032',
        bandwidth: 3000000,
        codecid: 7,
        representationId: 'video-126-7-3000000-1',
        qualityLabel: '杜比视界',
        sizeBytes: 900,
        segmentInfo: BiliDashSegmentInfo(
          initialization: '0-10',
          indexRange: '11-20',
        ),
      );
      const normalAudio = BiliDashStream(
        id: 30280,
        baseUrl: 'https://example.com/audio.m4s',
        mimeType: 'audio/mp4',
        codecs: 'mp4a.40.2',
        bandwidth: 192000,
        representationId: 'audio-30280-mp4a402-192000-0',
        sizeBytes: 111,
        segmentInfo: BiliDashSegmentInfo(
          initialization: '0-10',
          indexRange: '11-20',
        ),
      );
      const flacAudio = BiliDashStream(
        id: 30251,
        baseUrl: 'https://example.com/flac.m4s',
        mimeType: 'audio/mp4',
        codecs: 'fLaC',
        bandwidth: 900000,
        representationId: 'audio-30251-fLaC-900000-1',
        sizeBytes: 333,
        segmentInfo: BiliDashSegmentInfo(
          initialization: '0-10',
          indexRange: '11-20',
        ),
      );
      const options = BiliDownloadOptions(
        bvid: 'BV1xx411c7mD',
        cid: 11,
        videoTitle: '测试视频',
        pageTitle: 'P1 · 正片',
        coverUrl: '',
        referer: 'https://www.bilibili.com/video/BV1xx411c7mD',
        headers: <String, String>{'Referer': 'https://www.bilibili.com/'},
        manifest: BiliDashManifestData(
          durationMs: 1000,
          minBufferTimeMs: 1500,
          videoStreams: <BiliDashStream>[videoHevc, videoAvc],
          audioStreams: <BiliDashStream>[normalAudio, flacAudio],
        ),
        qualities: <BiliDownloadQualityOption>[
          BiliDownloadQualityOption(
            qualityId: 126,
            label: '杜比视界',
            videoStreams: <BiliDashStream>[videoHevc, videoAvc],
          ),
        ],
        variantLabel: 'web fnval=4048',
      );

      final prepared = client.prepareDownloadAsset(
        options: options,
        qualityId: 126,
        codecPreference: BiliVideoCodecPreference.hevc,
        targetDirectory: '/tmp/offline-cache',
      );

      expect(prepared.assetId, contains('q126-hevc-flac'));
      expect(prepared.selectedVideo, same(videoHevc));
      expect(prepared.selectedAudio, same(flacAudio));
      expect(
        prepared.profile.targetOutputFormat,
        VesperDownloadOutputFormat.mp4,
      );
      expect(prepared.profile.targetDirectory, '/tmp/offline-cache');
      expect(
        prepared.assetIndex.contentFormat,
        VesperDownloadContentFormat.dashSegments,
      );
      expect(prepared.assetIndex.resources, hasLength(3));
      expect(
        prepared.assetIndex.resources.first.generatedText,
        contains('media/video-q126-hevc.m4s'),
      );
      expect(
        prepared.assetIndex.resources.first.generatedText,
        contains('media/audio-30251-flac.m4s'),
      );
      final videoResource = prepared.assetIndex.resources.singleWhere(
        (resource) =>
            resource.resourceId == 'dash-video-video-126-12-4000000-0',
      );
      final audioResource = prepared.assetIndex.resources.singleWhere(
        (resource) =>
            resource.resourceId == 'dash-audio-audio-30251-fLaC-900000-1',
      );
      expect(videoResource.byteRange, isNull);
      expect(audioResource.byteRange, isNull);
      expect(videoResource.sizeBytes, 1000);
      expect(audioResource.sizeBytes, 333);
      expect(prepared.assetIndex.totalSizeBytes, 1333);
    });
  });

  group('Bili login cookies', () {
    test(
      'extracts QR login cookies from callback urls without decoding values',
      () {
        final cookies = parseBiliLoginCookiesFromUrl(
          'https://passport.bilibili.com/login/sso?'
          'DedeUserID=123&SESSDATA=abc%2Cdef%2Aghi&'
          'bili_jct=csrf-token&gourl=https%3A%2F%2Fwww.bilibili.com',
        );

        expect(cookies['DedeUserID'], '123');
        expect(cookies['SESSDATA'], 'abc%2Cdef%2Aghi');
        expect(cookies['bili_jct'], 'csrf-token');
        expect(cookies.containsKey('gourl'), isFalse);
      },
    );
  });

  group('BiliVideoEngagement', () {
    test('copies mutable action state without losing favorite target', () {
      const engagement = BiliVideoEngagement(
        isAuthenticated: true,
        isLiked: false,
        isFavorited: false,
        isFollowingOwner: false,
        favoriteMediaIds: <int>[],
        defaultFavoriteMediaId: 123,
      );

      final updated = engagement.copyWith(isLiked: true, isFavorited: true);

      expect(updated.isLiked, isTrue);
      expect(updated.isFavorited, isTrue);
      expect(updated.defaultFavoriteMediaId, 123);
    });

    test('queries favorite folders with the current user mid', () async {
      final httpClient = _FakeEngagementHttpClient();
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(_authenticatedCookies());
      addTearDown(() => client.transport.httpClient.close(force: true));

      await client.fetchVideoEngagement(_engagementDetail);

      final folderRequest = httpClient.requestedUris.lastWhere(
        (uri) => uri.path == '/x/v3/fav/folder/created/list-all',
      );
      expect(folderRequest.queryParameters['up_mid'], '42');
      expect(folderRequest.queryParameters['rid'], '${_engagementDetail.aid}');
    });

    test('sends expected like, favorite, and follow mutations', () async {
      final httpClient = _FakeEngagementHttpClient();
      final client = BiliClient(httpClient: httpClient)
        ..restoreCookies(_authenticatedCookies());
      addTearDown(() => client.transport.httpClient.close(force: true));

      const current = BiliVideoEngagement(
        isAuthenticated: true,
        isLiked: false,
        isFavorited: false,
        isFollowingOwner: false,
        favoriteMediaIds: <int>[],
        defaultFavoriteMediaId: 99,
      );

      await client.setVideoLike(
        detail: _engagementDetail,
        liked: true,
        current: current,
      );
      await client.setVideoFavorite(
        detail: _engagementDetail,
        favorited: true,
        current: current,
      );
      await client.setOwnerFollow(
        detail: _engagementDetail,
        following: true,
        current: current,
      );

      final likePost = httpClient.posts.singleWhere(
        (post) => post.uri.path == '/x/web-interface/archive/like',
      );
      expect(likePost.fields['aid'], '${_engagementDetail.aid}');
      expect(likePost.fields['bvid'], _engagementDetail.bvid);
      expect(likePost.fields['like'], '1');
      expect(likePost.fields['csrf'], 'csrf-token');

      final favoritePost = httpClient.posts.singleWhere(
        (post) => post.uri.path == '/x/v3/fav/resource/deal',
      );
      expect(favoritePost.fields['rid'], '${_engagementDetail.aid}');
      expect(favoritePost.fields['type'], '$biliVideoFavoriteType');
      expect(favoritePost.fields['add_media_ids'], '99');
      expect(favoritePost.fields['del_media_ids'], '');

      final followPost = httpClient.posts.singleWhere(
        (post) => post.uri.path == '/x/relation/modify',
      );
      expect(followPost.fields['fid'], '${_engagementDetail.ownerMid}');
      expect(followPost.fields['act'], '1');
      expect(followPost.fields['re_src'], '14');
    });
  });

  group('BiliHistoryStore', () {
    test('persists and deduplicates history entries', () async {
      final root = await Directory.systemTemp.createTemp('bili-history-test-');
      addTearDown(() => root.delete(recursive: true));

      final store = BiliHistoryStore(baseDirectory: root);
      await store.saveEntry(
        const BiliPlaybackHistoryEntry(
          bvid: 'BV1xx411c7mD',
          cid: 11,
          videoTitle: 'First',
          pageTitle: 'P1',
          coverUrl: '',
          ownerName: 'UP',
          playedAtMs: 100,
          lastPositionMs: 1000,
          durationMs: 2000,
        ),
      );
      await store.saveEntry(
        const BiliPlaybackHistoryEntry(
          bvid: 'BV1xx411c7mD',
          cid: 11,
          videoTitle: 'First',
          pageTitle: 'P1',
          coverUrl: '',
          ownerName: 'UP',
          playedAtMs: 200,
          lastPositionMs: 1500,
          durationMs: 2000,
        ),
      );

      final entries = await store.loadEntries();
      expect(entries, hasLength(1));
      expect(entries.first.playedAtMs, 200);
      expect(entries.first.lastPositionMs, 1500);
    });

    test('serializes concurrent history writes', () async {
      final root = await Directory.systemTemp.createTemp('bili-history-race-');
      addTearDown(() => root.delete(recursive: true));

      final store = BiliHistoryStore(baseDirectory: root);
      await Future.wait(<Future<void>>[
        store.saveEntry(
          const BiliPlaybackHistoryEntry(
            bvid: 'BV1',
            cid: 1,
            videoTitle: 'First',
            pageTitle: 'P1',
            coverUrl: '',
            ownerName: 'UP',
            playedAtMs: 100,
            lastPositionMs: 1000,
            durationMs: 2000,
          ),
        ),
        store.saveEntry(
          const BiliPlaybackHistoryEntry(
            bvid: 'BV2',
            cid: 2,
            videoTitle: 'Second',
            pageTitle: 'P1',
            coverUrl: '',
            ownerName: 'UP',
            playedAtMs: 200,
            lastPositionMs: 3000,
            durationMs: 4000,
          ),
        ),
      ]);

      final entries = await store.loadEntries();

      expect(entries.map((entry) => entry.bvid), <String>['BV2', 'BV1']);
    });

    test('migrates history from the legacy temp directory', () async {
      final root = await Directory.systemTemp.createTemp('bili-history-new-');
      final legacy = await Directory.systemTemp.createTemp(
        'bili-history-legacy-',
      );
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => legacy.delete(recursive: true));

      final legacyFile = File('${legacy.path}/bili-playback-history.json');
      await legacyFile.create(recursive: true);
      await legacyFile.writeAsString('''
[
  {
    "bvid": "BV1xx411c7mD",
    "cid": 11,
    "videoTitle": "Legacy",
    "pageTitle": "P1",
    "coverUrl": "",
    "ownerName": "UP",
    "playedAtMs": 321,
    "lastPositionMs": 654,
    "durationMs": 987
  }
]
''');

      final store = BiliHistoryStore(
        baseDirectory: root,
        legacyDirectory: legacy,
      );
      final entries = await store.loadEntries();

      expect(entries, hasLength(1));
      expect(entries.first.videoTitle, 'Legacy');
      expect(
        File('${root.path}/bili-playback-history.json').existsSync(),
        isTrue,
      );
    });
  });

  group('BiliOfflineDownloadStore', () {
    test('persists and deduplicates metadata entries', () async {
      final root = await Directory.systemTemp.createTemp('bili-offline-test-');
      addTearDown(() => root.delete(recursive: true));

      final store = BiliOfflineDownloadStore(baseDirectory: root);
      await store.saveEntries(<BiliOfflineDownloadMetadata>[
        const BiliOfflineDownloadMetadata(
          assetId: 'asset-1',
          bvid: 'BV1',
          cid: 1,
          videoTitle: 'Old',
          pageTitle: 'P1',
          coverUrl: '',
          qualityLabel: '1080P',
          createdAtMs: 100,
        ),
        const BiliOfflineDownloadMetadata(
          assetId: 'asset-1',
          taskId: 7,
          bvid: 'BV1',
          cid: 1,
          videoTitle: 'New',
          pageTitle: 'P1',
          coverUrl: '',
          qualityLabel: '1080P',
          createdAtMs: 200,
        ),
      ]);

      final entries = await store.loadEntries();

      expect(entries, hasLength(1));
      expect(entries.single.videoTitle, 'New');
      expect(entries.single.taskId, 7);
    });

    test('quarantines corrupt metadata instead of throwing', () async {
      final root = await Directory.systemTemp.createTemp('bili-offline-test-');
      addTearDown(() => root.delete(recursive: true));

      final file = File('${root.path}/bili-offline-cache.json');
      await file.writeAsString('{"version":1,"entries":[]}stale 403');

      final store = BiliOfflineDownloadStore(baseDirectory: root);
      final entries = await store.loadEntries();

      expect(entries, isEmpty);
      expect(file.existsSync(), isFalse);
      expect(
        root.listSync().whereType<File>().where(
          (value) => value.path.contains('.corrupt-'),
        ),
        isNotEmpty,
      );
    });
  });

  group('BiliSessionStore', () {
    test('migrates cookies from the legacy temp directory', () async {
      final root = await Directory.systemTemp.createTemp('bili-session-new-');
      final legacy = await Directory.systemTemp.createTemp(
        'bili-session-legacy-',
      );
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => legacy.delete(recursive: true));

      final legacyFile = File('${legacy.path}/bili-session.json');
      await legacyFile.create(recursive: true);
      await legacyFile.writeAsString(
        '{"savedAtMs":123,"cookies":{"SESSDATA":"abc","bili_jct":"token"}}',
      );

      final store = BiliSessionStore(
        baseDirectory: root,
        legacyDirectory: legacy,
      );
      final cookies = await store.loadCookies();

      expect(cookies['SESSDATA'], 'abc');
      expect(cookies['bili_jct'], 'token');
      expect(File('${root.path}/bili-session.json').existsSync(), isTrue);
    });

    test(
      'migrates plaintext cookies into secure storage and removes files',
      () async {
        final root = await Directory.systemTemp.createTemp('bili-session-new-');
        final legacy = await Directory.systemTemp.createTemp(
          'bili-session-legacy-',
        );
        final secureStorage = _FakeSessionSecureStorage();
        addTearDown(() => root.delete(recursive: true));
        addTearDown(() => legacy.delete(recursive: true));

        final legacyFile = File('${legacy.path}/bili-session.json');
        await legacyFile.create(recursive: true);
        await legacyFile.writeAsString(
          '{"savedAtMs":123,"cookies":{"SESSDATA":"abc","bili_jct":"token"}}',
        );

        final store = BiliSessionStore(
          baseDirectory: root,
          legacyDirectory: legacy,
          secureStorage: secureStorage,
        );
        final cookies = await store.loadCookies();

        expect(cookies['SESSDATA'], 'abc');
        expect(cookies['bili_jct'], 'token');
        expect(secureStorage.values, hasLength(1));
        expect(File('${root.path}/bili-session.json').existsSync(), isFalse);
        expect(legacyFile.existsSync(), isFalse);
      },
    );
  });

  group('BiliFeedVideo parser', () {
    test('parses map-shaped recommendation reasons', () {
      final video = parseBiliFeedVideo(<String, Object?>{
        'id': 42,
        'bvid': 'BV1Q541167Qg',
        'title': '<em>测试</em>视频',
        'owner': <String, Object?>{'name': 'UP 主'},
        'cover': 'https://i0.hdslb.com/example.jpg',
        'duration': 378,
        'stat': <String, Object?>{'view': 12000, 'danmaku': 345},
        'rcmd_reason': <String, Object?>{'content': '已关注的合集更新'},
        'pubdate': 1710000000,
      });

      expect(video, isNotNull);
      expect(video!.title, '测试视频');
      expect(video.author, 'UP 主');
      expect(video.description, '已关注的合集更新');
      expect(video.durationLabel, '06:18');
      expect(video.publishedAtLabel, isNotNull);
    });
  });

  group('BiliDanmakuParser', () {
    test('parses supported and unsupported danmaku entries from xml', () {
      const parser = BiliDanmakuParser();
      final entries = parser.parse('''
<?xml version="1.0" encoding="UTF-8"?>
<i>
  <d p="1.5,1,25,16777215,0,0,hash,11,0">第一条</d>
  <d p="2.0,5,30,16711680,0,0,hash,12,0">&lt;顶部&gt;</d>
  <d p="3.0,7,25,65280,0,0,hash,13,0">高级</d>
</i>
''');

      expect(entries, hasLength(3));
      expect(entries.first.appearAtMs, 1500);
      expect(entries.first.mode, BiliDanmakuMode.scroll);
      expect(entries[1].mode, BiliDanmakuMode.top);
      expect(entries[1].text, '<顶部>');
      expect(entries[2].mode, BiliDanmakuMode.unsupported);
    });
  });

  group('BiliQrLoginStatus', () {
    test('maps bilibili web qr codes to local status enum', () {
      expect(
        BiliQrLoginStatus.fromCode(86101),
        BiliQrLoginStatus.waitingForScan,
      );
      expect(
        BiliQrLoginStatus.fromCode(86090),
        BiliQrLoginStatus.scannedAwaitingConfirm,
      );
      expect(BiliQrLoginStatus.fromCode(0), BiliQrLoginStatus.confirmed);
      expect(BiliQrLoginStatus.fromCode(86038), BiliQrLoginStatus.expired);
      expect(BiliQrLoginStatus.fromCode(-1), BiliQrLoginStatus.failed);
    });
  });
}

const _engagementDetail = BiliVideoDetail(
  aid: 100,
  bvid: 'BV1xx411c7mD',
  title: '互动测试视频',
  ownerMid: 200,
  ownerName: '测试UP',
  ownerAvatarUrl: '',
  coverUrl: '',
  description: '',
  publishedAtLabel: null,
  playCountLabel: '1',
  danmakuCountLabel: '2',
  replyCountLabel: '3',
  likeCountLabel: '4',
  coinCountLabel: '5',
  favoriteCountLabel: '6',
  shareCountLabel: '7',
  pages: <BiliVideoPageEntry>[
    BiliVideoPageEntry(
      cid: 11,
      pageNumber: 1,
      title: '正片',
      durationSeconds: 60,
    ),
  ],
);

Map<String, String> _authenticatedCookies() {
  return const <String, String>{
    'SESSDATA': 'session',
    'bili_jct': 'csrf-token',
    'DedeUserID': '42',
    'buvid3': 'fake-buvid3',
    'buvid4': 'fake-buvid4',
  };
}

final class _RecordedPost {
  const _RecordedPost({required this.uri, required this.fields});

  final Uri uri;
  final Map<String, String> fields;
}

final class _FakeEngagementHttpClient implements HttpClient {
  final List<Uri> requestedUris = <Uri>[];
  final List<_RecordedPost> posts = <_RecordedPost>[];
  String? _userAgent;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) {
    _userAgent = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUris.add(url);
    return _FakeEngagementHttpClientRequest(
      response: _responseFor(url),
      onClose: (_) {},
    );
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    requestedUris.add(url);
    return _FakeEngagementHttpClientRequest(
      response: _FakeEngagementHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{},
        }),
      ),
      onClose: (body) {
        posts.add(_RecordedPost(uri: url, fields: Uri.splitQueryString(body)));
      },
    );
  }

  _FakeEngagementHttpClientResponse _responseFor(Uri url) {
    if (url.host == 'www.bilibili.com') {
      return _FakeEngagementHttpClientResponse('<html></html>');
    }

    if (url.path == '/x/frontend/finger/spi') {
      return _FakeEngagementHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{'b_3': 'fake-buvid3', 'b_4': 'fake-buvid4'},
        }),
      );
    }

    if (url.path == '/x/web-interface/nav') {
      return _FakeEngagementHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{
            'isLogin': true,
            'mid': 42,
            'uname': '当前用户',
            'face': '',
            'wbi_img': <String, Object?>{
              'img_url':
                  'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
              'sub_url':
                  'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
            },
          },
        }),
      );
    }

    if (url.path == '/x/web-interface/nav/stat') {
      return _FakeEngagementHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{},
        }),
      );
    }

    if (url.path == '/x/web-interface/archive/relation') {
      return _FakeEngagementHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{
            'like': false,
            'favorite': false,
            'attention': false,
          },
        }),
      );
    }

    if (url.path == '/x/v3/fav/folder/created/list-all') {
      return _FakeEngagementHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{
            'list': <Object?>[
              <String, Object?>{'id': 99, 'title': '默认收藏夹', 'fav_state': 0},
            ],
          },
        }),
      );
    }

    return _FakeEngagementHttpClientResponse(
      jsonEncode(<String, Object?>{
        'code': -404,
        'message': 'unexpected fake route: ${url.path}',
      }),
      statusCode: HttpStatus.notFound,
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSessionSecureStorage implements BiliSessionSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

final class _NeverCompletingHttpClient implements HttpClient {
  String? _userAgent;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) {
    _userAgent = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _NeverCompletingHttpClientRequest();
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NeverCompletingHttpClientRequest implements HttpClientRequest {
  final _FakeRegionHttpHeaders _headers = _FakeRegionHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() {
    return Completer<HttpClientResponse>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CookieHttpClient implements HttpClient {
  List<Cookie> cookies = const <Cookie>[];
  String? _userAgent;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) {
    _userAgent = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _CookieHttpClientRequest(_CookieHttpClientResponse(cookies));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CookieHttpClientRequest implements HttpClientRequest {
  _CookieHttpClientRequest(this._response);

  final _CookieHttpClientResponse _response;
  final _FakeRegionHttpHeaders _headers = _FakeRegionHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CookieHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  const _CookieHttpClientResponse(this.cookies);

  @override
  final List<Cookie> cookies;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  HttpHeaders get headers => _FakeRegionHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[
      utf8.encode('{}'),
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

final class _TypeDriftHttpClient implements HttpClient {
  String? _userAgent;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) {
    _userAgent = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeRegionHttpClientRequest(_responseFor(url));
  }

  _FakeRegionHttpClientResponse _responseFor(Uri url) {
    if (url.path == '/x/web-interface/nav') {
      return _FakeRegionHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{
            'isLogin': false,
            'wbi_img': <String, Object?>{
              'img_url':
                  'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
              'sub_url':
                  'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
            },
          },
        }),
      );
    }

    if (url.path == '/x/web-interface/view') {
      return _FakeRegionHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{
            'aid': '100',
            'bvid': 'BV1xx411c7mD',
            'title': 12345,
            'pic': 777,
            'desc': 888,
            'owner': <String, Object?>{'mid': '42', 'name': 99, 'face': 100},
            'stat': <String, Object?>{
              'view': '1000',
              'danmaku': '20',
              'reply': '3',
              'like': '4',
              'coin': '5',
              'favorite': '6',
              'share': '7',
            },
            'pages': <Object?>[
              <String, Object?>{
                'cid': '200',
                'page': '1',
                'part': 1,
                'duration': '125',
              },
            ],
          },
        }),
      );
    }

    if (url.path == '/x/web-interface/wbi/search/type') {
      return _FakeRegionHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{
            'result': <Object?>[
              <String, Object?>{
                'aid': '300',
                'bvid': 'BV2xx411c7mD',
                'title': 67890,
                'author': 42,
                'pic': 9,
                'duration': 125,
                'play': '1000',
                'video_review': '3',
                'description': 10,
                'pubdate': '1719057600',
              },
            ],
          },
        }),
      );
    }

    return _FakeRegionHttpClientResponse(
      jsonEncode(<String, Object?>{
        'code': -404,
        'message': 'unexpected fake route: ${url.path}',
      }),
      statusCode: HttpStatus.notFound,
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeEngagementHttpClientRequest implements HttpClientRequest {
  _FakeEngagementHttpClientRequest({
    required this.response,
    required this.onClose,
  });

  final _FakeEngagementHttpClientResponse response;
  final void Function(String body) onClose;
  final List<int> _body = <int>[];
  final _FakeRegionHttpHeaders _headers = _FakeRegionHttpHeaders();
  int _contentLength = -1;

  @override
  HttpHeaders get headers => _headers;

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) {
    _contentLength = value;
  }

  @override
  void add(List<int> data) {
    _body.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() async {
    onClose(utf8.decode(_body));
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeEngagementHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeEngagementHttpClientResponse(
    this.body, {
    this.statusCode = HttpStatus.ok,
  });

  final String body;

  @override
  final int statusCode;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  HttpHeaders get headers => _FakeRegionHttpHeaders();

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

final class _FakeRegionHttpClient implements HttpClient {
  _FakeRegionHttpClient({this.riskFirstRanking = false});

  final bool riskFirstRanking;
  final List<Uri> requestedUris = <Uri>[];
  String? _userAgent;
  bool _sentRankingRisk = false;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) {
    _userAgent = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUris.add(url);
    return _FakeRegionHttpClientRequest(_responseFor(url));
  }

  @override
  void close({bool force = false}) {}

  _FakeRegionHttpClientResponse _responseFor(Uri url) {
    if (url.host == 'www.bilibili.com') {
      return _FakeRegionHttpClientResponse('<html></html>');
    }

    if (url.path == '/x/frontend/finger/spi') {
      return _FakeRegionHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{'b_3': 'fake-buvid3', 'b_4': 'fake-buvid4'},
        }),
      );
    }

    if (url.path == '/x/web-interface/nav') {
      return _FakeRegionHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{
            'isLogin': false,
            'wbi_img': <String, Object?>{
              'img_url':
                  'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
              'sub_url':
                  'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
            },
          },
        }),
      );
    }

    if (url.path == '/pgc/season/index/result') {
      return _FakeRegionHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': 'success',
          'data': <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'season_id': 12345,
                'title': '测试番剧',
                'cover': 'https://example.com/cover.jpg',
                'link': 'https://www.bilibili.com/bangumi/play/ss12345',
                'new_ep': <String, Object?>{'index_show': '更新至第 1 话'},
                'stat': <String, Object?>{'follow': 12345},
                'evaluate': '简介',
              },
            ],
          },
        }),
      );
    }

    if (url.path == '/pgc/view/web/season') {
      return _FakeRegionHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': 'success',
          'result': <String, Object?>{
            'title': '测试番剧',
            'cover': 'https://example.com/season.jpg',
            'evaluate': '简介',
            'stat': <String, Object?>{
              'views': 12000,
              'danmakus': 300,
              'reply': 20,
              'likes': 400,
              'coins': 50,
              'favorites': 600,
              'share': 7,
            },
            'episodes': <Object?>[
              <String, Object?>{
                'aid': 101,
                'bvid': 'BV1111111111',
                'cid': 1001,
                'title': '1',
                'long_title': '第一话',
                'cover': 'https://example.com/ep1.jpg',
                'duration': 1200000,
                'pub_time': 1719057600,
              },
              <String, Object?>{
                'aid': 102,
                'bvid': 'BV2222222222',
                'cid': 1002,
                'title': '2',
                'long_title': '第二话',
                'cover': 'https://example.com/ep2.jpg',
                'duration': 1300000,
                'pub_time': 1719662400,
              },
            ],
          },
        }),
      );
    }

    if (url.path == '/x/web-interface/ranking/v2') {
      if (riskFirstRanking && !_sentRankingRisk) {
        _sentRankingRisk = true;
        return _FakeRegionHttpClientResponse(
          jsonEncode(<String, Object?>{
            'code': biliRiskControlCode,
            'message': '-352',
          }),
        );
      }

      return _FakeRegionHttpClientResponse(
        jsonEncode(<String, Object?>{
          'code': 0,
          'message': '0',
          'data': <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'aid': 1,
                'bvid': 'BV1xx411c7mD',
                'cid': 22,
                'title': '测试排行榜视频',
                'pic': 'https://example.com/rank.jpg',
                'short_link_v2': 'https://b23.tv/example',
                'owner': <String, Object?>{'name': '测试UP'},
                'pts': 99,
                'duration': 125,
                'stat': <String, Object?>{'view': 12000},
              },
            ],
          },
        }),
      );
    }

    return _FakeRegionHttpClientResponse(
      jsonEncode(<String, Object?>{
        'code': -404,
        'message': 'unexpected fake route: ${url.path}',
      }),
      statusCode: HttpStatus.notFound,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeRegionHttpClientRequest implements HttpClientRequest {
  _FakeRegionHttpClientRequest(this._response);

  final _FakeRegionHttpClientResponse _response;
  final _FakeRegionHttpHeaders _headers = _FakeRegionHttpHeaders();
  int _contentLength = -1;

  @override
  HttpHeaders get headers => _headers;

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) {
    _contentLength = value;
  }

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeRegionHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeRegionHttpClientResponse(this.body, {this.statusCode = HttpStatus.ok});

  final String body;

  @override
  final int statusCode;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  HttpHeaders get headers => _FakeRegionHttpHeaders();

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

final class _FakeRegionHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> values = <String, List<String>>{};
  ContentType? _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) {
    _contentType = value;
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = <String>[value.toString()];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
