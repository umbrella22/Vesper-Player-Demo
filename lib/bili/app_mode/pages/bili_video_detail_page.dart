import 'package:material_ui/material_ui.dart';

import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:bilibili_player/bili/common/services/bili_text.dart';
import 'package:bilibili_player/bili/common/pages/bili_playback_page.dart';

class BiliVideoDetailPage extends StatefulWidget {
  const BiliVideoDetailPage({
    super.key,
    required this.bvid,
    this.seedResult,
    required this.client,
    required this.historyStore,
  });

  final String bvid;
  final BiliSearchResult? seedResult;
  final BiliClient client;
  final BiliHistoryStore historyStore;

  @override
  State<BiliVideoDetailPage> createState() => _BiliVideoDetailPageState();
}

class _BiliVideoDetailPageState extends State<BiliVideoDetailPage> {
  late Future<BiliVideoDetail> _detailFuture;
  List<BiliPlaybackHistoryEntry> _history = const <BiliPlaybackHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.client.fetchVideoDetail(widget.bvid);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await widget.historyStore.loadEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _history = history;
    });
  }

  BiliPlaybackHistoryEntry? _matchHistory(BiliVideoPageEntry page) {
    for (final entry in _history) {
      if (entry.bvid == widget.bvid && entry.cid == page.cid) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _openPlayback(
    BiliVideoDetail detail,
    BiliVideoPageEntry page,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliPlaybackPage(
          detail: detail,
          initialPage: page,
          client: widget.client,
          historyStore: widget.historyStore,
        ),
      ),
    );
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: FutureBuilder<BiliVideoDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.error.toString()),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final detail = snapshot.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                pinned: true,
                expandedHeight: 380,
                title: Text(
                  detail.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFF0F1623),
                        child: detail.coverUrl.isEmpty
                            ? const Icon(
                                Icons.video_library_outlined,
                                color: Colors.white70,
                                size: 72,
                              )
                            : Image.network(
                                detail.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white70,
                                  size: 72,
                                ),
                              ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color(0x22000000),
                              Color(0x55000000),
                              Color(0xF20D1625),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 28,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _HeroChip(label: detail.ownerName),
                                _HeroChip(label: '${detail.playCountLabel} 播放'),
                                _HeroChip(label: '${detail.pages.length} 个分 P'),
                                _HeroChip(label: '${detail.likeCountLabel} 点赞'),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              detail.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            if (detail.description.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                detail.description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFFD6DFEA),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel(
                        title: '分 P 与播放进度',
                        subtitle: '直接从当前详情页选 P、续播或进入播放器。',
                      ),
                      const SizedBox(height: 16),
                      for (final page in detail.pages) ...[
                        _PageLine(
                          page: page,
                          historyEntry: _matchHistory(page),
                          onPlay: () => _openPlayback(detail, page),
                        ),
                        if (page != detail.pages.last)
                          const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF152337),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _PageLine extends StatelessWidget {
  const _PageLine({
    required this.page,
    required this.historyEntry,
    required this.onPlay,
  });

  final BiliVideoPageEntry page;
  final BiliPlaybackHistoryEntry? historyEntry;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resumeText = historyEntry == null
        ? null
        : '上次播放 ${biliFormatDurationSeconds(historyEntry!.lastPositionMs ~/ 1000)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onPlay,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x100A1628),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE6EE),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${page.pageNumber}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF8D3353),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF152337),
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoPill(
                            label:
                                '时长 ${biliFormatDurationSeconds(page.durationSeconds)}',
                          ),
                          if (resumeText != null) _InfoPill(label: resumeText),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF5D6C7F),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
