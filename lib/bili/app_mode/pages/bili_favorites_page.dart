import 'dart:async';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/bili/common/models/bili_favorites_models.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_page.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/view_models/bili_favorites_view_model.dart';
import 'package:vesper_media/download/download.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/player/media_glass_sheet.dart';

/// Browses one real favorite folder at a time using the signed-in client.
class BiliFavoritesPage extends StatefulWidget {
  const BiliFavoritesPage({
    super.key,
    required this.client,
    this.historyStore,
    this.offlineController,
    this.onLoginTap,
  });

  final BiliClient client;
  final BiliHistoryStore? historyStore;
  final BiliOfflineDownloadController? offlineController;
  final Future<void> Function()? onLoginTap;

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
    _viewModel = BiliFavoritesViewModel(client: widget.client);
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

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final visualTheme = AppVisualTheme.of(context);
      return AppGlassScaffold(
        backgroundColor: visualTheme.background,
        extendBody: false,
        resizeToAvoidBottomInset: true,
        appBarHeight: 52,
        appBar: GlassAppBar(
          centerTitle: false,
          leading: AppPressScale(
            child: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          title: Text(
            '我的收藏',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
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
      return [
        _FavoriteStatus(
          icon: Icons.folder_open_rounded,
          message: vm.errorMessage.value == null
              ? '还没有收藏夹。'
              : '加载失败：${vm.errorMessage.value}',
          actionLabel: vm.errorMessage.value == null ? null : '重试',
          onAction: vm.refresh,
        ),
      ];
    }
    final selectedIndex = folders.indexWhere(
      (folder) => folder.id == vm.activeFolderId.value,
    );
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabsWidth = folders.length * 156.0;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tabsWidth > constraints.maxWidth
                      ? tabsWidth
                      : constraints.maxWidth,
                  child: AppGlassSectionTabs(
                    items: [
                      for (final folder in folders)
                        AppGlassNavigationItem(
                          label: folder.mediaCount == null
                              ? folder.title
                              : '${folder.title} ${folder.mediaCount}',
                          semanticLabel: folder.mediaCount == null
                              ? folder.title
                              : '${folder.title}，${folder.mediaCount} 个内容',
                          icon: Icons.folder_outlined,
                          activeIcon: Icons.folder_rounded,
                        ),
                    ],
                    selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
                    onSelected: (index) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      _queryController.text = vm.keyword.value;
                      _resetScroll();
                      unawaited(vm.selectFolder(folders[index].id));
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
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
              return _FavoriteVideoTile(
                key: ValueKey('favorite-${item.type}-${item.id}'),
                item: item,
                opening: openingItemId == item.id,
                onTap: item.isAvailable && openingItemId == null
                    ? () => unawaited(_openVideo(item))
                    : null,
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
  });

  final IconData icon;
  final String message;
  final String? detail;
  final String? actionLabel;
  final Future<void> Function()? onAction;

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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              AppGlassButton(
                label: actionLabel!,
                onPressed: () => unawaited(onAction!()),
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
  });

  final BiliFavoriteItem item;
  final bool opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final unavailableLabel = item.type == 2 ? '视频已失效' : '暂不支持播放此内容';
    final tile = Semantics(
      button: item.isAvailable,
      enabled: onTap != null,
      child: Material(
        color: visualTheme.surface,
        borderRadius: BorderRadius.circular(AppVisualTokens.controlRadius),
        child: InkWell(
          onTap: onTap,
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
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    return onTap == null ? tile : AppPressScale(child: tile);
  }
}
