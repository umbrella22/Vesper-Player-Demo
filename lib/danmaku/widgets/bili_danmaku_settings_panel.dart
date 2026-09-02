import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/danmaku/danmaku.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/media.dart';

class BiliDanmakuSettingsPanel extends StatefulWidget {
  const BiliDanmakuSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ValueListenable<BiliDanmakuSettings> settings;
  final ValueChanged<BiliDanmakuSettings> onChanged;

  @override
  State<BiliDanmakuSettingsPanel> createState() =>
      _BiliDanmakuSettingsPanelState();
}

class _BiliDanmakuSettingsPanelState extends State<BiliDanmakuSettingsPanel> {
  late final TextEditingController _keywordController;
  late final TextEditingController _senderController;
  final FocusNode _keywordFocusNode = FocusNode(
    debugLabel: 'danmaku_keyword_filter',
  );
  final FocusNode _senderFocusNode = FocusNode(
    debugLabel: 'danmaku_sender_filter',
  );
  Timer? _editorCommitTimer;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController();
    _senderController = TextEditingController();
    _syncEditors();
    widget.settings.addListener(_syncEditors);
  }

  @override
  void didUpdateWidget(BiliDanmakuSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.settings, widget.settings)) {
      oldWidget.settings.removeListener(_syncEditors);
      widget.settings.addListener(_syncEditors);
      _syncEditors();
    }
  }

  @override
  void dispose() {
    _editorCommitTimer?.cancel();
    _commitEditors();
    widget.settings.removeListener(_syncEditors);
    _keywordController.dispose();
    _senderController.dispose();
    _keywordFocusNode.dispose();
    _senderFocusNode.dispose();
    super.dispose();
  }

  void _syncEditors() {
    final value = widget.settings.value;
    if (!_keywordFocusNode.hasFocus) {
      final text = value.overlay.blockedKeywords.join('\n');
      if (_keywordController.text != text) {
        _keywordController.text = text;
      }
    }
    if (!_senderFocusNode.hasFocus) {
      final text = value.sourceFilter.blockedSenderHashes.join('\n');
      if (_senderController.text != text) {
        _senderController.text = text;
      }
    }
  }

  void _scheduleEditorCommit() {
    _editorCommitTimer?.cancel();
    _editorCommitTimer = Timer(
      const Duration(milliseconds: 350),
      _commitEditors,
    );
  }

  void _commitEditors() {
    _editorCommitTimer?.cancel();
    _editorCommitTimer = null;
    final current = widget.settings.value;
    final keywords = _lines(_keywordController.text);
    final senderHashes = _lines(_senderController.text);
    final next = current.copyWith(
      overlay: current.overlay.copyWith(blockedKeywords: keywords),
      sourceFilter: current.sourceFilter.copyWith(
        blockedSenderHashes: senderHashes,
      ),
    );
    if (next != current) {
      widget.onChanged(next);
    }
  }

  List<String> _lines(String text) {
    return List<String>.unmodifiable(
      text.split(RegExp(r'\r\n?|\n')).where((value) => value.isNotEmpty),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BiliDanmakuSettings>(
      valueListenable: widget.settings,
      builder: (context, settings, _) {
        final overlay = settings.overlay;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelHeading(title: '弹幕设置'),
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                key: const ValueKey<String>('danmaku-settings-enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('显示弹幕'),
                value: overlay.enabled,
                onChanged: (value) =>
                    _setOverlay(settings, overlay.copyWith(enabled: value)),
              ),
            ),
            const SizedBox(height: 8),
            _SectionLabel(label: '类型'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _toggleButton(
                  label: '滚动',
                  selected: overlay.showScroll,
                  onTap: () => _setOverlay(
                    settings,
                    overlay.copyWith(showScroll: !overlay.showScroll),
                  ),
                ),
                _toggleButton(
                  label: '顶部',
                  selected: overlay.showTop,
                  onTap: () => _setOverlay(
                    settings,
                    overlay.copyWith(showTop: !overlay.showTop),
                  ),
                ),
                _toggleButton(
                  label: '底部',
                  selected: overlay.showBottom,
                  onTap: () => _setOverlay(
                    settings,
                    overlay.copyWith(showBottom: !overlay.showBottom),
                  ),
                ),
                _toggleButton(
                  label: '逆向',
                  selected: overlay.showReverse,
                  onTap: () => _setOverlay(
                    settings,
                    overlay.copyWith(showReverse: !overlay.showReverse),
                  ),
                ),
                _toggleButton(
                  label: '字幕',
                  selected: overlay.showCaption,
                  onTap: () => _setOverlay(
                    settings,
                    overlay.copyWith(showCaption: !overlay.showCaption),
                  ),
                ),
                _toggleButton(
                  label: '高级',
                  selected: overlay.showAdvanced,
                  onTap: () => _setOverlay(
                    settings,
                    overlay.copyWith(showAdvanced: !overlay.showAdvanced),
                  ),
                ),
                _toggleButton(
                  label: '彩色',
                  selected: overlay.showColor,
                  onTap: () => _setOverlay(
                    settings,
                    overlay.copyWith(showColor: !overlay.showColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionLabel(label: '显示区域'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in const <(double, String)>[
                  (0.25, '1/4'),
                  (0.5, '1/2'),
                  (0.75, '3/4'),
                  (1.0, '全屏'),
                ])
                  TuningOptionButton(
                    label: option.$2,
                    selected: overlay.displayArea == option.$1,
                    onTap: () => _setOverlay(
                      settings,
                      overlay.copyWith(displayArea: option.$1),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _DanmakuSlider(
              label: '不透明度',
              value: overlay.opacity,
              minimum: 0.1,
              maximum: 1,
              divisions: 9,
              valueFormatter: (value) => '${(value * 100).round()}%',
              onChangeEnd: (value) =>
                  _setOverlay(settings, overlay.copyWith(opacity: value)),
            ),
            _DanmakuSlider(
              label: '同屏密度',
              value: overlay.density,
              minimum: 0.2,
              maximum: 1,
              divisions: 8,
              valueFormatter: (value) => '${(value * 100).round()}%',
              onChangeEnd: (value) =>
                  _setOverlay(settings, overlay.copyWith(density: value)),
            ),
            _DanmakuSlider(
              label: '字号',
              value: overlay.fontScale,
              minimum: 0.6,
              maximum: 1.6,
              divisions: 10,
              valueFormatter: (value) => '${(value * 100).round()}%',
              onChangeEnd: (value) =>
                  _setOverlay(settings, overlay.copyWith(fontScale: value)),
            ),
            _DanmakuSlider(
              label: '云屏蔽等级',
              value: settings.sourceFilter.minimumWeight.toDouble(),
              minimum: 0,
              maximum: 10,
              divisions: 10,
              valueFormatter: (value) => '${value.round()}',
              onChangeEnd: (value) => widget.onChanged(
                settings.copyWith(
                  sourceFilter: settings.sourceFilter.copyWith(
                    minimumWeight: value.round(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey<String>('danmaku-keyword-filter'),
              controller: _keywordController,
              focusNode: _keywordFocusNode,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '关键词'),
              onChanged: (_) => _scheduleEditorCommit(),
              onTapOutside: (_) {
                _keywordFocusNode.unfocus();
                _commitEditors();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('danmaku-sender-filter'),
              controller: _senderController,
              focusNode: _senderFocusNode,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '屏蔽用户 Hash'),
              onChanged: (_) => _scheduleEditorCommit(),
              onTapOutside: (_) {
                _senderFocusNode.unfocus();
                _commitEditors();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _toggleButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return TuningOptionButton(label: label, selected: selected, onTap: onTap);
  }

  void _setOverlay(
    BiliDanmakuSettings settings,
    MediaDanmakuOverlaySettings overlay,
  ) {
    widget.onChanged(settings.copyWith(overlay: overlay));
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: AppVisualTheme.of(context).textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _DanmakuSlider extends StatefulWidget {
  const _DanmakuSlider({
    required this.label,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.divisions,
    required this.valueFormatter,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double minimum;
  final double maximum;
  final int divisions;
  final String Function(double value) valueFormatter;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_DanmakuSlider> createState() => _DanmakuSliderState();
}

class _DanmakuSliderState extends State<_DanmakuSlider> {
  late double _draftValue;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _draftValue = _clamped(widget.value);
  }

  @override
  void didUpdateWidget(_DanmakuSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        (oldWidget.value != widget.value ||
            oldWidget.minimum != widget.minimum ||
            oldWidget.maximum != widget.maximum)) {
      _draftValue = _clamped(widget.value);
    }
  }

  double _clamped(double value) {
    return value.clamp(widget.minimum, widget.maximum).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final valueLabel = widget.valueFormatter(_draftValue);
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: visualTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: _draftValue,
            min: widget.minimum,
            max: widget.maximum,
            divisions: widget.divisions,
            label: valueLabel,
            onChangeStart: (_) {
              _dragging = true;
            },
            onChanged: (value) {
              setState(() {
                _draftValue = value;
              });
            },
            onChangeEnd: (value) {
              setState(() {
                _dragging = false;
                _draftValue = _clamped(value);
              });
              widget.onChangeEnd(value);
            },
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            valueLabel,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
