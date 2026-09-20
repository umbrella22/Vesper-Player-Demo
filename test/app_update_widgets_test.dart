import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/app/updates/app_update_controller.dart';
import 'package:vesper_media/app/updates/app_update_release.dart';
import 'package:vesper_media/app/updates/app_update_widgets.dart';
import 'package:vesper_media/app/updates/github_app_update_client.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';

import 'support/app_update_fakes.dart';

void main() {
  late FakeUpdateClient client;
  late FakeUpdateInstaller installer;
  late AppUpdateController controller;
  setUp(() {
    client = FakeUpdateClient();
    installer = FakeUpdateInstaller();
    controller = AppUpdateController(
      client: client,
      installer: installer,
      currentVersion: () async => '1.14.0',
    );
  });
  tearDown(() => controller.dispose());

  Widget app({bool startup = false, Widget? home}) => AppUpdateScope(
    controller: controller,
    child: MaterialApp(
      theme: AppVisualTokens.mobileLightTheme(),
      home: startup
          ? AppUpdateStartupCheck(
              controller: controller,
              child: const Scaffold(body: Text('首页')),
            )
          : home ?? const Scaffold(body: AppUpdateSettingsRow()),
    ),
  );

  testWidgets(
    'manual check asks before downloading and later leaves the app alone',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('发现新版本 1.15.0'),
        ),
        findsOneWidget,
      );
      expect(client.downloads, 0);
      expect(installer.installCalls, 0);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(client.downloads, 0);
    },
  );

  testWidgets(
    'confirm shows progress then hands the verified download to the installer',
    (tester) async {
      final download = Completer<File>();
      client.downloadResult = download.future;
      await tester.pumpWidget(app());
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载并安装'));
      await tester.pump();
      expect(find.text('正在下载安装包…'), findsOneWidget);
      expect(find.text('取消下载'), findsOneWidget);
      expect(installer.installCalls, 0);
      download.complete(File('/cache/vesper-updates/update.apk'));
      await tester.pumpAndSettle();
      expect(find.text('已打开系统安装器，请按系统提示完成更新。'), findsOneWidget);
      expect(installer.installCalls, 1);
    },
  );

  testWidgets('cancel returns to confirmation without opening installer', (
    tester,
  ) async {
    final download = Completer<File>();
    client.downloadResult = download.future;
    await tester.pumpWidget(app());
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载并安装'));
    await tester.pump();
    await tester.tap(find.text('取消下载'));
    download.complete(File('/cache/vesper-updates/update.apk'));
    await tester.pumpAndSettle();
    expect(find.text('下载并安装'), findsOneWidget);
    expect(installer.installCalls, 0);
  });

  testWidgets('startup prompts once even if the home widget is recreated', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(app(startup: true));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 1.15.0'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(startup: true));
    await tester.pumpAndSettle();
    expect(client.checks, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('installer can be reopened without another download', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载并安装'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('再次打开安装程序'));
    await tester.pumpAndSettle();
    expect(client.downloads, 1);
    expect(installer.installCalls, 2);
  });

  testWidgets('startup network failure stays silent and manual retry works', (
    tester,
  ) async {
    final check = Completer<AppUpdateRelease?>();
    client.checkResult = check.future;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(app(startup: true));
    check.completeError(const AppUpdateException('连接 GitHub 失败'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.state.value.phase, AppUpdatePhase.failed);
    client.checkResult = null;
    await tester.pumpWidget(app());
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('下载并安装'), findsOneWidget);
    expect(client.checks, 2);
  });

  testWidgets('release still publishing offers retry without downloading', (
    tester,
  ) async {
    client.checkResult = Future.value(
      parseAppUpdateRelease(
        releaseJson()..['assets'] = [],
        AppUpdatePlatform.androidArm64,
      ),
    );
    await tester.pumpWidget(app());
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('安装包仍在发布中'), findsOneWidget);
    expect(find.text('下载并安装'), findsNothing);
    expect(client.downloads, 0);
    client.checkResult = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('下载并安装'), findsOneWidget);
  });

  testWidgets('checking does not interrupt a page opened after startup', (
    tester,
  ) async {
    final check = Completer<AppUpdateRelease?>();
    client.checkResult = check.future;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(app(startup: true));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('播放页')),
      ),
    );
    check.complete(updateRelease());
    await tester.pumpAndSettle();
    expect(find.text('播放页'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
