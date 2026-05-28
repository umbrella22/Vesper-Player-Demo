final class BiliOfflineStorageUsage {
  const BiliOfflineStorageUsage({
    required this.cacheBytes,
    required this.freeBytes,
    required this.totalBytes,
  });

  final int cacheBytes;
  final int freeBytes;
  final int totalBytes;

  int get availableBytes => cacheBytes + freeBytes;

  double get cacheRatio {
    final total = availableBytes;
    if (total <= 0) {
      return 0;
    }
    return cacheBytes / total;
  }
}
