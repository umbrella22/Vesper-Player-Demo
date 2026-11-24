import 'package:flutter/services.dart';

const MethodChannel _storageChannel = MethodChannel(
  'dev.ikaros.vesper_player/storage_space',
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
  final free = _readStorageBytes(payload['freeBytes']);
  final total = _readStorageBytes(payload['totalBytes']);
  if (free == null || total == null || free < 0 || total <= 0 || free > total) {
    throw PlatformException(code: 'storage_usage_invalid');
  }
  return BiliDeviceStorageSpace(freeBytes: free, totalBytes: total);
}

int? _readStorageBytes(Object? value) => switch (value) {
  int bytes => bytes,
  String bytes => int.tryParse(bytes),
  _ => null,
};
