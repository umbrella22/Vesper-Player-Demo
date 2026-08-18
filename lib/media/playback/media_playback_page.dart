import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_ui/vesper_player_ui.dart' as vesper_ui;

import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_media/media/player/media_glass_sheet.dart';

import 'media_listen_mode_view.dart';

part 'media_playback_page_actions.dart';
part 'media_playback_page_phone.dart';
part 'media_playback_page_tv.dart';
part 'media_playback_page_surfaces.dart';

enum TvPlaybackPanelType { none, quality, speed, subtitles, pages }

enum _PlaybackInfoTab { intro, comments }

enum _MediaPlaybackDisplayMode { video, listen }

/// 通用播放页壳。
///
/// 平台差异全部经构造槽位注入：
/// - [viewModel]：播放编排（调用方构造并管理生命周期）
/// - [binding]：单次播放的互动能力与内容面板
/// - [deviceControls]：亮度/音量设备控制
/// - [presentation]：系统呈现策略
/// - [contentTabsTrailing]/[tuningCacheEntry]/[tvControlBarExtras]/[tvFallbackHome]：
///   平台扩展 UI（弹幕入口/缓存入口/稍后再看/TV 首页回退）
/// - [recoveryDialogBuilder]：播放恢复失败提示（平台视觉）
class MediaPlaybackPage extends StatefulWidget {
  const MediaPlaybackPage({
    super.key,
    required this.viewModel,
    this.presentationMode = MediaPlaybackPresentationMode.phone,
    this.binding = const MediaPlaybackBinding(),
    this.deviceControls = const MediaNoopDeviceControls(),
    this.contentTabsTrailing,
    this.tuningCacheEntry,
    this.tvControlBarExtras = const <Widget>[],
    this.tvFallbackHome,
    this.recoveryDialogBuilder,
    this.presentation = MediaPlaybackPresentation.noop,
    this.onPushPlayback,
  });

  /// 播放编排 view model（调用方构造并负责 dispose）。
  final MediaPlaybackViewModel viewModel;

  final MediaPlaybackPresentationMode presentationMode;

  /// 页面级动态能力；缺省不渲染互动栏与内容 tab。
  final MediaPlaybackBinding binding;

  final MediaPlayerDeviceControls deviceControls;

  /// 内容 tab 尾部扩展（如弹幕入口胶囊）。
  final Widget? contentTabsTrailing;

  /// 调校面板的离线缓存入口（下载保持 app 级）。
  final Widget? tuningCacheEntry;

  /// TV 控制条右侧扩展按钮（如稍后再看）。
  final List<Widget> tvControlBarExtras;

  /// TV 返回栈底时的平台首页。
  final Widget? tvFallbackHome;

  /// 播放恢复失败提示对话框（平台视觉）；缺省使用默认对话框。
  final Future<bool?> Function(
    BuildContext context,
    MediaPlaybackRecoveryNotice notice,
  )?
  recoveryDialogBuilder;

  /// 系统呈现策略。
  final MediaPlaybackPresentation presentation;

  /// 打开新播放页（相关视频跳转等），由平台实现。
  final void Function(MediaDetail detail, MediaPlaybackEntry entry)?
  onPushPlayback;

  @override
  State<MediaPlaybackPage> createState() => _MediaPlaybackPageState();
}

class _MediaPlaybackPageState extends State<MediaPlaybackPage>
    with TickerProviderStateMixin {
  late final MediaPlaybackViewModel _viewModel;
  MediaContentSurfaces? _contentSurfaces;
  late final MediaPlaybackContentHost _contentHost;
  void Function()? _messageEffect;

  /// 内容 tab 控制器；平台未声明内容面板时为 null（不渲染 tab 区）。
  /// build 中按能力同步（评论面板可用性依赖 context，initState 无法判定）。
  TabController? _infoTabController;
  int _infoTabCount = 0;

  /// 评论面板可用性缓存：按 entry 失效（nullable builder 接收当前 target，
  /// 分 P 之间评论能力可能不同），surfaces 不换。
  bool? _commentsAvailable;
  String? _commentsAvailableEntryId;
  bool _settingsSurfaceOpen = false;
  bool _castingSurfaceOpen = false;
  bool _dlnaPickerOpen = false;
  _PlaybackInfoTab _selectedInfoTab = _PlaybackInfoTab.intro;
  bool _commentsRepliesOpen = false;
  final ScrollController _commentsScrollController = ScrollController();
  final ScrollController _commentRepliesScrollController = ScrollController(
    keepScrollOffset: false,
  );
  final ScrollController _relatedScrollController = ScrollController();
  final TextEditingController _commentComposerController =
      TextEditingController();
  final FocusNode _commentComposerFocusNode = FocusNode(
    debugLabel: 'comment_composer',
  );
  double _mobileStageCollapseOffset = 0;
  double? _scheduledMobileStageCollapseOffset;
  bool _mobileStageCollapseFrameScheduled = false;
  int _presentationGeneration = 0;
  bool _tvControlBarVisible = false;
  TvPlaybackPanelType _tvPanel = TvPlaybackPanelType.none;
  final FocusNode _tvPlaybackFocusNode = FocusNode(debugLabel: 'tv_playback');
  final Map<TvPlaybackPanelType, FocusNode> _tvPanelButtonFocusNodes =
      <TvPlaybackPanelType, FocusNode>{};
  TvPlaybackPanelType? _lastOpenedTvPanel;
  bool _tvPlaybackInitialFocusRequested = false;
  bool _playbackRecoveryDialogVisible = false;
  bool _tvBackDispatchPending = false;
  _MediaPlaybackDisplayMode _displayMode = _MediaPlaybackDisplayMode.video;

  bool get _isTvMode =>
      widget.presentationMode == MediaPlaybackPresentationMode.tv;

  bool get _tvPanelOpen => _tvPanel != TvPlaybackPanelType.none;

  bool get _playbackModalRouteOpen =>
      _settingsSurfaceOpen ||
      _castingSurfaceOpen ||
      _dlnaPickerOpen ||
      _playbackRecoveryDialogVisible;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel;
    _contentHost = MediaPlaybackContentHost(
      surfaceHost: MediaSurfaceHost(
        pushPlayback: (detail, entry) {
          widget.onPushPlayback?.call(detail, entry);
        },
      ),
      relatedScrollController: _relatedScrollController,
      commentsScrollController: _commentsScrollController,
      commentRepliesScrollController: _commentRepliesScrollController,
      commentComposerController: _commentComposerController,
      commentComposerFocusNode: _commentComposerFocusNode,
      onContentScroll: _handleMobileContentScroll,
      onCommentRepliesVisibilityChanged: _handleCommentRepliesVisibilityChanged,
      onSeekToTime: _seekToCommentTime,
    );
    _contentSurfaces = widget.binding.buildContentSurfaces(_contentHost);
    _commentsScrollController.addListener(_handleCommentsScrollPosition);
    _commentRepliesScrollController.addListener(
      _handleCommentRepliesScrollPosition,
    );
    // One-shot messages and playback-recovery notices are surfaced through an
    // effect that tracks the VM's pending-message signals.
    _messageEffect = effect(_handleViewModelMessage);
    HardwareKeyboard.instance.addHandler(_handleTvHardwareKeyEvent);
    unawaited(_enterPlaybackPresentation());
  }

  @override
  void didUpdateWidget(MediaPlaybackPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presentationMode != widget.presentationMode) {
      _tvPlaybackInitialFocusRequested = false;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleTvHardwareKeyEvent);
    _infoTabController?.removeListener(_handleInfoTabChanged);
    _infoTabController?.dispose();
    _commentsScrollController.removeListener(_handleCommentsScrollPosition);
    _commentsScrollController.dispose();
    _commentRepliesScrollController.removeListener(
      _handleCommentRepliesScrollPosition,
    );
    _commentRepliesScrollController.dispose();
    _relatedScrollController.dispose();
    _commentComposerController.dispose();
    _commentComposerFocusNode.dispose();
    _tvPlaybackFocusNode.dispose();
    for (final node in _tvPanelButtonFocusNodes.values) {
      node.dispose();
    }
    _messageEffect?.call();
    unawaited(_restoreAppPresentation());
    super.dispose();
  }

  void _mutate(VoidCallback mutation) => setState(mutation);

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Scaffold(
      backgroundColor: visualTheme.background,
      body: SignalBuilder(
        builder: (context) {
          // VM state is read deep inside nested element builders where the
          // signals runtime cannot track reads, so the outer builder only
          // subscribes to what it directly needs (controller future and
          // fullscreen). Each layout section wraps its own reads in a leaf
          // SignalBuilder for fine-grained rebuilds.
          final isFullscreen = _viewModel.isFullscreen;
          return FutureBuilder<VesperPlayerController>(
            future: _viewModel.controllerFuture,
            builder: (context, asyncSnapshot) {
              if (asyncSnapshot.hasError) {
                return MediaPlaybackErrorState(
                  error: asyncSnapshot.error!,
                  onRetry: _reloadCurrentPage,
                );
              }
              if (!asyncSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final controller = asyncSnapshot.data!;
              final overlayStyle = _isTvMode || isFullscreen
                  ? (widget.presentation.darkSurfaceStyle ??
                        const SystemUiOverlayStyle())
                  : (widget.presentation.playbackStyleForBrightness?.call(
                          Theme.of(context).brightness,
                        ) ??
                        const SystemUiOverlayStyle());
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle,
                child: ValueListenableBuilder<VesperPlayerSnapshot>(
                  valueListenable: controller.snapshotListenable,
                  builder: (context, snapshot, _) {
                    return AnimatedSwitcher(
                      duration: AppVisualTokens.motionDuration(
                        context,
                        const Duration(milliseconds: 240),
                      ),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child:
                          _displayMode == _MediaPlaybackDisplayMode.listen &&
                              !isFullscreen
                          ? PopScope(
                              key: const ValueKey<String>(
                                'listen-mode-container',
                              ),
                              canPop: false,
                              onPopInvokedWithResult: (didPop, _) {
                                if (!didPop) {
                                  _returnToVideoMode();
                                }
                              },
                              child: SignalBuilder(
                                builder: (context) => MediaListenModeView(
                                  controller: controller,
                                  snapshot: snapshot,
                                  detail: _viewModel.detail,
                                  selectedEntry: _viewModel.selectedEntry,
                                  isTv: _isTvMode,
                                  onReturnToVideo: _returnToVideoMode,
                                  onSelectEntry: _switchEntry,
                                  onSeek: (ratio) {
                                    unawaited(_viewModel.seekToRatio(ratio));
                                  },
                                  onOpenSubtitleSettings: _isTvMode
                                      ? null
                                      : () => unawaited(
                                          _showSettingsSurface(
                                            controller,
                                            isPortrait: true,
                                          ),
                                        ),
                                ),
                              ),
                            )
                          : KeyedSubtree(
                              key: const ValueKey<String>(
                                'video-mode-container',
                              ),
                              child: _buildPlaybackLayout(
                                context,
                                controller,
                                snapshot,
                                isFullscreen: isFullscreen,
                              ),
                            ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

final class _TvPlaybackToggleBarIntent extends Intent {
  const _TvPlaybackToggleBarIntent();
}

final class _TvPlaybackMenuIntent extends Intent {
  const _TvPlaybackMenuIntent();
}

final class _TvPlayPauseIntent extends Intent {
  const _TvPlayPauseIntent();
}

final class _TvPlaybackLeftIntent extends Intent {
  const _TvPlaybackLeftIntent();
}

final class _TvPlaybackRightIntent extends Intent {
  const _TvPlaybackRightIntent();
}

final class _TvPlaybackUpIntent extends Intent {
  const _TvPlaybackUpIntent();
}

final class _TvPlaybackDownIntent extends Intent {
  const _TvPlaybackDownIntent();
}

enum _ProjectionTarget { dlna }
