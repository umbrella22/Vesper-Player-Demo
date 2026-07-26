import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:bilibili_player/app/design/app_glass_controls.dart';
import 'package:bilibili_player/app/design/app_visual_theme.dart';
import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/pages/bili_playback_page.dart';
import 'package:bilibili_player/bili/common/services/bili_api_core.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_directional_focus_scope.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_focusable.dart';
import 'package:bilibili_player/download/download.dart';

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
  });

  final BiliClient client;
  final BiliLibrarySection initialSection;
  final BiliHistoryStore? historyStore;
  final BiliOfflineDownloadController? offlineController;
  final Future<void> Function()? onLoginTap;
  final BiliPlaybackPresentationMode presentationMode;

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
    _visibleSections = _isTv
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
        _showMessage('加载更多失败：$error');
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
    return '加载失败：$error';
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
      if (mounted) {
        await _load(_sectionForIndex(_tabController.index), force: true);
      }
    } catch (error) {
      _showMessage('打开视频失败：$error');
    }
  }

  Future<void> _removeWatchLater(BiliWatchLaterEntry entry) async {
    try {
      await widget.client.removeFromWatchLater(
        bvid: entry.bvid,
        aid: entry.aid,
      );
      _showMessage('已移出稍后再看');
      await _load(BiliLibrarySection.watchLater, force: true);
    } catch (error) {
      _showMessage('移除失败：$error');
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
    if (_isTv) {
      return _buildTvPage(context);
    }
    return _buildPhonePage(context);
  }

  Widget _buildPhonePage(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    const appBarContentHeight = 110.0;
    final appBarSurfaceHeight = topPadding + appBarContentHeight;
    return AppGlassScaffold(
      backgroundColor: AppVisualTokens.mobileBackground,
      extendBody: false,
      appBarHeight: appBarContentHeight,
      appBar: SizedBox(
        height: appBarSurfaceHeight,
        child: Column(
          children: [
            if (topPadding > 0) SizedBox(height: topPadding),
            SizedBox(
              height: 44,
              child: GlassContainer(
                key: const ValueKey<String>('bili-library-phone-toolbar'),
                useOwnLayer: true,
                quality: GlassQuality.standard,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: EdgeInsets.zero,
                shape: const LiquidRoundedSuperellipse(
                  borderRadius: AppVisualTokens.controlRadius,
                ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
            const SizedBox(height: 2),
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
      onBack: () => Navigator.of(context).maybePop(),
      child: Scaffold(
        key: const ValueKey<String>('bili-tv-library-root'),
        backgroundColor: const Color(0xFF0A0A0E),
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
          const Expanded(
            child: Text(
              '我的内容',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
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
      );
    }
    return switch (section) {
      BiliLibrarySection.following => _buildTvFollowingGrid(state),
      BiliLibrarySection.history => _buildTvHistoryGrid(state),
      BiliLibrarySection.watchLater => _buildTvWatchLaterGrid(state),
    };
  }

  Widget _buildTvFollowingGrid(_LibraryLoadState state) {
    if (state.following.isEmpty) {
      return _TvLibraryStatusView(
        icon: Icons.people_alt_outlined,
        title: '还没有关注内容',
        message: '关注的 UP 主会显示在这里。',
        primaryLabel: '刷新',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: () =>
            unawaited(_load(BiliLibrarySection.following, force: true)),
      );
    }
    return _buildTvGrid(
      section: BiliLibrarySection.following,
      childAspectRatio: 0.95,
      itemCount: state.following.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.following.length) {
          return _TvLibraryLoadMoreTile(
            key: const ValueKey<String>('bili-tv-library-load-more-following'),
            loading: state.loadingMore,
            onTap: () => unawaited(_loadMore(BiliLibrarySection.following)),
          );
        }
        final user = state.following[index];
        return _TvFollowingCard(
          key: ValueKey<String>('bili-tv-library-card-following-${user.mid}'),
          user: user,
          autofocus: index == 0,
          onTap: () => _showMessage('TV 端暂不支持打开 UP 主空间。'),
        );
      },
    );
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
      child: GridView.builder(
        key: ValueKey<String>('bili-tv-library-grid-${section.name}'),
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 34),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisSpacing: 24,
          crossAxisSpacing: 22,
          childAspectRatio: childAspectRatio,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
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
        return _FollowingTile(user: user);
      },
    );
  }

  Widget _buildHistoryList(_LibraryLoadState state) {
    if (state.history.isEmpty) {
      return const _LibraryEmptyView(message: '还没有云端播放历史。');
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
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

class _LibraryLoadMoreButton extends StatelessWidget {
  const _LibraryLoadMoreButton({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more_rounded),
        label: Text(loading ? '加载中' : '加载更多'),
      ),
    );
  }
}

class _FollowingTile extends StatelessWidget {
  const _FollowingTile({required this.user});

  final BiliFollowingUser user;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFFFFDCE7),
          backgroundImage: user.avatarUrl.isEmpty
              ? null
              : NetworkImage(user.avatarUrl),
          child: user.avatarUrl.isEmpty
              ? const Icon(
                  Icons.person_outline_rounded,
                  color: AppVisualTokens.primaryBlue,
                )
              : null,
        ),
        title: Text(
          user.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          user.sign.isEmpty ? (user.officialLabel ?? '已关注') : user.sign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _LibraryVideoTile extends StatelessWidget {
  const _LibraryVideoTile({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.progressMs,
    required this.durationMs,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final int progressMs;
  final int durationMs;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final progress = durationMs <= 0
        ? 0.0
        : (progressMs / durationMs).clamp(0.0, 1.0).toDouble();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 116,
                  height: 70,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      coverUrl.isEmpty
                          ? const ColoredBox(color: Color(0xFFE9ECF2))
                          : Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: Color(0xFFE9ECF2)),
                            ),
                      if (progress > 0)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.25,
                            ),
                            color: AppVisualTokens.primaryBlue,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF20232B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF858A94),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryErrorView extends StatelessWidget {
  const _LibraryErrorView({required this.message, this.onLogin, this.onRetry});

  final String message;
  final VoidCallback? onLogin;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          size: 44,
          color: AppVisualTokens.primaryBlue,
        ),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 18),
        if (onLogin != null)
          FilledButton(onPressed: onLogin, child: const Text('登录')),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

class _LibraryEmptyView extends StatelessWidget {
  const _LibraryEmptyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.inbox_outlined, size: 42, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

int _tvLibraryCoverCacheWidth(BuildContext context, double logicalWidth) {
  return (logicalWidth * MediaQuery.devicePixelRatioOf(context))
      .ceil()
      .clamp(160, 720)
      .toInt();
}

class _TvLibraryHeaderButton extends StatelessWidget {
  const _TvLibraryHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: TvFocusableSurface(
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.05,
        borderRadius: 12,
        focusArea: TvFocusArea.content,
        debugLabel: 'tv_library_$tooltip',
        onTap: onTap,
        builder: (context, focused) {
          return Tooltip(
            message: tooltip,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white.withValues(alpha: 0.20)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused
                      ? Colors.white.withValues(alpha: 0.78)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppVisualTokens.primaryBlue,
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: 24),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TvLibraryTab extends StatelessWidget {
  const _TvLibraryTab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 146,
      height: 48,
      child: TvGlassSelectable(
        selected: selected,
        useOwnLayer: true,
        scale: 1.04,
        borderRadius: 12,
        focusArea: TvFocusArea.content,
        debugLabel: 'tv_library_tab_$label',
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        builder: (context, state) {
          final focused =
              state == TvGlassSelectableState.focused ||
              state == TvGlassSelectableState.pressed;
          final foreground = selected || focused
              ? Colors.white
              : const Color(0x99FFFFFF);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 21),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: selected || focused
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                key: ValueKey<String>('bili-tv-library-tab-marker-$label'),
                duration: AppVisualTokens.motionDuration(
                  context,
                  AppVisualTokens.tvFocusDuration,
                ),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: selected
                      ? AppVisualTokens.primaryBlue
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TvLibraryLoadingView extends StatelessWidget {
  const _TvLibraryLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppVisualTokens.primaryBlue,
            ),
          ),
          SizedBox(height: 18),
          Text(
            '正在加载内容',
            style: TextStyle(
              color: Color(0x99FFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvLibraryStatusView extends StatelessWidget {
  const _TvLibraryStatusView({
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0x88FFFFFF), size: 54),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              if (onPrimary != null && primaryLabel != null) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _TvLibraryActionButton(
                      autofocus: true,
                      icon: primaryIcon ?? Icons.check_rounded,
                      label: primaryLabel!,
                      primary: true,
                      onTap: onPrimary!,
                    ),
                    if (onSecondary != null && secondaryLabel != null)
                      _TvLibraryActionButton(
                        icon: secondaryIcon ?? Icons.more_horiz_rounded,
                        label: secondaryLabel!,
                        onTap: onSecondary!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TvLibraryActionButton extends StatelessWidget {
  const _TvLibraryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 50,
      child: TvFocusableSurface(
        autofocus: autofocus,
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.04,
        borderRadius: 12,
        focusArea: TvFocusArea.content,
        debugLabel: 'tv_library_action_$label',
        onTap: onTap,
        builder: (context, focused) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.22)
                  : primary
                  ? AppVisualTokens.primaryBlue
                  : Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused
                    ? Colors.white.withValues(alpha: 0.85)
                    : primary
                    ? const Color(0x44FFFFFF)
                    : const Color(0x18FFFFFF),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
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

class _TvFollowingCard extends StatelessWidget {
  const _TvFollowingCard({
    super.key,
    required this.user,
    required this.autofocus,
    required this.onTap,
  });

  final BiliFollowingUser user;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatarCacheWidth = _tvLibraryCoverCacheWidth(context, 76);
    return TvFocusableSurface(
      autofocus: autofocus,
      useOverlayLift: false,
      focusPadding: 0,
      scale: 1.045,
      borderRadius: 12,
      focusArea: TvFocusArea.content,
      debugLabel: 'tv_library_following_${user.mid}',
      onTap: onTap,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: focused
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused
                  ? AppVisualTokens.primaryBlue
                  : const Color(0x18FFFFFF),
              width: focused ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipOval(
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: ColoredBox(
                    color: const Color(0xFF262630),
                    child: user.avatarUrl.isEmpty
                        ? const Icon(
                            Icons.person_outline_rounded,
                            color: Color(0x88FFFFFF),
                            size: 38,
                          )
                        : Image.network(
                            user.avatarUrl,
                            fit: BoxFit.cover,
                            cacheWidth: avatarCacheWidth,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.person_outline_rounded,
                              color: Color(0x88FFFFFF),
                              size: 38,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                user.sign.isEmpty ? (user.officialLabel ?? '已关注') : user.sign,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0x88FFFFFF),
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvLibraryVideoCard extends StatelessWidget {
  const _TvLibraryVideoCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.progressMs,
    required this.durationMs,
    required this.autofocus,
    required this.debugLabel,
    required this.onTap,
    this.removeKey,
    this.onRemove,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final int progressMs;
  final int durationMs;
  final bool autofocus;
  final String debugLabel;
  final VoidCallback onTap;
  final Key? removeKey;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final progress = durationMs <= 0
        ? 0.0
        : (progressMs / durationMs).clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheWidth = _tvLibraryCoverCacheWidth(
          context,
          constraints.maxWidth,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: TvFocusableSurface(
                autofocus: autofocus,
                useOverlayLift: false,
                focusPadding: 0,
                scale: 1.045,
                borderRadius: 12,
                focusArea: TvFocusArea.content,
                debugLabel: debugLabel,
                onTap: onTap,
                builder: (context, focused) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          foregroundDecoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: focused
                                  ? AppVisualTokens.primaryBlue
                                  : const Color(0x1AFFFFFF),
                              width: focused ? 2 : 1,
                            ),
                          ),
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
                                          size: 42,
                                        )
                                      : Image.network(
                                          coverUrl,
                                          fit: BoxFit.cover,
                                          cacheWidth: cacheWidth,
                                          errorBuilder: (_, _, _) =>
                                              const ColoredBox(
                                                color: Color(0xFF1A1A24),
                                                child: Icon(
                                                  Icons.broken_image_outlined,
                                                  color: Color(0x55FFFFFF),
                                                  size: 36,
                                                ),
                                              ),
                                        ),
                                ),
                                if (progress > 0)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 4,
                                      backgroundColor: Colors.black.withValues(
                                        alpha: 0.42,
                                      ),
                                      color: AppVisualTokens.primaryBlue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: focused
                              ? Colors.white
                              : const Color(0xE6FFFFFF),
                          fontSize: 14,
                          fontWeight: focused
                              ? FontWeight.w800
                              : FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0x77FFFFFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 8,
                right: 8,
                child: _TvLibraryRemoveButton(key: removeKey, onTap: onRemove!),
              ),
          ],
        );
      },
    );
  }
}

class _TvLibraryRemoveButton extends StatelessWidget {
  const _TvLibraryRemoveButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: TvFocusableSurface(
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.06,
        borderRadius: 10,
        focusArea: TvFocusArea.content,
        debugLabel: 'tv_library_remove_watch_later',
        onTap: onTap,
        builder: (context, focused) {
          return Tooltip(
            message: '移出稍后再看',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: focused
                    ? AppVisualTokens.primaryBlue
                    : Colors.black.withValues(alpha: 0.74),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused
                      ? Colors.white.withValues(alpha: 0.88)
                      : Colors.white.withValues(alpha: 0.22),
                ),
              ),
              child: const Icon(
                Icons.remove_circle_outline_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TvLibraryLoadMoreTile extends StatelessWidget {
  const _TvLibraryLoadMoreTile({
    super.key,
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusableSurface(
      useOverlayLift: false,
      focusPadding: 0,
      scale: 1.04,
      borderRadius: 12,
      focusArea: TvFocusArea.content,
      debugLabel: 'tv_library_load_more',
      onTap: loading ? () {} : onTap,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: focused
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused
                  ? Colors.white.withValues(alpha: 0.72)
                  : const Color(0x16FFFFFF),
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppVisualTokens.primaryBlue,
                    ),
                  )
                else
                  const Icon(
                    Icons.expand_more_rounded,
                    color: Color(0xCCFFFFFF),
                    size: 32,
                  ),
                const SizedBox(height: 10),
                Text(
                  loading ? '加载中' : '加载更多',
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
