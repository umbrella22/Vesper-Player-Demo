import 'package:flutter/services.dart';

const MethodChannel _storageChannel = MethodChannel(
  'dev.ikaros.bilibili_player/storage_space',
);

final class BiliDeviceStorageSpace {
  const BiliDeviceStorageSpace({
    required this.freeBytes,
    required this.totalBytes,
  });

  final int freeBytes;
  final int totalBytes;
}

Future<BiliDeviceStorageSpace> resolveBiliDeviceStorageSpace() async {
  final payload = await _storageChannel.invokeMapMethod<String, Object?>(
    'getStorageUsage',
  );
  if (payload == null) {
    throw PlatformException(
      code: 'storage_usage_empty',
      message: 'Storage usage payload is empty.',
    );
  }
  return BiliDeviceStorageSpace(
    freeBytes: _readStorageBytes(payload['freeBytes']),
    totalBytes: _readStorageBytes(payload['totalBytes']),
  );
}

int _readStorageBytes(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}
