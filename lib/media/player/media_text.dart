import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

final RegExp _cjkPattern = RegExp(r'[\u4E00-\u9FFF]');
final RegExp _http5xxPattern = RegExp(r'\bhttp\s*5\d{2}\b', caseSensitive: false);
final RegExp _http4xxPattern = RegExp(r'\bhttp\s*4\d{2}\b', caseSensitive: false);

bool _containsCjk(String value) => _cjkPattern.hasMatch(value);

String _stripDartErrorPrefixes(String raw) {
  var message = raw.trim();
  const prefixes = <String>[
    'Exception: ',
    'Bad state: ',
    'Invalid argument(s): ',
    'StateError: ',
    'FormatException: ',
  ];
  var changed = true;
  while (changed) {
    changed = false;
    for (final prefix in prefixes) {
      if (message.startsWith(prefix)) {
        message = message.substring(prefix.length).trim();
        changed = true;
      }
    }
  }
  return message;
}

/// 清洗并翻译常见底层异常/英文诊断文案为可读的中文提示。
///
/// 已是明确中文提示或调用方自定义短文案时保持原义；已知底层网络、存储、
/// 权限、编解码与内部协议诊断统一映射为面向用户的中文说明。
String sanitizeUserErrorMessage(String? raw, {required String fallback}) {
  if (raw == null) {
    return fallback;
  }
  final message = _stripDartErrorPrefixes(raw);
  if (message.isEmpty) {
    return fallback;
  }
  final lower = message.toLowerCase();

  if (lower.contains('media url is stale') ||
      lower.contains('stale or expired') ||
      lower.contains('http 401') ||
      lower.contains('http 403') ||
      lower.contains('http 404') ||
      lower.contains('http 410')) {
    return '资源链接已过期或无访问权限，请重新打开后再试。';
  }
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return '请求超时，请检查网络连接后重试。';
  }
  if (lower.contains('handshakeexception') ||
      lower.contains('tlsexception') ||
      lower.contains('certificate')) {
    return '安全连接失败，请检查网络或系统时间后重试。';
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection closed') ||
      lower.contains('software caused connection abort') ||
      lower.contains('network is unreachable') ||
      lower.contains('broken pipe') ||
      lower.contains('httpexception') ||
      lower.contains('clientexception')) {
    return '网络连接失败，请检查网络后重试。';
  }
  if (lower.contains('no space left') ||
      lower.contains('enospc') ||
      lower.contains('disk full')) {
    return '设备存储空间不足，请清理空间后重试。';
  }
  if (lower.contains('permission denied') ||
      lower.contains('eacces') ||
      lower.contains('eperm')) {
    return '缺少必要的文件或系统权限，请检查权限设置后重试。';
  }
  if (lower.contains('no such file') ||
      lower.contains('enoent') ||
      lower.contains('file not found') ||
      lower.contains('pathnotfoundexception')) {
    return '本地文件不存在或已被移除。';
  }
  if (lower.contains('cannot open file') ||
      lower.contains('creation failed') ||
      lower.contains('deletion failed')) {
    return '读写本地文件失败，请稍后重试。';
  }
  if (lower.contains('ffmpeg') || lower.contains('remux')) {
    return '视频封装失败，请重试或重新缓存。';
  }
  if (lower.contains('decoder') ||
      lower.contains('decode failure') ||
      lower.contains('unsupported codec') ||
      lower.contains('codec not supported')) {
    return '当前视频编码暂不受设备支持。';
  }
  if (lower.contains('wbi keys are unavailable')) {
    return '请求签名初始化失败，请稍后重试。';
  }
  if (lower.contains('unexpected qr login') ||
      lower.contains('qr login payload is incomplete') ||
      lower.contains('qr login poll failed')) {
    return '二维码服务响应异常，请刷新后重试。';
  }
  if (lower.contains('playback resolve failed') ||
      lower.contains('no dash object') ||
      lower.contains('dash parsed 0v') ||
      lower.contains('media url probe failed') ||
      lower.contains('no usable media url')) {
    return '无法获取可播放或可缓存的视频流，请稍后重试。';
  }
  if (lower.contains('unexpected bilibili api response') ||
      lower.contains('unknown bilibili error') ||
      lower.contains('returned json where binary')) {
    return '服务返回数据异常，请稍后重试。';
  }
  if (_http5xxPattern.hasMatch(message)) {
    return '服务器暂时不可用，请稍后重试。';
  }
  if (_http4xxPattern.hasMatch(message) || lower.contains('from bilibili')) {
    return '请求异常，请稍后重试。';
  }
  if (lower.contains('has been disposed') ||
      message.startsWith('PlatformException(') ||
      message.startsWith('VesperDownloadException(') ||
      message.startsWith('MissingPluginException(') ||
      message.startsWith('VesperPlayerError(')) {
    return fallback;
  }

  return message;
}

/// 平台无关的错误文案：把异常转换为用户可读的中文消息。
///
/// 平台 API 异常（如 Bilibili 的 [BiliApiException]）由平台自己的格式化
/// 入口处理；壳内统一使用本函数。
String mediaErrorMessage(Object error) {
  if (error is TimeoutException) {
    return '请求超时，请检查网络连接。';
  }
  if (error is HandshakeException || error is TlsException) {
    return '安全连接失败，请检查网络或系统时间后重试。';
  }
  if (error is SocketException || error is HttpException) {
    return '网络连接失败，请检查网络后重试。';
  }
  if (error is FileSystemException) {
    final osCode = error.osError?.errorCode;
    if (osCode == 28) {
      return '设备存储空间不足，请清理空间后重试。';
    }
    if (osCode == 13 || osCode == 1) {
      return '没有访问本地文件的权限，请检查存储权限。';
    }
    if (osCode == 2) {
      return '本地文件不存在或已被移除。';
    }
    final combined = '${error.message} ${error.osError?.message ?? ''}'.trim();
    final sanitized = sanitizeUserErrorMessage(
      combined,
      fallback: '读写本地文件失败，请稍后重试。',
    );
    return _containsCjk(sanitized) ? sanitized : '读写本地文件失败，请稍后重试。';
  }
  if (error is FormatException) {
    final trimmed = error.message.trim();
    return _containsCjk(trimmed) ? trimmed : '数据解析失败，请稍后重试。';
  }
  if (error is MissingPluginException) {
    return '当前设备暂不支持此功能。';
  }
  if (error is PlatformException) {
    final msg = error.message?.trim() ?? '';
    if (_containsCjk(msg)) {
      return msg;
    }
    final code = error.code.toLowerCase();
    if (code.contains('permission')) {
      return '缺少必要的系统权限，请在系统设置中授权后重试。';
    }
    if (code.contains('network')) {
      return '网络连接失败，请检查网络后重试。';
    }
    if (code.contains('timeout')) {
      return '操作超时，请稍后重试。';
    }
    if (code.contains('cancel')) {
      return '操作已取消。';
    }
    final sanitized = sanitizeUserErrorMessage(
      msg,
      fallback: '系统操作失败，请稍后重试。',
    );
    return _containsCjk(sanitized) ? sanitized : '系统操作失败，请稍后重试。';
  }
  if (error is StateError) {
    return sanitizeUserErrorMessage(
      error.message,
      fallback: '操作未能完成，请稍后重试。',
    );
  }
  if (error is ArgumentError) {
    final msg = error.message?.toString().trim() ?? '';
    return _containsCjk(msg) ? msg : '请求参数无效，请重试。';
  }
  if (error is TypeError ||
      error is RangeError ||
      error is NoSuchMethodError) {
    return '数据异常，请稍后重试。';
  }
  return sanitizeUserErrorMessage(
    error.toString(),
    fallback: '操作失败，请稍后重试。',
  );
}

/// 秒数 → mm:ss / hh:mm:ss 文案。
String mediaFormatDurationSeconds(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainingSeconds.toString().padLeft(2, '0')}';
}
