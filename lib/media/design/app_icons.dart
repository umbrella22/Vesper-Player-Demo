// 应用图标集：Remix Icon（https://remixicon.com，许可证见
// asset/icons/REMIX_ICON_LICENSE）。与 app_visual_theme 同层下沉到
// media/design，供 app/、bili/、media/ 三层共用。
// 字段名由 Remix 图形名驼峰化而来，便于对照官方文档；线/面成对
// （Line/Fill）用于选中态。播放控制条皮肤见 app_stage_skin.dart。
import 'package:flutter/widgets.dart';

abstract final class AppIcons {
  // account-circle-fill
  static const IconData accountCircleFill = IconData(0xea08, fontFamily: 'RemixIcon');
  // account-circle-line
  static const IconData accountCircleLine = IconData(0xea09, fontFamily: 'RemixIcon');
  // add-fill
  static const IconData addFill = IconData(0xea13, fontFamily: 'RemixIcon');
  // alarm-warning-line
  static const IconData alarmWarningLine = IconData(0xea1d, fontFamily: 'RemixIcon');
  // alert-line
  static const IconData alertLine = IconData(0xea21, fontFamily: 'RemixIcon');
  // arrow-down-s-line
  static const IconData arrowDownSLine = IconData(0xea4e, fontFamily: 'RemixIcon');
  // arrow-go-back-line
  static const IconData arrowGoBackLine = IconData(0xea58, fontFamily: 'RemixIcon');
  // arrow-left-line
  static const IconData arrowLeftLine = IconData(0xea60, fontFamily: 'RemixIcon');
  // arrow-left-right-line
  static const IconData arrowLeftRightLine = IconData(0xea62, fontFamily: 'RemixIcon');
  // arrow-left-s-line
  static const IconData arrowLeftSLine = IconData(0xea64, fontFamily: 'RemixIcon');
  // arrow-right-s-line
  static const IconData arrowRightSLine = IconData(0xea6e, fontFamily: 'RemixIcon');
  // arrow-up-s-line
  static const IconData arrowUpSLine = IconData(0xea78, fontFamily: 'RemixIcon');
  // award-line
  static const IconData awardLine = IconData(0xea8a, fontFamily: 'RemixIcon');
  // bookmark-fill
  static const IconData bookmarkFill = IconData(0xeae4, fontFamily: 'RemixIcon');
  // bookmark-line
  static const IconData bookmarkLine = IconData(0xeae5, fontFamily: 'RemixIcon');
  // camera-line
  static const IconData cameraLine = IconData(0xeb31, fontFamily: 'RemixIcon');
  // cast-fill
  static const IconData castFill = IconData(0xeb3e, fontFamily: 'RemixIcon');
  // cast-line
  static const IconData castLine = IconData(0xeb3f, fontFamily: 'RemixIcon');
  // chat-1-line
  static const IconData chat1Line = IconData(0xeb4d, fontFamily: 'RemixIcon');
  // chat-3-fill
  static const IconData chat3Fill = IconData(0xeb50, fontFamily: 'RemixIcon');
  // chat-3-line
  static const IconData chat3Line = IconData(0xeb51, fontFamily: 'RemixIcon');
  // check-fill
  static const IconData checkFill = IconData(0xeb7b, fontFamily: 'RemixIcon');
  // checkbox-circle-fill
  static const IconData checkboxCircleFill = IconData(0xeb80, fontFamily: 'RemixIcon');
  // checkbox-circle-line
  static const IconData checkboxCircleLine = IconData(0xeb81, fontFamily: 'RemixIcon');
  // checkbox-multiple-line
  static const IconData checkboxMultipleLine = IconData(0xeb89, fontFamily: 'RemixIcon');
  // close-circle-line
  static const IconData closeCircleLine = IconData(0xeb97, fontFamily: 'RemixIcon');
  // close-fill
  static const IconData closeFill = IconData(0xeb99, fontFamily: 'RemixIcon');
  // closed-captioning-fill
  static const IconData closedCaptioningFill = IconData(0xeb9a, fontFamily: 'RemixIcon');
  // closed-captioning-line
  static const IconData closedCaptioningLine = IconData(0xeb9b, fontFamily: 'RemixIcon');
  // cloud-off-line
  static const IconData cloudOffLine = IconData(0xeb9f, fontFamily: 'RemixIcon');
  // contrast-line
  static const IconData contrastLine = IconData(0xebda, fontFamily: 'RemixIcon');
  // cpu-line
  static const IconData cpuLine = IconData(0xebf0, fontFamily: 'RemixIcon');
  // database-2-line
  static const IconData database2Line = IconData(0xec16, fontFamily: 'RemixIcon');
  // delete-bin-line
  static const IconData deleteBinLine = IconData(0xec2a, fontFamily: 'RemixIcon');
  // download-2-line
  static const IconData download2Line = IconData(0xec54, fontFamily: 'RemixIcon');
  // download-line
  static const IconData downloadLine = IconData(0xec5a, fontFamily: 'RemixIcon');
  // emotion-happy-line
  static const IconData emotionHappyLine = IconData(0xec8d, fontFamily: 'RemixIcon');
  // error-warning-line
  static const IconData errorWarningLine = IconData(0xeca1, fontFamily: 'RemixIcon');
  // eye-line
  static const IconData eyeLine = IconData(0xecb5, fontFamily: 'RemixIcon');
  // eye-off-line
  static const IconData eyeOffLine = IconData(0xecb7, fontFamily: 'RemixIcon');
  // file-copy-line
  static const IconData fileCopyLine = IconData(0xecd5, fontFamily: 'RemixIcon');
  // film-line
  static const IconData filmLine = IconData(0xed21, fontFamily: 'RemixIcon');
  // folder-line
  static const IconData folderLine = IconData(0xed6a, fontFamily: 'RemixIcon');
  // folder-open-line
  static const IconData folderOpenLine = IconData(0xed70, fontFamily: 'RemixIcon');
  // folders-line
  static const IconData foldersLine = IconData(0xed8a, fontFamily: 'RemixIcon');
  // fullscreen-exit-fill
  static const IconData fullscreenExitFill = IconData(0xed9a, fontFamily: 'RemixIcon');
  // fullscreen-line
  static const IconData fullscreenLine = IconData(0xed9c, fontFamily: 'RemixIcon');
  // gamepad-line
  static const IconData gamepadLine = IconData(0xedab, fontFamily: 'RemixIcon');
  // grid-line
  static const IconData gridLine = IconData(0xeddf, fontFamily: 'RemixIcon');
  // group-fill
  static const IconData groupFill = IconData(0xede2, fontFamily: 'RemixIcon');
  // group-line
  static const IconData groupLine = IconData(0xede3, fontFamily: 'RemixIcon');
  // hd-line
  static const IconData hdLine = IconData(0xee02, fontFamily: 'RemixIcon');
  // headphone-line
  static const IconData headphoneLine = IconData(0xee05, fontFamily: 'RemixIcon');
  // heart-pulse-line
  static const IconData heartPulseLine = IconData(0xee11, fontFamily: 'RemixIcon');
  // history-line
  static const IconData historyLine = IconData(0xee17, fontFamily: 'RemixIcon');
  // home-5-fill
  static const IconData home5Fill = IconData(0xee1e, fontFamily: 'RemixIcon');
  // home-5-line
  static const IconData home5Line = IconData(0xee1f, fontFamily: 'RemixIcon');
  // image-line
  static const IconData imageLine = IconData(0xee4b, fontFamily: 'RemixIcon');
  // inbox-line
  static const IconData inboxLine = IconData(0xee4f, fontFamily: 'RemixIcon');
  // indeterminate-circle-line
  static const IconData indeterminateCircleLine = IconData(0xee57, fontFamily: 'RemixIcon');
  // information-line
  static const IconData informationLine = IconData(0xee59, fontFamily: 'RemixIcon');
  // install-line
  static const IconData installLine = IconData(0xee68, fontFamily: 'RemixIcon');
  // live-line
  static const IconData liveLine = IconData(0xeec0, fontFamily: 'RemixIcon');
  // lock-line
  static const IconData lockLine = IconData(0xeece, fontFamily: 'RemixIcon');
  // login-circle-line
  static const IconData loginCircleLine = IconData(0xeed6, fontFamily: 'RemixIcon');
  // logout-circle-r-line
  static const IconData logoutCircleRLine = IconData(0xeede, fontFamily: 'RemixIcon');
  // money-cny-circle-line
  static const IconData moneyCnyCircleLine = IconData(0xef61, fontFamily: 'RemixIcon');
  // moon-line
  static const IconData moonLine = IconData(0xef75, fontFamily: 'RemixIcon');
  // more-2-fill
  static const IconData more2Fill = IconData(0xef76, fontFamily: 'RemixIcon');
  // more-fill
  static const IconData moreFill = IconData(0xef78, fontFamily: 'RemixIcon');
  // movie-2-line
  static const IconData movie2Line = IconData(0xef7f, fontFamily: 'RemixIcon');
  // movie-line
  static const IconData movieLine = IconData(0xef81, fontFamily: 'RemixIcon');
  // music-2-line
  static const IconData music2Line = IconData(0xef83, fontFamily: 'RemixIcon');
  // palette-line
  static const IconData paletteLine = IconData(0xefc5, fontFamily: 'RemixIcon');
  // pause-fill
  static const IconData pauseFill = IconData(0xefd8, fontFamily: 'RemixIcon');
  // picture-in-picture-line
  static const IconData pictureInPictureLine = IconData(0xeff4, fontFamily: 'RemixIcon');
  // play-circle-fill
  static const IconData playCircleFill = IconData(0xf008, fontFamily: 'RemixIcon');
  // play-circle-line
  static const IconData playCircleLine = IconData(0xf009, fontFamily: 'RemixIcon');
  // play-fill
  static const IconData playFill = IconData(0xf00a, fontFamily: 'RemixIcon');
  // play-list-line
  static const IconData playListLine = IconData(0xf011, fontFamily: 'RemixIcon');
  // qr-code-line
  static const IconData qrCodeLine = IconData(0xf03d, fontFamily: 'RemixIcon');
  // qr-scan-line
  static const IconData qrScanLine = IconData(0xf041, fontFamily: 'RemixIcon');
  // question-line
  static const IconData questionLine = IconData(0xf045, fontFamily: 'RemixIcon');
  // refresh-line
  static const IconData refreshLine = IconData(0xf064, fontFamily: 'RemixIcon');
  // search-eye-line
  static const IconData searchEyeLine = IconData(0xf0cf, fontFamily: 'RemixIcon');
  // search-line
  static const IconData searchLine = IconData(0xf0d1, fontFamily: 'RemixIcon');
  // send-plane-line
  static const IconData sendPlaneLine = IconData(0xf0da, fontFamily: 'RemixIcon');
  // settings-fill
  static const IconData settingsFill = IconData(0xf0ed, fontFamily: 'RemixIcon');
  // settings-line
  static const IconData settingsLine = IconData(0xf0ee, fontFamily: 'RemixIcon');
  // share-line
  static const IconData shareLine = IconData(0xf0fe, fontFamily: 'RemixIcon');
  // shut-down-line
  static const IconData shutDownLine = IconData(0xf126, fontFamily: 'RemixIcon');
  // skip-back-line
  static const IconData skipBackLine = IconData(0xf140, fontFamily: 'RemixIcon');
  // skip-forward-line
  static const IconData skipForwardLine = IconData(0xf144, fontFamily: 'RemixIcon');
  // sort-desc
  static const IconData sortDesc = IconData(0xf160, fontFamily: 'RemixIcon');
  // sound-module-line
  static const IconData soundModuleLine = IconData(0xf162, fontFamily: 'RemixIcon');
  // speed-line
  static const IconData speedLine = IconData(0xf177, fontFamily: 'RemixIcon');
  // stack-line
  static const IconData stackLine = IconData(0xf181, fontFamily: 'RemixIcon');
  // star-fill
  static const IconData starFill = IconData(0xf186, fontFamily: 'RemixIcon');
  // star-line
  static const IconData starLine = IconData(0xf18b, fontFamily: 'RemixIcon');
  // stop-line
  static const IconData stopLine = IconData(0xf1a1, fontFamily: 'RemixIcon');
  // sun-line
  static const IconData sunLine = IconData(0xf1bf, fontFamily: 'RemixIcon');
  // thumb-down-line
  static const IconData thumbDownLine = IconData(0xf205, fontFamily: 'RemixIcon');
  // thumb-up-fill
  static const IconData thumbUpFill = IconData(0xf206, fontFamily: 'RemixIcon');
  // thumb-up-line
  static const IconData thumbUpLine = IconData(0xf207, fontFamily: 'RemixIcon');
  // ticket-line
  static const IconData ticketLine = IconData(0xf20d, fontFamily: 'RemixIcon');
  // time-fill
  static const IconData timeFill = IconData(0xf20e, fontFamily: 'RemixIcon');
  // time-line
  static const IconData timeLine = IconData(0xf20f, fontFamily: 'RemixIcon');
  // tv-2-line
  static const IconData tv2Line = IconData(0xf235, fontFamily: 'RemixIcon');
  // tv-line
  static const IconData tvLine = IconData(0xf237, fontFamily: 'RemixIcon');
  // user-3-fill
  static const IconData user3Fill = IconData(0xf255, fontFamily: 'RemixIcon');
  // user-3-line
  static const IconData user3Line = IconData(0xf256, fontFamily: 'RemixIcon');
  // user-add-fill
  static const IconData userAddFill = IconData(0xf25d, fontFamily: 'RemixIcon');
  // user-add-line
  static const IconData userAddLine = IconData(0xf25e, fontFamily: 'RemixIcon');
  // video-line
  static const IconData videoLine = IconData(0xf282, fontFamily: 'RemixIcon');
  // volume-up-line
  static const IconData volumeUpLine = IconData(0xf2a2, fontFamily: 'RemixIcon');
  // wifi-off-line
  static const IconData wifiOffLine = IconData(0xf2c2, fontFamily: 'RemixIcon');
  // forward-10-line
  static const IconData forward10Line = IconData(0xf32b, fontFamily: 'RemixIcon');
  // replay-10-line
  static const IconData replay10Line = IconData(0xf352, fontFamily: 'RemixIcon');
  // school-line
  static const IconData schoolLine = IconData(0xf35a, fontFamily: 'RemixIcon');
  // checkbox-blank-circle-line
  static const IconData checkboxBlankCircleLine = IconData(0xf3c1, fontFamily: 'RemixIcon');
  // verified-badge-line
  static const IconData verifiedBadgeLine = IconData(0xf3e8, fontFamily: 'RemixIcon');
  // equalizer-2-line
  static const IconData equalizer2Line = IconData(0xf404, fontFamily: 'RemixIcon');
  // video-off-line
  static const IconData videoOffLine = IconData(0xf51b, fontFamily: 'RemixIcon');
}
