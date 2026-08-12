import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/app/app_version.dart';
import 'package:vesper_media/app/system_presentation.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/models/bili_region_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/app/services/bili_ui_mode_controller.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/common/services/bili_text.dart';
import 'package:vesper_media/bili/common/services/bili_ui_mode_resolver.dart';
import 'package:vesper_media/bili/common/view_models/bili_hub_view_model.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_page.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_library_page.dart';
import 'package:vesper_media/media/tv/media_tv_focusable.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_directional_focus_scope.dart';
import 'package:vesper_media/bili/tv_mode/widgets/bili_tv_qr_login_dialog.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_glass_dialog.dart';
import 'package:vesper_media/app/home_page.dart';
import 'package:vesper_media/download/download.dart';

part 'bili_tv_hero.dart';
part 'bili_tv_cards.dart';
part 'bili_tv_account.dart';
part 'bili_tv_home_controller.dart';
part 'bili_tv_home_shell.dart';
part 'bili_tv_home_content.dart';
part 'bili_tv_home_browse_content.dart';
part 'bili_tv_home_account_content.dart';

enum _TvNavItem {
  recommend,
  following,
  regions,
  search,
  history,
  mine,
  settings,
}

const _tvGridMaxCrossAxisExtent = 184.0;
const _tvGridMaxCrossAxisExtentCeiling = 320.0;
// Keep ResizeImage keys independent from the animated rail constraint. Use
// the largest supported TV tile width for every cover in this page.
const _tvCoverDecodeLogicalWidth = _tvGridMaxCrossAxisExtentCeiling;
const _tvGridGrowthStartWidth = 1100.0;
const _tvGridGrowthEndWidth = 2600.0;
const _tvGridMainAxisSpacing = 14.0;
const _tvGridCrossAxisSpacing = 16.0;
const _tvGridChildAspectRatio = 1.14;
const _tvCardFocusPadding = 12.0;
const _tvGridFocusInset = 32.0;
const _tvHeroFocusDelay = Duration(milliseconds: 120);
const _tvHeroCrossFadeDuration = Duration(milliseconds: 260);
const _tvNestedRailGap = 12.0;

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
double biliTvGridMaxCrossAxisExtentForWidth(double crossAxisExtent) {
  assert(crossAxisExtent >= 0);
  final progress =
      ((crossAxisExtent - _tvGridGrowthStartWidth) /
              (_tvGridGrowthEndWidth - _tvGridGrowthStartWidth))
          .clamp(0.0, 1.0);
  return _tvGridMaxCrossAxisExtent +
      (_tvGridMaxCrossAxisExtentCeiling - _tvGridMaxCrossAxisExtent) * progress;
}

@visibleForTesting
double biliTvVideoGridTileWidthForCrossAxisExtent(
  double crossAxisExtent, {
  double maxCrossAxisExtent = _tvGridMaxCrossAxisExtent,
}) {
  assert(crossAxisExtent >= 0);
  assert(maxCrossAxisExtent > 0);
  final calculatedCrossAxisCount =
      (crossAxisExtent / (maxCrossAxisExtent + _tvGridCrossAxisSpacing)).ceil();
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
      _TvNavItem.following => '关注列表',
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
      _TvNavItem.following => Icons.people_alt_rounded,
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
    this.uiModeController,
    this.initialHistoryEntries = const <BiliPlaybackHistoryEntry>[],
    this.skipBootstrap = false,
  });

  final BiliClient? client;
  final BiliHistoryStore? historyStore;
  final BiliSessionStore? sessionStore;
  final BiliOfflineDownloadController? offlineController;
  final AppSettingsStore? appSettings;
  final BiliUiModeController? uiModeController;
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
  late final BiliUiModeController _uiModeController;
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'tv_search_field');
  final FocusNode _heroPlayFocusNode = FocusNode(debugLabel: 'tv_hero_play');
  final ScrollController _contentScrollController = ScrollController();
  final ScrollController _continueShelfController = ScrollController();

  _TvNavItem _selectedNav = _TvNavItem.recommend;
  _TvNavItem _lastPrimaryNav = _TvNavItem.recommend;
  bool _followingPaneActivated = false;
  bool _homeRailExpanded = true;
  bool _forceTvMode = false;
  bool _initialForceTvMode = false;
  bool _feedLoadMoreQueued = false;
  bool _regionLoadMoreQueued = false;
  int _presentationGeneration = 0;
  int _regionPage = 1;
  String _appVersion = '';

  List<BiliPlaybackHistoryEntry> _history = const [];
  BiliRegionSection _selectedRegion = biliRegionSections.first;
  List<BiliRegionVideo> _regionItems = const <BiliRegionVideo>[];
  bool _regionLoading = false;
  bool _regionLoadingMore = false;
  bool _hasMoreRegion = true;
  String? _regionErrorMessage;
  bool _restorePresentationOnDispose = true;
  bool _exitDialogVisible = false;
  TvFocusArea? _activeFocusArea = TvFocusArea.homeRail;
  _TvHeroItem? _heroItem;
  Timer? _heroUpdateTimer;
  bool _heroHasUserSelection = false;
  bool _uiModeControllerTransferred = false;

  @override
  void initState() {
    super.initState();
    unawaited(_enterTvHomePresentation());
    unawaited(_loadAppVersion());
    _searchController = TextEditingController();
    setTvFocusArea(_searchFocusNode, TvFocusArea.content);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _appSettings = widget.appSettings ?? const AppSettingsStore();
    _uiModeController =
        widget.uiModeController ??
        BiliUiModeController(
          resolver: BiliUiModeResolver(appSettings: _appSettings),
        );
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
    _heroPlayFocusNode.dispose();
    _searchController.dispose();
    _contentScrollController.dispose();
    _continueShelfController.dispose();
    _heroUpdateTimer?.cancel();
    _viewModel.dispose();
    if (widget.uiModeController == null && !_uiModeControllerTransferred) {
      _uiModeController.dispose();
    }
    if (_restorePresentationOnDispose) {
      unawaited(_restoreAppPresentation());
    }
    super.dispose();
  }

  void _mutate(VoidCallback mutation) => setState(mutation);

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
                  final railExpanded = _homeRailExpanded;
                  final collapsedRailWidth = wide ? 88.0 : 80.0;
                  final railWidth = railExpanded
                      ? (wide ? 300.0 : 260.0)
                      : collapsedRailWidth;
                  final margin = wide ? 28.0 : 20.0;
                  final followingSelected =
                      _selectedNav == _TvNavItem.following;
                  final contentInset = followingSelected
                      ? collapsedRailWidth + margin + _tvNestedRailGap
                      : railWidth + margin + _tvNestedRailGap;
                  final followingRailOffset = railWidth - collapsedRailWidth;
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
                          child: _buildContentArea(
                            followingRailOffset: followingRailOffset,
                            followingVerticalInset: margin,
                          ),
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
                          area: TvFocusArea.homeRail,
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
}
