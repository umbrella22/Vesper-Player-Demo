import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../models/bili_models.dart';
import '../services/bili_client.dart';
import '../services/bili_session_store.dart';

/// 扫码登录流程的页面级状态机。
///
/// UI 状态用 signals 表达（`signal<T>` + ReadonlySignal），符合仓库的
/// 状态管理约定：页面级控制器不应使用 ChangeNotifier。消费者通过
/// [revision]（每次状态变化自增）驱动 SignalBuilder 重建，或直接读
/// 各状态的 .value。
final class BiliQrLoginController {
  BiliQrLoginController({
    required this.client,
    required this.sessionStore,
    required this.onConfirmed,
  });

  final BiliClient client;
  final BiliSessionStore sessionStore;
  final ValueChanged<BiliUserProfile> onConfirmed;

  final Signal<BiliQrLoginTicket?> _ticket = Signal<BiliQrLoginTicket?>(null);
  final Signal<BiliQrLoginPollResult?> _pollResult =
      Signal<BiliQrLoginPollResult?>(null);
  final Signal<bool> _isLoading = Signal<bool>(true);
  final Signal<bool> _isPolling = Signal<bool>(false);
  final Signal<String?> _errorMessage = Signal<String?>(null);
  // Bumped on every state change so SignalBuilder can rebuild on any field.
  final Signal<int> _revision = Signal<int>(0);
  Timer? _timer;
  int _generation = 0;
  bool _active = true;
  bool _disposed = false;

  ReadonlySignal<BiliQrLoginTicket?> get ticket => _ticket;
  ReadonlySignal<BiliQrLoginPollResult?> get pollResult => _pollResult;
  ReadonlySignal<bool> get isLoading => _isLoading;
  ReadonlySignal<bool> get isPolling => _isPolling;
  ReadonlySignal<String?> get errorMessage => _errorMessage;

  /// Increments on every state mutation; listen to it to rebuild the whole
  /// login surface when any field changes.
  ReadonlySignal<int> get revision => _revision;

  bool get canRefresh {
    final status = _pollResult.value?.status;
    return _errorMessage.value != null ||
        status == BiliQrLoginStatus.expired ||
        status == BiliQrLoginStatus.failed;
  }

  bool get canCheck => _ticket.value != null && !_isPolling.value;

  String get statusMessage {
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
  }

  String get checkLabel {
    if (_isPolling.value) {
      return '检查中';
    }
    if (_pollResult.value?.status == BiliQrLoginStatus.scannedAwaitingConfirm) {
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
    _isLoading.value = true;
    _isPolling.value = false;
    _errorMessage.value = null;
    _ticket.value = null;
    _pollResult.value = null;
    _notify();

    try {
      final ticket = await client.generateQrLoginTicket();
      if (!_isCurrent(generation)) {
        return;
      }
      _ticket.value = ticket;
      _isLoading.value = false;
      _notify();
      _ensurePollingTimer();
      unawaited(checkNow());
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _isLoading.value = false;
      _errorMessage.value = error.toString();
      _notify();
    }
  }

  Future<void> checkNow() async {
    final ticket = _ticket.value;
    if (ticket == null || _isPolling.value || !_active || _disposed) {
      return;
    }
    final generation = _generation;
    _isPolling.value = true;
    _errorMessage.value = null;
    _notify();
    try {
      final result = await client.pollQrLogin(ticket.qrcodeKey);
      if (!_isCurrent(generation)) {
        return;
      }
      _pollResult.value = result;
      _errorMessage.value = null;
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
      _errorMessage.value = error.toString();
      _stopPollingTimer();
    } finally {
      if (_isCurrent(generation)) {
        _isPolling.value = false;
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
    _isPolling.value = false;
    _stopPollingTimer();
  }

  void _ensurePollingTimer() {
    if (!_active ||
        _disposed ||
        _ticket.value == null ||
        _timer?.isActive == true) {
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
      _revision.value += 1;
    }
  }

  void dispose() {
    cancel();
    _disposed = true;
    _ticket.dispose();
    _pollResult.dispose();
    _isLoading.dispose();
    _isPolling.dispose();
    _errorMessage.dispose();
    _revision.dispose();
  }
}
