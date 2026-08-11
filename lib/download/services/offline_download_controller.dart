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
import 'offline_cache_inventory.dart';
import 'download_manager_host.dart';
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
    required this._client,
    this._store = const BiliOfflineDownloadStore(),
    this._pluginResolver = const BiliDownloadPluginResolver(),
    this._manager,
  });

  static final BiliOfflineDownloadController instance =
      BiliOfflineDownloadController(client: BiliClient.instance);

  final BiliClient _client;
  final BiliOfflineDownloadStore _store;
  final BiliDownloadPluginResolver _pluginResolver;
  final Map<String, BiliOfflineDownloadMetadata> _metadataByAssetId =
      <String, BiliOfflineDownloadMetadata>{};
  // Cache directories and SDK tasks can outlive the app-owned metadata file.
  // Keep an inventory of those directories so they can be shown and removed.
  final Map<String, String> _orphanAssetDirectories = <String, String>{};
  final Map<String, String> _metadataIntegrityErrors = <String, String>{};

  BiliDownloadManagerHost? _manager;
  VesperDownloadSnapshot _snapshot = const VesperDownloadSnapshot.initial();
  StreamSubscription<VesperDownloadSnapshot>? _snapshotSubscription;
  Directory? _cacheRoot;
  List<VesperPluginReference> _postDownloadPluginReferences =
      const <VesperPluginReference>[];
  final Map<int, String> _lastTaskLogFingerprints = <int, String>{};
  Future<void>? _initializing;
  Future<void> _metadataWriteChain = Future<void>.value();
  Timer? _metadataPersistDebounce;
  DateTime _lastIntegrityRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _integrityRefreshGeneration = 0;
  bool _initialized = false;
  bool _disposed = false;

  /// SDK emits download snapshots at `minProgressIntervalMs` (250ms), i.e. up
  /// to ~4 writes/sec while a task is downloading. Debounce metadata writes so
  /// the whole JSON is not rewritten on every progress tick; a trailing write
  /// still lands shortly after the last snapshot. Explicit user actions
  /// (enqueue/remove/rename) bypass this via [_persistMetadata] directly.
  static const Duration _metadataPersistDebounceInterval = Duration(
    milliseconds: 1500,
  );

  /// Integrity probing walks every completed entry's output on disk. Throttle
  /// it to a once-per-interval cadence; a just-completed task shows up within
  /// one interval, and the play path re-validates the file in real time.
  static const Duration _integrityRefreshMinInterval = Duration(seconds: 5);

  bool get isInitialized => _initialized && !_disposed;

  bool get hasRemuxPlugin => _postDownloadPluginReferences.isNotEmpty;

  List<BiliOfflineDownloadEntry> get entries {
    return BiliOfflineCacheInventory.build(
      metadata: _metadataByAssetId.values,
      snapshot: _snapshot,
      orphanAssetDirectories: _orphanAssetDirectories,
      metadataIntegrityErrors: _metadataIntegrityErrors,
    );
  }

  List<BiliOfflineDownloadEntry> get activeEntries =>
      entries.where((entry) => entry.isActive).toList(growable: false);

  Future<void> initialize() {
    if (_disposed) {
      // A disposed controller must not re-initialize: the download manager,
      // snapshot subscription, and metadata write chain were torn down.
      throw StateError('BiliOfflineDownloadController has been disposed.');
    }
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
    if (_postDownloadPluginReferences.isEmpty) {
      throw const BiliOfflineDownloadException('缺少 MP4 合成插件，当前安装包无法生成离线 MP4。');
    }

    // Reuse the caller-provided options when they were resolved for this same
    // page (the download panel passes the manifest it already fetched), so a
    // collection enqueue does not re-fetch the DASH manifest and re-probe
    // every media URL per episode. Fall back to a fresh resolve otherwise.
    final BiliDownloadOptions resolvedOptions;
    if (options != null && options.cid == page.cid) {
      resolvedOptions = options;
    } else {
      resolvedOptions = await _client.resolveDownloadOptions(
        detail: detail,
        page: page,
      );
    }
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
      // 与 remove()/removeEntry() 一致：SDK 任务存在但删除失败时不能继续
      // 对同一 asset 重建任务——旧任务可能仍在运行或占用输出。
      final removed = await manager.removeTask(existingTask.taskId);
      if (!removed) {
        throw const BiliOfflineDownloadException('缓存任务删除失败，请稍后重试。');
      }
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
    _metadataIntegrityErrors.remove(metadata.assetId);
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

  /// Resolves a completed cache file only when it remains inside this
  /// controller's cache root. Persisted SDK/app paths are untrusted input: a
  /// damaged metadata record must not turn playback or export into arbitrary
  /// file access.
  Future<String?> resolvePlayableCachePath(
    BiliOfflineDownloadEntry entry,
  ) async {
    await initialize();
    final cacheRoot = _cacheRoot;
    if (cacheRoot == null) {
      return null;
    }
    return resolveBiliOfflineCachePathWithinRoot(
      cacheRoot: cacheRoot,
      candidates: <String>{
        ?entry.metadata.outputPath,
        ?entry.task?.assetIndex.completedPath,
        if (_isSafeAssetId(entry.metadata.assetId))
          '${cacheRoot.path}/assets/${entry.metadata.assetId}',
        if (entry.task?.assetId case final String taskAssetId
            when _isSafeAssetId(taskAssetId))
          '${cacheRoot.path}/assets/$taskAssetId',
      },
    );
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
      case VesperDownloadState.unknown:
      case null:
        break;
    }
  }

  Future<void> remove(int taskId) async {
    await initialize();
    final matchingEntries = entries
        .where(
          (entry) =>
              entry.task?.taskId == taskId || entry.metadata.taskId == taskId,
        )
        .toList(growable: false);
    final matchingAssetIds = matchingEntries
        .map((entry) => entry.metadata.assetId)
        .toSet();
    final manager = _manager;
    // SDK 任务不存在时（孤儿元数据）直接清理本地；任务存在但 SDK 删除失败
    // 时保留目录与元数据，并让调用方报告失败而不是"已删除"。
    if (manager != null && manager.task(taskId) != null) {
      final removed = await manager.removeTask(taskId);
      if (!removed) {
        throw const BiliOfflineDownloadException('缓存任务删除失败，请稍后重试。');
      }
    }
    for (final entry in matchingEntries) {
      await _deleteAssetDirectoryForMetadata(
        entry.metadata,
        assetId: entry.task?.assetId,
      );
      _orphanAssetDirectories.remove(entry.metadata.assetId);
      if (entry.task?.assetId case final assetId?) {
        _orphanAssetDirectories.remove(assetId);
      }
    }
    _metadataByAssetId.removeWhere(
      (assetId, metadata) =>
          matchingAssetIds.contains(assetId) || metadata.taskId == taskId,
    );
    _metadataIntegrityErrors.removeWhere(
      (assetId, _) => matchingAssetIds.contains(assetId),
    );
    await _persistMetadata();
    notifyListeners();
  }

  Future<void> removeEntry(BiliOfflineDownloadEntry entry) async {
    await initialize();
    final taskId = entry.task?.taskId ?? entry.metadata.taskId;
    final manager = _manager;
    // 与 remove() 一致：SDK 任务存在但删除失败时不删本地、不报成功。
    if (taskId != null && manager != null && manager.task(taskId) != null) {
      final removed = await manager.removeTask(taskId);
      if (!removed) {
        throw const BiliOfflineDownloadException('缓存任务删除失败，请稍后重试。');
      }
    }
    // The SDK normally removes task output, but an orphan task may have no
    // metadata path for the SDK to clean. Delete both the canonical asset
    // directory and any recorded output path regardless of task state.
    await _deleteAssetDirectoryForMetadata(
      entry.metadata,
      assetId: entry.task?.assetId,
    );
    _metadataByAssetId.remove(entry.metadata.assetId);
    _metadataIntegrityErrors.remove(entry.metadata.assetId);
    _orphanAssetDirectories.remove(entry.metadata.assetId);
    if (entry.task?.assetId case final taskAssetId?) {
      _orphanAssetDirectories.remove(taskAssetId);
    }
    await _persistMetadata();
    notifyListeners();
  }

  /// Re-scans the on-disk cache inventory after an external deletion or a
  /// metadata migration. This is intentionally separate from SDK refresh so a
  /// failed network refresh cannot hide local cleanup candidates.
  Future<void> refreshCacheInventory() async {
    await initialize();
    await _scanOrphanAssetDirectories();
    await _refreshMetadataIntegrity();
    notifyListeners();
  }

  Future<void> _doInitialize() async {
    final entries = await _store.loadEntries();
    _ensureNotDisposedDuringInitialize();
    _metadataByAssetId
      ..clear()
      ..addEntries(entries.map((entry) => MapEntry(entry.assetId, entry)));

    final root = await resolveBiliStorageDirectory();
    final cacheRoot = Directory('${root.path}/offline-cache');
    await cacheRoot.create(recursive: true);
    _ensureNotDisposedDuringInitialize();
    _cacheRoot = cacheRoot;
    _postDownloadPluginReferences = await _pluginResolver
        .bundledDownloadPluginReferences();
    _ensureNotDisposedDuringInitialize();

    var manager = _manager;
    if (manager == null) {
      VesperDownloadManagerAdapter created;
      try {
        created = await _createDownloadManager(
          cacheRoot: cacheRoot,
          postDownloadPluginReferences: _postDownloadPluginReferences,
        );
      } catch (_) {
        if (_postDownloadPluginReferences.isEmpty) {
          rethrow;
        }
        _postDownloadPluginReferences = const <VesperPluginReference>[];
        created = await _createDownloadManager(
          cacheRoot: cacheRoot,
          postDownloadPluginReferences: const <VesperPluginReference>[],
        );
      }
      // 原生 manager 已创建但初始化被 dispose 打断：销毁它而不是泄漏，
      // 再以 StateError 结束本次 initialize。
      if (_disposed) {
        unawaited(_disposeManagerSafely(created));
        throw StateError('BiliOfflineDownloadController has been disposed.');
      }
      manager = created;
    }
    _manager = manager;
    _snapshot = manager.snapshot;
    await _scanOrphanAssetDirectories();
    _ensureNotDisposedDuringInitialize();
    _snapshotSubscription = manager.snapshots.listen((snapshot) {
      if (_disposed) {
        return;
      }
      _snapshot = snapshot;
      _logDownloadSnapshot(snapshot);
      _reconcileMetadataWithSnapshot(snapshot);
      _schedulePersistMetadata();
      notifyListeners();
      unawaited(_refreshMetadataIntegrityAfterSnapshot());
    });
    _reconcileMetadataWithSnapshot(_snapshot);
    await _refreshMetadataIntegrity();
    _logDownloadSnapshot(_snapshot);
    await _persistMetadata();
    _ensureNotDisposedDuringInitialize();
    _initialized = true;
    notifyListeners();
  }

  Future<VesperDownloadManagerAdapter> _createDownloadManager({
    required Directory cacheRoot,
    required List<VesperPluginReference> postDownloadPluginReferences,
  }) async {
    return VesperDownloadManagerAdapter(
      await VesperDownloadManager.create(
        configuration: VesperDownloadConfiguration(
          baseDirectory: cacheRoot.path,
          postDownloadPluginReferences: postDownloadPluginReferences,
          runPostProcessorsOnCompletion: true,
          restoreTasksOnStartup: true,
          resumePartialDownloads: true,
        ),
        staleResourceRecovery: _recoverStaleDownloadPlan,
      ),
    );
  }

  /// Aborts [_doInitialize] when the controller was disposed while one of its
  /// awaits was pending: after dispose nothing may create the native manager,
  /// subscribe to snapshot streams, or call notifyListeners. The error also
  /// clears the shared [_initializing] future so a disposed controller cannot
  /// be re-initialized.
  void _ensureNotDisposedDuringInitialize() {
    if (_disposed) {
      throw StateError('BiliOfflineDownloadController has been disposed.');
    }
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
      VesperDownloadState.unknown ||
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
        clearOutputPath: completedPath == null || completedPath.isEmpty,
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

  /// Snapshot-driven persistence is debounced: SDK progress ticks arrive up
  /// to ~4/s while downloading, but metadata only changes meaningfully when a
  /// task transitions state, so merging ticks into one trailing write removes
  /// most of the write amplification. Direct user actions still call
  /// [_persistMetadata] immediately and wait on the write chain.
  void _schedulePersistMetadata() {
    _metadataPersistDebounce ??= Timer(_metadataPersistDebounceInterval, () {
      _metadataPersistDebounce = null;
      unawaited(
        _persistMetadata().then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            // 快照驱动的后台写盘失败不能静默丢弃，也不能成为未处理的异步
            // 错误：经 FlutterError 上报。显式用户操作路径（enqueue/remove
            // /rename）仍直接等待 _persistMetadata 并把错误抛给调用方。
            _reportBackgroundError(
              error,
              stackTrace,
              'persisting offline cache metadata',
            );
          },
        ),
      );
    });
  }

  Future<void> _deleteAssetDirectory(
    Directory cacheRoot,
    String assetId,
  ) async {
    if (!_isSafeAssetId(assetId)) {
      debugPrint('[BiliOffline] refusing unsafe asset id: $assetId');
      return;
    }
    final assetDirectory = Directory('${cacheRoot.path}/assets/$assetId');
    if (await assetDirectory.exists() &&
        await _isPathInsideCacheRoot(assetDirectory)) {
      await assetDirectory.delete(recursive: true);
    }
  }

  Future<void> _deleteAssetDirectoryForMetadata(
    BiliOfflineDownloadMetadata metadata, {
    String? assetId,
  }) async {
    final cacheRoot = _cacheRoot;
    if (cacheRoot != null) {
      for (final cleanupAssetId in biliOfflineCacheCleanupAssetIds(
        metadataAssetId: metadata.assetId,
        taskAssetId: assetId,
      )) {
        await _deleteAssetDirectory(cacheRoot, cleanupAssetId);
      }
    }
    final outputPath = metadata.outputPath;
    if (outputPath == null || outputPath.isEmpty) {
      return;
    }
    final outputFile = File(outputPath);
    if (await outputFile.exists() && await _isPathInsideCacheRoot(outputFile)) {
      await outputFile.delete();
      return;
    }
    final outputDirectory = Directory(outputPath);
    if (await outputDirectory.exists() &&
        await _isPathInsideCacheRoot(outputDirectory)) {
      await outputDirectory.delete(recursive: true);
    }
  }

  bool _isSafeAssetId(String assetId) {
    final value = assetId.trim();
    return value.isNotEmpty &&
        value != '.' &&
        value != '..' &&
        !value.contains('/') &&
        !value.contains('\\');
  }

  Future<bool> _isPathInsideCacheRoot(FileSystemEntity entity) async {
    final cacheRoot = _cacheRoot;
    if (cacheRoot == null) {
      return false;
    }
    return _isBiliOfflinePathInsideRoot(cacheRoot, entity);
  }

  Future<void> _scanOrphanAssetDirectories() async {
    final cacheRoot = _cacheRoot;
    if (cacheRoot == null) {
      return;
    }
    final assetsDirectory = Directory('${cacheRoot.path}/assets');
    if (!await assetsDirectory.exists()) {
      _orphanAssetDirectories.clear();
      return;
    }

    final discovered = <String, String>{};
    try {
      await for (final entity in assetsDirectory.list(
        followLinks: false,
        recursive: false,
      )) {
        if (entity is! Directory && entity is! File) {
          continue;
        }
        final segments = entity.uri.pathSegments;
        if (segments.isEmpty) {
          continue;
        }
        final assetId = segments.lastWhere(
          (segment) => segment.isNotEmpty && segment != '/',
          orElse: () => '',
        );
        if (assetId.isEmpty) {
          continue;
        }
        if (_metadataByAssetId.containsKey(assetId) ||
            _snapshot.tasks.any(
              (task) =>
                  task.state != VesperDownloadState.removed &&
                  task.assetId == assetId,
            )) {
          continue;
        }
        discovered[assetId] = entity.path;
      }
    } on FileSystemException catch (error) {
      // A transient directory permission/read error must not make the whole
      // offline page unusable. Keep the last known inventory and report it.
      debugPrint('[BiliOffline] cache inventory scan failed: $error');
      return;
    }
    _orphanAssetDirectories
      ..clear()
      ..addAll(discovered);
  }

  Future<void> _refreshMetadataIntegrity() async {
    final generation = ++_integrityRefreshGeneration;
    final cacheRoot = _cacheRoot;
    if (cacheRoot == null) {
      return;
    }
    final next = <String, String>{};
    final activeTasks = _snapshot.tasks
        .where((task) => task.state != VesperDownloadState.removed)
        .toList(growable: false);
    for (final metadata in _metadataByAssetId.values) {
      final task = _taskForMetadata(metadata, activeTasks);
      if (task != null &&
          task.assetId.isNotEmpty &&
          task.assetId != metadata.assetId) {
        // The synchronous inventory reports this identity mismatch. It does
        // not need a filesystem probe because neither asset can be trusted as
        // the content described by the other record.
        continue;
      }
      if (task != null && task.state != VesperDownloadState.completed) {
        continue;
      }
      final playablePath = await resolveBiliOfflineCachePathWithinRoot(
        cacheRoot: cacheRoot,
        candidates: <String>{
          ?metadata.outputPath,
          ?task?.assetIndex.completedPath,
          if (_isSafeAssetId(metadata.assetId))
            '${cacheRoot.path}/assets/${metadata.assetId}',
          if (task?.assetId case final String taskAssetId
              when _isSafeAssetId(taskAssetId))
            '${cacheRoot.path}/assets/$taskAssetId',
        },
      );
      if (playablePath == null) {
        next[metadata.assetId] = task == null
            ? '缓存任务和文件均已丢失，无法播放。请清理这条失效缓存。'
            : '缓存文件已丢失或不完整，无法播放。请清理这条失效缓存。';
      }
    }
    if (generation != _integrityRefreshGeneration) {
      return;
    }
    _metadataIntegrityErrors
      ..clear()
      ..addAll(next);
  }

  Future<void> _refreshMetadataIntegrityAfterSnapshot() async {
    // Throttle integrity probing: it stats every completed entry, and running
    // it on every 250ms snapshot while other tasks download is pure I/O churn.
    // A just-completed task becomes visible within one interval.
    final now = DateTime.now();
    if (now.difference(_lastIntegrityRefreshAt) <
        _integrityRefreshMinInterval) {
      return;
    }
    _lastIntegrityRefreshAt = now;
    try {
      await _refreshMetadataIntegrity();
      if (!_disposed) {
        notifyListeners();
      }
    } on FileSystemException catch (error) {
      debugPrint('[BiliOffline] cache integrity refresh failed: $error');
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
    _disposed = true;
    final pendingDebounce = _metadataPersistDebounce;
    _metadataPersistDebounce = null;
    if (pendingDebounce != null) {
      pendingDebounce.cancel();
      // Flush the trailing metadata write that the debounce would have
      // issued, so a dispose right after a snapshot does not drop the last
      // state transition. A failing flush is reported, not dropped.
      unawaited(_flushMetadataWriteSafely());
    }
    unawaited(_snapshotSubscription?.cancel() ?? Future<void>.value());
    _snapshotSubscription = null;
    // Release the native download manager (platform event subscription,
    // snapshot streams, task registry). SDK dispose() rethrows a platform
    // release error, which must be reported through FlutterError instead of
    // surfacing as an unhandled async error.
    final manager = _manager;
    _manager = null;
    if (manager != null) {
      unawaited(_disposeManagerSafely(manager));
    }
    super.dispose();
  }

  Future<void> _flushMetadataWriteSafely() async {
    try {
      await _persistMetadata();
    } catch (error, stackTrace) {
      _reportBackgroundError(error, stackTrace, 'flushing cached metadata');
    }
  }

  Future<void> _disposeManagerSafely(BiliDownloadManagerHost manager) async {
    try {
      await manager.dispose();
    } catch (error, stackTrace) {
      _reportBackgroundError(error, stackTrace, 'disposing download manager');
    }
  }

  void _reportBackgroundError(
    Object error,
    StackTrace stackTrace,
    String context,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'offline_download_controller',
        context: ErrorDescription(context),
      ),
    );
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

/// Resolves the first existing MP4 candidate that is a descendant of
/// [cacheRoot]. The helper is intentionally path-based so the containment
/// contract can be regression-tested without starting a native SDK manager.
@visibleForTesting
Future<String?> resolveBiliOfflineCachePathWithinRoot({
  required Directory cacheRoot,
  required Iterable<String> candidates,
}) async {
  for (final path in candidates) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      continue;
    }
    final file = File(normalizedPath);
    // The download profile is MP4-only.  Do not treat an in-root manifest,
    // subtitle, or temporary artifact as a playable completed cache.
    if (file.path.toLowerCase().endsWith('.mp4') &&
        await file.exists() &&
        await _isBiliOfflinePathInsideRoot(cacheRoot, file)) {
      return file.path;
    }

    final directory = Directory(normalizedPath);
    if (!await directory.exists() ||
        !await _isBiliOfflinePathInsideRoot(cacheRoot, directory)) {
      continue;
    }
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File ||
          !entity.path.toLowerCase().endsWith('.mp4') ||
          !await _isBiliOfflinePathInsideRoot(cacheRoot, entity)) {
        continue;
      }
      return entity.path;
    }
  }
  return null;
}

Future<bool> _isBiliOfflinePathInsideRoot(
  Directory cacheRoot,
  FileSystemEntity entity,
) async {
  try {
    final rootPath = await cacheRoot.resolveSymbolicLinks();
    final targetPath = await entity.resolveSymbolicLinks();
    final prefix = rootPath.endsWith(Platform.pathSeparator)
        ? rootPath
        : '$rootPath${Platform.pathSeparator}';
    // Never treat the cache root itself as a playable/deletable artifact.
    return targetPath.startsWith(prefix);
  } on FileSystemException {
    return false;
  }
}

/// Returns every canonical asset directory that may belong to a cache entry.
///
/// A restored SDK task can carry an asset ID that differs from stale app
/// metadata. Both IDs must be considered during deletion; otherwise one of
/// the directories is left behind and is rediscovered as an orphan later.
@visibleForTesting
Set<String> biliOfflineCacheCleanupAssetIds({
  required String metadataAssetId,
  String? taskAssetId,
}) {
  return <String>{
    if (metadataAssetId.trim().isNotEmpty) metadataAssetId,
    if (taskAssetId != null && taskAssetId.trim().isNotEmpty) taskAssetId,
  };
}
