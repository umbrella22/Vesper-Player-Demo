import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_icons.dart';
import 'package:signals/signals_flutter.dart';

import '../design/app_glass_controls.dart';
import 'app_update_controller.dart';
import 'app_update_release.dart';

class AppUpdateScope extends InheritedWidget {
  const AppUpdateScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final AppUpdateController controller;
  static AppUpdateController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppUpdateScope>()?.controller;
  @override
  bool updateShouldNotify(AppUpdateScope oldWidget) =>
      controller != oldWidget.controller;
}

class AppUpdateStartupCheck extends StatefulWidget {
  const AppUpdateStartupCheck({
    super.key,
    required this.controller,
    required this.child,
  });
  final AppUpdateController controller;
  final Widget child;
  @override
  State<AppUpdateStartupCheck> createState() => _AppUpdateStartupCheckState();
}

class _AppUpdateStartupCheckState extends State<AppUpdateStartupCheck> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final checked = await widget.controller.checkAtStartup();
    if (!checked ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        widget.controller.state.value.phase != AppUpdatePhase.available) {
      return;
    }
    await showAppUpdateDialog(context, widget.controller);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AppUpdateSettingsRow extends StatelessWidget {
  const AppUpdateSettingsRow({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppUpdateScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return SignalBuilder(
      builder: (context) {
        final state = controller.state.value;
        if (state.phase == AppUpdatePhase.unsupported) {
          return const SizedBox.shrink();
        }
        return AppSettingsRow(
          key: const ValueKey('app-check-for-updates'),
          icon: AppIcons.installLine,
          title: '检查更新',
          subtitle: state.phase == AppUpdatePhase.available
              ? '发现新版本 ${state.release!.version}'
              : '从 GitHub 获取最新安装包',
          onTap: () => showAppUpdateDialog(context, controller, check: true),
        );
      },
    );
  }
}

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppUpdateController controller, {
  bool check = false,
}) async {
  if (controller.dialogOpen) return;
  controller.dialogOpen = true;
  if (check && controller.state.value.file == null) {
    unawaited(controller.check());
  }
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AppUpdateDialog(controller: controller),
    );
  } finally {
    controller.dialogOpen = false;
  }
}

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.controller});
  final AppUpdateController controller;
  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.resumeInstallation());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.cancelDownload();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final controller = widget.controller;
      final state = controller.state.value;
      final downloading = state.phase == AppUpdatePhase.downloading;
      final busy = downloading || state.phase == AppUpdatePhase.installing;
      final playCover = state.platform == AppUpdatePlatform.playCover;
      return PopScope(
        canPop: !busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && downloading) controller.cancelDownload();
        },
        child: AlertDialog(
          title: Text(
            state.phase == AppUpdatePhase.available
                ? '发现新版本 ${state.release!.version}'
                : '应用更新',
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_statusMessage(state)),
                  if (state.phase == AppUpdatePhase.checking ||
                      state.phase == AppUpdatePhase.installing ||
                      downloading) ...[
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: downloading && state.total > 0
                          ? state.received / state.total
                          : null,
                    ),
                    if (downloading) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_megabytes(state.received)} / ${_megabytes(state.total)} MB',
                      ),
                    ],
                  ],
                  if (state.phase == AppUpdatePhase.available &&
                      state.release!.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: Text(
                          state.release!.notes,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (!busy)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  state.phase == AppUpdatePhase.available ? '稍后' : '关闭',
                ),
              ),
            if (downloading)
              TextButton(
                onPressed: controller.cancelDownload,
                child: const Text('取消下载'),
              ),
            if (state.phase == AppUpdatePhase.available)
              FilledButton(
                onPressed: controller.downloadAndInstall,
                child: Text(playCover ? '下载并打开 PlayCover' : '下载并安装'),
              ),
            if (state.phase == AppUpdatePhase.failed ||
                state.phase == AppUpdatePhase.publishing)
              FilledButton(
                onPressed: controller.check,
                child: const Text('重试'),
              ),
            if (state.phase == AppUpdatePhase.ready ||
                state.phase == AppUpdatePhase.permissionRequired ||
                state.phase == AppUpdatePhase.handedOff)
              FilledButton(
                onPressed: controller.installDownloaded,
                child: Text(
                  state.phase == AppUpdatePhase.permissionRequired
                      ? '授权并安装'
                      : state.phase == AppUpdatePhase.handedOff
                      ? '再次打开安装程序'
                      : '重试安装',
                ),
              ),
            if (playCover &&
                (state.phase == AppUpdatePhase.ready ||
                    state.phase == AppUpdatePhase.handedOff))
              TextButton(
                onPressed: controller.exportDownloaded,
                child: const Text('保存安装包'),
              ),
          ],
        ),
      );
    },
  );
}

String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

String _statusMessage(AppUpdateState state) => switch (state.phase) {
  AppUpdatePhase.idle || AppUpdatePhase.checking => '正在检查 GitHub Release…',
  AppUpdatePhase.unsupported => '此设备暂不支持直接安装更新。',
  AppUpdatePhase.upToDate => '当前版本 ${state.currentVersion} 已是最新版本。',
  AppUpdatePhase.publishing =>
    '发现新版本 ${state.release!.version}，此平台的安装包仍在发布中，请稍后重试。',
  AppUpdatePhase.available =>
    '当前版本 ${state.currentVersion} · 安装包 ${_megabytes(state.release!.asset!.size)} MB\n'
        '${state.platform == AppUpdatePlatform.playCover ? '下载完成后将交给 PlayCover 安装，安装后请重新打开应用。' : '下载完成后将打开系统安装器，由你确认安装。'}',
  AppUpdatePhase.downloading =>
    state.received == state.total ? '正在校验安装包…' : '正在下载安装包…',
  AppUpdatePhase.ready => '安装包已下载，可以重新打开安装程序。',
  AppUpdatePhase.installing => '正在打开安装程序…',
  AppUpdatePhase.permissionRequired => '请在系统设置中允许 Vesper 安装未知应用，返回后将继续打开安装器。',
  AppUpdatePhase.handedOff =>
    state.exported
        ? '请保存 IPA，然后在 PlayCover 中导入安装。'
        : state.platform == AppUpdatePlatform.playCover
        ? '安装包已交给 PlayCover，请完成安装后重新打开 Vesper。'
        : '已打开系统安装器，请按系统提示完成更新。',
  AppUpdatePhase.failed => '暂时无法检查更新。',
};
