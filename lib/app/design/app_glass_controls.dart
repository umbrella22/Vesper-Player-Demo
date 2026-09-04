import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/media/design/app_visual_theme.dart';

/// Bridges App-owned split `material_ui` surfaces into Liquid Glass's
/// Cupertino-only scaffold without coupling either package to legacy Material.
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
    this.resizeToAvoidBottomInset = false,
  });

  final Widget body;
  final Widget? appBar;
  final Widget? bottomBar;
  final Color? backgroundColor;
  final GlassStatusBarStyle statusBarStyle;
  final bool extendBody;
  final double appBarHeight;
  final double? bottomBarHeight;
  final bool resizeToAvoidBottomInset;

  static const double _keyboardVisibilityInset = 0.01;

  @override
  Widget build(BuildContext context) {
    final resolvedBackgroundColor =
        backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    final ambientMediaQuery = MediaQuery.maybeOf(context);
    final resolvedBottomBar = bottomBar == null
        ? null
        : _materialBottomBarSurface(
            bottomBar!,
            ambientMediaQuery,
            scaffoldHandlesKeyboard: resizeToAvoidBottomInset,
          );
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: GlassScaffold(
        body: _materialSurface(body),
        appBar: appBar == null ? null : _materialAppBarSurface(appBar!),
        bottomBar: resolvedBottomBar,
        // Liquid Glass is Material-decoupled, so resolve the App's split
        // material_ui scaffold color explicitly.
        backgroundColor: resolvedBackgroundColor,
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

  static Widget _materialBottomBarSurface(
    Widget child,
    MediaQueryData? mediaQuery, {
    required bool scaffoldHandlesKeyboard,
  }) {
    final surface = _materialSurface(child);
    if (mediaQuery == null) {
      return surface;
    }
    final keyboardVisible = mediaQuery.viewInsets.bottom > 0;
    final effectiveMediaQuery = scaffoldHandlesKeyboard && keyboardVisible
        ? mediaQuery.copyWith(
            // The resized Scaffold already places the bar above the IME. Keep
            // only a visibility signal so the bar can reserve its keyboard
            // actions without applying the full inset a second time.
            viewInsets: mediaQuery.viewInsets.copyWith(
              bottom: _keyboardVisibilityInset,
            ),
          )
        : mediaQuery;
    return MediaQuery(data: effectiveMediaQuery, child: surface);
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

@immutable
final class AppGlassNavigationSearchConfig {
  const AppGlassNavigationSearchConfig({
    required this.controller,
    required this.focusNode,
    required this.isActive,
    required this.isLoading,
    required this.onActiveChanged,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    this.hintText = '搜索视频、BV 号或链接',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isActive;
  final bool isLoading;
  final ValueChanged<bool> onActiveChanged;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final String hintText;
}

class AppGlassBottomNavigation extends StatelessWidget {
  const AppGlassBottomNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.quality,
    this.search,
    this.minimizeController,
    this.scrollController,
  });

  static const double barHeight = 50;
  static const double compactBarHeight = barHeight;
  static const double verticalPadding = 8;
  static const double extent = barHeight + verticalPadding * 2;
  static const double contentSpacing = 12;
  static const double tabItemWidth = 88;
  static const double _indicatorBorderRadius = 21;
  static const EdgeInsets _indicatorExpansion = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 3,
  );
  static const TextStyle _selectedLabelStyle = TextStyle(
    fontWeight: FontWeight.w800,
  );
  static const TextStyle _unselectedLabelStyle = TextStyle(
    fontWeight: FontWeight.w700,
  );
  static const Color _interactionGlowColor = Color(0x1FFFFFFF);
  static const ValueKey<String> navigationKey = ValueKey<String>(
    'app-glass-bottom-navigation',
  );
  static const ValueKey<String> searchButtonKey = ValueKey<String>(
    'app-glass-bottom-search-button',
  );
  static const ValueKey<String> searchFieldKey = ValueKey<String>(
    'app-glass-bottom-search-field',
  );
  static const ValueKey<String> searchExitButtonKey = ValueKey<String>(
    'app-glass-bottom-search-exit',
  );
  static const ValueKey<String> searchClearButtonKey = ValueKey<String>(
    'app-glass-bottom-search-clear',
  );
  static const ValueKey<String> searchDismissButtonKey = ValueKey<String>(
    'app-glass-bottom-search-dismiss',
  );
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
  final AppGlassNavigationSearchConfig? search;
  final GlassTabBarMinimizeController? minimizeController;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    if (highContrast) {
      return _OpaqueMinimizeObserver(
        minimizeController: minimizeController,
        scrollController: search?.isActive == true ? null : scrollController,
        child: _OpaqueBottomNavigation(
          items: items,
          selectedIndex: selectedIndex,
          onSelected: onSelected,
          search: search,
          minimizeController: minimizeController,
        ),
      );
    }
    final inheritedQuality =
        quality ?? GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
    final tabs = _buildTabs();
    final searchConfig = search;
    if (searchConfig != null &&
        (searchConfig.isActive || minimizeController == null)) {
      return _buildSearchableBar(
        context,
        visualTheme: visualTheme,
        inheritedQuality: inheritedQuality,
        tabs: tabs,
        search: searchConfig,
      );
    }
    if (minimizeController != null) {
      return _buildMinimizableBar(
        context,
        visualTheme: visualTheme,
        inheritedQuality: inheritedQuality,
        tabs: tabs,
        search: searchConfig,
      );
    }
    return GlassTabBar.bottom(
      key: navigationKey,
      tabs: tabs,
      selectedIndex: selectedIndex,
      onTabSelected: onSelected,
      horizontalPadding: 16,
      verticalPadding: verticalPadding,
      barHeight: barHeight,
      barBorderRadius: barHeight / 2,
      indicatorBorderRadius: _indicatorBorderRadius,
      indicatorExpansion: _indicatorExpansion,
      settings: _glassSettings(visualTheme),
      indicatorColor: visualTheme.neutralSelection,
      selectedIconColor: visualTheme.textPrimary,
      selectedLabelColor: visualTheme.textPrimary,
      unselectedIconColor: visualTheme.textSecondary,
      unselectedLabelColor: visualTheme.textSecondary,
      selectedLabelStyle: _selectedLabelStyle,
      unselectedLabelStyle: _unselectedLabelStyle,
      quality: inheritedQuality,
      maskingQuality: MaskingQuality.high,
      magnification: 1.12,
      innerBlur: 0.5,
      glowOpacity: 0.38,
      glowBlurRadius: 26,
      glowSpreadRadius: 5,
      interactionGlowColor: _interactionGlowColor,
      pressScale: AppVisualTokens.interactionScale(
        context,
        AppVisualTokens.pressedScale,
      ),
    );
  }

  List<GlassTab> _buildTabs() {
    return [
      for (final item in items)
        GlassTab(
          icon: Icon(item.icon),
          activeIcon: Icon(item.activeIcon ?? item.icon),
          label: item.label,
          semanticLabel: item.semanticLabel ?? item.label,
        ),
    ];
  }

  Widget _buildMinimizableBar(
    BuildContext context, {
    required AppVisualTheme visualTheme,
    required GlassQuality? inheritedQuality,
    required List<GlassTab> tabs,
    required AppGlassNavigationSearchConfig? search,
  }) {
    return GlassTabBar.minimizable(
      key: navigationKey,
      tabs: tabs,
      selectedIndex: selectedIndex,
      onTabSelected: onSelected,
      minimizeController: minimizeController,
      scrollController: scrollController,
      onMinimizedTabTap: minimizeController?.expand,
      trailingButton: search == null
          ? null
          : GlassTabBarTrailingButton(
              icon: _buildSearchIcon(visualTheme),
              onTap: () => search.onActiveChanged(true),
            ),
      horizontalPadding: 16,
      verticalPadding: verticalPadding,
      barHeight: barHeight,
      minimizedBarHeight: compactBarHeight,
      barBorderRadius: barHeight / 2,
      indicatorBorderRadius: _indicatorBorderRadius,
      indicatorExpansion: _indicatorExpansion,
      settings: _glassSettings(visualTheme),
      indicatorColor: visualTheme.neutralSelection,
      selectedIconColor: visualTheme.textPrimary,
      selectedLabelColor: visualTheme.textPrimary,
      unselectedIconColor: visualTheme.textSecondary,
      unselectedLabelColor: visualTheme.textSecondary,
      selectedLabelStyle: _selectedLabelStyle,
      unselectedLabelStyle: _unselectedLabelStyle,
      quality: inheritedQuality,
      maskingQuality: MaskingQuality.high,
      magnification: 1.12,
      innerBlur: 0.5,
      glowOpacity: 0.38,
      glowBlurRadius: 26,
      glowSpreadRadius: 5,
      interactionGlowColor: _interactionGlowColor,
      pressScale: AppVisualTokens.interactionScale(
        context,
        AppVisualTokens.pressedScale,
      ),
      tabWidth: search == null ? null : tabItemWidth,
    );
  }

  Widget _buildSearchableBar(
    BuildContext context, {
    required AppVisualTheme visualTheme,
    required GlassQuality? inheritedQuality,
    required List<GlassTab> tabs,
    required AppGlassNavigationSearchConfig search,
  }) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final scaffoldHandlesKeyboard =
        keyboardInset == AppGlassScaffold._keyboardVisibilityInset;
    final showsKeyboardDismiss =
        scaffoldHandlesKeyboard && search.focusNode.hasFocus;
    final tabBar = GlassTabBar.searchable(
      key: navigationKey,
      tabs: tabs,
      selectedIndex: selectedIndex,
      onTabSelected: onSelected,
      isSearchActive: search.isActive,
      extraButton: showsKeyboardDismiss
          ? _buildKeyboardDismissButton(visualTheme, search.focusNode)
          : null,
      searchConfig: GlassSearchBarConfig(
        onSearchToggle: search.onActiveChanged,
        hintText: search.hintText,
        controller: search.controller,
        focusNode: search.focusNode,
        onChanged: search.onChanged,
        onSubmitted: search.onSubmitted,
        onTapOutside: (_) => search.focusNode.unfocus(),
        autoFocusOnExpand: false,
        showsCancelButton: !scaffoldHandlesKeyboard,
        searchIcon: search.isActive
            ? _buildSearchFieldIcon(visualTheme)
            : _buildSearchIcon(visualTheme),
        collapsedLogoBuilder: (_) => Semantics(
          key: searchExitButtonKey,
          label: '退出搜索',
          button: true,
          child: SizedBox.square(
            dimension: AppVisualTokens.minimumTapTarget,
            child: ExcludeSemantics(
              child: Icon(
                items[selectedIndex].activeIcon ?? items[selectedIndex].icon,
                color: visualTheme.textPrimary,
              ),
            ),
          ),
        ),
        searchIconColor: visualTheme.textSecondary,
        textColor: visualTheme.textPrimary,
        cursorColor: visualTheme.textPrimary,
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: visualTheme.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        trailingBuilder: (_) =>
            _buildSearchTrailing(visualTheme, search: search),
        textInputAction: TextInputAction.search,
        cancelButtonColor: visualTheme.textPrimary,
        cancelIcon: _buildKeyboardDismissIcon(visualTheme),
      ),
      scrollController: scrollController,
      horizontalPadding: 16,
      verticalPadding: verticalPadding,
      barHeight: barHeight,
      searchBarHeight: compactBarHeight,
      barBorderRadius: barHeight / 2,
      indicatorBorderRadius: _indicatorBorderRadius,
      indicatorExpansion: _indicatorExpansion,
      settings: _glassSettings(visualTheme),
      indicatorColor: visualTheme.neutralSelection,
      selectedIconColor: visualTheme.textPrimary,
      selectedLabelColor: visualTheme.textPrimary,
      unselectedIconColor: visualTheme.textSecondary,
      unselectedLabelColor: visualTheme.textSecondary,
      selectedLabelStyle: _selectedLabelStyle,
      unselectedLabelStyle: _unselectedLabelStyle,
      textStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      quality: inheritedQuality,
      maskingQuality: MaskingQuality.high,
      magnification: 1.12,
      innerBlur: 0.5,
      glowOpacity: 0.38,
      glowBlurRadius: 26,
      glowSpreadRadius: 5,
      interactionGlowColor: _interactionGlowColor,
      pressScale: AppVisualTokens.interactionScale(
        context,
        AppVisualTokens.pressedScale,
      ),
      tabWidth: tabItemWidth,
    );
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: scaffoldHandlesKeyboard,
      child: tabBar,
    );
  }

  GlassTabBarExtraButton _buildKeyboardDismissButton(
    AppVisualTheme visualTheme,
    FocusNode focusNode,
  ) {
    return GlassTabBarExtraButton(
      icon: _buildKeyboardDismissIcon(visualTheme),
      onTap: focusNode.unfocus,
      label: '关闭键盘',
      iconColor: visualTheme.textPrimary,
      size: compactBarHeight,
      position: GlassExtraButtonPosition.afterSearch,
      collapseOnSearchFocus: false,
    );
  }

  Widget _buildKeyboardDismissIcon(AppVisualTheme visualTheme) {
    return Semantics(
      key: searchDismissButtonKey,
      label: '关闭键盘',
      button: true,
      child: SizedBox.square(
        dimension: AppVisualTokens.minimumTapTarget,
        child: ExcludeSemantics(
          child: Icon(
            Icons.close_rounded,
            color: visualTheme.textPrimary,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchIcon(AppVisualTheme visualTheme) {
    return Semantics(
      key: searchButtonKey,
      label: '搜索',
      button: true,
      child: SizedBox.square(
        dimension: AppVisualTokens.minimumTapTarget,
        child: _buildSearchFieldIcon(visualTheme),
      ),
    );
  }

  Widget _buildSearchFieldIcon(AppVisualTheme visualTheme) {
    return ExcludeSemantics(
      child: Icon(Icons.search_rounded, color: visualTheme.textSecondary),
    );
  }

  Widget _buildSearchTrailing(
    AppVisualTheme visualTheme, {
    required AppGlassNavigationSearchConfig search,
  }) {
    if (search.isLoading) {
      return Semantics(
        label: '正在搜索',
        liveRegion: true,
        child: const SizedBox.square(
          dimension: AppVisualTokens.minimumTapTarget,
          child: Center(
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    if (search.controller.text.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox.square(
      dimension: AppVisualTokens.minimumTapTarget,
      child: AppPressScale(
        child: IconButton(
          key: searchClearButtonKey,
          tooltip: '清空搜索',
          onPressed: search.onClear,
          padding: EdgeInsets.zero,
          icon: Icon(
            Icons.cancel_rounded,
            color: visualTheme.textSecondary,
            size: 20,
          ),
        ),
      ),
    );
  }

  LiquidGlassSettings _glassSettings(AppVisualTheme visualTheme) {
    return LiquidGlassSettings(
      blur: 12,
      thickness: 14,
      glassColor: visualTheme.glassTint,
      lightIntensity: 0.55,
      saturation: 1.04,
    );
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

class _OpaqueBottomNavigation extends StatelessWidget {
  const _OpaqueBottomNavigation({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.search,
    required this.minimizeController,
  });

  final List<AppGlassNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final AppGlassNavigationSearchConfig? search;
  final GlassTabBarMinimizeController? minimizeController;

  @override
  Widget build(BuildContext context) {
    if (search == null && minimizeController == null) {
      return _OpaqueNavigationBar(
        items: items,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        height: AppGlassBottomNavigation.barHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      );
    }

    final listenables = <Listenable>[
      ?minimizeController,
      ?search?.focusNode,
      ?search?.controller,
    ];
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) => _buildReactiveBar(context),
    );
  }

  Widget _buildReactiveBar(BuildContext context) {
    final searchConfig = search;
    final searchActive = searchConfig?.isActive ?? false;
    final minimized = !searchActive && (minimizeController?.minimized ?? false);
    final bar = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: AppGlassBottomNavigation.verticalPadding,
      ),
      child: SizedBox(
        height: AppGlassBottomNavigation.barHeight,
        child: searchActive
            ? _buildSearchMode(context, searchConfig!)
            : _buildNavigationMode(context, minimized: minimized),
      ),
    );

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    if (!searchActive ||
        !searchConfig!.focusNode.hasFocus ||
        keyboardInset <= 0) {
      return bar;
    }
    return Transform.translate(offset: Offset(0, -keyboardInset), child: bar);
  }

  Widget _buildNavigationMode(BuildContext context, {required bool minimized}) {
    if (minimized) {
      return Row(
        children: [
          _OpaqueCircleButton(
            label: '展开导航',
            icon: items[selectedIndex].activeIcon ?? items[selectedIndex].icon,
            foregroundColor: AppVisualTheme.of(context).textPrimary,
            selected: true,
            onTap: minimizeController!.expand,
          ),
          const Spacer(),
          if (search case final AppGlassNavigationSearchConfig searchConfig)
            _OpaqueCircleButton(
              key: AppGlassBottomNavigation.searchButtonKey,
              label: '搜索',
              icon: Icons.search_rounded,
              foregroundColor: AppVisualTheme.of(context).textSecondary,
              onTap: () => searchConfig.onActiveChanged(true),
            ),
        ],
      );
    }

    final searchConfig = search;
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth = searchConfig == null
            ? 0.0
            : AppGlassBottomNavigation.barHeight + 8;
        final maxNavigationWidth = constraints.maxWidth > searchWidth
            ? constraints.maxWidth - searchWidth
            : 0.0;
        final requestedNavigationWidth = searchConfig == null
            ? maxNavigationWidth
            : AppGlassBottomNavigation.tabItemWidth * items.length;
        final navigationWidth = requestedNavigationWidth < maxNavigationWidth
            ? requestedNavigationWidth
            : maxNavigationWidth;
        return Row(
          children: [
            SizedBox(
              width: navigationWidth,
              child: _OpaqueNavigationBar(
                items: items,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
                height: AppGlassBottomNavigation.barHeight,
                padding: EdgeInsets.zero,
              ),
            ),
            const Spacer(),
            if (searchConfig != null) ...[
              const SizedBox(width: 8),
              _OpaqueCircleButton(
                key: AppGlassBottomNavigation.searchButtonKey,
                label: '搜索',
                icon: Icons.search_rounded,
                foregroundColor: AppVisualTheme.of(context).textSecondary,
                size: AppGlassBottomNavigation.barHeight,
                onTap: () => searchConfig.onActiveChanged(true),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSearchMode(
    BuildContext context,
    AppGlassNavigationSearchConfig search,
  ) {
    final visualTheme = AppVisualTheme.of(context);
    return Row(
      children: [
        _OpaqueCircleButton(
          key: AppGlassBottomNavigation.searchExitButtonKey,
          label: '退出搜索',
          icon: items[selectedIndex].activeIcon ?? items[selectedIndex].icon,
          foregroundColor: visualTheme.textPrimary,
          selected: true,
          onTap: () => search.onActiveChanged(false),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Material(
            color: visualTheme.opaqueGlassFallback,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: visualTheme.glassBorder),
              borderRadius: BorderRadius.circular(
                AppGlassBottomNavigation.compactBarHeight / 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: AppGlassBottomNavigation.compactBarHeight,
              child: TextField(
                key: AppGlassBottomNavigation.searchFieldKey,
                controller: search.controller,
                focusNode: search.focusNode,
                onChanged: search.onChanged,
                onSubmitted: search.onSubmitted,
                onTapOutside: (_) => search.focusNode.unfocus(),
                textInputAction: TextInputAction.search,
                cursorColor: visualTheme.textPrimary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: visualTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: search.hintText,
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: visualTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: visualTheme.textSecondary,
                  ),
                  prefixIconConstraints: const BoxConstraints.tightFor(
                    width: AppVisualTokens.minimumTapTarget,
                    height: AppVisualTokens.minimumTapTarget,
                  ),
                  suffixIcon: _buildSearchTrailing(visualTheme, search),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: AppVisualTokens.minimumTapTarget,
                    minHeight: AppVisualTokens.minimumTapTarget,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (search.focusNode.hasFocus) ...[
          const SizedBox(width: 8),
          _OpaqueCircleButton(
            key: AppGlassBottomNavigation.searchDismissButtonKey,
            label: '关闭键盘',
            icon: Icons.close_rounded,
            foregroundColor: visualTheme.textPrimary,
            onTap: search.focusNode.unfocus,
          ),
        ],
      ],
    );
  }

  Widget? _buildSearchTrailing(
    AppVisualTheme visualTheme,
    AppGlassNavigationSearchConfig search,
  ) {
    if (search.isLoading) {
      return Semantics(
        label: '正在搜索',
        liveRegion: true,
        child: const SizedBox.square(
          dimension: AppVisualTokens.minimumTapTarget,
          child: Center(
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    if (search.controller.text.isEmpty) {
      return null;
    }
    return AppPressScale(
      child: IconButton(
        key: AppGlassBottomNavigation.searchClearButtonKey,
        tooltip: '清空搜索',
        onPressed: search.onClear,
        icon: Icon(
          Icons.cancel_rounded,
          color: visualTheme.textSecondary,
          size: 20,
        ),
      ),
    );
  }
}

/// Feeds fallback scroll samples without taking over the glass bar's
/// controller attachment, so a runtime contrast change cannot detach its
/// replacement.
class _OpaqueMinimizeObserver extends StatefulWidget {
  const _OpaqueMinimizeObserver({
    required this.minimizeController,
    required this.scrollController,
    required this.child,
  });

  final GlassTabBarMinimizeController? minimizeController;
  final ScrollController? scrollController;
  final Widget child;

  @override
  State<_OpaqueMinimizeObserver> createState() =>
      _OpaqueMinimizeObserverState();
}

class _OpaqueMinimizeObserverState extends State<_OpaqueMinimizeObserver> {
  var _needsBaseline = true;

  @override
  void initState() {
    super.initState();
    _attachScrollListener();
  }

  @override
  void didUpdateWidget(_OpaqueMinimizeObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minimizeController != widget.minimizeController ||
        oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_handleScroll);
      _attachScrollListener();
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_handleScroll);
    super.dispose();
  }

  void _attachScrollListener() {
    _needsBaseline = true;
    if (widget.minimizeController == null) {
      return;
    }
    widget.scrollController?.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _establishBaseline();
      }
    });
  }

  void _handleScroll() {
    final position = _singleScrollPosition;
    final controller = widget.minimizeController;
    if (position == null || controller == null) {
      _needsBaseline = true;
      return;
    }
    if (_needsBaseline) {
      _establishBaseline();
    }
    controller.handleSample(GlassTabBarScrollSample.fromPosition(position));
  }

  void _establishBaseline() {
    final position = _singleScrollPosition;
    final controller = widget.minimizeController;
    if (position == null || controller == null) {
      return;
    }
    final sample = GlassTabBarScrollSample.fromPosition(position);
    controller.handleSample(
      GlassTabBarScrollSample(
        pixels: sample.pixels,
        minScrollExtent: sample.minScrollExtent,
        maxScrollExtent: sample.maxScrollExtent,
        viewportDimension: sample.viewportDimension,
        direction: ScrollDirection.idle,
        outOfRange: sample.outOfRange,
      ),
    );
    _needsBaseline = false;
  }

  ScrollPosition? get _singleScrollPosition {
    final scrollController = widget.scrollController;
    if (scrollController == null ||
        !scrollController.hasClients ||
        scrollController.positions.length != 1) {
      return null;
    }
    final position = scrollController.positions.single;
    return position.hasContentDimensions ? position : null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _OpaqueCircleButton extends StatelessWidget {
  const _OpaqueCircleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.onTap,
    this.selected = false,
    this.size = AppGlassBottomNavigation.compactBarHeight,
  });

  final String label;
  final IconData icon;
  final Color foregroundColor;
  final VoidCallback onTap;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AppPressScale(
        child: Tooltip(
          message: label,
          child: Material(
            color: selected
                ? visualTheme.neutralSelection
                : visualTheme.opaqueGlassFallback,
            shape: CircleBorder(
              side: BorderSide(color: visualTheme.glassBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox.square(
              dimension: size,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Icon(icon, color: foregroundColor, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
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
                    child: AppPressScale(
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppPressScale extends StatefulWidget {
  const AppPressScale({super.key, required this.child});

  final Widget child;

  @override
  State<AppPressScale> createState() => _AppPressScaleState();
}

class _AppPressScaleState extends State<AppPressScale> {
  var _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed
            ? AppVisualTokens.interactionScale(
                context,
                AppVisualTokens.pressedScale,
              )
            : 1,
        duration: AppVisualTokens.motionDuration(
          context,
          AppVisualTokens.buttonPressDuration,
        ),
        curve: Curves.easeOut,
        child: widget.child,
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
