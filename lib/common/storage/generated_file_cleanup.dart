import 'dart:io';

/// Deletes stale generated artifacts and sibling atomic-write temporary files.
///
/// Directory listing, metadata, and deletion failures are intentionally
/// ignored so maintenance cannot break the foreground operation.
Future<void> deleteStaleGeneratedFilesBestEffort(
  Directory directory, {
  required String fileExtension,
  required Duration maxAge,
}) async {
  try {
    final cutoff = DateTime.now().subtract(maxAge);
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith(fileExtension) && !name.contains('.tmp-')) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {
        // Ignore individual file failures.
      }
    }
  } catch (_) {
    // Cleanup is always best-effort.
  }
}
