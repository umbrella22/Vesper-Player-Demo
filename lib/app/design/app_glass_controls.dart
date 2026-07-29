import 'dart:ui' as ui;

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'app_visual_theme.dart';

/// Keeps App-owned Material widgets on the split `material_ui` tree while
/// `liquid_glass_widgets` still builds its scaffold with Flutter's legacy
/// Material library. Remove this adapter once the package migrates.
class AppGlassScaffold extends StatelessWidget {
  const AppGlassScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomBar,
    this.backgroundColor,
    this.statusBarStyle = GlassStatusBarStyle.none,
    this.extendBody = true,
    this.appBarHeight = 44,
    this.bottomBarHeight,
  });

  final Widget body;
  final Widget? appBar;
  final Widget? bottomBar;
  final Color? backgroundColor;
  final GlassStatusBarStyle statusBarStyle;
  final bool extendBody;
  final double appBarHeight;
  final double? bottomBarHeight;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: GlassScaffold(
        body: _materialSurface(body),
        appBar: appBar == null ? null : _materialAppBarSurface(appBar!),
        bottomBar: bottomBar == null ? null : _materialSurface(bottomBar!),
        backgroundColor: backgroundColor,
        statusBarStyle: statusBarStyle,
        extendBody: extendBody,
        appBarHeight: appBarHeight,
        bottomBarHeight: bottomBarHeight,
      ),
    );
  }

  static Widget _materialSurface(Widget child) {
    return Material(type: MaterialType.transparency, child: child);
  }

  static Widget _materialAppBarSurface(Widget child) {
    final surface = _materialSurface(child);
    return switch (child) {
      final PreferredSizeWidget preferred => PreferredSize(
        preferredSize: preferred.preferredSize,
        child: surface,
      ),
      _ => surface,
    };
  }
}

class AppGlassButton extends StatelessWidget {
  const AppGlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    this.width,
    this.quality,
    this.primary = true,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool enabled;
  final double? width;
  final GlassQuality? quality;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? (primary ? Colors.white : Theme.of(context).colorScheme.onSurface)
        : Theme.of(context).disabledColor;
    return GlassButton.custom(
      onTap: onPressed,
      enabled: enabled,
      label: label,
      width: width,
      height: AppVisualTokens.minimumTapTarget,
      interactionScale: AppVisualTokens.pressedScale,
      stretch: 0.18,
      useOwnLayer: true,
      quality: quality,
      shape: const LiquidRoundedSuperellipse(
        borderRadius: AppVisualTokens.controlRadius,
      ),
      settings: LiquidGlassSettings(
        blur: 7,
        thickness: 18,
        glassColor: primary
            ? AppVisualTokens.primaryBlue40
            : Colors.white.withValues(alpha: 0.10),
        lightIntensity: 0.7,
        saturation: 1.15,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 19, color: foreground),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
final class AppGlassNavigationItem {
  const AppGlassNavigationItem({
    required this.label,
    required this.icon,
    this.activeIcon,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final IconData? activeIcon;
  final String? semanticLabel;
}

class AppGlassBottomNavigation extends StatelessWidget {
  const AppGlassBottomNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.quality = GlassQuality.premium,
  });

  static const double barHeight = 64;
  static const double verticalPadding = 12;
  static const double extent = barHeight + verticalPadding * 2;
  static const double contentSpacing = 12;
  static const ValueKey<String> contentClearanceKey = ValueKey<String>(
    'app-glass-bottom-content-clearance',
  );

  static double contentClearance(BuildContext context) {
    return extent + MediaQuery.paddingOf(context).bottom + contentSpacing;
  }

  final List<AppGlassNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final GlassQuality quality;

  @override
  Widget build(BuildContext context) {
    final tabBar = GlassTabBar.bottom(
      key: const ValueKey<String>('app-glass-bottom-navigation'),
      tabs: [
        for (final item in items)
          GlassTab(
            icon: Icon(item.icon),
            activeIcon: Icon(item.activeIcon ?? item.icon),
            label: item.label,
            semanticLabel: item.semanticLabel ?? item.label,
          ),
      ],
      selectedIndex: selectedIndex,
      onTabSelected: onSelected,
      horizontalPadding: 16,
      verticalPadding: verticalPadding,
      barHeight: barHeight,
      barBorderRadius: barHeight / 2,
      indicatorBorderRadius: 28,
      indicatorExpansion: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      indicatorColor: AppVisualTokens.neutralSelection,
      selectedIconColor: AppVisualTokens.textPrimary,
      selectedLabelColor: AppVisualTokens.textPrimary,
      unselectedIconColor: AppVisualTokens.textSecondary,
      unselectedLabelColor: AppVisualTokens.textSecondary,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      quality: quality,
      maskingQuality: MaskingQuality.high,
      magnification: 1.12,
      innerBlur: 0.5,
      glowOpacity: 0.38,
      glowBlurRadius: 26,
      glowSpreadRadius: 5,
      interactionGlowColor: const Color(0x1FFFFFFF),
    );

    return tabBar;
  }
}

class AppGlassSectionTabs extends StatelessWidget {
  const AppGlassSectionTabs({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.quality = GlassQuality.premium,
  });

  static const double height = 52;
  static const ValueKey<String> navigationKey = ValueKey<String>(
    'app-glass-section-tabs',
  );

  final List<AppGlassNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final GlassQuality quality;

  @override
  Widget build(BuildContext context) {
    final tabBar = GlassTabBar.inline(
      key: navigationKey,
      tabs: [
        for (final item in items)
          GlassTab(
            icon: Icon(item.icon),
            activeIcon: Icon(item.activeIcon ?? item.icon),
            label: item.label,
            semanticLabel: item.semanticLabel ?? item.label,
          ),
      ],
      selectedIndex: selectedIndex,
      onTabSelected: onSelected,
      barHeight: 48,
      barBorderRadius: 24,
      indicatorBorderRadius: 22,
      indicatorExpansion: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      indicatorColor: AppVisualTokens.neutralSelection,
      selectedIconColor: AppVisualTokens.textPrimary,
      selectedLabelColor: AppVisualTokens.textPrimary,
      unselectedIconColor: AppVisualTokens.textSecondary,
      unselectedLabelColor: AppVisualTokens.textSecondary,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      quality: quality,
      maskingQuality: MaskingQuality.high,
      magnification: 1.12,
      innerBlur: 0.5,
      glowOpacity: 0.38,
      glowBlurRadius: 26,
      glowSpreadRadius: 5,
      pressScale: AppVisualTokens.pressedScale,
      interactionGlowColor: const Color(0x1FFFFFFF),
    );

    return tabBar;
  }
}

class AppFrostedScrollAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const AppFrostedScrollAppBar({
    super.key,
    required this.scrollController,
    required this.child,
    this.height = 44,
    this.fadeStart = 8,
    this.fadeEnd = 56,
  }) : assert(fadeEnd > fadeStart);

  static const ValueKey<String> surfaceKey = ValueKey<String>(
    'app-frosted-scroll-app-bar-surface',
  );

  final ScrollController scrollController;
  final Widget child;
  final double height;
  final double fadeStart;
  final double fadeEnd;

  @override
  Size get preferredSize => Size.fromHeight(height);

  double _progress() {
    if (!scrollController.hasClients ||
        scrollController.positions.length != 1) {
      return 0;
    }
    return ((scrollController.offset - fadeStart) / (fadeEnd - fadeStart))
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: scrollController,
      builder: (context, child) {
        final progress = _progress();
        final blur = ui.lerpDouble(0, 18, progress)!;
        final surfaceAlpha = ui.lerpDouble(0, isDark ? 0.74 : 0.82, progress)!;
        final dividerAlpha = ui.lerpDouble(0, isDark ? 0.16 : 0.08, progress)!;
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: DecoratedBox(
                    key: surfaceKey,
                    decoration: BoxDecoration(
                      color: visualTheme.surface.withValues(
                        alpha: surfaceAlpha,
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: dividerAlpha),
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: child,
    );
  }
}
