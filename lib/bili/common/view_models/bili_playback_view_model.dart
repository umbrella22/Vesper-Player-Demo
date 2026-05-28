import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';

import 'package:bilibili_player/download/services/offline_download_controller.dart';
import '../../../player/player_sdk_options.dart';
import '../models/bili_models.dart';
import '../services/bili_client.dart';
import '../services/bili_history_store.dart';
import '../services/bili_text.dart';
import 'bili_external_playback_manager.dart';

enum BiliEngagementAction { like, favorite, share, follow }

enum BiliCodecStrategy {
  defaultStrategy('默认'),
  av1('AV1'),
  hevc('HEVC'),
  avc('AVC');

  const BiliCodecStrategy(this.label);

  final String label;
}

final class BiliPlaybackViewModel extends ChangeNotifier {
  BiliPlaybackViewModel({
    required this.detail,
    required BiliVideoPageEntry initialPage,
    required this.client,
    required this.historyStore,
    BiliOfflineDownloadController? offlineController,
    BiliResolvedPlayback? initialResolvedPlayback,
  }) : offlineController =
           offlineController ?? BiliOfflineDownloadController.instance,
       _selectedPage = initialPage,
       _shareCountLabel = detail.shareCountLabel,
       _initialResolvedPlayback = initialResolvedPlayback {
    _dlnaManager = BiliExternalPlaybackManager(detail: detail)
      ..setOnChanged(_notify);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _castEventsSubscription = _externalPlaybackForCast.events.listen(
        _handleExternalPlaybackEvent,
      );
    }
    _controllerFuture = _createController();
    unawaited(loadEngagementState());
  }

  final BiliVideoDetail detail;
  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliOfflineDownloadController offlineController;
  final BiliResolvedPlayback? _initialResolvedPlayback;
  final VesperExternalPlaybackController _externalPlaybackForCast =
      VesperExternalPlaybackController();

  late Future<VesperPlayerController> _controllerFuture;
  VesperPlayerController? _controller;
  BiliVideoPageEntry _selectedPage;
  String _shareCountLabel;
  BiliResolvedPlayback? _resolvedPlayback;
  BiliVideoEngagement? _engagement;
  bool _engagementLoading = false;
  BiliEngagementAction? _pendingEngagementAction;
  int? _selectedBiliQualityId;
  BiliCodecStrategy _selectedCodecStrategy = BiliCodecStrategy.defaultStrategy;
  VesperSystemPlaybackPermissionStatus _systemPlaybackPermissionStatus =
      VesperSystemPlaybackPermissionStatus.notRequired;
  String? _castMessage;
  String? _pendingMessage;
  bool _castPausedLocalPlayback = false;
  bool _isFullscreen = false;
  bool _isDisposed = false;
  StreamSubscription<VesperExternalPlaybackSessionEvent>?
  _castEventsSubscription;
  late final BiliExternalPlaybackManager _dlnaManager;

  Future<VesperPlayerController> get controllerFuture => _controllerFuture;

  VesperPlayerController? get controller => _controller;

  BiliVideoPageEntry get selectedPage => _selectedPage;

  String get shareCountLabel => _shareCountLabel;

  BiliResolvedPlayback? get resolvedPlayback => _resolvedPlayback;

  BiliVideoEngagement? get engagement => _engagement;

  bool get engagementLoading => _engagementLoading;

  BiliEngagementAction? get pendingEngagementAction => _pendingEngagementAction;

  int? get selectedBiliQualityId => _selectedBiliQualityId;

  BiliCodecStrategy get selectedCodecStrategy => _selectedCodecStrategy;

  VesperSystemPlaybackPermissionStatus get systemPlaybackPermissionStatus =>
      _systemPlaybackPermissionStatus;

  String? get castMessage => _castMessage;

  BiliDlnaState get dlnaState => _dlnaManager.state;

  List<VesperExternalPlaybackRoute> get dlnaRoutes => _dlnaManager.routes;

  String? get dlnaMessage => _dlnaManager.message;

  BiliExternalPlaybackManager get dlnaManager => _dlnaManager;

  bool get isFullscreen => _isFullscreen;

  String get ownerSubtitle {
    if (detail.ownerMid <= 0 && detail.ownerName == '番剧') {
      return detail.pages.length > 1 ? '${detail.pages.length} 话/集' : '番剧';
    }
    final parts = <String>[
      'UP 主',
      if (detail.pages.length > 1) '${detail.pages.length} 个分 P',
    ];
    return parts.join(' · ');
  }

  String get videoMetaLine {
    final parts = <String>[
      if (detail.playCountLabel != '--') '${detail.playCountLabel}播放',
      if (detail.publishedAtLabel != null) detail.publishedAtLabel!,
      'P${_selectedPage.pageNumber}',
    ];
    return parts.isEmpty ? 'P${_selectedPage.pageNumber}' : parts.join(' · ');
  }

  String? consumePendingMessage() {
    final message = _pendingMessage;
    _pendingMessage = null;
    return message;
  }

  void setFullscreen(bool value) {
    if (_isFullscreen == value) {
      return;
    }
    _isFullscreen = value;
    _notify();
  }

  Future<VesperPlayerController> _createController() async {
    VesperPlayerController? nextController;
    try {
      final initialResolved = _initialResolvedPlayback;
      final resolved =
          initialResolved != null && initialResolved.cid == _selectedPage.cid
          ? initialResolved
          : await client.resolvePlayback(
              detail: detail,
              page: _selectedPage,
              platform: defaultTargetPlatform,
            );
      _resolvedPlayback = resolved;
      _notify();

      nextController = await VesperPlayerController.create(
        initialSource: resolved.toSource(),
        resiliencePolicy: biliPlayerResiliencePolicy,
        trackPreferencePolicy: biliPlayerTrackPreferencePolicy,
        preloadBudgetPolicy: biliPlayerPreloadBudgetPolicy,
        benchmarkConfiguration: biliPlayerBenchmarkConfiguration(),
      );
      await nextController.initialize();
      await _configureSystemPlayback(nextController, resolved);
      await nextController.play();

      if (_isDisposed) {
        await nextController.dispose();
      } else {
        _controller = nextController;
        _notify();
      }
      return nextController;
    } catch (_) {
      if (nextController != null) {
        await nextController.dispose();
      }
      rethrow;
    }
  }

  Future<void> reloadCurrentPage() async {
    final previous = _controller;
    final previousSnapshot = previous?.snapshot;
    _controller = null;
    if (previous != null && previousSnapshot != null) {
      await _persistLatestHistory(previous, fallback: previousSnapshot);
    }
    if (previous != null) {
      await _disposeController(previous);
    }
    if (_isDisposed) {
      return;
    }
    _controllerFuture = _createController();
    _notify();
  }

  Future<void> loadEngagementState() async {
    if (_engagementLoading) {
      return;
    }
    _engagementLoading = true;
    _notify();
    try {
      _engagement = await client.fetchVideoEngagement(detail);
    } catch (_) {
      // Engagement is optional for guests and can fail independently of playback.
    } finally {
      _engagementLoading = false;
      _notify();
    }
  }

  Future<String?> toggleLike() {
    return _runEngagementAction(BiliEngagementAction.like, () async {
      final current = _engagement ?? await client.fetchVideoEngagement(detail);
      final nextLiked = !current.isLiked;
      _engagement = await client.setVideoLike(
        detail: detail,
        liked: nextLiked,
        current: current,
      );
      return _engagement!.isLiked ? '已点赞' : '已取消点赞';
    });
  }

  Future<String?> toggleFavorite() {
    return _runEngagementAction(BiliEngagementAction.favorite, () async {
      final current = _engagement ?? await client.fetchVideoEngagement(detail);
      final nextFavorited = !current.isFavorited;
      _engagement = await client.setVideoFavorite(
        detail: detail,
        favorited: nextFavorited,
        current: current,
      );
      return _engagement!.isFavorited ? '已收藏' : '已取消收藏';
    });
  }

  Future<String?> toggleFollow() {
    return _runEngagementAction(BiliEngagementAction.follow, () async {
      final current = _engagement ?? await client.fetchVideoEngagement(detail);
      final nextFollowing = !current.isFollowingOwner;
      _engagement = await client.setOwnerFollow(
        detail: detail,
        following: nextFollowing,
        current: current,
      );
      return _engagement!.isFollowingOwner ? '已关注 UP 主' : '已取消关注';
    });
  }

  Future<String?> shareVideo() {
    return _runEngagementAction(BiliEngagementAction.share, () async {
      final shouldRecordShare = client.hasAuthenticatedSession;
      final shareCount = shouldRecordShare
          ? await client.recordVideoShare(detail: detail)
          : null;
      await Clipboard.setData(
        ClipboardData(
          text:
              'https://www.bilibili.com/video/${_selectedPage.bvid ?? detail.bvid}',
        ),
      );
      if (shareCount != null) {
        _shareCountLabel = biliFormatCount(shareCount.toDouble());
      }
      return shouldRecordShare ? '已分享并复制链接' : '已复制分享链接';
    });
  }

  Future<String?> _runEngagementAction(
    BiliEngagementAction action,
    Future<String?> Function() operation,
  ) async {
    if (_pendingEngagementAction != null) {
      return null;
    }
    _pendingEngagementAction = action;
    _notify();
    try {
      return await operation();
    } catch (error) {
      return '操作失败：$error';
    } finally {
      _pendingEngagementAction = null;
      _notify();
    }
  }

  Future<String?> switchPage(BiliVideoPageEntry page) async {
    final controller = _controller;
    if (controller == null || page.cid == _selectedPage.cid) {
      return null;
    }

    final currentSnapshot = controller.snapshot;
    await _persistLatestHistory(controller, fallback: currentSnapshot);

    try {
      final resolved = await client.resolvePlayback(
        detail: detail,
        page: page,
        platform: defaultTargetPlatform,
      );
      await controller.selectSource(resolved.toSource());
      await _configureSystemPlayback(controller, resolved);
      await controller.play();
      if (_isDisposed) {
        return null;
      }
      _selectedPage = page;
      _resolvedPlayback = resolved;
      _selectedBiliQualityId = null;
      _selectedCodecStrategy = BiliCodecStrategy.defaultStrategy;
      _notify();
      return null;
    } catch (error) {
      return '切换分 P 失败：$error';
    }
  }

  Future<String?> loadCurrentPageToDlna() async {
    try {
      final resolved = await _refreshCurrentResolvedPlayback();
      return _dlnaManager.loadMedia(
        resolved: resolved,
        selectedPage: _selectedPage,
        refreshResolved: _refreshCurrentResolvedPlayback,
      );
    } catch (error) {
      return '投屏播放地址刷新失败：$error';
    }
  }

  Future<BiliResolvedPlayback> _refreshCurrentResolvedPlayback() async {
    final resolved = await client.resolvePlayback(
      detail: detail,
      page: _selectedPage,
      platform: defaultTargetPlatform,
    );
    if (!_isDisposed) {
      _resolvedPlayback = resolved;
      _notify();
    }
    return resolved;
  }

  Future<void> _disposeController(VesperPlayerController controller) async {
    try {
      await controller.clearSystemPlayback();
    } catch (_) {
      // System playback is optional and may already be unavailable during tear-down.
    }
    await controller.dispose();
  }

  Future<void> _configureSystemPlayback(
    VesperPlayerController controller,
    BiliResolvedPlayback resolved,
  ) async {
    try {
      _systemPlaybackPermissionStatus = await controller
          .getSystemPlaybackPermissionStatus();
      _notify();
      await controller.configureSystemPlayback(
        biliPlayerSystemPlaybackConfiguration(
          metadata: _systemPlaybackMetadataForResolved(resolved),
        ),
      );
    } catch (error) {
      if (!_isDisposed) {
        _emitMessage('系统播放接入失败：$error');
      }
    }
  }

  Future<String?> requestSystemPlaybackPermissions(
    VesperPlayerController controller,
  ) async {
    try {
      _systemPlaybackPermissionStatus = await controller
          .requestSystemPlaybackPermissions();
      _notify();
      return null;
    } catch (error) {
      return '系统播放权限请求失败：$error';
    }
  }

  Future<void> _handleExternalPlaybackEvent(
    VesperExternalPlaybackSessionEvent event,
  ) async {
    final controller = _controller;
    final resolved = _resolvedPlayback;
    if (controller == null || resolved == null || _isDisposed) {
      return;
    }

    if (event.routeId != VesperExternalPlaybackController.castRouteId) {
      return;
    }

    switch (event.kind) {
      case VesperExternalPlaybackSessionEventKind.routeConnected:
        final result = await _externalPlaybackForCast.loadFromPlayer(
          player: controller,
          source: resolved.toSource(),
          metadata: _systemPlaybackMetadataForResolved(resolved),
        );
        if (_isDisposed) return;
        _castPausedLocalPlayback = result.isSuccess;
        _castMessage = result.isSuccess
            ? '投屏已连接：${event.routeName ?? '外部设备'}'
            : result.message ?? '当前资源暂不支持投屏。';
        _notify();
      case VesperExternalPlaybackSessionEventKind.routeDisconnected:
        if (_castPausedLocalPlayback) {
          final positionMs = event.positionMs;
          if (positionMs != null) {
            final deltaMs =
                positionMs - controller.snapshot.timeline.positionMs;
            await controller.seekBy(deltaMs);
          }
          await controller.play();
        }
        if (_isDisposed) return;
        _castPausedLocalPlayback = false;
        _castMessage = '投屏已断开，本地播放已恢复。';
        _notify();
      case VesperExternalPlaybackSessionEventKind.suspended:
        if (_isDisposed) return;
        _castMessage = '投屏连接已暂停。';
        _notify();
      default:
    }
  }

  VesperSystemPlaybackMetadata _systemPlaybackMetadataForResolved(
    BiliResolvedPlayback resolved,
  ) {
    final resolvedPage = _pageForResolvedPlayback(resolved);
    final durationSeconds = resolvedPage?.durationSeconds ?? 0;
    final durationMs = durationSeconds > 0 ? durationSeconds * 1000 : null;
    return biliPlayerSystemPlaybackMetadata(
      title: resolved.title,
      subtitle: resolved.subtitle,
      artist: detail.ownerName,
      artworkUri: _selectedPage.coverUrl ?? detail.coverUrl,
      contentUri: resolved.uri,
      durationMs: durationMs,
    );
  }

  BiliVideoPageEntry? _pageForResolvedPlayback(BiliResolvedPlayback resolved) {
    for (final page in detail.pages) {
      if (page.cid == resolved.cid) {
        return page;
      }
    }
    return null;
  }

  Future<void> _persistHistory(VesperPlayerSnapshot snapshot) {
    return historyStore.saveEntry(
      BiliPlaybackHistoryEntry(
        bvid: _selectedPage.bvid ?? detail.bvid,
        cid: _selectedPage.cid,
        videoTitle: detail.title,
        pageTitle: _selectedPage.title,
        coverUrl: _selectedPage.coverUrl ?? detail.coverUrl,
        ownerName: detail.ownerName,
        playedAtMs: DateTime.now().millisecondsSinceEpoch,
        lastPositionMs: snapshot.timeline.positionMs,
        durationMs: snapshot.timeline.durationMs,
      ),
    );
  }

  Future<void> _persistLatestHistory(
    VesperPlayerController controller, {
    required VesperPlayerSnapshot fallback,
  }) async {
    var snapshot = fallback;
    try {
      await controller.refresh();
      snapshot = controller.snapshot;
    } catch (_) {
      snapshot = fallback;
    }
    await _persistHistory(snapshot);
  }

  Future<String?> setPlaybackRate(double rate) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    try {
      await controller.setPlaybackRate(rate);
      return null;
    } catch (error) {
      return '倍速切换失败：$error';
    }
  }

  Future<String?> selectBiliQuality(int? qualityId) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final tracks = playbackSelectionTracks(controller.snapshot);
    var nextStrategy = _selectedCodecStrategy;
    String? message;
    if (qualityId != null &&
        nextStrategy != BiliCodecStrategy.defaultStrategy &&
        !hasTrackForSelection(tracks, qualityId, nextStrategy)) {
      message = '当前清晰度没有 ${_selectedCodecStrategy.label}，已使用默认策略。';
      nextStrategy = BiliCodecStrategy.defaultStrategy;
    }

    _selectedBiliQualityId = qualityId;
    _selectedCodecStrategy = nextStrategy;
    _notify();
    return await applyBiliPlaybackSelection() ?? message;
  }

  Future<String?> selectCodecStrategy(BiliCodecStrategy strategy) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final tracks = playbackSelectionTracks(controller.snapshot);
    if (strategy != BiliCodecStrategy.defaultStrategy &&
        !hasTrackForSelection(tracks, _selectedBiliQualityId, strategy)) {
      return '当前分辨率没有 ${strategy.label} 策略。';
    }

    _selectedCodecStrategy = strategy;
    _notify();
    return applyBiliPlaybackSelection();
  }

  Future<String?> applyBiliPlaybackSelection() async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    try {
      if (_selectedBiliQualityId == null &&
          _selectedCodecStrategy == BiliCodecStrategy.defaultStrategy) {
        await controller.setAbrPolicy(const VesperAbrPolicy.auto());
        return null;
      }

      final snapshot = controller.snapshot;
      final track = _selectBestTrackForPlaybackSelection(snapshot);
      if (track == null) {
        return '当前视频没有可用的清晰度轨道。';
      }
      if (_hasNativeVideoTrack(snapshot, track.id)) {
        await controller.setAbrPolicy(VesperAbrPolicy.fixedTrack(track.id));
        return null;
      }

      final bitRate = track.bitRate;
      if (snapshot.capabilities.supportsAbrConstrained &&
          bitRate != null &&
          bitRate > 0) {
        await controller.setAbrPolicy(
          VesperAbrPolicy.constrained(maxBitRate: bitRate),
        );
        return null;
      }

      await controller.setAbrPolicy(VesperAbrPolicy.fixedTrack(track.id));
      return null;
    } catch (error) {
      return '清晰度切换失败：$error';
    }
  }

  List<double> playbackRates(VesperPlayerSnapshot snapshot) {
    final rates = <double>{
      1.0,
      1.25,
      1.5,
      2.0,
      snapshot.playbackRate,
      ...snapshot.capabilities.supportedPlaybackRates,
    };
    final normalized = rates.where((value) => value > 0).toList()..sort();
    return normalized;
  }

  List<VesperMediaTrack> playbackSelectionTracks(
    VesperPlayerSnapshot snapshot,
  ) {
    final nativeTracks = snapshot.trackCatalog.videoTracks;
    if (_availableBiliQualityIds(nativeTracks).isNotEmpty) {
      return nativeTracks;
    }

    final manifestTracks =
        _resolvedPlayback?.videoTracks ?? const <VesperMediaTrack>[];
    if (manifestTracks.isNotEmpty) {
      return manifestTracks;
    }

    return nativeTracks;
  }

  List<int> availableBiliQualityIds(List<VesperMediaTrack> tracks) {
    return _availableBiliQualityIds(tracks);
  }

  bool hasTrackForSelection(
    List<VesperMediaTrack> tracks,
    int? qualityId,
    BiliCodecStrategy strategy,
  ) {
    return tracks.any((track) {
      if (qualityId != null && _biliQualityIdForTrack(track) != qualityId) {
        return false;
      }
      return _codecStrategyForTrack(track) == strategy;
    });
  }

  BiliVideoCodecPreference currentDownloadCodecPreference() {
    return switch (_selectedCodecStrategy) {
      BiliCodecStrategy.defaultStrategy => BiliVideoCodecPreference.automatic,
      BiliCodecStrategy.av1 => BiliVideoCodecPreference.av1,
      BiliCodecStrategy.hevc => BiliVideoCodecPreference.hevc,
      BiliCodecStrategy.avc => BiliVideoCodecPreference.avc,
    };
  }

  String playbackStateLabel(VesperPlayerSnapshot snapshot) {
    return switch (snapshot.playbackState) {
      VesperPlaybackState.ready => '就绪',
      VesperPlaybackState.playing => '播放中',
      VesperPlaybackState.paused => '已暂停',
      VesperPlaybackState.finished => '已结束',
    };
  }

  String? biliQualityLabelFromQualityId(int qualityId) {
    return switch (qualityId) {
      127 => '8K 超高清',
      126 => '杜比视界',
      125 => 'HDR 真彩',
      120 => '4K 超清',
      116 => '1080P60',
      112 => '1080P 高码率',
      80 => '1080P',
      74 => '720P60',
      64 => '720P',
      32 => '480P',
      16 => '360P',
      6 => '240P',
      _ => null,
    };
  }

  int? biliQualityIdForTrack(VesperMediaTrack track) {
    return _biliQualityIdForTrack(track);
  }

  bool _hasNativeVideoTrack(VesperPlayerSnapshot snapshot, String trackId) {
    return snapshot.trackCatalog.videoTracks.any(
      (track) => track.id == trackId,
    );
  }

  VesperMediaTrack? _selectBestTrackForPlaybackSelection(
    VesperPlayerSnapshot snapshot,
  ) {
    final tracks = _sortedVideoTracks(playbackSelectionTracks(snapshot));
    Iterable<VesperMediaTrack> candidates = tracks;
    final selectedQualityId = _selectedBiliQualityId;
    if (selectedQualityId != null) {
      candidates = candidates.where(
        (track) => _biliQualityIdForTrack(track) == selectedQualityId,
      );
    }

    final strategy = _selectedCodecStrategy;
    if (strategy != BiliCodecStrategy.defaultStrategy) {
      final strategyMatches = candidates
          .where((track) => _codecStrategyForTrack(track) == strategy)
          .toList(growable: false);
      if (strategyMatches.isNotEmpty) {
        return strategyMatches.first;
      }
    }

    for (final candidate in candidates) {
      return candidate;
    }
    return null;
  }

  List<int> _availableBiliQualityIds(List<VesperMediaTrack> tracks) {
    final qualityIds = <int>{};
    for (final track in tracks) {
      final qualityId = _biliQualityIdForTrack(track);
      if (qualityId != null) {
        qualityIds.add(qualityId);
      }
    }
    final sorted = qualityIds.toList();
    sorted.sort(
      (left, right) =>
          _biliQualityRank(right).compareTo(_biliQualityRank(left)),
    );
    return sorted;
  }

  int _biliQualityRank(int qualityId) {
    return switch (qualityId) {
      127 => 1200,
      126 => 1190,
      125 => 1180,
      120 => 1100,
      116 => 1000,
      112 => 990,
      80 => 900,
      74 => 800,
      64 => 700,
      32 => 600,
      16 => 500,
      6 => 400,
      _ => qualityId,
    };
  }

  List<VesperMediaTrack> _sortedVideoTracks(List<VesperMediaTrack> tracks) {
    final sorted = List<VesperMediaTrack>.of(tracks);
    sorted.sort((left, right) {
      final qualityCompare = (_biliQualityIdForTrack(right) ?? 0).compareTo(
        _biliQualityIdForTrack(left) ?? 0,
      );
      if (qualityCompare != 0) {
        return qualityCompare;
      }

      final heightCompare = (right.height ?? 0).compareTo(left.height ?? 0);
      if (heightCompare != 0) {
        return heightCompare;
      }

      final bitRateCompare = (right.bitRate ?? 0).compareTo(left.bitRate ?? 0);
      if (bitRateCompare != 0) {
        return bitRateCompare;
      }

      return _videoTrackLabel(left).compareTo(_videoTrackLabel(right));
    });
    return sorted;
  }

  BiliCodecStrategy? _codecStrategyForTrack(VesperMediaTrack track) {
    final codec = track.codec?.toLowerCase() ?? '';
    if (codec.contains('av01')) {
      return BiliCodecStrategy.av1;
    }
    if (codec.contains('hev1') ||
        codec.contains('hvc1') ||
        codec.contains('dvh1') ||
        codec.contains('dvhe')) {
      return BiliCodecStrategy.hevc;
    }
    if (codec.contains('avc1')) {
      return BiliCodecStrategy.avc;
    }

    final codecId = _biliCodecIdFromTrackId(track.id);
    return switch (codecId) {
      13 => BiliCodecStrategy.av1,
      12 => BiliCodecStrategy.hevc,
      7 => BiliCodecStrategy.avc,
      _ => null,
    };
  }

  String _videoTrackLabel(VesperMediaTrack track) {
    final parts = <String>[];
    final biliQualityLabel = _biliQualityLabelFromTrack(track);
    if (biliQualityLabel != null) {
      parts.add(biliQualityLabel);
    } else if (track.label != null && track.label!.trim().isNotEmpty) {
      parts.add(track.label!.trim());
    } else if (track.width != null && track.height != null) {
      parts.add('${track.width}x${track.height}');
    } else if (track.height != null) {
      parts.add('${track.height}p');
    }
    final codecLabel = _codecLabel(track.codec);
    if (codecLabel != null) {
      parts.add(codecLabel);
    }
    if (track.frameRate != null && track.frameRate! >= 50) {
      parts.add('${track.frameRate!.round()}fps');
    }
    if (track.bitRate != null) {
      parts.add('${(track.bitRate! / 1000).round()} kbps');
    }
    return parts.isEmpty ? track.id : parts.join(' · ');
  }

  String? _biliQualityLabelFromTrack(VesperMediaTrack track) {
    final qualityId = _biliQualityIdForTrack(track);
    return qualityId == null ? null : biliQualityLabelFromQualityId(qualityId);
  }

  int? _biliQualityIdForTrack(VesperMediaTrack track) {
    return _biliQualityIdFromTrackId(track.id) ??
        _biliQualityIdFromTrackLabel(track.label) ??
        _biliQualityIdFromTrackShape(track);
  }

  int? _biliQualityIdFromTrackId(String trackId) {
    final match = RegExp(r'^video-(\d+)-').firstMatch(trackId);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    final nestedMatch = RegExp(r':video-(\d+)-').firstMatch(trackId);
    if (nestedMatch != null) {
      return int.tryParse(nestedMatch.group(1)!);
    }
    return int.tryParse(trackId);
  }

  int? _biliQualityIdFromTrackLabel(String? label) {
    final value = label?.toLowerCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.contains('8k')) {
      return 127;
    }
    if (value.contains('4k') || value.contains('2160')) {
      return 120;
    }
    if (value.contains('1080') && value.contains('60')) {
      return 116;
    }
    if (value.contains('1080')) {
      return 80;
    }
    if (value.contains('720') && value.contains('60')) {
      return 74;
    }
    if (value.contains('720')) {
      return 64;
    }
    if (value.contains('480')) {
      return 32;
    }
    if (value.contains('360')) {
      return 16;
    }
    if (value.contains('240')) {
      return 6;
    }
    return null;
  }

  int? _biliQualityIdFromTrackShape(VesperMediaTrack track) {
    final height = track.height;
    if (height == null || height <= 0) {
      return null;
    }

    final frameRate = track.frameRate ?? 0;
    if (height >= 4320) {
      return 127;
    }
    if (height >= 2160) {
      return 120;
    }
    if (height >= 1080) {
      return frameRate >= 50 ? 116 : 80;
    }
    if (height >= 720) {
      return frameRate >= 50 ? 74 : 64;
    }
    if (height >= 480) {
      return 32;
    }
    if (height >= 360) {
      return 16;
    }
    return 6;
  }

  int? _biliCodecIdFromTrackId(String trackId) {
    final match = RegExp(r'(?:^|:)video-\d+-(\d+)-').firstMatch(trackId);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  String? _codecLabel(String? codec) {
    final value = codec?.toLowerCase() ?? '';
    if (value.contains('dvh1') || value.contains('dvhe')) {
      return 'Dolby Vision';
    }
    if (value.contains('av01')) {
      return 'AV1';
    }
    if (value.contains('hev1') || value.contains('hvc1')) {
      return 'HEVC';
    }
    if (value.contains('avc1')) {
      return 'AVC';
    }
    return null;
  }

  void _emitMessage(String message) {
    _pendingMessage = message;
    _notify();
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    final controller = _controller;
    final snapshot = controller?.snapshot;
    if (controller != null && snapshot != null) {
      unawaited(_persistLatestHistory(controller, fallback: snapshot));
    }
    unawaited(_castEventsSubscription?.cancel() ?? Future<void>.value());
    _dlnaManager.dispose();
    _controller = null;
    if (controller != null) {
      unawaited(_disposeController(controller));
    }
    super.dispose();
  }
}
