part of 'bili_tv_home_page.dart';

extension _BiliTvHomeController on _BiliTvHomePageState {
  Future<void> _enterTvHomePresentation() async {
    await _applySystemPresentation(
      orientations: biliLandscapeOrientations,
      systemUiMode: SystemUiMode.immersiveSticky,
      overlayStyle: biliTvSystemUiStyle,
    );
  }

  Future<void> _restoreAppPresentation() async {
    await _applySystemPresentation(
      useAppOrientationPolicy: true,
      systemUiMode: SystemUiMode.edgeToEdge,
      overlayStyle: biliAppSystemUiStyle,
    );
  }

  Future<void> _applyPresentationFor(BiliUiMode mode) {
    return mode == BiliUiMode.tv
        ? _enterTvHomePresentation()
        : _restoreAppPresentation();
  }

  Future<void> _applySystemPresentation({
    List<DeviceOrientation>? orientations,
    bool useAppOrientationPolicy = false,
    required SystemUiMode systemUiMode,
    required SystemUiOverlayStyle overlayStyle,
  }) async {
    assert(useAppOrientationPolicy != (orientations != null));
    final generation = ++_presentationGeneration;
    if (useAppOrientationPolicy) {
      await setBiliAppPreferredOrientations();
    } else {
      await setBiliPreferredOrientations(orientations!);
    }
    if (generation != _presentationGeneration) {
      return;
    }
    await setBiliSystemUiMode(systemUiMode);
    if (generation != _presentationGeneration) {
      return;
    }
    setBiliSystemUiOverlayStyle(overlayStyle);
  }

  Future<void> _bootstrap() async {
    await _viewModel.bootstrap();
    await _loadHistory();
    final forceTvMode = await _appSettings.getForceTvMode();
    _forceTvMode = forceTvMode;
    _initialForceTvMode = forceTvMode;
    if (mounted) {
      _mutate(() {});
    }
  }

  Future<void> _loadAppVersion() async {
    final version = await AppVersion.load();
    if (!mounted || version.isEmpty || version == _appVersion) {
      return;
    }
    _mutate(() {
      _appVersion = version;
    });
  }

  Future<void> _loadHistory() async {
    final local = await (_viewModel.historyStore).loadEntries();
    var merged = local;
    final shouldLoadRemote =
        _viewModel.client.hasAuthenticatedSession ||
        _viewModel.profile.value.isLoggedIn;
    if (shouldLoadRemote) {
      try {
        final remote = await _viewModel.client.fetchRemoteHistory(pageSize: 30);
        final seen = <String>{};
        final cloud = remote
            .where(
              (entry) =>
                  entry.bvid.trim().isNotEmpty ||
                  entry.aid > 0 ||
                  entry.episodeId > 0,
            )
            .map(
              (entry) => BiliPlaybackHistoryEntry(
                bvid: entry.bvid,
                aid: entry.aid,
                cid: entry.cid,
                episodeId: entry.episodeId,
                business: entry.business,
                videoTitle: entry.title,
                pageTitle: entry.pageTitle,
                coverUrl: entry.coverUrl,
                ownerName: entry.ownerName,
                playedAtMs: entry.viewedAtMs,
                lastPositionMs: entry.progressMs,
                durationMs: entry.durationMs > 0 ? entry.durationMs : null,
              ),
            )
            .where((entry) => seen.add(_historyIdentity(entry)))
            .toList(growable: false);
        if (cloud.isNotEmpty) {
          merged = <BiliPlaybackHistoryEntry>[
            ...cloud,
            ...local.where((entry) => !seen.contains(_historyIdentity(entry))),
          ];
        }
      } catch (_) {
        // The local store is the offline fallback when the cursor endpoint
        // is unavailable or the session has expired.
      }
    }
    if (!mounted) {
      return;
    }
    final preferredHero = !_heroHasUserSelection && merged.isNotEmpty
        ? _TvHeroItem.history(merged.first)
        : null;
    _mutate(() {
      _history = merged;
      if (preferredHero != null) {
        _heroItem = preferredHero;
      }
    });
    if (preferredHero != null) {
      _precacheHeroCover(preferredHero);
    }
  }

  void _handleFocusAreaChanged(TvFocusArea? area) {
    if (!mounted) {
      return;
    }
    final previousArea = _activeFocusArea;
    if (previousArea == area) {
      return;
    }
    _mutate(() {
      _activeFocusArea = area;
      if (area == TvFocusArea.homeRail && previousArea != null) {
        _homeRailExpanded = true;
      } else if (area == TvFocusArea.rail ||
          area == TvFocusArea.content ||
          area == TvFocusArea.recommendGrid ||
          area == TvFocusArea.regionCategories ||
          area == TvFocusArea.regionGrid) {
        _homeRailExpanded = false;
      }
    });
  }

  void _handleRailItemFocus(_TvNavItem item, bool focused) {
    if (!focused || _homeRailExpanded) {
      return;
    }
    _mutate(() => _homeRailExpanded = true);
  }

  void _ensureInitialHero(List<BiliFeedVideo> feedItems) {
    if (_heroItem != null || feedItems.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _heroItem != null) {
        return;
      }
      final item = _history.isNotEmpty
          ? _TvHeroItem.history(_history.first)
          : _TvHeroItem.feed(feedItems.first);
      _mutate(() => _heroItem = item);
      _precacheHeroCover(item);
    });
  }

  void _scheduleHeroUpdate(_TvHeroItem item, bool focused) {
    if (!focused || _heroItem?.identity == item.identity) {
      return;
    }
    _heroUpdateTimer?.cancel();
    final delay = AppVisualTokens.motionDuration(context, _tvHeroFocusDelay);
    if (delay == Duration.zero) {
      _applyFocusedHero(item);
      return;
    }
    _heroUpdateTimer = Timer(delay, () => _applyFocusedHero(item));
  }

  void _applyFocusedHero(_TvHeroItem item) {
    if (!mounted || _heroItem?.identity == item.identity) {
      return;
    }
    _precacheHeroCover(item);
    _mutate(() {
      _heroItem = item;
      _heroHasUserSelection = true;
    });
  }

  void _precacheHeroCover(_TvHeroItem item) {
    if (!mounted || item.coverUrl.isEmpty) {
      return;
    }
    unawaited(
      precacheImage(NetworkImage(item.coverUrl), context, onError: (_, _) {}),
    );
  }

  bool _handleHistoryShelfDirectionalEdge(TraversalDirection direction) {
    if (direction != TraversalDirection.up ||
        _heroPlayFocusNode.context == null ||
        !_heroPlayFocusNode.canRequestFocus) {
      return false;
    }
    if (_contentScrollController.hasClients) {
      final position = _contentScrollController.position;
      if (position.pixels != position.minScrollExtent) {
        _contentScrollController.jumpTo(position.minScrollExtent);
      }
    }
    _heroPlayFocusNode.requestFocus();
    return true;
  }

  Future<void> _playHero(_TvHeroItem item) async {
    final regionItem = item.regionItem;
    if (regionItem != null) {
      await _openRegionVideo(regionItem);
      return;
    }
    await _openPlayback(
      item.bvid,
      aid: item.aid > 0 ? item.aid : null,
      cid: item.cid > 0 ? item.cid : null,
      episodeId: item.episodeId > 0 ? item.episodeId : null,
      initialPositionMs: item.initialPositionMs,
    );
  }

  Future<void> _openHeroDetails(_TvHeroItem item) async {
    late final BiliVideoDetail detail;
    try {
      final regionItem = item.regionItem;
      if (regionItem?.seasonId case final seasonId?) {
        detail = await _viewModel.client.fetchPgcSeasonFirstEpisodeDetail(
          seasonId,
        );
      } else if (regionItem != null) {
        if (item.bvid.isEmpty) {
          throw const BiliHubException('无法识别该视频。');
        }
        detail = await _viewModel.client.fetchVideoDetail(item.bvid);
      } else {
        final target = await _viewModel.resolvePlaybackTarget(
          item.bvid,
          aid: item.aid > 0 ? item.aid : null,
          cid: item.cid > 0 ? item.cid : null,
          episodeId: item.episodeId > 0 ? item.episodeId : null,
        );
        detail = target.detail;
      }
    } catch (error) {
      if (mounted) {
        _showMessage('加载详情失败：${biliErrorMessage(error)}');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final shouldPlay = await showBiliTvGlassDialog<bool>(
      context: context,
      maxWidth: 690,
      title: detail.title,
      message: detail.description.isEmpty
          ? '${detail.ownerName} · ${detail.playCountLabel} 播放'
          : detail.description,
      icon: Icons.info_outline_rounded,
      actions: const [
        BiliTvDialogAction(
          label: '返回',
          value: false,
          icon: Icons.arrow_back_rounded,
          autofocus: true,
        ),
        BiliTvDialogAction(
          label: '开始播放',
          value: true,
          icon: Icons.play_arrow_rounded,
        ),
      ],
    );
    if (shouldPlay == true && mounted) {
      await _playHero(item);
    }
  }

  String _historyIdentity(BiliPlaybackHistoryEntry entry) {
    if (entry.episodeId > 0) {
      return 'episode:${entry.episodeId}';
    }
    if (entry.cid > 0) {
      return 'cid:${entry.cid}';
    }
    if (entry.bvid.isNotEmpty) {
      return 'bvid:${entry.bvid}';
    }
    return 'aid:${entry.aid}';
  }

  Future<void> _openLibrary(BiliLibrarySection section) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliLibraryPage(
          client: _viewModel.client,
          initialSection: section,
          historyStore: _viewModel.historyStore,
          offlineController: _viewModel.offlineController,
          onLoginTap: _openQrLogin,
          presentationMode: BiliPlaybackPresentationMode.tv,
        ),
      ),
    );
    if (mounted) {
      await _loadHistory();
    }
  }

  Future<void> _openPlayback(
    String bvid, {
    int? aid,
    int? cid,
    int? episodeId,
    int initialPositionMs = 0,
  }) async {
    late final BiliHubPlaybackTarget target;
    try {
      target = await _viewModel.resolvePlaybackTarget(
        bvid,
        aid: aid,
        cid: cid,
        episodeId: episodeId,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('打开视频失败：${biliErrorMessage(error)}');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliPlaybackPage(
          detail: target.detail,
          initialPage: target.initialPage,
          client: _viewModel.client,
          historyStore: _viewModel.historyStore,
          offlineController: _viewModel.offlineController,
          initialPositionMs: initialPositionMs,
          presentationMode: BiliPlaybackPresentationMode.tv,
        ),
      ),
    );
    unawaited(_loadHistory());
  }

  Future<void> _openRegionVideo(BiliRegionVideo item) async {
    late final BiliVideoDetail detail;
    try {
      final seasonId = item.seasonId;
      if (seasonId != null) {
        detail = await _viewModel.client.fetchPgcSeasonFirstEpisodeDetail(
          seasonId,
        );
      } else {
        final bvid = item.bvid;
        if (bvid == null || bvid.isEmpty) {
          throw const BiliHubException('无法识别该视频。');
        }
        detail = await _viewModel.client.fetchVideoDetail(bvid);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('打开视频失败：${biliErrorMessage(error)}');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (detail.pages.isEmpty) {
      _showMessage('这个内容没有可播放剧集。');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiliPlaybackPage(
          detail: detail,
          initialPage: detail.pages.first,
          client: _viewModel.client,
          historyStore: _viewModel.historyStore,
          offlineController: _viewModel.offlineController,
          presentationMode: BiliPlaybackPresentationMode.tv,
        ),
      ),
    );
    unawaited(_loadHistory());
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearMessages() {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.removeCurrentSnackBar();
  }

  Future<void> _runSearch() async {
    final bvid = biliExtractBvid(_searchController.text.trim());
    if (bvid != null) {
      await _openPlayback(bvid);
      return;
    }
    await _viewModel.runSearch();
  }

  void _requestMoreFeed() {
    if (_selectedNav != _TvNavItem.recommend ||
        _feedLoadMoreQueued ||
        _viewModel.isRefreshingFeed.value ||
        _viewModel.isLoadingMoreFeed.value ||
        !_viewModel.hasMoreFeed.value) {
      return;
    }
    _feedLoadMoreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _feedLoadMoreQueued = false;
      if (!mounted) {
        return;
      }
      unawaited(
        _viewModel.loadMoreFeed().then((message) {
          if (message != null && mounted) {
            _showMessage(message);
          }
        }),
      );
    });
  }

  Future<void> _loadRegion({BiliRegionSection? section}) async {
    if (!_viewModel.profile.value.isLoggedIn &&
        !_viewModel.client.hasAuthenticatedSession) {
      _showMessage('分区内容需要登录后才能观看。');
      return;
    }
    final nextSection = section ?? _selectedRegion;
    _mutate(() {
      _selectedRegion = nextSection;
      _regionLoading = true;
      _regionErrorMessage = null;
      _hasMoreRegion = true;
    });
    try {
      final items = await _viewModel.client.fetchRegionVideos(
        nextSection,
        page: 1,
      );
      if (!mounted) {
        return;
      }
      _mutate(() {
        _regionItems = items;
        _regionPage = 1;
        _hasMoreRegion =
            nextSection.apiType == BiliRegionApiType.pgc && items.length >= 20;
        _regionLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _mutate(() {
        _regionErrorMessage = error is BiliApiException && error.code == -101
            ? '登录状态已失效，请重新登录后查看分区内容。'
            : biliErrorMessage(error);
        _regionLoading = false;
      });
      if (error is BiliApiException && error.code == -101) {
        _showMessage('登录状态已失效，请重新登录。');
      }
    }
  }

  void _requestMoreRegion() {
    if (_selectedNav != _TvNavItem.regions ||
        _regionLoadMoreQueued ||
        _regionLoading ||
        _regionLoadingMore ||
        !_hasMoreRegion) {
      return;
    }
    _regionLoadMoreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _regionLoadMoreQueued = false;
      if (!mounted) {
        return;
      }
      unawaited(_loadMoreRegion());
    });
  }

  Future<void> _loadMoreRegion() async {
    if (_regionLoading || _regionLoadingMore || !_hasMoreRegion) {
      return;
    }
    _mutate(() {
      _regionLoadingMore = true;
    });
    try {
      final nextPage = _regionPage + 1;
      final items = await _viewModel.client.fetchRegionVideos(
        _selectedRegion,
        page: nextPage,
      );
      if (!mounted) {
        return;
      }
      final existingIds = _regionItems.map((item) => item.id).toSet();
      final nextItems = items
          .where((item) => existingIds.add(item.id))
          .toList(growable: false);
      _mutate(() {
        _regionItems = <BiliRegionVideo>[..._regionItems, ...nextItems];
        _regionPage = nextPage;
        _hasMoreRegion = items.length >= 20 && nextItems.isNotEmpty;
        _regionLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _mutate(() {
        _regionLoadingMore = false;
      });
      _showMessage('加载更多分区内容失败：${biliErrorMessage(error)}');
    }
  }

  Future<void> _toggleForceTvMode(bool value) async {
    _mutate(() {
      _forceTvMode = value;
    });
    _clearMessages();
    if (value != _initialForceTvMode) {
      _showMessage('显示模式已修改，点击下方按钮返回首页切换。');
    }
    try {
      await _appSettings.setForceTvMode(value);
    } catch (error) {
      if (mounted) {
        _showMessage('保存显示模式失败：${biliErrorMessage(error)}');
      }
    }
  }
}
