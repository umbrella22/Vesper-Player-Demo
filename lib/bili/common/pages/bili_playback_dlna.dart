part of 'bili_playback_page.dart';

extension _BiliPlaybackDlna on _BiliPlaybackPageState {
  Widget? _buildStageProjectionAction(VesperPlayerController controller) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isAndroid) {
      return _StageDlnaProjectionButton(
        state: _dlnaState,
        onTap: () => unawaited(_openStageProjectionPicker()),
      );
    }
    if (isIos) {
      return vesper_ui.VesperAirPlayRouteIconButton(
        controller: controller,
        tintColor: Colors.white,
        activeTintColor: const Color(0xFFFB7299),
        size: 38,
      );
    }
    return null;
  }

  Future<void> _openStageProjectionPicker() async {
    if (_castingSurfaceOpen || _dlnaPickerOpen) {
      return;
    }
    if (!context.mounted) return;

    _setCastingSurfaceOpen(true);
    _ProjectionTarget? target;
    try {
      target = await showModalBottomSheet<_ProjectionTarget>(
        context: context,
        isScrollControlled: false,
        showDragHandle: true,
        backgroundColor: const Color(0xFFF4F4F8),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (sheetContext) {
          return _ProjectionPickerContent(
            onDlna: () =>
                Navigator.of(sheetContext).pop(_ProjectionTarget.dlna),
          );
        },
      );
    } finally {
      _setCastingSurfaceOpen(false);
    }

    if (!mounted || target == null) {
      return;
    }
    switch (target) {
      case _ProjectionTarget.dlna:
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (mounted) {
          await _openDlnaPicker();
        }
    }
  }

  Future<void> _openDlnaPicker() async {
    if (_dlnaPickerOpen) {
      return;
    }

    final isConnected = _dlnaState == BiliDlnaState.connected;
    if (isConnected) {
      final message = await _dlnaManager.disconnect();
      if (message != null && mounted) {
        _showMessage(message);
      }
      return;
    }

    if (!context.mounted) return;
    _setDlnaPickerOpen(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: const Color(0xFFF4F4F8),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (sheetContext) {
          return _DlnaPickerContent(
            manager: _dlnaManager,
            onLoadMedia: _viewModel.loadCurrentPageToDlna,
            onClose: () => Navigator.of(sheetContext).pop(),
            onMessage: _showMessage,
          );
        },
      );
    } finally {
      _setDlnaPickerOpen(false);
      if (_dlnaState == BiliDlnaState.discovering ||
          _dlnaState == BiliDlnaState.error) {
        unawaited(_dlnaManager.stopDiscovery());
      }
    }
  }
}

enum _ProjectionTarget { dlna }

class _StageDlnaProjectionButton extends StatelessWidget {
  const _StageDlnaProjectionButton({required this.state, required this.onTap});

  final BiliDlnaState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      BiliDlnaState.connected => Icons.cast_connected_rounded,
      BiliDlnaState.connecting ||
      BiliDlnaState.discovering => Icons.cast_rounded,
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

class _ProjectionPickerContent extends StatelessWidget {
  const _ProjectionPickerContent({required this.onDlna});

  final VoidCallback onDlna;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                color: const Color(0xFF20232B),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: _ProjectionCastOption()),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProjectionOptionCard(
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

class _ProjectionCastOption extends StatelessWidget {
  const _ProjectionCastOption();

  @override
  Widget build(BuildContext context) {
    return const _ProjectionOptionShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VesperExternalRouteIconButton(size: 56),
          SizedBox(height: 10),
          Text(
            'Cast',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF20232B),
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

class _ProjectionOptionCard extends StatelessWidget {
  const _ProjectionOptionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ProjectionOptionShell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: const Color(0xFFFB7299)),
          const SizedBox(height: 20),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF20232B),
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

class _ProjectionOptionShell extends StatelessWidget {
  const _ProjectionOptionShell({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(height: 118, child: Center(child: child)),
      ),
    );
  }
}

class _DlnaPickerContent extends StatefulWidget {
  const _DlnaPickerContent({
    required this.manager,
    required this.onLoadMedia,
    required this.onClose,
    required this.onMessage,
  });

  final BiliExternalPlaybackManager manager;
  final Future<String?> Function() onLoadMedia;
  final VoidCallback onClose;
  final void Function(String) onMessage;

  @override
  State<_DlnaPickerContent> createState() => _DlnaPickerContentState();
}

class _DlnaPickerContentState extends State<_DlnaPickerContent> {
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
    if (state == BiliDlnaState.connected && !_loadingMedia) {
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
    if (widget.manager.state == BiliDlnaState.error) {
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
                color: const Color(0xFF20232B),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            if (state == BiliDlnaState.discovering) ...[
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    '正在搜索 DLNA 设备…',
                    style: TextStyle(
                      color: Color(0xFF8B9098),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (message != null && message.isNotEmpty) ...[
              _DlnaStatusMessage(
                message: message,
                isError: state == BiliDlnaState.error,
              ),
              const SizedBox(height: 12),
            ],
            if (state == BiliDlnaState.connecting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text(
                      '正在连接设备…',
                      style: TextStyle(
                        color: Color(0xFF8B9098),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (state == BiliDlnaState.discovering &&
                routes.isEmpty &&
                (message == null || message.isEmpty))
              const Text(
                '未发现 DLNA 设备，请确保设备和手机在同一网络下。',
                style: TextStyle(
                  color: Color(0xFF8B9098),
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (routes.isNotEmpty)
              ...routes.map(
                (route) => _DlnaRouteTile(
                  route: route,
                  isLoading: state == BiliDlnaState.connecting,
                  onTap: () {
                    if (state == BiliDlnaState.connecting) return;
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

class _DlnaStatusMessage extends StatelessWidget {
  const _DlnaStatusMessage({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFB3261E) : const Color(0xFF6B5C00);
    final background = isError
        ? const Color(0xFFFFEDEA)
        : const Color(0xFFFFF7D6);
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

class _DlnaRouteTile extends StatelessWidget {
  const _DlnaRouteTile({
    required this.route,
    required this.isLoading,
    required this.onTap,
  });

  final VesperExternalPlaybackRoute route;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
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
                  color: Color(0xFFFB7299),
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
                        style: const TextStyle(
                          color: Color(0xFF20232B),
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
                          style: const TextStyle(
                            color: Color(0xFF8B9098),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Color(0xFF9AA3B2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
