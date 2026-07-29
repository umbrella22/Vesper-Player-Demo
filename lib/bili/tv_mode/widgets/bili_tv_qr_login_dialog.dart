import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/app/design/app_visual_theme.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';
import 'package:vesper_media/bili/common/widgets/bili_qr_code_view.dart';
import 'package:vesper_media/bili/common/widgets/bili_qr_login_controller.dart';
import 'package:vesper_media/bili/tv_mode/widgets/tv_glass_dialog.dart';

Future<BiliUserProfile?> showBiliTvQrLoginDialog({
  required BuildContext context,
  required BiliClient client,
  required BiliSessionStore sessionStore,
}) {
  return showBiliTvGlassOverlay<BiliUserProfile>(
    context: context,
    maxWidth: 930,
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
          final qrSize = (screenSize.height * (compact ? 0.34 : 0.32))
              .clamp(132.0, 250.0)
              .toDouble();
          return BiliTvGlassDialogSurface(
            title: '登录 Bilibili 账号',
            icon: Icons.qr_code_scanner_rounded,
            scrollController: _scrollController,
            surfaceKey: const ValueKey<String>('bili-tv-qr-login-surface'),
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQrColumn(qrSize, compact: compact),
                SizedBox(width: compact ? 24 : 36),
                Expanded(child: _buildLoginPanel(qrSize, compact: compact)),
              ],
            ),
            footer: Row(
              children: [
                Expanded(
                  child: BiliTvDialogButton(
                    label: '刷新二维码',
                    icon: Icons.refresh_rounded,
                    autofocus: true,
                    enabled: !_controller.isLoading,
                    debugLabel: 'tv_qr_login_refresh',
                    onTap: () => unawaited(_controller.refresh()),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: BiliTvDialogButton(
                    label: '取消',
                    icon: Icons.close_rounded,
                    debugLabel: 'tv_qr_login_cancel',
                    onTap: _dismiss,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQrColumn(double qrSize, {required bool compact}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2D34),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x24FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 20,
            offset: Offset(0, 9),
          ),
        ],
      ),
      padding: EdgeInsets.all(compact ? 14 : 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            key: const ValueKey<String>('bili-tv-qr-code-surface'),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: qrSize,
                child: BiliQrCodeView(
                  ticket: _controller.ticket,
                  isLoading: _controller.isLoading,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _controller.errorMessage == null
                      ? const Color(0xFF57D38C)
                      : const Color(0xFFFF7B83),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _controller.errorMessage == null
                      ? '二维码有效，请使用手机扫码'
                      : '二维码需要刷新',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoginPanel(double qrSize, {required bool compact}) {
    final error = _controller.errorMessage != null;
    final timestampMs = _controller.pollResult?.timestampMs;
    return SizedBox(
      height: qrSize + (compact ? 58 : 66),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '登录后可以同步收藏、关注与播放记录。',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xA6FFFFFF),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          SizedBox(height: compact ? 10 : 16),
          const _TvLoginStep(index: 1, label: '打开哔哩哔哩客户端'),
          SizedBox(height: compact ? 7 : 10),
          const _TvLoginStep(index: 2, label: '使用扫一扫扫描左侧二维码'),
          SizedBox(height: compact ? 7 : 10),
          const _TvLoginStep(index: 3, label: '在手机上确认登录'),
          const Spacer(),
          AnimatedContainer(
            duration: AppVisualTokens.motionDuration(
              context,
              AppVisualTokens.overlayDuration,
            ),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: error ? const Color(0x18FF7B83) : const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: error
                    ? const Color(0x40FF7B83)
                    : const Color(0x1FFFFFFF),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  error ? Icons.error_outline_rounded : Icons.sync_rounded,
                  color: error
                      ? const Color(0xFFFFA1A7)
                      : const Color(0xB3FFFFFF),
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppVisualTokens.motionDuration(
                      context,
                      AppVisualTokens.overlayDuration,
                    ),
                    child: Text(
                      _controller.statusMessage,
                      key: ValueKey<String>(_controller.statusMessage),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: error
                            ? const Color(0xFFFFB4AB)
                            : const Color(0xD9FFFFFF),
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (timestampMs != null) ...[
            const SizedBox(height: 6),
            Text(
              '状态更新时间 ${_formatTimestamp(timestampMs)}',
              style: const TextStyle(
                color: Color(0x8FFFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TvLoginStep extends StatelessWidget {
  const _TvLoginStep({required this.index, required this.label});

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0x1FFFFFFF),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xD9FFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
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
