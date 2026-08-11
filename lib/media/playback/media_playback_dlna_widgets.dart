// 通用 DLNA 投屏表面组件：设备发现/连接/投屏面板。
//
// 状态与操作全部来自 [MediaExternalPlaybackManager]（由调用方注入），
// 面板不接触平台类型。
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';
import 'package:vesper_player_ui/vesper_player_ui.dart' as vesper_ui;

import 'media_external_playback_manager.dart';

class StageDlnaProjectionButton extends StatelessWidget {
  const StageDlnaProjectionButton({
    super.key,
    required this.state,
    required this.onTap,
  });

  final MediaDlnaState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      MediaDlnaState.connected => Icons.cast_connected_rounded,
      MediaDlnaState.connecting ||
      MediaDlnaState.discovering => Icons.cast_rounded,
      _ => Icons.cast_outlined,
    };
    return vesper_ui.VesperStageIconButton(
      icon: icon,
      label: '投屏',
      size: 38,
      iconSize: 22,
      containerAlpha: 0,
      onPressed: onTap,
    );
  }
}

class ProjectionPickerContent extends StatelessWidget {
  const ProjectionPickerContent({super.key, required this.onDlna});

  final VoidCallback onDlna;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '投屏',
              style: theme.textTheme.titleLarge?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: ProjectionCastOption()),
                const SizedBox(width: 12),
                Expanded(
                  child: ProjectionOptionCard(
                    icon: Icons.cast_outlined,
                    label: 'DLNA',
                    onTap: onDlna,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectionCastOption extends StatelessWidget {
  const ProjectionCastOption({super.key});

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return ProjectionOptionShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VesperExternalRouteIconButton(size: 56),
          const SizedBox(height: 10),
          Text(
            'Cast',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class ProjectionOptionCard extends StatelessWidget {
  const ProjectionOptionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return ProjectionOptionShell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: AppVisualTokens.primaryBlue),
          const SizedBox(height: 20),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class ProjectionOptionShell extends StatelessWidget {
  const ProjectionOptionShell({
    super.key,
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: visualTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(height: 118, child: Center(child: child)),
      ),
    );
  }
}

class DlnaPickerContent extends StatefulWidget {
  const DlnaPickerContent({
    super.key,
    required this.manager,
    required this.onLoadMedia,
    required this.onClose,
    required this.onMessage,
  });

  final MediaExternalPlaybackManager manager;
  final Future<String?> Function() onLoadMedia;
  final VoidCallback onClose;
  final void Function(String) onMessage;

  @override
  State<DlnaPickerContent> createState() => DlnaPickerContentState();
}

class DlnaPickerContentState extends State<DlnaPickerContent> {
  static const Duration _successCloseGracePeriod = Duration(milliseconds: 800);

  bool _loadingMedia = false;

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_handleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.manager.startDiscovery());
    });
  }

  @override
  void dispose() {
    widget.manager.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) return;
    final state = widget.manager.state;
    if (state == MediaDlnaState.connected && !_loadingMedia) {
      unawaited(_loadMedia());
    }
    setState(() {});
  }

  Future<void> _loadMedia() async {
    if (_loadingMedia) {
      return;
    }
    _loadingMedia = true;
    final result = await widget.onLoadMedia();
    if (result != null && mounted) {
      widget.onMessage(result);
      _loadingMedia = false;
      return;
    }
    await Future<void>.delayed(_successCloseGracePeriod);
    if (!mounted) {
      return;
    }
    if (widget.manager.state == MediaDlnaState.error) {
      _loadingMedia = false;
      return;
    }
    if (mounted) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    final state = widget.manager.state;
    final routes = widget.manager.routes;
    final message = widget.manager.message;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DLNA 投屏',
              style: theme.textTheme.titleLarge?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            if (state == MediaDlnaState.discovering) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '正在搜索 DLNA 设备…',
                    style: TextStyle(
                      color: visualTheme.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (message != null && message.isNotEmpty) ...[
              DlnaStatusMessage(
                message: message,
                isError: state == MediaDlnaState.error,
              ),
              const SizedBox(height: 12),
            ],
            if (state == MediaDlnaState.connecting)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '正在连接设备…',
                      style: TextStyle(
                        color: visualTheme.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (state == MediaDlnaState.discovering &&
                routes.isEmpty &&
                (message == null || message.isEmpty))
              Text(
                '未发现 DLNA 设备，请确保设备和手机在同一网络下。',
                style: TextStyle(
                  color: visualTheme.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (routes.isNotEmpty)
              ...routes.map(
                (route) => DlnaRouteTile(
                  route: route,
                  isLoading: state == MediaDlnaState.connecting,
                  onTap: () {
                    if (state == MediaDlnaState.connecting) return;
                    unawaited(widget.manager.connect(route.routeId));
                  },
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onClose,
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DlnaStatusMessage extends StatelessWidget {
  const DlnaStatusMessage({
    super.key,
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final color = isError
        ? visualTheme.destructive
        : AppVisualTokens.primaryBlue;
    final background = Color.alphaBlend(
      color.withValues(alpha: 0.12),
      visualTheme.surfaceRaised,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DlnaRouteTile extends StatelessWidget {
  const DlnaRouteTile({
    super.key,
    required this.route,
    required this.isLoading,
    required this.onTap,
  });

  final VesperExternalPlaybackRoute route;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: visualTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.tv_rounded,
                  size: 24,
                  color: AppVisualTokens.primaryBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: visualTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (route.manufacturer != null || route.modelName != null)
                        Text(
                          [
                            route.manufacturer,
                            route.modelName,
                          ].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: visualTheme.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: visualTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
