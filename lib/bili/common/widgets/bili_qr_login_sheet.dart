import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:signals/signals_flutter.dart';

import '../models/bili_models.dart';
import '../services/bili_client.dart';
import '../services/bili_session_store.dart';

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
  final _ticket = signal<BiliQrLoginTicket?>(null);
  final _pollResult = signal<BiliQrLoginPollResult?>(null);
  final _isLoading = signal(true);
  final _isPolling = signal(false);
  final _errorMessage = signal<String?>(null);
  late final FlutterComputed<String> _statusMessage;
  late final FlutterComputed<bool> _canRefresh;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _statusMessage = computed(() {
      final errorMessage = _errorMessage.value;
      if (errorMessage != null) {
        return errorMessage;
      }
      return switch (_pollResult.value?.status) {
        BiliQrLoginStatus.waitingForScan || null => '用哔哩哔哩 App 扫码，然后在手机上确认登录。',
        BiliQrLoginStatus.scannedAwaitingConfirm => '已经扫到码了，等手机端确认。',
        BiliQrLoginStatus.confirmed => '登录成功，正在同步账号信息。',
        BiliQrLoginStatus.expired => '二维码已失效，刷新后重新扫码。',
        BiliQrLoginStatus.failed => _pollResult.value?.message ?? '登录失败。',
      };
    });
    _canRefresh = computed(() {
      return _errorMessage.value != null ||
          _pollResult.value?.status == BiliQrLoginStatus.expired;
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusMessage.dispose();
    _canRefresh.dispose();
    _ticket.dispose();
    _pollResult.dispose();
    _isLoading.dispose();
    _isPolling.dispose();
    _errorMessage.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _timer?.cancel();
    _isLoading.value = true;
    _errorMessage.value = null;
    _ticket.value = null;
    _pollResult.value = null;

    try {
      final ticket = await widget.client.generateQrLoginTicket();
      if (!mounted) {
        return;
      }
      _ticket.value = ticket;
      _isLoading.value = false;
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_poll()),
      );
      unawaited(_poll());
    } catch (error) {
      if (!mounted) {
        return;
      }
      _isLoading.value = false;
      _errorMessage.value = error.toString();
    }
  }

  Future<void> _poll() async {
    final ticket = _ticket.value;
    if (ticket == null || _isPolling.value) {
      return;
    }
    _isPolling.value = true;
    try {
      final result = await widget.client.pollQrLogin(ticket.qrcodeKey);
      if (!mounted) {
        return;
      }
      _pollResult.value = result;

      if (result.status == BiliQrLoginStatus.confirmed) {
        _timer?.cancel();
        final profile = await widget.client.fetchCurrentUserProfile();
        await widget.sessionStore.saveCookies(widget.client.snapshotCookies());
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop(profile);
        return;
      }

      if (result.status.isTerminal) {
        _timer?.cancel();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _errorMessage.value = error.toString();
      _timer?.cancel();
    } finally {
      if (mounted) {
        _isPolling.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(32),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
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
                          color: const Color(0xFF142237),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '登录后的 cookie 会带入搜索、详情、推荐流与播放解析。当前实现按 Web 端二维码登录流程走。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x120A1628),
                          blurRadius: 32,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SizedBox(
                        width: 240,
                        height: 240,
                        child: SignalBuilder(builder: _buildQrContent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SignalBuilder(builder: _buildStatusMessage),
                const SizedBox(height: 20),
                SignalBuilder(builder: _buildActions),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrContent(BuildContext context) {
    final ticket = _ticket.value;
    if (_isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ticket == null) {
      return const Icon(
        Icons.qr_code_2_rounded,
        size: 88,
        color: Color(0xFF7B8CA1),
      );
    }
    return QrImageView(
      data: ticket.url,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF111A2B),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF111A2B),
      ),
    );
  }

  Widget _buildStatusMessage(BuildContext context) {
    final theme = Theme.of(context);
    final message = _statusMessage.value;
    final timestampMs = _pollResult.value?.timestampMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            message,
            key: ValueKey<String>(message),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _errorMessage.value == null
                  ? const Color(0xFF526477)
                  : const Color(0xFF9A3453),
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
            onPressed: _canRefresh.value ? _bootstrap : null,
            child: const Text('刷新二维码'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _ticket.value == null || _isPolling.value ? null : _poll,
            child: Text(
              _isPolling.value
                  ? '检查中'
                  : _pollResult.value?.status ==
                        BiliQrLoginStatus.scannedAwaitingConfirm
                  ? '已扫码，继续等待'
                  : '立即检查状态',
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
