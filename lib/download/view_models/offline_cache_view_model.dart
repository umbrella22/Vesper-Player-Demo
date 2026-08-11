import 'dart:async';
import 'dart:io';

import 'package:signals/signals_flutter.dart';
import 'package:vesper_player/vesper_player.dart';

import '../../bili/common/models/bili_models.dart';
import '../../bili/common/services/bili_client.dart';
import '../../bili/common/services/bili_history_store.dart';
import '../models/offline_download_models.dart';
import '../models/offline_storage_models.dart';
import '../services/offline_download_controller.dart';
import '../services/offline_media_exporter.dart';

final class OfflineCacheOpenResult {
  const OfflineCacheOpenResult({
    required this.detail,
    required this.page,
    this.initialResolvedPlayback,
    this.message,
  });

  final BiliVideoDetail detail;
  final BiliVideoPageEntry page;
  final BiliResolvedPlayback? initialResolvedPlayback;
  final String? message;
}

final class BiliInvalidOfflineCacheException implements Exception {
  const BiliInvalidOfflineCacheException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class OfflineCacheDeleteResult {
  const OfflineCacheDeleteResult({
    required this.deleted,
    required this.message,
  });

  final bool deleted;
  final String message;
}

final class OfflineCacheCleanupResult {
  const OfflineCacheCleanupResult({
    required this.deletedCount,
    required this.failedCount,
  });

  final int deletedCount;
  final int failedCount;

  String get message {
    if (deletedCount == 0 && failedCount == 0) {
      return '没有需要清理的失效缓存';
    }
    if (failedCount == 0) {
      return '已清理 $deletedCount 条失效缓存';
    }
    if (deletedCount == 0) {
      return '$failedCount 条失效缓存清理失败';
    }
    return '已清理 $deletedCount 条失效缓存，$failedCount 条清理失败';
  }
}

final class OfflineCacheExportResult {
  const OfflineCacheExportResult({
    required this.exported,
    required this.message,
    this.uri,
  });

  final bool exported;
  final String message;
  final String? uri;
}

final class OfflineCacheViewModel {
  OfflineCacheViewModel({
    BiliOfflineDownloadController? controller,
    BiliClient? client,
    BiliHistoryStore? historyStore,
    this._mediaExporter = const BiliOfflineMediaExporter(),
  }) : controller = controller ?? BiliOfflineDownloadController.instance,
       client = client ?? BiliClient.instance,
       historyStore = historyStore ?? const BiliHistoryStore() {
    _entries.value = this.controller.entries.toList(growable: false);
    entries = _entries.readonly();
    errorMessage = _errorMessage.readonly();
    storageErrorMessage = _storageErrorMessage.readonly();
    storageUsage = _storageUsage.readonly();
    loading = _loading.readonly();
    storageLoading = _storageLoading.readonly();
    openingAssetIds = _openingAssetIds.readonly();
    deletingAssetIds = _deletingAssetIds.readonly();
    exportingAssetIds = _exportingAssetIds.readonly();
    taskActionTaskIds = _taskActionTaskIds.readonly();
    activeEntries = computed(
      () => _entries.value
          .where((entry) => entry.isActive)
          .toList(growable: false),
    );
    completedEntries = computed(
      () => _entries.value
          .where((entry) => !entry.isActive)
          .toList(growable: false),
    );
    invalidEntries = computed(
      () => _entries.value
          .where((entry) => entry.isUnplayable)
          .toList(growable: false),
    );
  }

  final BiliOfflineDownloadController controller;
  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliOfflineMediaExporter _mediaExporter;

  Timer? _storageRefreshTimer;
  final _entries = signal<List<BiliOfflineDownloadEntry>>(
    const <BiliOfflineDownloadEntry>[],
  );
  final _errorMessage = signal<String?>(null);
  final _storageErrorMessage = signal<String?>(null);
  final _storageUsage = signal<BiliOfflineStorageUsage?>(null);
  final _loading = signal(true);
  final _storageLoading = signal(true);
  final _openingAssetIds = signal<Set<String>>(const <String>{});
  final _deletingAssetIds = signal<Set<String>>(const <String>{});
  final _exportingAssetIds = signal<Set<String>>(const <String>{});
  final _taskActionTaskIds = signal<Set<int>>(const <int>{});

  late final ReadonlySignal<List<BiliOfflineDownloadEntry>> entries;
  late final FlutterComputed<List<BiliOfflineDownloadEntry>> activeEntries;
  late final FlutterComputed<List<BiliOfflineDownloadEntry>> completedEntries;
  late final FlutterComputed<List<BiliOfflineDownloadEntry>> invalidEntries;
  late final ReadonlySignal<String?> errorMessage;
  late final ReadonlySignal<String?> storageErrorMessage;
  late final ReadonlySignal<BiliOfflineStorageUsage?> storageUsage;
  late final ReadonlySignal<bool> loading;
  late final ReadonlySignal<bool> storageLoading;
  late final ReadonlySignal<Set<String>> openingAssetIds;
  late final ReadonlySignal<Set<String>> deletingAssetIds;
  late final ReadonlySignal<Set<String>> exportingAssetIds;
  late final ReadonlySignal<Set<int>> taskActionTaskIds;

  Future<void> initialize() async {
    controller.addListener(_handleControllerChanged);
    await reload();
  }

  Future<void> reload() async {
    _loading.value = true;
    _errorMessage.value = null;
    try {
      await controller.initialize();
      await controller.refreshCacheInventory();
      _syncEntries();
      await loadStorageUsage();
    } catch (error) {
      _errorMessage.value = error.toString();
    } finally {
      _loading.value = false;
    }
  }

  Future<void> loadStorageUsage() async {
    _storageLoading.value = true;
    _storageErrorMessage.value = null;
    try {
      _storageUsage.value = await controller.resolveStorageUsage();
    } catch (error) {
      _storageErrorMessage.value = error.toString();
    } finally {
      _storageLoading.value = false;
    }
  }

  Future<OfflineCacheOpenResult?> openEntry(
    BiliOfflineDownloadEntry entry,
  ) async {
    if (entry.isUnplayable) {
      throw BiliInvalidOfflineCacheException(entry.unplayableReason);
    }
    final assetId = entry.metadata.assetId;
    if (_openingAssetIds.value.contains(assetId)) {
      return null;
    }
    _openingAssetIds.value = <String>{..._openingAssetIds.value, assetId};
    try {
      final metadata = entry.metadata;
      final detail = await client.fetchVideoDetail(metadata.bvid);
      if (detail.pages.isEmpty) {
        throw const BiliOfflineDownloadException('这个视频没有可播放分 P。');
      }
      BiliVideoPageEntry? page;
      for (final candidate in detail.pages) {
        if (candidate.cid == metadata.cid) {
          page = candidate;
          break;
        }
      }
      if (page == null) {
        throw const BiliInvalidOfflineCacheException(
          '缓存视频元数据与当前分 P 不匹配，无法确认缓存内容，无法播放。',
        );
      }

      BiliResolvedPlayback? initialResolvedPlayback;
      String? message;
      if (entry.isCompleted) {
        final cachePath = await controller.resolvePlayableCachePath(entry);
        if (cachePath != null) {
          initialResolvedPlayback = _resolvedOfflinePlayback(
            detail: detail,
            page: page,
            entry: entry,
            outputPath: cachePath,
          );
        } else {
          throw const BiliInvalidOfflineCacheException('缓存文件已丢失或不完整，无法播放。');
        }
      } else {
        unawaited(_continueCaching(entry: entry, detail: detail, page: page));
        message = '正在边播边缓存';
      }

      return OfflineCacheOpenResult(
        detail: detail,
        page: page,
        initialResolvedPlayback: initialResolvedPlayback,
        message: message,
      );
    } finally {
      _openingAssetIds.value = <String>{..._openingAssetIds.value}
        ..remove(assetId);
    }
  }

  Future<OfflineCacheDeleteResult> deleteEntry(
    BiliOfflineDownloadEntry entry,
  ) async {
    final assetId = entry.metadata.assetId;
    if (_deletingAssetIds.value.contains(assetId)) {
      return const OfflineCacheDeleteResult(deleted: false, message: '');
    }
    _deletingAssetIds.value = <String>{..._deletingAssetIds.value, assetId};
    try {
      await controller.removeEntry(entry);
      _syncEntries();
      return const OfflineCacheDeleteResult(deleted: true, message: '已删除缓存');
    } catch (error) {
      return OfflineCacheDeleteResult(deleted: false, message: '删除失败：$error');
    } finally {
      _deletingAssetIds.value = <String>{..._deletingAssetIds.value}
        ..remove(assetId);
    }
  }

  Future<OfflineCacheCleanupResult> cleanupInvalidEntries() async {
    final invalid = invalidEntries.value.toList(growable: false);
    var deletedCount = 0;
    var failedCount = 0;
    for (final entry in invalid) {
      final result = await deleteEntry(entry);
      if (result.deleted) {
        deletedCount += 1;
      } else {
        failedCount += 1;
      }
    }
    return OfflineCacheCleanupResult(
      deletedCount: deletedCount,
      failedCount: failedCount,
    );
  }

  Future<OfflineCacheExportResult> exportEntry(
    BiliOfflineDownloadEntry entry,
  ) async {
    final assetId = entry.metadata.assetId;
    if (_exportingAssetIds.value.contains(assetId)) {
      return const OfflineCacheExportResult(exported: false, message: '');
    }
    if (entry.isUnplayable) {
      return OfflineCacheExportResult(
        exported: false,
        message: entry.unplayableReason,
      );
    }
    if (!entry.isCompleted) {
      return const OfflineCacheExportResult(
        exported: false,
        message: '缓存完成后才能导出到相册。',
      );
    }

    _exportingAssetIds.value = <String>{..._exportingAssetIds.value, assetId};
    try {
      final cachePath = await controller.resolvePlayableCachePath(entry);
      if (cachePath == null || !cachePath.toLowerCase().endsWith('.mp4')) {
        return const OfflineCacheExportResult(
          exported: false,
          message: '没有找到可导出的 MP4 文件。',
        );
      }

      final uri = await _mediaExporter.exportMp4ToGallery(
        sourcePath: cachePath,
        displayName: _exportFileName(entry),
      );
      return OfflineCacheExportResult(
        exported: true,
        message: '已导出到相册',
        uri: uri,
      );
    } catch (error) {
      return OfflineCacheExportResult(exported: false, message: '导出失败：$error');
    } finally {
      _exportingAssetIds.value = <String>{..._exportingAssetIds.value}
        ..remove(assetId);
    }
  }

  Future<void> toggleTaskCaching(BiliOfflineDownloadEntry entry) async {
    final task = entry.task;
    if (task == null || _taskActionTaskIds.value.contains(task.taskId)) {
      return;
    }
    final taskId = task.taskId;
    _taskActionTaskIds.value = <int>{..._taskActionTaskIds.value, taskId};
    try {
      switch (task.state) {
        case VesperDownloadState.downloading:
        case VesperDownloadState.preparing:
        case VesperDownloadState.queued:
          await controller.pause(taskId);
        case VesperDownloadState.paused:
        case VesperDownloadState.failed:
          await controller.resume(taskId);
        case VesperDownloadState.completed:
        case VesperDownloadState.removed:
        case VesperDownloadState.unknown:
          break;
      }
    } finally {
      _taskActionTaskIds.value = <int>{..._taskActionTaskIds.value}
        ..remove(taskId);
    }
  }

  Future<void> _continueCaching({
    required BiliOfflineDownloadEntry entry,
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
  }) async {
    final taskId = entry.task?.taskId ?? entry.metadata.taskId;
    if (taskId != null && entry.state != VesperDownloadState.failed) {
      await controller.startOrResume(taskId);
      return;
    }

    final qualityId = _qualityIdFromAssetId(entry.metadata.assetId);
    if (qualityId == null) {
      return;
    }
    await controller.enqueueBiliPage(
      detail: detail,
      page: page,
      qualityId: qualityId,
      codecPreference: _codecPreferenceFromAssetId(entry.metadata.assetId),
    );
  }

  BiliResolvedPlayback _resolvedOfflinePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required BiliOfflineDownloadEntry entry,
    required String outputPath,
  }) {
    final file = File(outputPath);
    return BiliResolvedPlayback(
      bvid: detail.bvid,
      cid: page.cid,
      title: detail.title,
      subtitle: 'P${page.pageNumber} · ${page.title}',
      uri: file.uri.toString(),
      protocol: VesperPlayerSourceProtocol.file,
      transportLabel: '离线缓存 · ${entry.metadata.qualityLabel}',
      isLocalFile: true,
      debugPath: outputPath,
    );
  }

  int? _qualityIdFromAssetId(String assetId) {
    final match = RegExp(r'-q(\d+)-').firstMatch(assetId);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  BiliVideoCodecPreference _codecPreferenceFromAssetId(String assetId) {
    if (assetId.contains('-av1-')) {
      return BiliVideoCodecPreference.av1;
    }
    if (assetId.contains('-hevc-')) {
      return BiliVideoCodecPreference.hevc;
    }
    if (assetId.contains('-avc-')) {
      return BiliVideoCodecPreference.avc;
    }
    return BiliVideoCodecPreference.automatic;
  }

  String _exportFileName(BiliOfflineDownloadEntry entry) {
    final metadata = entry.metadata;
    final raw =
        '${metadata.videoTitle}-${metadata.pageTitle}-${metadata.qualityLabel}';
    final sanitized = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized.isEmpty ? '${metadata.assetId}.mp4' : '$sanitized.mp4';
  }

  void _handleControllerChanged() {
    _syncEntries();
    _scheduleStorageRefresh();
  }

  void _scheduleStorageRefresh() {
    if (_storageLoading.value) {
      return;
    }
    _storageRefreshTimer?.cancel();
    _storageRefreshTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(loadStorageUsage());
    });
  }

  void _syncEntries() {
    _entries.value = controller.entries.toList(growable: false);
  }

  void dispose() {
    _storageRefreshTimer?.cancel();
    controller.removeListener(_handleControllerChanged);
    activeEntries.dispose();
    completedEntries.dispose();
    invalidEntries.dispose();
    _entries.dispose();
    _errorMessage.dispose();
    _storageErrorMessage.dispose();
    _storageUsage.dispose();
    _loading.dispose();
    _storageLoading.dispose();
    _openingAssetIds.dispose();
    _deletingAssetIds.dispose();
    _exportingAssetIds.dispose();
    _taskActionTaskIds.dispose();
  }
}
