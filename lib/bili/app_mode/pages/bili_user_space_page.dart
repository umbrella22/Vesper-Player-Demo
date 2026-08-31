import 'dart:async';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_page.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_text.dart';
import 'package:vesper_media/download/download.dart';

/// Mobile presentation of one followed UP's profile and archive list.
///
/// The page keeps account data request state local, while [BiliClient] owns
/// authentication gating, WBI signing and the network contracts. The same
/// profile/video models are also consumed by the TV following browser.
class BiliUserSpacePage extends StatefulWidget {
  const BiliUserSpacePage({
    super.key,
    required this.client,
    required this.user,
    this.historyStore,
    this.offlineController,
    this.onLoginTap,
  });

  final BiliClient client;
  final BiliFollowingUser user;
  final BiliHistoryStore? historyStore;
  final BiliOfflineDownloadController? offlineController;
  final Future<void> Function()? onLoginTap;

  @override
  State<BiliUserSpacePage> createState() => _BiliUserSpacePageState();
}

class _BiliUserSpacePageState extends State<BiliUserSpacePage> {
  static const _pageSize = 30;

  final TextEditingController _videoQueryController = TextEditingController();
  BiliUserSpaceProfile? _profile;
  List<BiliUserSpaceVideo> _videos = const <BiliUserSpaceVideo>[];
  String _activeKeyword = '';
  bool _loading = false;
  bool _loadingMore = false;
  bool _loaded = false;
  bool _hasMore = false;
  bool _authenticationRequired = false;
  bool _isExactBvidResult = false;
  int _page = 1;
  int _requestGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    _requestGeneration += 1;
    _videoQueryController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial({bool forceProfile = false}) async {
    if (!widget.client.hasAuthenticatedSession) {
      if (mounted) {
        setState(() {
          _authenticationRequired = true;
          _loaded = true;
          _loading = false;
          _videos = const <BiliUserSpaceVideo>[];
          _hasMore = false;
          _error = '请先登录 Bilibili 后查看 UP 主空间。';
        });
      }
      return;
    }

    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _authenticationRequired = false;
    });
    try {
      final profile = forceProfile || _profile == null
          ? await widget.client.fetchUserSpaceProfile(widget.user.mid)
          : _profile!;
      final page = await widget.client.fetchUserSpaceVideos(
        mid: widget.user.mid,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _profile = profile;
        _videos = page.videos;
        _activeKeyword = '';
        _page = page.page;
        _hasMore = page.hasMore;
        _isExactBvidResult = false;
        _loaded = true;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _authenticationRequired = _isAuthenticationError(error);
        _error = _spaceErrorMessage(error);
        if (_authenticationRequired) {
          _videos = const <BiliUserSpaceVideo>[];
          _hasMore = false;
        }
        _loaded = true;
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _searchVideos() async {
    final query = _videoQueryController.text.trim();
    if (!widget.client.hasAuthenticatedSession) {
      await _loadInitial();
      return;
    }

    final bvid = biliExtractBvid(query);
    if (bvid != null) {
      final local = _videos.where((item) => item.bvid == bvid).firstOrNull;
      if (local != null) {
        setState(() {
          _videos = <BiliUserSpaceVideo>[local];
          _activeKeyword = query;
          _hasMore = false;
          _isExactBvidResult = true;
          _error = null;
        });
        return;
      }
      await _searchExactBvid(query, bvid);
      return;
    }
    await _loadVideoPage(keyword: query, force: true);
  }

  Future<void> _searchExactBvid(String query, String bvid) async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _authenticationRequired = false;
    });
    try {
      final video = await widget.client.fetchUserSpaceVideoByBvid(
        mid: widget.user.mid,
        bvid: bvid,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _videos = video == null
            ? const <BiliUserSpaceVideo>[]
            : <BiliUserSpaceVideo>[video];
        _activeKeyword = query;
        _page = 1;
        _hasMore = false;
        _isExactBvidResult = true;
        _loaded = true;
        _error = video == null ? '该 BV 号不属于当前 UP 主。' : null;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _authenticationRequired = _isAuthenticationError(error);
        _error = _spaceErrorMessage(error);
        if (_authenticationRequired) {
          _videos = const <BiliUserSpaceVideo>[];
          _hasMore = false;
        }
        _loaded = true;
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadVideoPage({
    required String keyword,
    bool force = false,
  }) async {
    if (_loading || (!force && _loaded && keyword == _activeKeyword)) {
      return;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _authenticationRequired = false;
    });
    try {
      final page = await widget.client.fetchUserSpaceVideos(
        mid: widget.user.mid,
        pageSize: _pageSize,
        keyword: keyword,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _videos = page.videos;
        _activeKeyword = keyword;
        _page = page.page;
        _hasMore = page.hasMore;
        _isExactBvidResult = false;
        _loaded = true;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _authenticationRequired = _isAuthenticationError(error);
        _error = _spaceErrorMessage(error);
        if (_authenticationRequired) {
          _videos = const <BiliUserSpaceVideo>[];
          _hasMore = false;
        }
        _loaded = true;
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading ||
        _loadingMore ||
        !_loaded ||
        !_hasMore ||
        _isExactBvidResult ||
        !widget.client.hasAuthenticatedSession) {
      return;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final next = await widget.client.fetchUserSpaceVideos(
        mid: widget.user.mid,
        page: _page + 1,
        pageSize: _pageSize,
        keyword: _activeKeyword,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      final seen = _videos.map((item) => item.bvid).toSet();
      final unique = next.videos
          .where((item) => item.bvid.isNotEmpty && seen.add(item.bvid))
          .toList(growable: false);
      setState(() {
        _videos = <BiliUserSpaceVideo>[..._videos, ...unique];
        _page = next.page;
        _hasMore = next.hasMore && unique.isNotEmpty;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _authenticationRequired = _isAuthenticationError(error);
        _error = _spaceErrorMessage(error);
        if (_authenticationRequired) {
          _videos = const <BiliUserSpaceVideo>[];
          _hasMore = false;
        }
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _handleLogin() async {
    final onLoginTap = widget.onLoginTap;
    if (onLoginTap == null) {
      return;
    }
    await onLoginTap();
    if (mounted && widget.client.hasAuthenticatedSession) {
      await _loadInitial(forceProfile: true);
    }
  }

  Future<void> _openVideo(BiliUserSpaceVideo video) async {
    try {
      final detail = await widget.client.fetchVideoDetail(video.bvid);
      if (!mounted || detail.pages.isEmpty) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BiliPlaybackPage(
            detail: detail,
            initialPage: detail.pages.first,
            client: widget.client,
            historyStore: widget.historyStore ?? const BiliHistoryStore(),
            offlineController:
                widget.offlineController ??
                BiliOfflineDownloadController.instance,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('打开视频失败：${biliErrorMessage(error)}')),
          );
      }
    }
  }

  bool _isAuthenticationError(Object error) {
    return isBiliSessionInvalidError(error);
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
    final visualTheme = AppVisualTheme.of(context);
    final profile = _profile ?? BiliUserSpaceProfile.fromFollowing(widget.user);
    return AppGlassScaffold(
      backgroundColor: visualTheme.background,
      extendBody: false,
      appBarHeight: 52,
      appBar: GlassAppBar(
        centerTitle: false,
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('UP 主空间'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadInitial(forceProfile: true),
        child: _buildBody(context, profile),
      ),
    );
  }

  Widget _buildBody(BuildContext context, BiliUserSpaceProfile profile) {
    if (_loading && !_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _videos.isEmpty && _profile == null) {
      return _BiliUserSpaceStatus(
        icon: Icons.lock_outline_rounded,
        message: _error!,
        primaryLabel: _authenticationRequired && widget.onLoginTap != null
            ? '登录'
            : '重试',
        onPrimary: _authenticationRequired && widget.onLoginTap != null
            ? _handleLogin
            : () => _loadInitial(forceProfile: true),
      );
    }

    return ListView(
      key: const ValueKey<String>('bili-user-space-content'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _BiliUserSpaceProfileHeader(profile: profile),
        const SizedBox(height: 20),
        _buildVideoSearch(context),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              _activeKeyword.isEmpty ? '投稿视频' : '搜索结果',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            if (_loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (_error != null && !_authenticationRequired) ...[
          const SizedBox(height: 10),
          _BiliUserSpaceInlineError(message: _error!, onRetry: _searchVideos),
        ],
        if (_videos.isEmpty && !_loading) ...[
          const SizedBox(height: 52),
          _BiliUserSpaceEmpty(
            message: _activeKeyword.isEmpty ? '这个 UP 主还没有投稿。' : '没有匹配的视频。',
          ),
        ] else ...[
          const SizedBox(height: 10),
          for (final video in _videos) ...[
            _BiliUserSpaceVideoTile(
              video: video,
              onTap: () => _openVideo(video),
            ),
            const SizedBox(height: 8),
          ],
          if (_hasMore) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(_loadingMore ? '加载中' : '加载更多'),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildVideoSearch(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return TextField(
      key: const ValueKey<String>('bili-user-space-video-search'),
      controller: _videoQueryController,
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => unawaited(_searchVideos()),
      decoration: InputDecoration(
        hintText: '搜索投稿标题或 BV 号',
        prefixIcon: Icon(
          Icons.search_rounded,
          color: visualTheme.textSecondary,
        ),
        suffixIcon: _videoQueryController.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _videoQueryController.clear();
                  unawaited(_searchVideos());
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: visualTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
          borderSide: BorderSide(color: visualTheme.imageOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
          borderSide: BorderSide(color: visualTheme.imageOutline),
        ),
      ),
    );
  }
}

class _BiliUserSpaceProfileHeader extends StatelessWidget {
  const _BiliUserSpaceProfileHeader({required this.profile});

  final BiliUserSpaceProfile profile;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: visualTheme.surface,
      borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppVisualTokens.biliSourcePink.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.20
                    : 0.12,
              ),
              backgroundImage: profile.avatarUrl.isEmpty
                  ? null
                  : NetworkImage(profile.avatarUrl),
              child: profile.avatarUrl.isEmpty
                  ? const Icon(Icons.person_outline_rounded)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'UID ${profile.mid}',
                    style: TextStyle(color: visualTheme.textSecondary),
                  ),
                  if (profile.sign.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      profile.sign,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: visualTheme.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _BiliUserSpaceStat(
                        label: '投稿',
                        value: profile.archiveCount,
                      ),
                      _BiliUserSpaceStat(
                        label: '粉丝',
                        value: profile.followerCount,
                      ),
                      _BiliUserSpaceStat(
                        label: '关注',
                        value: profile.followingCount,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BiliUserSpaceStat extends StatelessWidget {
  const _BiliUserSpaceStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Text(
      '$label ${biliFormatCount(value)}',
      style: TextStyle(
        color: visualTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _BiliUserSpaceVideoTile extends StatelessWidget {
  const _BiliUserSpaceVideoTile({required this.video, required this.onTap});

  final BiliUserSpaceVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final subtitleParts = <String>[
      if (video.publishedAtLabel.isNotEmpty) video.publishedAtLabel,
      if (video.playCountLabel.isNotEmpty) '${video.playCountLabel} 播放',
    ];
    return Material(
      color: visualTheme.surface,
      borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 124,
                  height: 70,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      video.coverUrl.isEmpty
                          ? ColoredBox(color: visualTheme.surfaceRaised)
                          : Image.network(
                              video.coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  ColoredBox(color: visualTheme.surfaceRaised),
                            ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          color: Colors.black.withValues(alpha: 0.68),
                          child: Text(
                            video.durationLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: visualTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: visualTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BiliUserSpaceStatus extends StatelessWidget {
  const _BiliUserSpaceStatus({
    required this.icon,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final String message;
  final String primaryLabel;
  final Future<void> Function() onPrimary;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 72),
        Icon(icon, size: 44, color: AppVisualTokens.primaryBlue),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: visualTheme.textPrimary),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => unawaited(onPrimary()),
          child: Text(primaryLabel),
        ),
      ],
    );
  }
}

class _BiliUserSpaceInlineError extends StatelessWidget {
  const _BiliUserSpaceInlineError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: visualTheme.destructive.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: visualTheme.destructive),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
            IconButton(
              tooltip: '重试',
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _BiliUserSpaceEmpty extends StatelessWidget {
  const _BiliUserSpaceEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Column(
      children: [
        Icon(
          Icons.video_library_outlined,
          size: 42,
          color: visualTheme.textTertiary,
        ),
        const SizedBox(height: 10),
        Text(message, style: TextStyle(color: visualTheme.textSecondary)),
      ],
    );
  }
}
