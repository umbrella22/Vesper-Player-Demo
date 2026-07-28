import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/bili_models.dart';
import '../services/bili_client.dart';
import '../services/bili_session_store.dart';

final class BiliQrLoginController extends ChangeNotifier {
  BiliQrLoginController({
    required this.client,
    required this.sessionStore,
    required this.onConfirmed,
  });

  final BiliClient client;
  final BiliSessionStore sessionStore;
  final ValueChanged<BiliUserProfile> onConfirmed;

  BiliQrLoginTicket? _ticket;
  BiliQrLoginPollResult? _pollResult;
  bool _isLoading = true;
  bool _isPolling = false;
  String? _errorMessage;
  Timer? _timer;
  int _generation = 0;
  bool _active = true;
  bool _disposed = false;

  BiliQrLoginTicket? get ticket => _ticket;
  BiliQrLoginPollResult? get pollResult => _pollResult;
  bool get isLoading => _isLoading;
  bool get isPolling => _isPolling;
  String? get errorMessage => _errorMessage;

  bool get canRefresh {
    final status = _pollResult?.status;
    return _errorMessage != null ||
        status == BiliQrLoginStatus.expired ||
        status == BiliQrLoginStatus.failed;
  }

  bool get canCheck => _ticket != null && !_isPolling;

  String get statusMessage {
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return errorMessage;
    }
    return switch (_pollResult?.status) {
      BiliQrLoginStatus.waitingForScan || null => '用哔哩哔哩 App 扫码，然后在手机上确认登录。',
      BiliQrLoginStatus.scannedAwaitingConfirm => '已经扫到码了，等手机端确认。',
      BiliQrLoginStatus.confirmed => '登录成功，正在同步账号信息。',
      BiliQrLoginStatus.expired => '二维码已失效，刷新后重新扫码。',
      BiliQrLoginStatus.failed => _pollResult?.message ?? '登录失败。',
    };
  }

  String get checkLabel {
    if (_isPolling) {
      return '检查中';
    }
    if (_pollResult?.status == BiliQrLoginStatus.scannedAwaitingConfirm) {
      return '已扫码，继续等待';
    }
    return '立即检查状态';
  }

  Future<void> start() => refresh();

  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    _stopPollingTimer();
    _active = true;
    final generation = ++_generation;
    _isLoading = true;
    _isPolling = false;
    _errorMessage = null;
    _ticket = null;
    _pollResult = null;
    _notify();

    try {
      final ticket = await client.generateQrLoginTicket();
      if (!_isCurrent(generation)) {
        return;
      }
      _ticket = ticket;
      _isLoading = false;
      _notify();
      _ensurePollingTimer();
      unawaited(checkNow());
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _isLoading = false;
      _errorMessage = error.toString();
      _notify();
    }
  }

  Future<void> checkNow() async {
    final ticket = _ticket;
    if (ticket == null || _isPolling || !_active || _disposed) {
      return;
    }
    final generation = _generation;
    _isPolling = true;
    _errorMessage = null;
    _notify();
    try {
      final result = await client.pollQrLogin(ticket.qrcodeKey);
      if (!_isCurrent(generation)) {
        return;
      }
      _pollResult = result;
      _errorMessage = null;
      _notify();

      if (result.status == BiliQrLoginStatus.confirmed) {
        _stopPollingTimer();
        final profile = await client.fetchCurrentUserProfile();
        if (!_isCurrent(generation)) {
          return;
        }
        await sessionStore.saveCookies(client.snapshotCookies());
        if (!_isCurrent(generation)) {
          return;
        }
        cancel();
        onConfirmed(profile);
        return;
      }

      if (result.status.isTerminal) {
        _stopPollingTimer();
      } else {
        _ensurePollingTimer();
      }
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _errorMessage = error.toString();
      _stopPollingTimer();
    } finally {
      if (_isCurrent(generation)) {
        _isPolling = false;
        _notify();
      }
    }
  }

  void cancel() {
    if (_disposed || !_active) {
      return;
    }
    _active = false;
    _generation += 1;
    _isPolling = false;
    _stopPollingTimer();
  }

  void _ensurePollingTimer() {
    if (!_active || _disposed || _ticket == null || _timer?.isActive == true) {
      return;
    }
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(checkNow()),
    );
  }

  void _stopPollingTimer() {
    _timer?.cancel();
    _timer = null;
  }

  bool _isCurrent(int generation) =>
      !_disposed && _active && generation == _generation;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    cancel();
    _disposed = true;
    super.dispose();
  }
}
