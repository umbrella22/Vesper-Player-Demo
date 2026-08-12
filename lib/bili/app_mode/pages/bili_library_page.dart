import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_page.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_text.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_directional_focus_scope.dart';
import 'package:vesper_media/media/tv/media_tv_focusable.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_glass_dialog.dart';
import 'package:vesper_media/download/download.dart';

import 'bili_user_space_page.dart';

part 'bili_library_phone.dart';
part 'bili_library_tv.dart';
part 'bili_library_following_tv.dart';

enum BiliLibrarySection { following, history, watchLater }

/// Authenticated account library surfaces shared by phone and tablet layouts.
///
/// The page intentionally owns request state instead of making the hub view
/// model know about three unrelated endpoint payloads.  It also keeps failed
/// optional library requests local to the selected tab.
class BiliLibraryPage extends StatefulWidget {
  const BiliLibraryPage({
    super.key,
    required this.client,
    this.initialSection = BiliLibrarySection.following,
    this.historyStore,
    this.offlineController,
    this.onLoginTap,
    this.presentationMode = BiliPlaybackPresentationMode.phone,
    this.forceCompactTvFollowingRail = false,
  }) : embeddedTvFollowing = false,
       tvFollowingRailOffset = 0,
       tvFollowingVerticalInset = 0;

  const BiliLibraryPage.tvFollowingPane({
    super.key,
    required this.client,
    this.historyStore,
    this.offlineController,
    this.onLoginTap,
    this.forceCompactTvFollowingRail = false,
    this.tvFollowingRailOffset = 0,
    this.tvFollowingVerticalInset = 20,
  }) : initialSection = BiliLibrarySection.following,
       presentationMode = BiliPlaybackPresentationMode.tv,
       embeddedTvFollowing = true;

  final BiliClient client;
  final BiliLibrarySection initialSection;
  final BiliHistoryStore? historyStore;
  final BiliOfflineDownloadController? offlineController;
  final Future<void> Function()? onLoginTap;
  final BiliPlaybackPresentationMode presentationMode;
  final bool embeddedTvFollowing;
  final bool forceCompactTvFollowingRail;
  final double tvFollowingRailOffset;
  final double tvFollowingVerticalInset;

  @override
  State<BiliLibraryPage> createState() => _BiliLibraryPageState();
}

class _BiliLibraryPageState extends State<BiliLibraryPage>
    with SingleTickerProviderStateMixin {
  static const int _followingPageSize = 50;
  static const int _historyPageSize = 30;
  static const int _watchLaterPageSize = 30;

  late final TabController _tabController;
  late final List<BiliLibrarySection> _visibleSections;
  final Map<BiliLibrarySection, _LibraryLoadState> _states =
      <BiliLibrarySection, _LibraryLoadState>{};

  bool get _isTv => widget.presentationMode == BiliPlaybackPresentationMode.tv;

  @override
  void initState() {
    super.initState();
    _visibleSections = widget.embeddedTvFollowing
        ? const <BiliLibrarySection>[BiliLibrarySection.following]
        : _isTv
        ? const <BiliLibrarySection>[
            BiliLibrarySection.history,
            BiliLibrarySection.watchLater,
          ]
        : BiliLibrarySection.values;
    final requestedIndex = _visibleSections.indexOf(widget.initialSection);
    _tabController = TabController(
      length: _visibleSections.length,
      vsync: this,
      initialIndex: requestedIndex < 0 ? 0 : requestedIndex,
    )..addListener(_handleTabChanged);
    _load(_sectionForIndex(_tabController.index));
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    super.dispose();
  }

  BiliLibrarySection _sectionForIndex(int index) {
    final safeIndex = index.clamp(0, _visibleSections.length - 1);
    return _visibleSections[safeIndex];
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    _load(_sectionForIndex(_tabController.index));
  }

  _LibraryLoadState _stateFor(BiliLibrarySection section) {
    return _states.putIfAbsent(section, _LibraryLoadState.new);
  }

  Future<void> _load(BiliLibrarySection section, {bool force = false}) async {
    final state = _stateFor(section);
    if (state.loading) {
      return;
    }
    final hasAuthenticatedSession = widget.client.hasAuthenticatedSession;
    if (!force && state.loaded && hasAuthenticatedSession) {
      return;
    }
    List<BiliRemoteHistoryEntry>? refreshedLocalHistory;
    if (section == BiliLibrarySection.history) {
      // Local history remains useful while logged out and is also a fallback
      // when the cloud cursor endpoint is temporarily unavailable.
      try {
        final local = await (widget.historyStore ?? const BiliHistoryStore())
            .loadEntries();
        refreshedLocalHistory = local
            .map(
              (entry) => BiliRemoteHistoryEntry(
                aid: entry.aid,
                bvid: entry.bvid,
                cid: entry.cid,
                episodeId: entry.episodeId,
                title: entry.videoTitle,
                pageTitle: entry.pageTitle,
                coverUrl: entry.coverUrl,
                ownerName: entry.ownerName,
                durationMs: entry.durationMs ?? 0,
                progressMs: entry.lastPositionMs,
                viewedAtMs: entry.playedAtMs,
                business: entry.business,
              ),
            )
            .toList(growable: false);
      } catch (_) {
        refreshedLocalHistory = const <BiliRemoteHistoryEntry>[];
      }
    }
    if (!hasAuthenticatedSession) {
      if (mounted) {
        setState(() {
          if (section == BiliLibrarySection.history) {
            state.localHistory = refreshedLocalHistory!;
            state.history = refreshedLocalHistory;
            state.remoteHistoryCount = 0;
          }
          _clearAuthenticatedData(section, state);
          state.loading = false;
          state.loaded = true;
          state.authenticationRequired = true;
          state.error =
              section == BiliLibrarySection.history && state.history.isNotEmpty
              ? null
              : '请先登录 Bilibili 后查看此内容。';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        state.loading = true;
        state.error = null;
        state.authenticationRequired = false;
      });
    }
    try {
      switch (section) {
        case BiliLibrarySection.following:
          final following = await widget.client.fetchFollowingUsers(
            page: 1,
            pageSize: _followingPageSize,
          );
          state.following = following;
          state.hasMore = state.following.length >= _followingPageSize;
        case BiliLibrarySection.history:
          final page = await widget.client.fetchRemoteHistoryPage(
            page: 1,
            pageSize: _historyPageSize,
          );
          final remote = page.entries;
          final seen = remote.map(_historyIdentity).toSet();
          state.localHistory = refreshedLocalHistory!;
          state.history = <BiliRemoteHistoryEntry>[
            ...remote,
            ...state.localHistory.where(
              (item) => !seen.contains(_historyIdentity(item)),
            ),
          ];
          state.remoteHistoryCount = remote.length;
          state.historyMax = page.nextMax;
          state.historyViewAtMs = page.nextViewAtMs;
          state.hasMore = page.hasMore;
        case BiliLibrarySection.watchLater:
          final watchLater = await widget.client.fetchWatchLater(
            page: 1,
            pageSize: _watchLaterPageSize,
          );
          state.watchLater = watchLater;
          state.hasMore = state.watchLater.length >= _watchLaterPageSize;
      }
      state.page = 1;
      state.loaded = true;
      state.authenticationRequired = false;
    } catch (error) {
      state.error = _libraryError(error);
      final authenticationRequired =
          error is BiliApiException && error.code == -101;
      state.authenticationRequired = authenticationRequired;
      if (authenticationRequired) {
        if (section == BiliLibrarySection.history) {
          state.localHistory = refreshedLocalHistory!;
        }
        _clearAuthenticatedData(section, state);
      } else if (section == BiliLibrarySection.history &&
          !state.loaded &&
          state.history.isEmpty &&
          refreshedLocalHistory!.isNotEmpty) {
        state.localHistory = refreshedLocalHistory;
        state.history = refreshedLocalHistory;
        state.remoteHistoryCount = 0;
        state.hasMore = false;
      }
    } finally {
      state.loading = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadMore(BiliLibrarySection section) async {
    final state = _stateFor(section);
    if (state.loading ||
        state.loadingMore ||
        !state.loaded ||
        !state.hasMore ||
        !widget.client.hasAuthenticatedSession) {
      return;
    }
    final nextPage = state.page + 1;
    setState(() {
      state.loadingMore = true;
      state.error = null;
      state.authenticationRequired = false;
    });
    try {
      var receivedCount = 0;
      var uniqueCount = 0;
      bool? responseHasMore;
      switch (section) {
        case BiliLibrarySection.following:
          final next = await widget.client.fetchFollowingUsers(
            page: nextPage,
            pageSize: _followingPageSize,
          );
          receivedCount = next.length;
          final seen = state.following.map((item) => item.mid).toSet();
          final unique = next
              .where((item) => seen.add(item.mid))
              .toList(growable: false);
          uniqueCount = unique.length;
          state.following = <BiliFollowingUser>[...state.following, ...unique];
        case BiliLibrarySection.history:
          final page = await widget.client.fetchRemoteHistoryPage(
            page: nextPage,
            pageSize: _historyPageSize,
            max: state.historyMax,
            viewAtMs: state.historyViewAtMs,
          );
          final next = page.entries;
          receivedCount = next.length;
          final seen = state.history.map(_historyIdentity).toSet();
          final unique = next
              .where((item) => seen.add(_historyIdentity(item)))
              .toList(growable: false);
          uniqueCount = unique.length;
          final remoteCount = state.remoteHistoryCount.clamp(
            0,
            state.history.length,
          );
          state.history = <BiliRemoteHistoryEntry>[
            ...state.history.take(remoteCount),
            ...unique,
            ...state.history.skip(remoteCount),
          ];
          state.remoteHistoryCount += unique.length;
          state.historyMax = page.nextMax;
          state.historyViewAtMs = page.nextViewAtMs;
          responseHasMore = page.hasMore;
        case BiliLibrarySection.watchLater:
          final next = await widget.client.fetchWatchLater(
            page: nextPage,
            pageSize: _watchLaterPageSize,
          );
          receivedCount = next.length;
          final seen = state.watchLater.map(_watchLaterIdentity).toSet();
          final unique = next
              .where((item) => seen.add(_watchLaterIdentity(item)))
              .toList(growable: false);
          uniqueCount = unique.length;
          state.watchLater = <BiliWatchLaterEntry>[
            ...state.watchLater,
            ...unique,
          ];
      }
      state.page = nextPage;
      final pageSize = switch (section) {
        BiliLibrarySection.following => _followingPageSize,
        BiliLibrarySection.history => _historyPageSize,
        BiliLibrarySection.watchLater => _watchLaterPageSize,
      };
      state.hasMore =
          (responseHasMore ?? receivedCount >= pageSize) && uniqueCount > 0;
      state.authenticationRequired = false;
    } catch (error) {
      state.error = _libraryError(error);
      state.authenticationRequired =
          error is BiliApiException && error.code == -101;
      if (state.authenticationRequired) {
        _clearAuthenticatedData(section, state);
      } else {
        _showMessage('加载更多失败：${biliErrorMessage(error)}');
      }
    } finally {
      state.loadingMore = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  String _historyIdentity(BiliRemoteHistoryEntry item) {
    if (item.episodeId > 0) {
      return 'episode:${item.episodeId}';
    }
    if (item.cid > 0) {
      return 'cid:${item.cid}';
    }
    if (item.bvid.isNotEmpty) {
      return 'bvid:${item.bvid}';
    }
    return 'aid:${item.aid}';
  }

  String _watchLaterIdentity(BiliWatchLaterEntry item) {
    if (item.episodeId > 0) {
      return 'episode:${item.episodeId}';
    }
    if (item.cid > 0) {
      return 'cid:${item.cid}';
    }
    if (item.bvid.isNotEmpty) {
      return 'bvid:${item.bvid}';
    }
    return 'aid:${item.aid}';
  }

  void _clearAuthenticatedData(
    BiliLibrarySection section,
    _LibraryLoadState state,
  ) {
    switch (section) {
      case BiliLibrarySection.following:
        state.following = const <BiliFollowingUser>[];
        break;
      case BiliLibrarySection.history:
        // A cloud row may have deduplicated its local counterpart, so restore
        // the store snapshot instead of slicing the merged list by position.
        state.history = state.localHistory;
        state.remoteHistoryCount = 0;
        break;
      case BiliLibrarySection.watchLater:
        state.watchLater = const <BiliWatchLaterEntry>[];
        break;
    }
    state.hasMore = false;
    state.loadingMore = false;
    state.historyMax = 0;
    state.historyViewAtMs = 0;
  }

  String _libraryError(Object error) {
    if (error is BiliApiException && error.code == -101) {
      return '登录状态已失效，请重新登录后再试。';
    }
    if (error is BiliApiException &&
        (error.code == biliRiskControlCode || error.code == -412)) {
      return 'Bilibili 暂时限制了账户库请求，请稍后重试。';
    }
    return '加载失败：${biliErrorMessage(error)}';
  }

  Future<void> _handleLogin() async {
    final onLoginTap = widget.onLoginTap;
    if (onLoginTap == null) {
      return;
    }
    await onLoginTap();
    if (!mounted || !widget.client.hasAuthenticatedSession) {
      return;
    }
    await _load(_sectionForIndex(_tabController.index), force: true);
  }

  Future<void> _openVideo({
    required String bvid,
    int? aid,
    required int? cid,
    int? episodeId,
    int initialPositionMs = 0,
  }) async {
    final normalizedBvid = bvid.trim();
    final normalizedAid = aid != null && aid > 0 ? aid : null;
    final normalizedEpisodeId = episodeId != null && episodeId > 0
        ? episodeId
        : null;
    if (normalizedBvid.isEmpty &&
        normalizedAid == null &&
        normalizedEpisodeId == null) {
      _showMessage('该条记录缺少视频编号，暂时无法播放。');
      return;
    }
    try {
      final detail = normalizedEpisodeId != null
          ? await widget.client.fetchPgcEpisodeDetail(normalizedEpisodeId)
          : normalizedBvid.isNotEmpty
          ? await widget.client.fetchVideoDetail(normalizedBvid)
          : await widget.client.fetchVideoDetailByAid(normalizedAid!);
      if (!mounted || detail.pages.isEmpty) {
        return;
      }
      final page = normalizedEpisodeId != null
          ? detail.pages.firstWhere(
              (item) => item.episodeId == normalizedEpisodeId,
              orElse: () => throw const BiliApiException('无法找到对应的番剧分集。'),
            )
          : cid == null || cid <= 0
          ? detail.pages.first
          : detail.pages.firstWhere(
              (item) => item.cid == cid,
              orElse: () => detail.pages.first,
            );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BiliPlaybackPage(
            detail: detail,
            initialPage: page,
            client: widget.client,
            historyStore: widget.historyStore ?? const BiliHistoryStore(),
            offlineController:
                widget.offlineController ??
                BiliOfflineDownloadController.instance,
            initialPositionMs: initialPositionMs,
            presentationMode: widget.presentationMode,
          ),
        ),
      );
      if (mounted && !widget.embeddedTvFollowing) {
        await _load(_sectionForIndex(_tabController.index), force: true);
      }
    } catch (error) {
      _showMessage('打开视频失败：${biliErrorMessage(error)}');
    }
  }

  Future<void> _openUserSpace(BiliFollowingUser user) async {
    if (!widget.client.hasAuthenticatedSession) {
      await _load(BiliLibrarySection.following, force: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliUserSpacePage(
          client: widget.client,
          user: user,
          historyStore: widget.historyStore,
          offlineController: widget.offlineController,
          onLoginTap: widget.onLoginTap,
        ),
      ),
    );
  }

  Future<void> _removeWatchLater(BiliWatchLaterEntry entry) async {
    if (_isTv) {
      final confirmed = await showBiliTvGlassDialog<bool>(
        context: context,
        title: '移出稍后再看？',
        message: '“${entry.title}”会从稍后再看列表中移除。',
        icon: Icons.playlist_remove_rounded,
        actions: const [
          BiliTvDialogAction(
            label: '取消',
            value: false,
            icon: Icons.close_rounded,
            autofocus: true,
          ),
          BiliTvDialogAction(
            label: '移出',
            value: true,
            icon: Icons.delete_outline_rounded,
            isDestructive: true,
          ),
        ],
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    try {
      await widget.client.removeFromWatchLater(
        bvid: entry.bvid,
        aid: entry.aid,
      );
      _showMessage('已移出稍后再看');
      await _load(BiliLibrarySection.watchLater, force: true);
    } catch (error) {
      _showMessage('移除失败：${biliErrorMessage(error)}');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embeddedTvFollowing) {
      return KeyedSubtree(
        key: const ValueKey<String>('bili-tv-following-pane'),
        child: _buildTvSection(context, BiliLibrarySection.following),
      );
    }
    if (_isTv) {
      return _buildTvPage(context);
    }
    return _buildPhonePage(context);
  }

  Widget _buildPhonePage(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    const appBarContentHeight = 118.0;
    final appBarSurfaceHeight = topPadding + appBarContentHeight;
    return AppGlassScaffold(
      backgroundColor: visualTheme.background,
      extendBody: false,
      appBarHeight: appBarContentHeight,
      appBar: SizedBox(
        height: appBarSurfaceHeight,
        child: Column(
          children: [
            if (topPadding > 0) SizedBox(height: topPadding),
            SizedBox(
              height: 44,
              child: Padding(
                key: const ValueKey<String>('bili-library-phone-toolbar'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Expanded(
                      child: Text(
                        '我的内容',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: AppGlassSectionTabs.height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    return AppGlassSectionTabs(
                      selectedIndex: _tabController.index,
                      onSelected: (index) {
                        if (_tabController.index == index) {
                          return;
                        }
                        _tabController.animateTo(
                          index,
                          duration: AppVisualTokens.motionDuration(
                            context,
                            AppVisualTokens.tvFocusDuration,
                          ),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      items: const [
                        AppGlassNavigationItem(
                          icon: Icons.people_alt_outlined,
                          activeIcon: Icons.people_alt_rounded,
                          label: '关注',
                        ),
                        AppGlassNavigationItem(
                          icon: Icons.history_rounded,
                          label: '历史播放',
                        ),
                        AppGlassNavigationItem(
                          icon: Icons.watch_later_outlined,
                          activeIcon: Icons.watch_later_rounded,
                          label: '稍后再看',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      body: TabBarView(
        key: const ValueKey<String>('bili-library-phone-content'),
        controller: _tabController,
        children: BiliLibrarySection.values
            .map((section) => _buildSection(context, section))
            .toList(growable: false),
      ),
    );
  }

  Widget _buildTvPage(BuildContext context) {
    return TvDirectionalFocusScope(
      debugLabel: 'tv_library',
      handleGoBackKey: false,
      onBack: () => Navigator.of(context).maybePop(),
      child: Scaffold(
        key: const ValueKey<String>('bili-tv-library-root'),
        backgroundColor: AppVisualTokens.tvBackground,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTvHeader(context),
              Expanded(
                child: AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    final section = _sectionForIndex(_tabController.index);
                    return KeyedSubtree(
                      key: ValueKey<String>(
                        'bili-tv-library-section-${section.name}',
                      ),
                      child: _buildTvSection(context, section),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvHeader(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
      child: Row(
        children: [
          _TvLibraryHeaderButton(
            key: const ValueKey<String>('bili-tv-library-back'),
            icon: Icons.arrow_back_rounded,
            tooltip: '返回',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              '我的内容',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: visualTheme.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 20),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              final selectedSection = _sectionForIndex(_tabController.index);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < _visibleSections.length; index++)
                    Padding(
                      padding: EdgeInsets.only(left: index == 0 ? 0 : 10),
                      child: _TvLibraryTab(
                        key: ValueKey<String>(
                          'bili-tv-library-tab-${_visibleSections[index].name}',
                        ),
                        icon: _tvSectionIcon(_visibleSections[index]),
                        label: _tvSectionLabel(_visibleSections[index]),
                        selected: selectedSection == _visibleSections[index],
                        onTap: () => _selectTvSection(_visibleSections[index]),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 12),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              final section = _sectionForIndex(_tabController.index);
              return _TvLibraryHeaderButton(
                key: const ValueKey<String>('bili-tv-library-refresh'),
                icon: Icons.refresh_rounded,
                tooltip: '刷新',
                loading: _stateFor(section).loading,
                onTap: () => unawaited(_load(section, force: true)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _selectTvSection(BiliLibrarySection section) {
    final index = _visibleSections.indexOf(section);
    if (index < 0) {
      return;
    }
    if (_tabController.index != index) {
      _tabController.animateTo(
        index,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
    unawaited(_load(section));
  }

  IconData _tvSectionIcon(BiliLibrarySection section) {
    return switch (section) {
      BiliLibrarySection.following => Icons.people_alt_outlined,
      BiliLibrarySection.history => Icons.history_rounded,
      BiliLibrarySection.watchLater => Icons.watch_later_outlined,
    };
  }

  String _tvSectionLabel(BiliLibrarySection section) {
    return switch (section) {
      BiliLibrarySection.following => '关注',
      BiliLibrarySection.history => '历史播放',
      BiliLibrarySection.watchLater => '稍后再看',
    };
  }

  Widget _buildTvSection(BuildContext context, BiliLibrarySection section) {
    final state = _stateFor(section);
    if (state.loading && !state.loaded) {
      return const _TvLibraryLoadingView();
    }
    if (state.error != null && !_hasData(section, state)) {
      final canLogin =
          widget.onLoginTap != null && state.authenticationRequired;
      return _TvLibraryStatusView(
        icon: Icons.lock_outline_rounded,
        title: '暂时无法显示',
        message: state.error!,
        primaryLabel: canLogin ? '登录' : '重试',
        primaryIcon: canLogin ? Icons.login_rounded : Icons.refresh_rounded,
        onPrimary: canLogin
            ? () => unawaited(_handleLogin())
            : () => unawaited(_load(section, force: true)),
        secondaryLabel: canLogin ? '重试' : null,
        secondaryIcon: canLogin ? Icons.refresh_rounded : null,
        onSecondary: canLogin
            ? () => unawaited(_load(section, force: true))
            : null,
        autofocusPrimary: !widget.embeddedTvFollowing,
      );
    }
    return switch (section) {
      BiliLibrarySection.following => _buildTvFollowingBrowser(state),
      BiliLibrarySection.history => _buildTvHistoryGrid(state),
      BiliLibrarySection.watchLater => _buildTvWatchLaterGrid(state),
    };
  }

  Widget _buildTvFollowingBrowser(_LibraryLoadState state) {
    return _TvFollowingSpaceBrowser(
      following: state.following,
      followingHasMore: state.hasMore,
      followingLoadingMore: state.loadingMore,
      autofocusFirstRailItem: !widget.embeddedTvFollowing,
      initialRailCollapsed: widget.embeddedTvFollowing,
      forceCompactRail: widget.forceCompactTvFollowingRail,
      railOffset: widget.tvFollowingRailOffset,
      padding: widget.embeddedTvFollowing
          ? EdgeInsets.fromLTRB(
              0,
              widget.tvFollowingVerticalInset,
              28,
              widget.tvFollowingVerticalInset,
            )
          : const EdgeInsets.fromLTRB(28, 8, 28, 30),
      client: widget.client,
      onLoadMoreFollowing: () => _loadMore(BiliLibrarySection.following),
      onSearchFollowing: _loadFollowingPagesForSearch,
      onRefreshFollowing: () =>
          _load(BiliLibrarySection.following, force: true),
      onLogin: widget.onLoginTap == null ? null : _handleLogin,
      onOpenVideo: (video) =>
          _openVideo(bvid: video.bvid, aid: video.aid, cid: null),
    );
  }

  Future<void> _loadFollowingPagesForSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return;
    }
    final state = _stateFor(BiliLibrarySection.following);
    // Bound one explicit search action to six follow-list pages. This keeps a
    // typo from walking an unbounded account list while still covering the
    // first 300 follows; the rail retains an explicit load-more control.
    for (
      var loadedPages = 0;
      loadedPages < 6 && state.hasMore && mounted;
      loadedPages += 1
    ) {
      if (_followingMatches(state.following, normalized)) {
        return;
      }
      await _loadMore(BiliLibrarySection.following);
      if (state.loadingMore) {
        return;
      }
    }
  }

  bool _followingMatches(List<BiliFollowingUser> users, String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return users.isNotEmpty;
    }
    if (RegExp(r'^\d+$').hasMatch(normalized)) {
      return users.any((user) => user.mid.toString() == normalized);
    }
    final lowerCase = normalized.toLowerCase();
    return users.any((user) => user.name.toLowerCase().contains(lowerCase));
  }

  Widget _buildTvHistoryGrid(_LibraryLoadState state) {
    if (state.history.isEmpty) {
      return _TvLibraryStatusView(
        icon: Icons.history_rounded,
        title: '还没有播放历史',
        message: '看过的视频会在这里继续播放。',
        primaryLabel: '刷新',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: () =>
            unawaited(_load(BiliLibrarySection.history, force: true)),
      );
    }
    return _buildTvGrid(
      section: BiliLibrarySection.history,
      itemCount: state.history.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.history.length) {
          return _TvLibraryLoadMoreTile(
            key: const ValueKey<String>('bili-tv-library-load-more-history'),
            loading: state.loadingMore,
            onTap: () => unawaited(_loadMore(BiliLibrarySection.history)),
          );
        }
        final item = state.history[index];
        final identity = _historyIdentity(item);
        return _TvLibraryVideoCard(
          key: ValueKey<String>('bili-tv-library-card-history-$identity'),
          title: item.title,
          subtitle: '${item.ownerName} · ${item.pageTitle}',
          coverUrl: item.coverUrl,
          progressMs: item.progressMs,
          durationMs: item.durationMs,
          autofocus: index == 0,
          debugLabel: 'tv_library_history_$identity',
          onTap: () => _openVideo(
            bvid: item.bvid,
            aid: item.aid,
            cid: item.cid,
            episodeId: item.episodeId,
            initialPositionMs: item.progressMs,
          ),
        );
      },
    );
  }

  Widget _buildTvWatchLaterGrid(_LibraryLoadState state) {
    if (state.watchLater.isEmpty) {
      return _TvLibraryStatusView(
        icon: Icons.watch_later_outlined,
        title: '稍后再看是空的',
        message: '加入的视频会显示在这里。',
        primaryLabel: '刷新',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: () =>
            unawaited(_load(BiliLibrarySection.watchLater, force: true)),
      );
    }
    return _buildTvGrid(
      section: BiliLibrarySection.watchLater,
      itemCount: state.watchLater.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.watchLater.length) {
          return _TvLibraryLoadMoreTile(
            key: const ValueKey<String>('bili-tv-library-load-more-watchLater'),
            loading: state.loadingMore,
            onTap: () => unawaited(_loadMore(BiliLibrarySection.watchLater)),
          );
        }
        final item = state.watchLater[index];
        final identity = _watchLaterIdentity(item);
        return _TvLibraryVideoCard(
          key: ValueKey<String>('bili-tv-library-card-watchLater-$identity'),
          title: item.title,
          subtitle: '${item.ownerName} · ${item.pageTitle}',
          coverUrl: item.coverUrl,
          progressMs: item.progressMs,
          durationMs: item.durationMs,
          autofocus: index == 0,
          debugLabel: 'tv_library_watch_later_$identity',
          removeKey: ValueKey<String>('bili-tv-library-remove-$identity'),
          onRemove: () => unawaited(_removeWatchLater(item)),
          onTap: () => _openVideo(
            bvid: item.bvid,
            aid: item.aid,
            cid: item.cid,
            episodeId: item.episodeId,
            initialPositionMs: item.progressMs,
          ),
        );
      },
    );
  }

  Widget _buildTvGrid({
    required BiliLibrarySection section,
    required int itemCount,
    required NullableIndexedWidgetBuilder itemBuilder,
    double childAspectRatio = 1.08,
  }) {
    return TvFocusAreaScope(
      area: TvFocusArea.content,
      child: TvFocusOverlayScope(
        child: GridView.builder(
          key: ValueKey<String>('bili-tv-library-grid-${section.name}'),
          clipBehavior: Clip.none,
          padding: const EdgeInsets.all(tvFocusSafeInset),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisSpacing: 24,
            crossAxisSpacing: 22,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, BiliLibrarySection section) {
    final state = _stateFor(section);
    if (state.loading && !state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && !_hasData(section, state)) {
      return _LibraryErrorView(
        message: state.error!,
        onLogin: widget.onLoginTap == null ? null : _handleLogin,
        onRetry: () => _load(section, force: true),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(section, force: true),
      child: switch (section) {
        BiliLibrarySection.following => _buildFollowingList(state),
        BiliLibrarySection.history => _buildHistoryList(state),
        BiliLibrarySection.watchLater => _buildWatchLaterList(state),
      },
    );
  }

  bool _hasData(BiliLibrarySection section, _LibraryLoadState state) {
    return switch (section) {
      BiliLibrarySection.following => state.following.isNotEmpty,
      BiliLibrarySection.history => state.history.isNotEmpty,
      BiliLibrarySection.watchLater => state.watchLater.isNotEmpty,
    };
  }

  Widget _buildFollowingList(_LibraryLoadState state) {
    if (state.following.isEmpty) {
      return const _LibraryEmptyView(message: '还没有关注任何 UP 主。');
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      itemCount: state.following.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == state.following.length) {
          return _LibraryLoadMoreButton(
            loading: state.loadingMore,
            onPressed: () => _loadMore(BiliLibrarySection.following),
          );
        }
        final user = state.following[index];
        return _FollowingTile(
          user: user,
          onTap: () => unawaited(_openUserSpace(user)),
        );
      },
    );
  }

  Widget _buildHistoryList(_LibraryLoadState state) {
    if (state.history.isEmpty) {
      return const _LibraryEmptyView(message: '还没有云端播放历史。');
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      itemCount: state.history.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == state.history.length) {
          return _LibraryLoadMoreButton(
            loading: state.loadingMore,
            onPressed: () => _loadMore(BiliLibrarySection.history),
          );
        }
        final item = state.history[index];
        return _LibraryVideoTile(
          title: item.title,
          subtitle: '${item.ownerName} · ${item.pageTitle}',
          coverUrl: item.coverUrl,
          progressMs: item.progressMs,
          durationMs: item.durationMs,
          onTap: () => _openVideo(
            bvid: item.bvid,
            aid: item.aid,
            cid: item.cid,
            episodeId: item.episodeId,
            initialPositionMs: item.progressMs,
          ),
        );
      },
    );
  }

  Widget _buildWatchLaterList(_LibraryLoadState state) {
    if (state.watchLater.isEmpty) {
      return const _LibraryEmptyView(message: '稍后再看列表是空的。');
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      itemCount: state.watchLater.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == state.watchLater.length) {
          return _LibraryLoadMoreButton(
            loading: state.loadingMore,
            onPressed: () => _loadMore(BiliLibrarySection.watchLater),
          );
        }
        final item = state.watchLater[index];
        return _LibraryVideoTile(
          title: item.title,
          subtitle: '${item.ownerName} · ${item.pageTitle}',
          coverUrl: item.coverUrl,
          progressMs: item.progressMs,
          durationMs: item.durationMs,
          trailing: IconButton(
            tooltip: '移出稍后再看',
            onPressed: () => _removeWatchLater(item),
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          onTap: () => _openVideo(
            bvid: item.bvid,
            aid: item.aid,
            cid: item.cid,
            episodeId: item.episodeId,
            initialPositionMs: item.progressMs,
          ),
        );
      },
    );
  }
}

final class _LibraryLoadState {
  bool loading = false;
  bool loadingMore = false;
  bool loaded = false;
  bool hasMore = true;
  int page = 1;
  int remoteHistoryCount = 0;
  int historyMax = 0;
  int historyViewAtMs = 0;
  String? error;
  bool authenticationRequired = false;
  List<BiliFollowingUser> following = const <BiliFollowingUser>[];
  List<BiliRemoteHistoryEntry> localHistory = const <BiliRemoteHistoryEntry>[];
  List<BiliRemoteHistoryEntry> history = const <BiliRemoteHistoryEntry>[];
  List<BiliWatchLaterEntry> watchLater = const <BiliWatchLaterEntry>[];
}
