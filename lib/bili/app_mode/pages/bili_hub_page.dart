import 'dart:async';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/app/services/bili_ui_mode_controller.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/common/view_models/bili_hub_view_model.dart';
import 'package:vesper_media/bili/common/widgets/bili_cache_download_panel.dart';
import 'package:vesper_media/media/player/media_glass_sheet.dart';
import 'package:vesper_media/bili/common/widgets/bili_qr_login_sheet.dart';
import 'package:vesper_media/download/download.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_page.dart';
import 'bili_region_hub_page.dart';
import 'bili_library_page.dart';
import 'bili_settings_page.dart';

part 'bili_hub_common.dart';
part 'bili_hub_home.dart';
part 'bili_hub_mine.dart';

class BiliHubPage extends StatefulWidget {
  const BiliHubPage({
    super.key,
    this.client,
    this.historyStore,
    this.sessionStore,
    this.offlineController,
    this.appSettings,
    this.uiModeController,
  });

  final BiliClient? client;
  final BiliHistoryStore? historyStore;
  final BiliSessionStore? sessionStore;
  final BiliOfflineDownloadController? offlineController;
  final AppSettingsStore? appSettings;
  final BiliUiModeController? uiModeController;

  @override
  State<BiliHubPage> createState() => _BiliHubPageState();
}

class _BiliHubPageState extends State<BiliHubPage> {
  static const double _homeAppBarHeight = 44;
  static const ValueKey<String> _homeTopClearanceKey = ValueKey<String>(
    'bili-home-top-clearance',
  );

  late final TextEditingController _queryController;
  late final ScrollController _homeScrollController;
  late final BiliHubViewModel _viewModel;

  String get _query => _queryController.text.trim();

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _homeScrollController = ScrollController()..addListener(_handleHomeScroll);
    _viewModel = BiliHubViewModel(
      client: widget.client,
      historyStore: widget.historyStore,
      sessionStore: widget.sessionStore,
      offlineController: widget.offlineController,
    );
    unawaited(_viewModel.bootstrap());
  }

  @override
  void dispose() {
    _homeScrollController
      ..removeListener(_handleHomeScroll)
      ..dispose();
    _queryController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final directBvid = _viewModel.directBvid.value;
    if (directBvid != null) {
      await _openPlayback(directBvid);
      return;
    }
    await _viewModel.runSearch();
  }

  void _clearSearch() {
    _queryController.clear();
    _viewModel.clearSearch();
  }

  void _handleHomeScroll() {
    if (_viewModel.selectedTab.value != BiliHubTab.home ||
        !_homeScrollController.hasClients) {
      return;
    }
    final position = _homeScrollController.position;
    if (position.extentAfter > 900) {
      return;
    }
    if (_viewModel.showsSearchResults.value) {
      unawaited(_loadMoreSearch());
      return;
    }
    unawaited(_loadMoreFeed());
  }

  Future<void> _loadMoreFeed() async {
    final message = await _viewModel.loadMoreFeed();
    if (message != null && mounted) {
      _showMessage(message);
    }
  }

  Future<void> _loadMoreSearch() async {
    final message = await _viewModel.loadMoreSearch();
    if (message != null && mounted) {
      _showMessage(message);
    }
  }

  Future<void> _openPlayback(String bvid, {int? cid}) async {
    late final BiliHubPlaybackTarget target;
    try {
      target = await _viewModel.resolvePlaybackTarget(bvid, cid: cid);
    } catch (error) {
      if (mounted) {
        _showMessage('打开视频失败：${biliErrorMessage(error)}');
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
        ),
      ),
    );
    await _viewModel.loadHistory();
  }

  Future<void> _openHomeCacheSurface(_HomeVideoItem item) async {
    final isPortrait =
        MediaQuery.sizeOf(context).height >= MediaQuery.sizeOf(context).width;
    if (isPortrait) {
      await showMediaGlassSheet<void>(
        context: context,
        builder: (_) => _HomeCacheSurface(
          client: _viewModel.client,
          historyStore: _viewModel.historyStore,
          bvid: item.bvid,
          controller: _viewModel.offlineController,
          onMessage: _showMessage,
        ),
      );
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: AppVisualTokens.motionDuration(
        context,
        AppVisualTokens.overlayDuration,
      ),
      pageBuilder: (dialogContext, _, _) {
        final drawerWidth = (MediaQuery.sizeOf(dialogContext).width * 0.42)
            .clamp(
              MediaQuery.sizeOf(dialogContext).width * 0.28,
              MediaQuery.sizeOf(dialogContext).width * 0.42,
            )
            .toDouble();
        return Align(
          alignment: Alignment.centerLeft,
          child: GlassContainer(
            useOwnLayer: true,
            quality: GlassQuality.standard,
            shape: const LiquidRoundedSuperellipse(
              borderRadius: AppVisualTokens.sheetRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: SafeArea(
                right: false,
                child: SizedBox(
                  width: drawerWidth,
                  height: double.infinity,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                    child: _HomeCacheSurface(
                      client: _viewModel.client,
                      historyStore: _viewModel.historyStore,
                      bvid: item.bvid,
                      controller: _viewModel.offlineController,
                      onMessage: _showMessage,
                    ),
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

  Future<void> _openOfflineCachePage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfflineCachePage(
          controller: _viewModel.offlineController,
          client: _viewModel.client,
          historyStore: _viewModel.historyStore,
        ),
      ),
    );
  }

  Future<void> _openRegionHub() async {
    final hasSession =
        _viewModel.profile.value.isLoggedIn ||
        _viewModel.client.hasAuthenticatedSession;
    if (!hasSession) {
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliRegionHubPage(
          client: _viewModel.client,
          historyStore: _viewModel.historyStore,
          offlineController: _viewModel.offlineController,
        ),
      ),
    );
  }

  Future<bool?> _confirmRegionLogin() {
    return showMediaGlassDialog<bool>(
      context: context,
      title: '需要登录',
      message: '分区内容需要登录后才能观看，请先登录 Bilibili 账号。',
      appearance: MediaGlassDialogAppearance.readable,
      actions: const [
        MediaGlassDialogAction(label: '取消', value: false),
        MediaGlassDialogAction(label: '登录', value: true, isPrimary: true),
      ],
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliSettingsPage(
          appSettings: widget.appSettings,
          client: _viewModel.client,
          historyStore: _viewModel.historyStore,
          uiModeController: widget.uiModeController,
          sessionStore: _viewModel.sessionStore,
          offlineController: _viewModel.offlineController,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _viewModel.refreshProfile(
      clearInvalidSession: true,
      persistIfLoggedIn: true,
    );
  }

  Future<void> _openQrLogin() async {
    final profile = await showBiliQrLoginSheet(
      context: context,
      client: _viewModel.client,
      sessionStore: _viewModel.sessionStore,
    );
    if (profile == null || !mounted) {
      return;
    }
    await _viewModel.applyLoggedInProfile(profile);
  }

  void _handleAccountEntry() {
    if (_viewModel.profile.value.isLoggedIn) {
      _viewModel.selectMineTab();
      return;
    }
    unawaited(_openQrLogin());
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final selectedTab = _viewModel.selectedTab.value;
        final visualTheme = AppVisualTheme.of(context);
        return AppGlassScaffold(
          backgroundColor: visualTheme.background,
          statusBarStyle: GlassStatusBarStyle.auto,
          extendBody: true,
          appBarHeight: _homeAppBarHeight,
          bottomBarHeight: AppGlassBottomNavigation.extent,
          appBar: selectedTab == BiliHubTab.home
              ? AppFrostedScrollAppBar(
                  scrollController: _homeScrollController,
                  child: GlassAppBar(
                    centerTitle: false,
                    padding: const EdgeInsets.only(left: 2, right: 10),
                    title: SignalBuilder(
                      builder: (context) {
                        return _HomeHeader(
                          profile: _viewModel.profile.value,
                          controller: _queryController,
                          isSearching: _viewModel.isSearching.value,
                          onAccountTap: _handleAccountEntry,
                          onRegionTap: _openRegionHub,
                          onChanged: () => _viewModel.updateQuery(_query),
                          onSubmit: _runSearch,
                          onClear: _query.isEmpty ? null : _clearSearch,
                        );
                      },
                    ),
                  ),
                )
              : null,
          body: switch (selectedTab) {
            BiliHubTab.home => _buildHomeTab(),
            BiliHubTab.mine => _MineTab(
              profile: _viewModel.profile.value,
              profileErrorMessage: _viewModel.profileErrorMessage.value,
              isRefreshingProfile: _viewModel.isRefreshingProfile.value,
              historyCount: _viewModel.history.value.length,
              onLoginTap: _openQrLogin,
              onLogoutTap: _viewModel.logout,
              onSpaceTap: () => _showMessage('空间页暂未接入。'),
              onCacheTap: () => unawaited(_openOfflineCachePage()),
              onHistoryTap: () async {
                await _openLibrary(BiliLibrarySection.history);
              },
              onFollowingTap: () =>
                  unawaited(_openLibrary(BiliLibrarySection.following)),
              onWatchLaterTap: () =>
                  unawaited(_openLibrary(BiliLibrarySection.watchLater)),
              onSettingsTap: () => unawaited(_openSettings()),
              onRefresh: _viewModel.refreshMine,
            ),
          },
          bottomBar: _HubNavigationBar(
            selectedTab: selectedTab,
            onSelected: _viewModel.selectTab,
          ),
        );
      },
    );
  }

  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: _viewModel.refreshAll,
      child: CustomScrollView(
        controller: _homeScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              key: _homeTopClearanceKey,
              height: MediaQuery.paddingOf(context).top + _homeAppBarHeight,
            ),
          ),
          SignalBuilder(builder: _buildHomeBody),
          SliverToBoxAdapter(
            child: SizedBox(
              key: AppGlassBottomNavigation.contentClearanceKey,
              height: AppGlassBottomNavigation.contentClearance(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeBody(BuildContext context) {
    final showsSearchResults = _viewModel.showsSearchResults.value;
    late final int itemCount;
    late final _HomeVideoItem Function(int index) itemAt;
    if (showsSearchResults) {
      final results = _viewModel.results.value;
      itemCount = results.length;
      itemAt = (index) => _HomeVideoItem.fromSearch(results[index]);
    } else {
      final feedItems = _viewModel.feedItems.value;
      itemCount = feedItems.length;
      itemAt = (index) => _HomeVideoItem.fromFeed(feedItems[index]);
    }

    if (_viewModel.isBootstrapping.value) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        if (showsSearchResults && _viewModel.searchErrorMessage.value != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _InlineErrorBanner(
                message: _viewModel.searchErrorMessage.value!,
                actionLabel: '重新搜索',
                onPressed: _runSearch,
              ),
            ),
          ),
        if (!showsSearchResults && _viewModel.feedErrorMessage.value != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _InlineErrorBanner(
                message: _viewModel.feedErrorMessage.value!,
                actionLabel: '重新加载',
                onPressed: _viewModel.loadFeed,
              ),
            ),
          ),
        if ((showsSearchResults && _viewModel.isSearching.value) ||
            (!showsSearchResults &&
                _viewModel.isRefreshingFeed.value &&
                itemCount == 0))
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (showsSearchResults &&
            _viewModel.searchErrorMessage.value == null &&
            itemCount == 0)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _EmptyPanel(
                title: '没有搜到内容',
                body: '试试更短的关键词，或者直接贴 BV 号和完整视频链接。',
              ),
            ),
          )
        else
          _HomeVideoGrid(
            itemCount: itemCount,
            itemAt: itemAt,
            onTap: (item) => _openPlayback(item.bvid),
            onCacheTap: (item) => unawaited(_openHomeCacheSurface(item)),
          ),
        if (itemCount > 0)
          SliverToBoxAdapter(
            child: _LoadMoreFooter(
              isLoading: showsSearchResults
                  ? _viewModel.isLoadingMoreSearch.value
                  : _viewModel.isLoadingMoreFeed.value,
              hasMore: showsSearchResults
                  ? _viewModel.hasMoreSearch.value
                  : _viewModel.hasMoreFeed.value,
            ),
          ),
      ],
    );
  }
}
