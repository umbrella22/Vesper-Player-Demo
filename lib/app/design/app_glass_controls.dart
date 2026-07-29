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
    final resolvedBackgroundColor =
        backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: GlassScaffold(
        body: _materialSurface(body),
        appBar: appBar == null ? null : _materialAppBarSurface(appBar!),
        bottomBar: bottomBar == null ? null : _materialSurface(bottomBar!),
        // GlassScaffold only makes its legacy Material scaffold transparent
        // when a background widget is present. Passing backgroundColor leaks
        // the legacy light fallback through material_ui dark themes.
        background: ColoredBox(color: resolvedBackgroundColor),
        enableBackgroundSampling: false,
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
    final visualTheme = AppVisualTheme.of(context);
    final foreground = enabled
        ? (primary ? Colors.white : Theme.of(context).colorScheme.onSurface)
        : Theme.of(context).disabledColor;
    return GlassButton.custom(
      onTap: onPressed,
      enabled: enabled,
      label: label,
      width: width,
      height: AppVisualTokens.minimumTapTarget,
      interactionScale: AppVisualTokens.interactionScale(
        context,
        AppVisualTokens.pressedScale,
      ),
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
            : visualTheme.glassTint,
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
    this.quality,
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
  final GlassQuality? quality;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    if (highContrast) {
      return _OpaqueNavigationBar(
        items: items,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        height: barHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      );
    }
    final inheritedQuality =
        quality ?? GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
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
      settings: LiquidGlassSettings(
        blur: 12,
        thickness: 14,
        glassColor: visualTheme.glassTint,
        lightIntensity: 0.55,
        saturation: 1.04,
      ),
      indicatorColor: visualTheme.neutralSelection,
      selectedIconColor: visualTheme.textPrimary,
      selectedLabelColor: visualTheme.textPrimary,
      unselectedIconColor: visualTheme.textSecondary,
      unselectedLabelColor: visualTheme.textSecondary,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      quality: inheritedQuality,
      maskingQuality: MaskingQuality.high,
      magnification: 1.12,
      innerBlur: 0.5,
      glowOpacity: 0.38,
      glowBlurRadius: 26,
      glowSpreadRadius: 5,
      interactionGlowColor: const Color(0x1FFFFFFF),
      pressScale: AppVisualTokens.interactionScale(
        context,
        AppVisualTokens.pressedScale,
      ),
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
    this.quality,
  });

  static const double height = 52;
  static const ValueKey<String> navigationKey = ValueKey<String>(
    'app-glass-section-tabs',
  );

  final List<AppGlassNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final GlassQuality? quality;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    if (highContrast) {
      return _OpaqueNavigationBar(
        items: items,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        height: 48,
        padding: EdgeInsets.zero,
      );
    }
    final inheritedQuality =
        quality ?? GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
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
      settings: LiquidGlassSettings(
        blur: 10,
        thickness: 12,
        glassColor: visualTheme.glassTint,
        lightIntensity: 0.5,
        saturation: 1.02,
      ),
      indicatorColor: visualTheme.neutralSelection,
      selectedIconColor: visualTheme.textPrimary,
      selectedLabelColor: visualTheme.textPrimary,
      unselectedIconColor: visualTheme.textSecondary,
      unselectedLabelColor: visualTheme.textSecondary,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      quality: inheritedQuality,
      maskingQuality: MaskingQuality.high,
      magnification: 1.12,
      innerBlur: 0.5,
      glowOpacity: 0.38,
      glowBlurRadius: 26,
      glowSpreadRadius: 5,
      pressScale: AppVisualTokens.interactionScale(
        context,
        AppVisualTokens.pressedScale,
      ),
      interactionGlowColor: const Color(0x1FFFFFFF),
    );

    return tabBar;
  }
}

class _OpaqueNavigationBar extends StatelessWidget {
  const _OpaqueNavigationBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.height,
    required this.padding,
  });

  final List<AppGlassNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: padding,
      child: Material(
        color: visualTheme.opaqueGlassFallback,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: visualTheme.glassBorder),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: Semantics(
                    selected: index == selectedIndex,
                    button: true,
                    label: items[index].semanticLabel ?? items[index].label,
                    child: InkWell(
                      onTap: () => onSelected(index),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: index == selectedIndex
                              ? visualTheme.neutralSelection
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(height / 2 - 4),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                index == selectedIndex
                                    ? items[index].activeIcon ??
                                          items[index].icon
                                    : items[index].icon,
                                size: 20,
                                color: index == selectedIndex
                                    ? visualTheme.textPrimary
                                    : visualTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  items[index].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: index == selectedIndex
                                        ? visualTheme.textPrimary
                                        : visualTheme.textSecondary,
                                    fontWeight: index == selectedIndex
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppGroupedSurface extends StatelessWidget {
  const AppGroupedSurface({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    assert(children.isNotEmpty);
    final visualTheme = AppVisualTheme.of(context);
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    return Material(
      color: visualTheme.surface,
      shape: RoundedRectangleBorder(
        side: highContrast
            ? BorderSide(color: visualTheme.textPrimary, width: 1.5)
            : BorderSide.none,
        borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 64,
                  color: visualTheme.divider,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppSettingsRow extends StatelessWidget {
  const AppSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final foreground = destructive
        ? visualTheme.destructive
        : visualTheme.textPrimary;
    return Semantics(
      button: onTap != null,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                AppIconTile(
                  icon: icon,
                  color: iconColor ?? foreground,
                  muted: !enabled,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: enabled
                              ? foreground
                              : visualTheme.textTertiary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: visualTheme.textSecondary,
                                height: 1.3,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                trailing ??
                    Icon(
                      Icons.chevron_right_rounded,
                      color: visualTheme.textTertiary,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.muted = false,
    this.size = 38,
  });

  final IconData icon;
  final Color color;
  final bool muted;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visualTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 21,
          color: muted ? visualTheme.textTertiary : color,
        ),
      ),
    );
  }
}

class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: visualTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
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
