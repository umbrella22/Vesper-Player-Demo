import 'dart:convert';
import 'dart:io';

import '../models/bili_models.dart';
import 'bili_storage_directory.dart';

final class BiliHistoryStore {
  const BiliHistoryStore({Directory? baseDirectory, Directory? legacyDirectory})
    : _baseDirectory = baseDirectory,
      _legacyDirectory = legacyDirectory;

  final Directory? _baseDirectory;
  final Directory? _legacyDirectory;

  Future<List<BiliPlaybackHistoryEntry>> loadEntries() async {
    final file = await _historyFile();
    if (!await file.exists()) {
      return const <BiliPlaybackHistoryEntry>[];
    }

    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return const <BiliPlaybackHistoryEntry>[];
    }

    final decoded = jsonDecode(text);
    if (decoded is! List) {
      return const <BiliPlaybackHistoryEntry>[];
    }

    return decoded
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .map(BiliPlaybackHistoryEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> saveEntry(BiliPlaybackHistoryEntry entry) async {
    final file = await _historyFile();
    final currentEntries = await loadEntries();
    final updatedEntries = <BiliPlaybackHistoryEntry>[
      entry,
      ...currentEntries.where(
        (current) => current.bvid != entry.bvid || current.cid != entry.cid,
      ),
    ]..sort((left, right) => right.playedAtMs.compareTo(left.playedAtMs));

    await file.writeAsString(
      jsonEncode(
        updatedEntries
            .take(20)
            .map((historyEntry) => historyEntry.toJson())
            .toList(growable: false),
      ),
    );
  }

  Future<File> _historyFile() async {
    return resolveBiliStorageFile(
      fileName: 'bili-playback-history.json',
      baseDirectory: _baseDirectory,
      legacyDirectory: _legacyDirectory,
    );
  }
}
