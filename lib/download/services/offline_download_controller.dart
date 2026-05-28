import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vesper_player/vesper_player.dart';

import '../../bili/common/models/bili_models.dart';
import '../../bili/common/services/bili_client.dart';
import '../../bili/common/services/bili_storage_directory.dart';
import '../models/offline_download_models.dart';
import '../models/offline_storage_models.dart';
import 'download_plugin_resolver.dart';
import 'offline_device_storage.dart';
import 'offline_download_store.dart';

final class BiliOfflineDownloadException implements Exception {
  const BiliOfflineDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BiliOfflineDownloadController extends ChangeNotifier {
  BiliOfflineDownloadController({
    required BiliClient client,
    BiliOfflineDownloadStore store = const BiliOfflineDownloadStore(),
    BiliDownloadPluginResolver pluginResolver =
        const BiliDownloadPluginResolver(),
    VesperDownloadManager? manager,
  }) : _client = client,
       _store = store,
       _pluginResolver = pluginResolver,
       _manager = manager;

  static final BiliOfflineDownloadController instance =
      BiliOfflineDownloadController(client: BiliClient.instance);

  final BiliClient _client;
  final BiliOfflineDownloadStore _store;
  final BiliDownloadPluginResolver _pluginResolver;
  final Map<String, BiliOfflineDownloadMetadata> _metadataByAssetId =
      <String, BiliOfflineDownloadMetadata>{};

  VesperDownloadManager? _manager;
  VesperDownloadSnapshot _snapshot = const VesperDownloadSnapshot.initial();
  StreamSubscription<VesperDownloadSnapshot>? _snapshotSubscription;
  Directory? _cacheRoot;
  List<String> _pluginLibraryPaths = const <String>[];
  final Map<int, String> _lastTaskLogFingerprints = <int, String>{};
  Future<void>? _initializing;
  Future<void> _metadataWriteChain = Future<void>.value();
  bool _initialized = false;

  bool get isInitialized => _initialized;

  bool get hasRemuxPlugin => _pluginLibraryPaths.isNotEmpty;

  List<BiliOfflineDownloadEntry> get entries {
    final tasks = _snapshot.tasks;
    final result = _metadataByAssetId.values
        .map((metadata) {
          final task = _taskForMetadata(metadata, tasks);
          return BiliOfflineDownloadEntry(metadata: metadata, task: task);
        })
        .toList(growable: false);
    result.sort(
      (left, right) =>
          right.metadata.createdAtMs.compareTo(left.metadata.createdAtMs),
    );
    return result;
  }

  List<BiliOfflineDownloadEntry> get activeEntries =>
      entries.where((entry) => entry.isActive).toList(growable: false);

  Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }
    final initializing = _initializing;
    if (initializing != null) {
      return initializing;
    }
    final next = _doInitialize().whenComplete(() {
      if (!_initialized) {
        _initializing = null;
      }
    });
    _initializing = next;
    return next;
  }

  Future<BiliDownloadOptions> resolveOptions({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
  }) {
    _ensureAuthenticatedForOfflineCache(
      fallbackMessage: '请先登录 Bilibili 后再读取离线缓存清晰度。',
    );
    return _client.resolveDownloadOptions(detail: detail, page: page);
  }

  Future<BiliOfflineDownloadEntry> enqueueBiliPage({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required int qualityId,
    BiliVideoCodecPreference codecPreference =
        BiliVideoCodecPreference.automatic,
    BiliDownloadOptions? options,
  }) async {
    _ensureAuthenticatedForOfflineCache(
      fallbackMessage: '请先登录 Bilibili 后再使用离线缓存。',
    );
    await initialize();
    final manager = _manager;
    final cacheRoot = _cacheRoot;
    if (manager == null || cacheRoot == null) {
      throw const BiliOfflineDownloadException('离线缓存管理器未初始化。');
    }
    if (_pluginLibraryPaths.isEmpty) {
      throw const BiliOfflineDownloadException('缺少 MP4 合成插件，当前安装包无法生成离线 MP4。');
    }

    final resolvedOptions = await _client.resolveDownloadOptions(
      detail: detail,
      page: page,
    );
    final preview = _client.prepareDownloadAsset(
      options: resolvedOptions,
      qualityId: qualityId,
      codecPreference: codecPreference,
    );
    final existing = _metadataByAssetId[preview.assetId];
    final existingTask = existing == null
        ? null
        : _taskForMetadata(existing, manager.snapshot.tasks);
    if (existing != null &&
        (existing.errorMessage == null || existing.errorMessage!.isEmpty) &&
        existingTask != null &&
        existingTask.state != VesperDownloadState.failed &&
        existingTask.state != VesperDownloadState.removed) {
      if (existingTask.state == VesperDownloadState.paused) {
        await manager.resumeTask(existingTask.taskId);
      } else if (existingTask.state == VesperDownloadState.queued) {
        await manager.startTask(existingTask.taskId);
      }
      return BiliOfflineDownloadEntry(metadata: existing, task: existingTask);
    }

    if (existingTask != null) {
      await manager.removeTask(existingTask.taskId);
    } else {
      await _deleteAssetDirectory(cacheRoot, preview.assetId);
    }

    final assetDirectory = Directory(
      '${cacheRoot.path}/assets/${preview.assetId}',
    );
    final prepared = await _client.prepareVerifiedDownloadAsset(
      options: resolvedOptions,
      qualityId: qualityId,
      codecPreference: codecPreference,
      targetDirectory: assetDirectory.path,
    );
    _logPreparedAsset(prepared);
    final metadata = BiliOfflineDownloadMetadata(
      assetId: prepared.assetId,
      bvid: page.bvid ?? detail.bvid,
      cid: page.cid,
      videoTitle: detail.title,
      pageTitle: 'P${page.pageNumber} · ${page.title}',
      coverUrl: page.coverUrl ?? detail.coverUrl,
      qualityLabel: prepared.qualityLabel,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _metadataByAssetId[metadata.assetId] = metadata;
    await _persistMetadata();
    notifyListeners();

    int? taskId;
    try {
      taskId = await manager.createTask(
        assetId: prepared.assetId,
        source: prepared.source,
        profile: prepared.profile,
        assetIndex: prepared.assetIndex,
      );
    } catch (error) {
      final failed = metadata.copyWith(
        errorMessage: _formatDownloadError(error),
      );
      _metadataByAssetId[failed.assetId] = failed;
      await _persistMetadata();
      notifyListeners();
      throw BiliOfflineDownloadException(_formatDownloadError(error));
    }
    if (taskId == null) {
      final failed = metadata.copyWith(errorMessage: '创建缓存任务失败。');
      _metadataByAssetId[failed.assetId] = failed;
      await _persistMetadata();
      notifyListeners();
      throw const BiliOfflineDownloadException('创建缓存任务失败。');
    }
    final updated = metadata.copyWith(taskId: taskId, clearError: true);
    _metadataByAssetId[updated.assetId] = updated;
    await _persistMetadata();
    final started = await manager.startTask(taskId);
    if (!started) {
      final failed = updated.copyWith(errorMessage: '启动缓存任务失败。');
      _metadataByAssetId[failed.assetId] = failed;
      await _persistMetadata();
      notifyListeners();
      throw const BiliOfflineDownloadException('启动缓存任务失败。');
    }
    await manager.refresh();
    _snapshot = manager.snapshot;
    _logDownloadSnapshot(_snapshot);
    _reconcileMetadataWithSnapshot(_snapshot);
    notifyListeners();
    return BiliOfflineDownloadEntry(
      metadata: updated,
      task: _taskForMetadata(updated, _snapshot.tasks),
    );
  }

  Future<BiliOfflineStorageUsage> resolveStorageUsage() async {
    await initialize();
    final cacheRoot = _cacheRoot;
    if (cacheRoot == null) {
      throw const BiliOfflineDownloadException('离线缓存目录未初始化。');
    }

    final cacheBytes = await _directorySize(cacheRoot);
    try {
      final storage = await resolveBiliDeviceStorageSpace();
      return BiliOfflineStorageUsage(
        cacheBytes: cacheBytes,
        freeBytes: storage.freeBytes,
        totalBytes: storage.totalBytes,
      );
    } on MissingPluginException {
      throw const BiliOfflineDownloadException('无法读取设备存储空间。');
    } on PlatformException catch (_) {
      throw const BiliOfflineDownloadException('无法读取设备存储空间。');
    }
  }

  Future<void> pause(int taskId) async {
    await initialize();
    await _manager?.pauseTask(taskId);
  }

  Future<void> pauseAllActive() async {
    await initialize();
    final manager = _manager;
    if (manager == null) {
      return;
    }

    final taskIds = manager.snapshot.tasks
        .where(_shouldPauseForLogout)
        .map((task) => task.taskId)
        .toSet()
        .toList(growable: false);
    for (final taskId in taskIds) {
      await manager.pauseTask(taskId);
    }
    await manager.refresh();
    _snapshot = manager.snapshot;
    _reconcileMetadataWithSnapshot(_snapshot);
    notifyListeners();
  }

  Future<void> resume(int taskId) async {
    _ensureAuthenticatedForOfflineCache(
      fallbackMessage: '已退出登录，请重新登录后再继续离线缓存。',
    );
    await initialize();
    await _manager?.resumeTask(taskId);
  }

  Future<void> startOrResume(int taskId) async {
    _ensureAuthenticatedForOfflineCache(
      fallbackMessage: '已退出登录，请重新登录后再继续离线缓存。',
    );
    await initialize();
    final manager = _manager;
    final task = manager?.task(taskId);
    switch (task?.state) {
      case VesperDownloadState.queued:
        await manager?.startTask(taskId);
      case VesperDownloadState.paused:
        await manager?.resumeTask(taskId);
      case VesperDownloadState.preparing:
      case VesperDownloadState.downloading:
      case VesperDownloadState.completed:
      case VesperDownloadState.failed:
      case VesperDownloadState.removed:
      case null:
        break;
    }
  }

  Future<void> remove(int taskId) async {
    await initialize();
    await _manager?.removeTask(taskId);
    _metadataByAssetId.removeWhere((_, metadata) => metadata.taskId == taskId);
    await _persistMetadata();
    notifyListeners();
  }

  Future<void> removeEntry(BiliOfflineDownloadEntry entry) async {
    await initialize();
    final taskId = entry.task?.taskId ?? entry.metadata.taskId;
    if (taskId != null) {
      await _manager?.removeTask(taskId);
    } else {
      await _deleteAssetDirectoryForMetadata(entry.metadata);
    }
    _metadataByAssetId.remove(entry.metadata.assetId);
    await _persistMetadata();
    notifyListeners();
  }

  Future<void> _doInitialize() async {
    final entries = await _store.loadEntries();
    _metadataByAssetId
      ..clear()
      ..addEntries(entries.map((entry) => MapEntry(entry.assetId, entry)));

    final root = await resolveBiliStorageDirectory();
    final cacheRoot = Directory('${root.path}/offline-cache');
    await cacheRoot.create(recursive: true);
    _cacheRoot = cacheRoot;
    _pluginLibraryPaths = await _pluginResolver
        .bundledDownloadPluginLibraryPaths();

    final manager =
        _manager ??
        await VesperDownloadManager.create(
          configuration: VesperDownloadConfiguration(
            baseDirectory: cacheRoot.path,
            pluginLibraryPaths: _pluginLibraryPaths,
            runPostProcessorsOnCompletion: true,
            restoreTasksOnStartup: true,
            resumePartialDownloads: true,
          ),
          staleResourceRecovery: _recoverStaleDownloadPlan,
        );
    _manager = manager;
    _snapshot = manager.snapshot;
    _snapshotSubscription = manager.snapshots.listen((snapshot) {
      _snapshot = snapshot;
      _logDownloadSnapshot(snapshot);
      _reconcileMetadataWithSnapshot(snapshot);
      unawaited(_persistMetadata());
      notifyListeners();
    });
    _reconcileMetadataWithSnapshot(_snapshot);
    _logDownloadSnapshot(_snapshot);
    await _persistMetadata();
    _initialized = true;
    notifyListeners();
  }

  VesperDownloadTaskSnapshot? _taskForMetadata(
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

  bool _shouldPauseForLogout(VesperDownloadTaskSnapshot task) {
    return switch (task.state) {
      VesperDownloadState.queued ||
      VesperDownloadState.preparing ||
      VesperDownloadState.downloading => true,
      VesperDownloadState.paused ||
      VesperDownloadState.completed ||
      VesperDownloadState.failed ||
      VesperDownloadState.removed => false,
    };
  }

  void _ensureAuthenticatedForOfflineCache({required String fallbackMessage}) {
    if (!_client.hasAuthenticatedSession) {
      throw BiliOfflineDownloadException(fallbackMessage);
    }
  }

  void _reconcileMetadataWithSnapshot(VesperDownloadSnapshot snapshot) {
    var changed = false;
    for (final task in snapshot.tasks) {
      final metadata = _metadataByAssetId[task.assetId];
      if (metadata == null) {
        continue;
      }
      final completedPath = task.assetIndex.completedPath;
      final errorMessage = task.error?.message;
      final updated = metadata.copyWith(
        taskId: task.taskId,
        outputPath: completedPath == null || completedPath.isEmpty
            ? null
            : completedPath,
        errorMessage: errorMessage,
        clearError: errorMessage == null,
      );
      if (updated.taskId != metadata.taskId ||
          updated.outputPath != metadata.outputPath ||
          updated.errorMessage != metadata.errorMessage) {
        _metadataByAssetId[updated.assetId] = updated;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> _persistMetadata() {
    final snapshot = List<BiliOfflineDownloadMetadata>.of(
      _metadataByAssetId.values,
    );
    _metadataWriteChain = _metadataWriteChain.then(
      (_) => _store.saveEntries(snapshot),
      onError: (_) => _store.saveEntries(snapshot),
    );
    return _metadataWriteChain;
  }

  Future<void> _deleteAssetDirectory(
    Directory cacheRoot,
    String assetId,
  ) async {
    final assetDirectory = Directory('${cacheRoot.path}/assets/$assetId');
    if (await assetDirectory.exists()) {
      await assetDirectory.delete(recursive: true);
    }
  }

  Future<void> _deleteAssetDirectoryForMetadata(
    BiliOfflineDownloadMetadata metadata,
  ) async {
    final cacheRoot = _cacheRoot;
    if (cacheRoot != null) {
      await _deleteAssetDirectory(cacheRoot, metadata.assetId);
    }
    final outputPath = metadata.outputPath;
    if (outputPath == null || outputPath.isEmpty) {
      return;
    }
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      await outputFile.delete();
      return;
    }
    final outputDirectory = Directory(outputPath);
    if (await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          continue;
        }
      }
    }
    return total;
  }

  String _formatDownloadError(Object error) {
    final message = error.toString();
    if (_isStaleDownloadError(message)) {
      return '缓存资源链接已过期或被拒绝，请重新打开页面后再试。';
    }
    return message;
  }

  bool _isStaleDownloadError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('stale or expired') ||
        lower.contains('http 401') ||
        lower.contains('http 403') ||
        lower.contains('http 404') ||
        lower.contains('http 410');
  }

  @override
  void dispose() {
    unawaited(_snapshotSubscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  void _logPreparedAsset(BiliPreparedDownloadAsset prepared) {
    debugPrint(
      '[BiliOffline] create asset=${prepared.assetId} '
      'quality=${prepared.qualityLabel} target=${prepared.profile.targetDirectory ?? ''} '
      'total=${prepared.assetIndex.totalSizeBytes ?? 0}',
    );
    debugPrint(
      '[BiliOffline] headers ${_summarizeHeaders(prepared.source.source.headers)}',
    );
    for (final resource in prepared.assetIndex.resources) {
      final byteRange = resource.byteRange;
      debugPrint(
        '[BiliOffline] resource ${resource.resourceId} '
        'size=${resource.sizeBytes ?? 0} '
        'range=${byteRange == null ? 'none' : '${byteRange.offset}+${byteRange.length}'} '
        'path=${resource.relativePath ?? ''} '
        'generated=${resource.generatedText != null} '
        'uri=${resource.uri}',
      );
    }
    for (final segment in prepared.assetIndex.segments) {
      final byteRange = segment.byteRange;
      debugPrint(
        '[BiliOffline] segment ${segment.segmentId} '
        'size=${segment.sizeBytes ?? 0} '
        'range=${byteRange == null ? 'none' : '${byteRange.offset}+${byteRange.length}'} '
        'path=${segment.relativePath ?? ''} uri=${segment.uri}',
      );
    }
  }

  String _summarizeHeaders(Map<String, String> headers) {
    if (headers.isEmpty) {
      return 'none';
    }
    final normalized = <String, String>{
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
    String valueFor(String name) {
      final value = normalized[name.toLowerCase()];
      if (value == null || value.isEmpty) {
        return '$name=missing';
      }
      if (name.toLowerCase() == 'cookie') {
        return '$name=len${value.length}';
      }
      return '$name=$value';
    }

    return <String>[
      valueFor('User-Agent'),
      valueFor('Referer'),
      valueFor('Origin'),
      valueFor('Accept'),
      valueFor('Cookie'),
    ].join(',');
  }

  void _logDownloadSnapshot(VesperDownloadSnapshot snapshot) {
    for (final task in snapshot.tasks) {
      final error = task.error?.message ?? '';
      final fingerprint =
          '${task.state.name}|${task.progress.receivedBytes}|'
          '${task.progress.totalBytes ?? 0}|${task.assetIndex.completedPath ?? ''}|$error';
      if (_lastTaskLogFingerprints[task.taskId] == fingerprint) {
        continue;
      }
      _lastTaskLogFingerprints[task.taskId] = fingerprint;
      debugPrint(
        '[BiliOffline] task=${task.taskId} asset=${task.assetId} '
        'state=${task.state.name} progress=${task.progress.receivedBytes}/'
        '${task.progress.totalBytes ?? 0} completed=${task.assetIndex.completedPath ?? ''}'
        '${error.isEmpty ? '' : ' error=$error'}',
      );
    }
  }

  static int? _qualityIdFromAssetId(String assetId) {
    final match = RegExp(r'-q(\d+)-').firstMatch(assetId);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  static BiliVideoCodecPreference _codecPreferenceFromAssetId(String assetId) {
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

  Future<VesperDownloadRecoveredTaskPlan?> _recoverStaleDownloadPlan(
    VesperDownloadTaskSnapshot task,
    VesperDownloadStaleResource staleResource,
  ) async {
    try {
      final assetId = task.assetId;
      final metadata = _metadataByAssetId[assetId];
      if (metadata == null) {
        debugPrint(
          '[BiliOffline] stale recovery: no metadata for assetId=$assetId',
        );
        return null;
      }

      final qualityId = _qualityIdFromAssetId(assetId);
      if (qualityId == null) {
        debugPrint(
          '[BiliOffline] stale recovery: cannot parse qualityId '
          'from assetId=$assetId',
        );
        return null;
      }

      final codecPreference = _codecPreferenceFromAssetId(assetId);
      final detail = await _client.fetchVideoDetail(metadata.bvid);
      final page = detail.pages.firstWhere(
        (page) => page.cid == metadata.cid,
        orElse: () => detail.pages.first,
      );

      final options = await _client.resolveDownloadOptions(
        detail: detail,
        page: page,
      );

      final prepared = await _client.prepareVerifiedDownloadAsset(
        options: options,
        qualityId: qualityId,
        codecPreference: codecPreference,
        targetDirectory: '${_cacheRoot?.path ?? ''}/assets/$assetId',
      );

      debugPrint(
        '[BiliOffline] stale recovery: refreshed assetId=$assetId '
        'taskId=${task.taskId}',
      );

      return VesperDownloadRecoveredTaskPlan(
        source: prepared.source,
        profile: prepared.profile,
        assetIndex: prepared.assetIndex,
      );
    } catch (error) {
      debugPrint('[BiliOffline] stale recovery failed: $error');
      return null;
    }
  }
}
