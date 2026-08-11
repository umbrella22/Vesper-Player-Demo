part of 'bili_library_page.dart';

const _tvFollowingCompactRailWidth = 88.0;
const _tvFollowingExpandedRailWidth = 312.0;
const _tvFollowingContentGap = 20.0;

/// The TV variant keeps the followed-UP list visible while browsing uploads.
/// It deliberately owns only presentation state; API/authentication/WBI remain
/// in [BiliClient], and the library page remains the owner of follow paging.
class _TvFollowingSpaceBrowser extends StatefulWidget {
  const _TvFollowingSpaceBrowser({
    required this.following,
    required this.followingHasMore,
    required this.followingLoadingMore,
    required this.autofocusFirstRailItem,
    required this.initialRailCollapsed,
    required this.forceCompactRail,
    required this.railOffset,
    required this.padding,
    required this.client,
    required this.onLoadMoreFollowing,
    required this.onSearchFollowing,
    required this.onRefreshFollowing,
    required this.onOpenVideo,
    this.onLogin,
  });

  final List<BiliFollowingUser> following;
  final bool followingHasMore;
  final bool followingLoadingMore;
  final bool autofocusFirstRailItem;
  final bool initialRailCollapsed;
  final bool forceCompactRail;
  final double railOffset;
  final EdgeInsetsGeometry padding;
  final BiliClient client;
  final Future<void> Function() onLoadMoreFollowing;
  final Future<void> Function(String query) onSearchFollowing;
  final Future<void> Function() onRefreshFollowing;
  final Future<void> Function()? onLogin;
  final ValueChanged<BiliUserSpaceVideo> onOpenVideo;

  @override
  State<_TvFollowingSpaceBrowser> createState() =>
      _TvFollowingSpaceBrowserState();
}

class _TvFollowingSpaceBrowserState extends State<_TvFollowingSpaceBrowser> {
  static const _videoPageSize = 30;

  final TextEditingController _followingQueryController =
      TextEditingController();
  final TextEditingController _videoQueryController = TextEditingController();
  final FocusNode _followingSearchFocusNode = FocusNode(
    debugLabel: 'tv_following_search',
  );
  final FocusNode _videoSearchFocusNode = FocusNode(
    debugLabel: 'tv_space_video_search',
  );

  BiliFollowingUser? _selectedUser;
  BiliUserSpaceProfile? _profile;
  List<BiliUserSpaceVideo> _videos = const <BiliUserSpaceVideo>[];
  String _activeVideoKeyword = '';
  String? _spaceError;
  bool _spaceLoading = false;
  bool _spaceLoadingMore = false;
  bool _spaceLoaded = false;
  bool _spaceHasMore = false;
  bool _spaceAuthenticationRequired = false;
  bool _exactBvidResult = false;
  late bool _railCollapsed;
  bool _railCollapseCallbackScheduled = false;
  bool? _pendingRailCollapsed;
  int _videoPage = 1;
  int _spaceGeneration = 0;

  @override
  void initState() {
    super.initState();
    _railCollapsed = widget.initialRailCollapsed;
    setTvFocusArea(_followingSearchFocusNode, TvFocusArea.rail);
    setTvFocusArea(_videoSearchFocusNode, TvFocusArea.content);
    _followingSearchFocusNode.addListener(_handleFollowingSearchFocus);
    _videoSearchFocusNode.addListener(_handleVideoSearchFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelectedUser());
  }

  @override
  void didUpdateWidget(_TvFollowingSpaceBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.following != widget.following) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureSelectedUser(),
      );
    }
  }

  @override
  void dispose() {
    _spaceGeneration += 1;
    _followingSearchFocusNode
      ..removeListener(_handleFollowingSearchFocus)
      ..dispose();
    _videoSearchFocusNode
      ..removeListener(_handleVideoSearchFocus)
      ..dispose();
    _followingQueryController.dispose();
    _videoQueryController.dispose();
    super.dispose();
  }

  List<BiliFollowingUser> get _filteredFollowing {
    final query = _followingQueryController.text.trim();
    if (query.isEmpty) {
      return widget.following;
    }
    if (RegExp(r'^\d+$').hasMatch(query)) {
      return widget.following
          .where((user) => user.mid.toString() == query)
          .toList(growable: false);
    }
    final lowerCase = query.toLowerCase();
    return widget.following
        .where((user) => user.name.toLowerCase().contains(lowerCase))
        .toList(growable: false);
  }

  void _ensureSelectedUser() {
    if (!mounted) {
      return;
    }
    if (widget.following.isEmpty) {
      _clearSelectedUser();
      return;
    }
    final selectedMid = _selectedUser?.mid;
    final stillPresent =
        selectedMid != null &&
        widget.following.any((user) => user.mid == selectedMid);
    if (stillPresent) {
      return;
    }
    unawaited(_selectUser(widget.following.first));
  }

  void _clearSelectedUser() {
    final alreadyClear =
        _selectedUser == null &&
        _profile == null &&
        _videos.isEmpty &&
        !_spaceLoading &&
        !_spaceLoadingMore &&
        !_spaceLoaded &&
        !_spaceHasMore &&
        _spaceError == null &&
        !_spaceAuthenticationRequired &&
        _activeVideoKeyword.isEmpty &&
        !_exactBvidResult &&
        _videoQueryController.text.isEmpty;
    if (alreadyClear) {
      return;
    }
    _spaceGeneration += 1;
    setState(() {
      _selectedUser = null;
      _profile = null;
      _videos = const <BiliUserSpaceVideo>[];
      _activeVideoKeyword = '';
      _videoQueryController.clear();
      _spaceError = null;
      _spaceLoading = false;
      _spaceLoadingMore = false;
      _spaceLoaded = false;
      _spaceHasMore = false;
      _spaceAuthenticationRequired = false;
      _exactBvidResult = false;
      _videoPage = 1;
    });
  }

  void _handleFollowingSearchFocus() {
    if (_followingSearchFocusNode.hasFocus) {
      _setRailCollapsed(false);
    }
  }

  void _handleVideoSearchFocus() {
    if (_videoSearchFocusNode.hasFocus) {
      _setRailCollapsed(true);
    }
  }

  void _setRailCollapsed(bool collapsed) {
    if (!mounted ||
        (_railCollapsed == collapsed && _pendingRailCollapsed == null)) {
      return;
    }
    _pendingRailCollapsed = collapsed;
    if (_railCollapseCallbackScheduled) {
      return;
    }
    _railCollapseCallbackScheduled = true;
    // Focus callbacks run while FocusManager is applying a focus transaction.
    // Defer the layout change so replacing the expanded rail cannot mutate the
    // focus-node set during that iteration.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final target = _pendingRailCollapsed;
      _pendingRailCollapsed = null;
      _railCollapseCallbackScheduled = false;
      if (target == null || _railCollapsed == target) {
        return;
      }
      setState(() {
        _railCollapsed = target;
        // The hidden field must not steal the next left/right traversal while
        // the compact avatar rail is shown.
        _followingSearchFocusNode.skipTraversal = target;
      });
    });
  }

  Future<void> _selectUser(BiliFollowingUser user, {bool force = false}) async {
    if (!force &&
        _selectedUser?.mid == user.mid &&
        (_spaceLoaded || _spaceLoading)) {
      return;
    }
    final generation = ++_spaceGeneration;
    setState(() {
      _selectedUser = user;
      _profile = BiliUserSpaceProfile.fromFollowing(user);
      _videos = const <BiliUserSpaceVideo>[];
      _activeVideoKeyword = '';
      _videoQueryController.clear();
      _spaceError = null;
      _spaceLoading = true;
      _spaceLoadingMore = false;
      _spaceLoaded = false;
      _spaceHasMore = false;
      _spaceAuthenticationRequired = false;
      _exactBvidResult = false;
      _videoPage = 1;
    });
    try {
      final profile = await widget.client.fetchUserSpaceProfile(user.mid);
      if (!mounted || generation != _spaceGeneration) {
        return;
      }
      final page = await widget.client.fetchUserSpaceVideos(
        mid: user.mid,
        pageSize: _videoPageSize,
      );
      if (!mounted || generation != _spaceGeneration) {
        return;
      }
      setState(() {
        _profile = profile;
        _videos = page.videos;
        _videoPage = page.page;
        _spaceHasMore = page.hasMore;
        _spaceLoaded = true;
      });
    } catch (error) {
      if (!mounted || generation != _spaceGeneration) {
        return;
      }
      setState(() {
        _spaceError = _spaceErrorMessage(error);
        _spaceAuthenticationRequired = _isAuthenticationError(error);
        _spaceLoaded = true;
        if (_spaceAuthenticationRequired) {
          _videos = const <BiliUserSpaceVideo>[];
          _spaceHasMore = false;
        }
      });
    } finally {
      if (mounted && generation == _spaceGeneration) {
        setState(() => _spaceLoading = false);
      }
    }
  }

  void _handleFollowingQueryChanged() {
    final matches = _filteredFollowing;
    setState(() {});
    if (matches.isNotEmpty && _selectedUser?.mid != matches.first.mid) {
      unawaited(_selectUser(matches.first));
    }
  }

  Future<void> _submitFollowingSearch() async {
    final query = _followingQueryController.text.trim();
    if (query.isEmpty ||
        _filteredFollowing.isNotEmpty ||
        !widget.followingHasMore) {
      return;
    }
    await widget.onSearchFollowing(query);
    if (!mounted) {
      return;
    }
    final matches = _filteredFollowing;
    if (matches.isNotEmpty) {
      await _selectUser(matches.first);
    }
  }

  Future<void> _loadMoreFollowing() async {
    await widget.onLoadMoreFollowing();
    if (!mounted) {
      return;
    }
    final matches = _filteredFollowing;
    if (_selectedUser == null && matches.isNotEmpty) {
      await _selectUser(matches.first);
    }
  }

  Future<void> _searchVideos() async {
    final selected = _selectedUser;
    if (selected == null || !widget.client.hasAuthenticatedSession) {
      return;
    }
    final query = _videoQueryController.text.trim();
    final bvid = biliExtractBvid(query);
    if (bvid != null) {
      final local = _findLoadedVideo(bvid);
      if (local != null) {
        setState(() {
          _videos = <BiliUserSpaceVideo>[local];
          _activeVideoKeyword = query;
          _spaceHasMore = false;
          _exactBvidResult = true;
          _spaceError = null;
        });
        return;
      }
      await _searchExactBvid(selected, query, bvid);
      return;
    }
    await _loadVideoPage(selected, keyword: query, force: true);
  }

  BiliUserSpaceVideo? _findLoadedVideo(String bvid) {
    for (final video in _videos) {
      if (video.bvid == bvid) {
        return video;
      }
    }
    return null;
  }

  Future<void> _searchExactBvid(
    BiliFollowingUser selected,
    String query,
    String bvid,
  ) async {
    final generation = ++_spaceGeneration;
    setState(() {
      _spaceLoading = true;
      _spaceLoadingMore = false;
      _spaceError = null;
      _spaceAuthenticationRequired = false;
    });
    try {
      final video = await widget.client.fetchUserSpaceVideoByBvid(
        mid: selected.mid,
        bvid: bvid,
      );
      if (!mounted || generation != _spaceGeneration) {
        return;
      }
      setState(() {
        _videos = video == null
            ? const <BiliUserSpaceVideo>[]
            : <BiliUserSpaceVideo>[video];
        _activeVideoKeyword = query;
        _videoPage = 1;
        _spaceHasMore = false;
        _exactBvidResult = true;
        _spaceLoaded = true;
        _spaceError = video == null ? '该 BV 号不属于当前 UP 主。' : null;
      });
    } catch (error) {
      if (!mounted || generation != _spaceGeneration) {
        return;
      }
      setState(() {
        _spaceError = _spaceErrorMessage(error);
        _spaceAuthenticationRequired = _isAuthenticationError(error);
        _spaceLoaded = true;
        if (_spaceAuthenticationRequired) {
          _videos = const <BiliUserSpaceVideo>[];
          _spaceHasMore = false;
        }
      });
    } finally {
      if (mounted && generation == _spaceGeneration) {
        setState(() => _spaceLoading = false);
      }
    }
  }

  Future<void> _loadVideoPage(
    BiliFollowingUser selected, {
    required String keyword,
    bool force = false,
  }) async {
    if (_spaceLoading ||
        (!force && _spaceLoaded && keyword == _activeVideoKeyword)) {
      return;
    }
    final generation = ++_spaceGeneration;
    setState(() {
      _spaceLoading = true;
      _spaceLoadingMore = false;
      _spaceError = null;
      _spaceAuthenticationRequired = false;
    });
    try {
      final page = await widget.client.fetchUserSpaceVideos(
        mid: selected.mid,
        pageSize: _videoPageSize,
        keyword: keyword,
      );
      if (!mounted || generation != _spaceGeneration) {
        return;
      }
      setState(() {
        _videos = page.videos;
        _activeVideoKeyword = keyword;
        _videoPage = page.page;
        _spaceHasMore = page.hasMore;
        _exactBvidResult = false;
        _spaceLoaded = true;
      });
    } catch (error) {
      if (!mounted || generation != _spaceGeneration) {
        return;
      }
      setState(() {
        _spaceError = _spaceErrorMessage(error);
        _spaceAuthenticationRequired = _isAuthenticationError(error);
        _spaceLoaded = true;
        if (_spaceAuthenticationRequired) {
          _videos = const <BiliUserSpaceVideo>[];
          _spaceHasMore = false;
        }
      });
    } finally {
      if (mounted && generation == _spaceGeneration) {
        setState(() => _spaceLoading = false);
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    final selected = _selectedUser;
    if (selected == null ||
        _spaceLoading ||
        _spaceLoadingMore ||
        !_spaceHasMore ||
        _exactBvidResult ||
        !widget.client.hasAuthenticatedSession) {
      return;
    }
    final generation = ++_spaceGeneration;
    setState(() {
      _spaceLoadingMore = true;
      _spaceError = null;
    });
    try {
      final next = await widget.client.fetchUserSpaceVideos(
        mid: selected.mid,
        page: _videoPage + 1,
        pageSize: _videoPageSize,
        keyword: _activeVideoKeyword,
      );
      if (!mounted || generation != _spaceGeneration) {
        return;
      }
      final seen = _videos.map((item) => item.bvid).toSet();
      final unique = next.videos
          .where((video) => video.bvid.isNotEmpty && seen.add(video.bvid))
          .toList(growable: false);
      setState(() {
        _videos = <BiliUserSpaceVideo>[..._videos, ...unique];
        _videoPage = next.page;
        _spaceHasMore = next.hasMore && unique.isNotEmpty;
      });
    } catch (error) {
      if (!mounted || generation != _spaceGeneration) {
        return;
      }
      setState(() {
        _spaceError = _spaceErrorMessage(error);
        _spaceAuthenticationRequired = _isAuthenticationError(error);
        if (_spaceAuthenticationRequired) {
          _videos = const <BiliUserSpaceVideo>[];
          _spaceHasMore = false;
        }
      });
    } finally {
      if (mounted && generation == _spaceGeneration) {
        setState(() => _spaceLoadingMore = false);
      }
    }
  }

  Future<void> _reloadSelectedSpace() async {
    final selected = _selectedUser;
    if (selected != null) {
      await _selectUser(selected, force: true);
    }
  }

  Future<void> _loginAndReload() async {
    final onLogin = widget.onLogin;
    if (onLogin == null) {
      return;
    }
    final selectedMidBeforeLogin = _selectedUser?.mid;
    await onLogin();
    if (!mounted || !widget.client.hasAuthenticatedSession) {
      return;
    }
    // The parent refreshes the following list after login. Wait for that
    // update to reach this child before deciding whether the old UP is still
    // a valid reload target.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !widget.client.hasAuthenticatedSession) {
      return;
    }
    final selected = _selectedUser;
    final stillFollowingOriginal =
        selected != null &&
        selected.mid == selectedMidBeforeLogin &&
        widget.following.any((user) => user.mid == selected.mid);
    if (stillFollowingOriginal) {
      await _selectUser(selected, force: true);
    }
  }

  bool _isAuthenticationError(Object error) {
    return error is BiliApiException && error.code == -101;
  }

  String _spaceErrorMessage(Object error) {
    if (_isAuthenticationError(error)) {
      return '登录状态已失效，请重新登录后再试。';
    }
    if (error is BiliApiException &&
        (error.code == biliRiskControlCode || error.code == -412)) {
      return 'Bilibili 暂时限制了空间请求，请稍后重试。';
    }
    return '加载失败：${biliErrorMessage(error)}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) {
        final collapsed = _railCollapsed || widget.forceCompactRail;
        final contentOffset =
            widget.railOffset +
            (collapsed
                ? 0
                : _tvFollowingExpandedRailWidth - _tvFollowingCompactRailWidth);
        final duration = AppVisualTokens.motionDuration(
          context,
          AppVisualTokens.tvFocusDuration,
        );
        return Padding(
          padding: widget.padding,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              AnimatedPositioned(
                key: const ValueKey<String>('bili-tv-following-content-area'),
                duration: duration,
                curve: Curves.easeOutCubic,
                left:
                    _tvFollowingCompactRailWidth +
                    _tvFollowingContentGap +
                    contentOffset,
                top: 0,
                right: -contentOffset,
                bottom: 0,
                child: TvFocusGroupScope(
                  group: const ValueKey<String>('tv-following-space-content'),
                  child: _buildSubmissionsPane(context),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: widget.railOffset,
                top: 0,
                bottom: 0,
                child: _buildFollowingRail(context, collapsed: collapsed),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFollowingRail(BuildContext context, {required bool collapsed}) {
    final visualTheme = AppVisualTheme.of(context);
    final filtered = _filteredFollowing;
    return AnimatedContainer(
      key: const ValueKey<String>('bili-tv-following-rail'),
      duration: AppVisualTokens.motionDuration(
        context,
        AppVisualTokens.tvFocusDuration,
      ),
      curve: Curves.easeOutCubic,
      width: collapsed
          ? _tvFollowingCompactRailWidth
          : _tvFollowingExpandedRailWidth,
      decoration: BoxDecoration(
        color: visualTheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
        border: Border.all(color: visualTheme.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            key: ValueKey<String>(
              collapsed
                  ? 'bili-tv-following-rail-collapsed'
                  : 'bili-tv-following-rail-expanded',
            ),
            width: 0,
            height: 0,
          ),
          if (!collapsed) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: TextField(
                key: const ValueKey<String>('bili-tv-following-search'),
                controller: _followingQueryController,
                focusNode: _followingSearchFocusNode,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                onChanged: (_) => _handleFollowingQueryChanged(),
                onSubmitted: (_) => unawaited(_submitFollowingSearch()),
                decoration: InputDecoration(
                  hintText: '搜索关注的 UP 或 UID',
                  hintStyle: const TextStyle(color: Color(0x77FFFFFF)),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xAA409EFF),
                    size: 21,
                  ),
                  suffixIcon: _followingQueryController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _followingQueryController.clear();
                            _handleFollowingQueryChanged();
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xBBFFFFFF),
                            size: 19,
                          ),
                        ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppVisualTokens.primaryBlue,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_alt_outlined,
                    color: Color(0xAAFFFFFF),
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      '关注的 UP 主',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.following.length}',
                    style: const TextStyle(
                      color: Color(0x88FFFFFF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: _buildFollowingList(context, filtered, collapsed: collapsed),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowingList(
    BuildContext context,
    List<BiliFollowingUser> users, {
    required bool collapsed,
  }) {
    if (users.isEmpty) {
      return _buildFollowingRailEmpty(context, collapsed: collapsed);
    }
    final includeLoadMore =
        widget.followingHasMore &&
        (!_followingQueryController.text.trim().isNotEmpty || users.isEmpty);
    return ListView.separated(
      key: const ValueKey<String>('bili-tv-following-list'),
      padding: EdgeInsets.fromLTRB(
        collapsed ? 8 : 10,
        4,
        collapsed ? 8 : 10,
        14,
      ),
      itemCount: users.length + (includeLoadMore ? 1 : 0),
      separatorBuilder: (_, _) => SizedBox(height: collapsed ? 8 : 6),
      itemBuilder: (context, index) {
        if (index == users.length) {
          return _TvFollowingRailLoadMore(
            collapsed: collapsed,
            loading: widget.followingLoadingMore,
            onFocused: () => _setRailCollapsed(false),
            onTap: () => unawaited(_loadMoreFollowing()),
          );
        }
        final user = users[index];
        return _TvFollowingRailUser(
          key: ValueKey<String>('bili-tv-following-user-${user.mid}'),
          user: user,
          selected: _selectedUser?.mid == user.mid,
          collapsed: collapsed,
          autofocus:
              widget.autofocusFirstRailItem &&
              index == 0 &&
              _selectedUser == null,
          onFocused: () => _setRailCollapsed(false),
          onTap: () => unawaited(_selectUser(user)),
        );
      },
    );
  }

  Widget _buildFollowingRailEmpty(
    BuildContext context, {
    required bool collapsed,
  }) {
    final query = _followingQueryController.text.trim();
    final hasQuery = query.isNotEmpty;
    return Padding(
      padding: EdgeInsets.all(collapsed ? 8 : 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasQuery ? Icons.search_off_rounded : Icons.people_alt_outlined,
            color: const Color(0x88FFFFFF),
            size: collapsed ? 28 : 36,
          ),
          if (!collapsed) ...[
            const SizedBox(height: 10),
            Text(
              hasQuery ? '没有匹配的关注 UP' : '还没有关注任何 UP 主',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 13),
            ),
          ],
          if (widget.followingHasMore) ...[
            SizedBox(height: collapsed ? 8 : 14),
            _TvFollowingRailLoadMore(
              collapsed: collapsed,
              loading: widget.followingLoadingMore,
              onFocused: () => _setRailCollapsed(false),
              onTap: () => hasQuery
                  ? unawaited(_submitFollowingSearch())
                  : unawaited(_loadMoreFollowing()),
            ),
          ] else ...[
            SizedBox(height: collapsed ? 8 : 14),
            _TvFollowingRailRefresh(
              icon: hasQuery ? Icons.close_rounded : Icons.refresh_rounded,
              debugLabel: hasQuery
                  ? 'tv_following_clear_search'
                  : 'tv_following_refresh',
              onFocused: () => _setRailCollapsed(false),
              onTap: () {
                if (hasQuery) {
                  _followingQueryController.clear();
                  _handleFollowingQueryChanged();
                } else {
                  unawaited(widget.onRefreshFollowing());
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmissionsPane(BuildContext context) {
    final selected = _selectedUser;
    if (selected == null) {
      return const _TvFollowingSpaceStatus(
        icon: Icons.arrow_back_rounded,
        title: '选择一位 UP 主',
        message: '从左侧关注列表选择后，可浏览该 UP 主的投稿视频。',
      );
    }
    final profile = _profile ?? BiliUserSpaceProfile.fromFollowing(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TvFollowingSpaceProfileHeader(
          profile: profile,
          loading: _spaceLoading && !_spaceLoaded,
          onFocused: () => _setRailCollapsed(true),
          onRefresh: () => unawaited(_reloadSelectedSpace()),
        ),
        const SizedBox(height: 14),
        _buildVideoSearch(context),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              _activeVideoKeyword.isEmpty ? '投稿视频' : '搜索结果',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            if (_spaceLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xAAFFFFFF),
                ),
              ),
            const Spacer(),
            if (_spaceError != null && !_spaceAuthenticationRequired)
              _TvFollowingSpaceRetryButton(
                onFocused: () => _setRailCollapsed(true),
                onTap: () => unawaited(_reloadSelectedSpace()),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildVideoBody()),
      ],
    );
  }

  Widget _buildVideoSearch(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: TextField(
        key: const ValueKey<String>('bili-tv-space-video-search'),
        controller: _videoQueryController,
        focusNode: _videoSearchFocusNode,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => unawaited(_searchVideos()),
        decoration: InputDecoration(
          hintText: '搜索当前 UP 的投稿标题或 BV 号',
          hintStyle: const TextStyle(color: Color(0x77FFFFFF)),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xAA409EFF),
          ),
          suffixIcon: _videoQueryController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  onPressed: () {
                    _videoQueryController.clear();
                    unawaited(_searchVideos());
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xBBFFFFFF),
                  ),
                ),
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildVideoBody() {
    if (_spaceLoading && !_spaceLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xAAFFFFFF)),
      );
    }
    if (_spaceAuthenticationRequired) {
      return _TvFollowingSpaceStatus(
        icon: Icons.lock_outline_rounded,
        title: '需要重新登录',
        message: _spaceError ?? '登录状态已失效，请重新登录后再试。',
        primaryLabel: widget.onLogin == null ? null : '登录',
        onPrimary: widget.onLogin == null
            ? null
            : () => unawaited(_loginAndReload()),
      );
    }
    if (_videos.isEmpty) {
      return _TvFollowingSpaceStatus(
        icon: _spaceError == null
            ? Icons.video_library_outlined
            : Icons.error_outline_rounded,
        title: _spaceError == null ? '没有匹配的视频' : '暂时无法显示投稿',
        message: _spaceError ?? '这个 UP 主还没有符合条件的投稿视频。',
        primaryLabel: _spaceError == null ? null : '重试',
        onPrimary: _spaceError == null
            ? null
            : () => unawaited(_reloadSelectedSpace()),
      );
    }
    return GridView.builder(
      key: const ValueKey<String>('bili-tv-space-video-grid'),
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _tvLibraryVideoMaxCrossAxisExtent,
        mainAxisSpacing: 22,
        crossAxisSpacing: 20,
        childAspectRatio: 1.03,
      ),
      itemCount: _videos.length + (_spaceHasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _videos.length) {
          return _TvLibraryLoadMoreTile(
            key: const ValueKey<String>('bili-tv-space-video-load-more'),
            loading: _spaceLoadingMore,
            onTap: () => unawaited(_loadMoreVideos()),
          );
        }
        final video = _videos[index];
        final subtitle = <String>[
          if (video.publishedAtLabel.isNotEmpty) video.publishedAtLabel,
          if (video.playCountLabel.isNotEmpty) '${video.playCountLabel} 播放',
        ].join(' · ');
        return _TvLibraryVideoCard(
          key: ValueKey<String>('bili-tv-space-video-${video.bvid}'),
          title: video.title,
          subtitle: subtitle,
          coverUrl: video.coverUrl,
          progressMs: 0,
          durationMs: 0,
          durationLabel: video.durationLabel,
          // The rail owns initial focus. Entering the submission area through
          // directional focus is what collapses it to avatars.
          autofocus: false,
          debugLabel: 'tv_space_video_${video.bvid}',
          onFocusChange: (focused) {
            if (focused) {
              _setRailCollapsed(true);
            }
          },
          onTap: () => widget.onOpenVideo(video),
        );
      },
    );
  }
}

class _TvFollowingRailUser extends StatelessWidget {
  const _TvFollowingRailUser({
    super.key,
    required this.user,
    required this.selected,
    required this.collapsed,
    required this.autofocus,
    required this.onFocused,
    required this.onTap,
  });

  final BiliFollowingUser user;
  final bool selected;
  final bool collapsed;
  final bool autofocus;
  final VoidCallback onFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatarCacheWidth = _tvLibraryCoverCacheWidth(context, 54);
    return SizedBox(
      height: collapsed ? 66 : 76,
      child: TvFocusableSurface(
        autofocus: autofocus,
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.035,
        borderRadius: collapsed ? 28 : 12,
        focusArea: TvFocusArea.rail,
        debugLabel: 'tv_following_user_${user.mid}',
        onFocusChange: (focused) {
          if (focused) {
            onFocused();
          }
        },
        onTap: onTap,
        builder: (context, focused) {
          return LayoutBuilder(
            builder: (context, constraints) {
              // AnimatedContainer can pass an intermediate narrow constraint
              // for one frame before descendants receive the new collapsed
              // widget configuration. Use the actual width as the tie-breaker.
              final compact = collapsed || constraints.maxWidth < 150;
              final highlighted = focused || selected;
              final avatar = ClipOval(
                child: SizedBox(
                  width: compact ? 50 : 48,
                  height: compact ? 50 : 48,
                  child: ColoredBox(
                    color: const Color(0xFF272833),
                    child: user.avatarUrl.isEmpty
                        ? const Icon(
                            Icons.person_outline_rounded,
                            color: Color(0x99FFFFFF),
                            size: 28,
                          )
                        : Image.network(
                            user.avatarUrl,
                            fit: BoxFit.cover,
                            cacheWidth: avatarCacheWidth,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.person_outline_rounded,
                              color: Color(0x99FFFFFF),
                              size: 28,
                            ),
                          ),
                  ),
                ),
              );
              return Tooltip(
                message: user.name,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: compact ? 8 : 9,
                  ),
                  decoration: BoxDecoration(
                    color: highlighted
                        ? Colors.white.withValues(alpha: focused ? 0.20 : 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(compact ? 28 : 12),
                    border: Border.all(
                      color: focused
                          ? AppVisualTokens.primaryBlue
                          : selected
                          ? Colors.white.withValues(alpha: 0.20)
                          : Colors.transparent,
                      width: focused ? 1.8 : 1,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        alignment: compact
                            ? Alignment.center
                            : Alignment.centerLeft,
                        child: avatar,
                      ),
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.only(left: 58),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: focused || selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'UID ${user.mid}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0x88FFFFFF),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TvFollowingRailLoadMore extends StatelessWidget {
  const _TvFollowingRailLoadMore({
    required this.collapsed,
    required this.loading,
    required this.onFocused,
    required this.onTap,
  });

  final bool collapsed;
  final bool loading;
  final VoidCallback onFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: collapsed ? 58 : 52,
      child: TvFocusableSurface(
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.04,
        borderRadius: 12,
        focusArea: TvFocusArea.rail,
        debugLabel: 'tv_following_load_more',
        onFocusChange: (focused) {
          if (focused) {
            onFocused();
          }
        },
        onTap: loading ? () {} : onTap,
        builder: (context, focused) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = collapsed || constraints.maxWidth < 150;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: focused
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xCCFFFFFF),
                          ),
                        )
                      : compact
                      ? const Icon(
                          Icons.expand_more_rounded,
                          color: Color(0xCCFFFFFF),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.expand_more_rounded,
                              color: Color(0xCCFFFFFF),
                            ),
                            SizedBox(width: 5),
                            Text(
                              '加载更多',
                              style: TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TvFollowingRailRefresh extends StatelessWidget {
  const _TvFollowingRailRefresh({
    required this.icon,
    required this.debugLabel,
    required this.onFocused,
    required this.onTap,
  });

  final IconData icon;
  final String debugLabel;
  final VoidCallback onFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TvFocusableSurface(
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.04,
        borderRadius: 10,
        focusArea: TvFocusArea.rail,
        debugLabel: debugLabel,
        onFocusChange: (focused) {
          if (focused) {
            onFocused();
          }
        },
        onTap: onTap,
        builder: (context, focused) => DecoratedBox(
          decoration: BoxDecoration(
            color: focused
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Icon(icon, color: const Color(0xCCFFFFFF))),
        ),
      ),
    );
  }
}

class _TvFollowingSpaceProfileHeader extends StatelessWidget {
  const _TvFollowingSpaceProfileHeader({
    required this.profile,
    required this.loading,
    required this.onFocused,
    required this.onRefresh,
  });

  final BiliUserSpaceProfile profile;
  final bool loading;
  final VoidCallback onFocused;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final avatarCacheWidth = _tvLibraryCoverCacheWidth(context, 68);
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 68,
              height: 68,
              child: ColoredBox(
                color: const Color(0xFF292A34),
                child: profile.avatarUrl.isEmpty
                    ? const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xAAFFFFFF),
                        size: 38,
                      )
                    : Image.network(
                        profile.avatarUrl,
                        fit: BoxFit.cover,
                        cacheWidth: avatarCacheWidth,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xAAFFFFFF),
                          size: 38,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'UID ${profile.mid}  ·  ${biliFormatCount(profile.archiveCount)} 投稿  ·  ${biliFormatCount(profile.followerCount)} 粉丝',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 13,
                  ),
                ),
                if (profile.sign.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.sign,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0x77FFFFFF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 46,
            height: 46,
            child: TvFocusableSurface(
              useOverlayLift: false,
              focusPadding: 0,
              scale: 1.05,
              borderRadius: 12,
              focusArea: TvFocusArea.content,
              debugLabel: 'tv_space_refresh',
              onFocusChange: (focused) {
                if (focused) {
                  onFocused();
                }
              },
              onTap: loading ? () {} : onRefresh,
              builder: (context, focused) => DecoratedBox(
                decoration: BoxDecoration(
                  color: focused
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xCCFFFFFF),
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvFollowingSpaceRetryButton extends StatelessWidget {
  const _TvFollowingSpaceRetryButton({
    required this.onFocused,
    required this.onTap,
  });

  final VoidCallback onFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 38,
      child: TvFocusableSurface(
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.04,
        borderRadius: 10,
        focusArea: TvFocusArea.content,
        debugLabel: 'tv_space_retry',
        onFocusChange: (focused) {
          if (focused) {
            onFocused();
          }
        },
        onTap: onTap,
        builder: (context, focused) => DecoratedBox(
          decoration: BoxDecoration(
            color: focused
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.refresh_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

class _TvFollowingSpaceStatus extends StatelessWidget {
  const _TvFollowingSpaceStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0x99FFFFFF), size: 42),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 14),
            ),
            if (primaryLabel != null && onPrimary != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 44,
                child: TvFocusableSurface(
                  useOverlayLift: false,
                  focusPadding: 0,
                  scale: 1.04,
                  borderRadius: 12,
                  focusArea: TvFocusArea.content,
                  debugLabel: 'tv_space_status_action_$primaryLabel',
                  onTap: onPrimary!,
                  builder: (context, focused) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: focused
                          ? AppVisualTokens.primaryBlue
                          : AppVisualTokens.primaryBlue.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        child: Text(
                          primaryLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
