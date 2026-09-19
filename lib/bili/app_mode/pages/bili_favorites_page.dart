import 'dart:async';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/bili/common/models/bili_favorites_models.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_page.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/view_models/bili_favorites_view_model.dart';
import 'package:vesper_media/download/download.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/player/media_glass_sheet.dart';
import 'package:vesper_media/media/tv/media_tv_focusable.dart';
import 'package:vesper_media/bili/tv_mode/widgets/bili_tv_video_card.dart';

import 'bili_favorite_folder_card.dart';

part 'bili_favorites_tv.dart';

/// 手机收藏夹概览，点击卡片后浏览该收藏夹的内容。
class BiliFavoritesPage extends StatefulWidget {
  const BiliFavoritesPage({
    super.key,
    required this.client,
    this.historyStore,
    this.offlineController,
    this.onLoginTap,
    this.openPlayback,
  });

  final BiliClient client;
  final BiliHistoryStore? historyStore;
  final BiliOfflineDownloadController? offlineController;
  final Future<void> Function()? onLoginTap;

  /// 打开播放页；测试可注入以观察「返回后刷新」的行为。
  final Future<void> Function(BiliVideoDetail detail)? openPlayback;

  @override
  State<BiliFavoritesPage> createState() => _BiliFavoritesPageState();
}

class _BiliFavoritesPageState extends State<BiliFavoritesPage> {
  late final BiliFavoritesViewModel _viewModel;
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  final _openingItemId = signal<int?>(null);

  @override
  void initState() {
    super.initState();
    _viewModel = BiliFavoritesViewModel(
      client: widget.client,
      autoSelectFirstFolder: false,
    );
    unawaited(_viewModel.initialize());
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    _openingItemId.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _resetScroll() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _submitSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    _resetScroll();
    unawaited(_viewModel.search(_queryController.text));
  }

  void _selectFolder(int? folderId) {
    FocusManager.instance.primaryFocus?.unfocus();
    _queryController.text = _viewModel.keyword.value;
    _resetScroll();
    unawaited(_viewModel.selectFolder(folderId));
  }

  Future<void> _login() async {
    await widget.onLoginTap?.call();
    if (mounted) {
      await _viewModel.refresh();
    }
  }

  Future<void> _selectOrder() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showMediaGlassSheet<BiliFavoriteOrder>(
      context: context,
      appearance: MediaGlassSheetAppearance.readable,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text('收藏排序', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final order in BiliFavoriteOrder.values)
            AppPressScale(
              child: ListTile(
                title: Text(order.label),
                selected: order == _viewModel.order.value,
                trailing: order == _viewModel.order.value
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(order),
              ),
            ),
        ],
      ),
    );
    if (mounted && selected != null) {
      _resetScroll();
      await _viewModel.setOrder(selected);
    }
  }

  Future<void> _openVideo(BiliFavoriteItem item) async {
    if (!item.isAvailable || _openingItemId.value != null) {
      return;
    }
    _openingItemId.value = item.id;
    try {
      final detail = await widget.client.fetchVideoDetail(item.bvid);
      if (!mounted) return;
      if (detail.pages.isEmpty) {
        throw const BiliApiException('视频暂无可播放的分集。');
      }
      final openPlayback = widget.openPlayback;
      if (openPlayback != null) {
        await openPlayback(detail);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BiliPlaybackPage(
              detail: detail,
              initialPage: detail.pages.first,
              client: widget.client,
              historyStore: widget.historyStore ?? const BiliHistoryStore(),
              offlineController: widget.offlineController,
            ),
          ),
        );
      }
      // 播放页可以取消收藏，返回后列表与计数都可能已变化。
      if (mounted) {
        await _viewModel.refresh();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('打开视频失败：${biliErrorMessage(error)}')),
          );
      }
    } finally {
      if (mounted) {
        _openingItemId.value = null;
      }
    }
  }

  Future<void> _confirmRemoveItems(
    List<String> resourceKeys, {
    required String message,
  }) async {
    final shouldRemove = await showMediaGlassDialog<bool>(
      context: context,
      title: '移出收藏夹？',
      message: message,
      actions: const [
        MediaGlassDialogAction(label: '取消', value: false),
        MediaGlassDialogAction(label: '移出', value: true, isDestructive: true),
      ],
    );
    if (shouldRemove != true || !mounted) {
      return;
    }
    final result = await _viewModel.removeItems(resourceKeys);
    if (result != null && mounted) {
      _showMessage(result);
    }
  }

  Future<void> _confirmRemoveItem(BiliFavoriteItem item) async {
    final folderTitle = _viewModel.activeFolder.value?.title;
    await _confirmRemoveItems(
      [item.resourceKey],
      message: folderTitle == null
          ? '将从当前收藏夹移出「${item.title}」。'
          : '将从「$folderTitle」移出「${item.title}」。',
    );
  }

  Future<void> _confirmRemoveSelected() async {
    final count = _viewModel.selectedResourceKeys.value.length;
    await _confirmRemoveItems(
      _viewModel.selectedResourceKeys.value.toList(growable: false),
      message: '将从当前收藏夹移出已选的 $count 个内容。',
    );
  }

  Future<void> _createFolder() async {
    final title = await showMediaGlassSheet<String>(
      context: context,
      builder: (context) => _FolderCreateSheet(
        isBusy: () => _viewModel.isMutating.value,
        onCreate: (title, isPrivate) =>
            _viewModel.createFolder(title: title, isPrivate: isPrivate),
      ),
    );
    if (title != null && mounted) {
      _showMessage('已创建收藏夹「$title」');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final visualTheme = AppVisualTheme.of(context);
      final selectionMode = _viewModel.isSelectionMode.value;
      final selectedCount = _viewModel.selectedResourceKeys.value.length;
      final activeFolder = _viewModel.activeFolder.value;
      return PopScope<void>(
        // 返回键依次退出多选、返回收藏夹概览、退出页面。
        canPop: !selectionMode && activeFolder == null,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (selectionMode) {
            _viewModel.endSelection();
          } else if (activeFolder != null) {
            _selectFolder(null);
          }
        },
        child: AppGlassScaffold(
          backgroundColor: visualTheme.background,
          extendBody: false,
          resizeToAvoidBottomInset: true,
          appBarHeight: 52,
          appBar: GlassAppBar(
            centerTitle: false,
            leading: AppPressScale(
              child: IconButton(
                tooltip: selectionMode
                    ? '退出多选'
                    : activeFolder == null
                    ? '返回'
                    : '返回收藏夹',
                onPressed: selectionMode
                    ? _viewModel.endSelection
                    : activeFolder != null
                    ? () => _selectFolder(null)
                    : () => Navigator.of(context).maybePop(),
                icon: Icon(
                  selectionMode
                      ? Icons.close_rounded
                      : Icons.arrow_back_rounded,
                ),
              ),
            ),
            title: Text(
              selectionMode
                  ? '已选 $selectedCount 项'
                  : activeFolder?.title ?? '我的收藏',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              if (selectionMode) ...[
                AppPressScale(
                  child: IconButton(
                    tooltip: '全选',
                    onPressed: _viewModel.toggleSelectAll,
                    icon: const Icon(Icons.select_all_rounded),
                  ),
                ),
                AppPressScale(
                  child: TextButton.icon(
                    key: const ValueKey('bili-favorites-remove-selected'),
                    onPressed: selectedCount == 0 || _viewModel.isMutating.value
                        ? null
                        : () => unawaited(_confirmRemoveSelected()),
                    icon: _viewModel.isMutating.value
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline_rounded),
                    label: const Text('移出'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      foregroundColor: visualTheme.destructive,
                    ),
                  ),
                ),
              ] else ...[
                if (activeFolder == null &&
                    !_viewModel.authenticationRequired.value &&
                    _viewModel.folders.value.isNotEmpty)
                  AppPressScale(
                    child: IconButton(
                      key: const ValueKey('bili-favorites-create-folder'),
                      tooltip: '新建收藏夹',
                      onPressed: _viewModel.isMutating.value
                          ? null
                          : () => unawaited(_createFolder()),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ),
                AppPressScale(
                  child: IconButton(
                    tooltip: '刷新收藏',
                    onPressed: _viewModel.isLoading.value
                        ? null
                        : () => unawaited(_viewModel.refresh()),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ],
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _viewModel.refresh,
            child: CustomScrollView(
              key: const ValueKey('bili-favorites-content'),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: _buildSlivers(context),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _buildSlivers(BuildContext context) {
    final vm = _viewModel;
    final folders = vm.folders.value;
    final items = vm.items.value;
    final openingItemId = _openingItemId.value;
    if (vm.authenticationRequired.value) {
      return [
        _FavoriteStatus(
          icon: Icons.lock_outline_rounded,
          message: '登录后查看收藏',
          detail: vm.errorMessage.value,
          actionLabel: widget.onLoginTap == null ? null : '登录',
          onAction: _login,
        ),
      ];
    }
    if (folders.isEmpty) {
      if (vm.isLoading.value) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      }
      final error = vm.errorMessage.value;
      final onAction = error == null ? _createFolder : vm.refresh;
      return [
        _FavoriteStatus(
          icon: Icons.folder_open_rounded,
          message: error == null ? '还没有收藏夹。' : '加载失败：$error',
          actionKey: error == null
              ? const ValueKey('bili-favorites-create-folder')
              : null,
          actionLabel: error == null ? '新建收藏夹' : '重试',
          onAction: vm.isMutating.value ? null : onAction,
        ),
      ];
    }
    if (vm.activeFolderId.value == null) {
      return [
        if (vm.errorMessage.value case final String error)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('刷新失败：$error'),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.separated(
            itemCount: folders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => BiliFavoriteFolderCard(
              key: ValueKey('favorite-folder-${folders[index].id}'),
              client: widget.client,
              folder: folders[index],
              reloadToken: folders,
              onTap: () => _selectFolder(folders[index].id),
            ),
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(child: _buildSearch(context)),
      if (vm.isLoading.value)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (vm.errorMessage.value case final String error)
        _FavoriteStatus(
          icon: Icons.cloud_off_rounded,
          message: '加载失败：$error',
          actionLabel: '重试',
          onAction: vm.refresh,
        )
      else if (items.isEmpty)
        _FavoriteStatus(
          icon: Icons.video_library_outlined,
          message: vm.keyword.value.isEmpty ? '这个收藏夹还是空的。' : '没有匹配的收藏内容。',
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final selectionMode = vm.isSelectionMode.value;
              final selected = vm.selectedResourceKeys.value.contains(
                item.resourceKey,
              );
              return _FavoriteVideoTile(
                key: ValueKey('favorite-${item.type}-${item.id}'),
                item: item,
                opening: openingItemId == item.id,
                selectionMode: selectionMode,
                selected: selected,
                onTap: openingItemId != null
                    ? null
                    : selectionMode
                    ? () => vm.toggleSelection(item.resourceKey)
                    : (item.isAvailable
                          ? () => unawaited(_openVideo(item))
                          : null),
                onLongPress: selectionMode ? null : () => vm.beginSelection(),
                onRemove: vm.isMutating.value
                    ? null
                    : () => unawaited(_confirmRemoveItem(item)),
              );
            },
          ),
        ),
      if (vm.loadMoreErrorMessage.value case final String error)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: Text('加载更多失败：$error', textAlign: TextAlign.center),
          ),
        ),
      if (vm.hasMore.value && !vm.isLoading.value)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: AppPressScale(
                child: TextButton.icon(
                  onPressed: vm.isLoadingMore.value
                      ? null
                      : () => unawaited(vm.loadMore()),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  icon: vm.isLoadingMore.value
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(
                    vm.isLoadingMore.value
                        ? '加载中'
                        : vm.loadMoreErrorMessage.value == null
                        ? '加载更多'
                        : '重试加载',
                  ),
                ),
              ),
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
      ),
    ];
  }

  Widget _buildSearch(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _queryController,
            builder: (context, value, _) => TextField(
              key: const ValueKey('bili-favorites-search'),
              controller: _queryController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submitSearch(),
              decoration: InputDecoration(
                hintText: '搜索当前收藏夹',
                filled: true,
                fillColor: visualTheme.surface,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: value.text.isEmpty
                    ? null
                    : AppPressScale(
                        child: IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _queryController.clear();
                            _submitSearch();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppVisualTokens.controlRadius,
                  ),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppPressScale(
              child: TextButton.icon(
                key: const ValueKey('bili-favorites-sort'),
                onPressed: () => unawaited(_selectOrder()),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                icon: const Icon(Icons.sort_rounded, size: 18),
                label: Text(_viewModel.order.value.label),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteStatus extends StatelessWidget {
  const _FavoriteStatus({
    required this.icon,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final IconData icon;
  final String message;
  final String? detail;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: visualTheme.textTertiary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (detail != null && detail != message) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: visualTheme.textSecondary),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              AppGlassButton(
                key: actionKey,
                label: actionLabel!,
                enabled: onAction != null,
                onPressed: () => unawaited(onAction?.call()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FavoriteVideoTile extends StatelessWidget {
  const _FavoriteVideoTile({
    super.key,
    required this.item,
    required this.opening,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onRemove,
  });

  final BiliFavoriteItem item;
  final bool opening;
  final VoidCallback? onTap;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final unavailableLabel = item.type == 2 ? '视频已失效' : '暂不支持播放此内容';
    final tile = Semantics(
      button: true,
      enabled: onTap != null,
      selected: selectionMode ? selected : null,
      child: Material(
        color: selected ? visualTheme.surfaceRaised : visualTheme.surface,
        borderRadius: BorderRadius.circular(AppVisualTokens.controlRadius),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(AppVisualTokens.controlRadius),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final coverWidth = (constraints.maxWidth * 0.36).clamp(
                  80.0,
                  144.0,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selectionMode) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 6),
                        child: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 22,
                          color: selected
                              ? AppVisualTokens.primaryBlue
                              : visualTheme.textTertiary,
                        ),
                      ),
                    ],
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: coverWidth,
                        height: coverWidth * 9 / 16,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (item.coverUrl.isNotEmpty)
                              Image.network(
                                item.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => ColoredBox(
                                  color: visualTheme.surfaceRaised,
                                  child: const Icon(
                                    Icons.video_library_outlined,
                                  ),
                                ),
                              )
                            else
                              ColoredBox(
                                color: visualTheme.surfaceRaised,
                                child: Icon(
                                  item.isAvailable
                                      ? Icons.video_library_outlined
                                      : Icons.videocam_off_outlined,
                                  color: visualTheme.textTertiary,
                                ),
                              ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: visualTheme.imageOutline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: item.isAvailable
                                  ? visualTheme.textPrimary
                                  : visualTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.isAvailable
                                ? item.ownerName
                                : unavailableLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: visualTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (item.playCountLabel.isNotEmpty)
                                '${item.playCountLabel}播放',
                              if (item.durationLabel.isNotEmpty)
                                item.durationLabel,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: visualTheme.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                          if (item.favoritedAtLabel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '收藏于 ${item.favoritedAtLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: visualTheme.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (opening)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!selectionMode && onRemove != null)
                      AppPressScale(
                        child: IconButton(
                          key: ValueKey(
                            'favorite-remove-${item.type}-${item.id}',
                          ),
                          tooltip: '移出收藏夹',
                          onPressed: onRemove,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: AppVisualTokens.minimumTapTarget,
                            minHeight: AppVisualTokens.minimumTapTarget,
                          ),
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            color: visualTheme.textTertiary,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    // 无可交互动作（失效视频且不支持移出）时不加按压反馈，避免按了没反应。
    final interactive =
        onTap != null || onLongPress != null || onRemove != null;
    return interactive ? AppPressScale(child: tile) : tile;
  }
}

/// 新建收藏夹表单。提交成功后由调用方关闭并提示，失败时留在表单内展示原因。
class _FolderCreateSheet extends StatefulWidget {
  const _FolderCreateSheet({required this.isBusy, required this.onCreate});

  final bool Function() isBusy;
  final Future<int?> Function(String title, bool isPrivate) onCreate;

  @override
  State<_FolderCreateSheet> createState() => _FolderCreateSheetState();
}

class _FolderCreateSheetState extends State<_FolderCreateSheet> {
  final _controller = TextEditingController();
  bool _isPrivate = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final id = await widget.onCreate(title, _isPrivate);
    if (!mounted) return;
    if (id == null) {
      setState(() {
        _submitting = false;
        _error = '创建失败，请稍后重试。';
      });
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '新建收藏夹',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('bili-favorites-folder-title'),
            controller: _controller,
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_submit()),
            decoration: InputDecoration(
              hintText: '收藏夹名称',
              filled: true,
              fillColor: visualTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  AppVisualTokens.controlRadius,
                ),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('bili-favorites-folder-private'),
            value: _isPrivate,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _isPrivate = value),
            contentPadding: EdgeInsets.zero,
            title: const Text('设为私密'),
            subtitle: const Text('私密收藏夹只有自己可见'),
          ),
          if (_error case final String message) ...[
            const SizedBox(height: 4),
            Text(message, style: TextStyle(color: visualTheme.destructive)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      44,
                      AppVisualTokens.minimumTapTarget,
                    ),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppGlassButton(
                  label: _submitting ? '创建中' : '创建',
                  enabled: !_submitting && !widget.isBusy(),
                  onPressed: () => unawaited(_submit()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
