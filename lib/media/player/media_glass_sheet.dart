import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/media/design/app_visual_theme.dart';

enum MediaGlassSheetAppearance { translucent, readable }

enum MediaGlassDialogAppearance { translucent, readable }

Future<T?> showMediaGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxContentHeightFactor = 0.74,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.fromLTRB(18, 8, 18, 8),
  GlassQuality? quality,
  MediaGlassSheetAppearance appearance = MediaGlassSheetAppearance.translucent,
  bool barrierDismissible = true,
}) {
  assert(maxContentHeightFactor > 0 && maxContentHeightFactor <= 1);
  final maxContentHeight =
      MediaQuery.sizeOf(context).height * maxContentHeightFactor;
  final readable = appearance == MediaGlassSheetAppearance.readable;
  final visualTheme = AppVisualTheme.of(context);

  final transitionDuration = AppVisualTokens.motionDuration(
    context,
    AppVisualTokens.overlayDuration,
  );

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: readable
        ? visualTheme.scrim
        : Colors.black.withValues(alpha: 0.42),
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
      if (readable) {
        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _ReadableMediaSheet(
                maxContentHeight: maxContentHeight,
                contentPadding: contentPadding,
                child: builder(sheetContext),
              ),
            ),
          ),
        );
      }
      return SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GlassSheet(
            quality: quality,
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

/// Theme-backed sheet for forms, lists, images, and other dense content.
/// It intentionally avoids refraction so content behind the modal cannot bleed
/// through and compete with the foreground hierarchy.
final class _ReadableMediaSheet extends StatelessWidget {
  const _ReadableMediaSheet({
    required this.maxContentHeight,
    required this.contentPadding,
    required this.child,
  });

  final double maxContentHeight;
  final EdgeInsetsGeometry contentPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: MediaReadableSurface(
        surfaceKey: const ValueKey<String>('media-readable-glass-sheet'),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxContentHeight),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 28,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: visualTheme.textSecondary.withValues(
                          alpha: 0.42,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Padding(padding: contentPadding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opaque, theme-backed modal surface for dense content over image-rich pages.
final class MediaReadableSurface extends StatelessWidget {
  const MediaReadableSurface({
    super.key,
    required this.child,
    this.surfaceKey,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppVisualTokens.sheetRadius),
    ),
  });

  final Widget child;
  final Key? surfaceKey;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      key: surfaceKey,
      color: visualTheme.opaqueGlassFallback,
      elevation: 12,
      shadowColor: visualTheme.shadow.withValues(alpha: 0.82),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: visualTheme.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

final class MediaGlassDialogAction<T> {
  const MediaGlassDialogAction({
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

Future<T?> showMediaGlassDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  required List<MediaGlassDialogAction<T>> actions,
  bool barrierDismissible = false,
  double maxWidth = 360,
  GlassQuality? quality,
  MediaGlassDialogAppearance appearance =
      MediaGlassDialogAppearance.translucent,
}) {
  assert(actions.isNotEmpty && actions.length <= 3);
  final visualTheme = AppVisualTheme.of(context);
  final readable = appearance == MediaGlassDialogAppearance.readable;
  final transitionDuration = AppVisualTokens.motionDuration(
    context,
    AppVisualTokens.overlayDuration,
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: readable
        ? visualTheme.scrim
        : Colors.black.withValues(alpha: 0.54),
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
      if (readable) {
        return _ReadableMediaGlassDialog<T>(
          title: title,
          message: message,
          content: content,
          maxWidth: maxWidth,
          actions: actions,
        );
      }
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

/// Opaque, theme-backed dialog used when the content must remain readable over
/// image-rich app surfaces. The translucent third-party dialog remains the
/// default for decorative/low-density confirmations.
final class _ReadableMediaGlassDialog<T> extends StatelessWidget {
  const _ReadableMediaGlassDialog({
    required this.title,
    required this.message,
    required this.content,
    required this.maxWidth,
    required this.actions,
  });

  final String title;
  final String? message;
  final Widget? content;
  final double maxWidth;
  final List<MediaGlassDialogAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: MediaReadableSurface(
          surfaceKey: const ValueKey<String>('media-readable-glass-dialog'),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: visualTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: visualTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
                if (content != null) ...[const SizedBox(height: 10), content!],
                const SizedBox(height: 18),
                _buildActions(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    if (actions.length <= 2) {
      return Row(
        children: [
          for (var index = 0; index < actions.length; index += 1) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(child: _buildAction(context, actions[index])),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < actions.length; index += 1) ...[
          if (index > 0) const SizedBox(height: 10),
          _buildAction(context, actions[index]),
        ],
      ],
    );
  }

  Widget _buildAction(BuildContext context, MediaGlassDialogAction<T> action) {
    final visualTheme = AppVisualTheme.of(context);
    void onPressed() {
      Navigator.of(context).pop(action.value);
    }

    if (action.isPrimary) {
      return FilledButton(onPressed: onPressed, child: Text(action.label));
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: action.isDestructive
            ? visualTheme.destructive
            : visualTheme.textPrimary,
        side: BorderSide(color: visualTheme.glassBorder),
      ),
      child: Text(action.label),
    );
  }
}
