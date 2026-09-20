import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:signals/signals.dart';

import '../app_version.dart';
import 'app_update_installer.dart';
import 'app_update_release.dart';
import 'github_app_update_client.dart';

enum AppUpdatePhase {
  idle,
  checking,
  unsupported,
  upToDate,
  publishing,
  available,
  downloading,
  ready,
  installing,
  permissionRequired,
  handedOff,
  failed,
}

final class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.platform = AppUpdatePlatform.unsupported,
    this.currentVersion = '',
    this.release,
    this.received = 0,
    this.total = 0,
    this.file,
    this.error,
    this.exported = false,
  });

  final AppUpdatePhase phase;
  final AppUpdatePlatform platform;
  final String currentVersion;
  final AppUpdateRelease? release;
  final int received;
  final int total;
  final File? file;
  final String? error;
  final bool exported;

  AppUpdateState withPhase(
    AppUpdatePhase next, {
    int? received,
    int? total,
    File? file,
    String? error,
    bool exported = false,
  }) => AppUpdateState(
    phase: next,
    platform: platform,
    currentVersion: currentVersion,
    release: release,
    received: received ?? this.received,
    total: total ?? this.total,
    file: file ?? this.file,
    error: error,
    exported: exported,
  );
}

/// One instance per app; settings and startup share its check/download state.
final class AppUpdateController {
  AppUpdateController({
    AppUpdateClient? client,
    AppUpdateInstaller? installer,
    Future<String> Function()? currentVersion,
  }) : _client = client ?? GithubAppUpdateClient(),
       _installer = installer ?? const PlatformAppUpdateInstaller(),
       _currentVersion = currentVersion ?? AppVersion.load;

  final AppUpdateClient _client;
  final AppUpdateInstaller _installer;
  final Future<String> Function() _currentVersion;
  final _state = signal(const AppUpdateState());
  ReadonlySignal<AppUpdateState> get state => _state;
  bool _disposed = false;
  bool _startupChecked = false;
  bool _cancelRequested = false;
  bool dialogOpen = false;
  Future<void>? _checking;

  Future<bool> checkAtStartup() async {
    if (_startupChecked) return false;
    _startupChecked = true;
    await check();
    return true;
  }

  Future<void> check() {
    if (_disposed) return Future.value();
    if (_checking != null) return _checking!;
    if (const {
      AppUpdatePhase.downloading,
      AppUpdatePhase.installing,
      AppUpdatePhase.permissionRequired,
    }.contains(_state.value.phase)) {
      return Future.value();
    }
    final future = _check();
    _checking = future;
    return future.whenComplete(() => _checking = null);
  }

  Future<void> _check() async {
    _state.value = const AppUpdateState(phase: AppUpdatePhase.checking);
    try {
      final platform = await _installer.platform();
      if (_disposed) return;
      if (platform == AppUpdatePlatform.unsupported) {
        _state.value = const AppUpdateState(phase: AppUpdatePhase.unsupported);
        return;
      }
      final current = await _currentVersion();
      final installed = Version.parse(current);
      final release = await _client.latestRelease(platform);
      if (_disposed) return;
      final newer =
          release != null && isAppUpdateNewer(release.version, installed);
      _state.value = AppUpdateState(
        phase: !newer
            ? AppUpdatePhase.upToDate
            : release.asset == null
            ? AppUpdatePhase.publishing
            : AppUpdatePhase.available,
        platform: platform,
        currentVersion: current,
        release: release,
      );
    } catch (error) {
      if (!_disposed) {
        _state.value = _state.value.withPhase(
          AppUpdatePhase.failed,
          error: _errorMessage(error),
        );
      }
    }
  }

  Future<void> downloadAndInstall() async {
    if (_disposed || _state.value.phase != AppUpdatePhase.available) return;
    final asset = _state.value.release?.asset;
    if (asset == null) return;
    _cancelRequested = false;
    _state.value = _state.value.withPhase(
      AppUpdatePhase.downloading,
      received: 0,
      total: asset.size,
    );
    try {
      final file = await _client.download(
        asset,
        onProgress: (received, total) {
          if (!_disposed && !_cancelRequested) {
            _state.value = _state.value.withPhase(
              AppUpdatePhase.downloading,
              received: received,
              total: total,
            );
          }
        },
      );
      if (_disposed) return;
      if (_cancelRequested) throw AppUpdateCancelled();
      _state.value = _state.value.withPhase(AppUpdatePhase.ready, file: file);
      await installDownloaded();
    } on AppUpdateCancelled {
      if (!_disposed) {
        _state.value = _state.value.withPhase(AppUpdatePhase.available);
      }
    } catch (error) {
      if (!_disposed) {
        _state.value = _state.value.withPhase(
          AppUpdatePhase.available,
          error: _errorMessage(error),
        );
      }
    }
  }

  void cancelDownload() {
    _cancelRequested = true;
    _client.cancelDownload();
  }

  Future<void> installDownloaded() async {
    if (_disposed) return;
    final state = _state.value;
    if (state.file == null ||
        !const {
          AppUpdatePhase.ready,
          AppUpdatePhase.permissionRequired,
          AppUpdatePhase.handedOff,
        }.contains(state.phase)) {
      return;
    }
    _state.value = state.withPhase(AppUpdatePhase.installing);
    try {
      final result = await _installer.install(state.file!);
      if (_disposed) return;
      _state.value = state.withPhase(
        result == AppUpdateInstallResult.permissionRequired
            ? AppUpdatePhase.permissionRequired
            : AppUpdatePhase.handedOff,
      );
    } catch (error) {
      if (!_disposed) {
        _state.value = state.withPhase(
          AppUpdatePhase.ready,
          error: _errorMessage(error),
        );
      }
    }
  }

  Future<void> resumeInstallation() async {
    if (_disposed || _state.value.phase != AppUpdatePhase.permissionRequired) {
      return;
    }
    try {
      if (await _installer.canInstall()) await installDownloaded();
    } catch (error) {
      if (!_disposed) {
        _state.value = _state.value.withPhase(
          AppUpdatePhase.permissionRequired,
          error: _errorMessage(error),
        );
      }
    }
  }

  Future<void> exportDownloaded() async {
    if (_disposed || _state.value.file == null) return;
    try {
      await _installer.export(_state.value.file!);
      if (!_disposed) {
        _state.value = _state.value.withPhase(
          AppUpdatePhase.handedOff,
          exported: true,
        );
      }
    } catch (error) {
      if (!_disposed) {
        _state.value = _state.value.withPhase(
          AppUpdatePhase.ready,
          error: _errorMessage(error),
        );
      }
    }
  }

  void dispose() {
    _disposed = true;
    _client.dispose();
    _state.dispose();
  }
}

String _errorMessage(Object error) => switch (error) {
  AppUpdateException() => error.message,
  PlatformException() => error.message ?? '无法打开安装程序，请重试。',
  SocketException() || TimeoutException() => '连接 GitHub 失败，请检查网络后重试。',
  FileSystemException() => '无法保存安装包，请检查可用存储空间。',
  FormatException() => '无法识别版本或发布信息，请稍后重试。',
  _ => '更新失败，请稍后重试。',
};
