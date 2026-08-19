import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/bili_media_platform_adapter.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_media_mapper.dart';
import 'package:vesper_media/bili/common/services/bili_quality_mapping.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';

/// 抽取计划 §6.2 契约与模型红测试。
void main() {
  group('BiliMediaMapper 映射', () {
    test('toGenericDetail 保留壳需要字段并标记剧集内容', () {
      final detail = _buildDetail();
      final generic = BiliMediaMapper.toGenericDetail(detail);

      expect(generic.mediaId, 'BV1xx');
      expect(generic.title, '标题');
      expect(generic.coverUrl, 'https://cover');
      expect(generic.isEpisodic, isFalse);
      expect(generic.replyCountLabel, '1.2万');
      expect(generic.danmakuCountLabel, '3.4万');
      expect(generic.pages, hasLength(2));
      expect(generic.pages.first.entryId, '101');
      expect(generic.pages.first.pageNumber, 1);
      expect(generic.pages.first.title, 'P1 标题');
      expect(generic.pages.first.durationSeconds, 300);
    });

    test('番剧详情标记 isEpisodic', () {
      final pgc = BiliVideoDetail(
        aid: 1,
        bvid: 'BV1pgc',
        title: '剧集',
        ownerMid: 0,
        ownerName: '番剧',
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
        pages: const <BiliVideoPageEntry>[],
      );
      expect(BiliMediaMapper.toGenericDetail(pgc).isEpisodic, isTrue);
    });

    test('toBiliDetail 与原始详情无损往返', () {
      final original = _buildDetail();
      final roundTrip = BiliMediaMapper.toBiliDetail(
        BiliMediaMapper.toGenericDetail(original),
      );

      expect(roundTrip.aid, original.aid);
      expect(roundTrip.bvid, original.bvid);
      expect(roundTrip.title, original.title);
      expect(roundTrip.ownerMid, original.ownerMid);
      expect(roundTrip.ownerName, original.ownerName);
      expect(roundTrip.ownerAvatarUrl, original.ownerAvatarUrl);
      expect(roundTrip.coverUrl, original.coverUrl);
      expect(roundTrip.description, original.description);
      expect(roundTrip.publishedAtLabel, original.publishedAtLabel);
      expect(roundTrip.playCountLabel, original.playCountLabel);
      expect(roundTrip.danmakuCountLabel, original.danmakuCountLabel);
      expect(roundTrip.replyCountLabel, original.replyCountLabel);
      expect(roundTrip.likeCountLabel, original.likeCountLabel);
      expect(roundTrip.coinCountLabel, original.coinCountLabel);
      expect(roundTrip.favoriteCountLabel, original.favoriteCountLabel);
      expect(roundTrip.shareCountLabel, original.shareCountLabel);
      expect(roundTrip.pages, hasLength(original.pages.length));
      for (var i = 0; i < original.pages.length; i++) {
        expect(roundTrip.pages[i].cid, original.pages[i].cid);
        expect(roundTrip.pages[i].pageNumber, original.pages[i].pageNumber);
        expect(roundTrip.pages[i].title, original.pages[i].title);
        expect(
          roundTrip.pages[i].durationSeconds,
          original.pages[i].durationSeconds,
        );
        expect(roundTrip.pages[i].coverUrl, original.pages[i].coverUrl);
        expect(roundTrip.pages[i].aid, original.pages[i].aid);
        expect(roundTrip.pages[i].bvid, original.pages[i].bvid);
        expect(roundTrip.pages[i].episodeId, original.pages[i].episodeId);
      }
    });
  });

  group('ResolvedMediaPlayback.toSource 与 BiliResolvedPlayback 一致', () {
    test('remote 源逐字段一致', () {
      final resolved = _buildResolvedPlayback(isLocalFile: false);
      final generic = BiliMediaMapper.toResolvedPlayback(resolved);

      final expected = resolved.toSource();
      final actual = generic.toSource();
      _expectSourceEqual(actual, expected);
    });

    test('本地文件源逐字段一致', () {
      final resolved = _buildResolvedPlayback(isLocalFile: true);
      final generic = BiliMediaMapper.toResolvedPlayback(resolved);

      _expectSourceEqual(generic.toSource(), resolved.toSource());
    });

    test('mapper 保留可选纯音频源', () {
      final generic = BiliMediaMapper.toResolvedPlayback(
        _buildResolvedPlayback(isLocalFile: true, withAudioOnlySource: true),
      );

      expect(generic.audioOnlySource, isNotNull);
      expect(generic.audioOnlySource!.uri, 'file:///tmp/manifest-audio.mpd');
      expect(generic.audioOnlySource!.debugPath, '/tmp/manifest-audio.mpd');
      expect(
        generic.toAudioOnlySource()!.protocol,
        VesperPlayerSourceProtocol.dash,
      );
      expect(generic.toAudioOnlySource()!.externalSubtitles, hasLength(2));
    });
  });

  group('能力缺省语义', () {
    test('最小适配器只实现 resolvePlayback 并继承静态能力缺省值', () {
      final adapter = _EmptyAdapter();
      expect(adapter.danmaku, isNull);
      expect(adapter.history, isNull);
      expect(adapter.dlnaConfig, isNull);
      expect(adapter.qualityPolicy.supportsCodecSelection, isFalse);
      expect(adapter.qualityPolicy.codecLabelFor, isNull);
    });

    test('空播放绑定不声明会话级互动与内容面板', () {
      const binding = MediaPlaybackBinding();
      expect(binding.buildEngagement(), isNull);
      expect(
        binding.contentSurfacesBuilder,
        isNull,
        reason: '内容面板需要 MediaPlaybackContentHost，由播放页创建后再调用',
      );
    });

    test('BiliMediaPlatformAdapter 声明 B 站能力', () {
      final adapter = BiliMediaPlatformAdapter(client: BiliClient());
      expect(adapter.danmaku, isNotNull, reason: 'Phase 3 已接线');
      expect(adapter.history, isNotNull, reason: 'Phase 4 已接线');
      expect(adapter.qualityPolicy.supportsCodecSelection, isTrue);
      expect(adapter.dlnaConfig, isNotNull);
    });

    test('弹幕 provider 是稳定实例（不随读取重建）', () {
      final adapter = BiliMediaPlatformAdapter(client: BiliClient());
      expect(
        identical(adapter.danmaku, adapter.danmaku),
        isTrue,
        reason:
            '播放快照持续重建舞台并读取 adapter.danmaku，'
            '每次返回新实例会导致弹幕层反复重订阅与重复请求',
      );
    });

    test('Dolby Vision 轨道展示独立但策略归入 HEVC', () {
      final policy = BiliMediaPlatformAdapter(
        client: BiliClient(),
      ).qualityPolicy;
      const dvTrack = VesperMediaTrack(
        id: 'video-80-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'dvhe.05.06',
      );
      expect(policy.codecLabelFor!(dvTrack), 'Dolby Vision');
      expect(policy.codecStrategyIdentityFor!(dvTrack), 'HEVC');
    });

    test('原生轨道按语义和接近码率区分同尺寸清晰度', () {
      const regular = VesperMediaTrack(
        id: 'video-80-12-900000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'hev1.1.6.L120',
        bitRate: 900000,
        width: 1920,
        height: 1080,
        frameRate: 30,
      );
      const highBitRate = VesperMediaTrack(
        id: 'video-112-12-1800000-1',
        kind: VesperMediaTrackKind.video,
        label: '1080P 高码率',
        codec: 'hev1.1.6.L120',
        bitRate: 1800000,
        width: 1920,
        height: 1080,
        frameRate: 30,
      );
      const nativeTrack = VesperMediaTrack(
        id: 'opaque-native-track',
        kind: VesperMediaTrackKind.video,
        codec: 'hev1.1.6.L120',
        bitRate: 1794000,
        width: 1920,
        height: 1080,
        frameRate: 29.97,
      );

      expect(
        BiliQualityMapping.qualityOptionIdForNativeTrack(
          nativeTrack,
          const <MediaQualityOption>[
            MediaQualityOption(
              id: '112',
              label: '1080P 高码率',
              tracks: <VesperMediaTrack>[highBitRate],
            ),
            MediaQualityOption(
              id: '80',
              label: '1080P',
              tracks: <VesperMediaTrack>[regular],
            ),
          ],
        ),
        '112',
      );
    });
  });
}

void _expectSourceEqual(
  VesperPlayerSource actual,
  VesperPlayerSource expected,
) {
  expect(actual.uri, expected.uri);
  expect(actual.label, expected.label);
  expect(actual.kind, expected.kind);
  expect(actual.protocol, expected.protocol);
  expect(actual.headers, expected.headers);
  expect(
    actual.externalSubtitles,
    hasLength(expected.externalSubtitles.length),
  );
  for (var i = 0; i < expected.externalSubtitles.length; i++) {
    final a = actual.externalSubtitles[i];
    final e = expected.externalSubtitles[i];
    expect(a.id, e.id);
    expect(a.uri, e.uri);
    expect(a.mimeType, e.mimeType);
    expect(a.language, e.language);
    expect(a.label, e.label);
    expect(a.isDefault, e.isDefault);
  }
}

BiliVideoDetail _buildDetail() {
  return BiliVideoDetail(
    aid: 42,
    bvid: 'BV1xx',
    title: '标题',
    ownerMid: 7,
    ownerName: 'UP主',
    ownerAvatarUrl: 'https://avatar',
    coverUrl: 'https://cover',
    description: '简介',
    publishedAtLabel: '2026-01-01',
    playCountLabel: '5.6万',
    danmakuCountLabel: '3.4万',
    replyCountLabel: '1.2万',
    likeCountLabel: '9.8千',
    coinCountLabel: '7.6千',
    favoriteCountLabel: '5.4千',
    shareCountLabel: '3.2千',
    pages: const <BiliVideoPageEntry>[
      BiliVideoPageEntry(
        cid: 101,
        pageNumber: 1,
        title: 'P1 标题',
        durationSeconds: 300,
        aid: 42,
        bvid: 'BV1xx',
        coverUrl: 'https://cover/p1',
        episodeId: null,
      ),
      BiliVideoPageEntry(
        cid: 102,
        pageNumber: 2,
        title: 'P2 标题',
        durationSeconds: 240,
        aid: 42,
        bvid: 'BV1xx',
        coverUrl: null,
        episodeId: 99,
      ),
    ],
  );
}

BiliResolvedPlayback _buildResolvedPlayback({
  required bool isLocalFile,
  bool withAudioOnlySource = false,
}) {
  return BiliResolvedPlayback(
    bvid: 'BV1xx',
    cid: 101,
    title: '标题',
    subtitle: 'P1 · 分P标题',
    uri: isLocalFile
        ? 'file:///tmp/manifest.mpd'
        : 'https://media.example.com/master.mpd',
    protocol: VesperPlayerSourceProtocol.dash,
    transportLabel: 'test transport',
    isLocalFile: isLocalFile,
    headers: const <String, String>{'Referer': 'https://bilibili.com'},
    videoTracks: const <VesperMediaTrack>[],
    subtitleTracks: const <BiliSubtitleTrack>[
      BiliSubtitleTrack(
        id: 'subtitle:bili:1',
        language: 'zh-Hans',
        languageLabel: '中文（简体）',
        url: 'file:///tmp/sub.zh.vtt',
        isDefault: true,
      ),
      BiliSubtitleTrack(
        id: 'subtitle:bili:2',
        language: 'en',
        languageLabel: 'English',
        url: 'file:///tmp/sub.en.vtt',
      ),
    ],
    subtitleError: null,
    debugPath: isLocalFile ? '/tmp/manifest.mpd' : null,
    audioOnlySource: withAudioOnlySource
        ? const BiliResolvedPlaybackVariant(
            uri: 'file:///tmp/manifest-audio.mpd',
            protocol: VesperPlayerSourceProtocol.dash,
            transportLabel: 'AAC only',
            isLocalFile: true,
            headers: <String, String>{'Referer': 'https://bilibili.com'},
            debugPath: '/tmp/manifest-audio.mpd',
          )
        : null,
  );
}

final class _EmptyAdapter extends MediaPlatformAdapter {
  @override
  Future<ResolvedMediaPlayback> resolvePlayback({
    required MediaDetail detail,
    required MediaPlaybackEntry entry,
  }) async {
    throw UnimplementedError();
  }
}
