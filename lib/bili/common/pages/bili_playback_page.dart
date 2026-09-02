import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/app/services/danmaku_settings_controller.dart';
import 'package:vesper_media/app/system_presentation.dart';
import 'package:vesper_media/bili/common/services/bili_device_controls.dart';
import 'package:vesper_media/bili/common/view_models/bili_playback_view_model.dart';
import 'package:vesper_media/bili/common/widgets/bili_cache_download_panel.dart';
import 'package:vesper_media/download/services/offline_download_controller.dart';
import 'package:vesper_media/danmaku/danmaku.dart';
import 'package:vesper_media/danmaku/widgets/bili_danmaku_settings_panel.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_media/media/player/media_glass_sheet.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_media_mapper.dart';
import 'package:vesper_media/bili/tv_mode/pages/bili_tv_home_page.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_glass_dialog.dart';

import 'bili_playback_content_surfaces.dart';

/// Bilibili 播放页入口（薄包装）：构造 B 站内容状态与平台槽位，
/// 渲染通用播放页壳 [MediaPlaybackPage]。
class BiliPlaybackPage extends StatefulWidget {
  const BiliPlaybackPage({
    super.key,
    required this.detail,
    required this.initialPage,
    required this.client,
    required this.historyStore,
    this.offlineController,
    this.initialResolvedPlayback,
    this.initialPositionMs = 0,
    this.presentationMode = BiliPlaybackPresentationMode.phone,
    this.danmakuSettingsController,
  });

  final BiliVideoDetail detail;
  final BiliVideoPageEntry initialPage;
  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliOfflineDownloadController? offlineController;
  final BiliResolvedPlayback? initialResolvedPlayback;
  final int initialPositionMs;
  final BiliPlaybackPresentationMode presentationMode;
  final DanmakuSettingsController? danmakuSettingsController;

  @override
  State<BiliPlaybackPage> createState() => _BiliPlaybackPageState();
}

class _BiliPlaybackPageState extends State<BiliPlaybackPage> {
  late final BiliPlaybackViewModel _viewModel;
  late final MediaPlaybackBinding _playbackBinding;
  late final DanmakuSettingsController _danmakuSettingsController;
  bool _ownsDanmakuSettingsController = false;
  bool _danmakuSettingsBound = false;

  bool get _isTvMode =>
      widget.presentationMode == BiliPlaybackPresentationMode.tv;

  @override
  void initState() {
    super.initState();
    _viewModel = BiliPlaybackViewModel(
      detail: widget.detail,
      initialPage: widget.initialPage,
      client: widget.client,
      historyStore: widget.historyStore,
      offlineController: widget.offlineController,
      initialResolvedPlayback: widget.initialResolvedPlayback,
      initialPositionMs: widget.initialPositionMs,
    );
    _playbackBinding = MediaPlaybackBinding(
      engagementBuilder: _viewModel.buildEngagementCapability,
      contentSurfacesBuilder: (host) => BiliPlaybackContentSurfaces(
        viewModel: _viewModel,
        detail: widget.detail,
        host: host,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_danmakuSettingsBound) {
      return;
    }
    final inheritedController = DanmakuSettingsScope.maybeOf(context);
    _danmakuSettingsController =
        widget.danmakuSettingsController ??
        inheritedController ??
        DanmakuSettingsController();
    _ownsDanmakuSettingsController =
        widget.danmakuSettingsController == null && inheritedController == null;
    _viewModel.bindDanmakuSourceFilter(
      _danmakuSettingsController.sourceFilterListenable,
    );
    _danmakuSettingsBound = true;
  }

  @override
  void dispose() {
    _viewModel.dispose();
    if (_ownsDanmakuSettingsController) {
      _danmakuSettingsController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MediaPlaybackPage(
      viewModel: _viewModel.playbackViewModel,
      presentationMode: widget.presentationMode,
      binding: _playbackBinding,
      deviceControls: const BiliStageDeviceControls(),
      contentTabsTrailing: DanmakuEntryPill(
        danmakuCountLabel: widget.detail.danmakuCountLabel,
      ),
      tuningCacheEntry: CacheEntryButton(
        onTap: () => unawaited(_openCacheSurfaceFromSettings(context)),
      ),
      danmakuSettingsSurface: BiliDanmakuSettingsPanel(
        settings: _danmakuSettingsController.listenable,
        onChanged: _setDanmakuSettings,
      ),
      danmakuSettingsListenable: _danmakuSettingsController.overlayListenable,
      onDanmakuSettingsChanged: (settings) {
        _setDanmakuSettings(
          _danmakuSettingsController.value.copyWith(overlay: settings),
        );
      },
      tvControlBarExtras: <Widget>[
        SignalBuilder(builder: (context) => _buildTvWatchLaterButton()),
      ],
      tvFallbackHome: BiliTvHomePage(
        client: widget.client,
        historyStore: widget.historyStore,
        offlineController: widget.offlineController,
      ),
      recoveryDialogBuilder: _showPlaybackRecoveryDialog,
      presentation: _buildPresentation(),
      onPushPlayback: _pushRelatedPlayback,
    );
  }

  void _setDanmakuSettings(BiliDanmakuSettings settings) {
    unawaited(
      _danmakuSettingsController.setValue(settings).then((saved) {
        if (!saved && mounted) {
          _showMessage('弹幕设置保存失败');
        }
      }),
    );
  }

  Widget _buildTvWatchLaterButton() {
    final inWatchLater = _viewModel.isInWatchLater;
    final loading = _viewModel.watchLaterLoading;
    return TvBarButton(
      label: inWatchLater ? '已加入稍后再看' : '稍后再看',
      icon: inWatchLater
          ? Icons.watch_later_rounded
          : Icons.watch_later_outlined,
      onTap: loading ? () {} : () => unawaited(_toggleWatchLater()),
    );
  }

  Future<void> _toggleWatchLater() async {
    final message = await _viewModel.toggleWatchLater();
    if (message != null && mounted) {
      _showMessage(message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  MediaPlaybackPresentation _buildPresentation() {
    return MediaPlaybackPresentation(
      enterPlaybackTv: () => _applyPresentation(
        orientations: biliLandscapeOrientations,
        systemUiMode: SystemUiMode.immersiveSticky,
        overlayStyle: biliDarkSurfaceSystemUiStyle,
      ),
      enterPlaybackPhone: () => _applyPresentation(
        orientations: biliPortraitOrientations,
        systemUiMode: SystemUiMode.edgeToEdge,
        overlayStyle: biliDarkSurfaceSystemUiStyle,
      ),
      enterFullscreen: () => _applyPresentation(
        orientations: biliLandscapeOrientations,
        systemUiMode: SystemUiMode.immersiveSticky,
        overlayStyle: biliDarkSurfaceSystemUiStyle,
      ),
      exitFullscreen: () => _applyPresentation(
        orientations: biliPortraitOrientations,
        systemUiMode: SystemUiMode.edgeToEdge,
        overlayStyle: biliDarkSurfaceSystemUiStyle,
      ),
      restoreApp: () => _isTvMode
          ? _applyPresentation(
              orientations: biliLandscapeOrientations,
              systemUiMode: SystemUiMode.immersiveSticky,
              overlayStyle: biliDarkSurfaceSystemUiStyle,
            )
          : _applyPresentation(
              useAppOrientationPolicy: true,
              systemUiMode: SystemUiMode.edgeToEdge,
              overlayStyle: biliAppSystemUiStyle,
            ),
      darkSurfaceStyle: biliDarkSurfaceSystemUiStyle,
      playbackStyleForBrightness: playbackSystemUiStyleForBrightness,
    );
  }

  Future<void> _applyPresentation({
    List<DeviceOrientation>? orientations,
    bool useAppOrientationPolicy = false,
    required SystemUiMode systemUiMode,
    required SystemUiOverlayStyle overlayStyle,
  }) async {
    if (useAppOrientationPolicy) {
      await setBiliAppPreferredOrientations();
    } else {
      await setBiliPreferredOrientations(orientations!);
    }
    await setBiliSystemUiMode(systemUiMode);
    setBiliSystemUiOverlayStyle(overlayStyle);
  }

  Future<bool?> _showPlaybackRecoveryDialog(
    BuildContext dialogContext,
    MediaPlaybackRecoveryNotice notice,
  ) async {
    if (_isTvMode) {
      return showBiliTvGlassDialog<bool>(
        context: dialogContext,
        title: notice.title,
        message: notice.message,
        icon: Icons.sync_problem_rounded,
        actions: const [
          BiliTvDialogAction(
            label: '知道了',
            value: false,
            icon: Icons.close_rounded,
            autofocus: true,
          ),
          BiliTvDialogAction(
            label: '重新解析',
            value: true,
            icon: Icons.refresh_rounded,
          ),
        ],
      );
    }
    return showMediaGlassDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      appearance: MediaGlassDialogAppearance.readable,
      title: notice.title,
      message: notice.message,
      actions: const [
        MediaGlassDialogAction(label: '知道了', value: false),
        MediaGlassDialogAction(label: '重新解析', value: true, isPrimary: true),
      ],
    );
  }

  void _pushRelatedPlayback(MediaDetail detail, MediaPlaybackEntry entry) {
    if (!mounted) {
      return;
    }
    final biliDetail = BiliMediaMapper.toBiliDetail(detail);
    final biliPage = BiliMediaMapper.toBiliEntry(entry);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => BiliPlaybackPage(
          detail: biliDetail,
          initialPage: biliPage,
          client: widget.client,
          historyStore: widget.historyStore,
          offlineController: widget.offlineController,
          presentationMode: widget.presentationMode,
        ),
      ),
    );
  }

  // ---- 离线缓存表面（下载保持 app 级，B 站专属） ----

  Future<void> _openCacheSurfaceFromSettings(
    BuildContext surfaceContext,
  ) async {
    final size = MediaQuery.sizeOf(context);
    final isPortrait = size.height >= size.width;
    Navigator.of(surfaceContext).pop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) {
      return;
    }
    await _showCacheSurface(isPortrait: isPortrait);
  }

  Future<void> _showCacheSurface({required bool isPortrait}) {
    if (isPortrait) {
      return _showCacheSheet();
    }
    return _showCacheDrawer();
  }

  Future<void> _showCacheDrawer() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        final visualTheme = AppVisualTheme.of(dialogContext);
        final drawerWidth = (MediaQuery.sizeOf(dialogContext).width * 0.42)
            .clamp(
              MediaQuery.sizeOf(dialogContext).width * 0.28,
              MediaQuery.sizeOf(dialogContext).width * 0.42,
            )
            .toDouble();
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: visualTheme.background,
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
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: BiliCacheDownloadPanel(
                    detail: widget.detail,
                    currentPage: _viewModel.selectedPage,
                    selectedQualityId: _viewModel.selectedBiliQualityId,
                    codecPreference: _currentDownloadCodecPreference(),
                    controller: _viewModel.offlineController,
                    onMessage: _showMessage,
                    client: widget.client,
                    historyStore: widget.historyStore,
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

  Future<void> _showCacheSheet() {
    return showMediaGlassSheet<void>(
      context: context,
      appearance: MediaGlassSheetAppearance.readable,
      contentPadding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      builder: (_) => BiliCacheDownloadPanel(
        detail: widget.detail,
        currentPage: _viewModel.selectedPage,
        selectedQualityId: _viewModel.selectedBiliQualityId,
        codecPreference: _currentDownloadCodecPreference(),
        controller: _viewModel.offlineController,
        onMessage: _showMessage,
        client: widget.client,
        historyStore: widget.historyStore,
      ),
    );
  }

  BiliVideoCodecPreference _currentDownloadCodecPreference() {
    return _viewModel.currentDownloadCodecPreference();
  }
}
