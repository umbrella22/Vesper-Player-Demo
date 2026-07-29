import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/app/design/app_visual_theme.dart';

import '../models/bili_models.dart';
import '../services/bili_client.dart';
import '../services/bili_session_store.dart';
import 'bili_glass_sheet.dart';
import 'bili_qr_code_view.dart';
import 'bili_qr_login_controller.dart';

Future<BiliUserProfile?> showBiliQrLoginSheet({
  required BuildContext context,
  required BiliClient client,
  required BiliSessionStore sessionStore,
}) {
  return showBiliGlassSheet<BiliUserProfile>(
    context: context,
    maxContentHeightFactor: 0.86,
    contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
    appearance: BiliGlassSheetAppearance.readable,
    builder: (_) =>
        BiliQrLoginSheet(client: client, sessionStore: sessionStore),
  );
}

class BiliQrLoginSheet extends StatefulWidget {
  const BiliQrLoginSheet({
    super.key,
    required this.client,
    required this.sessionStore,
  });

  final BiliClient client;
  final BiliSessionStore sessionStore;

  @override
  State<BiliQrLoginSheet> createState() => _BiliQrLoginSheetState();
}

class _BiliQrLoginSheetState extends State<BiliQrLoginSheet> {
  late final BiliQrLoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BiliQrLoginController(
      client: widget.client,
      sessionStore: widget.sessionStore,
      onConfirmed: _handleConfirmed,
    );
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleConfirmed(BiliUserProfile profile) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    Navigator.of(context).pop(profile);
  }

  void _dismiss() {
    _controller.cancel();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final qrSize = (MediaQuery.sizeOf(context).height * 0.30)
        .clamp(200.0, 240.0)
        .toDouble();

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _controller.cancel();
        }
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '扫码登录哔哩哔哩',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: visualTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _dismiss,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '使用哔哩哔哩 App 扫码并确认，登录状态将保存在本机。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: visualTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: DecoratedBox(
                key: const ValueKey<String>('bili-qr-code-surface'),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.28 : 0.08,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: SizedBox(
                    width: qrSize,
                    height: qrSize,
                    child: BiliQrCodeView(
                      ticket: _controller.ticket,
                      isLoading: _controller.isLoading,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _buildStatusMessage(context),
            const SizedBox(height: 20),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMessage(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    final message = _controller.statusMessage;
    final timestampMs = _controller.pollResult?.timestampMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            message,
            key: ValueKey<String>(message),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _controller.errorMessage == null
                  ? visualTheme.textSecondary
                  : theme.colorScheme.error,
              height: 1.5,
            ),
          ),
        ),
        if (timestampMs != null) ...[
          const SizedBox(height: 8),
          Text(
            '状态更新时间 ${_formatTimestamp(timestampMs)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _controller.canRefresh ? _controller.refresh : null,
            child: const Text('刷新二维码'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _controller.canCheck ? _controller.checkNow : null,
            child: Text(_controller.checkLabel),
          ),
        ),
      ],
    );
  }
}

String _formatTimestamp(int timestampMs) {
  final dateTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}
