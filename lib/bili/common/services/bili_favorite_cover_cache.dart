import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vesper_media/common/storage/application_storage.dart';
import 'package:vesper_media/common/storage/atomic_file_writer.dart';

import '../models/bili_favorites_models.dart';
import '../models/bili_models.dart';

typedef BiliFavoriteCoverPageLoader =
    Future<BiliFavoritePage> Function({
      required int folderId,
      required int page,
      required int pageSize,
    });

final class BiliFavoriteCover {
  const BiliFavoriteCover({required this.resourceKey, required this.url});

  final String resourceKey;
  final String url;
}

/// Stores source identity separately from the image-file cache. Only a stable
/// account UID is persisted; anonymous/test sessions keep their own memory cache.
class BiliFavoriteCoverStore {
  BiliFavoriteCoverStore({this.directory});

  final Directory? directory;
  Future<void> _pendingWrite = Future<void>.value();

  Future<File> _file(int accountId) async {
    final base = await resolveApplicationStorageDirectory(
      baseDirectory: directory,
    );
    return File('${base.path}/favorite-covers-$accountId.json');
  }

  Future<Map<int, BiliFavoriteCover>> load(int accountId) async {
    await _pendingWrite;
    try {
      final file = await _file(accountId);
      if (!await file.exists()) return {};
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return {};
      final result = <int, BiliFavoriteCover>{};
      for (final entry in data.entries) {
        final folderId = int.tryParse(entry.key.toString());
        final value = entry.value;
        if (folderId == null || folderId <= 0 || value is! Map) continue;
        final resourceKey = value['resourceKey'];
        final url = value['url'];
        if (resourceKey is String &&
            resourceKey.isNotEmpty &&
            url is String &&
            url.isNotEmpty) {
          result[folderId] = BiliFavoriteCover(
            resourceKey: resourceKey,
            url: url,
          );
        }
      }
      return result;
    } catch (_) {
      // A missing/corrupt cache must not prevent browsing favorites.
      return {};
    }
  }

  Future<void> save(int accountId, Map<int, BiliFavoriteCover> covers) {
    final contents = jsonEncode({
      for (final entry in covers.entries)
        '${entry.key}': {
          'resourceKey': entry.value.resourceKey,
          'url': entry.value.url,
        },
    });
    return _pendingWrite = _pendingWrite.then((_) async {
      try {
        await writeStringAtomically(await _file(accountId), contents);
      } catch (_) {
        // Keep the usable in-memory cover when the disk cache is unavailable.
      }
    });
  }
}

final class BiliFavoriteCoverCache {
  BiliFavoriteCoverCache({
    required this.accountId,
    required this.sessionRevision,
    required this.isAuthenticated,
    required this.loadPage,
    required this.store,
  });

  final int? Function() accountId;
  final int Function() sessionRevision;
  final bool Function() isAuthenticated;
  final BiliFavoriteCoverPageLoader loadPage;
  final BiliFavoriteCoverStore store;

  final _covers = <int, BiliFavoriteCover>{};
  final _emptyCounts = <int, int?>{};
  final _requests = <int, Future<String>>{};
  final _versions = <int, int>{};
  int? _accountId;
  int? _sessionRevision;
  int _generation = 0;
  Future<void>? _load;

  int _syncScope() {
    final uid = accountId();
    final revision = sessionRevision();
    if (_accountId != uid || _sessionRevision != revision) {
      _generation++;
      _accountId = uid;
      _sessionRevision = revision;
      _covers.clear();
      _emptyCounts.clear();
      _requests.clear();
      _versions.clear();
      _load = null;
    }
    return _generation;
  }

  bool _isCurrent(int generation) =>
      generation == _generation &&
      _accountId == accountId() &&
      _sessionRevision == sessionRevision() &&
      isAuthenticated();

  Future<int> _ensureLoaded() async {
    final generation = _syncScope();
    await (_load ??= () async {
      final uid = _accountId;
      if (uid == null || uid <= 0) return;
      final saved = await store.load(uid);
      if (_isCurrent(generation)) _covers.addAll(saved);
    }());
    return generation;
  }

  String cachedUrl(int folderId) {
    _syncScope();
    return isAuthenticated() ? _covers[folderId]?.url ?? '' : '';
  }

  Future<void> _persist() async {
    final uid = _accountId;
    if (uid != null && uid > 0) await store.save(uid, _covers);
  }

  void _set(int folderId, BiliFavoriteCover? cover) {
    _versions[folderId] = (_versions[folderId] ?? 0) + 1;
    _requests.remove(folderId);
    _emptyCounts.remove(folderId);
    if (cover == null) {
      _covers.remove(folderId);
    } else {
      _covers[folderId] = cover;
    }
  }

  /// Retry missing sources after an explicit refresh, including offscreen cards.
  /// Valid source selections and still-current preview requests are retained.
  void invalidateEmptyCovers() {
    _syncScope();
    _emptyCounts.clear();
  }

  Future<String> coverFor(BiliFavoriteFolder folder) async {
    final generation = await _ensureLoaded();
    if (!_isCurrent(generation)) return '';
    if (folder.mediaCount == 0) {
      _set(folder.id, null);
      _emptyCounts[folder.id] = 0;
      await _persist();
      return '';
    }
    final cached = _covers[folder.id];
    if (cached != null) return cached.url;
    if (_emptyCounts.containsKey(folder.id) &&
        _emptyCounts[folder.id] == folder.mediaCount) {
      return '';
    }
    final pending = _requests[folder.id];
    if (pending != null) return pending;
    final version = _versions[folder.id] ?? 0;
    final request = _findCover(folder, generation, version);
    _requests[folder.id] = request;
    try {
      return await request;
    } finally {
      if (identical(_requests[folder.id], request)) {
        _requests.remove(folder.id);
      }
    }
  }

  Future<String> _findCover(
    BiliFavoriteFolder folder,
    int generation,
    int version,
  ) async {
    var pageNumber = 1;
    var pageSize = 1;
    final seen = <String>{};
    while (_isCurrent(generation)) {
      final page = await loadPage(
        folderId: folder.id,
        page: pageNumber,
        pageSize: pageSize,
      );
      if (!_isCurrent(generation)) return '';
      if ((_versions[folder.id] ?? 0) != version) {
        return _covers[folder.id]?.url ?? '';
      }
      final candidate = page.items.where(_usable).firstOrNull;
      if (candidate != null) {
        _set(
          folder.id,
          BiliFavoriteCover(
            resourceKey: candidate.resourceKey,
            url: candidate.coverUrl,
          ),
        );
        await _persist();
        return candidate.coverUrl;
      }
      if (!page.hasMore || page.items.isEmpty) {
        _emptyCounts[folder.id] = folder.mediaCount;
        return '';
      }
      if (pageSize == 1) {
        // Skip an unavailable head efficiently, using the normal list page size.
        pageSize = 20;
      } else {
        final previousCount = seen.length;
        seen.addAll(page.items.map((item) => item.resourceKey));
        if (seen.length == previousCount) return '';
        pageNumber++;
      }
    }
    return '';
  }

  /// Reuses evidence from browsing. Absence is meaningful only for a complete,
  /// unfiltered folder; search/sort/pagination must not evict a valid cover.
  Future<void> observeItems({
    required int folderId,
    required List<BiliFavoriteItem> items,
    required bool startsAtNewest,
    required bool isCompleteFolder,
  }) async {
    final generation = await _ensureLoaded();
    if (!_isCurrent(generation)) return;
    final current = _covers[folderId];
    if (current != null) {
      final source = items
          .where((item) => item.resourceKey == current.resourceKey)
          .firstOrNull;
      if (source != null ? source.isAvailable : !isCompleteFolder) return;
      _set(folderId, null);
    }
    if (startsAtNewest) {
      final candidate = items.where(_usable).firstOrNull;
      if (candidate != null) {
        _set(
          folderId,
          BiliFavoriteCover(
            resourceKey: candidate.resourceKey,
            url: candidate.coverUrl,
          ),
        );
      } else if (isCompleteFolder) {
        _set(folderId, null);
        _emptyCounts[folderId] = items.length;
      }
    }
    await _persist();
  }

  Future<void> resourcesAdded(int folderId) async {
    final generation = await _ensureLoaded();
    if (!_isCurrent(generation) || _covers.containsKey(folderId)) return;
    // New content can supply a missing cover. Reject previews of the old list.
    _set(folderId, null);
  }

  Future<void> removeResources(int folderId, Iterable<String> keys) async {
    final generation = await _ensureLoaded();
    if (!_isCurrent(generation)) return;
    if (keys.contains(_covers[folderId]?.resourceKey)) {
      _set(folderId, null);
      await _persist();
    } else if (!_covers.containsKey(folderId)) {
      // A preview started before the removal must not restore the deleted item.
      _set(folderId, null);
    }
  }

  static bool _usable(BiliFavoriteItem item) =>
      item.isAvailable && item.coverUrl.isNotEmpty;
}
