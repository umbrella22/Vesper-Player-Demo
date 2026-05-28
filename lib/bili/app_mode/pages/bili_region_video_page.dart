import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'package:bilibili_player/download/download.dart';
import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/models/bili_region_models.dart';
import 'package:bilibili_player/bili/common/services/bili_api_core.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:bilibili_player/bili/common/widgets/bili_cache_download_panel.dart';
import 'package:bilibili_player/bili/common/pages/bili_playback_page.dart';
import 'bili_region_visuals.dart';

class BiliRegionVideoPage extends StatefulWidget {
  const BiliRegionVideoPage({
    super.key,
    required this.section,
    this.client,
    this.historyStore,
    this.offlineController,
  });

  final BiliRegionSection section;
  final BiliClient? client;
  final BiliHistoryStore? historyStore;
  final BiliOfflineDownloadController? offlineController;

  @override
  State<BiliRegionVideoPage> createState() => _BiliRegionVideoPageState();
}

class _BiliRegionVideoPageState extends State<BiliRegionVideoPage> {
  late final BiliClient _client;
  late final BiliHistoryStore _historyStore;
  late final BiliOfflineDownloadController _offlineController;
  late final ScrollController _scrollController;

  final _items = signal<List<BiliRegionVideo>>(const <BiliRegionVideo>[]);
  final _loading = signal(true);
  final _loadingMore = signal(false);
  final _hasMore = signal(true);
  final _page = signal(1);
  final _errorMessage = signal<String?>(null);

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? BiliClient.instance;
    _historyStore = widget.historyStore ?? const BiliHistoryStore();
    _offlineController =
        widget.offlineController ?? BiliOfflineDownloadController.instance;
    _scrollController = ScrollController()..addListener(_onScroll);
    unawaited(_loadPage());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _items.dispose();
    _loading.dispose();
    _loadingMore.dispose();
    _hasMore.dispose();
    _page.dispose();
    _errorMessage.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading.value ||
        _loadingMore.value ||
        !_hasMore.value) {
      return;
    }
    if (_scrollController.position.extentAfter > 400) {
      return;
    }
    unawaited(_loadMore());
  }

  Future<void> _loadPage() async {
    _loading.value = true;
    _errorMessage.value = null;
    try {
      final items = await _client.fetchRegionVideos(widget.section, page: 1);
      if (!mounted) return;
      _items.value = items.toList(growable: false);
      _hasMore.value = items.length >= 20;
      _page.value = 1;
      _loading.value = false;
    } catch (error) {
      if (!mounted) return;
      _errorMessage.value = error.toString();
      _loading.value = false;
    }
  }

  Future<void> _loadMore() async {
    if (_loading.value || _loadingMore.value || !_hasMore.value) {
      return;
    }
    _loadingMore.value = true;
    try {
      final nextPage = _page.value + 1;
      final items = await _client.fetchRegionVideos(
        widget.section,
        page: nextPage,
      );
      if (!mounted) return;
      _items.value = <BiliRegionVideo>[..._items.value, ...items];
      _hasMore.value = items.length >= 20;
      _page.value = nextPage;
      _loadingMore.value = false;
    } catch (error) {
      if (!mounted) return;
      _loadingMore.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F6FB),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BiliRegionIcon(section: widget.section, size: 32, iconSize: 18),
            const SizedBox(width: 8),
            Text(
              widget.section.name,
              style: theme.textTheme.titleLarge?.copyWith(
                color: const Color(0xFF20232B),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
      body: SignalBuilder(builder: (context) => _buildBody(context, theme)),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    final items = _items.value;
    if (_loading.value) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.value != null) {
      return _buildError(theme);
    }
    if (items.isEmpty) {
      return _buildEmpty(theme);
    }
    return _buildGrid(theme, items);
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage.value ?? '加载失败',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF8B9098),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadPage, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Text(
        '暂无内容',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF8B9098),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildGrid(ThemeData theme, List<BiliRegionVideo> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 10.0;
        const crossAxisSpacing = 10.0;
        const targetCoverWidth = 150.0;
        const textHeight = 50.0;
        final usableWidth = constraints.maxWidth - horizontalPadding * 2;
        final crossAxisCount =
            (usableWidth / (targetCoverWidth + crossAxisSpacing))
                .ceil()
                .clamp(2, 7)
                .toInt();
        final tileWidth =
            (usableWidth - crossAxisSpacing * (crossAxisCount - 1)) /
            crossAxisCount;
        final coverHeight = tileWidth * 210 / 150;
        final tileHeight = coverHeight + textHeight;

        return GridView.builder(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 14,
            crossAxisSpacing: crossAxisSpacing,
            childAspectRatio: tileWidth / tileHeight,
          ),
          itemCount: items.length + (_hasMore.value ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return SignalBuilder(builder: _buildLoadMoreIndicator);
            }
            final item = items[index];
            return _RegionVideoCard(
              item: item,
              onTap: () => _openVideo(item),
              onCacheTap: () => unawaited(_openCacheSurface(item)),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadMoreIndicator(BuildContext context) {
    if (!_loadingMore.value) {
      return const SizedBox.shrink();
    }
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Future<void> _openVideo(BiliRegionVideo item) async {
    late final BiliVideoDetail detail;
    late final BiliVideoPageEntry initialPage;

    try {
      detail = await _resolveVideoDetail(item);
      initialPage = detail.pages.first;
    } catch (error) {
      if (mounted) {
        _showMessage('打开视频失败：$error');
      }
      return;
    }

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliPlaybackPage(
          detail: detail,
          initialPage: initialPage,
          client: _client,
          historyStore: _historyStore,
        ),
      ),
    );
  }

  Future<void> _openCacheSurface(BiliRegionVideo item) async {
    final isPortrait =
        MediaQuery.sizeOf(context).height >= MediaQuery.sizeOf(context).width;
    final detailFuture = _resolveVideoDetail(item);

    if (isPortrait) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: const Color(0xFFF4F4F8),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              bottom: 22 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: _RegionCacheSurface(
                detailFuture: detailFuture,
                client: _client,
                historyStore: _historyStore,
                controller: _offlineController,
                onMessage: _showMessage,
              ),
            ),
          ),
        ),
      );
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        final drawerWidth = (MediaQuery.sizeOf(dialogContext).width * 0.42)
            .clamp(
              MediaQuery.sizeOf(dialogContext).width * 0.28,
              MediaQuery.sizeOf(dialogContext).width * 0.42,
            )
            .toDouble();
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: const Color(0xFFF4F4F8),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              right: false,
              child: SizedBox(
                width: drawerWidth,
                height: double.infinity,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                  child: _RegionCacheSurface(
                    detailFuture: detailFuture,
                    client: _client,
                    historyStore: _historyStore,
                    controller: _offlineController,
                    onMessage: _showMessage,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  Future<BiliVideoDetail> _resolveVideoDetail(BiliRegionVideo item) async {
    final seasonId = item.seasonId;
    if (seasonId != null) {
      return _client.fetchPgcSeasonFirstEpisodeDetail(seasonId);
    }

    final bvid = item.bvid;
    if (bvid == null || bvid.isEmpty) {
      throw const BiliApiException('无法识别该视频。');
    }
    return _client.fetchVideoDetail(bvid);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }
}

class _RegionCacheSurface extends StatelessWidget {
  const _RegionCacheSurface({
    required this.detailFuture,
    required this.client,
    required this.historyStore,
    required this.controller,
    required this.onMessage,
  });

  final Future<BiliVideoDetail> detailFuture;
  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliOfflineDownloadController controller;
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: FutureBuilder<BiliVideoDetail>(
          future: detailFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final error = snapshot.error;
            if (error != null) {
              return _RegionCacheError(message: error.toString());
            }
            final detail = snapshot.data;
            if (detail == null || detail.pages.isEmpty) {
              return const _RegionCacheError(message: '没有可缓存的分 P。');
            }
            return BiliCacheDownloadPanel(
              detail: detail,
              currentPage: detail.pages.first,
              selectedQualityId: null,
              codecPreference: BiliVideoCodecPreference.automatic,
              controller: controller,
              onMessage: onMessage,
              client: client,
              historyStore: historyStore,
            );
          },
        ),
      ),
    );
  }
}

class _RegionCacheError extends StatelessWidget {
  const _RegionCacheError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFB33A59),
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF8B9098),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionVideoCard extends StatelessWidget {
  const _RegionVideoCard({
    required this.item,
    required this.onTap,
    required this.onCacheTap,
  });

  final BiliRegionVideo item;
  final VoidCallback onTap;
  final VoidCallback onCacheTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPgc = item.seasonId != null;
    final subtitle = isPgc
        ? item.indexLabel
        : item.subtitle?.isNotEmpty == true
        ? item.subtitle
        : item.followCountLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Material(
            color: const Color(0xFFE4E7EC),
            borderRadius: BorderRadius.circular(7),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: _CoverImage(
                coverUrl: item.coverUrl,
                aspectRatio: 150 / 210,
                overlay: _RegionCoverOverlay(item: item, isPgc: isPgc),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF20232B),
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 28,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Text(
                    subtitle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8B9098),
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              _RegionCardMenuButton(onTap: onCacheTap),
            ],
          ),
        ),
      ],
    );
  }
}

class _RegionCoverOverlay extends StatelessWidget {
  const _RegionCoverOverlay({required this.item, required this.isPgc});

  final BiliRegionVideo item;
  final bool isPgc;

  @override
  Widget build(BuildContext context) {
    final bottomLabel = isPgc ? item.followCountLabel : item.indexLabel;
    final theme = Theme.of(context);
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x00000000),
                  Color(0x12000000),
                  Color(0x9F000000),
                ],
              ),
            ),
          ),
        ),
        if (isPgc && item.scoreLabel != null)
          Positioned(
            left: 6,
            bottom: 6,
            child: _ScoreBadge(score: item.scoreLabel!),
          ),
        if (!isPgc)
          Positioned(
            left: 7,
            right: 7,
            bottom: 7,
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_outline_rounded,
                  color: Colors.white,
                  size: 15,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    item.followCountLabel ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      shadows: const <Shadow>[
                        Shadow(blurRadius: 4, color: Color(0xAA000000)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  item.indexLabel ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    shadows: const <Shadow>[
                      Shadow(blurRadius: 4, color: Color(0xAA000000)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else if (bottomLabel != null && bottomLabel.isNotEmpty)
          Positioned(
            right: 6,
            bottom: 7,
            child: Text(
              bottomLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                shadows: const <Shadow>[
                  Shadow(blurRadius: 4, color: Color(0xAA000000)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RegionCardMenuButton extends StatelessWidget {
  const _RegionCardMenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 32,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_vert_rounded, size: 20),
        color: const Color(0xFF9AA0AA),
        tooltip: '缓存',
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({
    required this.coverUrl,
    required this.aspectRatio,
    this.overlay,
  });

  final String coverUrl;
  final double aspectRatio;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final uri = coverUrl.startsWith('http')
        ? Uri.tryParse(coverUrl)
        : Uri.tryParse('https:$coverUrl');
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          uri != null
              ? Image.network(
                  uri.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const _CoverPlaceholder(),
                )
              : const _CoverPlaceholder(),
          if (overlay != null) Positioned.fill(child: overlay!),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFFF0F0F4)),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final String score;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFB7299).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          score,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
