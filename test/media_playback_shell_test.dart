import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
      'io.github.ikaros.vesper_player_external_playback/events',
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

  Future<_ShellHarness> pumpShell(
    WidgetTester tester, {
    _ShellAdapter? adapter,
    Size surfaceSize = const Size(1200, 900),
    MediaPlaybackPresentationMode presentationMode =
        MediaPlaybackPresentationMode.phone,
    MediaPlayerDeviceControls? deviceControls,
    MediaHistoryStore? historyStore,
    int initialPositionMs = 0,
    VesperPlayerSnapshot? initialSnapshot,
  }) async {
    final fakePlatform = installEnvironment(
      tester,
      initialSnapshot: initialSnapshot,
    );
    final resolvedAdapter = adapter ?? _ShellAdapter();
    final viewModel = MediaPlaybackViewModel(
      detail: target.detail,
      initialEntry: target.entry,
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
          deviceControls: deviceControls ?? const MediaNoopDeviceControls(),
          presentation: _shellPresentation,
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

  group('互动动作槽（§6.3）', () {
    testWidgets('声明动作按顺序渲染，busy 动作禁用', (tester) async {
      final adapter = _ShellAdapter(
        engagementCapability: MediaEngagementCapability(
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
      await pumpShell(tester, adapter: adapter);

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
      final adapter = _ShellAdapter(
        engagementCapability: MediaEngagementCapability(
          actions: <MediaEngagementActionSpec>[
            MediaEngagementActionSpec(
              id: MediaEngagementActionId.favorite,
              label: '收藏',
              perform: () async => '已收藏',
            ),
          ],
        ),
      );
      await pumpShell(tester, adapter: adapter);

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
      final adapter = _ShellAdapter(surfaces: _IntroOnlySurfaces());
      await pumpShell(tester, adapter: adapter);

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
    });

    testWidgets('声明弹幕时挂载 overlay', (tester) async {
      final adapter = _ShellAdapter(danmakuProvider: _EmptyDanmakuProvider());
      await pumpShell(tester, adapter: adapter);

      expect(find.byType(MediaDanmakuLayer), findsOneWidget);
    });

    testWidgets(
      '未声明 DLNA 时 Android 不显示投屏按钮',
      (tester) async {
        await pumpShell(tester);

        expect(find.byType(StageDlnaProjectionButton), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      '声明 DLNA 时 Android 显示投屏按钮',
      (tester) async {
        final adapter = _ShellAdapter(
          dlnaConfig: const MediaDlnaConfig(
            formatAdaptation: mediaDlnaFormatAdaptationConfig,
          ),
        );
        await pumpShell(tester, adapter: adapter);

        expect(find.byType(StageDlnaProjectionButton), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
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
      final adapter = _ShellAdapter(surfaces: _EntryAwareSurfaces());
      final harness = await pumpShell(tester, adapter: adapter);
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
      final adapter = _ShellAdapter(surfaces: _EntryAwareSurfaces());
      final harness = await pumpShell(tester, adapter: adapter);
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
      final adapter = _ShellAdapter(surfaces: _NullCommentsSurfaces());
      await pumpShell(tester, adapter: adapter);

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

final class _ShellAdapter implements MediaPlatformAdapter {
  _ShellAdapter({
    this.engagementCapability,
    this.danmakuProvider,
    this.surfaces,
    this.historyStore,
    this.dlnaConfig,
    this.qualityOptions = const <MediaQualityOption>[],
    this.qualityPolicy = const MediaQualityPolicy(),
  });

  final MediaEngagementCapability? engagementCapability;
  final MediaDanmakuProvider? danmakuProvider;
  final MediaContentSurfaces? surfaces;
  final MediaHistoryStore? historyStore;
  @override
  final MediaDlnaConfig? dlnaConfig;
  final List<MediaQualityOption> qualityOptions;
  @override
  final MediaQualityPolicy qualityPolicy;

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
    return ResolvedMediaPlayback(
      title: detail.title,
      subtitle: 'P${entry.pageNumber} · ${entry.title}',
      uri: 'https://example.test/shell.mp4',
      protocol: VesperPlayerSourceProtocol.progressive,
      transportLabel: 'shell',
      isLocalFile: false,
      qualityOptions: qualityOptions,
      supportsCodecSelection: qualityPolicy.supportsCodecSelection,
    );
  }

  @override
  MediaEngagementCapability? get engagement => engagementCapability;

  @override
  MediaDanmakuProvider? get danmaku => danmakuProvider;

  @override
  MediaContentSurfaces? get contentSurfaces => surfaces;

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
  Stream<MediaDanmakuEvent> danmakuFor(MediaPlaybackTarget target) async* {}
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
  final abrPolicyCalls =
      <({VesperAbrPolicy policy, int? expectedCatalogRevision})>[];
  int playCalls = 0;
  int disposeCalls = 0;
  int refreshCalls = 0;
  int selectSourceCalls = 0;
  Object? setAbrPolicyError;
  Object? setSubtitleSelectionError;
  Completer<void>? setAbrPolicyGate;
  Future<void> Function(VesperAbrPolicy policy)? setAbrPolicyHandler;

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

  @override
  Future<void> initialize(String playerId) async {}

  @override
  Future<void> dispose(String playerId) async {
    disposeCalls += 1;
  }

  @override
  Future<void> refreshPlayer(String playerId) async {
    refreshCalls += 1;
  }

  @override
  Future<void> selectSource(String playerId, VesperPlayerSource source) async {
    selectSourceCalls += 1;
    final gate = selectSourceGate;
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<void> play(String playerId) async {
    playCalls += 1;
  }

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> togglePause(String playerId) async {}

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> seekBy(String playerId, int deltaMs) async {
    seekDeltas.add(deltaMs);
  }

  @override
  Future<void> seekToRatio(String playerId, double ratio) async {
    if (failSeekToRatio) {
      throw PlatformException(code: 'seek-failed', message: '模拟 seek 失败');
    }
  }

  @override
  Future<void> seekToLiveEdge(String playerId) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double rate) async {}

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
  ) async {}

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
