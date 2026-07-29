import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/download/download.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('invalid cache banner confirms and removes stale entry', (
    WidgetTester tester,
  ) async {
    final entry = BiliOfflineDownloadEntry(
      metadata: const BiliOfflineDownloadMetadata(
        assetId: 'orphan-widget',
        bvid: '',
        cid: 0,
        videoTitle: '失效缓存',
        pageTitle: '视频信息丢失',
        coverUrl: '',
        qualityLabel: '未知清晰度',
        createdAtMs: 1,
      ),
      metadataMissing: true,
    );
    final controller = _FakeInvalidCacheController(entry);

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await _pumpOfflinePage(tester);

    expect(find.textContaining('发现 1 条失效缓存'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('offline-clean-invalid-cache')),
    );
    await tester.pump();

    expect(find.text('清理失效缓存？'), findsOneWidget);
    expect(find.textContaining('这些缓存无法播放'), findsOneWidget);
    await tester.tap(find.text('清理失效缓存'));
    await _pumpOfflinePage(tester);

    expect(controller.removedAssetIds, <String>['orphan-widget']);
    expect(find.textContaining('发现 1 条失效缓存'), findsNothing);
    expect(find.text('还没有离线缓存'), findsOneWidget);
  });

  testWidgets('tapping invalid cache explains that playback is unavailable', (
    WidgetTester tester,
  ) async {
    final entry = BiliOfflineDownloadEntry(
      metadata: const BiliOfflineDownloadMetadata(
        assetId: 'orphan-tap-widget',
        bvid: '',
        cid: 0,
        videoTitle: '失效缓存',
        pageTitle: '视频信息丢失',
        coverUrl: '',
        qualityLabel: '未知清晰度',
        createdAtMs: 1,
      ),
      metadataMissing: true,
    );
    final controller = _FakeInvalidCacheController(entry);

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await _pumpOfflinePage(tester);

    await tester.tap(find.text('失效缓存'));
    await tester.pump();

    expect(find.text('缓存无法播放'), findsOneWidget);
    expect(find.textContaining('是否清理这条失效缓存'), findsOneWidget);
  });
}

Future<void> _pumpOfflinePage(WidgetTester tester) async {
  for (var index = 0; index < 6; index += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final class _FakeInvalidCacheController extends BiliOfflineDownloadController {
  _FakeInvalidCacheController(BiliOfflineDownloadEntry entry)
    : _entries = <BiliOfflineDownloadEntry>[entry],
      super(client: BiliClient());

  final List<BiliOfflineDownloadEntry> _entries;
  final List<String> removedAssetIds = <String>[];

  @override
  bool get isInitialized => true;

  @override
  List<BiliOfflineDownloadEntry> get entries => _entries;

  @override
  Future<void> initialize() async {}

  @override
  Future<BiliOfflineStorageUsage> resolveStorageUsage() async {
    return const BiliOfflineStorageUsage(
      cacheBytes: 0,
      freeBytes: 1,
      totalBytes: 1,
    );
  }

  @override
  Future<void> removeEntry(BiliOfflineDownloadEntry entry) async {
    removedAssetIds.add(entry.metadata.assetId);
    _entries.removeWhere(
      (current) => current.metadata.assetId == entry.metadata.assetId,
    );
    notifyListeners();
  }
}
