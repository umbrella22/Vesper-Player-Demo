part of '../widget_test.dart';

void _registerOfflineCacheWidgetTests() {
  testWidgets('offline cache page renders active task progress', (
    WidgetTester tester,
  ) async {
    final controller = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[
        BiliOfflineDownloadEntry(
          metadata: const BiliOfflineDownloadMetadata(
            assetId: 'asset-1',
            taskId: 1,
            bvid: 'BV1',
            cid: 11,
            videoTitle: '缓存视频',
            pageTitle: 'P1 · 正片',
            coverUrl: '',
            qualityLabel: '1080P',
            createdAtMs: 100,
          ),
          task: const VesperDownloadTaskSnapshot(
            taskId: 1,
            assetId: 'asset-1',
            source: VesperDownloadSource(
              source: VesperPlayerSource(
                uri: 'vesper-generated://dash/manifest.mpd',
                label: '缓存视频',
                kind: VesperPlayerSourceKind.local,
                protocol: VesperPlayerSourceProtocol.dash,
              ),
              contentFormat: VesperDownloadContentFormat.dashSegments,
            ),
            profile: VesperDownloadProfile(
              targetOutputFormat: VesperDownloadOutputFormat.mp4,
            ),
            state: VesperDownloadState.downloading,
            progress: VesperDownloadProgressSnapshot(
              receivedBytes: 512,
              totalBytes: 1024,
            ),
            assetIndex: VesperDownloadAssetIndex(
              contentFormat: VesperDownloadContentFormat.dashSegments,
            ),
          ),
        ),
      ],
      storageUsage: const BiliOfflineStorageUsage(
        cacheBytes: 2 * 1024 * 1024,
        freeBytes: 8 * 1024 * 1024,
        totalBytes: 10 * 1024 * 1024,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await tester.pump();

    expect(find.text('离线缓存'), findsOneWidget);
    expect(find.text('存储空间'), findsOneWidget);
    expect(find.text('缓存占用'), findsOneWidget);
    expect(find.text('剩余空间'), findsOneWidget);
    expect(find.text('正在缓存'), findsOneWidget);
    expect(find.text('缓存视频'), findsOneWidget);
    expect(find.textContaining('缓存中'), findsOneWidget);
  });

  testWidgets('offline cache task action pending state is per task', (
    WidgetTester tester,
  ) async {
    final pauseCompleter = Completer<void>();
    final controller = _FakeOfflineController(<BiliOfflineDownloadEntry>[
      _offlineEntry(
        assetId: 'asset-1',
        taskId: 1,
        title: '缓存视频 A',
        state: VesperDownloadState.downloading,
        createdAtMs: 200,
      ),
      _offlineEntry(
        assetId: 'asset-2',
        taskId: 2,
        title: '缓存视频 B',
        state: VesperDownloadState.downloading,
        createdAtMs: 100,
      ),
    ])..pauseCompleter = pauseCompleter;

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('offline-task-action-1')),
    );
    await tester.pump();

    expect(controller.pausedTaskIds, <int>[1]);
    expect(
      find.byKey(const ValueKey<String>('offline-task-action-pending-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('offline-task-action-pending-2')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('offline-task-action-2')),
        matching: find.byIcon(AppIcons.pauseFill),
      ),
      findsOneWidget,
    );

    await tester.runAsync(() async {
      pauseCompleter.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('offline-task-action-pending-1')),
      findsNothing,
    );
  });

  testWidgets('offline cache page confirms deletion on end-to-start swipe', (
    WidgetTester tester,
  ) async {
    final controller = _FakeOfflineController(
      <BiliOfflineDownloadEntry>[
        BiliOfflineDownloadEntry(
          metadata: const BiliOfflineDownloadMetadata(
            assetId: 'asset-1',
            taskId: 1,
            bvid: 'BV1',
            cid: 11,
            videoTitle: '缓存视频',
            pageTitle: 'P1 · 正片',
            coverUrl: '',
            qualityLabel: '1080P',
            createdAtMs: 100,
          ),
          task: const VesperDownloadTaskSnapshot(
            taskId: 1,
            assetId: 'asset-1',
            source: VesperDownloadSource(
              source: VesperPlayerSource(
                uri: 'file:///tmp/offline.mp4',
                label: '缓存视频',
                kind: VesperPlayerSourceKind.local,
                protocol: VesperPlayerSourceProtocol.file,
              ),
              contentFormat: VesperDownloadContentFormat.singleFile,
            ),
            profile: VesperDownloadProfile(
              targetOutputFormat: VesperDownloadOutputFormat.mp4,
            ),
            state: VesperDownloadState.completed,
            progress: VesperDownloadProgressSnapshot(
              receivedBytes: 1024,
              totalBytes: 1024,
            ),
            assetIndex: VesperDownloadAssetIndex(
              contentFormat: VesperDownloadContentFormat.singleFile,
              completedPath: '/tmp/offline.mp4',
            ),
          ),
        ),
      ],
      storageUsage: const BiliOfflineStorageUsage(
        cacheBytes: 1024,
        freeBytes: 8 * 1024 * 1024,
        totalBytes: 8 * 1024 * 1024,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await tester.pump();

    expect(find.byTooltip('更多'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('offline-task-action-1')),
      findsNothing,
    );
    await tester.drag(find.byType(Dismissible), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除缓存？'), findsNothing);
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(controller.removedAssetIds, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('缓存视频'), findsOneWidget);
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(controller.removedAssetIds, <String>['asset-1']);
    expect(find.text('缓存视频'), findsNothing);
    expect(find.text('还没有离线缓存'), findsOneWidget);
  });

  testWidgets('offline cache menu confirms deletion of the selected item', (
    WidgetTester tester,
  ) async {
    final controller = _FakeOfflineController(<BiliOfflineDownloadEntry>[
      BiliOfflineDownloadEntry(
        metadata: const BiliOfflineDownloadMetadata(
          assetId: 'asset-1',
          taskId: 1,
          bvid: 'BV1',
          cid: 11,
          videoTitle: '缓存视频',
          pageTitle: 'P1 · 正片',
          coverUrl: '',
          qualityLabel: '1080P',
          outputPath: '/tmp/offline.mp4',
          createdAtMs: 100,
        ),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: OfflineCachePage(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.byIcon(AppIcons.more2Fill));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('导出到相册'), findsOneWidget);
    expect(find.text('导出为可在任意播放器中播放的 MP4'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除缓存？'), findsOneWidget);
    expect(controller.removedAssetIds, isEmpty);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(controller.removedAssetIds, ['asset-1']);
  });

  testWidgets(
    'offline cache delete dialog uses opaque readable surface and avoids duplicate storage error',
    (WidgetTester tester) async {
      for (final theme in [
        AppVisualTokens.mobileLightTheme(),
        AppVisualTokens.mobileDarkTheme(),
      ]) {
        final controller = _FakeOfflineController(
          <BiliOfflineDownloadEntry>[
            BiliOfflineDownloadEntry(
              metadata: const BiliOfflineDownloadMetadata(
                assetId: 'asset-delete-readable',
                taskId: 1,
                bvid: 'BV1',
                cid: 11,
                videoTitle: '缓存视频',
                pageTitle: 'P1 · 正片',
                coverUrl: '',
                qualityLabel: '1080P',
                outputPath: '/tmp/offline.mp4',
                createdAtMs: 100,
              ),
            ),
          ],
          storageError: const BiliOfflineDownloadException('无法读取设备存储空间。'),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: OfflineCachePage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('无法读取设备存储空间'), findsNothing);
        expect(find.text('无法读取设备存储空间。'), findsOneWidget);

        await tester.tap(find.byIcon(AppIcons.more2Fill));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();

        final dialog = find.byKey(
          const ValueKey<String>('media-readable-glass-dialog'),
        );
        expect(dialog, findsOneWidget);
        expect(find.byType(GlassDialog), findsNothing);
        expect(
          tester.widget<Material>(dialog).color!.a,
          equals(1.0),
        );
        expect(find.widgetWithText(FilledButton, '确认删除'), findsOneWidget);
        await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
        await tester.pumpAndSettle();
      }
    },
  );
}
