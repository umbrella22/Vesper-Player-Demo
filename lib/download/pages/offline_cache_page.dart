import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:signals/signals_flutter.dart';

import 'package:bilibili_player/app/design/app_glass_controls.dart';
import 'package:bilibili_player/app/design/app_visual_theme.dart';
import 'package:bilibili_player/bili/common/widgets/bili_glass_sheet.dart';
import '../../bili/common/pages/bili_playback_page.dart';
import '../../bili/common/services/bili_client.dart';
import '../../bili/common/services/bili_history_store.dart';
import '../models/offline_download_models.dart';
import '../services/offline_download_controller.dart';
import '../view_models/offline_cache_view_model.dart';
import '../widgets/offline_cache_widgets.dart';

enum _OfflineEntryAction { delete, export }

class OfflineCachePage extends StatefulWidget {
  const OfflineCachePage({
    super.key,
    this.controller,
    this.client,
    this.historyStore,
  });

  final BiliOfflineDownloadController? controller;
  final BiliClient? client;
  final BiliHistoryStore? historyStore;

  @override
  State<OfflineCachePage> createState() => _OfflineCachePageState();
}

class _OfflineCachePageState extends State<OfflineCachePage> {
  late final OfflineCacheViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = OfflineCacheViewModel(
      controller: widget.controller,
      client: widget.client,
      historyStore: widget.historyStore,
    );
    unawaited(_viewModel.initialize());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassScaffold(
      backgroundColor: AppVisualTokens.mobileBackground,
      extendBody: false,
      appBar: const GlassAppBar(
        centerTitle: false,
        title: Text('离线缓存', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          SignalBuilder(builder: _buildStatusSummary),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _viewModel.reload,
              child: SignalBuilder(builder: _buildEntryList),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSummary(BuildContext context) {
    final errorMessage = _viewModel.errorMessage.value;
    final storageUsage = _viewModel.storageUsage.value;
    final storageErrorMessage = _viewModel.storageErrorMessage.value;
    final invalidEntries = _viewModel.invalidEntries.value;
    if (errorMessage == null &&
        storageUsage == null &&
        storageErrorMessage == null &&
        invalidEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Column(
        children: [
          if (invalidEntries.isNotEmpty) ...[
            OfflineInvalidCacheSummary(
              count: invalidEntries.length,
              onCleanup: _confirmCleanupInvalidEntries,
            ),
            const SizedBox(height: 10),
          ],
          if (errorMessage != null) ...[
            OfflineInlineError(
              message: errorMessage,
              onRetry: _viewModel.reload,
            ),
            const SizedBox(height: 14),
          ],
          if (storageUsage != null || storageErrorMessage != null)
            OfflineStorageSummary(
              usage: storageUsage,
              loading: _viewModel.storageLoading.value,
              errorMessage: storageErrorMessage,
            ),
        ],
      ),
    );
  }

  Widget _buildEntryList(BuildContext context) {
    final entries = _viewModel.entries.value;
    final active = _viewModel.activeEntries.value;
    final completed = _viewModel.completedEntries.value;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
      children: [
        if (_viewModel.loading.value && entries.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (entries.isEmpty)
          const OfflineEmptyState()
        else ...[
          if (active.isNotEmpty) ...[
            const OfflineSectionHeader(title: '正在缓存'),
            const SizedBox(height: 8),
            _OfflineEntrySignalGroup(
              entries: active,
              viewModel: _viewModel,
              onOpen: _openEntry,
              onDelete: _deleteEntry,
              onToggleTask: _toggleTaskCaching,
              onMoreTap: _showEntryActions,
            ),
            const SizedBox(height: 18),
          ],
          if (completed.isNotEmpty) ...[
            const OfflineSectionHeader(title: '离线视频'),
            const SizedBox(height: 8),
            _OfflineEntrySignalGroup(
              entries: completed,
              viewModel: _viewModel,
              onOpen: _openEntry,
              onDelete: _deleteEntry,
              onToggleTask: _toggleTaskCaching,
              onMoreTap: _showEntryActions,
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _openEntry(BiliOfflineDownloadEntry entry) async {
    if (entry.isUnplayable) {
      await _confirmDeleteInvalidEntry(entry);
      return;
    }
    try {
      final result = await _viewModel.openEntry(entry);
      if (!mounted || result == null) {
        return;
      }
      final message = result.message;
      if (message != null && message.isNotEmpty) {
        _showMessage(message);
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BiliPlaybackPage(
            detail: result.detail,
            initialPage: result.page,
            client: _viewModel.client,
            historyStore: _viewModel.historyStore,
            offlineController: _viewModel.controller,
            initialResolvedPlayback: result.initialResolvedPlayback,
          ),
        ),
      );
    } on BiliInvalidOfflineCacheException catch (error) {
      if (mounted) {
        await _confirmDeleteInvalidEntry(entry, reason: error.message);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('打开视频失败：$error');
      }
    }
  }

  Future<bool> _deleteEntry(BiliOfflineDownloadEntry entry) async {
    final result = await _viewModel.deleteEntry(entry);
    if (mounted && result.message.isNotEmpty) {
      _showMessage(result.message);
    }
    return result.deleted;
  }

  Future<void> _toggleTaskCaching(BiliOfflineDownloadEntry entry) async {
    try {
      await _viewModel.toggleTaskCaching(entry);
    } catch (error) {
      if (mounted) {
        _showMessage('缓存操作失败：$error');
      }
    }
  }

  Future<void> _showEntryActions(BiliOfflineDownloadEntry entry) async {
    final canExport = entry.isCompleted && !entry.isUnplayable;
    final action = await showBiliGlassSheet<_OfflineEntryAction>(
      context: context,
      maxContentHeightFactor: 0.5,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('导出到相册'),
                  subtitle: const Text('导出为可在任意播放器中播放的 MP4'),
                  enabled: canExport,
                  onTap: canExport
                      ? () => Navigator.of(
                          context,
                        ).pop(_OfflineEntryAction.export)
                      : null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  textColor: const Color(0xFFE84A67),
                  iconColor: const Color(0xFFE84A67),
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('删除'),
                  onTap: () =>
                      Navigator.of(context).pop(_OfflineEntryAction.delete),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _OfflineEntryAction.delete:
        await _deleteEntry(entry);
      case _OfflineEntryAction.export:
        await _exportEntry(entry);
    }
  }

  Future<void> _confirmDeleteInvalidEntry(
    BiliOfflineDownloadEntry entry, {
    String? reason,
  }) async {
    final shouldDelete = await showBiliGlassDialog<bool>(
      context: context,
      title: '缓存无法播放',
      message: '${reason ?? entry.unplayableReason}\n\n是否清理这条失效缓存？',
      actions: const [
        BiliGlassDialogAction(label: '保留', value: false),
        BiliGlassDialogAction(label: '清理', value: true, isDestructive: true),
      ],
    );
    if (shouldDelete == true && mounted) {
      await _deleteEntry(entry);
    }
  }

  Future<void> _confirmCleanupInvalidEntries() async {
    final count = _viewModel.invalidEntries.value.length;
    if (count == 0) {
      return;
    }
    final shouldDelete = await showBiliGlassDialog<bool>(
      context: context,
      title: '清理失效缓存？',
      message: '发现 $count 条缓存的视频信息已丢失，这些缓存无法播放。清理后不可恢复。',
      actions: const [
        BiliGlassDialogAction(label: '取消', value: false),
        BiliGlassDialogAction(
          label: '清理失效缓存',
          value: true,
          isDestructive: true,
        ),
      ],
    );
    if (shouldDelete != true || !mounted) {
      return;
    }
    final result = await _viewModel.cleanupInvalidEntries();
    if (mounted) {
      _showMessage(result.message);
    }
  }

  Future<void> _exportEntry(BiliOfflineDownloadEntry entry) async {
    final result = await _viewModel.exportEntry(entry);
    if (mounted && result.message.isNotEmpty) {
      _showMessage(result.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OfflineEntrySignalGroup extends StatelessWidget {
  const _OfflineEntrySignalGroup({
    required this.entries,
    required this.viewModel,
    required this.onOpen,
    required this.onDelete,
    required this.onToggleTask,
    required this.onMoreTap,
  });

  final List<BiliOfflineDownloadEntry> entries;
  final OfflineCacheViewModel viewModel;
  final void Function(BiliOfflineDownloadEntry entry) onOpen;
  final Future<bool> Function(BiliOfflineDownloadEntry entry) onDelete;
  final Future<void> Function(BiliOfflineDownloadEntry entry) onToggleTask;
  final void Function(BiliOfflineDownloadEntry entry) onMoreTap;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        return OfflineEntryGroup(
          entries: entries,
          onOpen: onOpen,
          onDelete: onDelete,
          onToggleTask: onToggleTask,
          onMoreTap: onMoreTap,
          openingAssetIds: viewModel.openingAssetIds.value,
          deletingAssetIds: viewModel.deletingAssetIds.value,
          exportingAssetIds: viewModel.exportingAssetIds.value,
          taskActionTaskIds: viewModel.taskActionTaskIds.value,
        );
      },
    );
  }
}
