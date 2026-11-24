import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_icons.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_player/vesper_player.dart';

import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/download/download.dart';
import '../models/bili_models.dart';
import '../services/bili_api_core.dart';
import '../services/bili_client.dart';
import '../services/bili_download_asset_id.dart';
import '../services/bili_history_store.dart';
import '../services/bili_text.dart';

class BiliCacheDownloadPanel extends StatefulWidget {
  const BiliCacheDownloadPanel({
    super.key,
    required this.detail,
    required this.currentPage,
    required this.selectedQualityId,
    required this.codecPreference,
    required this.controller,
    required this.onMessage,
    this.client,
    this.historyStore,
  });

  final BiliVideoDetail detail;
  final BiliVideoPageEntry currentPage;
  final int? selectedQualityId;
  final BiliVideoCodecPreference codecPreference;
  final BiliOfflineDownloadController controller;
  final void Function(String message) onMessage;
  final BiliClient? client;
  final BiliHistoryStore? historyStore;

  @override
  State<BiliCacheDownloadPanel> createState() => _BiliCacheDownloadPanelState();
}

class _BiliCacheDownloadPanelState extends State<BiliCacheDownloadPanel> {
  final _options = signal<BiliDownloadOptions?>(null);
  final _errorMessage = signal<String?>(null);
  final _selectedQualityId = signal<int?>(null);
  final _loading = signal(true);
  final _pendingCids = signal<Set<int>>(const <int>{});
  final _entries = signal<List<BiliOfflineDownloadEntry>>(
    const <BiliOfflineDownloadEntry>[],
  );
  final _feedbackMessage = signal<String?>(null);
  final _feedbackIsError = signal(false);
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _entries.value = widget.controller.entries;
    if (!widget.controller.isInitialized) {
      unawaited(widget.controller.initialize().catchError((Object _) {}));
    }
    unawaited(_loadOptions());
  }

  @override
  void didUpdateWidget(BiliCacheDownloadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _entries.value = widget.controller.entries;
      if (!widget.controller.isInitialized) {
        unawaited(widget.controller.initialize().catchError((Object _) {}));
      }
    }
    if (oldWidget.detail.bvid != widget.detail.bvid ||
        oldWidget.currentPage.cid != widget.currentPage.cid) {
      unawaited(_loadOptions());
    }
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    _entries.value = widget.controller.entries;
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    widget.controller.removeListener(_handleControllerChanged);
    _options.dispose();
    _errorMessage.dispose();
    _selectedQualityId.dispose();
    _loading.dispose();
    _pendingCids.dispose();
    _entries.dispose();
    _feedbackMessage.dispose();
    _feedbackIsError.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final generation = ++_loadGeneration;
    _loading.value = true;
    _errorMessage.value = null;
    _feedbackMessage.value = null;
    try {
      final options = await widget.controller.resolveOptions(
        detail: widget.detail,
        page: widget.currentPage,
      );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      final preferredQualityId = widget.selectedQualityId;
      final selected =
          preferredQualityId != null &&
              options.quality(preferredQualityId) != null
          ? preferredQualityId
          : options.qualities.firstOrNull?.qualityId;
      _options.value = options;
      _selectedQualityId.value = selected;
      _loading.value = false;
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      _errorMessage.value = biliErrorMessage(error);
      _loading.value = false;
    }
  }

  Future<void> _enqueue(BiliVideoPageEntry page) async {
    final qualityId = _selectedQualityId.value;
    if (qualityId == null) {
      const msg = '当前视频没有可选缓存清晰度。';
      _feedbackIsError.value = true;
      _feedbackMessage.value = msg;
      widget.onMessage(msg);
      return;
    }
    if (_pendingCids.value.contains(page.cid)) {
      return;
    }
    _feedbackMessage.value = null;
    _pendingCids.value = <int>{..._pendingCids.value, page.cid};
    try {
      final options = _options.value;
      await widget.controller.enqueueBiliPage(
        detail: widget.detail,
        page: page,
        qualityId: qualityId,
        codecPreference: widget.codecPreference,
        options: page.cid == options?.cid ? options : null,
      );
      final msg = '已加入缓存：P${page.pageNumber}';
      if (mounted) {
        _entries.value = widget.controller.entries;
        _feedbackIsError.value = false;
        _feedbackMessage.value = msg;
      }
      widget.onMessage(msg);
    } catch (error) {
      final msg = '缓存失败：${biliErrorMessage(error)}';
      if (mounted) {
        _feedbackIsError.value = true;
        _feedbackMessage.value = msg;
      }
      widget.onMessage(msg);
    } finally {
      if (mounted) {
        _pendingCids.value = _pendingCids.value
            .where((cid) => cid != page.cid)
            .toSet();
      }
    }
  }

  Future<void> _openOfflineCachePage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfflineCachePage(
          controller: widget.controller,
          client: widget.client,
          historyStore: widget.historyStore,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight = constraints.hasBoundedHeight;
        final tightHeight =
            boundedHeight && constraints.minHeight == constraints.maxHeight;
        final body = SignalBuilder(
          builder: (context) => _buildBody(
            context,
            scrollableEpisodes: boundedHeight,
            expandEpisodes: tightHeight,
          ),
        );
        return Column(
          mainAxisSize: tightHeight ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CachePanelHeading(
              title: '下载缓存',
              subtitle: '选择清晰度后，点击合集中的分P开始缓存。',
            ),
            const SizedBox(height: 12),
            if (boundedHeight)
              Flexible(
                fit: tightHeight ? FlexFit.tight : FlexFit.loose,
                child: body,
              )
            else
              body,
            SignalBuilder(builder: _buildFeedbackBanner),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => unawaited(_openOfflineCachePage()),
                icon: const Icon(AppIcons.folderOpenLine, size: 19),
                label: const Text('查看缓存'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFeedbackBanner(BuildContext context) {
    final message = _feedbackMessage.value;
    if (message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }
    final visualTheme = AppVisualTheme.of(context);
    final isError = _feedbackIsError.value;
    final accent = isError
        ? visualTheme.destructive
        : visualTheme.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.12),
            visualTheme.surfaceRaised,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                isError
                    ? AppIcons.errorWarningLine
                    : AppIcons.checkboxCircleFill,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isError
                        ? visualTheme.destructive
                        : visualTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required bool scrollableEpisodes,
    required bool expandEpisodes,
  }) {
    final visualTheme = AppVisualTheme.of(context);
    final errorMessage = _errorMessage.value;
    final options = _options.value;
    if (_loading.value) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (errorMessage != null) {
      final errorWidget = _CacheInlineError(
        message: errorMessage,
        onRetry: _loadOptions,
      );
      return scrollableEpisodes
          ? SingleChildScrollView(child: errorWidget)
          : errorWidget;
    }
    if (options == null) {
      return const SizedBox.shrink();
    }
    final episodeList = _CacheEpisodeList(
      detailBvid: widget.detail.bvid,
      pages: widget.detail.pages,
      currentCid: widget.currentPage.cid,
      pendingCids: _pendingCids,
      entries: _entries,
      selectedQualityId: _selectedQualityId,
      onTap: (page) => unawaited(_enqueue(page)),
    );
    return Column(
      mainAxisSize: expandEpisodes ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '分辨率',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _CacheQualitySelector(
          options: options,
          selectedQualityId: _selectedQualityId,
          onSelected: (qualityId) => _selectedQualityId.value = qualityId,
        ),
        const SizedBox(height: 14),
        Text(
          '合集',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (scrollableEpisodes)
          Flexible(
            fit: expandEpisodes ? FlexFit.tight : FlexFit.loose,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: episodeList,
            ),
          )
        else
          episodeList,
      ],
    );
  }
}

class _CacheQualitySelector extends StatelessWidget {
  const _CacheQualitySelector({
    required this.options,
    required this.selectedQualityId,
    required this.onSelected,
  });

  final BiliDownloadOptions options;
  final ReadonlySignal<int?> selectedQualityId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final selectedQualityId = this.selectedQualityId.value;
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final option in options.qualities)
              _CacheQualityButton(
                label: option.label,
                selected: selectedQualityId == option.qualityId,
                onTap: () => onSelected(option.qualityId),
              ),
          ],
        );
      },
    );
  }
}

class _CacheEpisodeList extends StatelessWidget {
  const _CacheEpisodeList({
    required this.detailBvid,
    required this.pages,
    required this.currentCid,
    required this.pendingCids,
    required this.entries,
    required this.selectedQualityId,
    required this.onTap,
  });

  final String detailBvid;
  final List<BiliVideoPageEntry> pages;
  final int currentCid;
  final ReadonlySignal<Set<int>> pendingCids;
  final ReadonlySignal<List<BiliOfflineDownloadEntry>> entries;
  final ReadonlySignal<int?> selectedQualityId;
  final ValueChanged<BiliVideoPageEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: visualTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final page in pages) ...[
            _CacheEpisodeSignalRow(
              detailBvid: detailBvid,
              page: page,
              selected: page.cid == currentCid,
              pendingCids: pendingCids,
              entries: entries,
              selectedQualityId: selectedQualityId,
              onTap: () => onTap(page),
            ),
            if (page != pages.last)
              Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: visualTheme.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _CacheEpisodeSignalRow extends StatelessWidget {
  const _CacheEpisodeSignalRow({
    required this.detailBvid,
    required this.page,
    required this.selected,
    required this.pendingCids,
    required this.entries,
    required this.selectedQualityId,
    required this.onTap,
  });

  final String detailBvid;
  final BiliVideoPageEntry page;
  final bool selected;
  final ReadonlySignal<Set<int>> pendingCids;
  final ReadonlySignal<List<BiliOfflineDownloadEntry>> entries;
  final ReadonlySignal<int?> selectedQualityId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final cacheStatus = _resolveEpisodeCacheEntry(
          entries: entries.value,
          detailBvid: detailBvid,
          page: page,
          selectedQualityId: selectedQualityId.value,
        );
        return _CacheEpisodeRow(
          page: page,
          selected: selected,
          pending: pendingCids.value.contains(page.cid),
          cacheEntry: cacheStatus?.entry,
          matchesSelectedQuality: cacheStatus?.matchesSelectedQuality ?? false,
          onTap: onTap,
        );
      },
    );
  }
}

({BiliOfflineDownloadEntry entry, bool matchesSelectedQuality})?
_resolveEpisodeCacheEntry({
  required List<BiliOfflineDownloadEntry> entries,
  required String detailBvid,
  required BiliVideoPageEntry page,
  required int? selectedQualityId,
}) {
  final targetBvid = page.bvid ?? detailBvid;
  BiliOfflineDownloadEntry? best;
  var bestMatchesQuality = false;
  var bestRank = -1;
  for (final entry in entries) {
    if (entry.isUnplayable || entry.metadata.cid != page.cid) {
      continue;
    }
    if (entry.metadata.bvid != targetBvid &&
        entry.metadata.bvid != detailBvid) {
      continue;
    }
    final parsedQualityId = tryParseBiliDownloadAssetSelection(
      entry.metadata.assetId,
    )?.qualityId;
    final matchesSelectedQuality =
        selectedQualityId == null ||
        parsedQualityId == null ||
        parsedQualityId == selectedQualityId;
    final rank = entry.isCompleted
        ? 3
        : entry.isActive
        ? (entry.state == VesperDownloadState.paused ? 1 : 2)
        : 0;
    final isBetter =
        best == null ||
        (matchesSelectedQuality && !bestMatchesQuality) ||
        (matchesSelectedQuality == bestMatchesQuality &&
            (rank > bestRank ||
                (rank == bestRank &&
                    entry.metadata.createdAtMs > best.metadata.createdAtMs)));
    if (isBetter) {
      best = entry;
      bestMatchesQuality = matchesSelectedQuality;
      bestRank = rank;
    }
  }
  if (best == null) {
    return null;
  }
  return (entry: best, matchesSelectedQuality: bestMatchesQuality);
}

class _CacheQualityButton extends StatelessWidget {
  const _CacheQualityButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final color = selected
        ? visualTheme.accent
        : visualTheme.textPrimary;
    final background = selected
        ? Color.alphaBlend(
            visualTheme.accent.withValues(alpha: 0.14),
            visualTheme.surfaceRaised,
          )
        : visualTheme.surfaceRaised;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              fontSize: 14,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

class _CacheEpisodeRow extends StatelessWidget {
  const _CacheEpisodeRow({
    required this.page,
    required this.selected,
    required this.pending,
    required this.cacheEntry,
    required this.matchesSelectedQuality,
    required this.onTap,
  });

  final BiliVideoPageEntry page;
  final bool selected;
  final bool pending;
  final BiliOfflineDownloadEntry? cacheEntry;
  final bool matchesSelectedQuality;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final selectedBackground = Color.alphaBlend(
      visualTheme.accent.withValues(alpha: 0.14),
      visualTheme.surfaceRaised,
    );
    final entry = cacheEntry;
    final String? statusLabel;
    final Color statusColor;
    final IconData trailingIcon;
    final Color trailingColor;
    if (entry == null) {
      statusLabel = null;
      statusColor = visualTheme.accent;
      trailingIcon = AppIcons.downloadLine;
      trailingColor = visualTheme.accent;
    } else if (entry.isCompleted) {
      final qualityLabel = entry.metadata.qualityLabel;
      statusLabel = matchesSelectedQuality || qualityLabel.isEmpty
          ? '已缓存'
          : '已缓存 $qualityLabel';
      statusColor = visualTheme.accent;
      trailingIcon = matchesSelectedQuality
          ? AppIcons.checkboxCircleFill
          : AppIcons.downloadLine;
      trailingColor = visualTheme.accent;
    } else if (entry.isActive) {
      statusLabel = entry.state == VesperDownloadState.paused ? '已暂停' : '缓存中';
      statusColor = visualTheme.accent;
      trailingIcon = entry.state == VesperDownloadState.paused
          ? AppIcons.playFill
          : AppIcons.download2Line;
      trailingColor = visualTheme.accent;
    } else {
      statusLabel = '缓存失败';
      statusColor = visualTheme.destructive;
      trailingIcon = AppIcons.refreshLine;
      trailingColor = visualTheme.destructive;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: pending ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 34, minHeight: 24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? selectedBackground
                        : visualTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        'P${page.pageNumber}',
                        style: TextStyle(
                          color: selected
                              ? visualTheme.accent
                              : visualTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: visualTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          biliFormatDurationSeconds(page.durationSeconds),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: visualTheme.textTertiary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (statusLabel != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox.square(
                dimension: 22,
                child: pending
                    ? const Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(trailingIcon, size: 21, color: trailingColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CacheInlineError extends StatelessWidget {
  const _CacheInlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          visualTheme.destructive.withValues(alpha: 0.12),
          visualTheme.surfaceRaised,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            Icon(
              AppIcons.errorWarningLine,
              size: 19,
              color: visualTheme.destructive,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: visualTheme.destructive,
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

class _CachePanelHeading extends StatelessWidget {
  const _CachePanelHeading({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: visualTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
