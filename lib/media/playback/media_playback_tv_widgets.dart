import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_icons.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/tv/media_tv_focusable.dart';

/// TV 控制条按钮。
class TvBarButton extends StatelessWidget {
  const TvBarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      scale: 1.12,
      focusElevation: 0,
      focusCornerRadius: 12,
      baseCornerRadius: 12,
      showGlow: true,
      focusArea: TvFocusArea.playbackControls,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// TV 侧栏面板中的选项（通用：label + 选中态 + 点击）。
final class TvPanelOption {
  const TvPanelOption({
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
}

/// TV 侧栏面板容器：标题 + 说明 + 选项列表 + 关闭。
class TvPanelDrawer extends StatelessWidget {
  const TvPanelDrawer({
    super.key,
    required this.panelKey,
    required this.label,
    required this.subtitle,
    required this.options,
    required this.emptyMessage,
    required this.onClose,
  });

  /// 面板标识（选项列表滚动位置缓存 key）。
  final String panelKey;
  final String label;
  final String subtitle;
  final List<TvPanelOption> options;
  final String? emptyMessage;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0x88FFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: options.isEmpty
              ? Center(
                  child: Text(
                    emptyMessage ?? '暂无可用选项。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xA6FFFFFF),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                )
              : TvPanelOptionList(panelKey: panelKey, options: options),
        ),
        TvFocusable(
          autofocus: !options.any((option) => option.enabled),
          showGlow: false,
          scale: 1.04,
          focusCornerRadius: 12,
          baseCornerRadius: 12,
          focusArea: TvFocusArea.playbackPanel,
          debugLabel: 'tv_panel_close',
          onTap: onClose,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0x18FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x18FFFFFF)),
            ),
            child: const Text(
              '关闭',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class TvPanelOptionList extends StatefulWidget {
  const TvPanelOptionList({
    super.key,
    required this.panelKey,
    required this.options,
  });

  final String panelKey;
  final List<TvPanelOption> options;

  @override
  State<TvPanelOptionList> createState() => _TvPanelOptionListState();
}

class _TvPanelOptionListState extends State<TvPanelOptionList> {
  late final ScrollController _controller;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _focusNodes = _createFocusNodes(widget.options);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSelectedOption());
  }

  @override
  void didUpdateWidget(TvPanelOptionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    final optionsChanged =
        oldWidget.options.length != widget.options.length ||
        _selectedIndex(oldWidget.options) != _selectedIndex(widget.options) ||
        !_sameEnabledState(oldWidget.options, widget.options);
    final lengthChanged = oldWidget.options.length != widget.options.length;
    if (lengthChanged) {
      final staleNodes = _focusNodes;
      _focusNodes = _createFocusNodes(widget.options);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in staleNodes) {
          node.dispose();
        }
      });
    } else {
      for (var index = 0; index < widget.options.length; index += 1) {
        _focusNodes[index].canRequestFocus = widget.options[index].enabled;
      }
    }
    final focusedOptionBecameDisabled =
        focusedIndex >= 0 &&
        focusedIndex < widget.options.length &&
        !widget.options[focusedIndex].enabled;
    if (oldWidget.panelKey != widget.panelKey ||
        lengthChanged ||
        (optionsChanged && focusedOptionBecameDisabled)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusSelectedOption(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  List<FocusNode> _createFocusNodes(List<TvPanelOption> options) {
    return options
        .map(
          (option) => FocusNode(
            debugLabel: 'tv_panel_${option.label}',
            canRequestFocus: option.enabled,
          ),
        )
        .toList(growable: false);
  }

  bool _sameEnabledState(
    List<TvPanelOption> previous,
    List<TvPanelOption> current,
  ) {
    if (previous.length != current.length) {
      return false;
    }
    for (var index = 0; index < previous.length; index += 1) {
      if (previous[index].enabled != current[index].enabled) {
        return false;
      }
    }
    return true;
  }

  int _selectedIndex(List<TvPanelOption> options) {
    final selectedIndex = options.indexWhere(
      (option) => option.selected && option.enabled,
    );
    if (selectedIndex >= 0) {
      return selectedIndex;
    }
    return options.indexWhere((option) => option.enabled);
  }

  double _optionExtent() {
    final scaler = MediaQuery.textScalerOf(context);
    final hasSubtitles = widget.options.any(
      (option) => option.subtitle != null,
    );
    final textHeight =
        scaler.scale(16) * 1.5 +
        (hasSubtitles ? 3 + scaler.scale(12) * 1.25 * 2 : 0);
    // Leave space for the focus outline, tile padding and gap between rows.
    return 50 + (textHeight < 34 ? 34 : textHeight);
  }

  void _focusSelectedOption() {
    if (!mounted || !_controller.hasClients) return;
    final index = _selectedIndex(widget.options);
    if (index < 0) return;
    final node = _focusNodes[index];
    final position = _controller.position;
    final extent = _optionExtent();
    final start = 8 + index * extent;
    if (start < position.pixels ||
        start + extent > position.pixels + position.viewportDimension) {
      _controller.jumpTo(start.clamp(0.0, position.maxScrollExtent));
    }
    // An unattached FocusNode remembers this request until its lazy row mounts.
    node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: PageStorageKey<String>('tv-panel-list-${widget.panelKey}'),
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
      itemExtent: _optionExtent(),
      itemCount: widget.options.length,
      itemBuilder: (context, index) {
        final option = widget.options[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _TvPanelOptionTile(
            key: ObjectKey(_focusNodes[index]),
            option: option,
            focusNode: _focusNodes[index],
          ),
        );
      },
    );
  }
}

class _TvPanelOptionTile extends StatefulWidget {
  const _TvPanelOptionTile({
    super.key,
    required this.option,
    required this.focusNode,
  });

  final TvPanelOption option;
  final FocusNode focusNode;

  @override
  State<_TvPanelOptionTile> createState() => _TvPanelOptionTileState();
}

class _TvPanelOptionTileState extends State<_TvPanelOptionTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final enabled = option.enabled;
    final selected = option.selected && enabled;
    final focused = _focused && enabled;
    final surface = AnimatedScale(
      scale: focused ? 1.035 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: focused ? const Offset(-0.018, 0) : Offset.zero,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: focused
                ? Colors.white.withValues(alpha: 0.24)
                : selected
                ? AppVisualTokens.primaryActionBlueDark
                : !enabled
                ? const Color(0x0AFFFFFF)
                : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused
                  ? const Color(0xF2F8FBFF)
                  : selected
                  ? const Color(0x66FFFFFF)
                  : !enabled
                  ? const Color(0x10FFFFFF)
                  : const Color(0x16FFFFFF),
              width: focused ? 1.6 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.16),
                      blurRadius: 26,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.36),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: focused || selected
                      ? Colors.white
                      : const Color(0x00FFFFFF),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: focused || selected
                            ? Colors.white
                            : !enabled
                            ? const Color(0x66FFFFFF)
                            : const Color(0xDFFFFFFF),
                        fontSize: 16,
                        fontWeight: focused || selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    if (option.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        option.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: focused || selected
                              ? Colors.white.withValues(alpha: 0.85)
                              : !enabled
                              ? const Color(0x55FFFFFF)
                              : const Color(0xB3FFFFFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (selected)
                const Icon(
                  AppIcons.playFill,
                  color: Colors.white,
                  size: 24,
                )
              else if (focused)
                const Icon(
                  AppIcons.checkboxBlankCircleLine,
                  color: Color(0xCCFFFFFF),
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
    final semanticsLabel = option.subtitle == null
        ? option.label
        : '${option.label}，${option.subtitle}';
    final child = enabled
        ? TvFocusable(
            focusNode: widget.focusNode,
            debugLabel: 'tv_panel_${option.label}',
            showGlow: false,
            scale: 1,
            focusCornerRadius: 14,
            baseCornerRadius: 14,
            focusArea: TvFocusArea.playbackPanel,
            onFocusChange: (value) {
              if (mounted && _focused != value) {
                setState(() {
                  _focused = value;
                });
              }
            },
            onTap: option.onTap,
            child: surface,
          )
        : surface;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: option.selected,
      label: semanticsLabel,
      child: ExcludeSemantics(child: child),
    );
  }
}
