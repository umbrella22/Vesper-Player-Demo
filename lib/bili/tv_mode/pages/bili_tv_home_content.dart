part of 'bili_tv_home_page.dart';

extension _BiliTvHomeContent on _BiliTvHomePageState {
  Widget _buildPrimaryContentArea(_TvNavItem item) {
    if (item == _TvNavItem.recommend) {
      return _buildRecommendPage();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Text(
            item.label(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: switch (item) {
            _TvNavItem.recommend => const SizedBox.shrink(),
            _TvNavItem.following => const SizedBox.shrink(),
            _TvNavItem.regions => _buildRegionsPage(),
            _TvNavItem.search => _buildSearchPage(),
            _TvNavItem.history => _buildHistoryPage(),
            _TvNavItem.mine => _buildMinePage(),
            _TvNavItem.settings => _buildSettingsPage(),
          },
        ),
      ],
    );
  }

  Future<void> _handleNavTap(_TvNavItem item) async {
    final hasSession =
        _viewModel.profile.value.isLoggedIn ||
        _viewModel.client.hasAuthenticatedSession;
    if (item == _TvNavItem.regions && !hasSession) {
      final shouldLogin = await _confirmRegionLogin();
      if (!mounted || shouldLogin != true) {
        return;
      }
      await _openQrLogin();
      if (!mounted ||
          (!_viewModel.profile.value.isLoggedIn &&
              !_viewModel.client.hasAuthenticatedSession)) {
        return;
      }
    }

    if (!mounted) {
      return;
    }
    _mutate(() {
      _selectedNav = item;
      if (item == _TvNavItem.following) {
        _followingPaneActivated = true;
      } else {
        _lastPrimaryNav = item;
      }
    });
    if (item == _TvNavItem.history) {
      unawaited(_loadHistory());
    }
    if (item == _TvNavItem.recommend &&
        _viewModel.feedItems.value.isEmpty &&
        !_viewModel.isRefreshingFeed.value) {
      unawaited(_viewModel.loadFeed());
    }
    if (item == _TvNavItem.regions && _regionItems.isEmpty) {
      unawaited(_loadRegion());
    }
  }

  Widget _buildRecommendPage() {
    return SignalBuilder(
      builder: (context) {
        final items = _viewModel.feedItems.value;
        _ensureInitialHero(items);
        if (_viewModel.isBootstrapping.value) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0x88FFFFFF)),
          );
        }
        final feedErrorMessage = _viewModel.feedErrorMessage.value;
        if (feedErrorMessage != null && items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    color: const Color(0x66FFFFFF),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    feedErrorMessage,
                    style: const TextStyle(
                      color: Color(0x88FFFFFF),
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TvGlassSelectable(
                    borderRadius: 12,
                    onTap: () => _viewModel.loadFeed(),
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
        if (items.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0x88FFFFFF)),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final heroHeight = (constraints.maxHeight * 0.48)
                .clamp(280.0, 480.0)
                .toDouble();
            final historyCardWidth = (constraints.maxWidth * 0.19)
                .clamp(220.0, 310.0)
                .toDouble();
            final compactHero = constraints.maxWidth < 840 || heroHeight < 340;
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical &&
                    notification.metrics.extentAfter < 720) {
                  _requestMoreFeed();
                }
                return false;
              },
              child: _TvGridOverlayScope(
                child: CustomScrollView(
                  key: const ValueKey<String>('bili-tv-recommend-scroll'),
                  controller: _contentScrollController,
                  clipBehavior: Clip.hardEdge,
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: heroHeight,
                        child: _buildHeroPanel(
                          _heroItem ?? _TvHeroItem.feed(items.first),
                          compact: compactHero,
                        ),
                      ),
                    ),
                    if (_history.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _buildHistoryShelf(
                          entries: _history.take(20).toList(growable: false),
                          cardWidth: historyCardWidth,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          _history.isEmpty ? 10 : 0,
                          28,
                          0,
                        ),
                        child: const Text(
                          '为你推荐',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                    _buildFeedGrid(items: items),
                    if (_viewModel.isLoadingMoreFeed.value)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 4, bottom: 28),
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
                      )
                    else
                      const SliverToBoxAdapter(child: SizedBox(height: 28)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeroPanel(_TvHeroItem item, {required bool compact}) {
    final title = biliStripHtmlTags(item.title);
    final metadata = <String>[
      if (item.author.isNotEmpty) item.author,
      if (item.durationLabel.isNotEmpty) item.durationLabel,
      if (item.playCountLabel.isNotEmpty) '${item.playCountLabel} 播放',
    ].join(' · ');
    final progress = item.progress;
    final progressLabel = item.durationMs == null
        ? null
        : '已观看 ${biliFormatDurationSeconds(item.initialPositionMs ~/ 1000)} / ${biliFormatDurationSeconds(item.durationMs! ~/ 1000)}';
    return Padding(
      padding: EdgeInsets.fromLTRB(0, compact ? 30 : 46, 36, 18),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 560 : 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppVisualTokens.primaryBlue,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    item.eyebrow,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 16),
              Text(
                title,
                key: const ValueKey<String>('bili-tv-hero-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 34 : 44,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 9),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xD9FFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (!compact && item.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  biliStripHtmlTags(item.description),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xA6FFFFFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
              if (progressLabel != null && progress > 0) ...[
                SizedBox(height: compact ? 10 : 14),
                Text(
                  progressLabel,
                  style: const TextStyle(
                    color: Color(0xA6FFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      key: const ValueKey<String>('bili-tv-hero-progress'),
                      value: progress,
                      minHeight: 4,
                      backgroundColor: const Color(0x3DFFFFFF),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppVisualTokens.primaryBlue,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(height: compact ? 14 : 20),
              TvFocusGroupScope(
                key: const ValueKey<String>('bili-tv-hero-actions'),
                group: const ValueKey<String>('tv-hero-actions-focus'),
                child: AdaptiveLiquidGlassLayer(
                  quality: TvGlassQualityScope.of(context),
                  settings: const LiquidGlassSettings(
                    blur: 8,
                    thickness: 16,
                    glassColor: Color(0x14FFFFFF),
                    lightIntensity: 0.6,
                  ),
                  child: Row(
                    children: [
                      _TvHeroAction(
                        label: item.source == _TvHeroSource.history
                            ? '继续播放'
                            : '开始播放',
                        icon: Icons.play_arrow_rounded,
                        primary: true,
                        focusNode: _heroPlayFocusNode,
                        debugLabel: 'tv_hero_play',
                        onTap: () => unawaited(_playHero(item)),
                      ),
                      const SizedBox(width: 12),
                      _TvHeroAction(
                        label: '详情',
                        icon: Icons.info_outline_rounded,
                        debugLabel: 'tv_hero_details',
                        onTap: () => unawaited(_openHeroDetails(item)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryShelf({
    required List<BiliPlaybackHistoryEntry> entries,
    required double cardWidth,
  }) {
    final coverCacheWidth = biliTvCoverCacheWidth(
      tileWidth: _tvCoverDecodeLogicalWidth,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return _TvMediaShelf(
      key: const ValueKey<String>('bili-tv-continue-shelf'),
      title: '继续观看',
      controller: _continueShelfController,
      itemCount: entries.length,
      cardWidth: cardWidth,
      onDirectionalEdge: _handleHistoryShelfDirectionalEdge,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final hero = _TvHeroItem.history(entry);
        return _TvHistoryCard(
          key: ValueKey<String>('history_${hero.identity}'),
          coverUrl: entry.coverUrl,
          coverCacheWidth: coverCacheWidth,
          title: entry.videoTitle,
          subtitle: entry.pageTitle,
          ownerName: entry.ownerName,
          progress: hero.progress,
          onFocusChange: (focused) => _scheduleHeroUpdate(hero, focused),
          onTap: () => unawaited(_playHero(hero)),
        );
      },
    );
  }

  Widget _buildFeedGrid({required List<BiliFeedVideo> items}) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final gridCrossAxisExtent =
            constraints.crossAxisExtent - _tvGridFocusInset * 2;
        final maxCrossAxisExtent = biliTvGridMaxCrossAxisExtentForWidth(
          gridCrossAxisExtent,
        );
        final coverCacheWidth = biliTvCoverCacheWidth(
          tileWidth: _tvCoverDecodeLogicalWidth,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        return SliverPadding(
          key: const ValueKey<String>('bili-tv-recommend-grid'),
          padding: const EdgeInsets.fromLTRB(
            _tvGridFocusInset,
            16,
            _tvGridFocusInset,
            _tvGridFocusInset,
          ),
          sliver: SliverGrid.builder(
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxCrossAxisExtent,
              mainAxisSpacing: _tvGridMainAxisSpacing,
              crossAxisSpacing: _tvGridCrossAxisSpacing,
              childAspectRatio: _tvGridChildAspectRatio,
            ),
            itemBuilder: (context, index) {
              if (index >= items.length - 8) {
                _requestMoreFeed();
              }
              final item = items[index];
              final hero = _TvHeroItem.feed(item);
              return _TvVideoCard(
                key: ValueKey<String>('feed_${item.bvid}'),
                coverUrl: item.coverUrl,
                coverCacheWidth: coverCacheWidth,
                title: item.title,
                author: item.author,
                duration: item.durationLabel,
                playCount: item.playCountLabel,
                focusArea: TvFocusArea.recommendGrid,
                onFocusChange: (focused) => _scheduleHeroUpdate(hero, focused),
                onTap: () => unawaited(_playHero(hero)),
              );
            },
          ),
        );
      },
    );
  }
}
