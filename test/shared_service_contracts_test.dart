import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_dash_api.dart';
import 'package:vesper_media/bili/common/services/bili_dash_manifest_parser.dart';
import 'package:vesper_media/bili/common/services/bili_download_asset_id.dart';
import 'package:vesper_media/common/storage/application_storage.dart';
import 'package:vesper_media/common/storage/atomic_file_writer.dart';
import 'package:vesper_media/common/storage/generated_file_cleanup.dart';

void main() {
  group('shared application storage', () {
    test('migrates a legacy file and clears both locations', () async {
      final current = await Directory.systemTemp.createTemp(
        'application-storage-current-',
      );
      final legacy = await Directory.systemTemp.createTemp(
        'application-storage-legacy-',
      );
      addTearDown(() => current.delete(recursive: true));
      addTearDown(() => legacy.delete(recursive: true));

      final legacyFile = File('${legacy.path}/state.json');
      await legacyFile.writeAsString('{"source":"legacy"}');

      final resolved = await resolveApplicationStorageFile(
        fileName: 'state.json',
        baseDirectory: current,
        legacyDirectory: legacy,
      );

      expect(resolved.path, '${current.path}/state.json');
      expect(await resolved.readAsString(), '{"source":"legacy"}');
      await clearApplicationStorageFile(
        fileName: 'state.json',
        baseDirectory: current,
        legacyDirectory: legacy,
      );
      expect(await resolved.exists(), isFalse);
      expect(await legacyFile.exists(), isFalse);
    });
  });

  group('atomic string writes', () {
    test('creates parent directories and leaves no temporary file', () async {
      final root = await Directory.systemTemp.createTemp('atomic-write-new-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/nested/state.json');

      await writeStringAtomically(file, '{"value":1}');

      expect(await file.readAsString(), '{"value":1}');
      expect(_temporaryFilesUnder(root), isEmpty);
    });

    test('replaces an existing file and leaves no temporary file', () async {
      final root = await Directory.systemTemp.createTemp(
        'atomic-write-replace-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/state.json');
      await file.writeAsString('old');

      await writeStringAtomically(file, 'new');

      expect(await file.readAsString(), 'new');
      expect(_temporaryFilesUnder(root), isEmpty);
    });
  });

  test(
    'generated-file cleanup respects age, extension, and temp names',
    () async {
      final root = await Directory.systemTemp.createTemp('generated-cleanup-');
      addTearDown(() => root.delete(recursive: true));
      final staleManifest = File('${root.path}/stale.mpd');
      final staleTemporary = File('${root.path}/state.tmp-1-2');
      final staleUnrelated = File('${root.path}/keep.json');
      final recentManifest = File('${root.path}/recent.mpd');
      for (final file in <File>[
        staleManifest,
        staleTemporary,
        staleUnrelated,
        recentManifest,
      ]) {
        await file.writeAsString('contents');
      }
      final staleTime = DateTime.now().subtract(const Duration(hours: 2));
      await staleManifest.setLastModified(staleTime);
      await staleTemporary.setLastModified(staleTime);
      await staleUnrelated.setLastModified(staleTime);

      await deleteStaleGeneratedFilesBestEffort(
        root,
        fileExtension: '.mpd',
        maxAge: const Duration(hours: 1),
      );

      expect(await staleManifest.exists(), isFalse);
      expect(await staleTemporary.exists(), isFalse);
      expect(await staleUnrelated.exists(), isTrue);
      expect(await recentManifest.exists(), isTrue);
    },
  );

  group('Bilibili DASH API contract', () {
    test('builds the shared playback and download request parameters', () {
      final params = buildBiliDashPlayUrlParams(
        detail: _videoDetail,
        page: _videoPage,
        variant: const BiliDashRequestVariant(
          label: 'test',
          fnval: 976,
          extraParams: <String, Object?>{'high_quality': 1},
        ),
        session: 'session-value',
      );

      expect(params, <String, Object?>{
        'avid': 22,
        'bvid': 'BV1PAGE',
        'cid': 33,
        'qn': biliMaxVideoQuality,
        'otype': 'json',
        'fnver': 0,
        'fnval': 976,
        'fourk': 1,
        'support_multi_audio': 'true',
        'session': 'session-value',
        'high_quality': 1,
      });
    });

    test('keeps playback and download quality-label policies explicit', () {
      const parser = BiliDashManifestParser();
      final response = _dashResponse();

      final playback = parser.parse(response).manifest;
      final download = parser
          .parse(response, useResponseQualityLabels: false)
          .manifest;

      expect(playback?.videoStreams.single.qualityLabel, 'API 1080P');
      expect(download?.videoStreams.single.qualityLabel, '1080P');
      expect(
        playback?.videoStreams.single.representationId,
        download?.videoStreams.single.representationId,
      );
    });
  });

  group('Bilibili download asset selection', () {
    test('parses persisted quality and codec tokens', () {
      final selection = tryParseBiliDownloadAssetSelection(
        'bili-BV1TEST-33-q126-hevc-flac',
      );

      expect(selection?.qualityId, 126);
      expect(selection?.codecPreference, BiliVideoCodecPreference.hevc);
    });

    test('uses automatic codec for an unknown token', () {
      final selection = tryParseBiliDownloadAssetSelection(
        'bili-BV1TEST-33-q80-codec-audio30280',
      );

      expect(selection?.qualityId, 80);
      expect(selection?.codecPreference, BiliVideoCodecPreference.automatic);
    });

    test('rejects an asset ID without an encoded quality', () {
      expect(
        tryParseBiliDownloadAssetSelection('asset-without-quality'),
        isNull,
      );
    });
  });
}

List<File> _temporaryFilesUnder(Directory directory) {
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.contains('.tmp-'))
      .toList(growable: false);
}

const _videoDetail = BiliVideoDetail(
  aid: 11,
  bvid: 'BV1DETAIL',
  title: 'Video',
  ownerMid: 1,
  ownerName: 'Owner',
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
  pages: <BiliVideoPageEntry>[],
);

const _videoPage = BiliVideoPageEntry(
  cid: 33,
  pageNumber: 1,
  title: 'Page',
  durationSeconds: 60,
  aid: 22,
  bvid: 'BV1PAGE',
);

Map<String, Object?> _dashResponse() {
  return <String, Object?>{
    'support_formats': <Object?>[
      <String, Object?>{'quality': 80, 'new_description': 'API 1080P'},
    ],
    'dash': <String, Object?>{
      'duration': 60,
      'min_buffer_time': 1.5,
      'video': <Object?>[
        _dashStream(
          id: 80,
          url: 'https://example.com/video.m4s',
          mimeType: 'video/mp4',
          codecs: 'avc1.640028',
          bandwidth: 1200000,
          codecid: 7,
        ),
      ],
      'audio': <Object?>[
        _dashStream(
          id: 30280,
          url: 'https://example.com/audio.m4s',
          mimeType: 'audio/mp4',
          codecs: 'mp4a.40.2',
          bandwidth: 192000,
        ),
      ],
    },
  };
}

Map<String, Object?> _dashStream({
  required int id,
  required String url,
  required String mimeType,
  required String codecs,
  required int bandwidth,
  int? codecid,
}) {
  return <String, Object?>{
    'id': id,
    'base_url': url,
    'mime_type': mimeType,
    'codecs': codecs,
    'bandwidth': bandwidth,
    'codecid': codecid,
    'SegmentBase': <String, Object?>{
      'Initialization': '0-10',
      'indexRange': '11-20',
    },
  };
}
