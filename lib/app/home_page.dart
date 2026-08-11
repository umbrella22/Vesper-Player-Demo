import 'package:flutter/widgets.dart';

import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/app/services/bili_ui_mode_controller.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_hub_page.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/common/services/bili_ui_mode_resolver.dart';
import 'package:vesper_media/bili/tv_mode/pages/bili_tv_home_page.dart';
import 'package:vesper_media/download/services/offline_download_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.uiModeController,
    this.client,
    this.historyStore,
    this.sessionStore,
    this.offlineController,
    this.appSettings,
  }) : _ownsUiModeController = false;

  const HomePage.owningUiModeController({
    super.key,
    required BiliUiModeController this.uiModeController,
    this.client,
    this.historyStore,
    this.sessionStore,
    this.offlineController,
    this.appSettings,
  }) : _ownsUiModeController = true;

  final BiliUiModeController? uiModeController;
  final BiliClient? client;
  final BiliHistoryStore? historyStore;
  final BiliSessionStore? sessionStore;
  final BiliOfflineDownloadController? offlineController;
  final AppSettingsStore? appSettings;
  final bool _ownsUiModeController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final BiliUiModeController _uiModeController;

  @override
  void initState() {
    super.initState();
    _uiModeController =
        widget.uiModeController ??
        BiliUiModeController(
          resolver: BiliUiModeResolver(appSettings: widget.appSettings),
        );
  }

  @override
  void dispose() {
    if (widget.uiModeController == null || widget._ownsUiModeController) {
      _uiModeController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _uiModeController.tvModeListenable,
      builder: (context, isTvMode, _) {
        if (isTvMode) {
          return BiliTvHomePage(
            client: widget.client,
            historyStore: widget.historyStore,
            sessionStore: widget.sessionStore,
            offlineController: widget.offlineController,
            appSettings: widget.appSettings,
            uiModeController: _uiModeController,
          );
        }
        return BiliHubPage(
          client: widget.client,
          historyStore: widget.historyStore,
          sessionStore: widget.sessionStore,
          offlineController: widget.offlineController,
          appSettings: widget.appSettings,
          uiModeController: _uiModeController,
        );
      },
    );
  }
}
