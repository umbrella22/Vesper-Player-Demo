import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '离线缓存',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
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
    if (errorMessage == null &&
        storageUsage == null &&
        storageErrorMessage == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Column(
        children: [
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
    final canExport = entry.isCompleted;
    final action = await showModalBottomSheet<_OfflineEntryAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
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
