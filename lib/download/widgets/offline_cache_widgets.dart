import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vesper_player/vesper_player.dart';

import '../models/offline_download_models.dart';
import '../models/offline_storage_models.dart';

class OfflineSectionHeader extends StatelessWidget {
  const OfflineSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: const Color(0xFF20232B),
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class OfflineStorageSummary extends StatelessWidget {
  const OfflineStorageSummary({
    super.key,
    required this.usage,
    required this.loading,
    required this.errorMessage,
  });

  final BiliOfflineStorageUsage? usage;
  final bool loading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final usage = this.usage;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.storage_rounded,
                  size: 18,
                  color: Color(0xFFFB7299),
                ),
                const SizedBox(width: 8),
                Text(
                  '存储空间',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF20232B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                if (loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (usage != null) ...[
              Row(
                children: [
                  Expanded(
                    child: OfflineStorageStat(
                      label: '缓存占用',
                      value: biliFormatDownloadBytes(usage.cacheBytes),
                      valueColor: const Color(0xFFFB7299),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OfflineStorageStat(
                      label: '剩余空间',
                      value: biliFormatDownloadBytes(usage.freeBytes),
                      valueColor: const Color(0xFF20232B),
                      alignRight: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 10,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xFFF0F2F6)),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: usage.cacheRatio
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(color: Color(0xFFFB7299)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ] else if (loading)
              const SizedBox(
                height: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    color: Color(0xFFFB7299),
                    backgroundColor: Color(0xFFF0F2F6),
                  ),
                ),
              )
            else if (errorMessage != null && errorMessage!.isNotEmpty)
              Text(
                '无法读取设备存储空间',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFD94868),
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (errorMessage != null && errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFD94868),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OfflineStorageStat extends StatelessWidget {
  const OfflineStorageStat({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
    this.alignRight = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final crossAxisAlignment = alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xFF7E8591),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class OfflineEntryGroup extends StatelessWidget {
  const OfflineEntryGroup({
    super.key,
    required this.entries,
    required this.onOpen,
    required this.onDelete,
    required this.onToggleTask,
    required this.onMoreTap,
    required this.openingAssetIds,
    required this.deletingAssetIds,
    required this.exportingAssetIds,
    required this.taskActionTaskIds,
  });

  final List<BiliOfflineDownloadEntry> entries;
  final void Function(BiliOfflineDownloadEntry entry) onOpen;
  final Future<bool> Function(BiliOfflineDownloadEntry entry) onDelete;
  final Future<void> Function(BiliOfflineDownloadEntry entry) onToggleTask;
  final void Function(BiliOfflineDownloadEntry entry) onMoreTap;
  final Set<String> openingAssetIds;
  final Set<String> deletingAssetIds;
  final Set<String> exportingAssetIds;
  final Set<int> taskActionTaskIds;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in entries) ...[
          Dismissible(
            key: ValueKey<String>('offline-cache-${entry.metadata.assetId}'),
            direction: DismissDirection.startToEnd,
            confirmDismiss: (_) => onDelete(entry),
            background: const OfflineDeleteBackground(),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: deletingAssetIds.contains(entry.metadata.assetId)
                    ? null
                    : () => onOpen(entry),
                child: OfflineCacheTile(
                  entry: entry,
                  opening: openingAssetIds.contains(entry.metadata.assetId),
                  deleting: deletingAssetIds.contains(entry.metadata.assetId),
                  exporting: exportingAssetIds.contains(entry.metadata.assetId),
                  taskActionPending:
                      entry.task != null &&
                      taskActionTaskIds.contains(entry.task!.taskId),
                  onToggleTask: () => onToggleTask(entry),
                  onMoreTap: () => onMoreTap(entry),
                ),
              ),
            ),
          ),
          if (entry != entries.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class OfflineCacheTile extends StatelessWidget {
  const OfflineCacheTile({
    super.key,
    required this.entry,
    required this.opening,
    required this.deleting,
    required this.exporting,
    required this.taskActionPending,
    required this.onToggleTask,
    required this.onMoreTap,
  });

  final BiliOfflineDownloadEntry entry;
  final bool opening;
  final bool deleting;
  final bool exporting;
  final bool taskActionPending;
  final Future<void> Function() onToggleTask;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    final metadata = entry.metadata;
    final progress = entry.isCompleted
        ? 1.0
        : entry.progressRatio?.clamp(0.0, 1.0);
    final totalBytes = entry.totalBytes;
    final byteText = totalBytes == null || totalBytes <= 0
        ? biliFormatDownloadBytes(entry.receivedBytes)
        : '${biliFormatDownloadBytes(entry.receivedBytes)} / ${biliFormatDownloadBytes(totalBytes)}';
    final error = entry.displayErrorMessage;
    final isBusy = opening || deleting || exporting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 126,
              height: 78,
              child: metadata.coverUrl.isEmpty
                  ? const ColoredBox(color: Color(0xFFD9DDE5))
                  : Image.network(
                      metadata.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFFD9DDE5)),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata.videoTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF20232B),
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${metadata.pageTitle} · ${metadata.qualityLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF858A94),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 26,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          error == null || error.isEmpty
                              ? '${entry.statusLabel} · $byteText'
                              : '${entry.statusLabel} · $error',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: error == null
                                    ? const Color(0xFF7E8591)
                                    : const Color(0xFFD94868),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      if (entry.task case final task?)
                        OfflineTaskAction(
                          task: task,
                          pending: taskActionPending,
                          onTap: onToggleTask,
                        ),
                      OfflineEntryMoreButton(
                        enabled: !isBusy,
                        onTap: onMoreTap,
                      ),
                      if (isBusy)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: progress,
                    color: const Color(0xFFFB7299),
                    backgroundColor: const Color(0xFFF0F2F6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OfflineDeleteBackground extends StatelessWidget {
  const OfflineDeleteBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE84A67),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 6),
              Text(
                '删除',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OfflineTaskAction extends StatelessWidget {
  const OfflineTaskAction({
    super.key,
    required this.task,
    required this.pending,
    required this.onTap,
  });

  final VesperDownloadTaskSnapshot task;
  final bool pending;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (task.state) {
      VesperDownloadState.downloading ||
      VesperDownloadState.preparing ||
      VesperDownloadState.queued => Icons.pause_rounded,
      VesperDownloadState.paused ||
      VesperDownloadState.failed => Icons.play_arrow_rounded,
      _ => Icons.more_horiz_rounded,
    };
    final action = switch (task.state) {
      VesperDownloadState.downloading ||
      VesperDownloadState.preparing ||
      VesperDownloadState.queued => () => unawaited(onTap()),
      VesperDownloadState.paused ||
      VesperDownloadState.failed => () => unawaited(onTap()),
      _ => null,
    };
    final tooltip = switch (task.state) {
      VesperDownloadState.downloading ||
      VesperDownloadState.preparing ||
      VesperDownloadState.queued => '暂停',
      VesperDownloadState.paused || VesperDownloadState.failed => '继续',
      _ => '更多',
    };
    return Tooltip(
      message: pending ? '$tooltip中' : tooltip,
      child: InkResponse(
        key: ValueKey<String>('offline-task-action-${task.taskId}'),
        radius: 18,
        onTap: pending ? null : action,
        child: SizedBox.square(
          dimension: 26,
          child: pending
              ? Padding(
                  padding: const EdgeInsets.all(5),
                  child: CircularProgressIndicator(
                    key: ValueKey<String>(
                      'offline-task-action-pending-${task.taskId}',
                    ),
                    strokeWidth: 2,
                    color: Color(0xFFFB7299),
                  ),
                )
              : Icon(icon, color: const Color(0xFFFB7299), size: 22),
        ),
      ),
    );
  }
}

class OfflineEntryMoreButton extends StatelessWidget {
  const OfflineEntryMoreButton({
    super.key,
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '更多',
      child: IconButton(
        onPressed: enabled ? onTap : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        visualDensity: VisualDensity.compact,
        icon: const Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: Color(0xFF6D7482),
        ),
      ),
    );
  }
}

class OfflineInlineError extends StatelessWidget {
  const OfflineInlineError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 19,
              color: Color(0xFFFB7299),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF9B2F4D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class OfflineEmptyState extends StatelessWidget {
  const OfflineEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Column(
        children: [
          const Icon(
            Icons.download_for_offline_outlined,
            size: 46,
            color: Color(0xFFB6BBC4),
          ),
          const SizedBox(height: 14),
          Text(
            '还没有离线缓存',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF20232B),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '在播放设置里选择缓存后，任务会显示在这里。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF858A94),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
