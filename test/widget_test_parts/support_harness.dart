part of '../widget_test.dart';

final class _PlaybackHarness {
  _PlaybackHarness({
    required this.client,
    required this.platform,
    required this.historyStore,
  });

  final _FakePlaybackClient client;
  final _FakePlaybackVesperPlatform platform;
  final BiliHistoryStore historyStore;
}

final class _ExternalPlaybackHarness {
  _ExternalPlaybackHarness({
    this.loadResult = const <String, Object?>{
      'status': 'success',
      'routeId': 'uuid:tv',
      'relayEnabled': true,
    },
  });

  static const channel = MethodChannel(
    'io.github.ikaros.vesper_player_external_playback',
  );
  static const routesChannel = EventChannel(
    'io.github.ikaros.vesper_player_external_playback/routes',
  );
  static const eventsChannel = EventChannel(
    'io.github.ikaros.vesper_player_external_playback/events',
  );

  final Map<String, Object?> loadResult;
  final calls = <MethodCall>[];
  late dynamic _routesSink;
  late dynamic _eventsSink;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'startDiscovery':
            case 'stopDiscovery':
              return null;
            case 'connect':
              return <String, Object?>{
                'status': 'success',
                'routeId': 'uuid:tv',
              };
            case 'load':
              return loadResult;
            case 'disconnect':
              return <String, Object?>{'status': 'success'};
          }
          return <String, Object?>{
            'status': 'failed',
            'message': 'Unexpected method ${call.method}',
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          routesChannel,
          MockStreamHandler.inline(
            onListen: (_, events) {
              _routesSink = events;
            },
          ),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          eventsChannel,
          MockStreamHandler.inline(
            onListen: (_, events) {
              _eventsSink = events;
            },
          ),
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(routesChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventsChannel, null);
  }

  void emitDlnaRoute() {
    _routesSink.success(<Object?>[
      <String, Object?>{
        'routeId': 'uuid:tv',
        'name': 'Living Room TV',
        'kind': 'dlna',
      },
    ]);
  }

  void emitEvent(Object? event) {
    _eventsSink.success(event);
  }
}

final class _TvHomeHarness {
  const _TvHomeHarness({
    required this.client,
    required this.historyStore,
    required this.sessionStore,
    required this.offlineController,
    required this.appSettings,
  });

  final _FakeTvHomeClient client;
  final BiliHistoryStore historyStore;
  final BiliSessionStore sessionStore;
  final _FakeOfflineController offlineController;
  final AppSettingsStore appSettings;
}

Future<_PlaybackHarness> _pumpPlaybackPage(
  WidgetTester tester, {
  BiliVideoDetail? detail,
  BiliVideoPageEntry? initialPage,
  BiliPlaybackPresentationMode presentationMode =
      BiliPlaybackPresentationMode.phone,
  Size surfaceSize = const Size(1200, 900),
  VesperPlayerSnapshot? initialSnapshot,
  int initialPositionMs = 0,
  void Function(_FakePlaybackClient client)? configureClient,
  BiliResolvedPlayback? initialResolvedPlayback,
  ThemeData? theme,
  bool externalPlaybackMockInstalled = false,
}) async {
  final previousPlatform = VesperPlayerPlatform.instance;
  final platform = _FakePlaybackVesperPlatform(
    initialSnapshot: initialSnapshot ?? _playbackSnapshot,
  );
  VesperPlayerPlatform.instance = platform;
  addTearDown(() {
    VesperPlayerPlatform.instance = previousPlatform;
  });
  addTearDown(platform.closeEvents);
  const externalPlaybackEventsChannel = EventChannel(
    'io.github.ikaros.vesper_player_external_playback/events',
  );
  if (!externalPlaybackMockInstalled &&
      defaultTargetPlatform == TargetPlatform.android) {
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      externalPlaybackEventsChannel,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        externalPlaybackEventsChannel,
        null,
      );
    });
  }

  final playbackDetail = detail ?? _playbackDetail();
  final page = initialPage ?? playbackDetail.pages.first;
  final client = _FakePlaybackClient();
  configureClient?.call(client);
  final historyRoot = Directory(
    '${Directory.systemTemp.path}/bili-playback-widget-test-${DateTime.now().microsecondsSinceEpoch}',
  );
  final historyStore = BiliHistoryStore(baseDirectory: historyRoot);
  addTearDown(() async {
    if (await historyRoot.exists()) {
      await historyRoot.delete(recursive: true);
    }
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: BiliPlaybackPage(
        detail: playbackDetail,
        initialPage: page,
        client: client,
        historyStore: historyStore,
        initialResolvedPlayback:
            initialResolvedPlayback ??
            _resolvedPlaybackFor(playbackDetail, page),
        initialPositionMs: initialPositionMs,
        presentationMode: presentationMode,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await _flushRealAsync(tester);
  await tester.pump();

  return _PlaybackHarness(
    client: client,
    platform: platform,
    historyStore: historyStore,
  );
}

Future<_TvHomeHarness> _pumpTvHomePage(
  WidgetTester tester, {
  bool initialForceTvMode = false,
  Size surfaceSize = const Size(1280, 720),
  double viewInsetsBottom = 0,
  List<BiliFeedVideo>? initialFeedItems,
  List<BiliPlaybackHistoryEntry> initialHistoryEntries =
      const <BiliPlaybackHistoryEntry>[],
  bool skipBootstrap = false,
  bool loggedIn = false,
  bool authenticatedSession = false,
  bool emptyFollowing = false,
}) async {
  final root = Directory(
    '${Directory.systemTemp.path}/bili-tv-home-widget-test-${DateTime.now().microsecondsSinceEpoch}',
  );
  final settings = AppSettingsStore(baseDirectory: root);
  await tester.runAsync(() => settings.setForceTvMode(initialForceTvMode));

  final harness = _TvHomeHarness(
    client: _FakeTvHomeClient(emptyFollowing: emptyFollowing),
    historyStore: BiliHistoryStore(
      baseDirectory: Directory('${root.path}/history'),
    ),
    sessionStore: BiliSessionStore(
      baseDirectory: Directory('${root.path}/session'),
    ),
    offlineController: _FakeOfflineController(<BiliOfflineDownloadEntry>[]),
    appSettings: settings,
  );
  harness.client.loggedIn = loggedIn;
  if (authenticatedSession) {
    harness.client.restoreCookies(const <String, String>{
      'SESSDATA': 'sess',
      'bili_jct': 'csrf',
      'DedeUserID': '42',
      'buvid3': 'b3',
      'buvid4': 'b4',
    });
  }

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
  });

  await _pumpTvHomeFrame(
    tester,
    harness,
    surfaceSize: surfaceSize,
    viewInsetsBottom: viewInsetsBottom,
    initialFeedItems: initialFeedItems,
    initialHistoryEntries: initialHistoryEntries,
    skipBootstrap: skipBootstrap,
  );
  await _flushRealAsync(tester);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return harness;
}

Future<void> _flushRealAsync(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (predicate()) {
      return;
    }
  }
}

Future<void> _pumpTvHomeFrame(
  WidgetTester tester,
  _TvHomeHarness harness, {
  required Size surfaceSize,
  double viewInsetsBottom = 0,
  List<BiliFeedVideo>? initialFeedItems,
  List<BiliPlaybackHistoryEntry> initialHistoryEntries =
      const <BiliPlaybackHistoryEntry>[],
  bool skipBootstrap = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: surfaceSize,
          viewInsets: EdgeInsets.only(bottom: viewInsetsBottom),
        ),
        child: BiliTvHomePage(
          key: const ValueKey<String>('bili-tv-home-test-page'),
          client: harness.client,
          historyStore: harness.historyStore,
          sessionStore: harness.sessionStore,
          offlineController: harness.offlineController,
          appSettings: harness.appSettings,
          initialFeedItems: initialFeedItems ?? const <BiliFeedVideo>[],
          initialHistoryEntries: initialHistoryEntries,
          skipBootstrap: skipBootstrap,
        ),
      ),
    ),
  );
}

BiliOfflineDownloadEntry _offlineEntry({
  required String assetId,
  required int taskId,
  required String title,
  required VesperDownloadState state,
  int createdAtMs = 100,
}) {
  return BiliOfflineDownloadEntry(
    metadata: BiliOfflineDownloadMetadata(
      assetId: assetId,
      taskId: taskId,
      bvid: 'BV$taskId',
      cid: taskId,
      videoTitle: title,
      pageTitle: 'P$taskId · 正片',
      coverUrl: '',
      qualityLabel: '1080P',
      createdAtMs: createdAtMs,
    ),
    task: VesperDownloadTaskSnapshot(
      taskId: taskId,
      assetId: assetId,
      source: VesperDownloadSource(
        source: VesperPlayerSource(
          uri: 'vesper-generated://dash/$taskId/manifest.mpd',
          label: title,
          kind: VesperPlayerSourceKind.local,
          protocol: VesperPlayerSourceProtocol.dash,
        ),
        contentFormat: VesperDownloadContentFormat.dashSegments,
      ),
      profile: const VesperDownloadProfile(
        targetOutputFormat: VesperDownloadOutputFormat.mp4,
      ),
      state: state,
      progress: const VesperDownloadProgressSnapshot(
        receivedBytes: 512,
        totalBytes: 1024,
      ),
      assetIndex: const VesperDownloadAssetIndex(
        contentFormat: VesperDownloadContentFormat.dashSegments,
      ),
    ),
  );
}
