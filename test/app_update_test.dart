import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:vesper_media/app/updates/app_update_controller.dart';
import 'package:vesper_media/app/updates/app_update_installer.dart';
import 'package:vesper_media/app/updates/app_update_release.dart';
import 'package:vesper_media/app/updates/github_app_update_client.dart';

import 'support/app_update_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GitHub release selection', () {
    test(
      'chooses the exact Android or PlayCover installer, never unsigned IPA',
      () {
        final json = releaseJson();
        final android = parseAppUpdateRelease(
          json,
          AppUpdatePlatform.androidArm64,
        )!;
        final playCover = parseAppUpdateRelease(
          json,
          AppUpdatePlatform.playCover,
        )!;
        expect(android.asset!.name, 'vesper-v1.15.0-android-arm64-release.apk');
        expect(playCover.asset!.name, 'vesper-v1.15.0-ios-playcover.ipa');
        expect(android.version, Version(1, 15, 0));
        expect(android.asset!.sha256, 'a' * 64);
      },
    );

    test('skips draft, prerelease flag and prerelease version tags', () {
      for (final json in [
        releaseJson()..['draft'] = true,
        releaseJson()..['prerelease'] = true,
        releaseJson()..['tag_name'] = 'vesper_media-v1.15.0-rc.1',
      ]) {
        expect(
          parseAppUpdateRelease(json, AppUpdatePlatform.androidArm64),
          isNull,
        );
      }
    });

    test(
      'preserves a newer release while its platform artifact is not ready',
      () {
        final json = releaseJson()
          ..['assets'] = [
            releaseAsset('vesper-v1.15.0-ios-unsigned.ipa'),
            releaseAsset('vesper-v1.15.0-android-arm64-release.apk.sha256'),
            releaseAsset('vesper-v1.14.0-android-arm64-release.apk'),
          ];
        final release = parseAppUpdateRelease(
          json,
          AppUpdatePlatform.androidArm64,
        )!;
        expect(release.version, Version(1, 15, 0));
        expect(release.asset, isNull);
      },
    );

    test('supports checksum sidecar when GitHub digest is absent', () {
      final name = 'vesper-v1.15.0-android-arm64-release.apk';
      final json = releaseJson()
        ..['assets'] = [
          releaseAsset(name)..remove('digest'),
          releaseAsset('$name.sha256'),
        ];
      final release = parseAppUpdateRelease(
        json,
        AppUpdatePlatform.androidArm64,
      )!;
      expect(release.asset!.sha256, isNull);
      expect(release.asset!.checksumUrl.toString(), endsWith('$name.sha256'));
      (json['assets'] as List).removeLast();
      expect(
        parseAppUpdateRelease(json, AppUpdatePlatform.androidArm64)!.asset,
        isNull,
      );
    });

    test('rejects a matching name with a foreign download URL', () {
      final json = releaseJson();
      (json['assets'] as List).first['browser_download_url'] =
          'https://example.com/vesper-v1.15.0-android-arm64-release.apk';
      expect(
        () => parseAppUpdateRelease(json, AppUpdatePlatform.androidArm64),
        throwsFormatException,
      );
    });

    test(
      'supports historical v-prefixed tags and ignores build metadata ordering',
      () {
        final json = releaseJson()..['tag_name'] = 'v1.15.0';
        for (final asset in json['assets'] as List) {
          asset['browser_download_url'] =
              (asset['browser_download_url'] as String).replaceFirst(
                'vesper_media-v1.15.0',
                'v1.15.0',
              );
        }
        expect(
          parseAppUpdateRelease(json, AppUpdatePlatform.playCover)!.version,
          Version(1, 15, 0),
        );
        expect(
          isAppUpdateNewer(
            Version.parse('1.15.0+200'),
            Version.parse('1.15.0+100'),
          ),
          isFalse,
        );
        expect(
          isAppUpdateNewer(
            Version.parse('1.15.0'),
            Version.parse('1.15.0-rc.1'),
          ),
          isTrue,
        );
      },
    );
  });

  group('update lifecycle', () {
    late FakeUpdateClient client;
    late FakeUpdateInstaller installer;
    AppUpdateController makeController({String current = '1.14.0'}) {
      final controller = AppUpdateController(
        client: client,
        installer: installer,
        currentVersion: () async => current,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    setUp(() {
      client = FakeUpdateClient();
      installer = FakeUpdateInstaller();
    });

    test('compares numeric versions and never proposes downgrades', () async {
      for (final current in ['1.9.0', '1.15.0', '1.16.0', '2.0.0']) {
        final controller = makeController(current: current);
        await controller.check();
        expect(
          controller.state.value.phase,
          current == '1.9.0'
              ? AppUpdatePhase.available
              : AppUpdatePhase.upToDate,
        );
      }
      expect(client.downloads, 0);
      expect(installer.installCalls, 0);
    });

    test(
      'unknown current version does not offer an arbitrary update',
      () async {
        final controller = makeController(current: '');
        await controller.check();
        expect(controller.state.value.phase, AppUpdatePhase.failed);
        expect(client.checks, 0);
      },
    );

    test('unsupported device does not contact GitHub', () async {
      installer.target = AppUpdatePlatform.unsupported;
      final controller = makeController();
      await controller.check();
      expect(controller.state.value.phase, AppUpdatePhase.unsupported);
      expect(client.checks, 0);
    });

    test(
      'checks once at startup, but manual checking stays available',
      () async {
        final controller = makeController();
        expect(await controller.checkAtStartup(), isTrue);
        expect(await controller.checkAtStartup(), isFalse);
        expect(client.checks, 1);
        await controller.check();
        expect(client.checks, 2);
      },
    );

    test(
      'coalesces concurrent checks and waits for a completed download before installation',
      () async {
        final response = Completer<AppUpdateRelease?>();
        client.checkResult = response.future;
        final controller = makeController();
        final first = controller.check();
        final second = controller.check();
        response.complete(updateRelease());
        await Future.wait([first, second]);
        expect(client.checks, 1);
        final download = Completer<File>();
        client.downloadResult = download.future;
        final operation = controller.downloadAndInstall();
        await controller.downloadAndInstall();
        expect(client.downloads, 1);
        expect(installer.installCalls, 0);
        download.complete(File('/cache/vesper-updates/update.apk'));
        await operation;
        expect(installer.installCalls, 1);
        expect(controller.state.value.phase, AppUpdatePhase.handedOff);
      },
    );

    test(
      'cancelled download cannot install even if completion arrives late',
      () async {
        final controller = makeController();
        await controller.check();
        final download = Completer<File>();
        client.downloadResult = download.future;
        final operation = controller.downloadAndInstall();
        controller.cancelDownload();
        download.complete(File('/cache/vesper-updates/update.apk'));
        await operation;
        expect(installer.installCalls, 0);
        expect(controller.state.value.phase, AppUpdatePhase.available);
      },
    );

    test(
      'failed integrity validation is retryable and cannot install',
      () async {
        final controller = makeController();
        await controller.check();
        client.downloadResult = Future.error(
          const AppUpdateException('安装包校验失败'),
        );
        await controller.downloadAndInstall();
        expect(controller.state.value.phase, AppUpdatePhase.available);
        expect(controller.state.value.error, contains('校验失败'));
        expect(installer.installCalls, 0);
      },
    );

    test(
      'permission denial retains the file; granting permission resumes without redownloading',
      () async {
        installer.result = AppUpdateInstallResult.permissionRequired;
        final controller = makeController();
        await controller.check();
        await controller.downloadAndInstall();
        expect(controller.state.value.phase, AppUpdatePhase.permissionRequired);
        await controller.resumeInstallation();
        expect(installer.installCalls, 1);
        installer.allowed = true;
        installer.result = AppUpdateInstallResult.opened;
        await controller.resumeInstallation();
        expect(installer.installCalls, 2);
        expect(client.downloads, 1);
        expect(controller.state.value.phase, AppUpdatePhase.handedOff);
      },
    );

    test(
      'PlayCover launch failure keeps the IPA for retry or export',
      () async {
        installer.target = AppUpdatePlatform.playCover;
        installer.installError = PlatformException(
          code: 'INSTALL_FAILED',
          message: '未能打开 PlayCover',
        );
        final controller = makeController();
        await controller.check();
        await controller.downloadAndInstall();
        expect(controller.state.value.phase, AppUpdatePhase.ready);
        expect(controller.state.value.file, isNotNull);
        await controller.exportDownloaded();
        expect(installer.exports, 1);
        expect(controller.state.value.exported, isTrue);
      },
    );
  });

  test(
    'native installer maps platform support and unknown-source permission',
    () async {
      const channel = MethodChannel('dev.ikaros.vesper_player/app_update');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'platform' => 'playCover',
              'install' => 'permissionRequired',
              'canInstall' => true,
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const installer = PlatformAppUpdateInstaller();
      expect(await installer.platform(), AppUpdatePlatform.playCover);
      expect(
        await installer.install(File('/cache/update.ipa')),
        AppUpdateInstallResult.permissionRequired,
      );
      expect(await installer.canInstall(), isTrue);
      expect(calls[1].arguments, {'path': '/cache/update.ipa'});
    },
  );
}
