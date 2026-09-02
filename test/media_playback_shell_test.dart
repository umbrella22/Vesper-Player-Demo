import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/common/services/bili_quality_mapping.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_ui/vesper_player_ui.dart' as vesper_ui;

/// 播放壳组件级测试（计划 §6.3/§6.4）：fake adapter 驱动
/// MediaPlaybackPage，验证能力缺省渲染、互动动作槽、设备控制传递、
/// 历史回退与续播。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const target = MediaPlaybackTarget(
    detail: MediaDetail(
      mediaId: 'BV1SHELL',
      title: '壳测试视频',
      coverUrl: '',
      ownerName: '壳测试UP',
      replyCountLabel: '78',
      pages: <MediaPlaybackEntry>[
        MediaPlaybackEntry(
          entryId: '11',
          pageNumber: 1,
          title: 'P1',
          durationSeconds: 120,
        ),
      ],
    ),
    entry: MediaPlaybackEntry(
      entryId: '11',
      pageNumber: 1,
      title: 'P1',
      durationSeconds: 120,
    ),
  );

  /// 安装壳测试环境（fake 平台 + 通道 mock），返回 fake platform。
  /// 必须在 view model 构造前调用（构造会订阅平台事件流）。
  _ShellFakePlatform installEnvironment(
    WidgetTester tester, {
    VesperPlayerSnapshot? initialSnapshot,
  }) {
    final previousPlatform = VesperPlayerPlatform.instance;
    final fakePlatform = _ShellFakePlatform(initialSnapshot ?? _shellSnapshot);
    VesperPlayerPlatform.instance = fakePlatform;
    addTearDown(() {
      VesperPlayerPlatform.instance = previousPlatform;
    });
    addTearDown(fakePlatform.closeEvents);

    // 外部播放事件流（投屏会话）：测试环境无原生实现，静默接收。
    const externalPlaybackEventsChannel = EventChannel(
      'io.github.umbrella22.vesper_player_external_playback/events',
    );
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

    // 平台视图通道（VesperPlayerView 渲染）：返回伪视图 id。
    const platformViewsChannel = MethodChannel('flutter/platform_views');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      platformViewsChannel,
      (call) async {
        switch (call.method) {
          case 'create':
            return 1;
          case 'resize':
            final arguments = call.arguments as Map<Object?, Object?>;
            return <String, Object?>{
              'width': arguments['width'],
              'height': arguments['height'],
            };
          case 'dispose':
          case 'offset':
          case 'touch':
          case 'setDirection':
          case 'clearFocus':
            return null;
          default:
            return null;
        }
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        platformViewsChannel,
        null,
      );
    });

    return fakePlatform;
  }

  _ShellFakePlatform installViewModelEnvironment({
    VesperPlayerSnapshot? initialSnapshot,
  }) {
    final previousPlatform = VesperPlayerPlatform.instance;
    final fakePlatform = _ShellFakePlatform(initialSnapshot ?? _shellSnapshot);
    VesperPlayerPlatform.instance = fakePlatform;
    addTearDown(() {
      VesperPlayerPlatform.instance = previousPlatform;
    });
    addTearDown(fakePlatform.closeEvents);

    const externalPlaybackEventsChannel = EventChannel(
      'io.github.umbrella22.vesper_player_external_playback/events',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      externalPlaybackEventsChannel,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    addTearDown(() {
      messenger.setMockStreamHandler(externalPlaybackEventsChannel, null);
    });
    return fakePlatform;
  }

  Future<_ShellHarness> pumpShell(
    WidgetTester tester, {
    _ShellAdapter? adapter,
    MediaPlaybackTarget? playbackTarget,
    MediaPlaybackBinding binding = const MediaPlaybackBinding(),
    Size surfaceSize = const Size(1200, 900),
    MediaPlaybackPresentationMode presentationMode =
        MediaPlaybackPresentationMode.phone,
    MediaPlayerDeviceControls? deviceControls,
    MediaHistoryStore? historyStore,
    Widget? danmakuSettingsSurface,
    ValueListenable<MediaDanmakuOverlaySettings>? danmakuSettingsListenable,
    ValueChanged<MediaDanmakuOverlaySettings>? onDanmakuSettingsChanged,
    int initialPositionMs = 0,
    VesperPlayerSnapshot? initialSnapshot,
  }) async {
    final fakePlatform = installEnvironment(
      tester,
      initialSnapshot: initialSnapshot,
    );
    final resolvedAdapter = adapter ?? _ShellAdapter();
    final resolvedTarget = playbackTarget ?? target;
    final viewModel = MediaPlaybackViewModel(
      detail: resolvedTarget.detail,
      initialEntry: resolvedTarget.entry,
      adapter: resolvedAdapter,
      historyStore: historyStore,
      initialPositionMs: initialPositionMs,
    );
    addTearDown(viewModel.dispose);
    unawaited(
      viewModel.controllerFuture.then<void>((_) {}, onError: (Object _) {}),
    );

    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaPlaybackPage(
          viewModel: viewModel,
          presentationMode: presentationMode,
          binding: binding,
          deviceControls: deviceControls ?? const MediaNoopDeviceControls(),
          presentation: _shellPresentation,
          danmakuSettingsSurface: danmakuSettingsSurface,
          danmakuSettingsListenable: danmakuSettingsListenable,
          onDanmakuSettingsChanged: onDanmakuSettingsChanged,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    for (var round = 0; round < 3; round += 1) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
    }
    return _ShellHarness(viewModel: viewModel, platform: fakePlatform);
  }

  group('听视频 MVP', () {
    testWidgets('手机进入和返回保持同一播放会话，播放按钮复用原 controller', (tester) async {
      final harness = await pumpShell(
        tester,
        surfaceSize: const Size(390, 844),
      );
      final initialCreateCalls = harness.platform.createCalls;
      final initialPlayCalls = harness.platform.playCalls;

      await tester.tap(find.byKey(const ValueKey<String>('enter-listen-mode')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('listen-mode-container')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('listen-return-video')),
        findsOneWidget,
      );
      expect(find.byTooltip('退出听视频'), findsOneWidget);
      expect(find.byIcon(Icons.ondemand_video_rounded), findsNothing);
      expect(find.text('正在播放'), findsOneWidget);
      expect(harness.platform.createCalls, initialCreateCalls);
      expect(harness.platform.selectSourceCalls, 1);
      expect(
        harness.platform.selectedSources.single.uri,
        'https://example.test/11-audio.mpd',
      );
      expect(harness.platform.disposeCalls, 0);

      await tester.tap(find.byKey(const ValueKey<String>('listen-play-pause')));
      await tester.pump();
      expect(harness.platform.playCalls, initialPlayCalls + 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('listen-return-video')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('listen-mode-container')),
        findsNothing,
      );
      expect(find.byType(vesper_ui.VesperPlayerStage), findsOneWidget);
      expect(harness.platform.createCalls, initialCreateCalls);
      expect(harness.platform.selectSourceCalls, 2);
      expect(
        harness.platform.selectedSources.last.uri,
        'https://example.test/shell.mp4',
      );
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('手机系统返回先退出伴听且不销毁播放会话', (tester) async {
      final harness = await pumpShell(
        tester,
        surfaceSize: const Size(390, 844),
      );
      final initialCreateCalls = harness.platform.createCalls;

      await tester.tap(find.byKey(const ValueKey<String>('enter-listen-mode')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('listen-mode-container')),
        findsOneWidget,
      );

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('listen-mode-container')),
        findsNothing,
      );
      expect(find.byType(vesper_ui.VesperPlayerStage), findsOneWidget);
      expect(harness.platform.createCalls, initialCreateCalls);
      expect(harness.platform.selectSourceCalls, 2);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('手机合集可在同一播放器中切换分 P', (tester) async {
      const secondEntry = MediaPlaybackEntry(
        entryId: '22',
        pageNumber: 2,
        title: 'P2 第二章',
        durationSeconds: 180,
      );
      final multiPageTarget = MediaPlaybackTarget(
        detail: MediaDetail(
          mediaId: 'BV1LISTEN',
          title: '伴听合集',
          coverUrl: '',
          ownerName: '伴听测试UP',
          pages: <MediaPlaybackEntry>[target.entry, secondEntry],
        ),
        entry: target.entry,
      );
      final adapter = _ShellAdapter();
      final harness = await pumpShell(
        tester,
        adapter: adapter,
        playbackTarget: multiPageTarget,
        surfaceSize: const Size(390, 844),
      );
      final initialCreateCalls = harness.platform.createCalls;

      await tester.tap(find.byKey(const ValueKey<String>('enter-listen-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('合集'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('listen-phone-episodes')),
        findsOneWidget,
      );

      await tester.tap(find.text(secondEntry.title));
      for (var round = 0; round < 3; round += 1) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump();
      }

      expect(harness.viewModel.selectedEntry.entryId, secondEntry.entryId);
      expect(adapter.resolveCallCount, 2);
      expect(harness.platform.selectSourceCalls, 2);
      expect(
        harness.platform.selectedSources.map((source) => source.uri),
        <String>[
          'https://example.test/11-audio.mpd',
          'https://example.test/22-audio.mpd',
        ],
      );
      final systemMetadata =
          harness.platform.systemPlaybackConfigurations.last.metadata;
      expect(systemMetadata?.contentUri, 'https://example.test/22-audio.mpd');
      expect(systemMetadata?.durationMs, 180000);
      expect(systemMetadata?.title, contains('P2 第二章'));
      expect(harness.platform.createCalls, initialCreateCalls);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TV 可由控制条进入伴听并用返回键回到视频', (tester) async {
      const secondEntry = MediaPlaybackEntry(
        entryId: '22',
        pageNumber: 2,
        title: 'P2 第二章',
        durationSeconds: 180,
      );
      final multiPageTarget = MediaPlaybackTarget(
        detail: MediaDetail(
          mediaId: 'BV1LISTENTV',
          title: 'TV 伴听合集',
          coverUrl: '',
          ownerName: '伴听测试UP',
          pages: <MediaPlaybackEntry>[target.entry, secondEntry],
        ),
        entry: target.entry,
      );
      final harness = await pumpShell(
        tester,
        playbackTarget: multiPageTarget,
        presentationMode: MediaPlaybackPresentationMode.tv,
        surfaceSize: const Size(1920, 1080),
      );
      final initialCreateCalls = harness.platform.createCalls;

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('listen-mode-container')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('listen-return-video')),
        findsOneWidget,
      );
      expect(find.byTooltip('退出听视频'), findsOneWidget);
      expect(find.text('返回视频'), findsNothing);
      expect(find.text('字幕'), findsOneWidget);
      expect(find.text('合集'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_listen_播放');
      expect(harness.platform.createCalls, initialCreateCalls);
      expect(harness.platform.selectSourceCalls, 1);
      expect(harness.platform.disposeCalls, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('listen-mode-container')),
        findsNothing,
      );
      expect(find.byType(vesper_ui.VesperPlayerStage), findsNothing);
      expect(harness.platform.createCalls, initialCreateCalls);
      expect(harness.platform.selectSourceCalls, 2);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TV 矮屏进入伴听时封面和播放控制保持可见', (tester) async {
      final harness = await pumpShell(
        tester,
        presentationMode: MediaPlaybackPresentationMode.tv,
        surfaceSize: const Size(1024, 480),
      );
      final initialCreateCalls = harness.platform.createCalls;

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('listen-mode-container')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('listen-mode-cover')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('listen-play-pause')),
        findsOneWidget,
      );
      expect(harness.platform.createCalls, initialCreateCalls);
      expect(harness.platform.selectSourceCalls, 1);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('进入和返回伴听恢复位置、播放态、倍速与视频 ABR 策略', (tester) async {
      final initialSnapshot = _shellSnapshot.copyWith(
        playbackState: VesperPlaybackState.playing,
        playbackRate: 1.25,
        timeline: VesperTimeline(
          kind: VesperTimelineKind.vod,
          isSeekable: true,
          seekableRange: null,
          liveEdgeMs: null,
          positionMs: 42000,
          durationMs: 120000,
        ),
        trackSelection: const VesperTrackSelectionSnapshot(
          abrPolicy: VesperAbrPolicy.constrained(maxBitRate: 1800000),
        ),
      );
      final harness = await pumpShell(
        tester,
        initialSnapshot: initialSnapshot,
        surfaceSize: const Size(390, 844),
      );
      harness.platform
        ..updateSnapshotOnCommands = true
        ..selectedSourceSuccessSnapshot = _shellSnapshot;
      final initialPlayCalls = harness.platform.playCalls;

      await tester.tap(find.byKey(const ValueKey<String>('enter-listen-mode')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('listen-return-video')),
      );
      await tester.pumpAndSettle();

      expect(harness.platform.createCalls, 1);
      expect(harness.platform.disposeCalls, 0);
      expect(harness.platform.selectSourceCalls, 2);
      expect(harness.platform.seekRatios, <double>[0.35, 0.35]);
      expect(harness.platform.playbackRates, <double>[1.25, 1.25]);
      expect(harness.platform.playCalls, initialPlayCalls + 2);
      expect(harness.platform.pauseCalls, 0);
      expect(harness.platform.abrPolicyCalls, hasLength(1));
      expect(
        harness.platform.abrPolicyCalls.single.policy.mode,
        VesperAbrMode.constrained,
      );
      expect(harness.platform.abrPolicyCalls.single.policy.maxBitRate, 1800000);
      expect(harness.viewModel.sourceMode, MediaPlaybackSourceMode.video);
      expect(tester.takeException(), isNull);
      harness.platform.emitSnapshot(
        _shellSnapshot.copyWith(playbackState: VesperPlaybackState.paused),
      );
      await tester.pump();
    });

    testWidgets('暂停状态在进入和返回伴听后保持暂停', (tester) async {
      final harness = await pumpShell(
        tester,
        initialSnapshot: _shellSnapshot.copyWith(
          playbackState: VesperPlaybackState.paused,
          timeline: VesperTimeline(
            kind: VesperTimelineKind.vod,
            isSeekable: true,
            seekableRange: null,
            liveEdgeMs: null,
            positionMs: 30000,
            durationMs: 120000,
          ),
        ),
        surfaceSize: const Size(390, 844),
      );
      harness.platform
        ..updateSnapshotOnCommands = true
        ..selectedSourceSuccessSnapshot = _shellSnapshot;
      final initialPlayCalls = harness.platform.playCalls;

      final enterGate = Completer<void>();
      harness.platform.selectSourceGate = enterGate;
      final enterFuture = harness.viewModel.enterListenMode();
      await tester.pump();

      expect(harness.platform.selectSourceCalls, 1);
      expect(harness.platform.pauseCalls, 1);

      enterGate.complete();
      await tester.pumpAndSettle();
      expect(await enterFuture, isNull);
      expect(harness.platform.pauseCalls, 2);

      final exitGate = Completer<void>();
      harness.platform.selectSourceGate = exitGate;
      final exitFuture = harness.viewModel.exitListenMode();
      await tester.pump();

      expect(harness.platform.selectSourceCalls, 2);
      expect(harness.platform.pauseCalls, 3);

      exitGate.complete();
      await tester.pumpAndSettle();
      expect(await exitFuture, isNull);

      expect(harness.platform.pauseCalls, 4);
      expect(harness.platform.playCalls, initialPlayCalls);
      expect(harness.platform.seekRatios, <double>[0.25, 0.25]);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('返回视频按保存的清晰度和 codec 策略重新选择轨道', (tester) async {
      const avcTrack = VesperMediaTrack(
        id: 'video-80-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'avc1.640028',
        bitRate: 1000000,
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.supported,
          reason: VesperTrackSupportReason.none,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      final videoSnapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[avcTrack],
          catalogRevision: 21,
        ),
      );
      final adapter = _ShellAdapter(
        qualityOptions: const <MediaQualityOption>[
          MediaQualityOption(
            id: '80',
            label: '1080P',
            tracks: <VesperMediaTrack>[avcTrack],
          ),
        ],
        qualityPolicy: MediaQualityPolicy(
          supportsCodecSelection: true,
          codecLabelFor: (track) => 'AVC',
          codecIdentityFor: (track) => 'avc',
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: adapter,
        initialSnapshot: videoSnapshot,
        surfaceSize: const Size(390, 844),
      );
      expect(await harness.viewModel.selectQualityOption('80'), isNull);
      expect(await harness.viewModel.selectCodecIdentity('avc'), isNull);
      harness.platform.selectedSourceSuccessSnapshot = videoSnapshot;
      final initialAbrCalls = harness.platform.abrPolicyCalls.length;

      await tester.tap(find.byKey(const ValueKey<String>('enter-listen-mode')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('listen-return-video')),
      );
      await tester.pumpAndSettle();

      expect(harness.viewModel.selectedQualityOptionId, '80');
      expect(harness.viewModel.selectedCodecIdentity, 'avc');
      expect(harness.platform.abrPolicyCalls, hasLength(initialAbrCalls + 1));
      final restored = harness.platform.abrPolicyCalls.last;
      expect(restored.policy.mode, VesperAbrMode.fixedTrack);
      expect(restored.policy.trackId, avcTrack.id);
      expect(restored.expectedCatalogRevision, 21);
      expect(harness.platform.createCalls, 1);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('切源快照晚于方法回包时仍按旧进度恢复', (tester) async {
      final harness = await pumpShell(
        tester,
        initialSnapshot: _shellSnapshot.copyWith(
          playbackState: VesperPlaybackState.playing,
          timeline: const VesperTimeline(
            kind: VesperTimelineKind.vod,
            isSeekable: true,
            seekableRange: null,
            liveEdgeMs: null,
            positionMs: 48000,
            durationMs: 120000,
          ),
        ),
        surfaceSize: const Size(390, 844),
      );

      // 不发送新源快照，模拟 EventChannel 晚于 MethodChannel 回包。
      expect(await harness.viewModel.enterListenMode(), isNull);

      expect(harness.platform.seekRatios, <double>[0.4]);
      expect(harness.viewModel.sourceMode, MediaPlaybackSourceMode.audioOnly);
      expect(harness.platform.createCalls, 1);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
      harness.platform.emitSnapshot(
        _shellSnapshot.copyWith(playbackState: VesperPlaybackState.paused),
      );
      await tester.pump();
    });

    testWidgets('无纯音频源时保留视频界面并明确提示', (tester) async {
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(supportsAudioOnly: false),
        surfaceSize: const Size(390, 844),
      );

      await tester.tap(find.byKey(const ValueKey<String>('enter-listen-mode')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('listen-mode-container')),
        findsNothing,
      );
      expect(find.text('当前视频暂无可用的纯音频源。'), findsOneWidget);
      expect(harness.platform.selectSourceCalls, 0);
      expect(harness.viewModel.sourceMode, MediaPlaybackSourceMode.video);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('进入伴听切源失败时回滚完整视频源且不切换界面', (tester) async {
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() {
        FlutterError.onError = previousOnError;
      });
      final harness = await pumpShell(
        tester,
        surfaceSize: const Size(390, 844),
      );
      harness.platform.failSelectSourceCallsRemaining = 1;

      await tester.tap(find.byKey(const ValueKey<String>('enter-listen-mode')));
      await tester.pumpAndSettle();

      expect(
        harness.platform.selectedSources.map((source) => source.uri),
        <String>[
          'https://example.test/11-audio.mpd',
          'https://example.test/shell.mp4',
        ],
      );
      expect(
        find.byKey(const ValueKey<String>('listen-mode-container')),
        findsNothing,
      );
      expect(find.textContaining('进入听视频失败'), findsOneWidget);
      expect(harness.viewModel.sourceMode, MediaPlaybackSourceMode.video);
      expect(harness.platform.createCalls, 1);
      expect(harness.platform.disposeCalls, 0);
      expect(reported, isNotEmpty);
    });

    testWidgets('伴听中切分 P 播放失败时回滚旧条目和旧纯音频源', (tester) async {
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() {
        FlutterError.onError = previousOnError;
      });
      const secondEntry = MediaPlaybackEntry(
        entryId: '22',
        pageNumber: 2,
        title: 'P2 第二章',
        durationSeconds: 180,
      );
      final multiPageTarget = MediaPlaybackTarget(
        detail: MediaDetail(
          mediaId: 'BV1LISTENROLLBACK',
          title: '伴听回滚测试',
          coverUrl: '',
          ownerName: '伴听测试UP',
          pages: <MediaPlaybackEntry>[target.entry, secondEntry],
        ),
        entry: target.entry,
      );
      final harness = await pumpShell(
        tester,
        playbackTarget: multiPageTarget,
        surfaceSize: const Size(390, 844),
      );

      expect(await harness.viewModel.enterListenMode(), isNull);
      harness.platform.failPlayCallsRemaining = 1;
      final message = await harness.viewModel.switchEntry(secondEntry);

      expect(message, contains('切换分 P 失败'));
      expect(harness.viewModel.selectedEntry.entryId, target.entry.entryId);
      expect(harness.viewModel.sourceMode, MediaPlaybackSourceMode.audioOnly);
      expect(
        harness.viewModel.resolvedPlayback?.toAudioOnlySource()?.uri,
        'https://example.test/11-audio.mpd',
      );
      expect(
        harness.platform.selectedSources.map((source) => source.uri),
        <String>[
          'https://example.test/11-audio.mpd',
          'https://example.test/22-audio.mpd',
          'https://example.test/11-audio.mpd',
        ],
      );
      final systemMetadata =
          harness.platform.systemPlaybackConfigurations.last.metadata;
      expect(systemMetadata?.contentUri, 'https://example.test/11-audio.mpd');
      expect(systemMetadata?.durationMs, 120000);
      expect(systemMetadata?.title, contains('P1'));
      expect(harness.platform.createCalls, 1);
      expect(harness.platform.disposeCalls, 0);
      expect(reported, isNotEmpty);
    });

    testWidgets('伴听模式地址恢复继续选择新解析的纯音频源', (tester) async {
      final adapter = _ShellAdapter(versionSourcesByResolveCall: true);
      final harness = await pumpShell(
        tester,
        adapter: adapter,
        surfaceSize: const Size(390, 844),
      );

      expect(await harness.viewModel.enterListenMode(), isNull);
      expect(
        harness.platform.selectedSources.single.uri,
        'https://example.test/11-audio-1.mpd',
      );

      harness.platform.emitRecoverableSourceError();
      for (var round = 0; round < 10; round += 1) {
        await tester.pump(const Duration(milliseconds: 100));
        if (harness.viewModel.resolvedPlayback?.toAudioOnlySource()?.uri ==
            'https://example.test/11-audio-2.mpd') {
          break;
        }
      }

      expect(adapter.resolveCallCount, 2);
      expect(harness.platform.selectedSources, hasLength(2));
      expect(
        harness.platform.selectedSources.last.uri,
        'https://example.test/11-audio-2.mpd',
      );
      expect(harness.viewModel.sourceMode, MediaPlaybackSourceMode.audioOnly);
      expect(
        harness.viewModel.resolvedPlayback?.toAudioOnlySource()?.uri,
        'https://example.test/11-audio-2.mpd',
      );
      expect(
        harness.platform.systemPlaybackConfigurations.last.metadata?.contentUri,
        'https://example.test/11-audio-2.mpd',
      );
      expect(harness.platform.createCalls, 1);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(adapter.resolveCallCount, 2);
    });

    testWidgets('伴听地址恢复换源中切 P 时最终保留新 P 纯音频源', (tester) async {
      const secondEntry = MediaPlaybackEntry(
        entryId: '22',
        pageNumber: 2,
        title: 'P2 第二章',
        durationSeconds: 180,
      );
      final adapter = _ShellAdapter(versionSourcesByResolveCall: true);
      final harness = await pumpShell(
        tester,
        adapter: adapter,
        playbackTarget: MediaPlaybackTarget(
          detail: MediaDetail(
            mediaId: 'BV1LISTENRECOVERYRACE',
            title: '伴听恢复竞态测试',
            coverUrl: '',
            ownerName: '伴听测试UP',
            pages: <MediaPlaybackEntry>[target.entry, secondEntry],
          ),
          entry: target.entry,
        ),
        surfaceSize: const Size(390, 844),
      );

      expect(await harness.viewModel.enterListenMode(), isNull);
      final recoverySelectGate = Completer<void>();
      harness.platform.selectSourceGate = recoverySelectGate;
      harness.platform.emitRecoverableSourceError();
      for (var round = 0; round < 10; round += 1) {
        await tester.pump();
        if (harness.platform.selectedSources.length == 2) {
          break;
        }
      }
      expect(
        harness.platform.selectedSources.last.uri,
        'https://example.test/11-audio-2.mpd',
      );

      final switchFuture = harness.viewModel.switchEntry(secondEntry);
      await tester.pump();
      expect(harness.viewModel.selectedEntry.entryId, target.entry.entryId);

      recoverySelectGate.complete();
      expect(await switchFuture, isNull);
      await tester.pump();

      expect(adapter.resolveCallCount, 3);
      expect(
        harness.platform.selectedSources.map((source) => source.uri),
        <String>[
          'https://example.test/11-audio-1.mpd',
          'https://example.test/11-audio-2.mpd',
          'https://example.test/22-audio-3.mpd',
        ],
      );
      expect(harness.viewModel.selectedEntry.entryId, secondEntry.entryId);
      expect(harness.viewModel.sourceMode, MediaPlaybackSourceMode.audioOnly);
      expect(
        harness.viewModel.resolvedPlayback?.toAudioOnlySource()?.uri,
        'https://example.test/22-audio-3.mpd',
      );
      final systemMetadata =
          harness.platform.systemPlaybackConfigurations.last.metadata;
      expect(systemMetadata?.contentUri, 'https://example.test/22-audio-3.mpd');
      expect(systemMetadata?.durationMs, 180000);
      expect(systemMetadata?.title, contains('P2 第二章'));
      expect(harness.platform.createCalls, 1);
      expect(harness.platform.disposeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    test('reload 等待伴听换源退出后再销毁旧 controller', () async {
      final platform = installViewModelEnvironment();
      final viewModel = MediaPlaybackViewModel(
        detail: target.detail,
        initialEntry: target.entry,
        adapter: _ShellAdapter(),
        preferTextureViewForPlayback: () async => false,
      );
      addTearDown(() async {
        viewModel.dispose();
        await platform
            .waitForDisposeCalls(platform.createCalls)
            .timeout(const Duration(seconds: 2));
      });
      await viewModel.controllerFuture;
      final selectGate = Completer<void>();
      platform.selectSourceGate = selectGate;

      final enterFuture = viewModel.enterListenMode();
      await Future<void>.delayed(Duration.zero);
      expect(platform.selectSourceCalls, 1);

      final reloadFuture = viewModel.reloadCurrentPage();
      expect(viewModel.controller, isNull);
      expect(platform.disposeCalls, 0);

      selectGate.complete();
      final enterMessage = await enterFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(enterMessage, contains('播放源已更新'));
      await reloadFuture.timeout(const Duration(seconds: 2));
      final reloadedController = await viewModel.controllerFuture.timeout(
        const Duration(seconds: 2),
      );

      expect(reloadedController, isNotNull);
      expect(viewModel.controller, same(reloadedController));
      expect(platform.createCalls, 2);
      expect(platform.disposeCalls, 1);
    });

    test('dispose 等待伴听换源退出后再销毁 controller', () async {
      final platform = installViewModelEnvironment();
      final viewModel = MediaPlaybackViewModel(
        detail: target.detail,
        initialEntry: target.entry,
        adapter: _ShellAdapter(),
        preferTextureViewForPlayback: () async => false,
      );
      await viewModel.controllerFuture;
      final selectGate = Completer<void>();
      platform.selectSourceGate = selectGate;

      final enterFuture = viewModel.enterListenMode();
      await Future<void>.delayed(Duration.zero);
      expect(platform.selectSourceCalls, 1);

      viewModel.dispose();
      expect(viewModel.controller, isNull);
      expect(platform.disposeCalls, 0);

      selectGate.complete();
      final enterMessage = await enterFuture.timeout(
        const Duration(seconds: 2),
      );
      await platform.waitForDisposeCalls(1).timeout(const Duration(seconds: 2));

      expect(enterMessage, contains('播放源已更新'));
      expect(platform.disposeCalls, 1);
    });
  });

  group('互动动作槽（§6.3）', () {
    testWidgets('声明动作按顺序渲染，busy 动作禁用', (tester) async {
      final binding = MediaPlaybackBinding(
        engagementBuilder: () => MediaEngagementCapability(
          actions: <MediaEngagementActionSpec>[
            MediaEngagementActionSpec(
              id: MediaEngagementActionId.like,
              label: '点赞',
              count: 1234,
              selected: true,
              busy: false,
              perform: () async => null,
            ),
            MediaEngagementActionSpec(
              id: MediaEngagementActionId.coin,
              label: '硬币',
              busy: true,
              perform: () async => null,
            ),
          ],
        ),
      );
      await pumpShell(tester, binding: binding);

      expect(find.text('点赞'), findsOneWidget);
      expect(find.text('1234'), findsOneWidget);
      expect(find.text('硬币'), findsOneWidget);
      final coinButton = tester.widget<InkWell>(
        find.byKey(const ValueKey<String>('engagement-coin')),
      );
      expect(coinButton.onTap, isNull, reason: 'busy 动作应禁用');
      final likeButton = tester.widget<InkWell>(
        find.byKey(const ValueKey<String>('engagement-like')),
      );
      expect(likeButton.onTap, isNotNull);
    });

    testWidgets('动作执行提示语来自 perform 返回值', (tester) async {
      final binding = MediaPlaybackBinding(
        engagementBuilder: () => MediaEngagementCapability(
          actions: <MediaEngagementActionSpec>[
            MediaEngagementActionSpec(
              id: MediaEngagementActionId.favorite,
              label: '收藏',
              perform: () async => '已收藏',
            ),
          ],
        ),
      );
      await pumpShell(tester, binding: binding);

      await tester.tap(find.text('收藏'));
      await tester.pump();

      expect(find.text('已收藏'), findsOneWidget);
    });
  });

  group('codec 策略身份（§6.2）', () {
    testWidgets('身份是内部键且未提供规范标签时不泄漏到 UI', (tester) async {
      // identity 'hevc-main'（内部键）+ 无 codecIdentityLabelFor：
      // 选项回退组内首项展示 label（Dolby Vision），绝不出 'hevc-main'。
      const dvTrack = VesperMediaTrack(
        id: 'video-126-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '杜比视界',
        codec: 'dvhe.05.06',
      );
      const hevcTrack = VesperMediaTrack(
        id: 'video-80-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'hev1.1.6',
      );
      final adapter = _ShellAdapter(
        qualityOptions: const <MediaQualityOption>[
          MediaQualityOption(
            id: '80',
            label: '1080P',
            tracks: <VesperMediaTrack>[dvTrack, hevcTrack],
          ),
        ],
        qualityPolicy: MediaQualityPolicy(
          supportsCodecSelection: true,
          codecLabelFor: (track) =>
              track.codec == 'dvhe.05.06' ? 'Dolby Vision' : 'HEVC',
          codecIdentityFor: (track) => 'hevc-main',
        ),
      );
      await pumpShell(tester, adapter: adapter);

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Dolby Vision'), findsOneWidget);
      expect(find.text('hevc-main'), findsNothing);
      expect(find.text('HEVC'), findsNothing);
    });

    testWidgets('提供规范标签时按 codecIdentityLabelFor 展示', (tester) async {
      const hevcTrack = VesperMediaTrack(
        id: 'video-80-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'hev1.1.6',
      );
      final adapter = _ShellAdapter(
        qualityOptions: const <MediaQualityOption>[
          MediaQualityOption(
            id: '80',
            label: '1080P',
            tracks: <VesperMediaTrack>[hevcTrack],
          ),
        ],
        qualityPolicy: MediaQualityPolicy(
          supportsCodecSelection: true,
          codecLabelFor: (track) => 'HEVC',
          codecIdentityFor: (track) => 'hevc-main',
          codecIdentityLabelFor: (identity) =>
              identity == 'hevc-main' ? 'HEVC' : identity,
        ),
      );
      await pumpShell(tester, adapter: adapter);

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('HEVC'), findsOneWidget);
      expect(find.text('hevc-main'), findsNothing);
    });
  });

  group('fixed-track SDK 契约', () {
    const selectableTrack = VesperMediaTrack(
      id: 'video-80-7-1000-0',
      kind: VesperMediaTrackKind.video,
      label: '1080P',
      codec: 'avc1.640028',
      bitRate: 1000000,
      width: 1920,
      height: 1080,
      support: VesperTrackSupport(
        status: VesperTrackSupportStatus.supported,
        reason: VesperTrackSupportReason.none,
        source: VesperTrackSupportSource.runtimeTrackCatalog,
      ),
    );
    const qualityOptions = <MediaQualityOption>[
      MediaQualityOption(
        id: '80',
        label: '1080P',
        tracks: <VesperMediaTrack>[selectableTrack],
      ),
    ];

    testWidgets('fixed-track 携带选择时看到的 catalog revision', (tester) async {
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrConstrained: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[selectableTrack],
          adaptiveVideo: true,
          catalogRevision: 7,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(qualityOptions: qualityOptions),
        initialSnapshot: snapshot,
      );

      expect(await harness.viewModel.selectQualityOption('80'), isNull);
      final call = harness.platform.abrPolicyCalls.single;
      expect(call.policy.mode, VesperAbrMode.fixedTrack);
      expect(call.policy.trackId, selectableTrack.id);
      expect(call.expectedCatalogRevision, 7);
      expect(harness.viewModel.selectedQualityOptionId, '80');
    });

    testWidgets('不透明原生轨道 ID 按语义映射并下发 SDK 原生 ID', (tester) async {
      const declaredAvc = VesperMediaTrack(
        id: 'video-80-7-1000000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'avc1.640028',
        bitRate: 1000000,
        width: 1920,
        height: 1080,
        frameRate: 30,
      );
      const declaredHevc = VesperMediaTrack(
        id: 'video-80-12-900000-1',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'hev1.1.6.L120',
        bitRate: 900000,
        width: 1920,
        height: 1080,
        frameRate: 30,
      );
      const declaredAv1 = VesperMediaTrack(
        id: 'video-80-13-800000-2',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'av01.0.08M.08',
        bitRate: 800000,
        width: 1920,
        height: 1080,
        frameRate: 30,
      );
      const supported = VesperTrackSupport(
        status: VesperTrackSupportStatus.supported,
        reason: VesperTrackSupportReason.none,
        source: VesperTrackSupportSource.runtimeTrackCatalog,
      );
      const nativeAvc = VesperMediaTrack(
        id: '0:0:0:video-80-7-1000000-0:0',
        kind: VesperMediaTrackKind.video,
        codec: 'avc1.640028',
        bitRate: 998500,
        width: 1920,
        height: 1080,
        frameRate: 29.97,
        support: supported,
      );
      const nativeHevc = VesperMediaTrack(
        id: 'renderer/group/opaque-hevc',
        kind: VesperMediaTrackKind.video,
        codec: 'hev1.1.6.L120',
        bitRate: 897000,
        width: 1920,
        height: 1080,
        frameRate: 29.97,
        support: supported,
      );
      const nativeAv1 = VesperMediaTrack(
        id: 'native#opaque-av1',
        kind: VesperMediaTrackKind.video,
        codec: 'av01.0.08M.08',
        bitRate: 796000,
        width: 1920,
        height: 1080,
        frameRate: 29.97,
        support: supported,
      );
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[nativeAvc, nativeHevc, nativeAv1],
          adaptiveVideo: true,
          catalogRevision: 43,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(
          qualityOptions: const <MediaQualityOption>[
            MediaQualityOption(
              id: '80',
              label: '1080P',
              tracks: <VesperMediaTrack>[
                declaredAvc,
                declaredHevc,
                declaredAv1,
              ],
            ),
          ],
          qualityPolicy: BiliQualityMapping.buildQualityPolicy(),
        ),
        initialSnapshot: snapshot,
      );

      final option = harness.viewModel.qualitySelectionOptions(snapshot).single;
      expect(option.availability, MediaQualityAvailability.available);
      expect(option.candidateTracks.map((track) => track.id), <String>[
        nativeAvc.id,
        nativeHevc.id,
        nativeAv1.id,
      ]);
      for (final identity in const <String>['AVC', 'HEVC', 'AV1']) {
        expect(
          harness.viewModel.codecSelectionAvailability(
            snapshot,
            identity,
            optionId: '80',
          ),
          MediaQualityAvailability.available,
        );
      }

      expect(await harness.viewModel.selectQualityOption('80'), isNull);
      expect(await harness.viewModel.selectCodecIdentity('AVC'), isNull);
      expect(harness.platform.abrPolicyCalls.last.policy.trackId, nativeAvc.id);
      expect(await harness.viewModel.selectCodecIdentity('HEVC'), isNull);
      expect(
        harness.platform.abrPolicyCalls.last.policy.trackId,
        nativeHevc.id,
      );
      expect(await harness.viewModel.selectCodecIdentity('AV1'), isNull);
      expect(harness.platform.abrPolicyCalls.last.policy.trackId, nativeAv1.id);
      expect(harness.platform.abrPolicyCalls.last.expectedCatalogRevision, 43);
    });

    testWidgets('清晰度按 supported、unknown、unsupported 聚合', (tester) async {
      const unknownTrack = VesperMediaTrack(
        id: 'video-64-12-500-0',
        kind: VesperMediaTrackKind.video,
        codec: 'hev1.1.6',
        support: VesperTrackSupport(),
      );
      const unsupportedTrack = VesperMediaTrack(
        id: 'video-120-12-2000-0',
        kind: VesperMediaTrackKind.video,
        codec: 'hev1.2.4',
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.exceedsCapabilities,
          reason: VesperTrackSupportReason.formatExceedsCapabilities,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      final snapshot = _shellSnapshot.copyWith(
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[
            selectableTrack,
            unknownTrack,
            unsupportedTrack,
          ],
          adaptiveVideo: true,
          catalogRevision: 12,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(
          qualityOptions: const <MediaQualityOption>[
            ...qualityOptions,
            MediaQualityOption(
              id: '64',
              label: '720P',
              tracks: <VesperMediaTrack>[unknownTrack],
            ),
            MediaQualityOption(
              id: '120',
              label: '4K 超清',
              tracks: <VesperMediaTrack>[unsupportedTrack],
            ),
          ],
        ),
        initialSnapshot: snapshot,
      );

      final options = harness.viewModel.qualitySelectionOptions(snapshot);

      expect(
        options.map((option) => option.availability),
        <MediaQualityAvailability>[
          MediaQualityAvailability.available,
          MediaQualityAvailability.unknown,
          MediaQualityAvailability.unavailable,
        ],
      );
      expect(
        options.last.unavailableReason,
        VesperTrackSupportReason.formatExceedsCapabilities,
      );
    });

    testWidgets('显式不可选轨道不会下发 fixed-track', (tester) async {
      const unsupportedTrack = VesperMediaTrack(
        id: 'video-80-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P',
        codec: 'avc1.640028',
        bitRate: 1000000,
        width: 1920,
        height: 1080,
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.exceedsCapabilities,
          reason: VesperTrackSupportReason.formatExceedsCapabilities,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrConstrained: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[unsupportedTrack],
          adaptiveVideo: true,
          catalogRevision: 8,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(qualityOptions: qualityOptions),
        initialSnapshot: snapshot,
      );

      expect(
        await harness.viewModel.selectQualityOption('80'),
        '当前设备无法播放该清晰度。',
      );
      expect(harness.platform.abrPolicyCalls, isEmpty);
      expect(harness.viewModel.selectedQualityOptionId, isNull);
    });

    testWidgets('选择状态只在 SDK 命令成功后提交', (tester) async {
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[selectableTrack],
          catalogRevision: 13,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(qualityOptions: qualityOptions),
        initialSnapshot: snapshot,
      );
      final gate = Completer<void>();
      harness.platform.setAbrPolicyGate = gate;

      final selection = harness.viewModel.selectQualityOption('80');
      await tester.pump();

      expect(harness.viewModel.selectedQualityOptionId, isNull);
      gate.complete();
      expect(await selection, isNull);
      expect(harness.viewModel.selectedQualityOptionId, '80');
    });

    testWidgets('并发清晰度选择只提交最新请求', (tester) async {
      const secondTrack = VesperMediaTrack(
        id: 'video-120-7-2000-0',
        kind: VesperMediaTrackKind.video,
        codec: 'avc1.640033',
        bitRate: 2000000,
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.supported,
          reason: VesperTrackSupportReason.none,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[selectableTrack, secondTrack],
          catalogRevision: 14,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(
          qualityOptions: const <MediaQualityOption>[
            ...qualityOptions,
            MediaQualityOption(
              id: '120',
              label: '4K 超清',
              tracks: <VesperMediaTrack>[secondTrack],
            ),
          ],
        ),
        initialSnapshot: snapshot,
      );
      final firstRequestGate = Completer<void>();
      harness.platform.setAbrPolicyHandler = (policy) {
        return policy.trackId == selectableTrack.id
            ? firstRequestGate.future
            : Future<void>.value();
      };

      final firstRequest = harness.viewModel.selectQualityOption('80');
      await tester.pump();
      final latestRequest = harness.viewModel.selectQualityOption('120');

      expect(await latestRequest, isNull);
      expect(harness.viewModel.selectedQualityOptionId, '120');
      firstRequestGate.complete();
      expect(await firstRequest, isNull);
      expect(harness.viewModel.selectedQualityOptionId, '120');
    });

    testWidgets('取消 codec 子策略后使用默认候选轨道', (tester) async {
      const hevcTrack = VesperMediaTrack(
        id: 'video-80-12-900-0',
        kind: VesperMediaTrackKind.video,
        codec: 'hev1.1.6.L120',
        bitRate: 900000,
        width: 1920,
        height: 1080,
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.supported,
          reason: VesperTrackSupportReason.none,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[selectableTrack, hevcTrack],
          catalogRevision: 15,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(
          qualityOptions: const <MediaQualityOption>[
            MediaQualityOption(
              id: '80',
              label: '1080P',
              tracks: <VesperMediaTrack>[selectableTrack, hevcTrack],
            ),
          ],
          qualityPolicy: MediaQualityPolicy(
            supportsCodecSelection: true,
            codecLabelFor: (track) => track.id == hevcTrack.id ? 'HEVC' : 'AVC',
            codecIdentityFor: (track) =>
                track.id == hevcTrack.id ? 'HEVC' : 'AVC',
            codecIdentityLabelFor: (identity) => identity,
          ),
        ),
        initialSnapshot: snapshot,
      );

      expect(await harness.viewModel.selectQualityOption('80'), isNull);
      expect(await harness.viewModel.selectCodecIdentity('HEVC'), isNull);
      expect(harness.platform.abrPolicyCalls.last.policy.trackId, hevcTrack.id);

      expect(await harness.viewModel.selectCodecIdentity(null), isNull);
      expect(harness.viewModel.selectedCodecIdentity, isNull);
      expect(
        harness.platform.abrPolicyCalls.last.policy.trackId,
        selectableTrack.id,
      );
    });

    testWidgets('不支持 fixed-track 时使用 bitrate constraint', (tester) async {
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrConstrained: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[selectableTrack],
          adaptiveVideo: true,
          catalogRevision: 9,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(qualityOptions: qualityOptions),
        initialSnapshot: snapshot,
      );

      expect(await harness.viewModel.selectQualityOption('80'), isNull);
      final call = harness.platform.abrPolicyCalls.single;
      expect(call.policy.mode, VesperAbrMode.constrained);
      expect(call.policy.maxBitRate, selectableTrack.bitRate);
      expect(call.expectedCatalogRevision, isNull);
    });

    testWidgets('stale catalog 转为稳定中文提示', (tester) async {
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[selectableTrack],
          adaptiveVideo: true,
          catalogRevision: 10,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(qualityOptions: qualityOptions),
        initialSnapshot: snapshot,
      );
      harness.platform.setAbrPolicyError = VesperFixedTrackSelectionException(
        codeRawValue: 'staleCatalog',
        trackId: selectableTrack.id,
        expectedCatalogRevision: 10,
        actualCatalogRevision: 11,
        message: 'catalog changed',
      );

      final message = await harness.viewModel.selectQualityOption('80');

      expect(tester.takeException(), isA<VesperFixedTrackSelectionException>());
      expect(message, '清晰度切换失败：清晰度列表已更新，请重试。');
      expect(
        harness.platform.abrPolicyCalls.single.expectedCatalogRevision,
        10,
      );
      expect(harness.platform.refreshCalls, 1);
      expect(harness.viewModel.selectedQualityOptionId, isNull);
      await tester.pump();
      expect(find.text('播放器错误'), findsNothing);
    });

    testWidgets('fixed-track 拒绝保留上一次成功选择', (tester) async {
      const secondTrack = VesperMediaTrack(
        id: 'video-120-7-2000-0',
        kind: VesperMediaTrackKind.video,
        codec: 'avc1.640033',
        bitRate: 2000000,
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.supported,
          reason: VesperTrackSupportReason.none,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[selectableTrack, secondTrack],
          catalogRevision: 14,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(
          qualityOptions: const <MediaQualityOption>[
            ...qualityOptions,
            MediaQualityOption(
              id: '120',
              label: '4K 超清',
              tracks: <VesperMediaTrack>[secondTrack],
            ),
          ],
        ),
        initialSnapshot: snapshot,
      );
      expect(await harness.viewModel.selectQualityOption('80'), isNull);
      harness.platform.setAbrPolicyError = VesperFixedTrackSelectionException(
        codeRawValue: 'trackUnavailable',
        trackId: secondTrack.id,
        expectedCatalogRevision: 14,
        actualCatalogRevision: 14,
        message: 'track disappeared',
      );

      final message = await harness.viewModel.selectQualityOption('120');

      expect(tester.takeException(), isA<VesperFixedTrackSelectionException>());
      expect(message, '清晰度切换失败：该清晰度已不可用，请重新选择。');
      expect(harness.viewModel.selectedQualityOptionId, '80');
    });

    testWidgets('runtime rejection 由 SDK 降级，App 只对账一次', (tester) async {
      const fallbackTrack = VesperMediaTrack(
        id: 'video-64-7-500-0',
        kind: VesperMediaTrackKind.video,
        label: '720P',
        codec: 'avc1.4d401f',
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.supported,
          reason: VesperTrackSupportReason.none,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      final selectedSnapshot = _shellSnapshot.copyWith(
        playbackState: VesperPlaybackState.playing,
        capabilities: const VesperPlayerCapabilities(
          supportsAbrPolicy: true,
          supportsAbrFixedTrack: true,
        ),
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[selectableTrack, fallbackTrack],
          catalogRevision: 15,
        ),
        effectiveVideoTrackId: selectableTrack.id,
      );
      final harness = await pumpShell(
        tester,
        adapter: _ShellAdapter(
          qualityOptions: const <MediaQualityOption>[
            ...qualityOptions,
            MediaQualityOption(
              id: '64',
              label: '720P',
              tracks: <VesperMediaTrack>[fallbackTrack],
            ),
          ],
        ),
        initialSnapshot: selectedSnapshot,
      );
      expect(await harness.viewModel.selectQualityOption('80'), isNull);

      harness.platform.emitRuntimeTrackRejected(selectableTrack.id);
      harness.platform.emitSnapshot(
        selectedSnapshot.copyWith(
          playbackState: VesperPlaybackState.ready,
          trackCatalog: const VesperTrackCatalog(
            tracks: <VesperMediaTrack>[selectableTrack, fallbackTrack],
            catalogRevision: 16,
          ),
          effectiveVideoTrackId: fallbackTrack.id,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('当前设备无法继续播放所选清晰度，已切换至 720P。'), findsNothing);
      harness.platform.emitSnapshot(
        selectedSnapshot.copyWith(
          trackCatalog: const VesperTrackCatalog(
            tracks: <VesperMediaTrack>[selectableTrack, fallbackTrack],
            catalogRevision: 16,
          ),
          effectiveVideoTrackId: fallbackTrack.id,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.viewModel.selectedQualityOptionId, isNull);
      expect(harness.viewModel.selectedCodecIdentity, isNull);
      expect(
        harness.platform.abrPolicyCalls,
        hasLength(1),
        reason: 'SDK 已负责恢复 auto，App 不应重复下发',
      );
      final options = harness.viewModel.qualitySelectionOptions(
        harness.viewModel.controller!.snapshot,
      );
      expect(options.first.availability, MediaQualityAvailability.unavailable);
      expect(find.text('当前设备无法继续播放所选清晰度，已切换至 720P。'), findsOneWidget);
      harness.platform.emitSnapshot(
        selectedSnapshot.copyWith(playbackState: VesperPlaybackState.ready),
      );
      await tester.pump();
    });
  });

  group('字幕异步确认契约', () {
    testWidgets('类型化字幕超时使用稳定文案且不触发换源', (tester) async {
      final adapter = _ShellAdapter();
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsSubtitleTrackSelection: true,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: adapter,
        initialSnapshot: snapshot,
      );
      harness
          .platform
          .setSubtitleSelectionError = const VesperSubtitleException(
        code: 'subtitle_selection_timeout',
        phase: VesperSubtitleErrorPhase.selection,
        retriable: true,
        message:
            'Media3 did not confirm the subtitle selection before the deadline',
        trackId: 'subtitle:test:zh-CN',
      );

      final message = await harness.viewModel.selectSubtitle(
        const VesperTrackSelection.track('subtitle:test:zh-CN'),
      );
      await tester.pump();

      expect(tester.takeException(), isA<VesperSubtitleException>());
      expect(message, '字幕切换失败：字幕轨道仍在准备，请稍后重试。');
      expect(adapter.resolveCallCount, 1);
      expect(harness.platform.selectSourceCalls, 0);
      expect(find.text('播放器错误'), findsNothing);
    });
  });

  group('轨道能力交互', () {
    testWidgets('手机设置显示自动、unknown 和禁用原因', (tester) async {
      const supportedAvc = VesperMediaTrack(
        id: 'video-80-7-1000-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P AVC',
        codec: 'avc1.640028',
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.supported,
          reason: VesperTrackSupportReason.none,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      const unsupportedHevc = VesperMediaTrack(
        id: 'video-80-12-1100-0',
        kind: VesperMediaTrackKind.video,
        label: '1080P HEVC',
        codec: 'hev1.1.6.L120',
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.exceedsCapabilities,
          reason: VesperTrackSupportReason.formatExceedsCapabilities,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      const unknownTrack = VesperMediaTrack(
        id: 'video-64-7-800-0',
        kind: VesperMediaTrackKind.video,
        label: '720P',
        codec: 'avc1.4d401f',
      );
      const unsupported4k = VesperMediaTrack(
        id: 'video-120-12-2000-0',
        kind: VesperMediaTrackKind.video,
        label: '4K HEVC',
        codec: 'hev1.2.4.L153',
        support: VesperTrackSupport(
          status: VesperTrackSupportStatus.unsupported,
          reason: VesperTrackSupportReason.unsupportedSubtype,
          source: VesperTrackSupportSource.runtimeTrackCatalog,
        ),
      );
      final snapshot = _shellSnapshot.copyWith(
        trackCatalog: const VesperTrackCatalog(
          tracks: <VesperMediaTrack>[
            supportedAvc,
            unsupportedHevc,
            unknownTrack,
            unsupported4k,
          ],
          catalogRevision: 21,
        ),
      );
      final adapter = _ShellAdapter(
        qualityOptions: const <MediaQualityOption>[
          MediaQualityOption(
            id: '80',
            label: '1080P',
            tracks: <VesperMediaTrack>[supportedAvc, unsupportedHevc],
          ),
          MediaQualityOption(
            id: '64',
            label: '720P',
            tracks: <VesperMediaTrack>[unknownTrack],
          ),
          MediaQualityOption(
            id: '120',
            label: '4K 超清',
            tracks: <VesperMediaTrack>[unsupported4k],
          ),
        ],
        qualityPolicy: MediaQualityPolicy(
          supportsCodecSelection: true,
          codecLabelFor: (track) =>
              track.codec!.startsWith('avc') ? 'AVC' : 'HEVC',
          codecIdentityFor: (track) =>
              track.codec!.startsWith('avc') ? 'AVC' : 'HEVC',
          codecIdentityLabelFor: (identity) => identity,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: adapter,
        initialSnapshot: snapshot,
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('自动'), findsOneWidget);
      expect(find.text('兼容性未知'), findsOneWidget);
      expect(find.text('当前设备不支持'), findsNWidgets(2));
      expect(find.text('HEVC'), findsOneWidget);

      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('4K 超清，当前设备不支持')),
        matchesSemantics(
          label: '4K 超清，当前设备不支持',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: true,
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('tuning-quality-120')),
      );
      await tester.pump();
      expect(harness.platform.abrPolicyCalls, isEmpty);
      semantics.dispose();
    });

    testWidgets('TV catalog 更新后禁用项退出焦点树', (tester) async {
      List<TvPanelOption> options({required bool fourKEnabled}) {
        return <TvPanelOption>[
          TvPanelOption(label: '自动', selected: false, onTap: () {}),
          TvPanelOption(
            label: '4K 超清',
            subtitle: fourKEnabled ? null : '当前设备不支持',
            selected: true,
            enabled: fourKEnabled,
            onTap: () {},
          ),
        ];
      }

      Widget buildPanel(String revision, {required bool fourKEnabled}) {
        return MaterialApp(
          home: Scaffold(
            body: TvPanelOptionList(
              panelKey: 'quality:$revision',
              options: options(fourKEnabled: fourKEnabled),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildPanel('30', fourKEnabled: true));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_4K 超清');

      await tester.pumpWidget(buildPanel('31', fourKEnabled: false));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_自动');
      expect(
        find.ancestor(
          of: find.text('4K 超清'),
          matching: find.byType(TvFocusable),
        ),
        findsNothing,
      );
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('4K 超清，当前设备不支持')),
        matchesSemantics(
          label: '4K 超清，当前设备不支持',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: true,
          isSelected: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('TV 选项数量变化时 FocusNode 安全交接', (tester) async {
      Widget buildPanel(List<TvPanelOption> options) {
        return MaterialApp(
          home: Scaffold(
            body: TvPanelOptionList(panelKey: 'quality', options: options),
          ),
        );
      }

      final initialOptions = <TvPanelOption>[
        TvPanelOption(label: '自动', selected: true, onTap: () {}),
        TvPanelOption(label: '1080P', selected: false, onTap: () {}),
      ];
      await tester.pumpWidget(buildPanel(initialOptions));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        buildPanel(<TvPanelOption>[
          ...initialOptions,
          TvPanelOption(label: '720P', selected: false, onTap: () {}),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_自动');
      expect(find.text('720P'), findsOneWidget);
    });
  });

  group('能力缺省渲染（§6.4）', () {
    testWidgets('未声明内容面板时不渲染 tab 区', (tester) async {
      await pumpShell(tester);

      expect(find.byType(PlaybackContextTabs), findsNothing);
      expect(find.text('简介'), findsNothing);
    });

    testWidgets('仅简介无评论时只渲染一个 tab', (tester) async {
      final binding = MediaPlaybackBinding(
        contentSurfacesBuilder: (_) => _IntroOnlySurfaces(),
      );
      await pumpShell(tester, binding: binding);

      expect(find.byType(PlaybackContextTabs), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('playback-intro-tab')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
        findsNothing,
      );
    });

    testWidgets('未声明弹幕时无 overlay 挂载', (tester) async {
      await pumpShell(tester);
      expect(find.byType(MediaDanmakuLayer), findsNothing);
      expect(
        tester
            .widget<vesper_ui.VesperPlayerStage>(
              find.byType(vesper_ui.VesperPlayerStage),
            )
            .contentOverlay,
        isNull,
      );
    });

    testWidgets('声明弹幕时通过 SDK contentOverlay 挂载', (tester) async {
      final adapter = _ShellAdapter(danmakuProvider: _EmptyDanmakuProvider());
      await pumpShell(tester, adapter: adapter);

      expect(find.byType(MediaDanmakuLayer), findsOneWidget);
      expect(
        tester
            .widget<vesper_ui.VesperPlayerStage>(
              find.byType(vesper_ui.VesperPlayerStage),
            )
            .contentOverlay,
        isA<MediaDanmakuLayer>(),
      );
    });

    testWidgets('横屏控制栏按播放、弹幕、字幕、倍速、画质、全屏排序', (tester) async {
      final adapter = _ShellAdapter(danmakuProvider: _EmptyDanmakuProvider());
      final snapshot = _shellSnapshot.copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsSubtitleTrackSelection: true,
        ),
      );
      final harness = await pumpShell(
        tester,
        adapter: adapter,
        initialSnapshot: snapshot,
        danmakuSettingsSurface: const SizedBox(
          key: ValueKey<String>('host-danmaku-settings'),
        ),
      );
      harness.viewModel.setFullscreen(true);
      await tester.pumpAndSettle();

      final play = find.byIcon(Icons.play_arrow_rounded);
      final toggle = find.byKey(const ValueKey<String>('toggle-danmaku'));
      final danmakuSettings = find.byKey(
        const ValueKey<String>('open-danmaku-settings'),
      );
      final subtitleSettings = find.byKey(
        const ValueKey<String>('open-subtitle-settings'),
      );
      final pills = find.byType(vesper_ui.VesperStagePillButton);
      final fullscreen = find.byIcon(Icons.fullscreen_exit_rounded);

      expect(
        find.byKey(const ValueKey<String>('landscape-control-bar-leading')),
        findsOneWidget,
      );
      expect(play, findsOneWidget);
      expect(toggle, findsOneWidget);
      expect(danmakuSettings, findsOneWidget);
      expect(subtitleSettings, findsOneWidget);
      expect(pills, findsNWidgets(2));
      expect(fullscreen, findsOneWidget);
      expect(tester.getCenter(play).dx, lessThan(tester.getCenter(toggle).dx));
      expect(
        tester.getCenter(toggle).dx,
        lessThan(tester.getCenter(danmakuSettings).dx),
      );
      expect(
        tester.getCenter(danmakuSettings).dx,
        lessThan(tester.getCenter(subtitleSettings).dx),
      );
      expect(
        tester.getCenter(subtitleSettings).dx,
        lessThan(tester.getCenter(pills.first).dx),
      );
      expect(
        tester.getCenter(pills.first).dx,
        lessThan(tester.getCenter(pills.last).dx),
      );
      expect(
        tester.getCenter(pills.last).dx,
        lessThan(tester.getCenter(fullscreen).dx),
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('横屏无可用宿主能力时插槽不占位', (tester) async {
      final harness = await pumpShell(tester);
      harness.viewModel.setFullscreen(true);
      await tester.pumpAndSettle();

      final stage = tester.widget<vesper_ui.VesperPlayerStage>(
        find.byType(vesper_ui.VesperPlayerStage),
      );
      expect(stage.landscapeControlBarLeading, isNull);
      expect(
        find.byKey(const ValueKey<String>('landscape-control-bar-leading')),
        findsNothing,
      );
    });

    testWidgets('弹幕抽屉独立显示并在打开期间保持控制层', (tester) async {
      final adapter = _ShellAdapter(danmakuProvider: _EmptyDanmakuProvider());
      final harness = await pumpShell(
        tester,
        adapter: adapter,
        danmakuSettingsSurface: const SizedBox(
          key: ValueKey<String>('host-danmaku-settings'),
          child: Text('宿主弹幕设置'),
        ),
      );
      harness.viewModel.setFullscreen(true);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('open-danmaku-settings')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('danmaku-settings-drawer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('host-danmaku-settings')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<vesper_ui.VesperPlayerStage>(
              find.byType(vesper_ui.VesperPlayerStage),
            )
            .keepControlsVisible,
        isTrue,
      );

      Navigator.of(
        tester.element(
          find.byKey(const ValueKey<String>('danmaku-settings-drawer')),
        ),
      ).pop();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<vesper_ui.VesperPlayerStage>(
              find.byType(vesper_ui.VesperPlayerStage),
            )
            .keepControlsVisible,
        isFalse,
      );
    });

    testWidgets('播放器标题返回键按当前显示模式切换语义', (tester) async {
      final harness = await pumpShell(tester);
      var stage = tester.widget<vesper_ui.VesperPlayerStage>(
        find.byType(vesper_ui.VesperPlayerStage),
      );
      expect(stage.navigateBackSemanticLabel, '返回上一页');

      harness.viewModel.setFullscreen(true);
      await tester.pumpAndSettle();
      stage = tester.widget<vesper_ui.VesperPlayerStage>(
        find.byType(vesper_ui.VesperPlayerStage),
      );
      expect(stage.navigateBackSemanticLabel, '退出全屏');
      stage.onNavigateBack!();
      await tester.pumpAndSettle();
      expect(harness.viewModel.isFullscreen, isFalse);
    });

    testWidgets('手机弹幕按钮切换当前播放页的显示状态', (tester) async {
      final adapter = _ShellAdapter(danmakuProvider: _EmptyDanmakuProvider());
      await pumpShell(
        tester,
        adapter: adapter,
        surfaceSize: const Size(390, 844),
      );

      expect(
        tester
            .widget<MediaDanmakuLayer>(find.byType(MediaDanmakuLayer))
            .settings
            .enabled,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey<String>('toggle-danmaku')));
      await tester.pump();

      expect(
        tester
            .widget<MediaDanmakuLayer>(find.byType(MediaDanmakuLayer))
            .settings
            .enabled,
        isFalse,
      );
      expect(find.bySemanticsLabel('开启弹幕'), findsOneWidget);
    });

    testWidgets('TV 提供显示开关和简化设置，但不挂载评论或互动输入', (tester) async {
      final adapter = _ShellAdapter(danmakuProvider: _EmptyDanmakuProvider());
      final settings = ValueNotifier<MediaDanmakuOverlaySettings>(
        const MediaDanmakuOverlaySettings(),
      );
      addTearDown(settings.dispose);
      final binding = MediaPlaybackBinding(
        contentSurfacesBuilder: (_) => _EntryAwareSurfaces(),
      );
      const tvEntry = MediaPlaybackEntry(
        entryId: '22',
        pageNumber: 2,
        title: 'P2',
        durationSeconds: 120,
      );
      const tvTarget = MediaPlaybackTarget(
        detail: MediaDetail(
          mediaId: 'BV1TV',
          title: 'TV 弹幕测试',
          coverUrl: '',
          pages: <MediaPlaybackEntry>[tvEntry],
        ),
        entry: tvEntry,
      );
      await pumpShell(
        tester,
        adapter: adapter,
        binding: binding,
        playbackTarget: tvTarget,
        presentationMode: MediaPlaybackPresentationMode.tv,
        surfaceSize: const Size(1920, 1080),
        danmakuSettingsListenable: settings,
        onDanmakuSettingsChanged: (value) => settings.value = value,
      );

      expect(find.byType(MediaDanmakuLayer), findsOneWidget);
      expect(find.byType(PlaybackContextTabs), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
        findsNothing,
      );
      expect(find.byType(TextField), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('toggle-danmaku')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('open-danmaku-settings')),
        findsOneWidget,
      );
      expect(find.text('弹幕已开'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('toggle-danmaku')));
      await tester.pump();
      expect(find.text('弹幕已关'), findsOneWidget);
      expect(
        tester
            .widget<MediaDanmakuLayer>(find.byType(MediaDanmakuLayer))
            .settings
            .enabled,
        isFalse,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('open-danmaku-settings')),
      );
      await tester.pumpAndSettle();

      expect(find.text('弹幕设置'), findsWidgets);
      final optionLabels = tester
          .widget<TvPanelOptionList>(find.byType(TvPanelOptionList))
          .options
          .map((option) => option.label);
      expect(
        optionLabels,
        containsAll(<String>[
          '滚动弹幕',
          '顶部弹幕',
          '底部弹幕',
          '字幕弹幕',
          '高级弹幕',
          '彩色弹幕',
          '区域 3/4',
          '透明度 80%',
          '字号 标准',
          '密度 标准',
        ]),
      );
      expect(find.byType(TextField), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_滚动弹幕');

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(settings.value.showScroll, isFalse);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_panel_滚动弹幕');
    });

    testWidgets('未声明 DLNA 时 Android 不显示投屏按钮', (tester) async {
      await pumpShell(tester);

      expect(find.byType(StageDlnaProjectionButton), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('声明 DLNA 时 Android 显示投屏按钮', (tester) async {
      final adapter = _ShellAdapter(
        dlnaConfig: const MediaDlnaConfig(
          formatAdaptation: mediaDlnaFormatAdaptationConfig,
        ),
      );
      await pumpShell(tester, adapter: adapter);

      expect(find.byType(StageDlnaProjectionButton), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('设备控制与历史接缝', () {
    testWidgets('注入的设备控制传递到播放器 stage', (tester) async {
      final controls = _ShellDeviceControls();
      await pumpShell(tester, deviceControls: controls);

      final stage = tester.widget<vesper_ui.VesperPlayerStage>(
        find.byType(vesper_ui.VesperPlayerStage),
      );
      expect(stage.deviceControls, same(controls));
    });

    testWidgets('历史存储回退到 adapter.history', (tester) async {
      final history = _ShellHistoryStore();
      final adapter = _ShellAdapter(historyStore: history);
      final harness = await pumpShell(tester, adapter: adapter);

      expect(harness.viewModel.historyStore, same(history));
    });

    testWidgets('未显式初始位置时按历史进度续播', (tester) async {
      final history = _ShellHistoryStore(latestPositionMs: 30000);
      final adapter = _ShellAdapter(historyStore: history);
      final harness = await pumpShell(tester, adapter: adapter);

      expect(harness.platform.seekDeltas, <int>[30000]);
    });

    testWidgets('显式初始位置优先于历史进度', (tester) async {
      final history = _ShellHistoryStore(latestPositionMs: 30000);
      final adapter = _ShellAdapter(historyStore: history);
      final harness = await pumpShell(
        tester,
        adapter: adapter,
        initialPositionMs: 5000,
      );

      expect(harness.platform.seekDeltas, <int>[5000]);
    });

    testWidgets('慢历史查询期间切换分 P 时不应用旧进度', (tester) async {
      final history = _ShellHistoryStore()..gate = Completer<int?>();
      final adapter = _ShellAdapter(historyStore: history);
      final harness = await pumpShell(tester, adapter: adapter);
      await tester.pump();

      // 查询挂起期间切换分 P。
      await harness.viewModel.switchEntry(
        const MediaPlaybackEntry(
          entryId: '22',
          pageNumber: 2,
          title: 'P2',
          durationSeconds: 60,
        ),
      );
      await tester.pump();
      history.gate!.complete(30000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        harness.platform.seekDeltas,
        isEmpty,
        reason: '旧分 P 的历史进度不得应用到新 source',
      );
    });

    testWidgets('切分 P 的 selectSource 窗口内释放的历史查询不应用旧进度', (tester) async {
      final history = _ShellHistoryStore()..gate = Completer<int?>();
      final adapter = _ShellAdapter(historyStore: history);
      final harness = await pumpShell(tester, adapter: adapter);
      await tester.pump();

      // selectSource 挂起：切分 P 进入 selectSource 后、_selectedEntry
      // 更新前的窗口内，历史查询返回（entryId 校验仍会通过）。
      final selectGate = Completer<void>();
      harness.platform.selectSourceGate = selectGate;
      final switchFuture = harness.viewModel.switchEntry(
        const MediaPlaybackEntry(
          entryId: '22',
          pageNumber: 2,
          title: 'P2',
          durationSeconds: 60,
        ),
      );
      await tester.pump();

      history.gate!.complete(30000);
      await tester.pump();

      selectGate.complete();
      await switchFuture;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        harness.platform.seekDeltas,
        isEmpty,
        reason: 'selectSource 窗口内返回的旧进度不得 seek 到新 source',
      );
    });

    testWidgets('慢历史查询返回时不覆盖用户已 seek 的位置', (tester) async {
      final history = _ShellHistoryStore()..gate = Completer<int?>();
      final adapter = _ShellAdapter(historyStore: history);
      final harness = await pumpShell(tester, adapter: adapter);
      await tester.pump();

      // 查询挂起期间用户 seek（经 VM 入口，递增用户操作代际）。
      await harness.viewModel.seekToRatio(0.5);
      await tester.pump();
      history.gate!.complete(30000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        harness.platform.seekDeltas,
        isEmpty,
        reason: '慢 IO 返回后不得覆盖用户已 seek 的位置',
      );
    });

    testWidgets('主播放器进度条拖动使在途历史续播失效', (tester) async {
      final history = _ShellHistoryStore()..gate = Completer<int?>();
      final adapter = _ShellAdapter(historyStore: history);
      final harness = await pumpShell(tester, adapter: adapter);
      await tester.pump();

      // 舞台时间轴：SDK stage 内部直接调 controller.seekToRatio，
      // 经 seek 感知代理递增用户操作代际（tap 即提交 seek）。
      final scrubber = find.byType(vesper_ui.VesperTimelineScrubber);
      expect(scrubber, findsWidgets);
      await tester.tap(scrubber.first);
      await tester.pump();

      history.gate!.complete(30000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        harness.platform.seekDeltas,
        isEmpty,
        reason: 'stage 手势 seek 应使在途历史续播失效',
      );
    });

    testWidgets('回到直播（seekToLiveEdge）使在途历史续播失效', (tester) async {
      final history = _ShellHistoryStore()..gate = Completer<int?>();
      final adapter = _ShellAdapter(historyStore: history);
      final harness = await pumpShell(tester, adapter: adapter);
      await tester.pump();

      // SDK Stage 的"回到直播"直接调 controller.seekToLiveEdge（代理拦截）。
      await harness.viewModel.controller!.seekToLiveEdge();
      await tester.pump();
      history.gate!.complete(30000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        harness.platform.seekDeltas,
        isEmpty,
        reason: 'seekToLiveEdge 应使在途历史续播失效',
      );
    });

    testWidgets('dispose 后公开 controller 清空', (tester) async {
      final harness = await pumpShell(tester);
      expect(harness.viewModel.controller, isNotNull);

      harness.viewModel.dispose();
      expect(
        harness.viewModel.controller,
        isNull,
        reason: 'dispose 后不得泄漏已销毁的代理实例',
      );
    });

    testWidgets('过时代际创建以取消错误结束且不泄漏已销毁实例', (tester) async {
      final adapter = _ShellAdapter()..resolveGate = Completer<void>();
      final fakePlatform = installEnvironment(tester);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final viewModel = MediaPlaybackViewModel(
        detail: target.detail,
        initialEntry: target.entry,
        adapter: adapter,
      );
      addTearDown(viewModel.dispose);
      final oldFuture = viewModel.controllerFuture;

      // reload 使旧创建链过时；两条链都挂在同一个 resolve gate 上。
      viewModel.reloadCurrentPage();
      final newFuture = viewModel.controllerFuture;
      adapter.resolveGate!.complete();
      await tester.pump();
      for (var round = 0; round < 3; round += 1) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump();
      }

      // 新链成功（可播放的代理实例）。
      final controller = await newFuture;
      expect(controller, isNotNull);
      expect(viewModel.controller, same(controller));

      // 旧链创建的实例已被 dispose（不泄漏给调用方）。
      expect(fakePlatform.disposeCalls, 1);

      // 旧链以取消错误结束（调用方不应收到已销毁实例）。
      await expectLater(
        oldFuture,
        throwsA(isA<Exception>()),
        reason: '过时代际应以取消错误结束',
      );
    });

    testWidgets('seek 失败返回错误消息而非伪装成功', (tester) async {
      // SDK 会把平台异常经 FlutterError.reportError 上报（测试环境会
      // 视为测试失败），这里拦截以验证错误传播链。
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() {
        FlutterError.onError = previousOnError;
      });

      final harness = await pumpShell(tester);
      harness.platform.failSeekToRatio = true;

      final message = await harness.viewModel.seekToRatio(0.5);
      expect(message, isNotNull);
      expect(message, contains('跳转失败'));
      expect(reported, isNotEmpty, reason: 'SDK 应上报平台操作异常');
    });
  });

  group('评论面板可用性（§6.4）', () {
    testWidgets('切换分 P 后评论 tab 随能力出现', (tester) async {
      final binding = MediaPlaybackBinding(
        contentSurfacesBuilder: (_) => _EntryAwareSurfaces(),
      );
      final harness = await pumpShell(tester, binding: binding);
      await tester.pump();

      // entry '11'：无评论 → 单 tab。
      expect(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('playback-intro-tab')),
        findsOneWidget,
      );

      // 切换分 P 到 '22'：有评论 → 评论 tab 出现。
      await harness.viewModel.switchEntry(
        const MediaPlaybackEntry(
          entryId: '22',
          pageNumber: 2,
          title: 'P2',
          durationSeconds: 60,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
        findsOneWidget,
      );

      // 激活评论 tab 后内容可见。
      await tester.tap(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
      );
      await tester.pumpAndSettle();
      expect(find.text('第二分 P 的评论'), findsOneWidget);
    });

    testWidgets('正在查看评论时切到无评论 entry 不留残留状态', (tester) async {
      final binding = MediaPlaybackBinding(
        contentSurfacesBuilder: (_) => _EntryAwareSurfaces(),
      );
      final harness = await pumpShell(tester, binding: binding);
      await tester.pump();

      // 切到有评论分 P 并激活评论 tab。
      await harness.viewModel.switchEntry(
        const MediaPlaybackEntry(
          entryId: '22',
          pageNumber: 2,
          title: 'P2',
          durationSeconds: 60,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
      );
      await tester.pumpAndSettle();
      expect(find.text('第二分 P 的评论'), findsOneWidget);

      // 反向切回无评论分 P：评论 tab 消失、无残留（选中态/回复面板
      // 重置），渲染无异常。
      await harness.viewModel.switchEntry(
        const MediaPlaybackEntry(
          entryId: '11',
          pageNumber: 1,
          title: 'P1',
          durationSeconds: 120,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('playback-intro-tab')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // 再切回有评论分 P：评论 tab 恢复且可正常激活。
      await harness.viewModel.switchEntry(
        const MediaPlaybackEntry(
          entryId: '22',
          pageNumber: 2,
          title: 'P2',
          durationSeconds: 60,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
      );
      await tester.pumpAndSettle();
      expect(find.text('第二分 P 的评论'), findsOneWidget);
    });

    testWidgets('评论 builder 返回 null 时不渲染评论 tab', (tester) async {
      final binding = MediaPlaybackBinding(
        contentSurfacesBuilder: (_) => _NullCommentsSurfaces(),
      );
      await pumpShell(tester, binding: binding);

      expect(find.byType(PlaybackContextTabs), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('playback-comments-tab')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('playback-intro-tab')),
        findsOneWidget,
      );
    });
  });
}

class _ShellHarness {
  _ShellHarness({required this.viewModel, required this.platform});

  final MediaPlaybackViewModel viewModel;
  final _ShellFakePlatform platform;
}

final _shellPresentation = MediaPlaybackPresentation(
  enterPlaybackTv: () async {},
  enterPlaybackPhone: () async {},
  enterFullscreen: () async {},
  exitFullscreen: () async {},
  restoreApp: () async {},
);

final _shellSnapshot = VesperPlayerSnapshot(
  title: '壳测试视频',
  subtitle: 'P1 · P1',
  sourceLabel: 'shell-test',
  playbackState: VesperPlaybackState.ready,
  playbackRate: 1,
  isBuffering: false,
  isInterrupted: false,
  hasVideoSurface: true,
  timeline: VesperTimeline(
    kind: VesperTimelineKind.vod,
    isSeekable: true,
    seekableRange: null,
    liveEdgeMs: null,
    positionMs: 0,
    durationMs: 120000,
  ),
  trackCatalog: const VesperTrackCatalog(tracks: <VesperMediaTrack>[]),
);

final class _ShellAdapter extends MediaPlatformAdapter {
  _ShellAdapter({
    this.danmakuProvider,
    this.historyStore,
    this.dlnaConfig,
    this.qualityOptions = const <MediaQualityOption>[],
    this.qualityPolicy = const MediaQualityPolicy(),
    this.supportsAudioOnly = true,
    this.versionSourcesByResolveCall = false,
  });

  final MediaDanmakuProvider? danmakuProvider;
  final MediaHistoryStore? historyStore;
  @override
  final MediaDlnaConfig? dlnaConfig;
  final List<MediaQualityOption> qualityOptions;
  @override
  final MediaQualityPolicy qualityPolicy;
  final bool supportsAudioOnly;
  final bool versionSourcesByResolveCall;

  /// 非空时 resolvePlayback 挂起，由测试手动完成（模拟慢解析/过时代际）。
  Completer<void>? resolveGate;
  int resolveCallCount = 0;

  @override
  Future<ResolvedMediaPlayback> resolvePlayback({
    required MediaDetail detail,
    required MediaPlaybackEntry entry,
  }) async {
    resolveCallCount += 1;
    final gate = resolveGate;
    if (gate != null) {
      await gate.future;
    }
    final versionSuffix = versionSourcesByResolveCall
        ? '-$resolveCallCount'
        : '';
    return ResolvedMediaPlayback(
      title: detail.title,
      subtitle: 'P${entry.pageNumber} · ${entry.title}',
      uri: 'https://example.test/shell$versionSuffix.mp4',
      protocol: VesperPlayerSourceProtocol.progressive,
      transportLabel: 'shell',
      isLocalFile: false,
      qualityOptions: qualityOptions,
      supportsCodecSelection: qualityPolicy.supportsCodecSelection,
      audioOnlySource: supportsAudioOnly
          ? ResolvedMediaSourceVariant(
              uri:
                  'https://example.test/${entry.entryId}-audio$versionSuffix.mpd',
              protocol: VesperPlayerSourceProtocol.dash,
              transportLabel: 'shell audio only',
              isLocalFile: false,
            )
          : null,
    );
  }

  @override
  MediaDanmakuProvider? get danmaku => danmakuProvider;

  @override
  MediaHistoryStore? get history => historyStore;
}

final class _IntroOnlySurfaces implements MediaContentSurfaces {
  @override
  String get introTabLabel => '简介';

  @override
  String? get commentsTabLabel => null;

  @override
  Widget buildIntroSurface(
    BuildContext context,
    MediaPlaybackTarget target,
    MediaSurfaceHost host,
  ) {
    return const Padding(padding: EdgeInsets.all(16), child: Text('仅有简介的面板'));
  }

  @override
  Widget? buildCommentsSurface(
    BuildContext context,
    MediaPlaybackTarget target,
  ) {
    return null;
  }
}

final class _EmptyDanmakuProvider implements MediaDanmakuProvider {
  @override
  MediaDanmakuSession openSession(MediaPlaybackTarget target) {
    return const _EmptyDanmakuSession();
  }
}

final class _EmptyDanmakuSession implements MediaDanmakuSession {
  const _EmptyDanmakuSession();

  @override
  Stream<MediaDanmakuSnapshot> get snapshots =>
      const Stream<MediaDanmakuSnapshot>.empty();

  @override
  void updatePosition(int positionMs) {}

  @override
  Future<void> close() async {}
}

final class _NullCommentsSurfaces implements MediaContentSurfaces {
  @override
  String get introTabLabel => '简介';

  @override
  String? get commentsTabLabel => '评论';

  @override
  Widget buildIntroSurface(
    BuildContext context,
    MediaPlaybackTarget target,
    MediaSurfaceHost host,
  ) {
    return const Padding(padding: EdgeInsets.all(16), child: Text('仅有简介的面板'));
  }

  @override
  Widget? buildCommentsSurface(
    BuildContext context,
    MediaPlaybackTarget target,
  ) {
    return null;
  }
}

/// 评论能力随 entry 变化的面板：entry '22' 有评论，其余没有。
final class _EntryAwareSurfaces implements MediaContentSurfaces {
  @override
  String get introTabLabel => '简介';

  @override
  String? get commentsTabLabel => '评论';

  @override
  Widget buildIntroSurface(
    BuildContext context,
    MediaPlaybackTarget target,
    MediaSurfaceHost host,
  ) {
    return const Padding(padding: EdgeInsets.all(16), child: Text('仅有简介的面板'));
  }

  @override
  Widget? buildCommentsSurface(
    BuildContext context,
    MediaPlaybackTarget target,
  ) {
    return target.entry.entryId == '22'
        ? const Padding(padding: EdgeInsets.all(16), child: Text('第二分 P 的评论'))
        : null;
  }
}

final class _ShellHistoryStore implements MediaHistoryStore {
  _ShellHistoryStore({this.latestPositionMs});

  final int? latestPositionMs;

  /// 非空时最新一次查询挂起，由测试手动完成（模拟慢 IO）。
  Completer<int?>? gate;

  @override
  Future<List<MediaHistoryEntry>> loadEntries() async {
    return const <MediaHistoryEntry>[];
  }

  @override
  Future<void> saveEntry(MediaHistoryEntry entry) async {}

  @override
  Future<int?> latestPositionMsFor(String mediaId, String entryId) async {
    final gate = this.gate;
    if (gate != null) {
      return gate.future;
    }
    return latestPositionMs;
  }
}

final class _ShellDeviceControls implements MediaPlayerDeviceControls {
  @override
  Future<double?> currentBrightnessRatio() async => null;

  @override
  Future<double?> setBrightnessRatio(double ratio) async => null;

  @override
  Future<double?> currentVolumeRatio() async => null;

  @override
  Future<double?> setVolumeRatio(double ratio) async => null;
}

final class _ShellFakePlatform extends VesperPlayerPlatform {
  _ShellFakePlatform(VesperPlayerSnapshot snapshot) : _current = snapshot;

  VesperPlayerSnapshot _current;
  final StreamController<VesperPlayerEvent> _eventsController =
      StreamController<VesperPlayerEvent>.broadcast();
  final seekDeltas = <int>[];
  final seekRatios = <double>[];
  final selectedSources = <VesperPlayerSource>[];
  final playbackRates = <double>[];
  final abrPolicyCalls =
      <({VesperAbrPolicy policy, int? expectedCatalogRevision})>[];
  final systemPlaybackConfigurations = <VesperSystemPlaybackConfiguration>[];
  int playCalls = 0;
  int createCalls = 0;
  int disposeCalls = 0;
  int refreshCalls = 0;
  int selectSourceCalls = 0;
  int pauseCalls = 0;
  int failSelectSourceCallsRemaining = 0;
  int failPlayCallsRemaining = 0;
  final Map<int, Completer<void>> _disposeWaiters = <int, Completer<void>>{};
  Object? setAbrPolicyError;
  Object? setSubtitleSelectionError;
  Completer<void>? setAbrPolicyGate;
  Future<void> Function(VesperAbrPolicy policy)? setAbrPolicyHandler;
  VesperPlayerSnapshot? selectedSourceSuccessSnapshot;
  bool updateSnapshotOnCommands = false;

  /// 非空时 selectSource 挂起，由测试手动完成（模拟切源窗口）。
  Completer<void>? selectSourceGate;

  /// 为 true 时 seekToRatio 抛错（验证错误传播）。
  bool failSeekToRatio = false;

  /// 模拟播放推进/用户 seek 后的位置（经快照事件广播给 controller）。
  void emitPosition(int positionMs) {
    final current = _current;
    final next = current.copyWith(
      timeline: VesperTimeline(
        kind: current.timeline.kind,
        isSeekable: true,
        seekableRange: null,
        liveEdgeMs: null,
        positionMs: positionMs,
        durationMs: current.timeline.durationMs,
      ),
    );
    _current = next;
    _eventsController.add(
      VesperPlayerSnapshotEvent(playerId: 'shell-test-player', snapshot: next),
    );
  }

  void emitSnapshot(VesperPlayerSnapshot snapshot) {
    _current = snapshot;
    _eventsController.add(
      VesperPlayerSnapshotEvent(
        playerId: 'shell-test-player',
        snapshot: snapshot,
      ),
    );
  }

  void emitRuntimeTrackRejected(String trackId) {
    _eventsController.add(
      VesperPlayerWarningEvent(
        playerId: 'shell-test-player',
        warning: VesperRuntimeWarning.capability(
          VesperCapabilityWarning(
            reason: VesperCapabilityWarningReason.hdrNativeFrameUnsupported,
            reasonRawValue: 'runtimeTrackRejected',
            recommendedPlaybackPath: VesperRecommendedPlaybackPath.systemPlayer,
            hdrKind: VesperPlaybackCapabilityHdrKind.none,
            diagnostics: <String, Object?>{
              'code': 'runtimeTrackRejected',
              'trackId': trackId,
              'sourceEpoch': 1,
            },
          ),
        ),
      ),
    );
  }

  void emitRecoverableSourceError() {
    _eventsController.add(
      const VesperPlayerErrorEvent(
        playerId: 'shell-test-player',
        error: VesperPlayerError(
          message: '模拟播放地址失效',
          code: VesperPlayerErrorCode.invalidSource,
          category: VesperPlayerErrorCategory.source,
          retriable: true,
        ),
      ),
    );
  }

  @override
  Future<VesperPlatformCreateResult> createPlayer({
    VesperPlayerSource? initialSource,
    VesperPlayerRenderSurfaceKind renderSurfaceKind =
        VesperPlayerRenderSurfaceKind.auto,
    VesperPlaybackResiliencePolicy resiliencePolicy =
        const VesperPlaybackResiliencePolicy(),
    VesperTrackPreferencePolicy trackPreferencePolicy =
        const VesperTrackPreferencePolicy(),
    VesperPreloadBudgetPolicy preloadBudgetPolicy =
        const VesperPreloadBudgetPolicy(),
    bool keepScreenOnDuringPlayback = true,
    VesperBenchmarkConfiguration benchmarkConfiguration =
        const VesperBenchmarkConfiguration.disabled(),
    VesperSourceNormalizerConfiguration sourceNormalizerConfiguration =
        const VesperSourceNormalizerConfiguration(),
    VesperFrameProcessorConfiguration frameProcessorConfiguration =
        const VesperFrameProcessorConfiguration(),
    VesperNativeFramePipelineConfiguration nativeFramePipelineConfiguration =
        const VesperNativeFramePipelineConfiguration(),
    VesperPipelineEventHookConfiguration pipelineEventHookConfiguration =
        const VesperPipelineEventHookConfiguration(),
  }) async {
    createCalls += 1;
    return VesperPlatformCreateResult(
      playerId: 'shell-test-player',
      snapshot: _current,
    );
  }

  @override
  Stream<VesperPlayerEvent> eventsFor(String playerId) {
    return _eventsController.stream;
  }

  Future<void> closeEvents() => _eventsController.close();

  Future<void> waitForDisposeCalls(int expected) {
    if (disposeCalls >= expected) {
      return Future<void>.value();
    }
    return (_disposeWaiters[expected] ??= Completer<void>()).future;
  }

  @override
  Future<void> initialize(String playerId) async {}

  @override
  Future<void> dispose(String playerId) async {
    disposeCalls += 1;
    final completedWaiters = _disposeWaiters.entries
        .where((entry) => entry.key <= disposeCalls)
        .toList(growable: false);
    for (final entry in completedWaiters) {
      entry.value.complete();
      _disposeWaiters.remove(entry.key);
    }
  }

  @override
  Future<void> refreshPlayer(String playerId) async {
    refreshCalls += 1;
  }

  @override
  Future<void> selectSource(String playerId, VesperPlayerSource source) async {
    selectSourceCalls += 1;
    selectedSources.add(source);
    if (failSelectSourceCallsRemaining > 0) {
      failSelectSourceCallsRemaining -= 1;
      throw PlatformException(code: 'select-source-failed');
    }
    final gate = selectSourceGate;
    if (gate != null) {
      await gate.future;
    }
    final successSnapshot = selectedSourceSuccessSnapshot;
    if (successSnapshot != null) {
      emitSnapshot(successSnapshot);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> play(String playerId) async {
    playCalls += 1;
    if (failPlayCallsRemaining > 0) {
      failPlayCallsRemaining -= 1;
      throw PlatformException(code: 'play-failed');
    }
    if (updateSnapshotOnCommands) {
      emitSnapshot(
        _current.copyWith(playbackState: VesperPlaybackState.playing),
      );
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> pause(String playerId) async {
    pauseCalls += 1;
    if (updateSnapshotOnCommands) {
      emitSnapshot(
        _current.copyWith(playbackState: VesperPlaybackState.paused),
      );
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> togglePause(String playerId) async {}

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> setPictureInPictureConfiguration(
    String playerId,
    VesperPictureInPictureConfiguration configuration,
  ) async {}

  @override
  Future<void> requestPictureInPicture(
    String playerId, {
    VesperPictureInPictureConfiguration? configuration,
  }) async {}

  @override
  Future<void> exitPictureInPicture(String playerId) async {}

  @override
  Future<void> seekBy(String playerId, int deltaMs) async {
    seekDeltas.add(deltaMs);
    if (updateSnapshotOnCommands) {
      final timeline = _current.timeline;
      emitSnapshot(
        _current.copyWith(
          timeline: VesperTimeline(
            kind: timeline.kind,
            isSeekable: timeline.isSeekable,
            seekableRange: timeline.seekableRange,
            liveEdgeMs: timeline.liveEdgeMs,
            positionMs: timeline.positionMs + deltaMs,
            durationMs: timeline.durationMs,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> seekToRatio(String playerId, double ratio) async {
    if (failSeekToRatio) {
      throw PlatformException(code: 'seek-failed', message: '模拟 seek 失败');
    }
    seekRatios.add(ratio);
    if (updateSnapshotOnCommands) {
      final timeline = _current.timeline;
      final durationMs = timeline.durationMs;
      if (durationMs != null && durationMs > 0) {
        emitSnapshot(
          _current.copyWith(
            timeline: VesperTimeline(
              kind: timeline.kind,
              isSeekable: timeline.isSeekable,
              seekableRange: timeline.seekableRange,
              liveEdgeMs: timeline.liveEdgeMs,
              positionMs: (durationMs * ratio).round(),
              durationMs: durationMs,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  @override
  Future<void> seekToLiveEdge(String playerId) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double rate) async {
    playbackRates.add(rate);
    if (updateSnapshotOnCommands) {
      emitSnapshot(_current.copyWith(playbackRate: rate));
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> setVideoTrackSelection(
    String playerId,
    VesperTrackSelection selection,
  ) async {}

  @override
  Future<void> setAudioTrackSelection(
    String playerId,
    VesperTrackSelection selection,
  ) async {}

  @override
  Future<void> setSubtitleTrackSelection(
    String playerId,
    VesperTrackSelection selection,
  ) async {
    final error = setSubtitleSelectionError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setAbrPolicy(
    String playerId,
    VesperAbrPolicy policy, {
    int? expectedCatalogRevision,
  }) async {
    abrPolicyCalls.add((
      policy: policy,
      expectedCatalogRevision: expectedCatalogRevision,
    ));
    final gate = setAbrPolicyGate;
    if (gate != null) {
      await gate.future;
    }
    final handler = setAbrPolicyHandler;
    if (handler != null) {
      await handler(policy);
    }
    final error = setAbrPolicyError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setResiliencePolicy(
    String playerId,
    VesperPlaybackResiliencePolicy policy,
  ) async {}

  @override
  Future<void> updateViewport(
    String playerId,
    VesperPlayerViewport viewport,
  ) async {}

  @override
  Future<void> clearViewport(String playerId) async {}

  @override
  Future<void> configureSystemPlayback(
    String playerId,
    VesperSystemPlaybackConfiguration configuration,
  ) async {
    systemPlaybackConfigurations.add(configuration);
  }

  @override
  Future<void> clearSystemPlayback(String playerId) async {}

  @override
  Future<VesperSystemPlaybackPermissionStatus>
  getSystemPlaybackPermissionStatus() async {
    return VesperSystemPlaybackPermissionStatus.notRequired;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
