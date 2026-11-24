import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/common/widgets/app_network_image.dart';
import 'package:vesper_media/media/design/app_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/download/download.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/models/bili_region_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/widgets/bili_cache_download_panel.dart';
import 'package:vesper_media/media/player/media_glass_sheet.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_page.dart';

import '../widgets/bili_video_grid_card.dart';
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
  final _loadMoreFailed = signal(false);
  final _page = signal(1);
  final _errorMessage = signal<String?>(null);
  final _loginRequired = signal(false);

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
    _loadMoreFailed.dispose();
    _page.dispose();
    _errorMessage.dispose();
    _loginRequired.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading.value ||
        _loadingMore.value ||
        !_hasMore.value ||
        _loadMoreFailed.value ||
        _loginRequired.value) {
      return;
    }
    if (_scrollController.position.extentAfter > 400) {
      return;
    }
    unawaited(_loadMore());
  }

  Future<void> _loadPage() async {
    _loadMoreFailed.value = false;
    if (!_client.hasAuthenticatedSession) {
      _loginRequired.value = true;
      _loading.value = false;
      _loadingMore.value = false;
      _errorMessage.value = null;
      return;
    }
    _loginRequired.value = false;
    _loading.value = true;
    _errorMessage.value = null;
    try {
      final items = await _client.fetchRegionVideos(widget.section, page: 1);
      if (!mounted) return;
      _items.value = items.toList(growable: false);
      _hasMore.value =
          widget.section.apiType == BiliRegionApiType.pgc && items.length >= 20;
      _page.value = 1;
      _loading.value = false;
    } catch (error) {
      if (!mounted) return;
      if (isBiliSessionInvalidError(error)) {
        _loginRequired.value = true;
        _errorMessage.value = null;
      } else {
        _errorMessage.value = biliErrorMessage(error);
      }
      _loading.value = false;
    }
  }

  Future<void> _loadMore() async {
    if (_loading.value || _loadingMore.value || !_hasMore.value) {
      return;
    }
    if (!_client.hasAuthenticatedSession) {
      _loginRequired.value = true;
      _errorMessage.value = null;
      return;
    }
    _loadMoreFailed.value = false;
    _loadingMore.value = true;
    try {
      final nextPage = _page.value + 1;
      final items = await _client.fetchRegionVideos(
        widget.section,
        page: nextPage,
      );
      if (!mounted) return;
      final existingIds = _items.value.map((item) => item.id).toSet();
      final nextItems = items
          .where((item) => existingIds.add(item.id))
          .toList(growable: false);
      _items.value = <BiliRegionVideo>[..._items.value, ...nextItems];
      _hasMore.value =
          widget.section.apiType == BiliRegionApiType.pgc &&
          items.length >= 20 &&
          nextItems.isNotEmpty;
      _page.value = nextPage;
      _loadingMore.value = false;
    } catch (error) {
      if (!mounted) return;
      if (isBiliSessionInvalidError(error)) {
        _loginRequired.value = true;
        _errorMessage.value = null;
      } else {
        _loadMoreFailed.value = true;
      }
      _loadingMore.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return AppGlassScaffold(
      backgroundColor: visualTheme.background,
      extendBody: false,
      appBar: GlassAppBar(
        centerTitle: false,
        leading: ModalRoute.of(context)?.canPop == true
            ? const BackButton()
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BiliRegionIcon(section: widget.section, size: 32, iconSize: 18),
            const SizedBox(width: 8),
            Text(
              widget.section.name,
              style: theme.textTheme.titleLarge?.copyWith(
                color: visualTheme.textPrimary,
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
    if (_loginRequired.value) {
      return _buildLoginRequired(theme);
    }
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

  Widget _buildLoginRequired(ThemeData theme) {
    final visualTheme = AppVisualTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              AppIcons.lockLine,
              size: 42,
              color: AppVisualTokens.primaryBlue,
            ),
            const SizedBox(height: 12),
            Text(
              '需要登录后查看分区内容',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请返回首页完成 Bilibili 登录，再重新进入分类。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: visualTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            AppGlassButton(
              onPressed: _loadPage,
              icon: AppIcons.refreshLine,
              label: '重新检查登录状态',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    final visualTheme = AppVisualTheme.of(context);
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
                color: visualTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            AppGlassButton(label: '重试', onPressed: _loadPage),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    final visualTheme = AppVisualTheme.of(context);
    return Center(
      child: Text(
        '暂无内容',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: visualTheme.textSecondary,
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
        final textScaler = MediaQuery.textScalerOf(context);
        final titleFontSize =
            Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14.0;
        final subtitleFontSize =
            Theme.of(context).textTheme.bodySmall?.fontSize ?? 12.0;
        final scaledTitleHeight = (textScaler.scale(titleFontSize) * 1.2)
            .ceilToDouble();
        final scaledSubtitleHeight = (textScaler.scale(subtitleFontSize) * 1.25)
            .ceilToDouble();
        final metadataHeight = math.max(
          kMinInteractiveDimension,
          scaledSubtitleHeight + _RegionVideoCard.metadataBottomPadding,
        );
        final coverRatio = widget.section.apiType == BiliRegionApiType.pgc
            ? 150 / 210
            : 16 / 9;
        final usableWidth = constraints.maxWidth - horizontalPadding * 2;
        final crossAxisCount =
            (usableWidth / (targetCoverWidth + crossAxisSpacing))
                .ceil()
                .clamp(2, 7)
                .toInt();
        final tileWidth =
            (usableWidth - crossAxisSpacing * (crossAxisCount - 1)) /
            crossAxisCount;
        final coverHeight = tileWidth / coverRatio;
        final tileHeight =
            coverHeight +
            _RegionVideoCard.titleTopPadding +
            scaledTitleHeight +
            metadataHeight;

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
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: crossAxisSpacing,
            mainAxisExtent: tileHeight,
          ),
          itemCount: items.length + (_hasMore.value ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return SignalBuilder(builder: _buildLoadMoreIndicator);
            }
            final item = items[index];
            return _RegionVideoCard(
              coverRatio: coverRatio,
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
    if (_loadMoreFailed.value) {
      return Center(
        child: TextButton(onPressed: _loadMore, child: const Text('重试加载更多')),
      );
    }
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
      if (detail.pages.isEmpty) throw const BiliApiException('这个视频没有可播放的分 P。');
      initialPage = detail.pages.first;
    } catch (error) {
      if (mounted) {
        _showMessage('打开视频失败：${biliErrorMessage(error)}');
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
          offlineController: _offlineController,
        ),
      ),
    );
  }

  Future<void> _openCacheSurface(BiliRegionVideo item) async {
    final isPortrait =
        MediaQuery.sizeOf(context).height >= MediaQuery.sizeOf(context).width;
    Future<BiliVideoDetail> loadDetail() => _resolveVideoDetail(item);

    if (isPortrait) {
      await showMediaGlassSheet<void>(
        context: context,
        appearance: MediaGlassSheetAppearance.readable,
        contentHandlesScrolling: true,
        contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        builder: (_) => _RegionCacheSurface(
          loadDetail: loadDetail,
          client: _client,
          historyStore: _historyStore,
          controller: _offlineController,
          onMessage: _showMessage,
        ),
      );
      return;
    }

    await showMediaReadableSideDrawer<void>(
      context: context,
      surfaceKey: const ValueKey<String>('media-readable-region-cache-drawer'),
      scrollable: false,
      builder: (_) => _RegionCacheSurface(
        loadDetail: loadDetail,
        client: _client,
        historyStore: _historyStore,
        controller: _offlineController,
        onMessage: _showMessage,
      ),
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
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RegionCacheSurface extends StatefulWidget {
  const _RegionCacheSurface({
    required this.loadDetail,
    required this.client,
    required this.historyStore,
    required this.controller,
    required this.onMessage,
  });

  final Future<BiliVideoDetail> Function() loadDetail;
  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliOfflineDownloadController controller;
  final void Function(String message) onMessage;

  @override
  State<_RegionCacheSurface> createState() => _RegionCacheSurfaceState();
}

class _RegionCacheSurfaceState extends State<_RegionCacheSurface> {
  late Future<BiliVideoDetail> _detailFuture = widget.loadDetail();

  void _retry() {
    setState(() {
      _detailFuture = widget.loadDetail();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BiliVideoDetail>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final error = snapshot.error;
        if (error != null) {
          return SingleChildScrollView(
            child: _RegionCacheError(
              message: biliErrorMessage(error),
              onRetry: _retry,
            ),
          );
        }
        final detail = snapshot.data;
        if (detail == null || detail.pages.isEmpty) {
          return SingleChildScrollView(
            child: _RegionCacheError(message: '没有可缓存的分 P。', onRetry: _retry),
          );
        }
        return BiliCacheDownloadPanel(
          detail: detail,
          currentPage: detail.pages.first,
          selectedQualityId: null,
          codecPreference: BiliVideoCodecPreference.automatic,
          controller: widget.controller,
          onMessage: widget.onMessage,
          client: widget.client,
          historyStore: widget.historyStore,
        );
      },
    );
  }
}

class _RegionCacheError extends StatelessWidget {
  const _RegionCacheError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.errorWarningLine,
            color: visualTheme.destructive,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: visualTheme.destructive,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refreshLine, size: 18),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RegionVideoCard extends StatelessWidget {
  const _RegionVideoCard({
    required this.coverRatio,
    required this.item,
    required this.onTap,
    required this.onCacheTap,
  });

  static const titleTopPadding = 6.0;
  static const metadataBottomPadding = 16.0;

  final double coverRatio;
  final BiliRegionVideo item;
  final VoidCallback onTap;
  final VoidCallback onCacheTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    final isPgc = item.seasonId != null;
    final subtitle = isPgc
        ? item.indexLabel
        : item.subtitle?.isNotEmpty == true
        ? item.subtitle
        : item.followCountLabel;

    return BiliVideoGridCard(
      onTap: onTap,
      cover: _CoverImage(
        coverUrl: item.coverUrl,
        aspectRatio: coverRatio,
        overlay: _RegionCoverOverlay(item: item, isPgc: isPgc),
      ),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: titleTopPadding),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 8,
                      bottom: metadataBottomPadding,
                    ),
                    child: Text(
                      subtitle ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: visualTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
                _RegionCardMenuButton(onTap: onCacheTap),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionCoverOverlay extends StatelessWidget {
  const _RegionCoverOverlay({required this.item, required this.isPgc});

  final BiliRegionVideo item;
  final bool isPgc;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w900,
      fontSize: 11,
      shadows: const [Shadow(blurRadius: 4, color: Color(0xAA000000))],
    );
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
        Positioned(
          left: isPgc ? 6 : 7,
          right: isPgc ? 6 : 7,
          bottom: isPgc ? 6 : 7,
          child: Row(
            children: [
              if (isPgc && item.scoreLabel != null) ...[
                _ScoreBadge(score: item.scoreLabel!),
                const SizedBox(width: 4),
              ],
              if (!isPgc) ...[
                const Icon(
                  AppIcons.playCircleLine,
                  color: Colors.white,
                  size: 15,
                ),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: Text(
                  item.followCountLabel ?? '',
                  textAlign: isPgc ? TextAlign.end : TextAlign.start,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
              if (!isPgc && item.indexLabel != null) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.indexLabel!,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
              ],
            ],
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
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox.square(
      dimension: kMinInteractiveDimension,
      child: IconButton(
        onPressed: onTap,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(
          end: 6,
          bottom: _RegionVideoCard.metadataBottomPadding,
        ),
        icon: const Icon(AppIcons.moreFill, size: 18),
        color: visualTheme.textTertiary,
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
    final visualTheme = AppVisualTheme.of(context);
    final uri = coverUrl.startsWith('http')
        ? Uri.tryParse(coverUrl)
        : Uri.tryParse('https:$coverUrl');
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          uri != null
              ? AppNetworkImage(
                  uri.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const _CoverPlaceholder(),
                )
              : const _CoverPlaceholder(),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: visualTheme.imageOutline),
                ),
              ),
            ),
          ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppVisualTheme.of(context).surfaceRaised,
      ),
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
        color: AppVisualTokens.primaryActionBlue.withValues(alpha: 0.92),
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
