// Vesper Stage 播放控制条的应用级皮肤（vesper_player_ui >= 0.6.4）。
//
// [AppStageIcons] 是播放条与手势 HUD 图标的唯一声明点，图形来自
// [AppIcons]（Remix Icon 线性集）；Stage 的内置按钮、注入按钮与手势
// HUD 全部跟随，无需改调用点。
//
// metrics 只覆写偏离 20/22/24 图标网格的 SDK 默认值（navigation 23、
// expandedFullscreen 19），其余尺寸沿用 SDK 缺省。
import 'package:flutter/widgets.dart' show IconData;
import 'package:vesper_media/media/design/app_icons.dart';
import 'package:vesper_player_ui/vesper_player_ui.dart';

abstract final class AppStageIcons {
  static const IconData play = AppIcons.playFill;
  static const IconData pause = AppIcons.pauseFill;
  static const IconData fullscreen = AppIcons.fullscreenLine;
  static const IconData exitFullscreen = AppIcons.fullscreenExitFill;
  static const IconData navigateBack = AppIcons.arrowLeftLine;
  static const IconData more = AppIcons.more2Fill;
  static const IconData brightness = AppIcons.sunLine;
  static const IconData volume = AppIcons.volumeUpLine;
  static const IconData speed = AppIcons.speedLine;
}

const VesperPlayerStageSkin appPlayerStageSkin = VesperPlayerStageSkin(
  icons: VesperPlayerStageIcons(
    play: AppStageIcons.play,
    pause: AppStageIcons.pause,
    fullscreen: AppStageIcons.fullscreen,
    exitFullscreen: AppStageIcons.exitFullscreen,
    navigateBack: AppStageIcons.navigateBack,
    more: AppStageIcons.more,
    brightness: AppStageIcons.brightness,
    volume: AppStageIcons.volume,
    speed: AppStageIcons.speed,
  ),
  metrics: VesperStageMetrics(
    navigation: VesperStageButtonStyle(
        size: 38, iconSize: 22, backgroundOpacity: 0),
    expandedFullscreen: VesperStageButtonStyle(
        size: 34, iconSize: 20, backgroundOpacity: 0),
  ),
);
