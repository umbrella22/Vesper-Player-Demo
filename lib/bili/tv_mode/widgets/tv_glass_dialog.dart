import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'package:bilibili_player/app/design/app_visual_theme.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_directional_focus_scope.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_focusable.dart';

final class BiliTvDialogAction<T> {
  const BiliTvDialogAction({
    required this.label,
    required this.value,
    required this.icon,
    this.autofocus = false,
    this.isDestructive = false,
  });

  final String label;
  final T value;
  final IconData icon;
  final bool autofocus;
  final bool isDestructive;
}

typedef BiliTvGlassOverlayBuilder =
    Widget Function(BuildContext context, VoidCallback dismiss);

Future<T?> showBiliTvGlassOverlay<T>({
  required BuildContext context,
  required BiliTvGlassOverlayBuilder builder,
  double maxWidth = 560,
  String debugLabel = 'tv_dialog',
}) {
  assert(maxWidth > 0);
  final transitionDuration = AppVisualTokens.motionDuration(
    context,
    AppVisualTokens.overlayDuration,
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0xB8000000),
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
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      void dismiss() => Navigator.of(dialogContext).pop();

      return Theme(
        data: AppVisualTokens.darkTheme(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Semantics(
                  namesRoute: true,
                  scopesRoute: true,
                  explicitChildNodes: true,
                  child: TvDirectionalFocusScope(
                    autofocus: false,
                    // Android dispatches KEYCODE_BACK as both a key event and
                    // a route pop. Let the modal route consume it once.
                    handleGoBackKey: false,
                    onBack: dismiss,
                    debugLabel: debugLabel,
                    child: Material(
                      type: MaterialType.transparency,
                      child: builder(dialogContext, dismiss),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<T?> showBiliTvGlassDialog<T>({
  required BuildContext context,
  required String title,
  required String message,
  required IconData icon,
  required List<BiliTvDialogAction<T>> actions,
  double maxWidth = 560,
}) {
  assert(actions.isNotEmpty && actions.length <= 3);
  assert(actions.where((action) => action.autofocus).length <= 1);
  final hasExplicitAutofocus = actions.any((action) => action.autofocus);
  final defaultAutofocusIndex = hasExplicitAutofocus
      ? -1
      : actions.indexWhere((action) => !action.isDestructive);
  return showBiliTvGlassOverlay<T>(
    context: context,
    maxWidth: maxWidth,
    builder: (dialogContext, dismiss) => BiliTvGlassDialogSurface(
      title: title,
      message: message,
      icon: icon,
      footer: Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: 14),
            Expanded(
              child: BiliTvDialogButton(
                label: actions[index].label,
                icon: actions[index].icon,
                autofocus:
                    actions[index].autofocus || index == defaultAutofocusIndex,
                isDestructive: actions[index].isDestructive,
                onTap: () =>
                    Navigator.of(dialogContext).pop(actions[index].value),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class BiliTvGlassDialogSurface extends StatelessWidget {
  const BiliTvGlassDialogSurface({
    super.key,
    required this.title,
    required this.icon,
    this.message,
    this.content,
    this.footer,
    this.scrollController,
    this.surfaceKey = const ValueKey<String>('bili-tv-dialog-surface'),
  });

  final String title;
  final IconData icon;
  final String? message;
  final Widget? content;
  final Widget? footer;
  final ScrollController? scrollController;
  final Key surfaceKey;

  @override
  Widget build(BuildContext context) {
    const outerRadius = 26.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(outerRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            key: surfaceKey,
            decoration: BoxDecoration(
              color: const Color(0xF01A1C22),
              borderRadius: BorderRadius.circular(outerRadius),
              border: Border.all(color: const Color(0x38FFFFFF)),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(30, 28, 30, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0x18FFFFFF),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          icon,
                          color: const Color(0xE6FFFFFF),
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (message case final value?) ...[
                    const SizedBox(height: 18),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xC7FFFFFF),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (content case final value?) ...[
                    const SizedBox(height: 22),
                    value,
                  ],
                  if (footer case final value?) ...[
                    const SizedBox(height: 28),
                    value,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BiliTvDialogButton extends StatelessWidget {
  const BiliTvDialogButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.autofocus = false,
    this.isDestructive = false,
    this.enabled = true,
    this.debugLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;
  final bool isDestructive;
  final bool enabled;
  final String? debugLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedDebugLabel = debugLabel ?? 'tv_dialog_$label';
    if (!enabled) {
      return Semantics(
        button: true,
        enabled: false,
        label: label,
        excludeSemantics: true,
        child: _buildSurface(context, focused: false, enabled: false),
      );
    }
    return Semantics(
      button: true,
      enabled: true,
      label: label,
      excludeSemantics: true,
      child: TvGlassSelectable(
        autofocus: autofocus,
        debugLabel: resolvedDebugLabel,
        borderRadius: 14,
        scale: 1.025,
        onTap: onTap,
        builder: (context, state) {
          final focused =
              state == TvGlassSelectableState.focused ||
              state == TvGlassSelectableState.pressed;
          return _buildSurface(context, focused: focused, enabled: true);
        },
      ),
    );
  }

  Widget _buildSurface(
    BuildContext context, {
    required bool focused,
    required bool enabled,
  }) {
    final foreground = !enabled
        ? const Color(0x61FFFFFF)
        : isDestructive
        ? const Color(0xFFFFB4AB)
        : Colors.white;
    return AnimatedContainer(
      key: ValueKey<String>('bili-tv-dialog-action-$label'),
      duration: AppVisualTokens.motionDuration(
        context,
        AppVisualTokens.tvFocusDuration,
      ),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: !enabled
            ? const Color(0x0AFFFFFF)
            : focused
            ? const Color(0x26FFFFFF)
            : isDestructive
            ? const Color(0x16FF6B63)
            : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: !enabled
              ? const Color(0x12FFFFFF)
              : focused
              ? const Color(0xB3FFFFFF)
              : isDestructive
              ? const Color(0x42FF8A83)
              : const Color(0x24FFFFFF),
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: foreground, size: 22),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
