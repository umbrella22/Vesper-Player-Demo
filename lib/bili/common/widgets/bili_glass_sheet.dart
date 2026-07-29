import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/app/design/app_visual_theme.dart';

enum BiliGlassSheetAppearance { translucent, readable }

Future<T?> showBiliGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxContentHeightFactor = 0.74,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.fromLTRB(18, 8, 18, 8),
  GlassQuality? quality,
  BiliGlassSheetAppearance appearance = BiliGlassSheetAppearance.translucent,
  bool barrierDismissible = true,
}) {
  assert(maxContentHeightFactor > 0 && maxContentHeightFactor <= 1);
  final maxContentHeight =
      MediaQuery.sizeOf(context).height * maxContentHeightFactor;

  final transitionDuration = AppVisualTokens.motionDuration(
    context,
    AppVisualTokens.overlayDuration,
  );

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: transitionDuration,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (sheetContext, animation, secondaryAnimation) {
      final visualTheme = AppVisualTheme.of(sheetContext);
      final readable = appearance == BiliGlassSheetAppearance.readable;
      return SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GlassSheet(
            key: readable
                ? const ValueKey<String>('bili-readable-glass-sheet')
                : null,
            quality: quality,
            settings: readable
                ? LiquidGlassSettings(
                    glassColor: visualTheme.surface.withValues(alpha: 0.96),
                    thickness: 8,
                    blur: 12,
                    lightIntensity: 0.5,
                    chromaticAberration: 0,
                    refractiveIndex: 0.1,
                    saturation: 1,
                    ambientStrength: 0.28,
                  )
                : null,
            dragIndicatorColor: readable
                ? visualTheme.textSecondary.withValues(alpha: 0.42)
                : null,
            topBorderRadius: AppVisualTokens.sheetRadius,
            bottomBorderRadius: AppVisualTokens.sheetRadius,
            margin: const EdgeInsets.all(8),
            padding: EdgeInsets.zero,
            isScrollable: false,
            suppressInteractionOnChildren: true,
            enableSaturationGlow: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxContentHeight),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: contentPadding,
                child: Material(
                  type: MaterialType.transparency,
                  child: GlassInteractionSilence(child: builder(sheetContext)),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

final class BiliGlassDialogAction<T> {
  const BiliGlassDialogAction({
    required this.label,
    required this.value,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  final String label;
  final T value;
  final bool isPrimary;
  final bool isDestructive;
}

Future<T?> showBiliGlassDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  required List<BiliGlassDialogAction<T>> actions,
  bool barrierDismissible = false,
  double maxWidth = 360,
  GlassQuality? quality,
}) {
  assert(actions.isNotEmpty && actions.length <= 3);
  final transitionDuration = AppVisualTokens.motionDuration(
    context,
    AppVisualTokens.overlayDuration,
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.54),
    transitionDuration: transitionDuration,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return GlassDialog(
        title: title,
        message: message,
        content: content,
        quality: quality,
        maxWidth: maxWidth,
        actions: [
          for (final action in actions)
            GlassDialogAction(
              label: action.label,
              isPrimary: action.isPrimary,
              isDestructive: action.isDestructive,
              onPressed: () => Navigator.of(dialogContext).pop(action.value),
            ),
        ],
      );
    },
  );
}
