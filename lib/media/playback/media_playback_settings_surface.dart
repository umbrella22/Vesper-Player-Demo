import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_player/vesper_player.dart';

enum MediaPlaybackDrawerSide { leading, trailing }

/// 通用播放页侧边抽屉。调用方只提供内容与出现方向，遮罩、尺寸、滚动和
/// 键盘避让由公共层统一处理。
Future<T?> showMediaPlaybackSideDrawer<T>(
  BuildContext context, {
  required MediaPlaybackDrawerSide side,
  required WidgetBuilder builder,
  Key? surfaceKey,
}) {
  final appearsFromLeading = side == MediaPlaybackDrawerSide.leading;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, _) {
      final visualTheme = AppVisualTheme.of(dialogContext);
      final drawerWidth = MediaQuery.sizeOf(dialogContext).width * 0.42;
      return Align(
        alignment: appearsFromLeading
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: Material(
          key: surfaceKey,
          color: visualTheme.background,
          borderRadius: BorderRadius.horizontal(
            left: appearsFromLeading ? Radius.zero : const Radius.circular(22),
            right: appearsFromLeading ? const Radius.circular(22) : Radius.zero,
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            left: appearsFromLeading,
            right: !appearsFromLeading,
            child: SizedBox(
              width: drawerWidth,
              height: double.infinity,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  22 + MediaQuery.viewInsetsOf(dialogContext).bottom,
                ),
                child: builder(dialogContext),
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
          begin: Offset(appearsFromLeading ? -1 : 1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// 通用设置表面：窄屏弹出底栏，宽屏左侧抽屉。
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
    side: MediaPlaybackDrawerSide.leading,
    builder: (drawerContext) {
      return ValueListenableBuilder<VesperPlayerSnapshot>(
        valueListenable: controller.snapshotListenable,
        builder: (context, drawerSnapshot, _) {
          return contentBuilder(context, drawerSnapshot);
        },
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
          child: ValueListenableBuilder<VesperPlayerSnapshot>(
            valueListenable: controller.snapshotListenable,
            builder: (context, sheetSnapshot, _) {
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
