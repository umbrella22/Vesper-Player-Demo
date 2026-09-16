import 'package:signals/signals_flutter.dart';

import '../models/bili_favorites_models.dart';
import '../models/bili_models.dart';
import '../services/bili_api_core.dart';
import '../services/bili_client.dart';

final class BiliFavoritesViewModel {
  BiliFavoritesViewModel({required this.client}) {
    folders = _folders.readonly();
    activeFolderId = _activeFolderId.readonly();
    items = _items.readonly();
    isLoading = _isLoading.readonly();
    isLoadingMore = _isLoadingMore.readonly();
    hasMore = _hasMore.readonly();
    keyword = _keyword.readonly();
    order = _order.readonly();
    errorMessage = _errorMessage.readonly();
    loadMoreErrorMessage = _loadMoreErrorMessage.readonly();
    authenticationRequired = _authenticationRequired.readonly();
    activeFolder = computed(() {
      final id = _activeFolderId.value;
      for (final folder in _folders.value) {
        if (folder.id == id) return folder;
      }
      return null;
    });
  }

  final BiliClient client;
  final _folders = signal<List<BiliFavoriteFolder>>([]);
  final _activeFolderId = signal<int?>(null);
  final _items = signal<List<BiliFavoriteItem>>([]);
  final _isLoading = signal(false);
  final _isLoadingMore = signal(false);
  final _hasMore = signal(false);
  final _keyword = signal('');
  final _order = signal(BiliFavoriteOrder.recent);
  final _errorMessage = signal<String?>(null);
  final _loadMoreErrorMessage = signal<String?>(null);
  final _authenticationRequired = signal(false);

  late final ReadonlySignal<List<BiliFavoriteFolder>> folders;
  late final ReadonlySignal<int?> activeFolderId;
  late final ReadonlySignal<List<BiliFavoriteItem>> items;
  late final ReadonlySignal<bool> isLoading;
  late final ReadonlySignal<bool> isLoadingMore;
  late final ReadonlySignal<bool> hasMore;
  late final ReadonlySignal<String> keyword;
  late final ReadonlySignal<BiliFavoriteOrder> order;
  late final ReadonlySignal<String?> errorMessage;
  late final ReadonlySignal<String?> loadMoreErrorMessage;
  late final ReadonlySignal<bool> authenticationRequired;
  late final FlutterComputed<BiliFavoriteFolder?> activeFolder;

  var _page = 1;
  var _generation = 0;
  var _disposed = false;
  int? _accountSessionRevision;

  Future<void> initialize() => refresh();

  Future<void> refresh() => _load(reloadFolders: true);

  Future<void> selectFolder(int folderId) async {
    if (_disposed || folderId == _activeFolderId.value) return;
    if (!_folders.value.any((folder) => folder.id == folderId)) return;
    _activeFolderId.value = folderId;
    await _load();
  }

  Future<void> search(String value) async {
    if (_disposed) return;
    final nextKeyword = value.trim();
    if (nextKeyword == _keyword.value) return;
    _keyword.value = nextKeyword;
    await _load();
  }

  Future<void> setOrder(BiliFavoriteOrder value) async {
    if (_disposed || value == _order.value) return;
    _order.value = value;
    await _load();
  }

  Future<void> _load({bool reloadFolders = false}) async {
    if (_disposed) return;
    final generation = ++_generation;
    if (!_checkSession()) return;
    final sessionRevision = client.sessionRevision;
    if (_accountSessionRevision != sessionRevision) {
      _folders.value = [];
      _activeFolderId.value = null;
      _accountSessionRevision = sessionRevision;
    }
    _isLoading.value = true;
    _isLoadingMore.value = false;
    _errorMessage.value = null;
    _loadMoreErrorMessage.value = null;
    _items.value = [];
    _hasMore.value = false;
    _page = 1;
    try {
      if (reloadFolders || _folders.value.isEmpty) {
        final nextFolders = await client.fetchFavoriteFolders();
        if (!_isCurrent(generation) || !_checkSession(sessionRevision)) return;
        _folders.value = nextFolders;
        if (!nextFolders.any((folder) => folder.id == _activeFolderId.value)) {
          _activeFolderId.value = nextFolders.firstOrNull?.id;
        }
      }
      final folderId = _activeFolderId.value;
      if (folderId == null) return;
      final result = await client.fetchFavoriteItems(
        folderId: folderId,
        keyword: _keyword.value,
        order: _order.value,
      );
      if (!_isCurrent(generation) || !_checkSession(sessionRevision)) return;
      _items.value = _uniqueItems(result.items);
      _hasMore.value = result.hasMore;
    } catch (error) {
      if (!_isCurrent(generation) || !_checkSession(sessionRevision)) return;
      _handleError(error, loadingMore: false);
    } finally {
      if (_isCurrent(generation)) _isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (_disposed ||
        _isLoading.value ||
        _isLoadingMore.value ||
        !_hasMore.value) {
      return;
    }
    if (!_checkSession(_accountSessionRevision)) return;
    final folderId = _activeFolderId.value;
    if (folderId == null) return;
    final generation = _generation;
    final sessionRevision = client.sessionRevision;
    final nextPage = _page + 1;
    _isLoadingMore.value = true;
    _loadMoreErrorMessage.value = null;
    try {
      final result = await client.fetchFavoriteItems(
        folderId: folderId,
        page: nextPage,
        keyword: _keyword.value,
        order: _order.value,
      );
      if (!_isCurrent(generation) || !_checkSession(sessionRevision)) return;
      final mergedItems = _uniqueItems([..._items.value, ...result.items]);
      final receivedNewItems = mergedItems.length > _items.value.length;
      _items.value = mergedItems;
      _page = nextPage;
      _hasMore.value = result.hasMore && receivedNewItems;
    } catch (error) {
      if (!_isCurrent(generation) || !_checkSession(sessionRevision)) return;
      _handleError(error, loadingMore: true);
    } finally {
      if (_isCurrent(generation)) _isLoadingMore.value = false;
    }
  }

  bool _checkSession([int? expectedRevision]) {
    if (!client.hasAuthenticatedSession) {
      _clearAccountData(authenticationRequired: true);
      return false;
    }
    if (expectedRevision != null &&
        expectedRevision != client.sessionRevision) {
      _clearAccountData(authenticationRequired: false);
      _errorMessage.value = '登录账号已变化，请刷新收藏。';
      return false;
    }
    _authenticationRequired.value = false;
    return true;
  }

  void _handleError(Object error, {required bool loadingMore}) {
    if (isBiliSessionInvalidError(error)) {
      _clearAccountData(authenticationRequired: true);
      return;
    }
    final target = loadingMore ? _loadMoreErrorMessage : _errorMessage;
    target.value = biliErrorMessage(error);
  }

  void _clearAccountData({required bool authenticationRequired}) {
    ++_generation;
    _authenticationRequired.value = authenticationRequired;
    _folders.value = [];
    _activeFolderId.value = null;
    _items.value = [];
    _hasMore.value = false;
    _isLoading.value = false;
    _isLoadingMore.value = false;
    _errorMessage.value = null;
    _loadMoreErrorMessage.value = null;
  }

  bool _isCurrent(int generation) => !_disposed && _generation == generation;

  List<BiliFavoriteItem> _uniqueItems(List<BiliFavoriteItem> values) {
    final keys = <String>{};
    return values
        .where((item) => keys.add(item.resourceKey))
        .toList(growable: false);
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    activeFolder.dispose();
    _folders.dispose();
    _activeFolderId.dispose();
    _items.dispose();
    _isLoading.dispose();
    _isLoadingMore.dispose();
    _hasMore.dispose();
    _keyword.dispose();
    _order.dispose();
    _errorMessage.dispose();
    _loadMoreErrorMessage.dispose();
    _authenticationRequired.dispose();
  }
}
