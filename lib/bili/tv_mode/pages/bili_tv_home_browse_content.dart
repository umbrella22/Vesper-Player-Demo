part of 'bili_tv_home_page.dart';

extension _BiliTvHomeBrowseContent on _BiliTvHomePageState {
  Widget _buildRegionsPage() {
    if (_regionItems.isEmpty &&
        !_regionLoading &&
        _regionErrorMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedNav == _TvNavItem.regions) {
          unawaited(_loadRegion());
        }
      });
    }

    return Column(
      children: [
        SizedBox(
          height: 50,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            scrollDirection: Axis.horizontal,
            itemCount: biliRegionSections.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final section = biliRegionSections[index];
              final selected = _selectedRegion.id == section.id;
              return _TvRegionPill(
                key: ValueKey<String>('bili-tv-region-${section.id}'),
                section: section,
                selected: selected,
                onTap: () => unawaited(_loadRegion(section: section)),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildRegionContentGrid()),
      ],
    );
  }

  Widget _buildRegionContentGrid() {
    if (_regionLoading && _regionItems.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0x88FFFFFF)),
      );
    }
    final error = _regionErrorMessage;
    if (error != null && _regionItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Color(0x66FFFFFF),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                error,
                style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TvGlassSelectable(
                borderRadius: 12,
                onTap: () => unawaited(_loadRegion()),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                builder: (context, state) => const Text(
                  '重新加载',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_regionItems.isEmpty) {
      return const Center(
        child: Text(
          '暂无内容',
          style: TextStyle(color: Color(0x88FFFFFF), fontSize: 16),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 720) {
          _requestMoreRegion();
        }
        return false;
      },
      child: _TvGridOverlayScope(
        child: CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                28,
                _tvGridFocusInset,
                28,
                _tvGridFocusInset,
              ),
              sliver: _TvRegionVideoGrid(
                items: _regionItems,
                onTapItem: _openRegionVideo,
                onFocusItem: (item, focused) =>
                    _scheduleHeroUpdate(_TvHeroItem.region(item), focused),
                onNearEnd: _requestMoreRegion,
              ),
            ),
            if (_regionLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0x88FFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPage() {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(28, 0, 28, keyboardBottom),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: GlassContainer(
              useOwnLayer: true,
              quality: TvGlassQualityScope.of(context),
              shape: const LiquidRoundedSuperellipse(
                borderRadius: AppVisualTokens.controlRadius,
              ),
              settings: const LiquidGlassSettings(
                blur: 8,
                thickness: 18,
                glassColor: Color(0x18409EFF),
              ),
              child: SignalBuilder(
                builder: (context) {
                  return TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: '搜索视频、BV 号或链接',
                      hintStyle: const TextStyle(
                        color: Color(0x66FFFFFF),
                        fontWeight: FontWeight.w400,
                      ),
                      filled: true,
                      fillColor: Colors.transparent,
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xAA409EFF),
                        size: 22,
                      ),
                      suffixIcon: _TvSearchSuffixIcon(
                        loading: _viewModel.isSearching.value,
                        visible: _searchController.text.isNotEmpty,
                        onClear: () {
                          _searchController.clear();
                          _viewModel.clearSearch();
                        },
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: (_) {
                      _mutate(() {});
                      _viewModel.updateQuery(_searchController.text);
                    },
                    onSubmitted: (_) => _runSearch(),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SignalBuilder(
              builder: (context) {
                final results = _viewModel.results.value;
                if (_viewModel.isSearching.value && results.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0x88FFFFFF)),
                  );
                }
                final searchErrorMessage = _viewModel.searchErrorMessage.value;
                if (searchErrorMessage != null && results.isEmpty) {
                  return Center(
                    child: Text(
                      searchErrorMessage,
                      style: const TextStyle(
                        color: Color(0x88FFFFFF),
                        fontSize: 15,
                      ),
                    ),
                  );
                }
                if (_viewModel.activeSearchKeyword.value != null &&
                    results.isEmpty) {
                  return const Center(
                    child: Text(
                      '没有搜到内容',
                      style: TextStyle(color: Color(0x88FFFFFF), fontSize: 16),
                    ),
                  );
                }
                return _TvGridOverlayScope(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final gridCrossAxisExtent =
                          constraints.maxWidth - _tvGridFocusInset * 2;
                      final maxCrossAxisExtent =
                          biliTvGridMaxCrossAxisExtentForWidth(
                            gridCrossAxisExtent,
                          );
                      final coverCacheWidth = biliTvCoverCacheWidth(
                        tileWidth: _tvCoverDecodeLogicalWidth,
                        devicePixelRatio: MediaQuery.devicePixelRatioOf(
                          context,
                        ),
                      );
                      return GridView.builder(
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.fromLTRB(
                          _tvGridFocusInset,
                          _tvGridFocusInset,
                          _tvGridFocusInset,
                          _tvGridFocusInset,
                        ),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: maxCrossAxisExtent,
                          mainAxisSpacing: _tvGridMainAxisSpacing,
                          crossAxisSpacing: _tvGridCrossAxisSpacing,
                          childAspectRatio: _tvGridChildAspectRatio,
                        ),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final result = results[index];
                          return _TvSearchResultCard(
                            coverUrl: result.coverUrl,
                            coverCacheWidth: coverCacheWidth,
                            title: result.title,
                            author: result.author,
                            duration: result.durationLabel,
                            playCount: result.playCountLabel,
                            onFocusChange: (focused) => _scheduleHeroUpdate(
                              _TvHeroItem.search(result),
                              focused,
                            ),
                            onTap: () => _openPlayback(result.bvid),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchFocusNode.hasFocus) {
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
        );
      }
    });
  }

  Widget _buildHistoryPage() {
    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_rounded,
                color: const Color(0x66FFFFFF),
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                '还没有播放历史',
                style: TextStyle(color: Color(0x88FFFFFF), fontSize: 16),
              ),
              const SizedBox(height: 16),
              TvFocusable(
                onTap: () {
                  _mutate(() {
                    _selectedNav = _TvNavItem.recommend;
                    _lastPrimaryNav = _TvNavItem.recommend;
                  });
                  if (_viewModel.feedItems.value.isEmpty &&
                      !_viewModel.isRefreshingFeed.value) {
                    unawaited(_viewModel.loadFeed());
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '去看看推荐',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _TvGridOverlayScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gridCrossAxisExtent =
              constraints.maxWidth - _tvGridFocusInset * 2;
          final maxCrossAxisExtent = biliTvGridMaxCrossAxisExtentForWidth(
            gridCrossAxisExtent,
          );
          final coverCacheWidth = biliTvCoverCacheWidth(
            tileWidth: _tvCoverDecodeLogicalWidth,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          );
          return GridView.builder(
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(
              28,
              _tvGridFocusInset,
              28,
              _tvGridFocusInset,
            ),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxCrossAxisExtent,
              mainAxisSpacing: _tvGridMainAxisSpacing,
              crossAxisSpacing: _tvGridCrossAxisSpacing,
              childAspectRatio: _tvGridChildAspectRatio,
            ),
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final entry = _history[index];
              final progress = entry.durationMs != null && entry.durationMs! > 0
                  ? entry.lastPositionMs / entry.durationMs!
                  : 0.0;
              return _TvHistoryCard(
                coverUrl: entry.coverUrl,
                coverCacheWidth: coverCacheWidth,
                title: entry.videoTitle,
                subtitle: entry.pageTitle,
                ownerName: entry.ownerName,
                progress: progress,
                onFocusChange: (focused) =>
                    _scheduleHeroUpdate(_TvHeroItem.history(entry), focused),
                onTap: () => _openPlayback(
                  entry.bvid,
                  aid: entry.aid,
                  cid: entry.cid > 0 ? entry.cid : null,
                  episodeId: entry.episodeId > 0 ? entry.episodeId : null,
                  initialPositionMs: entry.lastPositionMs,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
