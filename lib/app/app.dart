import 'dart:async';

import 'package:vesper_media/app/home_page.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/app/services/bili_ui_mode_controller.dart';
import 'package:vesper_media/app/system_presentation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_ui_mode_resolver.dart';
import 'package:vesper_media/download/services/offline_download_controller.dart';

import 'design/app_theme_controller.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';

class VesperApp extends StatefulWidget {
  const VesperApp({
    super.key,
    this.appSettings = const AppSettingsStore(),
    this.initialThemePreference = AppThemePreference.system,
    this.uiModeController,
    this.client,
    this.offlineController,
  });

  final AppSettingsStore appSettings;
  final AppThemePreference initialThemePreference;
  final BiliUiModeController? uiModeController;
  final BiliClient? client;
  final BiliOfflineDownloadController? offlineController;

  @override
  State<VesperApp> createState() => _VesperAppState();
}

class _VesperAppState extends State<VesperApp> with WidgetsBindingObserver {
  late final AppThemeController _themeController;
  late final BiliUiModeController _uiModeController;

  @override
  void initState() {
    super.initState();
    _themeController = AppThemeController(
      settings: widget.appSettings,
      initialPreference: widget.initialThemePreference,
    );
    _uiModeController =
        widget.uiModeController ??
        BiliUiModeController(
          resolver: BiliUiModeResolver(appSettings: widget.appSettings),
        );
    WidgetsBinding.instance.addObserver(this);
    unawaited(refreshBiliAppPreferredOrientationsIfActive());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshBiliAppPreferredOrientationsIfActive());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeController.dispose();
    if (widget.uiModeController == null) {
      _uiModeController.dispose();
    }
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
          return ValueListenableBuilder<bool>(
            valueListenable: _uiModeController.tvModeListenable,
            builder: (context, isTvMode, _) {
              return _buildMaterialApp(isTvMode, disableAnimations);
            },
          );
        },
      ),
    );
  }

  Widget _buildMaterialApp(bool isTvMode, bool disableAnimations) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vesper',
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
              ? biliTvSystemUiStyle
              : appSystemUiStyleForBrightness(theme.brightness),
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: HomePage(
        uiModeController: _uiModeController,
        client: widget.client,
        offlineController: widget.offlineController,
        appSettings: widget.appSettings,
      ),
    );
  }
}
