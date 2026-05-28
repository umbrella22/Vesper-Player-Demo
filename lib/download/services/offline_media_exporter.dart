import 'package:flutter/services.dart';

final class BiliOfflineMediaExportException implements Exception {
  const BiliOfflineMediaExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BiliOfflineMediaExporter {
  const BiliOfflineMediaExporter({
    MethodChannel channel = const MethodChannel(
      'dev.ikaros.bilibili_player/media_export',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<String?> exportMp4ToGallery({
    required String sourcePath,
    required String displayName,
  }) async {
    final normalizedPath = sourcePath.trim();
    if (normalizedPath.isEmpty) {
      throw const BiliOfflineMediaExportException('缓存文件路径为空。');
    }
    if (!normalizedPath.toLowerCase().endsWith('.mp4')) {
      throw const BiliOfflineMediaExportException('只能导出 MP4 缓存文件。');
    }

    try {
      return await _channel.invokeMethod<String>('exportMp4ToGallery', {
        'sourcePath': normalizedPath,
        'displayName': _normalizedDisplayName(displayName),
      });
    } on PlatformException catch (error) {
      throw BiliOfflineMediaExportException(error.message ?? '导出到相册失败。');
    } on MissingPluginException {
      throw const BiliOfflineMediaExportException('当前平台不支持导出到相册。');
    }
  }

  String _normalizedDisplayName(String value) {
    final trimmed = value.trim();
    final baseName = trimmed.isEmpty ? 'bilibili-offline-video' : trimmed;
    return baseName.toLowerCase().endsWith('.mp4') ? baseName : '$baseName.mp4';
  }
}
