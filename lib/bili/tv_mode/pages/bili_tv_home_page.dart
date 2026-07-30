import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/app/design/app_visual_theme.dart';
import 'package:vesper_media/app/system_presentation.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/models/bili_region_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/common/services/bili_text.dart';
import 'package:vesper_media/bili/common/services/bili_ui_mode_resolver.dart';
import 'package:vesper_media/bili/common/view_models/bili_hub_view_model.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_page.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_library_page.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_focusable.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_directional_focus_scope.dart';
import 'package:vesper_media/bili/tv_mode/widgets/bili_tv_qr_login_dialog.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_glass_dialog.dart';
import 'package:vesper_media/app/home_page.dart';
import 'package:vesper_media/download/download.dart';
import 'package:vesper_media/main.dart';

enum _TvNavItem { recommend, regions, search, history, mine, settings }

const _tvGridMaxCrossAxisExtent = 184.0;
const _tvGridMainAxisSpacing = 14.0;
const _tvGridCrossAxisSpacing = 16.0;
const _tvGridChildAspectRatio = 1.14;
const _tvCardFocusPadding = 12.0;
const _tvGridFocusInset = 32.0;
const _tvHeroFocusDelay = Duration(milliseconds: 120);
const _tvHeroCrossFadeDuration = Duration(milliseconds: 260);

enum _TvHeroSource { history, feed, region, search }

@immutable
final class _TvHeroItem {
  const _TvHeroItem({
    required this.identity,
    required this.source,
    required this.eyebrow,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.description,
    required this.durationLabel,
    required this.bvid,
    this.aid = 0,
    this.cid = 0,
    this.episodeId = 0,
    this.initialPositionMs = 0,
    this.durationMs,
    this.playCountLabel = '',
    this.regionItem,
  });

  factory _TvHeroItem.feed(BiliFeedVideo item) {
    return _TvHeroItem(
      identity: 'feed:${item.bvid}',
      source: _TvHeroSource.feed,
      eyebrow: '为你推荐',
      title: item.title,
      author: item.author,
      coverUrl: item.coverUrl,
      description: item.description?.trim().isNotEmpty == true
          ? item.description!.trim()
          : '发现值得继续观看的内容。',
      durationLabel: item.durationLabel,
      playCountLabel: item.playCountLabel,
      bvid: item.bvid,
      aid: item.aid,
    );
  }

  factory _TvHeroItem.history(BiliPlaybackHistoryEntry entry) {
    return _TvHeroItem(
      identity:
          'history:${entry.episodeId > 0 ? entry.episodeId : entry.bvid}:${entry.cid}',
      source: _TvHeroSource.history,
      eyebrow: '继续观看',
      title: entry.videoTitle,
      author: entry.ownerName,
      coverUrl: entry.coverUrl,
      description: entry.pageTitle.isEmpty ? '从上次离开的地方继续。' : entry.pageTitle,
      durationLabel: entry.durationMs == null
          ? ''
          : biliFormatDurationSeconds(entry.durationMs! ~/ 1000),
      bvid: entry.bvid,
      aid: entry.aid,
      cid: entry.cid,
      episodeId: entry.episodeId,
      initialPositionMs: entry.lastPositionMs,
      durationMs: entry.durationMs,
    );
  }

  factory _TvHeroItem.region(BiliRegionVideo item) {
    return _TvHeroItem(
      identity: 'region:${item.id}',
      source: _TvHeroSource.region,
      eyebrow: '分区精选',
      title: item.title,
      author: item.subtitle ?? item.followCountLabel ?? '',
      coverUrl: item.coverUrl,
      description: item.description?.trim().isNotEmpty == true
          ? item.description!.trim()
          : '来自当前分区的内容。',
      durationLabel: item.indexLabel ?? item.scoreLabel ?? '',
      playCountLabel: item.followCountLabel ?? '',
      bvid: item.bvid ?? '',
      aid: item.aid ?? 0,
      cid: item.cid ?? 0,
      episodeId: item.epId ?? 0,
      regionItem: item,
    );
  }

  factory _TvHeroItem.search(BiliSearchResult item) {
    return _TvHeroItem(
      identity: 'search:${item.bvid}',
      source: _TvHeroSource.search,
      eyebrow: '搜索结果',
      title: item.title,
      author: item.author,
      coverUrl: item.coverUrl,
      description: item.description?.trim().isNotEmpty == true
          ? item.description!.trim()
          : '来自当前搜索结果。',
      durationLabel: item.durationLabel,
      playCountLabel: item.playCountLabel,
      bvid: item.bvid,
      aid: item.aid,
    );
  }

  final String identity;
  final _TvHeroSource source;
  final String eyebrow;
  final String title;
  final String author;
  final String coverUrl;
  final String description;
  final String durationLabel;
  final String playCountLabel;
  final String bvid;
  final int aid;
  final int cid;
  final int episodeId;
  final int initialPositionMs;
  final int? durationMs;
  final BiliRegionVideo? regionItem;

  double get progress {
    final duration = durationMs;
    if (duration == null || duration <= 0) {
      return 0;
    }
    return (initialPositionMs / duration).clamp(0.0, 1.0);
  }
}

@visibleForTesting
double biliTvVideoGridTileWidthForCrossAxisExtent(double crossAxisExtent) {
  assert(crossAxisExtent >= 0);
  final calculatedCrossAxisCount =
      (crossAxisExtent / (_tvGridMaxCrossAxisExtent + _tvGridCrossAxisSpacing))
          .ceil();
  final crossAxisCount = calculatedCrossAxisCount < 1
      ? 1
      : calculatedCrossAxisCount;
  final calculatedUsableExtent =
      crossAxisExtent - _tvGridCrossAxisSpacing * (crossAxisCount - 1);
  final usableExtent = calculatedUsableExtent < 0
      ? 0.0
      : calculatedUsableExtent;
  return usableExtent / crossAxisCount;
}

@visibleForTesting
int biliTvCoverCacheWidth({
  required double tileWidth,
  required double devicePixelRatio,
}) {
  assert(tileWidth >= 0);
  assert(devicePixelRatio > 0);
  return (tileWidth * devicePixelRatio).ceil().clamp(160, 720).toInt();
}

extension on _TvNavItem {
  String label() {
    return switch (this) {
      _TvNavItem.recommend => '为你推荐',
      _TvNavItem.regions => '分区',
      _TvNavItem.search => '搜索',
      _TvNavItem.history => '历史记录',
      _TvNavItem.mine => '我的',
      _TvNavItem.settings => '设置',
    };
  }

  IconData icon() {
    return switch (this) {
      _TvNavItem.recommend => Icons.home_rounded,
      _TvNavItem.regions => Icons.grid_view_rounded,
      _TvNavItem.search => Icons.search_rounded,
      _TvNavItem.history => Icons.history_rounded,
      _TvNavItem.mine => Icons.person_rounded,
      _TvNavItem.settings => Icons.settings_rounded,
    };
  }
}

class BiliTvHomePage extends StatefulWidget {
  const BiliTvHomePage({
    super.key,
    this.client,
    this.historyStore,
    this.sessionStore,
    this.offlineController,
    this.appSettings,
    this.initialFeedItems = const <BiliFeedVideo>[],
    this.initialHistoryEntries = const <BiliPlaybackHistoryEntry>[],
    this.skipBootstrap = false,
  });

  final BiliClient? client;
  final BiliHistoryStore? historyStore;
  final BiliSessionStore? sessionStore;
  final BiliOfflineDownloadController? offlineController;
  final AppSettingsStore? appSettings;
  @visibleForTesting
  final List<BiliFeedVideo> initialFeedItems;
  @visibleForTesting
  final List<BiliPlaybackHistoryEntry> initialHistoryEntries;
  @visibleForTesting
  final bool skipBootstrap;

  @override
  State<BiliTvHomePage> createState() => _BiliTvHomePageState();
}

class _BiliTvHomePageState extends State<BiliTvHomePage> {
  late final BiliHubViewModel _viewModel;
  late final AppSettingsStore _appSettings;
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'tv_search_field');
  final ScrollController _contentScrollController = ScrollController();
  final ScrollController _continueShelfController = ScrollController();
  final ScrollController _recommendShelfController = ScrollController();

  _TvNavItem _selectedNav = _TvNavItem.recommend;
  bool _forceTvMode = false;
  bool _initialForceTvMode = false;
  bool _feedLoadMoreQueued = false;
  bool _regionLoadMoreQueued = false;
  int _presentationGeneration = 0;
  int _regionPage = 1;

  List<BiliPlaybackHistoryEntry> _history = const [];
  BiliRegionSection _selectedRegion = biliRegionSections.first;
  List<BiliRegionVideo> _regionItems = const <BiliRegionVideo>[];
  bool _regionLoading = false;
  bool _regionLoadingMore = false;
  bool _hasMoreRegion = true;
  String? _regionErrorMessage;
  bool _restorePresentationOnDispose = true;
  bool _exitDialogVisible = false;
  TvFocusArea? _activeFocusArea = TvFocusArea.rail;
  _TvHeroItem? _heroItem;
  Timer? _heroUpdateTimer;
  bool _heroHasUserSelection = false;

  @override
  void initState() {
    super.initState();
    unawaited(_enterTvHomePresentation());
    _searchController = TextEditingController();
    setTvFocusArea(_searchFocusNode, TvFocusArea.content);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _appSettings = widget.appSettings ?? const AppSettingsStore();
    _viewModel = BiliHubViewModel(
      client: widget.client,
      historyStore: widget.historyStore,
      sessionStore: widget.sessionStore,
      offlineController: widget.offlineController,
    );
    if (widget.initialFeedItems.isNotEmpty || widget.skipBootstrap) {
      _viewModel.seedFeedForTesting(widget.initialFeedItems);
    }
    _history = widget.initialHistoryEntries;
    if (widget.initialHistoryEntries.isNotEmpty) {
      _heroItem = _TvHeroItem.history(widget.initialHistoryEntries.first);
    } else if (widget.initialFeedItems.isNotEmpty) {
      _heroItem = _TvHeroItem.feed(widget.initialFeedItems.first);
    }
    if (!widget.skipBootstrap) {
      unawaited(_bootstrap());
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _contentScrollController.dispose();
    _continueShelfController.dispose();
    _recommendShelfController.dispose();
    _heroUpdateTimer?.cancel();
    _viewModel.dispose();
    if (_restorePresentationOnDispose) {
      unawaited(_restoreAppPresentation());
    }
    super.dispose();
  }

  Future<void> _enterTvHomePresentation() async {
    await _applySystemPresentation(
      orientations: biliLandscapeOrientations,
      systemUiMode: SystemUiMode.immersiveSticky,
      overlayStyle: biliTvSystemUiStyle,
    );
  }

  Future<void> _restoreAppPresentation() async {
    await _applySystemPresentation(
      useAppOrientationPolicy: true,
      systemUiMode: SystemUiMode.edgeToEdge,
      overlayStyle: biliAppSystemUiStyle,
    );
  }

  Future<void> _applyPresentationFor(BiliUiMode mode) {
    return mode == BiliUiMode.tv
        ? _enterTvHomePresentation()
        : _restoreAppPresentation();
  }

  Future<void> _applySystemPresentation({
    List<DeviceOrientation>? orientations,
    bool useAppOrientationPolicy = false,
    required SystemUiMode systemUiMode,
    required SystemUiOverlayStyle overlayStyle,
  }) async {
    assert(useAppOrientationPolicy != (orientations != null));
    final generation = ++_presentationGeneration;
    if (useAppOrientationPolicy) {
      await setBiliAppPreferredOrientations();
    } else {
      await setBiliPreferredOrientations(orientations!);
    }
    if (generation != _presentationGeneration) {
      return;
    }
    await setBiliSystemUiMode(systemUiMode);
    if (generation != _presentationGeneration) {
      return;
    }
    setBiliSystemUiOverlayStyle(overlayStyle);
  }

  Future<void> _bootstrap() async {
    await _viewModel.bootstrap();
    await _loadHistory();
    final forceTvMode = await _appSettings.getForceTvMode();
    _forceTvMode = forceTvMode;
    _initialForceTvMode = forceTvMode;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadHistory() async {
    final local = await (_viewModel.historyStore).loadEntries();
    var merged = local;
    final shouldLoadRemote =
        _viewModel.client.hasAuthenticatedSession ||
        _viewModel.profile.value.isLoggedIn;
    if (shouldLoadRemote) {
      try {
        final remote = await _viewModel.client.fetchRemoteHistory(pageSize: 30);
        final seen = <String>{};
        final cloud = remote
            .where(
              (entry) =>
                  entry.bvid.trim().isNotEmpty ||
                  entry.aid > 0 ||
                  entry.episodeId > 0,
            )
            .map(
              (entry) => BiliPlaybackHistoryEntry(
                bvid: entry.bvid,
                aid: entry.aid,
                cid: entry.cid,
                episodeId: entry.episodeId,
                business: entry.business,
                videoTitle: entry.title,
                pageTitle: entry.pageTitle,
                coverUrl: entry.coverUrl,
                ownerName: entry.ownerName,
                playedAtMs: entry.viewedAtMs,
                lastPositionMs: entry.progressMs,
                durationMs: entry.durationMs > 0 ? entry.durationMs : null,
              ),
            )
            .where((entry) => seen.add(_historyIdentity(entry)))
            .toList(growable: false);
        if (cloud.isNotEmpty) {
          merged = <BiliPlaybackHistoryEntry>[
            ...cloud,
            ...local.where((entry) => !seen.contains(_historyIdentity(entry))),
          ];
        }
      } catch (_) {
        // The local store is the offline fallback when the cursor endpoint
        // is unavailable or the session has expired.
      }
    }
    if (!mounted) {
      return;
    }
    final preferredHero = !_heroHasUserSelection && merged.isNotEmpty
        ? _TvHeroItem.history(merged.first)
        : null;
    setState(() {
      _history = merged;
      if (preferredHero != null) {
        _heroItem = preferredHero;
      }
    });
    if (preferredHero != null) {
      _precacheHeroCover(preferredHero);
    }
  }

  void _handleFocusAreaChanged(TvFocusArea? area) {
    if (!mounted || _activeFocusArea == area) {
      return;
    }
    setState(() => _activeFocusArea = area);
  }

  void _ensureInitialHero(List<BiliFeedVideo> feedItems) {
    if (_heroItem != null || feedItems.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _heroItem != null) {
        return;
      }
      final item = _history.isNotEmpty
          ? _TvHeroItem.history(_history.first)
          : _TvHeroItem.feed(feedItems.first);
      setState(() => _heroItem = item);
      _precacheHeroCover(item);
    });
  }

  void _scheduleHeroUpdate(_TvHeroItem item, bool focused) {
    if (!focused || _heroItem?.identity == item.identity) {
      return;
    }
    _heroUpdateTimer?.cancel();
    final delay = AppVisualTokens.motionDuration(context, _tvHeroFocusDelay);
    if (delay == Duration.zero) {
      _applyFocusedHero(item);
      return;
    }
    _heroUpdateTimer = Timer(delay, () => _applyFocusedHero(item));
  }

  void _applyFocusedHero(_TvHeroItem item) {
    if (!mounted || _heroItem?.identity == item.identity) {
      return;
    }
    _precacheHeroCover(item);
    setState(() {
      _heroItem = item;
      _heroHasUserSelection = true;
    });
  }

  void _precacheHeroCover(_TvHeroItem item) {
    if (!mounted || item.coverUrl.isEmpty) {
      return;
    }
    unawaited(
      precacheImage(NetworkImage(item.coverUrl), context, onError: (_, _) {}),
    );
  }

  Future<void> _playHero(_TvHeroItem item) async {
    final regionItem = item.regionItem;
    if (regionItem != null) {
      await _openRegionVideo(regionItem);
      return;
    }
    await _openPlayback(
      item.bvid,
      aid: item.aid > 0 ? item.aid : null,
      cid: item.cid > 0 ? item.cid : null,
      episodeId: item.episodeId > 0 ? item.episodeId : null,
      initialPositionMs: item.initialPositionMs,
    );
  }

  Future<void> _openHeroDetails(_TvHeroItem item) async {
    late final BiliVideoDetail detail;
    try {
      final regionItem = item.regionItem;
      if (regionItem?.seasonId case final seasonId?) {
        detail = await _viewModel.client.fetchPgcSeasonFirstEpisodeDetail(
          seasonId,
        );
      } else if (regionItem != null) {
        if (item.bvid.isEmpty) {
          throw const BiliHubException('无法识别该视频。');
        }
        detail = await _viewModel.client.fetchVideoDetail(item.bvid);
      } else {
        final target = await _viewModel.resolvePlaybackTarget(
          item.bvid,
          aid: item.aid > 0 ? item.aid : null,
          cid: item.cid > 0 ? item.cid : null,
          episodeId: item.episodeId > 0 ? item.episodeId : null,
        );
        detail = target.detail;
      }
    } catch (error) {
      if (mounted) {
        _showMessage('加载详情失败：$error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final shouldPlay = await showBiliTvGlassDialog<bool>(
      context: context,
      maxWidth: 690,
      title: detail.title,
      message: detail.description.isEmpty
          ? '${detail.ownerName} · ${detail.playCountLabel} 播放'
          : detail.description,
      icon: Icons.info_outline_rounded,
      actions: const [
        BiliTvDialogAction(
          label: '返回',
          value: false,
          icon: Icons.arrow_back_rounded,
          autofocus: true,
        ),
        BiliTvDialogAction(
          label: '开始播放',
          value: true,
          icon: Icons.play_arrow_rounded,
        ),
      ],
    );
    if (shouldPlay == true && mounted) {
      await _playHero(item);
    }
  }

  String _historyIdentity(BiliPlaybackHistoryEntry entry) {
    if (entry.episodeId > 0) {
      return 'episode:${entry.episodeId}';
    }
    if (entry.cid > 0) {
      return 'cid:${entry.cid}';
    }
    if (entry.bvid.isNotEmpty) {
      return 'bvid:${entry.bvid}';
    }
    return 'aid:${entry.aid}';
  }

  Future<void> _openLibrary(BiliLibrarySection section) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliLibraryPage(
          client: _viewModel.client,
          initialSection: section,
          historyStore: _viewModel.historyStore,
          offlineController: _viewModel.offlineController,
          onLoginTap: _openQrLogin,
          presentationMode: BiliPlaybackPresentationMode.tv,
        ),
      ),
    );
    if (mounted) {
      await _loadHistory();
    }
  }

  Future<void> _openPlayback(
    String bvid, {
    int? aid,
    int? cid,
    int? episodeId,
    int initialPositionMs = 0,
  }) async {
    late final BiliHubPlaybackTarget target;
    try {
      target = await _viewModel.resolvePlaybackTarget(
        bvid,
        aid: aid,
        cid: cid,
        episodeId: episodeId,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('打开视频失败：$error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliPlaybackPage(
          detail: target.detail,
          initialPage: target.initialPage,
          client: _viewModel.client,
          historyStore: _viewModel.historyStore,
          offlineController: _viewModel.offlineController,
          initialPositionMs: initialPositionMs,
          presentationMode: BiliPlaybackPresentationMode.tv,
        ),
      ),
    );
    unawaited(_loadHistory());
  }

  Future<void> _openRegionVideo(BiliRegionVideo item) async {
    late final BiliVideoDetail detail;
    try {
      final seasonId = item.seasonId;
      if (seasonId != null) {
        detail = await _viewModel.client.fetchPgcSeasonFirstEpisodeDetail(
          seasonId,
        );
      } else {
        final bvid = item.bvid;
        if (bvid == null || bvid.isEmpty) {
          throw const BiliHubException('无法识别该视频。');
        }
        detail = await _viewModel.client.fetchVideoDetail(bvid);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('打开视频失败：$error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (detail.pages.isEmpty) {
      _showMessage('这个内容没有可播放剧集。');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliPlaybackPage(
          detail: detail,
          initialPage: detail.pages.first,
          client: _viewModel.client,
          historyStore: _viewModel.historyStore,
          offlineController: _viewModel.offlineController,
          presentationMode: BiliPlaybackPresentationMode.tv,
        ),
      ),
    );
    unawaited(_loadHistory());
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runSearch() async {
    final bvid = biliExtractBvid(_searchController.text.trim());
    if (bvid != null) {
      await _openPlayback(bvid);
      return;
    }
    await _viewModel.runSearch();
  }

  void _requestMoreFeed() {
    if (_feedLoadMoreQueued ||
        _viewModel.isRefreshingFeed.value ||
        _viewModel.isLoadingMoreFeed.value ||
        !_viewModel.hasMoreFeed.value) {
      return;
    }
    _feedLoadMoreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _feedLoadMoreQueued = false;
      if (!mounted) {
        return;
      }
      unawaited(
        _viewModel.loadMoreFeed().then((message) {
          if (message != null && mounted) {
            _showMessage(message);
          }
        }),
      );
    });
  }

  Future<void> _loadRegion({BiliRegionSection? section}) async {
    if (!_viewModel.profile.value.isLoggedIn &&
        !_viewModel.client.hasAuthenticatedSession) {
      _showMessage('分区内容需要登录后才能观看。');
      return;
    }
    final nextSection = section ?? _selectedRegion;
    setState(() {
      _selectedRegion = nextSection;
      _regionLoading = true;
      _regionErrorMessage = null;
      _hasMoreRegion = true;
    });
    try {
      final items = await _viewModel.client.fetchRegionVideos(
        nextSection,
        page: 1,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _regionItems = items;
        _regionPage = 1;
        _hasMoreRegion =
            nextSection.apiType == BiliRegionApiType.pgc && items.length >= 20;
        _regionLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _regionErrorMessage = error is BiliApiException && error.code == -101
            ? '登录状态已失效，请重新登录后查看分区内容。'
            : error.toString();
        _regionLoading = false;
      });
      if (error is BiliApiException && error.code == -101) {
        _showMessage('登录状态已失效，请重新登录。');
      }
    }
  }

  void _requestMoreRegion() {
    if (_regionLoadMoreQueued ||
        _regionLoading ||
        _regionLoadingMore ||
        !_hasMoreRegion) {
      return;
    }
    _regionLoadMoreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _regionLoadMoreQueued = false;
      if (!mounted) {
        return;
      }
      unawaited(_loadMoreRegion());
    });
  }

  Future<void> _loadMoreRegion() async {
    if (_regionLoading || _regionLoadingMore || !_hasMoreRegion) {
      return;
    }
    setState(() {
      _regionLoadingMore = true;
    });
    try {
      final nextPage = _regionPage + 1;
      final items = await _viewModel.client.fetchRegionVideos(
        _selectedRegion,
        page: nextPage,
      );
      if (!mounted) {
        return;
      }
      final existingIds = _regionItems.map((item) => item.id).toSet();
      final nextItems = items
          .where((item) => existingIds.add(item.id))
          .toList(growable: false);
      setState(() {
        _regionItems = <BiliRegionVideo>[..._regionItems, ...nextItems];
        _regionPage = nextPage;
        _hasMoreRegion = items.length >= 20 && nextItems.isNotEmpty;
        _regionLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _regionLoadingMore = false;
      });
      _showMessage('加载更多分区内容失败：$error');
    }
  }

  Future<void> _toggleForceTvMode(bool value) async {
    setState(() {
      _forceTvMode = value;
    });
    _showMessage(
      value == _initialForceTvMode
          ? '已恢复当前显示模式，无需切换首页。'
          : '显示模式已修改，点击下方按钮返回首页切换。',
    );
    try {
      await _appSettings.setForceTvMode(value);
    } catch (error) {
      if (mounted) {
        _showMessage('保存显示模式失败：$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppVisualTokens.tvTheme(),
      child: TvGlassQualityScope(
        maxQuality: GlassQuality.standard,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              unawaited(_confirmExitApp());
            }
          },
          child: TvDirectionalFocusScope(
            debugLabel: 'tv_home',
            handleGoBackKey: false,
            onBack: () => unawaited(_confirmExitApp()),
            onFocusAreaChanged: _handleFocusAreaChanged,
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: Colors.transparent,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1440;
                  final railExpanded = _activeFocusArea == TvFocusArea.rail;
                  final railWidth = railExpanded
                      ? (wide ? 300.0 : 260.0)
                      : (wide ? 88.0 : 80.0);
                  final margin = wide ? 28.0 : 20.0;
                  final contentInset = railWidth + margin + (wide ? 52 : 36);
                  final duration = AppVisualTokens.motionDuration(
                    context,
                    AppVisualTokens.overlayDuration,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildTvBackdrop(constraints),
                      AnimatedPositioned(
                        key: const ValueKey<String>('bili-tv-content-area'),
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        left: contentInset,
                        top: 0,
                        right: 0,
                        bottom: 0,
                        child: TvFocusAreaScope(
                          area: TvFocusArea.content,
                          child: _buildContentArea(),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        left: margin,
                        top: margin,
                        bottom: margin,
                        width: railWidth,
                        child: TvFocusAreaScope(
                          area: TvFocusArea.rail,
                          child: _buildLeftRail(expanded: railExpanded),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmExitApp() async {
    if (!mounted || _exitDialogVisible) {
      return;
    }
    _exitDialogVisible = true;
    bool? shouldExit;
    try {
      shouldExit = await showBiliTvGlassDialog<bool>(
        context: context,
        maxWidth: 690,
        title: '退出 Vesper？',
        message: '播放进度已经保存，下次打开时可以继续观看。',
        icon: Icons.logout_rounded,
        actions: const [
          BiliTvDialogAction(
            label: '继续观看',
            value: false,
            icon: Icons.play_arrow_rounded,
            autofocus: true,
          ),
          BiliTvDialogAction(
            label: '退出应用',
            value: true,
            icon: Icons.power_settings_new_rounded,
            isDestructive: true,
          ),
        ],
      );
    } finally {
      _exitDialogVisible = false;
    }
    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }

  Widget _buildTvBackdrop(BoxConstraints constraints) {
    final hero = _heroItem;
    final duration = AppVisualTokens.motionDuration(
      context,
      _tvHeroCrossFadeDuration,
    );
    final cacheWidth =
        (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(960, 2560)
            .toInt();
    return RepaintBoundary(
      key: const ValueKey<String>('bili-tv-hero-backdrop'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: [...previousChildren, ?currentChild],
            ),
            child: hero == null || hero.coverUrl.isEmpty
                ? const ColoredBox(
                    key: ValueKey<String>('tv-hero-empty'),
                    color: AppVisualTokens.tvBackground,
                  )
                : Image.network(
                    hero.coverUrl,
                    key: ValueKey<String>('tv-hero-${hero.identity}'),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    cacheWidth: cacheWidth,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: AppVisualTokens.tvBackground),
                  ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0, 0.42, 1],
                colors: [
                  Color(0xF2111318),
                  Color(0xA6111318),
                  Color(0x33111318),
                ],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.46, 0.78, 1],
                colors: [
                  Color(0x1A111318),
                  Color(0x4D111318),
                  Color(0xE6111318),
                  AppVisualTokens.tvBackground,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftRail({required bool expanded}) {
    final quality = TvGlassQualityScope.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final contents = LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 620;
        final showLabels = expanded && constraints.maxWidth >= 180;
        return Column(
          children: [
            _buildRailProfile(expanded: showLabels, compact: compactHeight),
            SizedBox(height: compactHeight ? 6 : 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: compactHeight ? 8 : 10,
                ),
                children: [
                  for (final item in _TvNavItem.values)
                    _buildRailItem(
                      item,
                      expanded: showLabels,
                      compact: compactHeight,
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                showLabels ? 20 : 0,
                4,
                showLabels ? 20 : 0,
                compactHeight ? 10 : 18,
              ),
              child: Row(
                mainAxisAlignment: showLabels
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 40,
                    child: Center(
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 16,
                        color: Color(0x73FFFFFF),
                      ),
                    ),
                  ),
                  if (showLabels) ...[
                    const SizedBox(width: 12),
                    const Flexible(
                      child: Text(
                        '按返回键退出',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0x73FFFFFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
    final surface = DecoratedBox(
      key: const ValueKey<String>('bili-tv-left-rail'),
      decoration: BoxDecoration(
        color: highContrast ? const Color(0xFF17191F) : const Color(0xB317191F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highContrast
              ? const Color(0xB3FFFFFF)
              : const Color(0x2EFFFFFF),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: contents,
      ),
    );
    if (highContrast) {
      return surface;
    }
    return AdaptiveLiquidGlassLayer(
      quality: quality,
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      settings: const LiquidGlassSettings(
        blur: 11,
        thickness: 18,
        glassColor: Color(0x2417191F),
        lightIntensity: 0.62,
        saturation: 1.05,
      ),
      child: GlassContainer(
        useOwnLayer: false,
        quality: quality,
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        clipBehavior: Clip.hardEdge,
        child: surface,
      ),
    );
  }

  Widget _buildRailProfile({required bool expanded, bool compact = false}) {
    return SignalBuilder(
      builder: (context) {
        final profile = _viewModel.profile.value;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            expanded ? 20 : 0,
            compact ? 12 : 18,
            expanded ? 20 : 0,
            0,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  SizedBox(
                    key: const ValueKey<String>('bili-tv-rail-logo'),
                    width: 40,
                    child: Center(
                      child: Container(
                        width: compact ? 36 : 40,
                        height: compact ? 36 : 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6FA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 2),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Color(0xFF111318),
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Text(
                        'VESPER',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: compact ? 10 : 16),
              const Divider(height: 1, color: Color(0x24FFFFFF)),
              SizedBox(height: compact ? 10 : 16),
              Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  SizedBox(
                    key: const ValueKey<String>('bili-tv-rail-avatar'),
                    width: 40,
                    child: Center(
                      child: CircleAvatar(
                        radius: compact ? 17 : 19,
                        backgroundColor: const Color(0x33FFFFFF),
                        backgroundImage: profile.avatarUrl.isNotEmpty
                            ? NetworkImage(profile.avatarUrl)
                            : null,
                        child: profile.avatarUrl.isEmpty
                            ? Icon(
                                profile.isLoggedIn
                                    ? Icons.person_rounded
                                    : Icons.person_outline_rounded,
                                color: const Color(0xB3FFFFFF),
                                size: compact ? 18 : 20,
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.isLoggedIn ? profile.name : '未登录',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xF2FFFFFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile.isLoggedIn ? '已同步播放记录' : '登录后同步内容',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0x80FFFFFF),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRailItem(
    _TvNavItem item, {
    required bool expanded,
    bool compact = false,
  }) {
    final selected = _selectedNav == item;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 1 : 3),
      child: TvGlassSelectable(
        autofocus: item == _TvNavItem.recommend,
        selected: selected,
        useOwnLayer: false,
        scale: 1,
        borderRadius: 12,
        focusArea: TvFocusArea.rail,
        debugLabel: 'nav_${item.name}',
        onTap: () => unawaited(_handleNavTap(item)),
        builder: (context, state) {
          final focused =
              state == TvGlassSelectableState.focused ||
              state == TvGlassSelectableState.pressed;
          return SizedBox(
            height: compact ? 42 : 50,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: 0,
                  child: AnimatedContainer(
                    duration: AppVisualTokens.motionDuration(
                      context,
                      AppVisualTokens.tvFocusDuration,
                    ),
                    width: 3,
                    height: compact ? 20 : 24,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppVisualTokens.primaryBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 0),
                  child: Row(
                    mainAxisAlignment: expanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(expanded ? -1 : 0, 0),
                        child: SizedBox(
                          key: ValueKey<String>(
                            'bili-tv-rail-icon-${item.name}',
                          ),
                          width: 40,
                          child: Center(
                            child: Icon(
                              item.icon(),
                              color: focused || selected
                                  ? Colors.white
                                  : const Color(0x99FFFFFF),
                              size: focused
                                  ? (compact ? 21 : 23)
                                  : (compact ? 20 : 22),
                            ),
                          ),
                        ),
                      ),
                      if (expanded) ...[
                        SizedBox(width: compact ? 9 : 11),
                        Expanded(
                          child: Text(
                            item.label(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 14 : 15,
                              fontWeight: focused || selected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: focused || selected
                                  ? Colors.white
                                  : const Color(0x99FFFFFF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContentArea() {
    if (_selectedNav == _TvNavItem.recommend) {
      return _buildRecommendPage();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Text(
            _selectedNav.label(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: switch (_selectedNav) {
            _TvNavItem.recommend => const SizedBox.shrink(),
            _TvNavItem.regions => _buildRegionsPage(),
            _TvNavItem.search => _buildSearchPage(),
            _TvNavItem.history => _buildHistoryPage(),
            _TvNavItem.mine => _buildMinePage(),
            _TvNavItem.settings => _buildSettingsPage(),
          },
        ),
      ],
    );
  }

  Future<void> _handleNavTap(_TvNavItem item) async {
    final hasSession =
        _viewModel.profile.value.isLoggedIn ||
        _viewModel.client.hasAuthenticatedSession;
    if (item == _TvNavItem.regions && !hasSession) {
      final shouldLogin = await _confirmRegionLogin();
      if (!mounted || shouldLogin != true) {
        return;
      }
      await _openQrLogin();
      if (!mounted ||
          (!_viewModel.profile.value.isLoggedIn &&
              !_viewModel.client.hasAuthenticatedSession)) {
        return;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedNav = item;
    });
    if (item == _TvNavItem.search) {
      _requestSearchFocusAfterFrame();
    }
    if (item == _TvNavItem.history) {
      unawaited(_loadHistory());
    }
    if (item == _TvNavItem.recommend) {
      unawaited(_viewModel.loadFeed());
    }
    if (item == _TvNavItem.regions && _regionItems.isEmpty) {
      unawaited(_loadRegion());
    }
  }

  Widget _buildRecommendPage() {
    return SignalBuilder(
      builder: (context) {
        final items = _viewModel.feedItems.value;
        _ensureInitialHero(items);
        if (_viewModel.isBootstrapping.value) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0x88FFFFFF)),
          );
        }
        final feedErrorMessage = _viewModel.feedErrorMessage.value;
        if (feedErrorMessage != null && items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    color: const Color(0x66FFFFFF),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    feedErrorMessage,
                    style: const TextStyle(
                      color: Color(0x88FFFFFF),
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TvGlassSelectable(
                    autofocus: true,
                    borderRadius: 12,
                    onTap: () => _viewModel.loadFeed(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    builder: (context, state) => const Text(
                      '重新加载',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (items.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0x88FFFFFF)),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final heroHeight = (constraints.maxHeight * 0.48)
                .clamp(280.0, 480.0)
                .toDouble();
            final cardWidth = (constraints.maxWidth * 0.19)
                .clamp(220.0, 310.0)
                .toDouble();
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical &&
                    notification.metrics.extentAfter < 720) {
                  _requestMoreFeed();
                }
                return false;
              },
              child: CustomScrollView(
                key: const ValueKey<String>('bili-tv-recommend-scroll'),
                controller: _contentScrollController,
                clipBehavior: Clip.hardEdge,
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: heroHeight,
                      child: _buildHeroPanel(
                        _heroItem ?? _TvHeroItem.feed(items.first),
                        compact: constraints.maxWidth < 840,
                      ),
                    ),
                  ),
                  if (_history.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildHistoryShelf(
                        entries: _history.take(20).toList(growable: false),
                        cardWidth: cardWidth,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _buildFeedShelf(items: items, cardWidth: cardWidth),
                  ),
                  if (_viewModel.isLoadingMoreFeed.value)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 28),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0x88FFFFFF),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeroPanel(_TvHeroItem item, {required bool compact}) {
    final title = biliStripHtmlTags(item.title);
    final metadata = <String>[
      if (item.author.isNotEmpty) item.author,
      if (item.durationLabel.isNotEmpty) item.durationLabel,
      if (item.playCountLabel.isNotEmpty) '${item.playCountLabel} 播放',
    ].join(' · ');
    final progress = item.progress;
    final progressLabel = item.durationMs == null
        ? null
        : '已观看 ${biliFormatDurationSeconds(item.initialPositionMs ~/ 1000)} / ${biliFormatDurationSeconds(item.durationMs! ~/ 1000)}';
    return Padding(
      padding: EdgeInsets.fromLTRB(0, compact ? 30 : 46, 36, 18),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 560 : 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppVisualTokens.primaryBlue,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    item.eyebrow,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 16),
              Text(
                title,
                key: const ValueKey<String>('bili-tv-hero-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 34 : 44,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 9),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xD9FFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (!compact && item.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  biliStripHtmlTags(item.description),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xA6FFFFFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
              if (progressLabel != null && progress > 0) ...[
                SizedBox(height: compact ? 10 : 14),
                Text(
                  progressLabel,
                  style: const TextStyle(
                    color: Color(0xA6FFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      key: const ValueKey<String>('bili-tv-hero-progress'),
                      value: progress,
                      minHeight: 4,
                      backgroundColor: const Color(0x3DFFFFFF),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppVisualTokens.primaryBlue,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(height: compact ? 14 : 20),
              TvFocusGroupScope(
                key: const ValueKey<String>('bili-tv-hero-actions'),
                group: const ValueKey<String>('tv-hero-actions-focus'),
                child: AdaptiveLiquidGlassLayer(
                  quality: TvGlassQualityScope.of(context),
                  settings: const LiquidGlassSettings(
                    blur: 8,
                    thickness: 16,
                    glassColor: Color(0x14FFFFFF),
                    lightIntensity: 0.6,
                  ),
                  child: Row(
                    children: [
                      _TvHeroAction(
                        label: item.source == _TvHeroSource.history
                            ? '继续播放'
                            : '开始播放',
                        icon: Icons.play_arrow_rounded,
                        primary: true,
                        debugLabel: 'tv_hero_play',
                        onTap: () => unawaited(_playHero(item)),
                      ),
                      const SizedBox(width: 12),
                      _TvHeroAction(
                        label: '详情',
                        icon: Icons.info_outline_rounded,
                        debugLabel: 'tv_hero_details',
                        onTap: () => unawaited(_openHeroDetails(item)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryShelf({
    required List<BiliPlaybackHistoryEntry> entries,
    required double cardWidth,
  }) {
    final coverCacheWidth = biliTvCoverCacheWidth(
      tileWidth: cardWidth,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return _TvMediaShelf(
      key: const ValueKey<String>('bili-tv-continue-shelf'),
      title: '继续观看',
      controller: _continueShelfController,
      itemCount: entries.length,
      cardWidth: cardWidth,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final hero = _TvHeroItem.history(entry);
        return _TvHistoryCard(
          key: ValueKey<String>('history_${hero.identity}'),
          coverUrl: entry.coverUrl,
          coverCacheWidth: coverCacheWidth,
          title: entry.videoTitle,
          subtitle: entry.pageTitle,
          ownerName: entry.ownerName,
          progress: hero.progress,
          onFocusChange: (focused) => _scheduleHeroUpdate(hero, focused),
          onTap: () => unawaited(_playHero(hero)),
        );
      },
    );
  }

  Widget _buildFeedShelf({
    required List<BiliFeedVideo> items,
    required double cardWidth,
  }) {
    final coverCacheWidth = biliTvCoverCacheWidth(
      tileWidth: cardWidth,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return _TvMediaShelf(
      key: const ValueKey<String>('bili-tv-recommend-shelf'),
      title: '为你推荐',
      controller: _recommendShelfController,
      itemCount: items.length,
      cardWidth: cardWidth,
      itemBuilder: (context, index) {
        if (index >= items.length - 8) {
          _requestMoreFeed();
        }
        final item = items[index];
        final hero = _TvHeroItem.feed(item);
        return _TvVideoCard(
          key: ValueKey<String>('feed_${item.bvid}'),
          coverUrl: item.coverUrl,
          coverCacheWidth: coverCacheWidth,
          title: item.title,
          author: item.author,
          duration: item.durationLabel,
          playCount: item.playCountLabel,
          onFocusChange: (focused) => _scheduleHeroUpdate(hero, focused),
          onTap: () => unawaited(_playHero(hero)),
        );
      },
    );
  }

  Widget _buildRegionsPage() {
    if (_regionItems.isEmpty &&
        !_regionLoading &&
        _regionErrorMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedNav == _TvNavItem.regions) {
          unawaited(_loadRegion());
        }
      });
    }

    return Column(
      children: [
        SizedBox(
          height: 50,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            scrollDirection: Axis.horizontal,
            itemCount: biliRegionSections.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final section = biliRegionSections[index];
              final selected = _selectedRegion.id == section.id;
              return _TvRegionPill(
                section: section,
                selected: selected,
                autofocus: index == 0,
                onTap: () => unawaited(_loadRegion(section: section)),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildRegionContentGrid()),
      ],
    );
  }

  Widget _buildRegionContentGrid() {
    if (_regionLoading && _regionItems.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0x88FFFFFF)),
      );
    }
    final error = _regionErrorMessage;
    if (error != null && _regionItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Color(0x66FFFFFF),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                error,
                style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TvGlassSelectable(
                autofocus: true,
                borderRadius: 12,
                onTap: () => unawaited(_loadRegion()),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                builder: (context, state) => const Text(
                  '重新加载',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_regionItems.isEmpty) {
      return const Center(
        child: Text(
          '暂无内容',
          style: TextStyle(color: Color(0x88FFFFFF), fontSize: 16),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 720) {
          _requestMoreRegion();
        }
        return false;
      },
      child: _TvGridOverlayScope(
        child: CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                28,
                _tvGridFocusInset,
                28,
                _tvGridFocusInset,
              ),
              sliver: _TvRegionVideoGrid(
                items: _regionItems,
                onTapItem: _openRegionVideo,
                onFocusItem: (item, focused) =>
                    _scheduleHeroUpdate(_TvHeroItem.region(item), focused),
                onNearEnd: _requestMoreRegion,
              ),
            ),
            if (_regionLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0x88FFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPage() {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(28, 0, 28, keyboardBottom),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: GlassContainer(
              useOwnLayer: true,
              quality: TvGlassQualityScope.of(context),
              shape: const LiquidRoundedSuperellipse(
                borderRadius: AppVisualTokens.controlRadius,
              ),
              settings: const LiquidGlassSettings(
                blur: 8,
                thickness: 18,
                glassColor: Color(0x18409EFF),
              ),
              child: SignalBuilder(
                builder: (context) {
                  return TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: '搜索视频、BV 号或链接',
                      hintStyle: const TextStyle(
                        color: Color(0x66FFFFFF),
                        fontWeight: FontWeight.w400,
                      ),
                      filled: true,
                      fillColor: Colors.transparent,
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xAA409EFF),
                        size: 22,
                      ),
                      suffixIcon: _TvSearchSuffixIcon(
                        loading: _viewModel.isSearching.value,
                        visible: _searchController.text.isNotEmpty,
                        onClear: () {
                          _searchController.clear();
                          _viewModel.clearSearch();
                        },
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: (_) {
                      setState(() {});
                      _viewModel.updateQuery(_searchController.text);
                    },
                    onSubmitted: (_) => _runSearch(),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SignalBuilder(
              builder: (context) {
                final results = _viewModel.results.value;
                if (_viewModel.isSearching.value && results.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0x88FFFFFF)),
                  );
                }
                final searchErrorMessage = _viewModel.searchErrorMessage.value;
                if (searchErrorMessage != null && results.isEmpty) {
                  return Center(
                    child: Text(
                      searchErrorMessage,
                      style: const TextStyle(
                        color: Color(0x88FFFFFF),
                        fontSize: 15,
                      ),
                    ),
                  );
                }
                if (_viewModel.activeSearchKeyword.value != null &&
                    results.isEmpty) {
                  return const Center(
                    child: Text(
                      '没有搜到内容',
                      style: TextStyle(color: Color(0x88FFFFFF), fontSize: 16),
                    ),
                  );
                }
                return _TvGridOverlayScope(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final gridCrossAxisExtent =
                          constraints.maxWidth - _tvGridFocusInset * 2;
                      final coverCacheWidth = biliTvCoverCacheWidth(
                        tileWidth: biliTvVideoGridTileWidthForCrossAxisExtent(
                          gridCrossAxisExtent,
                        ),
                        devicePixelRatio: MediaQuery.devicePixelRatioOf(
                          context,
                        ),
                      );
                      return GridView.builder(
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.fromLTRB(
                          _tvGridFocusInset,
                          _tvGridFocusInset,
                          _tvGridFocusInset,
                          _tvGridFocusInset,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: _tvGridMaxCrossAxisExtent,
                              mainAxisSpacing: _tvGridMainAxisSpacing,
                              crossAxisSpacing: _tvGridCrossAxisSpacing,
                              childAspectRatio: _tvGridChildAspectRatio,
                            ),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final result = results[index];
                          return _TvSearchResultCard(
                            coverUrl: result.coverUrl,
                            coverCacheWidth: coverCacheWidth,
                            title: result.title,
                            author: result.author,
                            duration: result.durationLabel,
                            playCount: result.playCountLabel,
                            onFocusChange: (focused) => _scheduleHeroUpdate(
                              _TvHeroItem.search(result),
                              focused,
                            ),
                            onTap: () => _openPlayback(result.bvid),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchFocusNode.hasFocus) {
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
        );
      }
    });
  }

  void _requestSearchFocusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedNav != _TvNavItem.search) {
        return;
      }
      _searchFocusNode.requestFocus();
    });
  }

  Widget _buildHistoryPage() {
    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_rounded,
                color: const Color(0x66FFFFFF),
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                '还没有播放历史',
                style: TextStyle(color: Color(0x88FFFFFF), fontSize: 16),
              ),
              const SizedBox(height: 16),
              TvFocusable(
                autofocus: true,
                onTap: () {
                  setState(() {
                    _selectedNav = _TvNavItem.recommend;
                  });
                  unawaited(_viewModel.loadFeed());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '去看看推荐',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _TvGridOverlayScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final coverCacheWidth = biliTvCoverCacheWidth(
            tileWidth: biliTvVideoGridTileWidthForCrossAxisExtent(
              constraints.maxWidth - _tvGridFocusInset * 2,
            ),
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          );
          return GridView.builder(
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(
              28,
              _tvGridFocusInset,
              28,
              _tvGridFocusInset,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _tvGridMaxCrossAxisExtent,
              mainAxisSpacing: _tvGridMainAxisSpacing,
              crossAxisSpacing: _tvGridCrossAxisSpacing,
              childAspectRatio: _tvGridChildAspectRatio,
            ),
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final entry = _history[index];
              final progress = entry.durationMs != null && entry.durationMs! > 0
                  ? entry.lastPositionMs / entry.durationMs!
                  : 0.0;
              return _TvHistoryCard(
                coverUrl: entry.coverUrl,
                coverCacheWidth: coverCacheWidth,
                title: entry.videoTitle,
                subtitle: entry.pageTitle,
                ownerName: entry.ownerName,
                progress: progress,
                onFocusChange: (focused) =>
                    _scheduleHeroUpdate(_TvHeroItem.history(entry), focused),
                onTap: () => _openPlayback(
                  entry.bvid,
                  aid: entry.aid,
                  cid: entry.cid > 0 ? entry.cid : null,
                  episodeId: entry.episodeId > 0 ? entry.episodeId : null,
                  initialPositionMs: entry.lastPositionMs,
                ),
                autofocus: index == 0,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMinePage() {
    return SignalBuilder(
      builder: (context) {
        final profile = _viewModel.profile.value;
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 760 || constraints.maxHeight < 390;
            final account = _buildMineAccount(profile, compact: compact);
            final library = _buildMineLibraryActions(compact: compact);
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                28,
                compact ? 8 : 22,
                28,
                compact ? 24 : 36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            account,
                            const SizedBox(height: 22),
                            library,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 5, child: account),
                            const SizedBox(width: 48),
                            Expanded(flex: 6, child: library),
                          ],
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMineAccount(BiliUserProfile profile, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: compact ? 32 : 40,
              backgroundColor: const Color(0x33FFFFFF),
              backgroundImage: profile.avatarUrl.isNotEmpty
                  ? NetworkImage(profile.avatarUrl)
                  : null,
              child: profile.avatarUrl.isEmpty
                  ? Icon(
                      Icons.person_rounded,
                      color: const Color(0x99FFFFFF),
                      size: compact ? 30 : 36,
                    )
                  : null,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.isLoggedIn ? profile.name : '未登录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    profile.isLoggedIn ? '账号已登录' : '登录后同步账号内容',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0x77FFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 16 : 24),
        if (!profile.isLoggedIn)
          _TvMineCommand(
            key: const ValueKey<String>('bili-tv-mine-login'),
            autofocus: true,
            icon: Icons.qr_code_scanner_rounded,
            label: '扫码登录',
            primary: true,
            onTap: () => unawaited(_openQrLogin()),
          )
        else
          Row(
            children: [
              Expanded(
                child: _TvMineCommand(
                  key: const ValueKey<String>('bili-tv-mine-logout'),
                  autofocus: true,
                  icon: Icons.logout_rounded,
                  label: '退出登录',
                  onTap: () => unawaited(_confirmLogout()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TvMineCommand(
                  key: const ValueKey<String>('bili-tv-mine-refresh'),
                  icon: Icons.refresh_rounded,
                  label: '刷新状态',
                  onTap: () => unawaited(_viewModel.refreshMine()),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildMineLibraryActions({required bool compact}) {
    final visualTheme = AppVisualTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '我的内容',
          style: TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: visualTheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: visualTheme.imageOutline),
            boxShadow: [
              BoxShadow(
                color: visualTheme.shadow,
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _TvLibraryAction(
                  key: const ValueKey<String>('bili-tv-mine-history'),
                  icon: Icons.history_rounded,
                  label: '历史播放',
                  compact: compact,
                  onTap: () =>
                      unawaited(_openLibrary(BiliLibrarySection.history)),
                ),
              ),
              Container(width: 1, height: 54, color: visualTheme.divider),
              Expanded(
                child: _TvLibraryAction(
                  key: const ValueKey<String>('bili-tv-mine-watch-later'),
                  icon: Icons.watch_later_outlined,
                  label: '稍后再看',
                  compact: compact,
                  onTap: () =>
                      unawaited(_openLibrary(BiliLibrarySection.watchLater)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 420;
        return Align(
          alignment: compactHeight ? Alignment.topCenter : Alignment.center,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              compactHeight ? 4 : 24,
              24,
              compactHeight ? 24 : 36,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _buildSettingsPanelContent(compact: compactHeight),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsPanelContent({required bool compact}) {
    final modeChanged = _forceTvMode != _initialForceTvMode;
    final visualTheme = AppVisualTheme.of(context);
    return Container(
      padding: EdgeInsets.all(compact ? 22 : 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TV 设置',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 14 : 24),
          TvGlassSelectable(
            key: const ValueKey<String>('bili-tv-settings-force-mode-card'),
            autofocus: true,
            scale: 1.025,
            borderRadius: AppVisualTokens.controlRadius,
            focusArea: TvFocusArea.content,
            debugLabel: 'tv_settings_force_mode',
            onTap: () => _toggleForceTvMode(!_forceTvMode),
            builder: (context, state) => DecoratedBox(
              decoration: BoxDecoration(
                color: visualTheme.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(
                  AppVisualTokens.controlRadius,
                ),
                border: Border.all(color: visualTheme.imageOutline),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 18 : 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '强制 TV 模式',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _forceTvMode ? '当前：TV 模式' : '当前：自动检测（根据设备）',
                            style: const TextStyle(
                              color: Color(0x88FFFFFF),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    IgnorePointer(
                      child: Switch(
                        value: _forceTvMode,
                        onChanged: _toggleForceTvMode,
                        activeThumbColor: AppVisualTokens.primaryBlue,
                        activeTrackColor: const Color(0x66409EFF),
                        inactiveThumbColor: const Color(0xDDFFFFFF),
                        inactiveTrackColor: const Color(0x22FFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 12 : 20),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              key: const ValueKey<String>('bili-tv-settings-about-card'),
              decoration: BoxDecoration(
                color: visualTheme.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(
                  AppVisualTokens.controlRadius,
                ),
                border: Border.all(color: visualTheme.imageOutline),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 18 : 24),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '关于 Vesper',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Vesper 1.2.0 · TV',
                      style: TextStyle(color: Color(0x88FFFFFF), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (modeChanged) ...[
            SizedBox(height: compact ? 12 : 20),
            Center(
              child: TvFocusable(
                autofocus: false,
                scale: 1.05,
                focusCornerRadius: 14,
                baseCornerRadius: 14,
                showGlow: false,
                onTap: () async {
                  final nextMode = await refreshUiMode();
                  await _applyPresentationFor(nextMode);
                  if (!mounted) {
                    return;
                  }
                  _restorePresentationOnDispose = false;
                  Navigator.of(context).pushAndRemoveUntil(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, a, b) => const HomePage(),
                      transitionsBuilder: (_, animation, c, child) {
                        return FadeTransition(
                          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOutCubic,
                            ),
                          ),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeInOutCubic,
                              ),
                            ),
                            child: child,
                          ),
                        );
                      },
                      transitionDuration: const Duration(milliseconds: 400),
                    ),
                    (_) => false,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppVisualTokens.primaryBlue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '返回首页并切换',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
          SizedBox(height: compact ? 12 : 20),
          const Text(
            '提示：开启强制 TV 模式后，应用将在手机和平板上也显示 TV 界面。'
            '关闭后将根据设备自动选择界面。模式切换将在返回首页后生效。',
            style: TextStyle(
              color: Color(0x66FFFFFF),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openQrLogin() async {
    final profile = await showBiliTvQrLoginDialog(
      context: context,
      client: _viewModel.client,
      sessionStore: _viewModel.sessionStore,
    );
    if (profile == null || !mounted) {
      return;
    }
    await _viewModel.applyLoggedInProfile(profile);
    await _loadHistory();
    setState(() {});
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showBiliTvGlassDialog<bool>(
      context: context,
      title: '退出登录？',
      message: '本机保存的登录状态会被清除，正在进行的离线缓存也会暂停。',
      icon: Icons.logout_rounded,
      actions: const [
        BiliTvDialogAction(
          label: '取消',
          value: false,
          icon: Icons.close_rounded,
          autofocus: true,
        ),
        BiliTvDialogAction(
          label: '退出登录',
          value: true,
          icon: Icons.logout_rounded,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _viewModel.logout();
      await _loadHistory();
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        _showMessage('退出登录失败：$error');
      }
    }
  }

  Future<bool?> _confirmRegionLogin() {
    return showBiliTvGlassDialog<bool>(
      context: context,
      title: '需要登录',
      message: '分区内容需要登录后才能观看，请先登录 Bilibili 账号。',
      icon: Icons.lock_outline_rounded,
      actions: const [
        BiliTvDialogAction(
          label: '取消',
          value: false,
          icon: Icons.close_rounded,
          autofocus: true,
        ),
        BiliTvDialogAction(label: '登录', value: true, icon: Icons.login_rounded),
      ],
    );
  }
}

class _TvHeroAction extends StatelessWidget {
  const _TvHeroAction({
    required this.label,
    required this.icon,
    required this.debugLabel,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final String debugLabel;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TvGlassSelectable(
      useOwnLayer: false,
      scale: 1.025,
      borderRadius: AppVisualTokens.controlRadius,
      focusArea: TvFocusArea.content,
      debugLabel: debugLabel,
      onTap: onTap,
      builder: (context, state) {
        final focused = state == TvGlassSelectableState.focused;
        final pressed = state == TvGlassSelectableState.pressed;
        return AnimatedContainer(
          duration: AppVisualTokens.motionDuration(
            context,
            AppVisualTokens.buttonPressDuration,
          ),
          width: primary ? 174 : 142,
          height: 52,
          decoration: BoxDecoration(
            color: primary
                ? AppVisualTokens.primaryBlue
                : focused || pressed
                ? const Color(0x3DFFFFFF)
                : const Color(0x24FFFFFF),
            borderRadius: BorderRadius.circular(AppVisualTokens.controlRadius),
            boxShadow: primary
                ? const [
                    BoxShadow(
                      color: Color(0x33409EFF),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          padding: const EdgeInsets.only(left: 17, right: 19),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: icon == Icons.play_arrow_rounded ? 2 : 0,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvMediaShelf extends StatelessWidget {
  const _TvMediaShelf({
    super.key,
    required this.title,
    required this.controller,
    required this.itemCount,
    required this.cardWidth,
    required this.itemBuilder,
  });

  final String title;
  final ScrollController controller;
  final int itemCount;
  final double cardWidth;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final cardHeight = cardWidth / (16 / 9) + 58;
    return TvFocusGroupScope(
      group: ValueKey<String>('tv-shelf-focus-$title'),
      onDirectionalEdge: (direction) {
        if (!controller.hasClients ||
            (direction != TraversalDirection.left &&
                direction != TraversalDirection.right)) {
          return false;
        }
        final position = controller.position;
        final delta = cardWidth + 14;
        final target = switch (direction) {
          TraversalDirection.left => (position.pixels - delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
          TraversalDirection.right => (position.pixels + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
          _ => position.pixels,
        };
        if ((target - position.pixels).abs() < 1) {
          return false;
        }
        unawaited(
          controller.animateTo(
            target,
            duration: AppVisualTokens.motionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            curve: Curves.easeOutCubic,
          ),
        );
        return true;
      },
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: cardHeight + _tvGridFocusInset * 2,
                child: Overlay.wrap(
                  clipBehavior: Clip.none,
                  child: ListView.separated(
                    key: ValueKey<String>('tv-shelf-list-$title'),
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    scrollCacheExtent: ScrollCacheExtent.pixels(
                      cardWidth * 2.5,
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      _tvGridFocusInset,
                      _tvGridFocusInset,
                      34,
                      _tvGridFocusInset,
                    ),
                    itemCount: itemCount,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, index) => SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: itemBuilder(context, index),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvGridOverlayScope extends StatelessWidget {
  const _TvGridOverlayScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(clipBehavior: Clip.hardEdge, child: child);
  }
}

class _TvSearchSuffixIcon extends StatelessWidget {
  const _TvSearchSuffixIcon({
    required this.loading,
    required this.visible,
    required this.onClear,
  });

  final bool loading;
  final bool visible;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>('bili-tv-search-suffix'),
      width: 48,
      height: 48,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: loading
              ? const SizedBox(
                  key: ValueKey<String>('search-loading'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0x88FFFFFF),
                  ),
                )
              : visible
              ? IconButton(
                  key: const ValueKey<String>('search-clear'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0x88FFFFFF),
                    size: 20,
                  ),
                  onPressed: onClear,
                )
              : const SizedBox.shrink(key: ValueKey<String>('search-empty')),
        ),
      ),
    );
  }
}

class _TvRegionVideoGrid extends StatelessWidget {
  const _TvRegionVideoGrid({
    required this.items,
    required this.onTapItem,
    required this.onFocusItem,
    required this.onNearEnd,
  });

  final List<BiliRegionVideo> items;
  final void Function(BiliRegionVideo item) onTapItem;
  final void Function(BiliRegionVideo item, bool focused) onFocusItem;
  final VoidCallback onNearEnd;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final coverCacheWidth = biliTvCoverCacheWidth(
          tileWidth: biliTvVideoGridTileWidthForCrossAxisExtent(
            constraints.crossAxisExtent,
          ),
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        return SliverGrid.builder(
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _tvGridMaxCrossAxisExtent,
            mainAxisSpacing: _tvGridMainAxisSpacing,
            crossAxisSpacing: _tvGridCrossAxisSpacing,
            childAspectRatio: _tvGridChildAspectRatio,
          ),
          itemBuilder: (context, index) {
            if (index >= items.length - 8) {
              onNearEnd();
            }
            final item = items[index];
            final subtitle = item.seasonId != null
                ? item.indexLabel ?? item.followCountLabel ?? '番剧'
                : item.subtitle ?? item.followCountLabel ?? '';
            final duration = item.seasonId != null
                ? item.scoreLabel == null
                      ? '剧集'
                      : '${item.scoreLabel}分'
                : item.indexLabel ?? '';
            return _TvVideoCard(
              key: ValueKey('region_${item.id}'),
              coverUrl: item.coverUrl,
              coverCacheWidth: coverCacheWidth,
              title: item.title,
              author: subtitle,
              duration: duration,
              playCount: item.followCountLabel ?? '',
              onFocusChange: (focused) => onFocusItem(item, focused),
              onTap: () => onTapItem(item),
            );
          },
        );
      },
    );
  }
}

class _TvRegionPill extends StatelessWidget {
  const _TvRegionPill({
    required this.section,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final BiliRegionSection section;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvGlassSelectable(
      autofocus: autofocus,
      selected: selected,
      scale: 1.06,
      borderRadius: AppVisualTokens.controlRadius,
      focusArea: TvFocusArea.content,
      debugLabel: 'region_${section.id}',
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      builder: (context, state) {
        final focused =
            state == TvGlassSelectableState.focused ||
            state == TvGlassSelectableState.pressed;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(section.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(
              section.name,
              style: TextStyle(
                color: focused || selected
                    ? Colors.white
                    : const Color(0xAAFFFFFF),
                fontSize: 15,
                fontWeight: focused || selected
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppVisualTokens.primaryBlue,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TvVideoCard extends StatelessWidget {
  const _TvVideoCard({
    super.key,
    required this.coverUrl,
    required this.coverCacheWidth,
    required this.title,
    required this.author,
    required this.duration,
    required this.playCount,
    required this.onTap,
    this.onFocusChange,
  });

  final String coverUrl;
  final int coverCacheWidth;
  final String title;
  final String author;
  final String duration;
  final String playCount;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    return TvFocusableSurface(
      scale: 1.07,
      focusPadding: _tvCardFocusPadding,
      useOverlayLift: true,
      focusArea: TvFocusArea.content,
      debugLabel: 'video_$title',
      onFocusChange: onFocusChange,
      onTap: onTap,
      builder: (context, focused) => LayoutBuilder(
        builder: (context, constraints) {
          final boundedHeight = constraints.hasBoundedHeight;
          final tight = boundedHeight && constraints.maxHeight < 116;
          final condensed = boundedHeight && constraints.maxHeight < 136;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFF1A1A24),
                        child: coverUrl.isEmpty
                            ? const Icon(
                                Icons.video_library_outlined,
                                color: Color(0x55FFFFFF),
                                size: 40,
                              )
                            : Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: coverCacheWidth,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: Color(0xFF1A1A24)),
                              ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 6,
                        child: Text(
                          playCount,
                          style: const TextStyle(
                            color: Color(0xDDFFFFFF),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            duration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: condensed ? 4 : 5),
              Text(
                title,
                maxLines: tight ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: focused ? Colors.white : const Color(0xEEFFFFFF),
                  fontSize: condensed ? 12 : 12.2,
                  fontWeight: focused ? FontWeight.w800 : FontWeight.w600,
                  height: 1.17,
                ),
              ),
              if (!condensed) ...[
                const SizedBox(height: 2),
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x66FFFFFF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TvSearchResultCard extends StatelessWidget {
  const _TvSearchResultCard({
    required this.coverUrl,
    required this.coverCacheWidth,
    required this.title,
    required this.author,
    required this.duration,
    required this.playCount,
    required this.onTap,
    this.onFocusChange,
  });

  final String coverUrl;
  final int coverCacheWidth;
  final String title;
  final String author;
  final String duration;
  final String playCount;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    return _TvVideoCard(
      coverUrl: coverUrl,
      coverCacheWidth: coverCacheWidth,
      title: title,
      author: author,
      duration: duration,
      playCount: playCount,
      onFocusChange: onFocusChange,
      onTap: onTap,
    );
  }
}

class _TvHistoryCard extends StatelessWidget {
  const _TvHistoryCard({
    super.key,
    required this.coverUrl,
    required this.coverCacheWidth,
    required this.title,
    required this.subtitle,
    required this.ownerName,
    required this.progress,
    required this.onTap,
    this.autofocus = false,
    this.onFocusChange,
  });

  final String coverUrl;
  final int coverCacheWidth;
  final String title;
  final String subtitle;
  final String ownerName;
  final double progress;
  final VoidCallback onTap;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    return TvFocusableSurface(
      autofocus: autofocus,
      scale: 1.07,
      focusPadding: _tvCardFocusPadding,
      useOverlayLift: true,
      focusArea: TvFocusArea.content,
      debugLabel: 'history_$title',
      onFocusChange: onFocusChange,
      onTap: onTap,
      builder: (context, focused) => LayoutBuilder(
        builder: (context, constraints) {
          final boundedHeight = constraints.hasBoundedHeight;
          final tight = boundedHeight && constraints.maxHeight < 116;
          final condensed = boundedHeight && constraints.maxHeight < 136;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFF1A1A24),
                        child: coverUrl.isEmpty
                            ? const Icon(
                                Icons.video_library_outlined,
                                color: Color(0x55FFFFFF),
                                size: 40,
                              )
                            : Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: coverCacheWidth,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: Color(0xFF1A1A24)),
                              ),
                      ),
                      if (progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            backgroundColor: const Color(0x33000000),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppVisualTokens.primaryBlue,
                            ),
                            minHeight: 3,
                          ),
                        ),
                      Positioned(
                        right: 8,
                        bottom: progress > 0 ? 10 : 7,
                        child: Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: condensed ? 4 : 5),
              Text(
                title,
                maxLines: tight ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: focused ? Colors.white : const Color(0xEEFFFFFF),
                  fontSize: condensed ? 12 : 12.2,
                  fontWeight: focused ? FontWeight.w800 : FontWeight.w600,
                  height: 1.17,
                ),
              ),
              if (!condensed) ...[
                const SizedBox(height: 2),
                Text(
                  '$ownerName · $subtitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x66FFFFFF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TvLibraryAction extends StatelessWidget {
  const _TvLibraryAction({
    super.key,
    required this.icon,
    required this.label,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvGlassSelectable(
      scale: 1.045,
      borderRadius: 12,
      focusArea: TvFocusArea.content,
      debugLabel: 'mine_library_$label',
      onTap: onTap,
      builder: (context, state) => SizedBox(
        width: double.infinity,
        height: compact ? 68 : 104,
        child: Flex(
          direction: compact ? Axis.horizontal : Axis.vertical,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xCCFFFFFF), size: compact ? 22 : 30),
            SizedBox(width: compact ? 9 : 0, height: compact ? 0 : 10),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xDDFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvMineCommand extends StatelessWidget {
  const _TvMineCommand({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TvGlassSelectable(
      autofocus: autofocus,
      scale: 1.045,
      borderRadius: 12,
      selected: primary,
      focusArea: TvFocusArea.content,
      debugLabel: 'mine_command_$label',
      onTap: onTap,
      builder: (context, state) => SizedBox(
        width: double.infinity,
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
