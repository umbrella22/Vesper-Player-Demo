import 'dart:io';

import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/download/download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  test('asset ID mismatch remains one entry and is explicitly unplayable', () {
    final task = _downloadTask(assetId: 'task-asset');
    final metadata = _metadata(assetId: 'metadata-asset', taskId: task.taskId);

    final entries = BiliOfflineCacheInventory.build(
      metadata: <BiliOfflineDownloadMetadata>[metadata],
      snapshot: VesperDownloadSnapshot(
        tasks: <VesperDownloadTaskSnapshot>[task],
      ),
    );

    expect(entries, hasLength(1));
    expect(entries.single.metadata, same(metadata));
    expect(entries.single.task, same(task));
    expect(entries.single.metadataMissing, isFalse);
    expect(entries.single.isUnplayable, isTrue);
    expect(entries.single.unplayableReason, contains('元数据不匹配'));
  });

  test(
    'unknown metadata shape is quarantined instead of read as empty',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bili-offline-shape-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/bili-offline-cache.json');
      await file.writeAsString('{"version":2,"items":[]}');
      final store = BiliOfflineDownloadStore(baseDirectory: root);

      final entries = await store.loadEntries();

      expect(entries, isEmpty);
      expect(file.existsSync(), isFalse);
      expect(
        root.listSync().whereType<File>().where(
          (entry) => entry.path.contains('.corrupt-'),
        ),
        isNotEmpty,
      );
    },
  );

  testWidgets('missing completed file prompts to clean invalid cache', (
    WidgetTester tester,
  ) async {
    final entry = BiliOfflineDownloadEntry(
      metadata: _metadata(outputPath: '/missing/offline-video.mp4'),
    );
    final controller = _IntegrityTestController(entry);

    await tester.pumpWidget(
      MaterialApp(
        home: OfflineCachePage(controller: controller, client: _DetailClient()),
      ),
    );
    for (var index = 0; index < 6; index += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('离线视频').last);
    await tester.pump();

    expect(find.text('缓存无法播放'), findsOneWidget);
    expect(find.textContaining('缓存文件已丢失或不完整'), findsOneWidget);
    expect(find.textContaining('是否清理这条失效缓存'), findsOneWidget);
  });
}

BiliOfflineDownloadMetadata _metadata({
  String assetId = 'metadata-asset',
  int? taskId,
  String? outputPath,
}) {
  return BiliOfflineDownloadMetadata(
    assetId: assetId,
    taskId: taskId,
    bvid: 'BV1xx411c7mD',
    cid: 11,
    videoTitle: '离线视频',
    pageTitle: 'P1',
    coverUrl: '',
    qualityLabel: '1080P',
    outputPath: outputPath,
    createdAtMs: 100,
  );
}

VesperDownloadTaskSnapshot _downloadTask({required String assetId}) {
  return VesperDownloadTaskSnapshot(
    taskId: 42,
    assetId: assetId,
    source: const VesperDownloadSource(
      source: VesperPlayerSource(
        uri: 'file:///tmp/offline.mp4',
        label: '离线视频',
        kind: VesperPlayerSourceKind.local,
        protocol: VesperPlayerSourceProtocol.file,
      ),
      contentFormat: VesperDownloadContentFormat.singleFile,
    ),
    profile: const VesperDownloadProfile(
      targetOutputFormat: VesperDownloadOutputFormat.mp4,
    ),
    state: VesperDownloadState.completed,
    progress: const VesperDownloadProgressSnapshot(
      receivedBytes: 10,
      totalBytes: 10,
    ),
    assetIndex: const VesperDownloadAssetIndex(
      contentFormat: VesperDownloadContentFormat.singleFile,
      completedPath: '/tmp/offline.mp4',
    ),
  );
}

final class _IntegrityTestController extends BiliOfflineDownloadController {
  _IntegrityTestController(this.entry) : super(client: BiliClient());

  final BiliOfflineDownloadEntry entry;

  @override
  bool get isInitialized => true;

  @override
  List<BiliOfflineDownloadEntry> get entries => <BiliOfflineDownloadEntry>[
    entry,
  ];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshCacheInventory() async {}

  @override
  Future<String?> resolvePlayableCachePath(
    BiliOfflineDownloadEntry entry,
  ) async => null;

  @override
  Future<BiliOfflineStorageUsage> resolveStorageUsage() async {
    return const BiliOfflineStorageUsage(
      cacheBytes: 1,
      freeBytes: 1,
      totalBytes: 2,
    );
  }
}

final class _DetailClient extends BiliClient {
  @override
  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async {
    return const BiliVideoDetail(
      aid: 1,
      bvid: 'BV1xx411c7mD',
      title: '离线视频',
      ownerMid: 2,
      ownerName: 'UP',
      ownerAvatarUrl: '',
      coverUrl: '',
      description: '',
      publishedAtLabel: null,
      playCountLabel: '1',
      danmakuCountLabel: '1',
      replyCountLabel: '1',
      likeCountLabel: '1',
      coinCountLabel: '1',
      favoriteCountLabel: '1',
      shareCountLabel: '1',
      pages: <BiliVideoPageEntry>[
        BiliVideoPageEntry(
          cid: 11,
          pageNumber: 1,
          title: '正片',
          durationSeconds: 60,
        ),
      ],
    );
  }
}
