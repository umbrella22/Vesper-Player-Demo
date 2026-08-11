import 'dart:async';
import 'dart:io';

/// 平台无关的错误文案：把异常转换为用户可读的中文消息。
///
/// 平台 API 异常（如 Bilibili 的 [BiliApiException]）由平台自己的格式化
/// 入口处理；壳内统一使用本函数。
String mediaErrorMessage(Object error) {
  if (error is SocketException) {
    return error.message;
  }
  if (error is FormatException) {
    return error.message.isEmpty ? '数据格式异常' : error.message;
  }
  if (error is TimeoutException) {
    return '请求超时，请检查网络连接';
  }
  if (error is FileSystemException) {
    return error.message;
  }
  final message = error.toString();
  const exceptionPrefix = 'Exception: ';
  return message.startsWith(exceptionPrefix)
      ? message.substring(exceptionPrefix.length)
      : message;
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
