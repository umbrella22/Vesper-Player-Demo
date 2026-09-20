import 'dart:io';

import 'package:flutter/services.dart';

import 'app_update_release.dart';

enum AppUpdateInstallResult { opened, permissionRequired }

abstract interface class AppUpdateInstaller {
  Future<AppUpdatePlatform> platform();
  Future<AppUpdateInstallResult> install(File file);
  Future<bool> canInstall();
  Future<void> export(File file);
}

final class PlatformAppUpdateInstaller implements AppUpdateInstaller {
  const PlatformAppUpdateInstaller();

  static const _channel = MethodChannel('dev.ikaros.vesper_player/app_update');

  @override
  Future<AppUpdatePlatform> platform() async {
    try {
      return switch (await _channel.invokeMethod<String>('platform')) {
        'androidArm64' => AppUpdatePlatform.androidArm64,
        'playCover' => AppUpdatePlatform.playCover,
        _ => AppUpdatePlatform.unsupported,
      };
    } on MissingPluginException {
      return AppUpdatePlatform.unsupported;
    }
  }

  @override
  Future<AppUpdateInstallResult> install(File file) async {
    final result = await _channel.invokeMethod<String>('install', {
      'path': file.path,
    });
    return switch (result) {
      'opened' => AppUpdateInstallResult.opened,
      'permissionRequired' => AppUpdateInstallResult.permissionRequired,
      _ => throw PlatformException(
        code: 'INSTALL_FAILED',
        message: '未能打开安装程序。',
      ),
    };
  }

  @override
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> export(File file) =>
      _channel.invokeMethod<void>('export', {'path': file.path});
}
