import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_player/vesper_player.dart';

import 'media_playback_settings_widgets.dart';

/// 全屏播放设置统一从右侧进入，尺寸、主题、关闭手势与键盘避让共用。
/// 带固定标题的内容自行管理滚动，普通内容使用默认滚动容器。
Future<T?> showMediaPlaybackSideDrawer<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Key? surfaceKey,
  bool scrollable = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.16),
    transitionDuration: AppVisualTokens.motionDuration(
      context,
      AppVisualTokens.overlayDuration,
    ),
    pageBuilder: (dialogContext, animation, _) {
      final size = MediaQuery.sizeOf(dialogContext);
      final drawerWidth = (size.width * 0.35).clamp(300.0, 460.0);
      final darkTheme = AppVisualTokens.mobileDarkTheme();
      const accent = AppVisualTokens.primaryBlue;
      final drawerTheme = darkTheme.copyWith(
        colorScheme: darkTheme.colorScheme.copyWith(
          primary: accent,
          secondary: accent,
        ),
        extensions: [
          AppVisualTheme.dark.copyWith(
            background: const Color(0xEB101115),
            surfaceRaised: const Color(0xD925262C),
            textPrimary: const Color(0xFFF6F6F8),
            textSecondary: const Color(0xFFA9AAB3),
          ),
        ],
        iconTheme: const IconThemeData(color: Color(0xFFF6F6F8)),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: accent,
          selectionColor: accent.withValues(alpha: 0.24),
          selectionHandleColor: accent,
        ),
        inputDecorationTheme: darkTheme.inputDecorationTheme.copyWith(
          focusedBorder: darkTheme.inputDecorationTheme.focusedBorder?.copyWith(
            borderSide: BorderSide(
              color: accent.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
        ),
        sliderTheme: darkTheme.sliderTheme.copyWith(
          activeTrackColor: accent,
          inactiveTrackColor: const Color(0xFF3A3B43),
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: Colors.transparent,
          thumbColor: Colors.white,
          overlayColor: accent.withValues(alpha: 0.12),
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 5,
            elevation: 0,
            pressedElevation: 0,
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? accent
                : const Color(0xFF4C4D55),
          ),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      );
      var horizontalDrag = 0.0;
      // The scroll viewport must shrink with the IME so focused fields can
      // scroll into the visible area, instead of behind the keyboard.
      return Padding(
        padding: MediaQuery.viewInsetsOf(dialogContext),
        child: MediaQuery.removeViewInsets(
          context: dialogContext,
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          child: Align(
            alignment: Alignment.centerRight,
            child: SlideTransition(
              position: animation
                  .drive(CurveTween(curve: Curves.easeOutCubic))
                  .drive(Tween(begin: const Offset(1, 0), end: Offset.zero)),
              child: GestureDetector(
                onHorizontalDragStart: (_) => horizontalDrag = 0,
                onHorizontalDragUpdate: (details) =>
                    horizontalDrag += details.delta.dx,
                onHorizontalDragEnd: (details) {
                  if (horizontalDrag > 64 ||
                      (horizontalDrag > 0 &&
                          (details.primaryVelocity ?? 0) > 700)) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: Theme(
                  data: drawerTheme,
                  child: MediaPlaybackDrawerScope(
                    child: Material(
                      key: surfaceKey,
                      color: drawerTheme
                          .extension<AppVisualTheme>()!
                          .background,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(18),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        width: drawerWidth,
                        height: double.infinity,
                        child: SafeArea(
                          left: false,
                          child: scrollable
                              ? SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    12,
                                    18,
                                    18,
                                  ),
                                  child: Builder(builder: builder),
                                )
                              : Builder(builder: builder),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

/// 通用设置表面：窄屏弹出底栏，宽屏右侧抽屉。
///
/// 内容由 [contentBuilder] 提供（如音画调校面板）；离线缓存等平台专属
/// 入口通过内容自身注入，本容器不接触平台类型。
Future<void> showMediaPlaybackSettingsSurface(
  BuildContext context, {
  required bool isPortrait,
  required VesperPlayerController controller,
  required Widget Function(BuildContext, VesperPlayerSnapshot) contentBuilder,
}) async {
  if (isPortrait) {
    await _showSettingsSheet(context, controller, contentBuilder);
  } else {
    await _showSettingsDrawer(context, controller, contentBuilder);
  }
}

Future<void> _showSettingsDrawer(
  BuildContext context,
  VesperPlayerController controller,
  Widget Function(BuildContext, VesperPlayerSnapshot) contentBuilder,
) {
  return showMediaPlaybackSideDrawer<void>(
    context,
    surfaceKey: const ValueKey('playback-settings-drawer'),
    scrollable: false,
    builder: (drawerContext) {
      return _PlaybackSettingsContent(
        controller: controller,
        builder: contentBuilder,
      );
    },
  );
}

Future<void> _showSettingsSheet(
  BuildContext context,
  VesperPlayerController controller,
  Widget Function(BuildContext, VesperPlayerSnapshot) contentBuilder,
) {
  final visualTheme = AppVisualTheme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: visualTheme.background,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.82,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            bottom: 22 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: _PlaybackSettingsContent(
            controller: controller,
            builder: (context, sheetSnapshot) {
              return SingleChildScrollView(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppVisualTheme.of(context).surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppVisualTheme.of(context).shadow,
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: contentBuilder(context, sheetSnapshot),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

/// Both presentations subscribe to player snapshots and app selection signals.
class _PlaybackSettingsContent extends StatelessWidget {
  const _PlaybackSettingsContent({
    required this.controller,
    required this.builder,
  });

  final VesperPlayerController controller;
  final Widget Function(BuildContext, VesperPlayerSnapshot) builder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VesperPlayerSnapshot>(
        valueListenable: controller.snapshotListenable,
        builder: (context, snapshot, _) =>
            SignalBuilder(builder: (context) => builder(context, snapshot)),
      );
}
