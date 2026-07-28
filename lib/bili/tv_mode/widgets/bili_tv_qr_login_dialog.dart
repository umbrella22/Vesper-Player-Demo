import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:bilibili_player/app/design/app_visual_theme.dart';
import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_session_store.dart';
import 'package:bilibili_player/bili/common/widgets/bili_qr_code_view.dart';
import 'package:bilibili_player/bili/common/widgets/bili_qr_login_controller.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_glass_dialog.dart';

Future<BiliUserProfile?> showBiliTvQrLoginDialog({
  required BuildContext context,
  required BiliClient client,
  required BiliSessionStore sessionStore,
}) {
  return showBiliTvGlassOverlay<BiliUserProfile>(
    context: context,
    maxWidth: 820,
    debugLabel: 'tv_qr_login_dialog',
    builder: (dialogContext, dismiss) => BiliTvQrLoginDialog(
      client: client,
      sessionStore: sessionStore,
      onDismiss: dismiss,
      onConfirmed: (profile) => Navigator.of(dialogContext).pop(profile),
    ),
  );
}

class BiliTvQrLoginDialog extends StatefulWidget {
  const BiliTvQrLoginDialog({
    super.key,
    required this.client,
    required this.sessionStore,
    required this.onDismiss,
    required this.onConfirmed,
  });

  final BiliClient client;
  final BiliSessionStore sessionStore;
  final VoidCallback onDismiss;
  final ValueChanged<BiliUserProfile> onConfirmed;

  @override
  State<BiliTvQrLoginDialog> createState() => _BiliTvQrLoginDialogState();
}

class _BiliTvQrLoginDialogState extends State<BiliTvQrLoginDialog> {
  late final BiliQrLoginController _controller;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = BiliQrLoginController(
      client: widget.client,
      sessionStore: widget.sessionStore,
      onConfirmed: _handleConfirmed,
    );
    unawaited(_controller.start());
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealFooter());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _revealFooter() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final target = _scrollController.position.maxScrollExtent;
    if (target <= 0) {
      return;
    }
    final duration = AppVisualTokens.motionDuration(
      context,
      const Duration(milliseconds: 160),
    );
    if (duration == Duration.zero) {
      _scrollController.jumpTo(target);
      return;
    }
    unawaited(
      _scrollController.animateTo(
        target,
        duration: duration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _handleConfirmed(BiliUserProfile profile) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    widget.onConfirmed(profile);
  }

  void _dismiss() {
    _controller.cancel();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _controller.cancel();
        }
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final screenSize = MediaQuery.sizeOf(context);
          final compact = screenSize.height < 560;
          final qrSize = (screenSize.height * (compact ? 0.28 : 0.30))
              .clamp(132.0, 230.0)
              .toDouble();
          return BiliTvGlassDialogSurface(
            title: '扫码登录',
            icon: Icons.qr_code_scanner_rounded,
            scrollController: _scrollController,
            surfaceKey: const ValueKey<String>('bili-tv-qr-login-surface'),
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQrSurface(qrSize),
                SizedBox(width: compact ? 22 : 30),
                Expanded(child: _buildStatusPanel(qrSize, compact: compact)),
              ],
            ),
            footer: Row(
              children: [
                Expanded(
                  child: BiliTvDialogButton(
                    label: '关闭',
                    icon: Icons.close_rounded,
                    autofocus: true,
                    debugLabel: 'tv_qr_login_close',
                    onTap: _dismiss,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: BiliTvDialogButton(
                    label: '刷新二维码',
                    icon: Icons.refresh_rounded,
                    enabled: _controller.canRefresh,
                    debugLabel: 'tv_qr_login_refresh',
                    onTap: () => unawaited(_controller.refresh()),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: BiliTvDialogButton(
                    label: _controller.checkLabel,
                    icon: Icons.sync_rounded,
                    enabled: _controller.canCheck,
                    debugLabel: 'tv_qr_login_check',
                    onTap: () => unawaited(_controller.checkNow()),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQrSurface(double qrSize) {
    return DecoratedBox(
      key: const ValueKey<String>('bili-tv-qr-code-surface'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x1AFFFFFF), spreadRadius: 1),
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox.square(
          dimension: qrSize,
          child: BiliQrCodeView(
            ticket: _controller.ticket,
            isLoading: _controller.isLoading,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPanel(double qrSize, {required bool compact}) {
    final error = _controller.errorMessage != null;
    final timestampMs = _controller.pollResult?.timestampMs;
    return SizedBox(
      height: qrSize + 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '使用手机端哔哩哔哩扫码并确认',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          AnimatedSwitcher(
            duration: AppVisualTokens.motionDuration(
              context,
              AppVisualTokens.overlayDuration,
            ),
            child: Text(
              _controller.statusMessage,
              key: ValueKey<String>(_controller.statusMessage),
              maxLines: compact ? 3 : 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: error
                    ? const Color(0xFFFFB4AB)
                    : const Color(0xD9FFFFFF),
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
          if (timestampMs != null) ...[
            SizedBox(height: compact ? 6 : 10),
            Text(
              '状态更新时间 ${_formatTimestamp(timestampMs)}',
              style: const TextStyle(
                color: Color(0x8FFFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const Spacer(),
          const Row(
            children: [
              Icon(Icons.autorenew_rounded, size: 18, color: Color(0x99FFFFFF)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '状态会自动检查，登录成功后自动关闭',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
