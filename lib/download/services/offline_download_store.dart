import 'dart:convert';
import 'dart:io';

import 'package:vesper_media/common/storage/application_storage.dart';
import 'package:vesper_media/common/storage/atomic_file_writer.dart';

import '../models/offline_download_models.dart';

const String _offlineCacheMetadataFileName = 'bili-offline-cache.json';

final class BiliOfflineDownloadStore {
  const BiliOfflineDownloadStore({
    this.baseDirectory,
    this.legacyDirectory,
    this.fileName = _offlineCacheMetadataFileName,
  });

  final Directory? baseDirectory;
  final Directory? legacyDirectory;
  final String fileName;

  Future<List<BiliOfflineDownloadMetadata>> loadEntries() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return const <BiliOfflineDownloadMetadata>[];
    }
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) {
        return const <BiliOfflineDownloadMetadata>[];
      }
      final decoded = jsonDecode(text);
      final rawEntries = switch (decoded) {
        {'entries': final List<dynamic> entries} => entries,
        final List<dynamic> entries => entries,
        _ => throw const FormatException(
          'Unexpected offline cache metadata shape.',
        ),
      };
      final entries = rawEntries
          .whereType<Map<Object?, Object?>>()
          .map((value) => Map<String, Object?>.from(value))
          .map(BiliOfflineDownloadMetadata.fromJson)
          .where((entry) => entry.assetId.isNotEmpty)
          .toList(growable: false);
      return _dedupe(entries);
    } on FormatException {
      await _quarantineCorruptFile(file);
      return const <BiliOfflineDownloadMetadata>[];
    } on TypeError {
      await _quarantineCorruptFile(file);
      return const <BiliOfflineDownloadMetadata>[];
    }
  }

  Future<void> saveEntries(
    Iterable<BiliOfflineDownloadMetadata> entries,
  ) async {
    final deduped = _dedupe(entries);
    final file = await _resolveFile();
    final text = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'entries': deduped.map((entry) => entry.toJson()).toList(),
    });
    await writeStringAtomically(file, text);
  }

  Future<File> _resolveFile() {
    return resolveApplicationStorageFile(
      fileName: fileName,
      baseDirectory: baseDirectory,
      legacyDirectory: legacyDirectory,
    );
  }

  List<BiliOfflineDownloadMetadata> _dedupe(
    Iterable<BiliOfflineDownloadMetadata> entries,
  ) {
    final byAssetId = <String, BiliOfflineDownloadMetadata>{};
    for (final entry in entries) {
      final previous = byAssetId[entry.assetId];
      if (previous == null || entry.createdAtMs >= previous.createdAtMs) {
        byAssetId[entry.assetId] = entry;
      }
    }
    final sorted = byAssetId.values.toList(growable: false);
    sorted.sort((left, right) => right.createdAtMs.compareTo(left.createdAtMs));
    return sorted;
  }

  Future<void> _quarantineCorruptFile(File file) async {
    if (!await file.exists()) {
      return;
    }
    final suffix = DateTime.now().millisecondsSinceEpoch;
    final backup = File('${file.path}.corrupt-$suffix');
    try {
      await file.rename(backup.path);
    } on FileSystemException {
      try {
        await file.copy(backup.path);
        await file.delete();
      } on FileSystemException {
        // Leave the original file in place if the platform refuses both paths.
      }
    }
  }
}
