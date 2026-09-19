part of 'bili_favorites_page.dart';

const _tvFavoritesCompactRailWidth = 88.0;
const _tvFavoritesExpandedRailWidth = 312.0;

/// TV 收藏浏览：左侧收藏夹栏 + 右侧网格，共用手机版 view model。
///
/// 遥控器没有长按语义，因此多选由可聚焦的「管理」入口进入；返回键先退出
/// 多选，再退出页面。
class BiliFavoritesTvView extends StatefulWidget {
  const BiliFavoritesTvView({
    super.key,
    required this.client,
    this.historyStore,
    this.offlineController,
    this.onLoginTap,
    this.autofocusRail = true,
  });

  final BiliClient client;
  final BiliHistoryStore? historyStore;
  final BiliOfflineDownloadController? offlineController;
  final Future<void> Function()? onLoginTap;
  final bool autofocusRail;

  @override
  State<BiliFavoritesTvView> createState() => _BiliFavoritesTvViewState();
}

class _BiliFavoritesTvViewState extends State<BiliFavoritesTvView> {
  late final BiliFavoritesViewModel _viewModel;
  bool _railCollapsed = false;
  bool _pendingRailCollapsed = false;
  bool _railCollapseScheduled = false;
  String? _openingBvid;

  @override
  void initState() {
    super.initState();
    _viewModel = BiliFavoritesViewModel(client: widget.client);
    unawaited(_viewModel.initialize());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _setRailCollapsed(bool collapsed) {
    if (!mounted || _railCollapsed == collapsed) {
      return;
    }
    _pendingRailCollapsed = collapsed;
    if (_railCollapseScheduled) {
      return;
    }
    _railCollapseScheduled = true;
    // 焦点回调运行在 FocusManager 事务内，布局变化必须延后到该轮次之后，
    // 否则替换轨道会在这轮遍历中改动焦点节点集合。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _railCollapseScheduled = false;
      final target = _pendingRailCollapsed;
      if (target == _railCollapsed) return;
      setState(() => _railCollapsed = target);
    });
  }

  Future<void> _selectFolder(int folderId) async {
    _setRailCollapsed(true);
    await _viewModel.selectFolder(folderId);
  }

  Future<void> _openVideo(BiliFavoriteItem item) async {
    if (!item.isAvailable || _openingBvid != null) return;
    setState(() => _openingBvid = item.bvid);
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
            presentationMode: BiliPlaybackPresentationMode.tv,
          ),
        ),
      );
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
        setState(() => _openingBvid = null);
      }
    }
  }

  Future<void> _confirmRemoveSelected() async {
    final count = _viewModel.selectedResourceKeys.value.length;
    final shouldRemove = await showMediaGlassDialog<bool>(
      context: context,
      title: '移出收藏夹？',
      message: '将从当前收藏夹移出已选的 $count 个内容。',
      actions: const [
        MediaGlassDialogAction(label: '取消', value: false),
        MediaGlassDialogAction(label: '移出', value: true, isDestructive: true),
      ],
    );
    if (shouldRemove != true || !mounted) return;
    final result = await _viewModel.removeSelected();
    if (result != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result)));
    }
  }

  Future<void> _createFolder() async {
    final title = await showMediaGlassSheet<String>(
      context: context,
      appearance: MediaGlassSheetAppearance.readable,
      builder: (context) => _FolderCreateSheet(
        isBusy: () => _viewModel.isMutating.value,
        onCreate: (title, isPrivate) =>
            _viewModel.createFolder(title: title, isPrivate: isPrivate),
      ),
    );
    if (title != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已创建收藏夹「$title」')));
    }
  }

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final selectionMode = _viewModel.isSelectionMode.value;
      return PopScope<void>(
        canPop: !selectionMode,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && selectionMode) {
            _viewModel.endSelection();
          }
        },
        child: Row(
          children: [
            _buildRail(context),
            const SizedBox(width: 20),
            Expanded(child: _buildContent(context)),
          ],
        ),
      );
    },
  );

  Widget _buildRail(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final folders = _viewModel.folders.value;
    final activeFolderId = _viewModel.activeFolderId.value;
    final collapsed = _railCollapsed;
    return AnimatedContainer(
      key: const ValueKey<String>('bili-tv-favorites-rail'),
      duration: AppVisualTokens.motionDuration(
        context,
        AppVisualTokens.tvFocusDuration,
      ),
      curve: Curves.easeOutCubic,
      width: collapsed
          ? _tvFavoritesCompactRailWidth
          : _tvFavoritesExpandedRailWidth,
      decoration: BoxDecoration(
        color: visualTheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
        border: Border.all(color: visualTheme.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 展开动画尚未提供完整宽度时，继续使用图标布局。
          final collapsed =
              _railCollapsed ||
              constraints.maxWidth < _tvFavoritesExpandedRailWidth - 2;
          return Column(
            children: [
              SizedBox(
                key: ValueKey<String>(
                  collapsed
                      ? 'bili-tv-favorites-rail-collapsed'
                      : 'bili-tv-favorites-rail-expanded',
                ),
                width: 0,
                height: 0,
              ),
              if (!collapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_copy_outlined,
                        color: visualTheme.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '我的收藏',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: visualTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: TvFocusAreaScope(
                  area: TvFocusArea.rail,
                  child: TvFocusOverlayScope(
                    key: const ValueKey<String>(
                      'bili-tv-favorites-rail-focus-scope',
                    ),
                    child: folders.isEmpty
                        ? _buildRailStatus(context, collapsed: collapsed)
                        : ListView.separated(
                            key: const ValueKey<String>(
                              'bili-tv-favorites-rail-list',
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: collapsed ? 8 : 10,
                              vertical: tvInlineFocusSafeInset,
                            ),
                            itemCount: folders.length + 1,
                            separatorBuilder: (_, _) =>
                                SizedBox(height: collapsed ? 8 : 6),
                            itemBuilder: (context, index) {
                              if (index == folders.length) {
                                return _TvFavoritesRailAction(
                                  key: const ValueKey<String>(
                                    'bili-tv-favorites-rail-create',
                                  ),
                                  icon: Icons.add_rounded,
                                  label: '新建收藏夹',
                                  collapsed: collapsed,
                                  enabled: !_viewModel.isMutating.value,
                                  onFocused: () => _setRailCollapsed(false),
                                  onTap: () => unawaited(_createFolder()),
                                );
                              }
                              final folder = folders[index];
                              return _TvFavoritesRailFolder(
                                key: ValueKey<String>(
                                  'bili-tv-favorites-folder-${folder.id}',
                                ),
                                folder: folder,
                                selected: folder.id == activeFolderId,
                                collapsed: collapsed,
                                autofocus:
                                    widget.autofocusRail &&
                                    folder.id == activeFolderId,
                                onFocused: () => _setRailCollapsed(false),
                                onTap: () =>
                                    unawaited(_selectFolder(folder.id)),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRailStatus(BuildContext context, {required bool collapsed}) {
    final visualTheme = AppVisualTheme.of(context);
    if (_viewModel.isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }
    final authenticationRequired = _viewModel.authenticationRequired.value;
    final canCreate =
        !authenticationRequired && _viewModel.errorMessage.value == null;
    if (canCreate) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!collapsed)
            const Padding(padding: EdgeInsets.all(18), child: Text('还没有收藏夹。')),
          _TvFavoritesRailAction(
            key: const ValueKey<String>('bili-tv-favorites-rail-create'),
            icon: Icons.add_rounded,
            label: '新建收藏夹',
            collapsed: collapsed,
            autofocus: widget.autofocusRail,
            enabled: !_viewModel.isMutating.value,
            onFocused: () => _setRailCollapsed(false),
            onTap: () => unawaited(_createFolder()),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            authenticationRequired
                ? Icons.lock_outline_rounded
                : Icons.folder_open_rounded,
            size: 36,
            color: visualTheme.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            authenticationRequired
                ? '登录后查看收藏'
                : '加载失败：${_viewModel.errorMessage.value}',
            textAlign: TextAlign.center,
            style: TextStyle(color: visualTheme.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          // TvFocusableSurface 的 Stack 需要有限高度约束，列内必须自带尺寸。
          SizedBox(
            height: 44,
            child: TvFocusableSurface(
              debugLabel: 'tv_favorites_status_action',
              autofocus: widget.autofocusRail,
              borderRadius: AppVisualTokens.controlRadius,
              focusArea: TvFocusArea.rail,
              onTap: () {
                if (authenticationRequired && widget.onLoginTap != null) {
                  unawaited(widget.onLoginTap!.call());
                  return;
                }
                unawaited(_viewModel.refresh());
              },
              builder: (context, focused) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Text(
                    authenticationRequired && widget.onLoginTap != null
                        ? '登录'
                        : '重试',
                    style: TextStyle(
                      color: focused
                          ? AppVisualTokens.primaryBlue
                          : visualTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final vm = _viewModel;
    final items = vm.items.value;
    final selectionMode = vm.isSelectionMode.value;
    final selectedCount = vm.selectedResourceKeys.value.length;
    return TvFocusAreaScope(
      area: TvFocusArea.content,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  selectionMode ? '已选 $selectedCount 项' : '收藏内容',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: visualTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selectionMode) ...[
                _buildHeaderAction(
                  context,
                  key: const ValueKey<String>('bili-tv-favorites-select-all'),
                  label: '全选',
                  icon: Icons.select_all_rounded,
                  onTap: vm.toggleSelectAll,
                ),
                const SizedBox(width: 10),
                _buildHeaderAction(
                  context,
                  key: const ValueKey<String>('bili-tv-favorites-remove'),
                  label: '移出',
                  icon: Icons.delete_outline_rounded,
                  destructive: true,
                  enabled: selectedCount > 0 && !vm.isMutating.value,
                  onTap: () => unawaited(_confirmRemoveSelected()),
                ),
                const SizedBox(width: 10),
                _buildHeaderAction(
                  context,
                  key: const ValueKey<String>('bili-tv-favorites-cancel'),
                  label: '取消',
                  icon: Icons.close_rounded,
                  onTap: vm.endSelection,
                ),
              ] else ...[
                _buildHeaderAction(
                  context,
                  key: const ValueKey<String>('bili-tv-favorites-manage'),
                  label: '管理',
                  icon: Icons.tune_rounded,
                  enabled: items.isNotEmpty,
                  onTap: vm.beginSelection,
                ),
                const SizedBox(width: 10),
                _buildHeaderAction(
                  context,
                  key: const ValueKey<String>('bili-tv-favorites-refresh'),
                  label: '刷新',
                  icon: Icons.refresh_rounded,
                  onTap: () => unawaited(vm.refresh()),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildGrid(context, items)),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(
    BuildContext context, {
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
    bool destructive = false,
  }) {
    final visualTheme = AppVisualTheme.of(context);
    final color = destructive
        ? visualTheme.destructive
        : visualTheme.textPrimary;
    // 顶栏内的动作位于 Row，宽度不受约束，因此用不带 expand-Stack 的
    // TvFocusable；TvFocusableSurface 需要双向有界约束。
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: TvFocusable(
        key: key,
        debugLabel: 'tv_favorites_action_$label',
        focusArea: TvFocusArea.content,
        baseCornerRadius: AppVisualTokens.controlRadius,
        focusCornerRadius: AppVisualTokens.controlRadius,
        scale: 1.05,
        onTap: enabled ? onTap : () {},
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: focused ? AppVisualTokens.primaryBlue : color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: focused ? AppVisualTokens.primaryBlue : color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<BiliFavoriteItem> items) {
    final vm = _viewModel;
    if (vm.isLoading.value && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.authenticationRequired.value) {
      // 登录提示由收藏夹栏承担，内容区不重复同一段文案。
      return const SizedBox.shrink();
    }
    if (vm.errorMessage.value case final String error) {
      return _buildContentStatus(
        context,
        icon: Icons.cloud_off_rounded,
        message: '加载失败：$error',
      );
    }
    if (items.isEmpty) {
      return _buildContentStatus(
        context,
        icon: Icons.video_library_outlined,
        message: vm.keyword.value.isEmpty ? '这个收藏夹还是空的。' : '没有匹配的收藏内容。',
      );
    }
    final selectionMode = vm.isSelectionMode.value;
    final selectedKeys = vm.selectedResourceKeys.value;
    final hasMore = vm.hasMore.value;
    return TvFocusOverlayScope(
      key: const ValueKey<String>('bili-tv-favorites-grid-focus-scope'),
      child: GridView.builder(
        key: const ValueKey<String>('bili-tv-favorites-grid'),
        clipBehavior: Clip.none,
        padding: const EdgeInsets.all(tvFocusSafeInset),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisSpacing: 24,
          crossAxisSpacing: 22,
          childAspectRatio: 1.08,
        ),
        itemCount: items.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == items.length) {
            return _buildLoadMore(context);
          }
          final item = items[index];
          final selected = selectedKeys.contains(item.resourceKey);
          return BiliTvVideoCard(
            key: ValueKey<String>('bili-tv-favorite-card-${item.resourceKey}'),
            coverUrl: item.coverUrl,
            coverCacheWidth: _tvFavoritesCoverCacheWidth(context),
            title: item.title,
            subtitle: item.isAvailable
                ? [
                    if (item.playCountLabel.isNotEmpty)
                      '${item.playCountLabel}播放',
                    if (item.favoritedAtLabel.isNotEmpty)
                      '收藏于 ${item.favoritedAtLabel}',
                  ].join(' · ')
                : (item.type == 2 ? '视频已失效' : '暂不支持播放此内容'),
            durationLabel: item.durationLabel,
            leadingLabel: selectionMode && selected ? '✓ 已选' : '',
            // 首焦点属于收藏夹栏；网格抢焦会立刻把侧栏收窄，用户就看不到
            // 自己有哪些收藏夹。与 TV 关注浏览器的 rail-first 行为一致。
            autofocus: !widget.autofocusRail && index == 0,
            debugLabel: 'tv_favorite_${item.resourceKey}',
            onFocusChange: (focused) {
              if (focused) _setRailCollapsed(true);
            },
            onTap: () {
              if (selectionMode) {
                _viewModel.toggleSelection(item.resourceKey);
                return;
              }
              if (!item.isAvailable) return;
              unawaited(_openVideo(item));
            },
          );
        },
      ),
    );
  }

  Widget _buildLoadMore(BuildContext context) {
    final vm = _viewModel;
    final visualTheme = AppVisualTheme.of(context);
    return TvFocusableSurface(
      key: const ValueKey<String>('bili-tv-favorites-load-more'),
      debugLabel: 'tv_favorites_load_more',
      autofocus: false,
      borderRadius: AppVisualTokens.contentRadius,
      focusArea: TvFocusArea.content,
      onTap: vm.isLoadingMore.value ? () {} : () => unawaited(vm.loadMore()),
      builder: (context, focused) => DecoratedBox(
        decoration: BoxDecoration(
          color: visualTheme.surface.withValues(alpha: focused ? 0.9 : 0.6),
          borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
          border: Border.all(
            color: focused
                ? AppVisualTokens.primaryBlue
                : visualTheme.glassBorder,
          ),
        ),
        child: Center(
          child: vm.isLoadingMore.value
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  vm.loadMoreErrorMessage.value == null ? '加载更多' : '重试加载',
                  style: TextStyle(
                    color: focused
                        ? AppVisualTokens.primaryBlue
                        : visualTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildContentStatus(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) {
    final visualTheme = AppVisualTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: visualTheme.textTertiary),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: visualTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TvFavoritesRailFolder extends StatelessWidget {
  const _TvFavoritesRailFolder({
    super.key,
    required this.folder,
    required this.selected,
    required this.collapsed,
    required this.autofocus,
    required this.onFocused,
    required this.onTap,
  });

  final BiliFavoriteFolder folder;
  final bool selected;
  final bool collapsed;
  final bool autofocus;
  final VoidCallback onFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final countLabel = folder.mediaCount == null ? '' : '${folder.mediaCount}';
    return SizedBox(
      height: collapsed ? 60 : 52,
      child: TvFocusableSurface(
        autofocus: autofocus,
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.035,
        borderRadius: AppVisualTokens.contentRadius,
        focusArea: TvFocusArea.rail,
        debugLabel: 'tv_favorites_folder_${folder.id}',
        onFocusChange: (focused) {
          if (focused) onFocused();
        },
        onTap: onTap,
        builder: (context, focused) {
          final foreground = selected
              ? AppVisualTokens.primaryBlue
              : visualTheme.textPrimary;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 6 : 12),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  selected ? Icons.folder_rounded : Icons.folder_outlined,
                  size: 20,
                  color: selected ? AppVisualTokens.primaryBlue : foreground,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      folder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: focused ? Colors.white : foreground,
                        fontSize: 13,
                        fontWeight: selected || focused
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (countLabel.isNotEmpty)
                    Text(
                      countLabel,
                      style: TextStyle(
                        color: visualTheme.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TvFavoritesRailAction extends StatelessWidget {
  const _TvFavoritesRailAction({
    super.key,
    required this.icon,
    required this.label,
    required this.collapsed,
    this.autofocus = false,
    required this.enabled,
    required this.onFocused,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final bool autofocus;
  final bool enabled;
  final VoidCallback onFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      height: collapsed ? 60 : 52,
      child: TvFocusableSurface(
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.035,
        borderRadius: AppVisualTokens.contentRadius,
        focusArea: TvFocusArea.rail,
        debugLabel: 'tv_favorites_rail_$label',
        autofocus: autofocus,
        onFocusChange: (focused) {
          if (focused) onFocused();
        },
        onTap: enabled ? onTap : () {},
        builder: (context, focused) => Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 6 : 12),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: focused
                      ? AppVisualTokens.primaryBlue
                      : visualTheme.textSecondary,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: focused
                            ? AppVisualTokens.primaryBlue
                            : visualTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _tvFavoritesCoverCacheWidth(BuildContext context) {
  final ratio = MediaQuery.devicePixelRatioOf(context);
  return (260 * ratio).round().clamp(240, 640).toInt();
}
