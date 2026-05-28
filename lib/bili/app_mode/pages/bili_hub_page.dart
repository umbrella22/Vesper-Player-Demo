import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:bilibili_player/bili/common/services/bili_session_store.dart';
import 'package:bilibili_player/bili/common/services/bili_text.dart';
import 'package:bilibili_player/bili/common/view_models/bili_hub_view_model.dart';
import 'package:bilibili_player/bili/common/widgets/bili_cache_download_panel.dart';
import 'package:bilibili_player/bili/common/widgets/bili_qr_login_sheet.dart';
import 'package:bilibili_player/download/download.dart';
import 'package:bilibili_player/bili/common/pages/bili_playback_page.dart';
import 'bili_region_hub_page.dart';
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
  });

  final BiliClient? client;
  final BiliHistoryStore? historyStore;
  final BiliSessionStore? sessionStore;
  final BiliOfflineDownloadController? offlineController;

  @override
  State<BiliHubPage> createState() => _BiliHubPageState();
}

class _BiliHubPageState extends State<BiliHubPage> {
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
        ),
      ),
    );
    await _viewModel.loadHistory();
  }

  Future<void> _openHomeCacheSurface(_HomeVideoItem item) async {
    final isPortrait =
        MediaQuery.sizeOf(context).height >= MediaQuery.sizeOf(context).width;
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliSettingsPage(
          client: _viewModel.client,
          sessionStore: _viewModel.sessionStore,
          offlineController: _viewModel.offlineController,
        ),
      ),
    );
    await _viewModel.refreshProfile(
      clearInvalidSession: true,
      persistIfLoggedIn: true,
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

  Future<void> _openHistorySheet() async {
    final history = _viewModel.history.value;
    if (history.isEmpty) {
      _showMessage('还没有播放历史。');
      return;
    }

    final entry = await showModalBottomSheet<BiliPlaybackHistoryEntry>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          shrinkWrap: true,
          itemCount: history.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = history[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 42,
                  child: entry.coverUrl.isEmpty
                      ? const ColoredBox(color: Color(0xFFE9ECF2))
                      : Image.network(
                          entry.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Color(0xFFE9ECF2)),
                        ),
                ),
              ),
              title: Text(
                entry.videoTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${entry.pageTitle} · ${_formatPosition(entry.lastPositionMs, entry.durationMs)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).pop(entry),
            );
          },
        ),
      ),
    );

    if (!mounted || entry == null) {
      return;
    }
    await _openPlayback(entry.bvid, cid: entry.cid);
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final selectedTab = _viewModel.selectedTab.value;
        return Scaffold(
          backgroundColor: Colors.white,
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
              onHistoryTap: _openHistorySheet,
              onFavoritesTap: () => _showMessage('收藏夹暂未接入。'),
              onWatchLaterTap: () => _showMessage('稍后再看暂未接入。'),
              onSettingsTap: () => unawaited(_openSettings()),
              onRefresh: _viewModel.refreshMine,
            ),
          },
          bottomNavigationBar: _HubNavigationBar(
            selectedTab: selectedTab,
            onSelected: _viewModel.selectTab,
          ),
        );
      },
    );
  }

  Widget _buildHomeTab() {
    final topPadding = MediaQuery.paddingOf(context).top;

    return RefreshIndicator(
      onRefresh: _viewModel.refreshAll,
      child: CustomScrollView(
        controller: _homeScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _HomeSearchHeaderDelegate(
              topPadding: topPadding,
              child: SignalBuilder(
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
          ),
          SignalBuilder(builder: _buildHomeBody),
        ],
      ),
    );
  }

  Widget _buildHomeBody(BuildContext context) {
    final showsSearchResults = _viewModel.showsSearchResults.value;
    final items = showsSearchResults
        ? _viewModel.results.value
              .map(_HomeVideoItem.fromSearch)
              .toList(growable: false)
        : _viewModel.feedItems.value
              .map(_HomeVideoItem.fromFeed)
              .toList(growable: false);

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
                items.isEmpty))
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (showsSearchResults &&
            _viewModel.searchErrorMessage.value == null &&
            items.isEmpty)
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
            items: items,
            onTap: (item) => _openPlayback(item.bvid),
            onCacheTap: (item) => unawaited(_openHomeCacheSurface(item)),
          ),
        if (items.isNotEmpty)
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
