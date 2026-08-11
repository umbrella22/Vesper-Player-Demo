import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vesper_media/media/capabilities/media_content_surfaces.dart';
import 'package:vesper_media/media/playback/media_playback_widgets.dart';

/// 播放页呈现模式。
enum MediaPlaybackPresentationMode { phone, tv }

/// 系统呈现策略（方向/系统 UI/状态栏），由平台实现注入。
///
/// 壳不依赖具体平台的方向常量与系统 UI 服务。
final class MediaPlaybackPresentation {
  const MediaPlaybackPresentation({
    required this.enterPlaybackTv,
    required this.enterPlaybackPhone,
    required this.enterFullscreen,
    required this.exitFullscreen,
    required this.restoreApp,
    this.darkSurfaceStyle,
    this.playbackStyleForBrightness,
  });

  /// TV 模式进入播放页（横屏沉浸式）。
  final Future<void> Function() enterPlaybackTv;

  /// 手机模式进入播放页（竖屏 edge-to-edge）。
  final Future<void> Function() enterPlaybackPhone;

  /// 进入全屏（横屏沉浸式）。
  final Future<void> Function() enterFullscreen;

  /// 退出全屏（竖屏 edge-to-edge）。
  final Future<void> Function() exitFullscreen;

  /// 离开播放页恢复 app 呈现（app 方向策略 + 状态栏）。
  final Future<void> Function() restoreApp;

  /// TV/全屏时的深色状态栏样式（平台主题）。
  final SystemUiOverlayStyle? darkSurfaceStyle;

  /// 手机播放页的状态栏样式（按亮度）。
  final SystemUiOverlayStyle Function(Brightness brightness)?
  playbackStyleForBrightness;

  static const noop = MediaPlaybackPresentation(
    enterPlaybackTv: _noop,
    enterPlaybackPhone: _noop,
    enterFullscreen: _noop,
    exitFullscreen: _noop,
    restoreApp: _noop,
  );

  static Future<void> _noop() async {}
}

/// 壳提供给内容槽的宿主：滚动联动、评论回复开关同步、评论时间跳转、
/// 以及打开新播放页（相关视频跳转）的通用通道。
final class MediaPlaybackContentHost {
  MediaPlaybackContentHost({
    required this.surfaceHost,
    required this.relatedScrollController,
    required this.commentsScrollController,
    required this.commentRepliesScrollController,
    required this.commentComposerController,
    required this.commentComposerFocusNode,
    required this.onContentScroll,
    required this.onCommentRepliesVisibilityChanged,
    required this.onSeekToTime,
    this.onLoadMoreComments,
    this.onLoadMoreCommentReplies,
  });

  /// 内容 → 壳的通用通道（如"打开相关视频的新播放页"）。
  final MediaSurfaceHost surfaceHost;

  final ScrollController relatedScrollController;
  final ScrollController commentsScrollController;
  final ScrollController commentRepliesScrollController;
  final TextEditingController commentComposerController;
  final FocusNode commentComposerFocusNode;

  /// 舞台折叠联动：内容滚动时由壳调整折叠偏移。
  final bool Function(ScrollNotification) onContentScroll;

  /// 评论回复面板开关（壳用于折叠偏移与滚动控制器同步）。
  final ValueChanged<bool> onCommentRepliesVisibilityChanged;

  /// 按评论时间跳转（壳实现，基于播放控制器）。
  final Future<void> Function(int seconds) onSeekToTime;

  /// 评论列表滚动到底部时加载更多（内容实现创建时回填）。
  Future<void> Function()? onLoadMoreComments;
  Future<void> Function()? onLoadMoreCommentReplies;
}

/// 无操作设备控制（未注入平台实现时的缺省）。
final class MediaNoopDeviceControls implements MediaPlayerDeviceControls {
  const MediaNoopDeviceControls();

  @override
  Future<double?> currentBrightnessRatio() async => null;

  @override
  Future<double?> setBrightnessRatio(double ratio) async => null;

  @override
  Future<double?> currentVolumeRatio() async => null;

  @override
  Future<double?> setVolumeRatio(double ratio) async => null;
}
