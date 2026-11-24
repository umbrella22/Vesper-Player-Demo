// liquid_glass_widgets 1.20.0 resolves CupertinoColors from flutter/cupertino.dart's CupertinoTheme.
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/media/design/app_visual_theme.dart';

enum MediaGlassSheetAppearance { translucent, readable }

enum MediaGlassDialogAppearance { translucent, readable }

bool _shouldForceReadableModal(BuildContext context, GlassQuality? quality) {
  return MediaQuery.highContrastOf(context) ||
      quality == GlassQuality.minimal ||
      GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality ==
          GlassQuality.minimal;
}

/// Shared landscape container for the app's cache panels.
Future<T?> showMediaReadableSideDrawer<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Key? surfaceKey,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.fromLTRB(20, 18, 20, 22),
  bool scrollable = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: AppVisualTheme.of(context).scrim,
    transitionDuration: AppVisualTokens.motionDuration(
      context,
      AppVisualTokens.overlayDuration,
    ),
    pageBuilder: (drawerContext, _, _) {
      final screenWidth = MediaQuery.sizeOf(drawerContext).width;
      final drawerWidth = (screenWidth * 0.42)
          .clamp(300.0, 440.0)
          .clamp(0.0, screenWidth * 0.9);
      return Padding(
        padding: MediaQuery.viewInsetsOf(drawerContext),
        child: MediaQuery.removeViewInsets(
          context: drawerContext,
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          child: Align(
            alignment: Alignment.centerLeft,
            child: MediaReadableSurface(
              surfaceKey: surfaceKey,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(AppVisualTokens.sheetRadius),
              ),
              child: SafeArea(
                right: false,
                child: SizedBox(
                  width: drawerWidth,
                  height: double.infinity,
                  child: scrollable
                      ? SingleChildScrollView(
                          padding: contentPadding,
                          child: Builder(builder: builder),
                        )
                      : Padding(
                          padding: contentPadding,
                          child: Builder(builder: builder),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    ),
  );
}

Future<T?> showMediaGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxContentHeightFactor = 0.74,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.fromLTRB(18, 8, 18, 8),
  GlassQuality? quality,
  MediaGlassSheetAppearance appearance = MediaGlassSheetAppearance.readable,
  bool barrierDismissible = true,
  bool contentHandlesScrolling = false,
}) {
  assert(maxContentHeightFactor > 0 && maxContentHeightFactor <= 1);
  final readable =
      appearance == MediaGlassSheetAppearance.readable ||
      _shouldForceReadableModal(context, quality);
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
      // Consume the IME before aligning and constraining the sheet. Padding
      // follows the platform's inset animation, keeping caret reveal in sync.
      return Padding(
        padding: MediaQuery.viewInsetsOf(sheetContext),
        child: MediaQuery.removeViewInsets(
          context: sheetContext,
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxContentHeight =
                      (MediaQuery.sizeOf(context).height *
                              maxContentHeightFactor)
                          .clamp(0.0, constraints.maxHeight);
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: readable
                        ? _ReadableMediaSheet(
                            maxContentHeight: maxContentHeight,
                            contentHandlesScrolling: contentHandlesScrolling,
                            contentPadding: contentPadding,
                            child: builder(context),
                          )
                        : ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: maxContentHeight,
                            ),
                            child: cupertino.CupertinoTheme(
                              data: cupertino.CupertinoThemeData(
                                brightness: Theme.of(context).brightness,
                              ),
                              child: GlassSheet(
                                quality: quality,
                                topBorderRadius: AppVisualTokens.sheetRadius,
                                bottomBorderRadius: AppVisualTokens.sheetRadius,
                                margin: EdgeInsets.zero,
                                padding: contentPadding,
                                suppressInteractionOnChildren: true,
                                enableSaturationGlow: false,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: GlassInteractionSilence(
                                    child: builder(context),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  );
                },
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
    required this.contentHandlesScrolling,
    required this.contentPadding,
    required this.child,
  });

  final double maxContentHeight;
  final bool contentHandlesScrolling;
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
                      color: visualTheme.textSecondary.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: contentHandlesScrolling
                    ? Padding(padding: contentPadding, child: child)
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: contentPadding,
                        child: child,
                      ),
              ),
            ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final borderColor = highContrast
        ? visualTheme.glassBorder
        : (isDark ? const Color(0x38FFFFFF) : const Color(0x26000000));
    return Material(
      key: surfaceKey,
      color: visualTheme.opaqueGlassFallback,
      elevation: 16,
      shadowColor: visualTheme.shadow.withValues(alpha: isDark ? 0.9 : 0.45),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: borderColor, width: highContrast ? 1.5 : 1.0),
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
  MediaGlassDialogAppearance appearance = MediaGlassDialogAppearance.readable,
}) {
  assert(actions.isNotEmpty && actions.length <= 3);
  final visualTheme = AppVisualTheme.of(context);
  final readable =
      appearance == MediaGlassDialogAppearance.readable ||
      _shouldForceReadableModal(context, quality);
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
      return cupertino.CupertinoTheme(
        data: cupertino.CupertinoThemeData(
          brightness: Theme.of(dialogContext).brightness,
        ),
        child: GlassDialog(
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
        ),
      );
    },
  );
}

/// Opaque, theme-backed dialog used when the content must remain readable over
/// image-rich app surfaces.
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: MediaReadableSurface(
              surfaceKey: const ValueKey<String>(
                'media-readable-glass-dialog',
              ),
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
                    if (message != null || content != null) ...[
                      const SizedBox(height: 10),
                      Flexible(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message != null)
                                Text(
                                  message!,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: visualTheme.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              if (content != null) ...[
                                if (message != null) const SizedBox(height: 10),
                                content!,
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _buildActions(context),
                  ],
                ),
              ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    void onPressed() {
      Navigator.of(context).pop(action.value);
    }

    if (action.isDestructive) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: visualTheme.destructive,
          foregroundColor: isDark ? const Color(0xFF2B070B) : Colors.white,
        ),
        child: Text(action.label),
      );
    }
    if (action.isPrimary) {
      return FilledButton(onPressed: onPressed, child: Text(action.label));
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(
          AppVisualTokens.minimumTapTarget,
          AppVisualTokens.minimumTapTarget,
        ),
        foregroundColor: visualTheme.textPrimary,
        backgroundColor: visualTheme.surfaceRaised,
        side: BorderSide(
          color: highContrast ? visualTheme.textPrimary : visualTheme.divider,
          width: highContrast ? 1.5 : 1.0,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppVisualTokens.controlRadius),
          ),
        ),
      ),
      child: Text(action.label),
    );
  }
}
