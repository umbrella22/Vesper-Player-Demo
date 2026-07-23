import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/pages/bili_playback_page.dart';
import 'package:bilibili_player/bili/common/services/bili_api_core.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
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
  final Map<BiliLibrarySection, _LibraryLoadState> _states =
      <BiliLibrarySection, _LibraryLoadState>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: BiliLibrarySection.values.length,
      vsync: this,
      initialIndex: widget.initialSection.index,
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
    return BiliLibrarySection.values[index.clamp(0, 2)];
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
    if (section == BiliLibrarySection.history) {
      // Local history remains useful while logged out and is also a fallback
      // when the cloud cursor endpoint is temporarily unavailable.
      try {
        final local = await (widget.historyStore ?? const BiliHistoryStore())
            .loadEntries();
        state.localHistory = local
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
        state.history = state.localHistory;
        state.remoteHistoryCount = 0;
      } catch (_) {
        state.localHistory = const <BiliRemoteHistoryEntry>[];
        state.history = const <BiliRemoteHistoryEntry>[];
        state.remoteHistoryCount = 0;
      }
    }
    if (!hasAuthenticatedSession) {
      if (mounted) {
        setState(() {
          _clearAuthenticatedData(section, state);
          state.loading = false;
          state.loaded = true;
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
        if (force) {
          state.page = 1;
          state.hasMore = true;
          state.remoteHistoryCount = 0;
          state.historyMax = 0;
          state.historyViewAtMs = 0;
        }
        state.loading = true;
        state.error = null;
      });
    }
    try {
      switch (section) {
        case BiliLibrarySection.following:
          state.following = await widget.client.fetchFollowingUsers(
            page: 1,
            pageSize: _followingPageSize,
          );
          state.hasMore = state.following.length >= _followingPageSize;
        case BiliLibrarySection.history:
          final page = await widget.client.fetchRemoteHistoryPage(
            page: 1,
            pageSize: _historyPageSize,
          );
          final remote = page.entries;
          final seen = remote.map(_historyIdentity).toSet();
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
          state.watchLater = await widget.client.fetchWatchLater(
            page: 1,
            pageSize: _watchLaterPageSize,
          );
          state.hasMore = state.watchLater.length >= _watchLaterPageSize;
      }
      state.loaded = true;
    } catch (error) {
      state.error = _libraryError(error);
      if (error is BiliApiException && error.code == -101) {
        _clearAuthenticatedData(section, state);
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
    } catch (error) {
      state.error = _libraryError(error);
      if (error is BiliApiException && error.code == -101) {
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F8),
      appBar: AppBar(
        title: const Text('我的内容'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF20232B),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFFB7299),
          unselectedLabelColor: const Color(0xFF858A94),
          indicatorColor: const Color(0xFFFB7299),
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_outlined), text: '关注'),
            Tab(icon: Icon(Icons.history_rounded), text: '历史播放'),
            Tab(icon: Icon(Icons.watch_later_outlined), text: '稍后再看'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: BiliLibrarySection.values
            .map((section) => _buildSection(context, section))
            .toList(growable: false),
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
                  color: Color(0xFFFB7299),
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
                            color: const Color(0xFFFB7299),
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
          color: Color(0xFFFB7299),
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
