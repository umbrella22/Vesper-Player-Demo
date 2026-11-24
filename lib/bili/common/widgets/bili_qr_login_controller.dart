import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../models/bili_models.dart';
import '../services/bili_api_core.dart';
import '../services/bili_client.dart';
import '../services/bili_session_store.dart';

/// Owns one QR ticket at a time. Both login surfaces read the same signals.
final class BiliQrLoginController {
  BiliQrLoginController({
    required this.client,
    required this.sessionStore,
    required this.onConfirmed,
  });

  final BiliClient client;
  final BiliSessionStore sessionStore;
  final ValueChanged<BiliUserProfile> onConfirmed;

  final _ticket = signal<BiliQrLoginTicket?>(null);
  final _pollResult = signal<BiliQrLoginPollResult?>(null);
  final _isLoading = signal(true);
  final _manualCheckPending = signal(false);
  final _errorMessage = signal<String?>(null);
  Timer? _timer;
  Future<void>? _inFlight;
  int _generation = 0;
  int _pollDelaySeconds = 2;
  bool _disposed = false;
  bool _active = false;
  int _ticketSessionRevision = 0;
  Map<String, String>? _previousCookies;
  int? _provisionalRevision;

  ReadonlySignal<BiliQrLoginTicket?> get ticket => _ticket;
  ReadonlySignal<BiliQrLoginPollResult?> get pollResult => _pollResult;
  ReadonlySignal<bool> get isLoading => _isLoading;
  ReadonlySignal<String?> get errorMessage => _errorMessage;

  bool get canRefresh =>
      !_isLoading.value &&
      _pollResult.value?.status != BiliQrLoginStatus.confirmed;
  bool get canCheck =>
      _ticket.value != null &&
      _pollResult.value?.status.isTerminal != true &&
      !_manualCheckPending.value;

  String get statusMessage {
    final errorMessage = _errorMessage.value;
    if (errorMessage != null) return errorMessage;
    return switch (_pollResult.value?.status) {
      BiliQrLoginStatus.waitingForScan || null => '用哔哩哔哩 App 扫码，然后在手机上确认登录。',
      BiliQrLoginStatus.scannedAwaitingConfirm => '已扫码，请在手机上确认登录。',
      BiliQrLoginStatus.confirmed => '登录成功，正在同步账号信息。',
      BiliQrLoginStatus.expired => '二维码已失效，刷新后重新扫码。',
      BiliQrLoginStatus.failed => _failedMessage(),
    };
  }

  String _failedMessage() {
    final msg = _pollResult.value?.message.trim();
    return (msg == null || msg.isEmpty) ? '登录失败，请刷新二维码重试。' : msg;
  }

  String get checkLabel {
    if (_manualCheckPending.value) return '检查中';
    if (_pollResult.value?.status == BiliQrLoginStatus.scannedAwaitingConfirm) {
      return '已扫码，继续等待';
    }
    return '立即检查状态';
  }

  Future<void> start() => refresh();

  Future<void> refresh() async {
    if (_disposed || _pollResult.value?.status == BiliQrLoginStatus.confirmed) {
      return;
    }
    cancel();
    final generation = _generation;
    _active = true;
    _ticketSessionRevision = client.sessionRevision;
    _isLoading.value = true;
    _ticket.value = null;
    _pollResult.value = null;
    _errorMessage.value = null;
    _pollDelaySeconds = 2;
    try {
      final ticket = await client.generateQrLoginTicket();
      if (!_isCurrent(generation)) return;
      _ticket.value = ticket;
      _isLoading.value = false;
      unawaited(_check());
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _isLoading.value = false;
      _errorMessage.value = biliErrorMessage(error);
    }
  }

  Future<void> checkNow() => _check(manual: true);

  Future<void> _check({bool manual = false}) {
    final ticket = _ticket.value;
    if (!_active ||
        _disposed ||
        ticket == null ||
        _pollResult.value?.status.isTerminal == true) {
      return Future<void>.value();
    }
    if (manual) _manualCheckPending.value = true;
    _timer?.cancel();
    final generation = _generation;
    return _inFlight ??= _poll(ticket, generation).whenComplete(() {
      if (_isCurrent(generation)) {
        _inFlight = null;
        _manualCheckPending.value = false;
      }
    });
  }

  Future<void> _poll(BiliQrLoginTicket ticket, int generation) async {
    final BiliQrLoginPollResult result;
    try {
      result = await client.pollQrLogin(ticket.qrcodeKey);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      final transient =
          error is SocketException ||
          error is HandshakeException ||
          error is TlsException ||
          error is HttpException ||
          error is TimeoutException ||
          (error is BiliApiException &&
              (error.outcomeUnknown ||
                  (error.code != null &&
                      error.code! >= 500 &&
                      error.code! < 600)));
      _errorMessage.value = transient ? '连接中断，将自动重试。' : biliErrorMessage(error);
      if (transient) {
        _pollDelaySeconds = (_pollDelaySeconds * 2).clamp(2, 32);
        _schedulePoll();
      }
      return;
    }
    if (!_isCurrent(generation)) return;
    if (client.sessionRevision != _ticketSessionRevision) {
      _fail('账号状态已变更，请刷新二维码。');
      return;
    }
    _pollResult.value = result;
    _errorMessage.value = null;
    _pollDelaySeconds = 2;
    if (result.status == BiliQrLoginStatus.confirmed) {
      await _confirm(result, generation);
    } else if (!result.status.isTerminal) {
      _schedulePoll();
    }
  }

  Future<void> _confirm(BiliQrLoginPollResult result, int generation) async {
    final BiliUserProfile profile;
    try {
      _previousCookies = client.snapshotCookies();
      client.acceptQrLogin(result);
      _provisionalRevision = client.sessionRevision;
      bool ownsSession() =>
          _isCurrent(generation) &&
          _provisionalRevision == client.sessionRevision;
      profile = await client.fetchCurrentUserProfile();
      if (!ownsSession() || !profile.isLoggedIn) {
        throw const BiliApiException('无法验证登录账号，请刷新二维码。');
      }
      try {
        await sessionStore.saveCookiesWhileCurrent(
          client.snapshotCookies(),
          isCurrent: ownsSession,
        );
      } catch (error) {
        debugPrint('[BiliQR] session persistence failed: ${error.runtimeType}');
        throw const BiliApiException('无法保存登录信息，请稍后重新扫码。');
      }
      if (!ownsSession()) throw const BiliApiException('账号状态已变更，请刷新二维码。');
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _rollbackCredentials();
      _fail(biliErrorMessage(error));
      return;
    }
    _previousCookies = null;
    _provisionalRevision = null;
    cancel();
    onConfirmed(profile);
  }

  void _fail(String message) {
    _pollResult.value = BiliQrLoginPollResult(
      status: BiliQrLoginStatus.failed,
      message: message,
    );
    _errorMessage.value = message;
  }

  void _schedulePoll() {
    _timer = Timer(
      Duration(seconds: _pollDelaySeconds),
      () => unawaited(_check()),
    );
  }

  void _rollbackCredentials() {
    final previous = _previousCookies;
    if (previous != null && _provisionalRevision == client.sessionRevision) {
      client.restoreCookies(previous);
    }
    _previousCookies = null;
    _provisionalRevision = null;
  }

  bool _isCurrent(int generation) =>
      _active && !_disposed && generation == _generation;

  void cancel() {
    if (_disposed) return;
    _generation++;
    _active = false;
    _timer?.cancel();
    _inFlight = null;
    _manualCheckPending.value = false;
    _rollbackCredentials();
  }

  void dispose() {
    cancel();
    _disposed = true;
    _ticket.dispose();
    _pollResult.dispose();
    _isLoading.dispose();
    _manualCheckPending.dispose();
    _errorMessage.dispose();
  }
}
