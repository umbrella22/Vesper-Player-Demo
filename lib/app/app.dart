import 'dart:async';

import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'design/app_theme_controller.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';

typedef AppSystemUiStyleBuilder =
    SystemUiOverlayStyle Function(Brightness brightness);

/// 单供应商应用与通用 Material 壳之间的静态装配。
///
/// 供应商在 `lib/platform_app.dart` 创建该对象。未提供 [tvModeListenable]
/// 时应用固定使用手机布局；其余系统呈现策略也都有通用缺省值。
@immutable
final class VesperAppHost {
  const VesperAppHost({
    required this.homeBuilder,
    this.appTitle = 'Vesper',
    this.tvModeListenable,
    this.refreshPreferredOrientations,
    this.tvSystemUiStyle,
    this.systemUiStyleForBrightness,
  });

  final String appTitle;
  final WidgetBuilder homeBuilder;
  final ValueListenable<bool>? tvModeListenable;
  final Future<void> Function()? refreshPreferredOrientations;
  final SystemUiOverlayStyle? tvSystemUiStyle;
  final AppSystemUiStyleBuilder? systemUiStyleForBrightness;
}

class VesperApp extends StatefulWidget {
  const VesperApp({
    super.key,
    required this.host,
    this.appSettings = const AppSettingsStore(),
    this.initialThemePreference = AppThemePreference.system,
  });

  final VesperAppHost host;
  final AppSettingsStore appSettings;
  final AppThemePreference initialThemePreference;

  @override
  State<VesperApp> createState() => _VesperAppState();
}

class _VesperAppState extends State<VesperApp> with WidgetsBindingObserver {
  late final AppThemeController _themeController;

  @override
  void initState() {
    super.initState();
    _themeController = AppThemeController(
      settings: widget.appSettings,
      initialPreference: widget.initialThemePreference,
    );
    WidgetsBinding.instance.addObserver(this);
    _refreshPreferredOrientations();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPreferredOrientations();
    }
  }

  void _refreshPreferredOrientations() {
    final refresh = widget.host.refreshPreferredOrientations;
    if (refresh != null) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    return AppThemeScope(
      controller: _themeController,
      child: ListenableBuilder(
        listenable: _themeController,
        builder: (context, _) {
          final tvModeListenable = widget.host.tvModeListenable;
          if (tvModeListenable == null) {
            return _buildMaterialApp(false, disableAnimations);
          }
          return ValueListenableBuilder<bool>(
            valueListenable: tvModeListenable,
            builder: (context, isTvMode, _) =>
                _buildMaterialApp(isTvMode, disableAnimations),
          );
        },
      ),
    );
  }

  Widget _buildMaterialApp(bool isTvMode, bool disableAnimations) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: widget.host.appTitle,
      theme: isTvMode
          ? AppVisualTokens.tvTheme()
          : AppVisualTokens.mobileLightTheme(),
      darkTheme: isTvMode
          ? AppVisualTokens.tvTheme()
          : AppVisualTokens.mobileDarkTheme(),
      highContrastTheme: isTvMode
          ? AppVisualTokens.mobileDarkHighContrastTheme()
          : AppVisualTokens.mobileLightHighContrastTheme(),
      highContrastDarkTheme: AppVisualTokens.mobileDarkHighContrastTheme(),
      themeMode: isTvMode ? ThemeMode.dark : _themeController.themeMode,
      themeAnimationDuration: disableAnimations
          ? Duration.zero
          : AppVisualTokens.overlayDuration,
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        final theme = Theme.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: isTvMode
              ? widget.host.tvSystemUiStyle ??
                    mediaSystemUiStyleForBrightness(Brightness.dark)
              : widget.host.systemUiStyleForBrightness?.call(
                      theme.brightness,
                    ) ??
                    mediaSystemUiStyleForBrightness(theme.brightness),
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: Builder(builder: widget.host.homeBuilder),
    );
  }
}
