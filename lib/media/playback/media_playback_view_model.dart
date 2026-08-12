import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';

import '../adapter/media_platform_adapter.dart';
import '../capabilities/media_history.dart';
import '../models/media_detail.dart';
import '../models/media_playback_notice.dart';
import '../models/resolved_media.dart';
import '../player/media_text.dart';
import '../player/player_options.dart';
import 'media_external_playback_manager.dart';

part 'media_playback_view_model_controller.dart';
part 'media_playback_view_model_recovery.dart';
part 'media_playback_view_model_tracks.dart';
part 'media_playback_seek_aware_controller.dart';

/// 过时代际的播放器创建被取消（reload/dispose 后旧创建链才完成）。
final class _PlaybackSourceObsoleted implements Exception {
  const _PlaybackSourceObsoleted();
}

final class _TrackSelectionAvailability {
  const _TrackSelectionAvailability({
    required this.availability,
    required this.declaredTracks,
    required this.candidateTracks,
    this.unavailableReason,
  });

  final MediaQualityAvailability availability;
  final List<VesperMediaTrack> declaredTracks;
  final List<VesperMediaTrack> candidateTracks;
  final VesperTrackSupportReason? unavailableReason;
}

/// 通用播放编排：控制器生命周期、解析/恢复、清晰度/倍速/字幕、DLNA、
/// 系统播放与历史。
///
/// 平台差异全部收敛在 [MediaPlatformAdapter]：
/// - 解析：`adapter.resolvePlayback(detail, entry)`
/// - 清晰度：`resolved.qualityOptions` + `adapter.qualityPolicy`
/// - DLNA 格式适配：`adapter.dlnaConfig`
/// - 历史：`adapter.history`（可选，缺省不记录）
final class MediaPlaybackViewModel {
  MediaPlaybackViewModel({
    required MediaDetail detail,
    required MediaPlaybackEntry initialEntry,
    required MediaPlatformAdapter adapter,
    MediaHistoryStore? historyStore,
    this._initialResolvedPlayback,
    int initialPositionMs = 0,
    Future<bool> Function()? preferTextureViewForPlayback,
  }) : detail = detail,
       adapter = adapter,
       historyStore = historyStore ?? adapter.history,
       _selectedEntry = signal(initialEntry),
       _pendingInitialPositionMs = initialPositionMs > 0
           ? initialPositionMs
           : null,
       _preferTextureViewForPlayback =
           preferTextureViewForPlayback ?? _defaultPreferTextureView {
    _dlnaManager = MediaExternalPlaybackManager(
      detail: detail,
      formatAdaptation: adapter.dlnaConfig?.formatAdaptation,
    )..addListener(_handleDlnaChanged);
    _handleDlnaChanged();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _castEventsSubscription = _externalPlaybackForCast.events.listen(
        _handleExternalPlaybackEvent,
        onError: (Object _) {},
      );
    }
    // 未显式指定初始位置时，播放创建完成后从历史存储异步续播
    // （见 _applyHistoryResume）；这里无需预启动查询。
    _controllerFuture = signal(_trackControllerFuture(_createController()));
  }

  static Future<bool> _defaultPreferTextureView() async => false;

  /// 历史续播是否已应用（仅首次创建消费一次）。
  bool _historyResumeApplied = false;

  /// 切源代际：switchEntry 的 selectSource 前递增，使在途历史续播失效。
  int _sourceGeneration = 0;

  /// 用户操作代际：经 VM 的 seek 入口（seekToRatio/seekBy）时递增，
  /// 使在途历史续播失效。
  int _userSeekGeneration = 0;

  final MediaDetail detail;
  final MediaPlatformAdapter adapter;

  /// 历史存储：显式注入优先，缺省回退到 [MediaPlatformAdapter.history]。
  /// 未声明该能力的平台不记录观看历史。
  final MediaHistoryStore? historyStore;

  final VesperExternalPlaybackController _externalPlaybackForCast =
      VesperExternalPlaybackController();
  static const int _maxPlaybackRecoveryAttempts = 3;
  static const List<Duration> _playbackRecoveryBackoff = <Duration>[
    Duration.zero,
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ];
  static const Duration _playbackRecoverySuccessWindow = Duration(seconds: 5);

  late final Signal<Future<VesperPlayerController>> _controllerFuture;
  VesperPlayerController? _controller;

  /// 对外暴露的控制器：seek 感知代理（stage 手势 seek 使在途历史续播失效）。
  VesperPlayerController? _userController;
  int? _pendingInitialPositionMs;
  ResolvedMediaPlayback? _initialResolvedPlayback;
  final Future<bool> Function() _preferTextureViewForPlayback;
  late final Signal<MediaPlaybackEntry> _selectedEntry;
  final Signal<ResolvedMediaPlayback?> _resolvedPlayback =
      Signal<ResolvedMediaPlayback?>(null);
  final Signal<String?> _selectedQualityOptionId = Signal<String?>(null);
  final Signal<String?> _selectedCodecIdentity = Signal<String?>(null);
  final Signal<VesperPlayerError?> _suppressedPlaybackCommandError =
      Signal<VesperPlayerError?>(null);
  final Signal<VesperSystemPlaybackPermissionStatus>
  _systemPlaybackPermissionStatus =
      Signal<VesperSystemPlaybackPermissionStatus>(
        VesperSystemPlaybackPermissionStatus.notRequired,
      );
  final Signal<String?> _castMessage = Signal<String?>(null);
  final Signal<MediaDlnaState> _dlnaState = Signal<MediaDlnaState>(
    MediaDlnaState.idle,
  );
  final Signal<List<VesperExternalPlaybackRoute>> _dlnaRoutes =
      Signal<List<VesperExternalPlaybackRoute>>(
        const <VesperExternalPlaybackRoute>[],
      );
  final Signal<String?> _dlnaMessage = Signal<String?>(null);
  final Signal<String?> _pendingMessage = Signal<String?>(null);
  final Signal<MediaPlaybackRecoveryNotice?> _pendingPlaybackRecoveryNotice =
      Signal<MediaPlaybackRecoveryNotice?>(null);
  bool _castPausedLocalPlayback = false;
  final Signal<bool> _isFullscreen = Signal<bool>(false);
  bool _isDisposed = false;
  bool _playbackRecoveryInFlight = false;
  bool _playbackRecoveryFailureReported = false;
  bool _playbackSourceTransitionInFlight = false;
  int _playbackRecoveryAttempts = 0;
  int _playbackRecoveryGeneration = 0;
  int _controllerGeneration = 0;
  int _playbackSelectionGeneration = 0;
  final Set<String> _runtimeRejectedVideoTrackIds = <String>{};
  final Set<String> _handledRuntimeTrackRejections = <String>{};
  String? _pendingRuntimeFallbackTrackId;
  VesperPlayerError? _deferredPlaybackRecoveryError;
  StreamSubscription<VesperPlayerEvent>? _controllerEventsSubscription;
  Timer? _playbackRecoverySuccessTimer;
  StreamSubscription<VesperExternalPlaybackSessionEvent>?
  _castEventsSubscription;
  late final MediaExternalPlaybackManager _dlnaManager;

  Future<VesperPlayerController> get controllerFuture =>
      _controllerFuture.value;

  VesperPlayerController? get controller => _userController;

  MediaPlaybackEntry get selectedEntry => _selectedEntry.value;

  ResolvedMediaPlayback? get resolvedPlayback => _resolvedPlayback.value;

  String? get selectedQualityOptionId => _selectedQualityOptionId.value;

  String? get selectedCodecIdentity => _selectedCodecIdentity.value;

  /// Command rejections do not make otherwise healthy playback terminal.
  /// Subtitle failures are presented by their selection surface, while a
  /// fixed-track rejection is presented by the typed command result.
  String? playbackErrorMessage(VesperPlayerSnapshot snapshot) {
    final error = snapshot.lastError;
    if (error == null ||
        error.details['domain'] == 'subtitle' ||
        identical(error, _suppressedPlaybackCommandError.value)) {
      return null;
    }
    return error.message;
  }

  VesperSystemPlaybackPermissionStatus get systemPlaybackPermissionStatus =>
      _systemPlaybackPermissionStatus.value;

  String? get castMessage => _castMessage.value;

  MediaDlnaState get dlnaState => _dlnaState.value;

  List<VesperExternalPlaybackRoute> get dlnaRoutes => _dlnaRoutes.value;

  String? get dlnaMessage => _dlnaMessage.value;

  MediaExternalPlaybackManager get dlnaManager => _dlnaManager;

  bool get isFullscreen => _isFullscreen.value;

  String? consumePendingMessage() {
    if (_isDisposed) {
      return null;
    }
    final message = _pendingMessage.value;
    _pendingMessage.value = null;
    return message;
  }

  MediaPlaybackRecoveryNotice? consumePendingPlaybackRecoveryNotice() {
    if (_isDisposed) {
      return null;
    }
    final notice = _pendingPlaybackRecoveryNotice.value;
    _pendingPlaybackRecoveryNotice.value = null;
    return notice;
  }

  void setFullscreen(bool value) {
    if (_isDisposed) {
      return;
    }
    if (_isFullscreen.value == value) {
      return;
    }
    _isFullscreen.value = value;
  }

  /// 兜底监听创建 future 的取消错误：过时代际以 [_PlaybackSourceObsoleted]
  /// 结束（调用方不应收到已销毁实例），但旧 future 可能已无订阅者，
  /// 这里挂一个忽略监听避免 unhandled async error。
  static Future<VesperPlayerController> _trackControllerFuture(
    Future<VesperPlayerController> future,
  ) {
    unawaited(future.then<void>((_) {}, onError: (Object _) {}));
    return future;
  }

  Future<void> reloadCurrentPage() async {
    if (_isDisposed) {
      return;
    }
    _controllerGeneration += 1;
    _resetPlaybackRecoveryState(clearPendingNotice: true);
    final previous = _controller;
    final previousSnapshot = previous?.snapshot;
    _controller = null;
    _userController = null;
    if (previous != null && previousSnapshot != null) {
      if (previousSnapshot.lastError != null) {
        unawaited(_persistHistory(previousSnapshot));
      } else {
        await _persistLatestHistory(previous, fallback: previousSnapshot);
      }
    }
    if (previous != null) {
      await _disposeController(previous);
    }
    if (_isDisposed) {
      return;
    }
    _controllerFuture.value = _trackControllerFuture(_createController());
  }

  Future<String?> switchEntry(MediaPlaybackEntry entry) async {
    if (_isDisposed) {
      return null;
    }
    final controller = _controller;
    if (controller == null || entry.entryId == _selectedEntry.value.entryId) {
      return null;
    }
    // Reentrancy guard: a previous switch may still be resolving/selecting
    // its source. Let the in-flight transition finish untouched instead of
    // interleaving two resolvePlayback -> selectSource -> play chains that
    // would race on _selectedEntry/_resolvedPlayback writes.
    if (_playbackSourceTransitionInFlight) {
      return null;
    }

    _playbackSourceTransitionInFlight = true;
    _invalidatePlaybackSelectionRequests();
    _resetPlaybackRecoveryState(clearPendingNotice: true);
    // 切源前递增：在途的历史续播查询（绑定旧 source）立即失效，
    // 避免 selectSource 之后、_selectedEntry 更新之前返回的旧进度
    // 被 seek 到新 source。
    _sourceGeneration += 1;
    try {
      final currentSnapshot = controller.snapshot;
      unawaited(_persistHistory(currentSnapshot));
      final resolved = await adapter.resolvePlayback(
        detail: detail,
        entry: entry,
      );
      await controller.selectSource(resolved.toSource());
      await _configureSystemPlayback(controller, resolved);
      await controller.play();
      if (_isDisposed) {
        return null;
      }
      _selectedEntry.value = entry;
      _resolvedPlayback.value = resolved;
      _resetRuntimeTrackCapabilityState();
      _selectedQualityOptionId.value = null;
      _selectedCodecIdentity.value = null;
      return null;
    } catch (error) {
      return '切换分 P 失败：${mediaErrorMessage(error)}';
    } finally {
      _playbackSourceTransitionInFlight = false;
    }
  }

  Future<String?> loadCurrentEntryToDlna() async {
    if (_isDisposed) {
      return null;
    }
    try {
      final resolved = await _refreshCurrentResolvedPlayback();
      if (_isDisposed) {
        return null;
      }
      return _dlnaManager.loadMedia(
        resolved: resolved,
        selectedPage: _selectedEntry.value,
        refreshResolved: _refreshCurrentResolvedPlayback,
      );
    } catch (error) {
      return '投屏播放地址刷新失败：${mediaErrorMessage(error)}';
    }
  }

  Future<String?> requestSystemPlaybackPermissions(
    VesperPlayerController controller,
  ) async {
    if (_isDisposed) {
      return null;
    }
    try {
      final permissionStatus = await controller
          .requestSystemPlaybackPermissions();
      if (_isDisposed) {
        return null;
      }
      _systemPlaybackPermissionStatus.value = permissionStatus;
      return null;
    } catch (error) {
      return '系统播放权限请求失败：${mediaErrorMessage(error)}';
    }
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
      return '倍速切换失败：${mediaErrorMessage(error)}';
    }
  }

  /// 用户 seek 入口（壳内所有 seek 调用走这里）：递增用户操作代际，
  /// 使在途的历史续播查询失效，避免慢 IO 返回后覆盖用户操作。
  /// 返回错误消息（null = 成功）；代际递增与错误处理分离，
  /// 失败时不会伪装成功。
  Future<String?> seekToRatio(double ratio) async {
    _userSeekGeneration += 1;
    final controller = _controller;
    if (controller == null) {
      return '播放器尚未准备好。';
    }
    try {
      await controller.seekToRatio(ratio);
      return null;
    } catch (error) {
      return '跳转失败：${mediaErrorMessage(error)}';
    }
  }

  /// 用户 seek 入口（相对增量形式），语义同 [seekToRatio]。
  Future<String?> seekBy(int deltaMs) async {
    _userSeekGeneration += 1;
    final controller = _controller;
    if (controller == null) {
      return '播放器尚未准备好。';
    }
    try {
      await controller.seekBy(deltaMs);
      return null;
    } catch (error) {
      return '跳转失败：${mediaErrorMessage(error)}';
    }
  }

  /// 选择清晰度选项；null 表示回到自动。
  Future<String?> selectQualityOption(String? optionId) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final nextCodecIdentity = optionId == null
        ? null
        : _selectedCodecIdentity.value;
    if (optionId != null) {
      final option = _qualitySelectionOption(
        controller.snapshot,
        optionId,
        codecIdentity: nextCodecIdentity,
      );
      if (option == null) {
        return '当前视频没有可用的清晰度轨道。';
      }
      if (!option.canSelect) {
        return _unavailableSelectionMessage(
          option.unavailableReason,
          noMatchingTracks: option.candidateTracks.isEmpty,
        );
      }
    }
    final selectionGeneration = ++_playbackSelectionGeneration;
    final result = await _applyPlaybackSelection(
      optionId: optionId,
      codecIdentity: nextCodecIdentity,
    );
    if (_isDisposed || selectionGeneration != _playbackSelectionGeneration) {
      return null;
    }
    if (result == null) {
      _selectedQualityOptionId.value = optionId;
      _selectedCodecIdentity.value = nextCodecIdentity;
    }
    return result;
  }

  /// 选择 codec 子策略（AV1/HEVC/AVC 等身份）；null 表示默认。
  Future<String?> selectCodecIdentity(String? identity) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final optionId = _selectedQualityOptionId.value;
    if (identity != null) {
      final availability = _codecSelectionAvailability(
        controller.snapshot,
        identity,
        optionId: optionId,
      );
      final label = _codecDisplayLabel(identity);
      if (availability.declaredTracks.isEmpty) {
        return '当前分辨率没有 $label 策略。';
      }
      if (availability.availability == MediaQualityAvailability.unavailable) {
        return '当前设备不支持 $label 策略。';
      }
    }
    final selectionGeneration = ++_playbackSelectionGeneration;
    final result = await _applyPlaybackSelection(
      optionId: optionId,
      codecIdentity: identity,
    );
    if (_isDisposed || selectionGeneration != _playbackSelectionGeneration) {
      return null;
    }
    if (result == null) {
      _selectedCodecIdentity.value = identity;
    }
    return result;
  }

  Future<String?> applyPlaybackSelection() {
    return _applyPlaybackSelection(
      optionId: _selectedQualityOptionId.value,
      codecIdentity: _selectedCodecIdentity.value,
    );
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
    if (nativeTracks.isNotEmpty) {
      return nativeTracks;
    }
    final manifestTracks =
        _resolvedPlayback.value?.videoTracks ?? const <VesperMediaTrack>[];
    if (manifestTracks.isNotEmpty) {
      return manifestTracks;
    }
    return nativeTracks;
  }

  /// 当前解析结果提供的清晰度选项（适配器已分组）。
  List<MediaQualityOption> availableQualityOptions() {
    return _resolvedPlayback.value?.qualityOptions ??
        const <MediaQualityOption>[];
  }

  /// 将解析阶段的清晰度分组与最新 SDK track catalog 能力合并。
  List<MediaQualitySelectionOption> qualitySelectionOptions(
    VesperPlayerSnapshot snapshot, {
    String? codecIdentity,
  }) {
    final effectiveCodecIdentity =
        codecIdentity ?? _selectedCodecIdentity.value;
    return availableQualityOptions()
        .map((option) {
          final availability = _optionSelectionAvailability(
            snapshot,
            option,
            codecIdentity: effectiveCodecIdentity,
          );
          return MediaQualitySelectionOption(
            option: option,
            availability: availability.availability,
            candidateTracks: availability.candidateTracks,
            unavailableReason: availability.unavailableReason,
          );
        })
        .toList(growable: false);
  }

  MediaQualityAvailability codecSelectionAvailability(
    VesperPlayerSnapshot snapshot,
    String identity, {
    String? optionId,
  }) {
    return _codecSelectionAvailability(
      snapshot,
      identity,
      optionId: optionId,
    ).availability;
  }

  String? qualitySelectionSupportingText(MediaQualitySelectionOption option) {
    return switch (option.availability) {
      MediaQualityAvailability.available => null,
      MediaQualityAvailability.unknown => '兼容性未知',
      MediaQualityAvailability.unavailable =>
        option.candidateTracks.isEmpty
            ? option.unavailableReason == null
                  ? '当前清晰度无此编码'
                  : '清晰度暂不可用'
            : _unavailableSelectionSupportingText(option.unavailableReason),
    };
  }

  String? codecSelectionSupportingText(
    VesperPlayerSnapshot snapshot,
    String identity, {
    String? optionId,
  }) {
    final availability = _codecSelectionAvailability(
      snapshot,
      identity,
      optionId: optionId,
    );
    return switch (availability.availability) {
      MediaQualityAvailability.available => null,
      MediaQualityAvailability.unknown => '兼容性未知',
      MediaQualityAvailability.unavailable =>
        availability.declaredTracks.isEmpty
            ? '当前清晰度无此编码'
            : _unavailableSelectionSupportingText(
                availability.unavailableReason,
              ),
    };
  }

  /// 是否支持 codec 细分选择（平台声明）。
  bool get supportsCodecSelection =>
      _resolvedPlayback.value?.supportsCodecSelection ?? false;

  List<VesperMediaTrack> subtitleTracks(VesperPlayerSnapshot snapshot) {
    return snapshot.trackCatalog.subtitleTracks;
  }

  VesperTrackSelection subtitleSelection(VesperPlayerSnapshot snapshot) {
    return snapshot.trackSelection.confirmedSubtitle;
  }

  Future<String?> selectSubtitle(VesperTrackSelection selection) async {
    final controller = _controller;
    if (controller == null) {
      return '播放器尚未准备好。';
    }
    final snapshot = controller.snapshot;
    if (!snapshot.capabilities.supportsSubtitleTrackSelection) {
      return '当前播放内核不支持字幕切换。';
    }
    try {
      await controller.setSubtitleTrackSelection(selection);
      return null;
    } on VesperSubtitleException catch (error) {
      return '字幕切换失败：${_subtitleSelectionErrorMessage(error)}';
    } catch (error) {
      return '字幕切换失败：${mediaErrorMessage(error)}';
    }
  }

  String playbackStateLabel(VesperPlayerSnapshot snapshot) {
    return switch (snapshot.playbackState) {
      VesperPlaybackState.ready => '就绪',
      VesperPlaybackState.playing => '播放中',
      VesperPlaybackState.paused => '已暂停',
      VesperPlaybackState.finished => '已结束',
    };
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _controllerGeneration += 1;
    _playbackRecoveryGeneration += 1;
    _playbackRecoverySuccessTimer?.cancel();
    final controller = _controller;
    final snapshot = controller?.snapshot;
    if (controller != null && snapshot != null) {
      unawaited(_persistLatestHistory(controller, fallback: snapshot));
    }
    unawaited(_controllerEventsSubscription?.cancel() ?? Future<void>.value());
    unawaited(_castEventsSubscription?.cancel() ?? Future<void>.value());
    _externalPlaybackForCast.dispose();
    _dlnaManager.removeListener(_handleDlnaChanged);
    _dlnaManager.dispose();
    _controller = null;
    _userController = null;
    if (controller != null) {
      unawaited(_disposeController(controller));
    }
    _selectedEntry.dispose();
    _controllerFuture.dispose();
    _resolvedPlayback.dispose();
    _selectedQualityOptionId.dispose();
    _selectedCodecIdentity.dispose();
    _suppressedPlaybackCommandError.dispose();
    _systemPlaybackPermissionStatus.dispose();
    _castMessage.dispose();
    _dlnaState.dispose();
    _dlnaRoutes.dispose();
    _dlnaMessage.dispose();
    _pendingMessage.dispose();
    _pendingPlaybackRecoveryNotice.dispose();
    _isFullscreen.dispose();
  }
}
