import 'package:signals/signals_flutter.dart';

import 'package:bilibili_player/download/download.dart';
import '../models/bili_models.dart';
import '../services/bili_client.dart';
import '../services/bili_history_store.dart';
import '../services/bili_logout_service.dart';
import '../services/bili_session_store.dart';
import '../services/bili_text.dart';

enum BiliHubTab { home, mine }

final class BiliHubPlaybackTarget {
  const BiliHubPlaybackTarget({
    required this.detail,
    required this.initialPage,
  });

  final BiliVideoDetail detail;
  final BiliVideoPageEntry initialPage;
}

final class BiliHubException implements Exception {
  const BiliHubException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class BiliHubViewModel {
  BiliHubViewModel({
    BiliClient? client,
    BiliHistoryStore? historyStore,
    BiliSessionStore? sessionStore,
    BiliOfflineDownloadController? offlineController,
  }) : client = client ?? BiliClient.instance,
       historyStore = historyStore ?? const BiliHistoryStore(),
       sessionStore = sessionStore ?? const BiliSessionStore(),
       offlineController =
           offlineController ?? BiliOfflineDownloadController.instance {
    feedItems = _feedItems.readonly();
    results = _results.readonly();
    history = _history.readonly();
    profile = _profile.readonly();
    selectedTab = _selectedTab.readonly();
    isBootstrapping = _isBootstrapping.readonly();
    isRefreshingFeed = _isRefreshingFeed.readonly();
    isLoadingMoreFeed = _isLoadingMoreFeed.readonly();
    isSearching = _isSearching.readonly();
    isLoadingMoreSearch = _isLoadingMoreSearch.readonly();
    isRefreshingProfile = _isRefreshingProfile.readonly();
    hasMoreFeed = _hasMoreFeed.readonly();
    hasMoreSearch = _hasMoreSearch.readonly();
    query = _query.readonly();
    activeSearchKeyword = _activeSearchKeyword.readonly();
    feedErrorMessage = _feedErrorMessage.readonly();
    searchErrorMessage = _searchErrorMessage.readonly();
    profileErrorMessage = _profileErrorMessage.readonly();
    directBvid = computed(() => biliExtractBvid(_query.value));
    showsSearchResults = computed(
      () => _query.value.isNotEmpty || _results.value.isNotEmpty,
    );
  }

  final BiliClient client;
  final BiliHistoryStore historyStore;
  final BiliSessionStore sessionStore;
  final BiliOfflineDownloadController offlineController;

  final _feedItems = signal<List<BiliFeedVideo>>(const <BiliFeedVideo>[]);
  final _results = signal<List<BiliSearchResult>>(const <BiliSearchResult>[]);
  final _history = signal<List<BiliPlaybackHistoryEntry>>(
    const <BiliPlaybackHistoryEntry>[],
  );
  final _profile = signal<BiliUserProfile>(
    const BiliUserProfile(isLoggedIn: false, name: '未登录', avatarUrl: ''),
  );
  final _selectedTab = signal(BiliHubTab.home);
  final _isBootstrapping = signal(true);
  final _isRefreshingFeed = signal(false);
  final _isLoadingMoreFeed = signal(false);
  final _isSearching = signal(false);
  final _isLoadingMoreSearch = signal(false);
  final _isRefreshingProfile = signal(false);
  final _hasMoreFeed = signal(true);
  final _hasMoreSearch = signal(true);
  final _query = signal('');
  final _activeSearchKeyword = signal<String?>(null);
  final _feedErrorMessage = signal<String?>(null);
  final _searchErrorMessage = signal<String?>(null);
  final _profileErrorMessage = signal<String?>(null);
  final _feedPage = signal(1);
  final _searchPage = signal(1);

  late final ReadonlySignal<List<BiliFeedVideo>> feedItems;
  late final ReadonlySignal<List<BiliSearchResult>> results;
  late final ReadonlySignal<List<BiliPlaybackHistoryEntry>> history;
  late final ReadonlySignal<BiliUserProfile> profile;
  late final ReadonlySignal<BiliHubTab> selectedTab;
  late final ReadonlySignal<bool> isBootstrapping;
  late final ReadonlySignal<bool> isRefreshingFeed;
  late final ReadonlySignal<bool> isLoadingMoreFeed;
  late final ReadonlySignal<bool> isSearching;
  late final ReadonlySignal<bool> isLoadingMoreSearch;
  late final ReadonlySignal<bool> isRefreshingProfile;
  late final ReadonlySignal<bool> hasMoreFeed;
  late final ReadonlySignal<bool> hasMoreSearch;
  late final ReadonlySignal<String> query;
  late final ReadonlySignal<String?> activeSearchKeyword;
  late final ReadonlySignal<String?> feedErrorMessage;
  late final ReadonlySignal<String?> searchErrorMessage;
  late final ReadonlySignal<String?> profileErrorMessage;
  late final FlutterComputed<String?> directBvid;
  late final FlutterComputed<bool> showsSearchResults;

  Future<void> bootstrap() async {
    final persistedCookies = await sessionStore.loadCookies();
    if (persistedCookies.isNotEmpty) {
      client.restoreCookies(persistedCookies);
    }

    await Future.wait(<Future<void>>[
      loadHistory(),
      loadFeed(),
      refreshProfile(
        clearInvalidSession: persistedCookies.isNotEmpty,
        persistIfLoggedIn: true,
      ),
    ]);

    _isBootstrapping.value = false;
  }

  Future<void> refreshAll() async {
    await Future.wait(<Future<void>>[
      loadHistory(),
      loadFeed(),
      refreshProfile(clearInvalidSession: true, persistIfLoggedIn: true),
    ]);
  }

  Future<void> loadHistory() async {
    _history.value = await historyStore.loadEntries();
  }

  Future<void> loadFeed() async {
    _isRefreshingFeed.value = true;
    _feedErrorMessage.value = null;
    _hasMoreFeed.value = true;

    try {
      final items = await client.fetchRecommendedFeed(page: 1);
      _feedItems.value = items;
      _feedPage.value = 1;
      _hasMoreFeed.value = items.isNotEmpty;
    } catch (error) {
      _feedErrorMessage.value = error.toString();
    } finally {
      _isRefreshingFeed.value = false;
    }
  }

  Future<String?> loadMoreFeed() async {
    if (_isRefreshingFeed.value ||
        _isLoadingMoreFeed.value ||
        !_hasMoreFeed.value) {
      return null;
    }

    final nextPage = _feedPage.value + 1;
    _isLoadingMoreFeed.value = true;

    try {
      final items = await client.fetchRecommendedFeed(page: nextPage);
      final existingBvids = _feedItems.value.map((item) => item.bvid).toSet();
      final nextItems = items
          .where((item) => existingBvids.add(item.bvid))
          .toList(growable: false);
      _feedItems.value = <BiliFeedVideo>[..._feedItems.value, ...nextItems];
      _feedPage.value = nextPage;
      _hasMoreFeed.value = items.isNotEmpty && nextItems.isNotEmpty;
      return null;
    } catch (error) {
      return '加载更多推荐失败：$error';
    } finally {
      _isLoadingMoreFeed.value = false;
    }
  }

  Future<void> refreshProfile({
    required bool clearInvalidSession,
    required bool persistIfLoggedIn,
  }) async {
    _isRefreshingProfile.value = true;
    _profileErrorMessage.value = null;

    try {
      final nextProfile = await client.fetchCurrentUserProfile();
      if (nextProfile.isLoggedIn && persistIfLoggedIn) {
        await sessionStore.saveCookies(client.snapshotCookies());
      }
      if (!nextProfile.isLoggedIn && clearInvalidSession) {
        client.clearSession();
        await sessionStore.clear();
      }
      _profile.value = nextProfile;
    } catch (error) {
      if (clearInvalidSession) {
        client.clearSession();
        await sessionStore.clear();
      }
      _profile.value = const BiliUserProfile(
        isLoggedIn: false,
        name: '未登录',
        avatarUrl: '',
      );
      _profileErrorMessage.value = error.toString();
    } finally {
      _isRefreshingProfile.value = false;
    }
  }

  void updateQuery(String value) {
    _query.value = value.trim();
  }

  Future<void> runSearch() async {
    final keyword = _query.value;
    if (keyword.isEmpty) {
      return;
    }

    _isSearching.value = true;
    _searchErrorMessage.value = null;
    _results.value = const <BiliSearchResult>[];
    _searchPage.value = 1;
    _hasMoreSearch.value = true;
    _activeSearchKeyword.value = keyword;

    try {
      final nextResults = await client.searchVideos(keyword, page: 1);
      _results.value = nextResults;
      _hasMoreSearch.value = nextResults.isNotEmpty;
    } catch (error) {
      _searchErrorMessage.value = error.toString();
    } finally {
      _isSearching.value = false;
    }
  }

  Future<String?> loadMoreSearch() async {
    final keyword = _activeSearchKeyword.value;
    if (keyword == null ||
        keyword != _query.value ||
        _isSearching.value ||
        _isLoadingMoreSearch.value ||
        !_hasMoreSearch.value) {
      return null;
    }

    final nextPage = _searchPage.value + 1;
    _isLoadingMoreSearch.value = true;

    try {
      final nextResults = await client.searchVideos(keyword, page: nextPage);
      final existingBvids = _results.value.map((item) => item.bvid).toSet();
      final uniqueResults = nextResults
          .where((item) => existingBvids.add(item.bvid))
          .toList(growable: false);
      _results.value = <BiliSearchResult>[..._results.value, ...uniqueResults];
      _searchPage.value = nextPage;
      _hasMoreSearch.value = nextResults.isNotEmpty && uniqueResults.isNotEmpty;
      return null;
    } catch (error) {
      return '加载更多搜索结果失败：$error';
    } finally {
      _isLoadingMoreSearch.value = false;
    }
  }

  void clearSearch() {
    _query.value = '';
    _results.value = const <BiliSearchResult>[];
    _searchErrorMessage.value = null;
    _activeSearchKeyword.value = null;
    _searchPage.value = 1;
    _hasMoreSearch.value = true;
  }

  void seedFeedForTesting(List<BiliFeedVideo> items) {
    _feedItems.value = items;
    _hasMoreFeed.value = false;
    _isBootstrapping.value = false;
  }

  Future<BiliHubPlaybackTarget> resolvePlaybackTarget(
    String bvid, {
    int? cid,
  }) async {
    final detail = await client.fetchVideoDetail(bvid);
    if (detail.pages.isEmpty) {
      throw const BiliHubException('这个视频没有可播放分 P。');
    }

    final initialPage = cid == null
        ? detail.pages.first
        : detail.pages.firstWhere(
            (page) => page.cid == cid,
            orElse: () => detail.pages.first,
          );
    return BiliHubPlaybackTarget(detail: detail, initialPage: initialPage);
  }

  Future<void> applyLoggedInProfile(BiliUserProfile nextProfile) async {
    _profile.value = nextProfile;
    _profileErrorMessage.value = null;
    _selectedTab.value = BiliHubTab.mine;
    await Future.wait(<Future<void>>[loadFeed(), loadHistory()]);
  }

  Future<void> logout() async {
    await clearBiliAuthenticatedSession(
      client: client,
      sessionStore: sessionStore,
      offlineController: offlineController,
    );
    _profile.value = const BiliUserProfile(
      isLoggedIn: false,
      name: '未登录',
      avatarUrl: '',
    );
    _profileErrorMessage.value = null;
    await loadFeed();
  }

  Future<void> refreshMine() {
    return Future.wait(<Future<void>>[
      loadHistory(),
      refreshProfile(clearInvalidSession: true, persistIfLoggedIn: true),
    ]).then((_) {});
  }

  void selectTab(BiliHubTab tab) {
    _selectedTab.value = tab;
  }

  void selectMineTab() {
    _selectedTab.value = BiliHubTab.mine;
  }

  void dispose() {
    directBvid.dispose();
    showsSearchResults.dispose();
    _feedItems.dispose();
    _results.dispose();
    _history.dispose();
    _profile.dispose();
    _selectedTab.dispose();
    _isBootstrapping.dispose();
    _isRefreshingFeed.dispose();
    _isLoadingMoreFeed.dispose();
    _isSearching.dispose();
    _isLoadingMoreSearch.dispose();
    _isRefreshingProfile.dispose();
    _hasMoreFeed.dispose();
    _hasMoreSearch.dispose();
    _query.dispose();
    _activeSearchKeyword.dispose();
    _feedErrorMessage.dispose();
    _searchErrorMessage.dispose();
    _profileErrorMessage.dispose();
    _feedPage.dispose();
    _searchPage.dispose();
  }
}
