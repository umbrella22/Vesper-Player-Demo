import 'package:vesper_player/vesper_player.dart';

import '../models/offline_download_models.dart';

/// Builds the user-visible cache list from the three local sources of truth:
/// app metadata, restored SDK tasks, and on-disk asset paths.
///
/// The SDK can restore a task after the app metadata file has been deleted, and
/// a file or directory can survive after both records are gone. Such records are
/// represented as explicitly unplayable entries instead of being silently
/// omitted, allowing the UI to offer a safe cleanup action.
final class BiliOfflineCacheInventory {
  const BiliOfflineCacheInventory._();

  static List<BiliOfflineDownloadEntry> build({
    required Iterable<BiliOfflineDownloadMetadata> metadata,
    required VesperDownloadSnapshot snapshot,
    Map<String, String> orphanAssetDirectories = const <String, String>{},
    Map<String, String> metadataIntegrityErrors = const <String, String>{},
  }) {
    final metadataByAssetId = <String, BiliOfflineDownloadMetadata>{
      for (final entry in metadata) entry.assetId: entry,
    };
    final tasks = snapshot.tasks
        .where((task) => task.state != VesperDownloadState.removed)
        .toList(growable: false);
    final taskAssetIds = <String>{
      for (final task in tasks)
        if (task.state != VesperDownloadState.removed) task.assetId,
    };
    final claimedTaskIds = <int>{};
    final result = <BiliOfflineDownloadEntry>[];
    for (final entry in metadataByAssetId.values) {
      final task = _taskForMetadata(entry, tasks);
      if (task != null) {
        claimedTaskIds.add(task.taskId);
      }
      final taskAssetMismatch =
          task != null &&
          task.assetId.isNotEmpty &&
          task.assetId != entry.assetId;
      result.add(
        BiliOfflineDownloadEntry(
          metadata: entry,
          task: task,
          integrityError: taskAssetMismatch
              ? '缓存任务与视频元数据不匹配，无法确认缓存内容，无法播放。请清理这条失效缓存。'
              : metadataIntegrityErrors[entry.assetId],
        ),
      );
    }

    for (final task in tasks) {
      if (claimedTaskIds.contains(task.taskId) ||
          metadataByAssetId.containsKey(task.assetId)) {
        continue;
      }
      result.add(_orphanEntryForTask(task));
    }

    for (final entry in orphanAssetDirectories.entries) {
      if (taskAssetIds.contains(entry.key) ||
          metadataByAssetId.containsKey(entry.key)) {
        continue;
      }
      result.add(_orphanEntryForDirectory(entry.key, entry.value));
    }

    result.sort((left, right) {
      final createdCompare = right.metadata.createdAtMs.compareTo(
        left.metadata.createdAtMs,
      );
      return createdCompare == 0
          ? left.metadata.assetId.compareTo(right.metadata.assetId)
          : createdCompare;
    });
    return List<BiliOfflineDownloadEntry>.unmodifiable(result);
  }

  static VesperDownloadTaskSnapshot? _taskForMetadata(
    BiliOfflineDownloadMetadata metadata,
    List<VesperDownloadTaskSnapshot> tasks,
  ) {
    final taskId = metadata.taskId;
    if (taskId != null) {
      for (final task in tasks) {
        if (task.taskId == taskId) {
          return task;
        }
      }
    }
    for (final task in tasks) {
      if (task.assetId == metadata.assetId) {
        return task;
      }
    }
    return null;
  }

  static BiliOfflineDownloadEntry _orphanEntryForTask(
    VesperDownloadTaskSnapshot task,
  ) {
    final assetId = task.assetId.isEmpty
        ? 'orphan-task-${task.taskId}'
        : task.assetId;
    return BiliOfflineDownloadEntry(
      metadata: _missingMetadata(
        assetId: assetId,
        taskId: task.taskId,
        outputPath: task.assetIndex.completedPath,
      ),
      task: task,
      metadataMissing: true,
    );
  }

  static BiliOfflineDownloadEntry _orphanEntryForDirectory(
    String assetId,
    String path,
  ) {
    return BiliOfflineDownloadEntry(
      metadata: _missingMetadata(assetId: assetId, outputPath: path),
      metadataMissing: true,
    );
  }

  static BiliOfflineDownloadMetadata _missingMetadata({
    required String assetId,
    int? taskId,
    String? outputPath,
  }) {
    return BiliOfflineDownloadMetadata(
      assetId: assetId,
      taskId: taskId,
      bvid: '',
      cid: 0,
      videoTitle: '失效缓存（视频信息丢失）',
      pageTitle: '视频信息丢失',
      coverUrl: '',
      qualityLabel: '未知清晰度',
      outputPath: outputPath,
      createdAtMs: 0,
      errorMessage: '缓存视频信息已丢失，无法播放。请清理这条失效缓存。',
    );
  }
}
