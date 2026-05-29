import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';

import '../../../player/player_sdk_options.dart';
import '../models/bili_models.dart';

enum BiliDlnaState { idle, discovering, connecting, connected, error }

typedef BiliResolvedPlaybackRefresh = Future<BiliResolvedPlayback> Function();

class BiliExternalPlaybackManager {
  BiliExternalPlaybackManager({
    required BiliVideoDetail detail,
    VesperExternalPlaybackController? dlnaController,
  }) : _detail = detail,
       _dlnaController = dlnaController ?? VesperExternalPlaybackController() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _sessionSubscription = _dlnaController.events.listen(_handleSessionEvent);
    }
  }

  final BiliVideoDetail _detail;
  final VesperExternalPlaybackController _dlnaController;

  BiliDlnaState _state = BiliDlnaState.idle;
  List<VesperExternalPlaybackRoute> _routes =
      const <VesperExternalPlaybackRoute>[];
  String? _message;
  String? _connectedRouteId;
  String? _connectedRouteName;
  String? _disconnectFailureMessage;
  String? _disconnectFailureRouteId;
  String? _retryableLoadDiagnosticMessage;
  String? _retryableLoadDiagnosticCode;
  bool _loadingMedia = false;
  bool _pausedLocalPlayback = false;
  bool _disposed = false;

  StreamSubscription<List<VesperExternalPlaybackRoute>>? _routesSubscription;
  StreamSubscription<VesperExternalPlaybackSessionEvent>? _sessionSubscription;
  VoidCallback? _onChanged;
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  BiliDlnaState get state => _state;

  List<VesperExternalPlaybackRoute> get routes => _routes;

  String? get message => _message;

  String? get connectedRouteName => _connectedRouteName;

  VesperExternalPlaybackController get dlnaController => _dlnaController;

  void setOnChanged(VoidCallback callback) {
    _onChanged = callback;
  }

  void addListener(VoidCallback callback) {
    _listeners.add(callback);
  }

  void removeListener(VoidCallback callback) {
    _listeners.remove(callback);
  }

  void dispose() {
    _disposed = true;
    _routesSubscription?.cancel();
    _routesSubscription = null;
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _dlnaController.dispose();
    _listeners.clear();
  }

  Future<void> startDiscovery() async {
    if (_state == BiliDlnaState.discovering ||
        _state == BiliDlnaState.connecting ||
        _state == BiliDlnaState.connected) {
      return;
    }
    _message = null;
    _disconnectFailureMessage = null;
    _disconnectFailureRouteId = null;
    _routes = const <VesperExternalPlaybackRoute>[];
    _routesSubscription ??= _dlnaController.routes.listen(_handleRoutes);
    _setState(BiliDlnaState.discovering);
    try {
      await _dlnaController.startDiscovery();
    } catch (error) {
      _routesSubscription?.cancel();
      _routesSubscription = null;
      _message = 'DLNA 设备发现启动失败：$error';
      _setState(BiliDlnaState.error);
    }
  }

  Future<void> stopDiscovery() async {
    if (_state == BiliDlnaState.idle ||
        _state == BiliDlnaState.connecting ||
        _state == BiliDlnaState.connected) {
      return;
    }
    try {
      await _dlnaController.stopDiscovery();
    } catch (_) {}
    _routesSubscription?.cancel();
    _routesSubscription = null;
    _setState(BiliDlnaState.idle);
  }

  Future<String?> connect(String routeId) async {
    if (_state != BiliDlnaState.discovering) {
      return '设备列表已过期，请重新刷新。';
    }
    try {
      _setState(BiliDlnaState.connecting);
      await _dlnaController.stopDiscovery();
      _routesSubscription?.cancel();
      _routesSubscription = null;
      final result = await _dlnaController.connect(routeId);
      if (_disposed) return null;
      if (result.isSuccess) {
        _connectedRouteId = result.routeId ?? routeId;
        _disconnectFailureMessage = null;
        _disconnectFailureRouteId = null;
        _message = result.message;
        _setState(BiliDlnaState.connected);
        return null;
      }
      await _failConnection(result.message ?? '连接失败。');
      return _message;
    } catch (error) {
      if (_disposed) return null;
      await _failConnection('DLNA 连接失败：$error');
      return _message;
    }
  }

  Future<String?> loadMedia({
    required BiliResolvedPlayback resolved,
    BiliVideoPageEntry? selectedPage,
    BiliResolvedPlaybackRefresh? refreshResolved,
  }) async {
    if (_state != BiliDlnaState.connected || _connectedRouteId == null) {
      return '请先连接 DLNA 设备。';
    }
    _loadingMedia = true;
    _retryableLoadDiagnosticMessage = null;
    _retryableLoadDiagnosticCode = null;
    try {
      var result = await _loadResolvedMedia(
        resolved: resolved,
        selectedPage: selectedPage,
      );
      if (_disposed) return null;
      if (result.isSuccess) {
        return _completeLoadSuccess();
      }

      if (refreshResolved != null && _shouldRetryLoadFailure(result.message)) {
        _message = '播放地址可能已过期，正在刷新投屏资源…';
        _notify();
        BiliResolvedPlayback refreshed;
        try {
          refreshed = await refreshResolved();
        } catch (error) {
          if (_disposed) return null;
          await _failConnection('播放地址刷新失败：$error');
          return _message;
        }
        if (_disposed) return null;
        if (_state != BiliDlnaState.connected || _connectedRouteId == null) {
          return _message ?? 'DLNA 连接已断开。';
        }
        _retryableLoadDiagnosticMessage = null;
        _retryableLoadDiagnosticCode = null;
        result = await _loadResolvedMedia(
          resolved: refreshed,
          selectedPage: selectedPage,
        );
        if (_disposed) return null;
        if (result.isSuccess) {
          return _completeLoadSuccess();
        }
      }
      await _failConnection(
        _retryableLoadDiagnosticMessage ?? result.message ?? '投屏播放失败。',
      );
      return _message;
    } catch (error) {
      if (_disposed) return null;
      await _failConnection('投屏播放失败：$error');
      return _message;
    } finally {
      _loadingMedia = false;
      _retryableLoadDiagnosticMessage = null;
      _retryableLoadDiagnosticCode = null;
    }
  }

  Future<VesperExternalPlaybackResult> _loadResolvedMedia({
    required BiliResolvedPlayback resolved,
    BiliVideoPageEntry? selectedPage,
  }) {
    final source = resolved.toSource();
    final metadata = buildSystemPlaybackMetadata(resolved, selectedPage);
    final item = VesperExternalPlaybackMediaItem(
      sources: <VesperPlayerSource>[source],
      metadata: metadata,
      proxyPolicy: VesperExternalProxyPolicy.auto,
      formatAdaptation: biliDlnaFormatAdaptationConfig,
    );
    return _dlnaController.load(item);
  }

  String? _completeLoadSuccess() {
    if (_state != BiliDlnaState.connected || _connectedRouteId == null) {
      return _message ?? 'DLNA 连接已断开。';
    }
    _pausedLocalPlayback = true;
    _message = '已投放到 ${_connectedRouteName ?? 'DLNA 设备'}';
    _notify();
    return null;
  }

  Future<String?> disconnect() async {
    if (_state != BiliDlnaState.connected) {
      return null;
    }
    _disconnectFailureMessage = null;
    _disconnectFailureRouteId = null;
    try {
      await _dlnaController.disconnect();
    } catch (_) {}
    _clearConnection();
    _message = null;
    _setState(BiliDlnaState.idle);
    return null;
  }

  Future<void> resumeLocalPlayback({
    required VesperPlayerController controller,
    int? externalPositionMs,
  }) async {
    if (!_pausedLocalPlayback) return;
    _pausedLocalPlayback = false;
    if (externalPositionMs != null) {
      final deltaMs =
          externalPositionMs - controller.snapshot.timeline.positionMs;
      await controller.seekBy(deltaMs);
    }
    await controller.play();
  }

  VesperSystemPlaybackMetadata buildSystemPlaybackMetadata(
    BiliResolvedPlayback resolved,
    BiliVideoPageEntry? page,
  ) {
    final durationSeconds = page?.durationSeconds ?? 0;
    final durationMs = durationSeconds > 0 ? durationSeconds * 1000 : null;
    return biliPlayerSystemPlaybackMetadata(
      title: resolved.title,
      subtitle: resolved.subtitle,
      artist: _detail.ownerName,
      artworkUri: _detail.coverUrl,
      contentUri: resolved.uri,
      durationMs: durationMs,
    );
  }

  void _handleRoutes(List<VesperExternalPlaybackRoute> routes) {
    _routes = routes
        .where((route) => route.kind == VesperExternalPlaybackRouteKind.dlna)
        .toList(growable: false);
    if (_routes.isNotEmpty) {
      _message = null;
    }
    _notify();
  }

  Future<void> _handleSessionEvent(
    VesperExternalPlaybackSessionEvent event,
  ) async {
    switch (event.kind) {
      case VesperExternalPlaybackSessionEventKind.routeConnected:
        _connectedRouteId = event.routeId;
        _connectedRouteName = event.routeName ?? event.routeId;
        _disconnectFailureMessage = null;
        _disconnectFailureRouteId = null;
        _message = '已连接到 ${_connectedRouteName ?? 'DLNA 设备'}';
        _setState(BiliDlnaState.connected);
      case VesperExternalPlaybackSessionEventKind.routeDisconnected:
        final failureMessage = _disconnectFailureMessage;
        _clearConnection();
        if (failureMessage != null &&
            (_disconnectFailureRouteId == null ||
                event.routeId == null ||
                event.routeId == _disconnectFailureRouteId)) {
          _message = failureMessage;
          _setState(BiliDlnaState.error);
          return;
        }
        _message = 'DLNA 连接已断开。';
        _setState(BiliDlnaState.idle);
      case VesperExternalPlaybackSessionEventKind.playing:
        _pausedLocalPlayback = true;
        _notify();
      case VesperExternalPlaybackSessionEventKind.paused:
      case VesperExternalPlaybackSessionEventKind.stopped:
      case VesperExternalPlaybackSessionEventKind.suspended:
        _notify();
      case VesperExternalPlaybackSessionEventKind.loaded:
        _message = null;
        _notify();
      case VesperExternalPlaybackSessionEventKind.discoveryDiagnostic:
        final message = _discoveryDiagnosticMessage(event);
        if (message != null) {
          if (_isFatalPlaybackDiagnostic(event)) {
            if (_shouldHoldRetryableLoadDiagnostic(event)) {
              _retryableLoadDiagnosticMessage = message;
              _retryableLoadDiagnosticCode = event.code;
              _message = '投屏资源加载失败，准备刷新播放地址…';
              _notify();
              return;
            }
            await _failConnection(message, routeId: event.routeId);
            return;
          }
          _message = message;
        }
        _notify();
      case VesperExternalPlaybackSessionEventKind.error:
        if (_shouldHoldRetryableLoadDiagnostic(event)) {
          _retryableLoadDiagnosticMessage = event.message ?? event.code;
          _retryableLoadDiagnosticCode = event.code;
          _message = '投屏资源加载失败，准备刷新播放地址…';
          _notify();
          return;
        }
        await _failConnection(
          event.message ?? 'DLNA 播放出错。',
          routeId: event.routeId,
        );
    }
  }

  Future<void> _failConnection(String message, {String? routeId}) async {
    if (_disposed) {
      return;
    }
    _disconnectFailureMessage = message;
    _disconnectFailureRouteId = routeId ?? _connectedRouteId;
    final shouldDisconnect =
        _state == BiliDlnaState.connecting ||
        _state == BiliDlnaState.connected ||
        _connectedRouteId != null;
    if (shouldDisconnect) {
      try {
        await _dlnaController.disconnect();
      } catch (_) {}
    }
    if (_disposed) {
      return;
    }
    _clearConnection();
    _message = message;
    _setState(BiliDlnaState.error);
  }

  void _clearConnection() {
    _connectedRouteId = null;
    _connectedRouteName = null;
    _pausedLocalPlayback = false;
  }

  void _setState(BiliDlnaState newState) {
    if (_disposed) return;
    _state = newState;
    _notify();
  }

  void _notify() {
    _onChanged?.call();
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  String? _discoveryDiagnosticMessage(
    VesperExternalPlaybackSessionEvent event,
  ) {
    final severity = event.details['severity'];
    if (severity == 'info') {
      return null;
    }
    return switch (event.code) {
      'cleartext_http_blocked' => 'DLNA 设备描述请求被 Android 明文 HTTP 策略拦截。',
      'lan_network_unavailable' => '未检测到可用于 DLNA 搜索的 Wi-Fi 或以太网。',
      'ssdp_no_response' => '暂未收到局域网 DLNA 设备响应，请确认设备和手机在同一网络下。',
      'm_search_permission_denied' ||
      'description_permission_denied' ||
      'network_permission_denied' ||
      'notify_permission_denied' ||
      'multicast_lock_permission_denied' => 'DLNA 搜索缺少网络权限，请检查系统权限设置。',
      _ => event.message ?? event.code,
    };
  }

  bool _isFatalPlaybackDiagnostic(VesperExternalPlaybackSessionEvent event) {
    final severity = event.details['severity']?.toLowerCase();
    if (severity != 'warning' && severity != 'error') {
      return false;
    }
    if (_state != BiliDlnaState.connected &&
        _state != BiliDlnaState.connecting &&
        _connectedRouteId == null) {
      return false;
    }

    final code = event.code?.toLowerCase() ?? '';
    final message = event.message?.toLowerCase() ?? '';
    final details = event.details;
    return code.startsWith('host_') ||
        code.startsWith('relay_') ||
        code.contains('remux') ||
        code == 'unsupported_dash_layout' ||
        code == 'missing_runtime' ||
        code == 'ffmpeg_open_failed' ||
        message.contains('relay') ||
        message.contains('remux') ||
        details.containsKey('inputMode') ||
        details.containsKey('fallbackFormat') ||
        details.containsKey('sessionId');
  }

  bool _shouldHoldRetryableLoadDiagnostic(
    VesperExternalPlaybackSessionEvent event,
  ) {
    if (!_loadingMedia) {
      return false;
    }
    return _isRetryableDlnaLoadFailure(
      event.message,
      code: event.code,
      details: event.details,
    );
  }

  bool _shouldRetryLoadFailure(String? message) {
    return _isRetryableDlnaLoadFailure(
          message,
          code: _retryableLoadDiagnosticCode,
        ) ||
        _isRetryableDlnaLoadFailure(
          _retryableLoadDiagnosticMessage,
          code: _retryableLoadDiagnosticCode,
        );
  }

  bool _isRetryableDlnaLoadFailure(
    String? message, {
    String? code,
    Map<String, String> details = const <String, String>{},
  }) {
    final normalizedCode = code?.toLowerCase() ?? '';
    if (normalizedCode == 'host_fetch_failed' ||
        normalizedCode == 'dash_resource_permission_denied' ||
        normalizedCode.startsWith('http_')) {
      return true;
    }

    final normalizedMessage = message?.toLowerCase() ?? '';
    if (normalizedMessage.contains('failed to fetch dash sidx') ||
        normalizedMessage.contains('dash_resource_permission_denied') ||
        normalizedMessage.contains('host_fetch_failed') ||
        normalizedMessage.contains('http 401') ||
        normalizedMessage.contains('http 403') ||
        normalizedMessage.contains('http 404') ||
        normalizedMessage.contains('did not honor byte range') ||
        normalizedMessage.contains('invalid content-range') ||
        normalizedMessage.contains('remote media host could not be resolved')) {
      return true;
    }

    final httpStatus = details['httpStatus'];
    return httpStatus == '401' || httpStatus == '403' || httpStatus == '404';
  }
}
