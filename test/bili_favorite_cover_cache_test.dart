import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/models/bili_favorites_models.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_favorite_cover_cache.dart';

void main() {
  late Directory directory;
  late _Fixture fixture;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('favorite-covers-test-');
    fixture = _Fixture(BiliFavoriteCoverStore(directory: directory));
  });
  tearDown(() async => directory.delete(recursive: true));

  test('concurrent cards and later visits share one preview request', () async {
    final pending = Completer<BiliFavoritePage>();
    fixture.loader = (_, _) => pending.future;
    final first = fixture.cache.coverFor(_folder);
    final second = fixture.cache.coverFor(_folder);
    await fixture.requestStarted.future;
    pending.complete(_page([_item(1)]));
    expect(await first, _url(1));
    expect(await second, _url(1));
    expect(await fixture.cache.coverFor(_folder), _url(1));
    expect(fixture.requests, [(1, 1)]);
  });

  test(
    'source persists across client/app recreation for the same UID',
    () async {
      expect(await fixture.cache.coverFor(_folder), _url(1));
      final reopened = _Fixture(BiliFavoriteCoverStore(directory: directory));
      expect(await reopened.cache.coverFor(_folder), _url(1));
      expect(reopened.requests, isEmpty);
    },
  );

  test(
    'accounts and unknown-UID sessions never share persisted sources',
    () async {
      await fixture.cache.coverFor(_folder);
      fixture.uid = 9;
      fixture.revision++;
      fixture.loader = (_, _) async => _page([_item(2)]);
      expect(fixture.cache.cachedUrl(1), isEmpty);
      expect(await fixture.cache.coverFor(_folder), _url(2));
      fixture.uid = 8;
      fixture.revision++;
      expect(await fixture.cache.coverFor(_folder), _url(1));
      final anonymous = _Fixture(BiliFavoriteCoverStore(directory: directory))
        ..uid = null;
      anonymous.loader = (_, _) async => _page([_item(3)]);
      expect(await anonymous.cache.coverFor(_folder), _url(3));
      final otherAnonymous = _Fixture(
        BiliFavoriteCoverStore(directory: directory),
      )..uid = null;
      expect(await otherAnonymous.cache.coverFor(_folder), _url(1));
      expect(otherAnonymous.requests, hasLength(1));
    },
  );

  test(
    'unavailable first videos are skipped, including across pages',
    () async {
      fixture.loader = (page, size) async => size == 1
          ? _page([_item(1, available: false)], hasMore: true)
          : page == 1
          ? _page([
              _item(1, available: false),
              _item(2, cover: ''),
            ], hasMore: true)
          : _page([_item(3)]);
      expect(await fixture.cache.coverFor(_folder), _url(3));
      expect(fixture.requests, [(1, 1), (1, 20), (2, 20)]);
    },
  );

  test('new additions and a new URL do not replace a valid source', () async {
    await fixture.cache.coverFor(_folder);
    await fixture.observe([
      _item(2),
      _item(1, cover: 'https://example.test/changed.jpg'),
    ]);
    expect(await fixture.cache.coverFor(_folder), _url(1));
    expect(fixture.requests, hasLength(1));
  });

  test(
    'confirmed unavailable source is replaced using the browsed list',
    () async {
      await fixture.cache.coverFor(_folder);
      await fixture.observe([_item(1, available: false), _item(2)]);
      expect(await fixture.cache.coverFor(_folder), _url(2));
      expect(fixture.requests, hasLength(1));
    },
  );

  test(
    'partial/search pages cannot prove absence; complete folder can',
    () async {
      await fixture.cache.coverFor(_folder);
      await fixture.observe([_item(2)], complete: false);
      expect(fixture.cache.cachedUrl(1), _url(1));
      await fixture.cache.observeItems(
        folderId: 1,
        items: [_item(3)],
        startsAtNewest: false,
        isCompleteFolder: false,
      );
      expect(fixture.cache.cachedUrl(1), _url(1));
      await fixture.observe([_item(2)], complete: true);
      expect(fixture.cache.cachedUrl(1), _url(2));
    },
  );

  test('late preview cannot overwrite a newer authoritative list', () async {
    final pending = Completer<BiliFavoritePage>();
    fixture.loader = (_, _) => pending.future;
    final preview = fixture.cache.coverFor(_folder);
    await fixture.requestStarted.future;
    await fixture.observe([_item(2)]);
    pending.complete(_page([_item(1)]));
    expect(await preview, _url(2));
    expect(fixture.cache.cachedUrl(1), _url(2));
  });

  for (final added in [true, false]) {
    test(
      'content mutation detaches an obsolete preview (added: $added)',
      () async {
        final oldPage = Completer<BiliFavoritePage>();
        fixture.loader = (_, _) => oldPage.future;
        final oldPreview = fixture.cache.coverFor(_folder);
        await fixture.requestStarted.future;
        if (added) {
          await fixture.cache.resourcesAdded(1);
        } else {
          await fixture.cache.removeResources(1, ['1:2']);
        }
        fixture.loader = (_, _) async => _page([_item(2)]);
        expect(
          await fixture.cache
              .coverFor(_folder)
              .timeout(const Duration(seconds: 5)),
          _url(2),
        );
        oldPage.complete(_page([_item(1)]));
        expect(await oldPreview, _url(2));
        expect(fixture.requests, hasLength(2));
        expect(fixture.cache.cachedUrl(1), _url(2));
      },
    );
  }

  test(
    'late preview after session replacement cannot write into new account',
    () async {
      final pending = Completer<BiliFavoritePage>();
      fixture.loader = (_, _) => pending.future;
      final preview = fixture.cache.coverFor(_folder);
      await fixture.requestStarted.future;
      fixture.uid = 9;
      fixture.revision++;
      fixture.loader = (_, _) async => _page([_item(2)]);
      expect(await fixture.cache.coverFor(_folder), _url(2));
      pending.complete(_page([_item(1)]));
      expect(await preview, isEmpty);
      expect(fixture.cache.cachedUrl(1), _url(2));
    },
  );

  test(
    'failed preview is retryable and never becomes a cached empty folder',
    () async {
      fixture.loader = (_, _) async => throw const SocketException('offline');
      await expectLater(
        fixture.cache.coverFor(_folder),
        throwsA(isA<SocketException>()),
      );
      fixture.loader = (_, _) async => _page([_item(2)]);
      expect(await fixture.cache.coverFor(_folder), _url(2));
      expect(fixture.requests, hasLength(2));
    },
  );

  test(
    'removing the selected resource invalidates it, other removals do not',
    () async {
      await fixture.cache.coverFor(_folder);
      await fixture.cache.removeResources(1, ['2:2']);
      expect(fixture.cache.cachedUrl(1), _url(1));
      await fixture.cache.removeResources(1, ['1:2']);
      fixture.loader = (_, _) async => _page([_item(2)]);
      expect(await fixture.cache.coverFor(_folder), _url(2));
    },
  );

  for (final count in [3, null]) {
    test(
      'manual refresh retries empty sources with unchanged count $count',
      () async {
        final folder = BiliFavoriteFolder(
          id: 1,
          title: 'favorites',
          containsCurrentVideo: false,
          mediaCount: count,
        );
        fixture.loader = (_, _) async => _page([_item(1, available: false)]);
        expect(await fixture.cache.coverFor(folder), isEmpty);
        fixture.loader = (_, _) async => _page([_item(1)]);
        expect(await fixture.cache.coverFor(folder), isEmpty);
        expect(fixture.requests, hasLength(1));
        fixture.cache.invalidateEmptyCovers();
        expect(await fixture.cache.coverFor(folder), _url(1));
        expect(fixture.requests, hasLength(2));
        fixture.loader = (_, _) async => _page([_item(2)]);
        fixture.cache.invalidateEmptyCovers();
        expect(await fixture.cache.coverFor(folder), _url(1));
        expect(fixture.requests, hasLength(2));
      },
    );
  }

  test(
    'adding content retries missing covers but preserves valid sources',
    () async {
      fixture.loader = (_, _) async => _page([_item(1, available: false)]);
      expect(await fixture.cache.coverFor(_folder), isEmpty);
      await fixture.cache.resourcesAdded(1);
      fixture.loader = (_, _) async => _page([_item(2)]);
      expect(await fixture.cache.coverFor(_folder), _url(2));
      await fixture.cache.resourcesAdded(1);
      fixture.loader = (_, _) async => _page([_item(3)]);
      expect(await fixture.cache.coverFor(_folder), _url(2));
      expect(fixture.requests, hasLength(2));
    },
  );

  test(
    'empty folder clears a persisted source without a preview request',
    () async {
      await fixture.cache.coverFor(_folder);
      expect(
        await fixture.cache.coverFor(
          const BiliFavoriteFolder(
            id: 1,
            title: 'empty',
            containsCurrentVideo: false,
            mediaCount: 0,
          ),
        ),
        isEmpty,
      );
      expect(fixture.requests, hasLength(1));
      final reopened = _Fixture(BiliFavoriteCoverStore(directory: directory));
      reopened.loader = (_, _) async => _page([_item(2)]);
      expect(await reopened.cache.coverFor(_folder), _url(2));
    },
  );
}

class _Fixture {
  _Fixture(BiliFavoriteCoverStore store) {
    cache = BiliFavoriteCoverCache(
      accountId: () => uid,
      sessionRevision: () => revision,
      isAuthenticated: () => authenticated,
      loadPage: ({required folderId, required page, required pageSize}) {
        requests.add((page, pageSize));
        if (!requestStarted.isCompleted) requestStarted.complete();
        return loader(page, pageSize);
      },
      store: store,
    );
  }
  int? uid = 8;
  int revision = 1;
  bool authenticated = true;
  final requests = <(int, int)>[];
  final requestStarted = Completer<void>();
  Future<BiliFavoritePage> Function(int, int) loader = (_, _) async =>
      _page([_item(1)]);
  late final BiliFavoriteCoverCache cache;

  Future<void> observe(List<BiliFavoriteItem> items, {bool complete = true}) =>
      cache.observeItems(
        folderId: 1,
        items: items,
        startsAtNewest: true,
        isCompleteFolder: complete,
      );
}

const _folder = BiliFavoriteFolder(
  id: 1,
  title: 'favorites',
  containsCurrentVideo: false,
  mediaCount: 3,
);
String _url(int id) => 'https://example.test/$id.jpg';
BiliFavoriteItem _item(int id, {bool available = true, String? cover}) =>
    BiliFavoriteItem(
      id: id,
      bvid: 'BV$id',
      title: 'video $id',
      coverUrl: cover ?? _url(id),
      ownerName: '',
      durationLabel: '',
      playCountLabel: '',
      favoritedAtLabel: '',
      isAvailable: available,
    );
BiliFavoritePage _page(List<BiliFavoriteItem> items, {bool hasMore = false}) =>
    BiliFavoritePage(items: items, page: 1, pageSize: 20, hasMore: hasMore);
