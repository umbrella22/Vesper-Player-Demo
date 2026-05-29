import 'dart:convert';
import 'dart:io';

import '../models/bili_models.dart';
import 'bili_api_core.dart';
import 'bili_storage_directory.dart';

final class BiliHistoryStore {
  const BiliHistoryStore({Directory? baseDirectory, Directory? legacyDirectory})
    : _baseDirectory = baseDirectory,
      _legacyDirectory = legacyDirectory;

  static final Map<String, Future<void>> _writeChains =
      <String, Future<void>>{};

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

    return readObjectList(jsonDecode(text))
        .whereType<Map<Object?, Object?>>()
        .map(readObjectMap)
        .map(BiliPlaybackHistoryEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> saveEntry(BiliPlaybackHistoryEntry entry) async {
    final file = await _historyFile();
    final previousWrite = _writeChains[file.path] ?? Future<void>.value();
    final nextWrite = previousWrite
        .catchError((_) {})
        .then((_) => _saveEntry(file: file, entry: entry));
    _writeChains[file.path] = nextWrite;
    try {
      await nextWrite;
    } finally {
      if (identical(_writeChains[file.path], nextWrite)) {
        _writeChains.remove(file.path);
      }
    }
  }

  Future<void> _saveEntry({
    required File file,
    required BiliPlaybackHistoryEntry entry,
  }) async {
    final currentEntries = await loadEntries();
    final updatedEntries = <BiliPlaybackHistoryEntry>[
      entry,
      ...currentEntries.where(
        (current) => current.bvid != entry.bvid || current.cid != entry.cid,
      ),
    ]..sort((left, right) => right.playedAtMs.compareTo(left.playedAtMs));

    final payload = jsonEncode(
      updatedEntries
          .take(20)
          .map((historyEntry) => historyEntry.toJson())
          .toList(growable: false),
    );
    await file.parent.create(recursive: true);
    final tempFile = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-$pid',
    );
    await tempFile.writeAsString(payload, flush: true);
    try {
      await tempFile.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
    }
  }

  Future<File> _historyFile() async {
    return resolveBiliStorageFile(
      fileName: 'bili-playback-history.json',
      baseDirectory: _baseDirectory,
      legacyDirectory: _legacyDirectory,
    );
  }
}
