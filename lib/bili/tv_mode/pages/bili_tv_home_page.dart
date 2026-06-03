import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import 'package:bilibili_player/app/system_presentation.dart';
import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/models/bili_region_models.dart';
import 'package:bilibili_player/bili/common/services/bili_app_settings.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:bilibili_player/bili/common/services/bili_session_store.dart';
import 'package:bilibili_player/bili/common/services/bili_text.dart';
import 'package:bilibili_player/bili/common/services/bili_ui_mode_resolver.dart';
import 'package:bilibili_player/bili/common/view_models/bili_hub_view_model.dart';
import 'package:bilibili_player/bili/common/pages/bili_playback_page.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_focusable.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_directional_focus_scope.dart';
import 'package:bilibili_player/bili/common/widgets/bili_qr_login_sheet.dart';
import 'package:bilibili_player/app/home_page.dart';
import 'package:bilibili_player/download/download.dart';
import 'package:bilibili_player/main.dart';

enum _TvNavItem { recommend, regions, search, history, mine, settings }

const _tvGridMaxCrossAxisExtent = 184.0;
const _tvGridMainAxisSpacing = 14.0;
const _tvGridCrossAxisSpacing = 16.0;
const _tvGridChildAspectRatio = 1.14;
const _tvCardFocusPadding = 14.0;
const _tvGridFocusInset = _tvCardFocusPadding * 2;

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
    this.skipBootstrap = false,
  });

  final BiliClient? client;
  final BiliHistoryStore? historyStore;
  final BiliSessionStore? sessionStore;
  final BiliOfflineDownloadController? offlineController;
  final BiliAppSettings? appSettings;
  @visibleForTesting
  final List<BiliFeedVideo> initialFeedItems;
  @visibleForTesting
  final bool skipBootstrap;

  @override
  State<BiliTvHomePage> createState() => _BiliTvHomePageState();
}

class _BiliTvHomePageState extends State<BiliTvHomePage> {
  late final BiliHubViewModel _viewModel;
  late final BiliAppSettings _appSettings;
  late final TextEditingController _searchController;
  final ScrollController _contentScrollController = ScrollController();

  _TvNavItem _selectedNav = _TvNavItem.recommend;
  _TvNavItem? _focusedNav;
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

  @override
  void initState() {
    super.initState();
    unawaited(_enterTvHomePresentation());
    _searchController = TextEditingController();
    _appSettings = widget.appSettings ?? const BiliAppSettings();
    _viewModel = BiliHubViewModel(
      client: widget.client,
      historyStore: widget.historyStore,
      sessionStore: widget.sessionStore,
      offlineController: widget.offlineController,
    );
    if (widget.initialFeedItems.isNotEmpty || widget.skipBootstrap) {
      _viewModel.seedFeedForTesting(widget.initialFeedItems);
    }
    if (!widget.skipBootstrap) {
      unawaited(_bootstrap());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _contentScrollController.dispose();
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
      orientations: biliAppDefaultOrientations,
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
    required List<DeviceOrientation> orientations,
    required SystemUiMode systemUiMode,
    required SystemUiOverlayStyle overlayStyle,
  }) async {
    final generation = ++_presentationGeneration;
    await setBiliPreferredOrientations(orientations);
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
    final forceTvMode = await _appSettings.getForceTvMode();
    _forceTvMode = forceTvMode;
    _initialForceTvMode = forceTvMode;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadHistory() async {
    _history = await (_viewModel.historyStore).loadEntries();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openPlayback(String bvid, {int? cid}) async {
    late final BiliHubPlaybackTarget target;
    try {
      target = await _viewModel.resolvePlaybackTarget(bvid, cid: cid);
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
          presentationMode: BiliPlaybackPresentationMode.tv,
        ),
      ),
    );
    await _viewModel.loadHistory();
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
    await _viewModel.loadHistory();
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
        _hasMoreRegion = items.length >= 20;
        _regionLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _regionErrorMessage = error.toString();
        _regionLoading = false;
      });
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmExitApp());
        }
      },
      child: TvDirectionalFocusScope(
        debugLabel: 'tv_home',
        onBack: () => unawaited(_confirmExitApp()),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: const Color(0xFF0A0A0E),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final railWidth = constraints.maxWidth < 900 ? 184.0 : 216.0;
              return Row(
                children: [
                  TvFocusAreaScope(
                    area: TvFocusArea.rail,
                    child: _buildLeftRail(railWidth),
                  ),
                  Expanded(
                    child: TvFocusAreaScope(
                      area: TvFocusArea.content,
                      child: _buildContentArea(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmExitApp() async {
    if (!mounted) {
      return;
    }
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF202027),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: const TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 15,
            height: 1.45,
          ),
          title: const Text('退出应用'),
          content: const Text('确定要退出 bilibili_player 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('退出'),
            ),
          ],
        );
      },
    );
    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }

  Widget _buildLeftRail(double width) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          key: const ValueKey<String>('bili-tv-left-rail'),
          width: width,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x88000000)],
            ),
            border: Border(
              right: BorderSide(color: Color(0x11FFFFFF), width: 0.5),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactHeight = constraints.maxHeight < 360;
              return ListView(
                padding: EdgeInsets.only(
                  top: compactHeight ? 20 : 32,
                  bottom: compactHeight ? 10 : 18,
                ),
                children: [
                  _buildRailProfile(compact: compactHeight),
                  SizedBox(height: compactHeight ? 12 : 18),
                  ..._TvNavItem.values.map(
                    (item) => _buildRailItem(item, compact: compactHeight),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRailProfile({bool compact = false}) {
    return SignalBuilder(
      builder: (context) {
        final profile = _viewModel.profile.value;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
          child: Row(
            children: [
              CircleAvatar(
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
                        color: const Color(0x99FFFFFF),
                        size: compact ? 18 : 20,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  profile.isLoggedIn ? profile.name : '未登录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRailItem(_TvNavItem item, {bool compact = false}) {
    final selected = _selectedNav == item;
    final focused = _focusedNav == item;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 1 : 2,
      ),
      child: TvFocusable(
        autofocus: item == _TvNavItem.recommend,
        scale: 1.035,
        focusElevation: 0,
        focusCornerRadius: 10,
        baseCornerRadius: 10,
        showGlow: false,
        focusArea: TvFocusArea.rail,
        debugLabel: 'nav_${item.name}',
        onFocusChange: (value) {
          setState(() {
            _focusedNav = value
                ? item
                : _focusedNav == item
                ? null
                : _focusedNav;
          });
        },
        onTap: () {
          setState(() {
            _selectedNav = item;
          });
          if (item == _TvNavItem.history) {
            unawaited(_loadHistory());
          }
          if (item == _TvNavItem.recommend) {
            unawaited(_viewModel.loadFeed());
          }
          if (item == _TvNavItem.regions && _regionItems.isEmpty) {
            unawaited(_loadRegion());
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: focused
                ? Colors.white.withValues(alpha: 0.22)
                : selected
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: focused
                  ? const Color(0x99FFFFFF)
                  : const Color(0x00FFFFFF),
              width: 1,
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 10,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: compact ? 22 : 26,
                decoration: BoxDecoration(
                  color: focused || selected
                      ? const Color(0xFFFB7299)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Icon(
                item.icon(),
                color: focused || selected
                    ? Colors.white
                    : const Color(0x99FFFFFF),
                size: focused ? (compact ? 21 : 22) : (compact ? 19 : 20),
              ),
              SizedBox(width: compact ? 8 : 10),
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
                        : const Color(0x88FFFFFF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 0),
          child: Text(
            _selectedNav.label(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: switch (_selectedNav) {
            _TvNavItem.recommend => _buildRecommendPage(),
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

  Widget _buildRecommendPage() {
    return SignalBuilder(
      builder: (context) {
        final items = _viewModel.feedItems.value;
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
                  TvFocusable(
                    autofocus: true,
                    onTap: () => _viewModel.loadFeed(),
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
                        '重新加载',
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
        if (items.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0x88FFFFFF)),
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 720) {
              _requestMoreFeed();
            }
            return false;
          },
          child: _TvGridOverlayScope(
            child: CustomScrollView(
              controller: _contentScrollController,
              clipBehavior: Clip.none,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    28,
                    _tvGridFocusInset,
                    28,
                    _tvGridFocusInset,
                  ),
                  sliver: _TvVideoGrid(
                    items: items,
                    onTapItem: (item) => _openPlayback(item.bvid),
                    onNearEnd: _requestMoreFeed,
                  ),
                ),
                if (_viewModel.isLoadingMoreFeed.value)
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
              TvFocusable(
                autofocus: true,
                onTap: () => unawaited(_loadRegion()),
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
                    '重新加载',
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
            child: SignalBuilder(
              builder: (context) {
                return TextField(
                  controller: _searchController,
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
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0x88FFFFFF),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
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
                  child: GridView.builder(
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
                        title: result.title,
                        author: result.author,
                        duration: result.durationLabel,
                        playCount: result.playCountLabel,
                        onTap: () => _openPlayback(result.bvid),
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
      child: GridView.builder(
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
            title: entry.videoTitle,
            subtitle: entry.pageTitle,
            ownerName: entry.ownerName,
            progress: progress,
            onTap: () => _openPlayback(entry.bvid, cid: entry.cid),
            autofocus: index == 0,
          );
        },
      ),
    );
  }

  Widget _buildMinePage() {
    return SignalBuilder(
      builder: (context) {
        final profile = _viewModel.profile.value;
        return Center(
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: const Color(0x33FFFFFF),
                  backgroundImage: profile.avatarUrl.isNotEmpty
                      ? NetworkImage(profile.avatarUrl)
                      : null,
                  child: profile.avatarUrl.isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          color: Color(0x99FFFFFF),
                          size: 38,
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  profile.isLoggedIn ? profile.name : '未登录',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  profile.isLoggedIn ? '账号已登录' : '扫描二维码登录后同步推荐与播放解析',
                  style: const TextStyle(
                    color: Color(0x77FFFFFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 28),
                if (!profile.isLoggedIn)
                  TvFocusable(
                    autofocus: true,
                    onTap: () => unawaited(_openQrLogin()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFB7299),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        '扫码登录',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                else ...[
                  TvFocusable(
                    autofocus: true,
                    onTap: () async {
                      await _viewModel.logout();
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        '退出登录',
                        style: TextStyle(
                          color: Color(0xFFDDDDDD),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TvFocusable(
                    onTap: () => unawaited(_viewModel.refreshMine()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        '刷新账号状态',
                        style: TextStyle(
                          color: Color(0xBBFFFFFF),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 18 : 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TvFocusable(
              autofocus: true,
              scale: 1.035,
              focusCornerRadius: 16,
              baseCornerRadius: 16,
              showGlow: false,
              onTap: () => _toggleForceTvMode(!_forceTvMode),
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
                      activeThumbColor: const Color(0xFFFB7299),
                      activeTrackColor: const Color(0x66FB7299),
                      inactiveThumbColor: const Color(0xDDFFFFFF),
                      inactiveTrackColor: const Color(0x22FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: compact ? 12 : 20),
          Container(
            key: const ValueKey<String>('bili-tv-settings-about-card'),
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 18 : 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '关于',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'bilibili_player 0.1.0 - TV Preview',
                  style: TextStyle(color: Color(0x88FFFFFF), fontSize: 13),
                ),
              ],
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
                    color: const Color(0xFFFB7299),
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
    final profile = await showModalBottomSheet<BiliUserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BiliQrLoginSheet(
        client: _viewModel.client,
        sessionStore: _viewModel.sessionStore,
      ),
    );
    if (profile == null || !mounted) {
      return;
    }
    await _viewModel.applyLoggedInProfile(profile);
    setState(() {});
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

class _TvVideoGrid extends StatelessWidget {
  const _TvVideoGrid({
    required this.items,
    required this.onTapItem,
    required this.onNearEnd,
  });

  final List<BiliFeedVideo> items;
  final void Function(BiliFeedVideo item) onTapItem;
  final VoidCallback onNearEnd;

  @override
  Widget build(BuildContext context) {
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
        return _TvVideoCard(
          key: ValueKey('feed_${item.bvid}'),
          coverUrl: item.coverUrl,
          title: item.title,
          author: item.author,
          duration: item.durationLabel,
          playCount: item.playCountLabel,
          onTap: () => onTapItem(item),
        );
      },
    );
  }
}

class _TvRegionVideoGrid extends StatelessWidget {
  const _TvRegionVideoGrid({
    required this.items,
    required this.onTapItem,
    required this.onNearEnd,
  });

  final List<BiliRegionVideo> items;
  final void Function(BiliRegionVideo item) onTapItem;
  final VoidCallback onNearEnd;

  @override
  Widget build(BuildContext context) {
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
          title: item.title,
          author: subtitle,
          duration: duration,
          playCount: item.followCountLabel ?? '',
          onTap: () => onTapItem(item),
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
    return TvFocusable(
      autofocus: autofocus,
      scale: 1.06,
      showGlow: false,
      focusCornerRadius: 14,
      baseCornerRadius: 14,
      focusArea: TvFocusArea.content,
      debugLabel: 'region_${section.id}',
      onTap: onTap,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.22)
                  : selected
                  ? const Color(0x33FB7299)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused
                    ? const Color(0xCCFFFFFF)
                    : selected
                    ? const Color(0x99FB7299)
                    : const Color(0x16FFFFFF),
                width: 1,
              ),
            ),
            child: Row(
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
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TvVideoCard extends StatelessWidget {
  const _TvVideoCard({
    super.key,
    required this.coverUrl,
    required this.title,
    required this.author,
    required this.duration,
    required this.playCount,
    required this.onTap,
  });

  final String coverUrl;
  final String title;
  final String author;
  final String duration;
  final String playCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusableSurface(
      scale: 1.12,
      focusPadding: _tvCardFocusPadding,
      useOverlayLift: true,
      focusArea: TvFocusArea.content,
      debugLabel: 'video_$title',
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
    required this.title,
    required this.author,
    required this.duration,
    required this.playCount,
    required this.onTap,
  });

  final String coverUrl;
  final String title;
  final String author;
  final String duration;
  final String playCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TvVideoCard(
      coverUrl: coverUrl,
      title: title,
      author: author,
      duration: duration,
      playCount: playCount,
      onTap: onTap,
    );
  }
}

class _TvHistoryCard extends StatelessWidget {
  const _TvHistoryCard({
    required this.coverUrl,
    required this.title,
    required this.subtitle,
    required this.ownerName,
    required this.progress,
    required this.onTap,
    this.autofocus = false,
  });

  final String coverUrl;
  final String title;
  final String subtitle;
  final String ownerName;
  final double progress;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusableSurface(
      autofocus: autofocus,
      scale: 1.12,
      focusPadding: _tvCardFocusPadding,
      useOverlayLift: true,
      focusArea: TvFocusArea.content,
      debugLabel: 'history_$title',
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
                              Color(0xFFFB7299),
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
