import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'package:bilibili_player/download/download.dart';
import '../models/bili_models.dart';
import '../services/bili_client.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(_loadOptions());
  }

  @override
  void dispose() {
    _options.dispose();
    _errorMessage.dispose();
    _selectedQualityId.dispose();
    _loading.dispose();
    _pendingCids.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    _loading.value = true;
    _errorMessage.value = null;
    try {
      final options = await widget.controller.resolveOptions(
        detail: widget.detail,
        page: widget.currentPage,
      );
      if (!mounted) {
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
      if (!mounted) {
        return;
      }
      _errorMessage.value = error.toString();
      _loading.value = false;
    }
  }

  Future<void> _enqueue(BiliVideoPageEntry page) async {
    final qualityId = _selectedQualityId.value;
    if (qualityId == null || _pendingCids.value.contains(page.cid)) {
      return;
    }
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
      widget.onMessage('已加入缓存：P${page.pageNumber}');
    } catch (error) {
      widget.onMessage('缓存失败：$error');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CachePanelHeading(
          title: '下载缓存',
          subtitle: '选择清晰度后，点击合集中的分P开始缓存。',
        ),
        const SizedBox(height: 12),
        SignalBuilder(builder: _buildBody),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => unawaited(_openOfflineCachePage()),
            icon: const Icon(Icons.folder_open_rounded, size: 19),
            label: const Text('查看缓存'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final errorMessage = _errorMessage.value;
    final options = _options.value;
    if (_loading.value) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (errorMessage != null) {
      return _CacheInlineError(message: errorMessage, onRetry: _loadOptions);
    }
    if (options == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '分辨率',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF162033),
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
            color: const Color(0xFF162033),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        _CacheEpisodeList(
          pages: widget.detail.pages,
          currentCid: widget.currentPage.cid,
          pendingCids: _pendingCids,
          onTap: (page) => unawaited(_enqueue(page)),
        ),
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
    required this.pages,
    required this.currentCid,
    required this.pendingCids,
    required this.onTap,
  });

  final List<BiliVideoPageEntry> pages;
  final int currentCid;
  final ReadonlySignal<Set<int>> pendingCids;
  final ValueChanged<BiliVideoPageEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final page in pages) ...[
            _CacheEpisodeSignalRow(
              page: page,
              selected: page.cid == currentCid,
              pendingCids: pendingCids,
              onTap: () => onTap(page),
            ),
            if (page != pages.last)
              const Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: Color(0xFFE5E8EE),
              ),
          ],
        ],
      ),
    );
  }
}

class _CacheEpisodeSignalRow extends StatelessWidget {
  const _CacheEpisodeSignalRow({
    required this.page,
    required this.selected,
    required this.pendingCids,
    required this.onTap,
  });

  final BiliVideoPageEntry page;
  final bool selected;
  final ReadonlySignal<Set<int>> pendingCids;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        return _CacheEpisodeRow(
          page: page,
          selected: selected,
          pending: pendingCids.value.contains(page.cid),
          onTap: onTap,
        );
      },
    );
  }
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
    final color = selected ? const Color(0xFFFB7299) : const Color(0xFF162033);
    return Material(
      color: selected ? const Color(0xFFFFEDF3) : const Color(0xFFF7F8FA),
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
    required this.onTap,
  });

  final BiliVideoPageEntry page;
  final bool selected;
  final bool pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: pending ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFFFEDF3)
                      : const Color(0xFFEFF2F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'P${page.pageNumber}',
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFFFB7299)
                        : const Color(0xFF687084),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
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
                        color: const Color(0xFF20232B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      biliFormatDurationSeconds(page.durationSeconds),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF8B929F),
                        fontWeight: FontWeight.w700,
                      ),
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
                    : const Icon(
                        Icons.download_rounded,
                        size: 21,
                        color: Color(0xFFFB7299),
                      ),
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
                maxLines: 3,
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

class _CachePanelHeading extends StatelessWidget {
  const _CachePanelHeading({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            color: const Color(0xFF162033),
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF74859A),
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
