import 'package:signals/signals_flutter.dart';

import '../models/bili_favorites_models.dart';
import '../models/bili_models.dart';
import '../services/bili_api_core.dart';
import '../services/bili_client.dart';

final class BiliFavoritesViewModel {
  BiliFavoritesViewModel({
    required this.client,
    this.autoSelectFirstFolder = true,
  }) {
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
    selectedResourceKeys = _selectedResourceKeys.readonly();
    isSelectionMode = _isSelectionMode.readonly();
    isMutating = _isMutating.readonly();
    activeFolder = computed(() {
      final id = _activeFolderId.value;
      for (final folder in _folders.value) {
        if (folder.id == id) return folder;
      }
      return null;
    });
  }

  final BiliClient client;

  /// 手机先显示收藏夹概览；TV 保持默认选中首个收藏夹。
  final bool autoSelectFirstFolder;
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
  final _selectedResourceKeys = signal<Set<String>>(<String>{});
  final _isSelectionMode = signal(false);
  final _isMutating = signal(false);

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

  /// 已勾选的资源标识集合。空集不代表非多选态，见 [isSelectionMode]。
  late final ReadonlySignal<Set<String>> selectedResourceKeys;

  /// 多选模式独立于选择数量：允许进入多选后「已选 0 项」。
  late final ReadonlySignal<bool> isSelectionMode;

  /// 移出 / 新建等写操作进行中，用于禁用重复提交。
  late final ReadonlySignal<bool> isMutating;
  late final FlutterComputed<BiliFavoriteFolder?> activeFolder;

  var _page = 1;
  var _generation = 0;
  var _disposed = false;
  int? _accountSessionRevision;

  Future<void> initialize() => refresh();

  Future<void> refresh() => _load(reloadFolders: true);

  Future<void> selectFolder(int? folderId) async {
    if (_disposed || folderId == _activeFolderId.value) return;
    if (folderId != null &&
        !_folders.value.any((folder) => folder.id == folderId)) {
      return;
    }
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

  /// 进入多选模式。进入时选择为空，界面显示「已选 0 项」。
  void beginSelection() {
    if (_disposed) return;
    _isSelectionMode.value = true;
    _selectedResourceKeys.value = <String>{};
  }

  /// 退出多选模式并清空选择。
  void endSelection() {
    if (_disposed) return;
    _isSelectionMode.value = false;
    _selectedResourceKeys.value = <String>{};
  }

  void toggleSelection(String resourceKey) {
    if (_disposed || !_isSelectionMode.value) return;
    final next = Set<String>.of(_selectedResourceKeys.value);
    if (!next.remove(resourceKey)) {
      next.add(resourceKey);
    }
    _selectedResourceKeys.value = next;
  }

  /// 全选 / 取消全选当前已加载的可见行。
  void toggleSelectAll() {
    if (_disposed || !_isSelectionMode.value) return;
    final selectable = _items.value.map((item) => item.resourceKey).toSet();
    if (_selectedResourceKeys.value.length == selectable.length &&
        selectable.isNotEmpty) {
      _selectedResourceKeys.value = <String>{};
      return;
    }
    _selectedResourceKeys.value = selectable;
  }

  /// 移出当前收藏夹中已勾选的条目。
  Future<String?> removeSelected() {
    final selectedKeys = _selectedResourceKeys.value;
    if (selectedKeys.isEmpty) return Future<String?>.value();
    return removeItems(selectedKeys);
  }

  /// 移出当前收藏夹中的指定条目（单条或多条）。
  ///
  /// 删除会改变服务端分页偏移，成功后从第一页重新读取。
  Future<String?> removeItems(Iterable<String> resourceKeys) async {
    if (_disposed || _isMutating.value) return null;
    if (!_checkSession(_accountSessionRevision)) return null;
    final folderId = _activeFolderId.value;
    final keys = resourceKeys.toSet();
    if (folderId == null || keys.isEmpty) return null;
    final generation = _generation;
    final sessionRevision = client.sessionRevision;
    _isMutating.value = true;
    try {
      await client.removeFavoriteItems(
        folderId: folderId,
        resourceIds: keys.toList(growable: false),
      );
      if (!_isCurrent(generation) || !_checkSession(sessionRevision)) {
        return null;
      }
      await refresh();
      return '已移出 ${keys.length} 个内容';
    } catch (error) {
      if (!_isCurrent(generation) || !_checkSession(sessionRevision)) {
        return null;
      }
      if (isBiliSessionInvalidError(error)) {
        _clearAccountData(authenticationRequired: true);
        return null;
      }
      // 失败不丢行：列表与选择都保持原样，便于直接重试。
      return '移出失败：${biliErrorMessage(error)}';
    } finally {
      if (!_disposed) _isMutating.value = false;
    }
  }

  /// 新建收藏夹；返回服务端分配的 ID，失败返回 null 并写入 [errorMessage]。
  Future<int?> createFolder({
    required String title,
    required bool isPrivate,
  }) async {
    if (_disposed || _isMutating.value) return null;
    if (!_checkSession(_accountSessionRevision)) return null;
    final generation = _generation;
    final sessionRevision = client.sessionRevision;
    _isMutating.value = true;
    try {
      final id = await client.createFavoriteFolder(
        title: title,
        isPrivate: isPrivate,
      );
      if (!_isCurrent(generation) || !_checkSession(sessionRevision)) {
        return null;
      }
      await refresh();
      return id;
    } catch (error) {
      if (!_isCurrent(generation) || !_checkSession(sessionRevision)) {
        return null;
      }
      if (isBiliSessionInvalidError(error)) {
        _clearAccountData(authenticationRequired: true);
        return null;
      }
      _errorMessage.value = biliErrorMessage(error);
      return null;
    } finally {
      if (!_disposed) _isMutating.value = false;
    }
  }

  Future<void> _load({bool reloadFolders = false}) async {
    if (_disposed) return;
    final generation = ++_generation;
    if (!_checkSession()) return;
    // 列表内容即将变更，旧选择不再指向可见行。
    _isSelectionMode.value = false;
    _selectedResourceKeys.value = <String>{};
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
          _activeFolderId.value = autoSelectFirstFolder
              ? nextFolders.firstOrNull?.id
              : null;
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
        _isMutating.value ||
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
    _isSelectionMode.value = false;
    _selectedResourceKeys.value = <String>{};
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
    _selectedResourceKeys.dispose();
    _isSelectionMode.dispose();
    _isMutating.dispose();
  }
}
