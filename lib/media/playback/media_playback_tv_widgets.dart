import 'package:material_ui/material_ui.dart';
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
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
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
          autofocus: options.isEmpty,
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
  bool _autofocusSelected = true;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusSelectedOption();
      if (mounted) {
        setState(() {
          _autofocusSelected = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(TvPanelOptionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panelKey != widget.panelKey ||
        oldWidget.options.length != widget.options.length ||
        _selectedIndex(oldWidget.options) != _selectedIndex(widget.options)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusSelectedOption(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _selectedIndex(List<TvPanelOption> options) {
    final index = options.indexWhere((option) => option.selected);
    return index < 0 ? 0 : index;
  }

  void _focusSelectedOption() {
    if (!mounted || !_controller.hasClients || widget.options.isEmpty) {
      return;
    }
    final selectedIndex = _selectedIndex(widget.options);
    _controller.animateTo(
      (selectedIndex * 86.0).clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(widget.options);
    return ListView.separated(
      key: PageStorageKey<String>('tv-panel-list-${widget.panelKey}'),
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
      itemCount: widget.options.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final option = widget.options[index];
        return _TvPanelOptionTile(
          option: option,
          autofocus: _autofocusSelected && index == selectedIndex,
        );
      },
    );
  }
}

class _TvPanelOptionTile extends StatefulWidget {
  const _TvPanelOptionTile({required this.option, required this.autofocus});

  final TvPanelOption option;
  final bool autofocus;

  @override
  State<_TvPanelOptionTile> createState() => _TvPanelOptionTileState();
}

class _TvPanelOptionTileState extends State<_TvPanelOptionTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final selected = option.selected;
    final focused = _focused;
    return TvFocusable(
      autofocus: widget.autofocus,
      debugLabel: 'tv_panel_${option.label}',
      showGlow: false,
      scale: 1,
      focusCornerRadius: 14,
      baseCornerRadius: 14,
      focusArea: TvFocusArea.playbackPanel,
      onFocusChange: (value) {
        setState(() {
          _focused = value;
        });
      },
      onTap: option.onTap,
      child: AnimatedScale(
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
                  ? AppVisualTokens.primaryBlue
                  : const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused
                    ? const Color(0xF2F8FBFF)
                    : selected
                    ? AppVisualTokens.primaryBlue80
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
                                ? Colors.white.withValues(alpha: 0.82)
                                : const Color(0x88FFFFFF),
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
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  )
                else if (focused)
                  const Icon(
                    Icons.radio_button_unchecked_rounded,
                    color: Color(0xCCFFFFFF),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
