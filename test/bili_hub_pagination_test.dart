import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/view_models/bili_hub_view_model.dart';

void main() {
  test(
    'refresh discards old pages without clearing a newer loading state',
    () async {
      final client = _PagingClient();
      final model = BiliHubViewModel(client: client);
      addTearDown(model.dispose);
      final initial = model.loadFeed();
      client.feedRequests.last.complete([_feed('old-first')]);
      await initial;

      final oldPage = model.loadMoreFeed();
      final oldRequest = client.feedRequests.last;
      final refresh = model.loadFeed();
      client.feedRequests.last.complete([_feed('new-first')]);
      await refresh;
      final newPage = model.loadMoreFeed();
      final newRequest = client.feedRequests.last;

      oldRequest.complete([_feed('old-second')]);
      await oldPage;
      expect(model.feedItems.value.map((item) => item.bvid), ['new-first']);
      expect(model.isLoadingMoreFeed.value, isTrue);
      newRequest.complete([_feed('new-second')]);
      await newPage;
      expect(model.feedItems.value.map((item) => item.bvid), [
        'new-first',
        'new-second',
      ]);
      expect(client.feedPages, [1, 2, 1, 2]);
    },
  );

  test(
    'only the latest refresh may publish an error or clear loading',
    () async {
      final client = _PagingClient();
      final model = BiliHubViewModel(client: client);
      addTearDown(model.dispose);
      final first = model.loadFeed();
      final second = model.loadFeed();
      client.feedRequests.first.completeError(StateError('stale request'));
      await first;
      expect(model.isRefreshingFeed.value, isTrue);
      expect(model.feedErrorMessage.value, isNull);
      client.feedRequests.last.complete([_feed('new')]);
      await second;
      expect(model.feedItems.value.single.bvid, 'new');
      expect(model.isRefreshingFeed.value, isFalse);
    },
  );

  test('unsubmitted draft preserves pagination of submitted results', () async {
    final client = _PagingClient();
    final model = BiliHubViewModel(client: client);
    addTearDown(model.dispose);
    model.updateQuery('submitted-A');
    await model.runSearch();
    model.updateQuery('draft-B');
    await model.loadMoreSearch();
    expect(client.searchRequests, ['submitted-A:1', 'submitted-A:2']);
    expect(model.activeSearchKeyword.value, 'submitted-A');
    expect(model.query.value, 'draft-B');
    expect(model.results.value, hasLength(2));
    expect(model.showsSearchResults.value, isTrue);
  });
}

class _PagingClient extends BiliClient {
  final feedRequests = <Completer<List<BiliFeedVideo>>>[];
  final feedPages = <int>[];
  final searchRequests = <String>[];

  @override
  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) {
    feedPages.add(page);
    final request = Completer<List<BiliFeedVideo>>();
    feedRequests.add(request);
    return request.future;
  }

  @override
  Future<List<BiliSearchResult>> searchVideos(
    String keyword, {
    int page = 1,
  }) async {
    searchRequests.add('$keyword:$page');
    return [
      BiliSearchResult(
        aid: page,
        bvid: '$keyword:$page',
        title: keyword,
        author: '',
        coverUrl: '',
        durationLabel: '',
        playCountLabel: '',
        danmakuCountLabel: '',
      ),
    ];
  }
}

BiliFeedVideo _feed(String id) => BiliFeedVideo(
  aid: 1,
  bvid: id,
  title: id,
  author: '',
  coverUrl: '',
  durationLabel: '',
  playCountLabel: '',
  danmakuCountLabel: '',
);
