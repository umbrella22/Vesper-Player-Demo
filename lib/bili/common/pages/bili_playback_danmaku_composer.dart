import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_icons.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/media.dart';

enum DanmakuEventAction { copyText, toggleSenderBlock, toggleLike, retract }

/// 点选弹幕后弹出的操作面板。
///
/// 交互边界（与设计文档一致）：
/// - 本地屏蔽不需要服务端标识，任何时候都可用；
/// - 点赞与撤回需要 dmid，源没有提供 dmid（合成 ID）时这两项不出现——
///   合成 ID 只用于本地去重与渲染，绝不用于服务端操作。
class DanmakuEventSheet extends StatelessWidget {
  const DanmakuEventSheet({
    super.key,
    required this.event,
    required this.senderBlocked,
    this.interaction = const MediaDanmakuInteractionState(),
  });

  final MediaDanmakuEvent event;
  final bool senderBlocked;
  final MediaDanmakuInteractionState interaction;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '弹幕操作',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: visualTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: visualTheme.divider),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                event.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: visualTheme.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (event.hasServerId && interaction.canLike) ...[
            DanmakuSheetAction(
              key: const ValueKey<String>('danmaku-action-like'),
              icon: interaction.liked
                  ? AppIcons.thumbUpFill
                  : AppIcons.thumbUpLine,
              label: switch ((interaction.pending, interaction.liked)) {
                (true, _) => '处理中…',
                (false, true) => '取消点赞',
                (false, false) => '点赞弹幕',
              },
              onTap: interaction.pending
                  ? null
                  : () =>
                        Navigator.of(context)
                            .pop(DanmakuEventAction.toggleLike),
            ),
            const SizedBox(height: 8),
          ],
          if (event.hasServerId && interaction.canRetract) ...[
            DanmakuSheetAction(
              key: const ValueKey<String>('danmaku-action-retract'),
              icon: AppIcons.arrowGoBackLine,
              label: '撤回我的弹幕',
              onTap: interaction.pending
                  ? null
                  : () => Navigator.of(context).pop(DanmakuEventAction.retract),
            ),
            const SizedBox(height: 8),
          ],
          DanmakuSheetAction(
            key: const ValueKey<String>('danmaku-action-copy'),
            icon: AppIcons.fileCopyLine,
            label: '复制内容',
            onTap: () => Navigator.of(context).pop(DanmakuEventAction.copyText),
          ),
          if (event.senderHash.isNotEmpty) ...[
            const SizedBox(height: 8),
            DanmakuSheetAction(
              key: const ValueKey<String>('danmaku-action-block-sender'),
              icon: senderBlocked ? AppIcons.eyeLine : AppIcons.eyeOffLine,
              label: senderBlocked ? '取消屏蔽该发送者' : '屏蔽该发送者',
              onTap: () =>
                  Navigator.of(context)
                      .pop(DanmakuEventAction.toggleSenderBlock),
            ),
          ],
          if (!event.hasServerId) ...[
            const SizedBox(height: 10),
            Text(
              '这条弹幕缺少编号，无法点赞或撤回。',
              style: TextStyle(color: visualTheme.textTertiary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class DanmakuSheetAction extends StatelessWidget {
  const DanmakuSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: visualTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(AppVisualTokens.controlRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppVisualTokens.controlRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: visualTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: visualTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 手机播放页标签栏的弹幕入口，点击后在键盘上方打开输入栏。
///
/// 提交策略遵循设计约定：
/// - 成功后才由会话把弹幕插入快照，输入框清空；
/// - 失败保留草稿并提示，不自动重发；
/// - 结果未知（超时）也保留草稿，由后续对账决定。
///
/// TV 不提供该入口。
class BiliDanmakuComposer extends StatefulWidget {
  const BiliDanmakuComposer({
    super.key,
    required this.sendController,
    required this.currentPositionMs,
  });

  final MediaDanmakuSendController sendController;

  /// 输入期间视频仍可继续播放，提交时读取最新播放位置。
  final int Function() currentPositionMs;

  @override
  State<BiliDanmakuComposer> createState() => _BiliDanmakuComposerState();
}

class _BiliDanmakuComposerState extends State<BiliDanmakuComposer> {
  String _draft = '';
  bool _inputOpen = false;

  Future<void> _openInput() async {
    if (_inputOpen) return;
    _inputOpen = true;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      showDragHandle: false,
      backgroundColor: AppVisualTheme.of(context).surface,
      barrierColor: AppVisualTheme.of(context).scrim.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(),
      sheetAnimationStyle: AnimationStyle(
        duration: AppVisualTokens.motionDuration(
          context,
          AppVisualTokens.overlayDuration,
        ),
      ),
      builder: (context) => _DanmakuInputSheet(
        sendController: widget.sendController,
        currentPositionMs: () => widget.currentPositionMs(),
        draft: _draft,
        onDraftChanged: (value) => _draft = value,
      ),
    );
    _inputOpen = false;
    if (!mounted || sent != true) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('弹幕已发送')));
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return AppPressScale(
      child: TextButton(
        key: const ValueKey<String>('bili-danmaku-entry'),
        onPressed: () => unawaited(_openInput()),
        style: TextButton.styleFrom(
          foregroundColor: visualTheme.textSecondary,
          backgroundColor: visualTheme.surfaceRaised,
          minimumSize: const Size(40, 30),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: const StadiumBorder(),
          textStyle: Theme.of(context).textTheme.bodySmall,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('点我发弹幕'),
            SizedBox(width: 6),
            Icon(AppIcons.chat3Line, size: 14),
          ],
        ),
      ),
    );
  }
}

class _DanmakuInputSheet extends StatefulWidget {
  const _DanmakuInputSheet({
    required this.sendController,
    required this.currentPositionMs,
    required this.draft,
    required this.onDraftChanged,
  });

  final MediaDanmakuSendController sendController;
  final int Function() currentPositionMs;
  final String draft;
  final ValueChanged<String> onDraftChanged;

  @override
  State<_DanmakuInputSheet> createState() => _DanmakuInputSheetState();
}

class _DanmakuInputSheetState extends State<_DanmakuInputSheet> {
  late final _controller = TextEditingController(text: widget.draft);
  final _sending = signal(false);
  final _message = signal<String?>(null);
  final _isError = signal(false);

  @override
  void dispose() {
    _controller.dispose();
    _sending.dispose();
    _message.dispose();
    _isError.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending.value) {
      return;
    }
    _sending.value = true;
    _message.value = null;
    _isError.value = false;
    late final MediaDanmakuSendResult result;
    try {
      result = await widget.sendController.send(
        MediaDanmakuSendRequest(
          text: text,
          positionMs: widget.currentPositionMs(),
        ),
      );
    } catch (_) {
      if (mounted) {
        _isError.value = true;
        _message.value = '发送结果未确认，请在弹幕列表中查看。';
      }
      return;
    } finally {
      if (mounted) _sending.value = false;
    }
    if (!mounted) return;
    if (result.isSuccess) {
      _controller.clear();
      widget.onDraftChanged('');
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pop(true);
      return;
    }
    _isError.value = !result.isPending;
    _message.value = result.isPending
        ? '弹幕可能已发送，请稍后在弹幕列表中确认。'
        : (result.errorMessage ?? '弹幕发送失败。');
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sendIconColor = isDark
        ? AppVisualTokens.primaryBlue
        : const Color(0xFF0B5CAD);
    return SignalBuilder(
      builder: (context) => PopScope(
        canPop: !_sending.value,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: visualTheme.surface,
            border: Border(
              top: BorderSide(
                color: highContrast
                    ? visualTheme.textPrimary
                    : visualTheme.divider,
                width: highContrast ? 1.5 : 1.0,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                key: const ValueKey<String>('bili-danmaku-input-bar'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_message.value case final String message)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            message,
                            style: TextStyle(
                              color: _isError.value
                                  ? visualTheme.destructive
                                  : visualTheme.textSecondary,
                              fontWeight: _isError.value
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey<String>('bili-danmaku-input'),
                            controller: _controller,
                            autofocus: true,
                            readOnly: _sending.value,
                            textInputAction: TextInputAction.send,
                            maxLength: 100,
                            onChanged: widget.onDraftChanged,
                            onSubmitted: (_) => unawaited(_submit()),
                            decoration: InputDecoration(
                              hintText: '发个友善的弹幕见证当下',
                              hintStyle: TextStyle(
                                color: visualTheme.textTertiary,
                                fontSize: 14,
                              ),
                              counterText: '',
                              isDense: true,
                              filled: true,
                              fillColor: visualTheme.surfaceRaised,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: highContrast
                                    ? BorderSide(color: visualTheme.textPrimary)
                                    : BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: highContrast
                                    ? BorderSide(color: visualTheme.textPrimary)
                                    : BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppPressScale(
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _controller,
                            builder: (context, value, _) {
                              final hasText = value.text.trim().isNotEmpty;
                              return IconButton(
                                key: const ValueKey<String>(
                                  'bili-danmaku-send',
                                ),
                                tooltip: '发送弹幕',
                                color: hasText && !_sending.value
                                    ? sendIconColor
                                    : visualTheme.textTertiary,
                                onPressed: _sending.value
                                    ? null
                                    : () => unawaited(_submit()),
                                icon: _sending.value
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(AppIcons.sendPlaneLine),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
