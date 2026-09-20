import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:vesper_media/app/updates/app_update_installer.dart';
import 'package:vesper_media/app/updates/app_update_release.dart';
import 'package:vesper_media/app/updates/github_app_update_client.dart';

Map<String, dynamic> releaseAsset(String name) => {
  'name': name,
  'size': 1024,
  'digest': 'sha256:${'a' * 64}',
  'browser_download_url':
      'https://github.com/$appUpdateRepository/releases/download/vesper_media-v1.15.0/$name',
};

Map<String, dynamic> releaseJson() => {
  'tag_name': 'vesper_media-v1.15.0',
  'draft': false,
  'prerelease': false,
  'body': '改善播放与评论体验。',
  'assets': [
    releaseAsset('vesper-v1.15.0-android-arm64-release.apk'),
    releaseAsset('vesper-v1.15.0-ios-unsigned.ipa'),
    releaseAsset('vesper-v1.15.0-ios-playcover.ipa'),
  ],
};

AppUpdateRelease updateRelease() => AppUpdateRelease(
  version: Version(1, 15, 0),
  tag: 'vesper_media-v1.15.0',
  notes: '改善播放与评论体验。',
  pageUrl: Uri.parse(
    'https://github.com/$appUpdateRepository/releases/tag/vesper_media-v1.15.0',
  ),
  asset: AppUpdateAsset(
    name: 'vesper-v1.15.0-android-arm64-release.apk',
    url: Uri.parse(
      'https://github.com/$appUpdateRepository/releases/download/vesper_media-v1.15.0/vesper-v1.15.0-android-arm64-release.apk',
    ),
    size: 1024,
    sha256: 'a' * 64,
  ),
);

class FakeUpdateClient implements AppUpdateClient {
  int checks = 0;
  int downloads = 0;
  int cancellations = 0;
  Future<AppUpdateRelease?>? checkResult;
  Future<File>? downloadResult;
  @override
  Future<AppUpdateRelease?> latestRelease(AppUpdatePlatform platform) async {
    checks++;
    return checkResult ?? updateRelease();
  }

  @override
  Future<File> download(
    AppUpdateAsset asset, {
    required void Function(int, int) onProgress,
  }) async {
    downloads++;
    onProgress(512, 1024);
    return downloadResult ?? File('/cache/vesper-updates/update.apk');
  }

  @override
  void cancelDownload() {
    cancellations++;
  }

  @override
  void dispose() {}
}

class FakeUpdateInstaller implements AppUpdateInstaller {
  AppUpdatePlatform target = AppUpdatePlatform.androidArm64;
  AppUpdateInstallResult result = AppUpdateInstallResult.opened;
  Object? installError;
  bool allowed = false;
  int installCalls = 0;
  int exports = 0;
  @override
  Future<AppUpdatePlatform> platform() async => target;
  @override
  Future<AppUpdateInstallResult> install(File file) async {
    installCalls++;
    if (installError != null) throw installError!;
    return result;
  }

  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> export(File file) async {
    exports++;
  }
}
