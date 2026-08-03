import 'package:vesper_player/vesper_player.dart';

/// 离线下载控制器对下载管理器的最小依赖面。
///
/// SDK 的 [VesperDownloadManager] 构造是私有的，测试无法替身；控制器改为
/// 依赖本接口后，删除与释放路径可以在不触碰平台通道的前提下注入替身验证
/// 行为（例如 removeTask 返回 false、dispose 重新抛出平台错误）。
abstract interface class BiliDownloadManagerHost {
  Future<int?> createTask({
    required String assetId,
    required VesperDownloadSource source,
    VesperDownloadProfile profile = const VesperDownloadProfile(),
    VesperDownloadAssetIndex assetIndex = const VesperDownloadAssetIndex(),
  });

  Future<bool> removeTask(int taskId);

  Future<bool> pauseTask(int taskId);

  Future<bool> resumeTask(int taskId);

  Future<bool> startTask(int taskId);

  Future<void> refresh();

  /// 释放下载管理器；实现可能重新抛出平台释放错误。
  Future<void> dispose();

  /// 返回任务快照；任务不存在时返回 null。
  VesperDownloadTaskSnapshot? task(int taskId);

  VesperDownloadSnapshot get snapshot;

  Stream<VesperDownloadSnapshot> get snapshots;
}

/// 将 [VesperDownloadManager] 包装为 [BiliDownloadManagerHost]。
final class VesperDownloadManagerAdapter implements BiliDownloadManagerHost {
  const VesperDownloadManagerAdapter(this._manager);

  final VesperDownloadManager _manager;

  @override
  Future<int?> createTask({
    required String assetId,
    required VesperDownloadSource source,
    VesperDownloadProfile profile = const VesperDownloadProfile(),
    VesperDownloadAssetIndex assetIndex = const VesperDownloadAssetIndex(),
  }) {
    return _manager.createTask(
      assetId: assetId,
      source: source,
      profile: profile,
      assetIndex: assetIndex,
    );
  }

  @override
  Future<bool> removeTask(int taskId) => _manager.removeTask(taskId);

  @override
  Future<bool> pauseTask(int taskId) => _manager.pauseTask(taskId);

  @override
  Future<bool> resumeTask(int taskId) => _manager.resumeTask(taskId);

  @override
  Future<bool> startTask(int taskId) => _manager.startTask(taskId);

  @override
  Future<void> refresh() => _manager.refresh();

  @override
  Future<void> dispose() => _manager.dispose();

  @override
  VesperDownloadTaskSnapshot? task(int taskId) => _manager.task(taskId);

  @override
  VesperDownloadSnapshot get snapshot => _manager.snapshot;

  @override
  Stream<VesperDownloadSnapshot> get snapshots => _manager.snapshots;
}
