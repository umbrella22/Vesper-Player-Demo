import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/download/models/offline_download_models.dart';
import 'package:vesper_media/download/services/download_manager_host.dart';
import 'package:vesper_media/download/services/download_plugin_resolver.dart';
import 'package:vesper_media/download/services/offline_download_controller.dart';
import 'package:vesper_media/download/services/offline_download_store.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiliOfflineDownloadController deletion', () {
    late Directory root;
    late BiliOfflineDownloadStore store;
    late _FakeDownloadManagerHost manager;
    late BiliOfflineDownloadController controller;

    Future<void> createController({
      int? knownTaskId,
      bool removeResult = true,
      Object? disposeError,
      BiliClient? client,
      Future<void>? pluginGate,
      VesperDownloadState taskState = VesperDownloadState.completed,
      String? taskError,
      bool snapshotIncludesTask = false,
      Future<String?> Function({
        required Directory cacheRoot,
        required Iterable<String> candidates,
      })?
      cachePathResolver,
    }) async {
      root = await Directory.systemTemp.createTemp('bili-offline-remove-test-');
      // Controller 内部通过 path_provider 解析缓存根目录：mock 通道让
      // 它与测试目录一致，否则删除逻辑落在 systemTemp 下的其他位置。
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return root.path;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final pluginResolver = BiliDownloadPluginResolver(
        loader: () async {
          final gate = pluginGate;
          if (gate != null) {
            await gate;
          }
          return <VesperPluginReference>[
            VesperBundledPluginReferences.remuxFfmpeg,
          ];
        },
      );
      store = BiliOfflineDownloadStore(baseDirectory: root);
      manager = _FakeDownloadManagerHost(
        knownTaskId: knownTaskId,
        removeResult: removeResult,
        disposeError: disposeError,
        taskState: taskState,
        taskError: taskError,
        snapshotIncludesTask: snapshotIncludesTask,
      );
      controller = BiliOfflineDownloadController(
        client: client ?? BiliClient(),
        store: store,
        pluginResolver: pluginResolver,
        manager: manager,
        cachePathResolver:
            cachePathResolver ?? resolveBiliOfflineCachePathWithinRoot,
      );
    }

    Future<BiliOfflineDownloadMetadata> seedMetadata({
      int? taskId,
      int? episodeId,
      String? errorMessage,
    }) async {
      final metadata = BiliOfflineDownloadMetadata(
        assetId: 'bili-BV1xx411c7mD-11-q80-avc-audio30280',
        bvid: 'BV1xx411c7mD',
        cid: 11,
        videoTitle: '离线视频',
        pageTitle: 'P1 · 正片',
        coverUrl: '',
        qualityLabel: '1080P 高清',
        createdAtMs: 1,
        taskId: taskId,
        errorMessage: errorMessage,
        playbackMetadata: episodeId == null
            ? null
            : BiliOfflinePlaybackMetadata(
                aid: 1,
                pageNumber: 1,
                pageTitle: '',
                durationSeconds: 0,
                ownerMid: 1,
                ownerName: '',
                ownerAvatarUrl: '',
                description: '',
                episodeId: episodeId,
              ),
      );
      await store.saveEntries(<BiliOfflineDownloadMetadata>[metadata]);
      return metadata;
    }

    Future<void> seedAssetDirectory() async {
      final cacheRoot = Directory('${root.path}/vesper-player/offline-cache');
      await Directory(
        '${cacheRoot.path}/assets/bili-BV1xx411c7mD-11-q80-avc-audio30280',
      ).create(recursive: true);
    }

    test('removeEntry throws and keeps everything when removeTask fails', () async {
      await createController(knownTaskId: 42, removeResult: false);
      final metadata = await seedMetadata(taskId: 42);
      await seedAssetDirectory();
      await controller.initialize();

      final entry = controller.entries.single;
      await expectLater(
        controller.removeEntry(entry),
        throwsA(isA<BiliOfflineDownloadException>()),
      );

      expect(manager.removedTaskIds, <int>[42]);
      // 目录、元数据与内存状态都必须保留。
      expect(
        Directory(
          '${root.path}/vesper-player/offline-cache/assets/bili-BV1xx411c7mD-11-q80-avc-audio30280',
        ).existsSync(),
        isTrue,
      );
      expect(controller.entries, hasLength(1));
      expect(controller.entries.single.metadata.assetId, metadata.assetId);
      // 元数据文件不能被写成"已删除"。
      final reloaded = await store.loadEntries();
      expect(reloaded, hasLength(1));
    });

    test('removeEntry deletes directory and metadata when removeTask succeeds', () async {
      await createController(knownTaskId: 42, removeResult: true);
      await seedMetadata(taskId: 42);
      await seedAssetDirectory();
      await controller.initialize();

      final entry = controller.entries.single;
      await controller.removeEntry(entry);

      expect(manager.removedTaskIds, <int>[42]);
      expect(
        Directory(
          '${root.path}/vesper-player/offline-cache/assets/bili-BV1xx411c7mD-11-q80-avc-audio30280',
        ).existsSync(),
        isFalse,
      );
      expect(controller.entries, isEmpty);
      final reloaded = await store.loadEntries();
      expect(reloaded, isEmpty);
    });

    test('removeEntry cleans up an orphan task whose SDK task is gone', () async {
      // SDK 中任务已不存在（orphan）：本地清理必须继续，而不是被拒绝。
      await createController(knownTaskId: null, removeResult: false);
      final metadata = await seedMetadata(taskId: 42);
      await seedAssetDirectory();
      await controller.initialize();

      final entry = controller.entries.single;
      await controller.removeEntry(entry);

      expect(manager.removedTaskIds, isEmpty);
      expect(
        Directory(
          '${root.path}/vesper-player/offline-cache/assets/bili-BV1xx411c7mD-11-q80-avc-audio30280',
        ).existsSync(),
        isFalse,
      );
      expect(controller.entries, isEmpty);
      expect(metadata.assetId, 'bili-BV1xx411c7mD-11-q80-avc-audio30280');
    });

    test('remove fails fast when the SDK task cannot be removed', () async {
      await createController(knownTaskId: 7, removeResult: false);
      await seedMetadata();
      await controller.initialize();

      await expectLater(
        controller.remove(7),
        throwsA(isA<BiliOfflineDownloadException>()),
      );
      expect(controller.entries, hasLength(1));
    });

    test(
      'remove updates the inventory even without an SDK stream event',
      () async {
        await createController(knownTaskId: 42, snapshotIncludesTask: true);
        await seedMetadata(taskId: 42);
        await controller.initialize();
        addTearDown(controller.dispose);
        expect(controller.entries.single.task?.taskId, 42);
        await controller.remove(42);
        expect(controller.entries, isEmpty);
      },
    );

    test('concurrent enqueue creates one SDK task per asset', () async {
      final client = _RecoveryClient()
        ..restoreCookies({'SESSDATA': 's', 'bili_jct': 'c'});
      await createController(client: client);
      await controller.initialize();
      addTearDown(controller.dispose);
      manager.createResult = 43;
      final detail = await client.fetchVideoDetail('BV1xx411c7mD');
      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          controller.enqueueBiliPage(
            detail: detail,
            page: detail.pages.single,
            qualityId: 80,
          ),
      ]);
      expect(results.map((item) => item.metadata.taskId), [43, 43]);
      expect(manager.createCalls, 1);
      expect(client.preparedRequests, 1);
    });

    test('space preflight budgets for input tracks and remux output', () async {
      final client = _RecoveryClient(totalSizeBytes: 100)
        ..restoreCookies({'SESSDATA': 's', 'bili_jct': 'c'});
      var freeBytes = 199;
      const channel = MethodChannel('dev.ikaros.vesper_player/storage_space');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'freeBytes': freeBytes, 'totalBytes': 1000},
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await createController(client: client);
      await controller.initialize();
      addTearDown(controller.dispose);
      manager.createResult = 43;
      final detail = await client.fetchVideoDetail('BV1xx411c7mD');
      Future<BiliOfflineDownloadEntry> enqueue() => controller.enqueueBiliPage(
        detail: detail,
        page: detail.pages.single,
        qualityId: 80,
      );
      await expectLater(
        enqueue(),
        throwsA(
          isA<BiliOfflineDownloadException>().having(
            (e) => e.message,
            'message',
            contains('存储空间不足'),
          ),
        ),
      );
      expect(manager.createCalls, 0);
      expect(controller.entries, isEmpty);
      freeBytes = 200;
      await enqueue();
      expect(manager.createCalls, 1);
    });

    test('low disk keeps the previous failed task, unavailable space lets the SDK proceed', () async {
      final client = _RecoveryClient(totalSizeBytes: 100)
        ..restoreCookies({'SESSDATA': 's', 'bili_jct': 'c'});
      const channel = MethodChannel('dev.ikaros.vesper_player/storage_space');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Object? free = 0;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'totalBytes': 1000, 'freeBytes': free},
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await createController(
        client: client,
        knownTaskId: 42,
        taskState: VesperDownloadState.failed,
        taskError: 'old failure',
        snapshotIncludesTask: true,
      );
      await seedMetadata(taskId: 42);
      await controller.initialize();
      addTearDown(controller.dispose);
      manager.createResult = 43;
      final detail = await client.fetchVideoDetail('BV1xx411c7mD');
      Future<BiliOfflineDownloadEntry> enqueue() => controller.enqueueBiliPage(
        detail: detail,
        page: detail.pages.single,
        qualityId: 80,
      );
      await expectLater(
        enqueue(),
        throwsA(isA<BiliOfflineDownloadException>()),
      );
      expect(manager.removedTaskIds, isEmpty);
      expect(manager.createCalls, 0);
      expect((await store.loadEntries()).single.taskId, 42);
      free = null;
      await enqueue();
      expect(manager.removedTaskIds, [42]);
      expect(manager.createCalls, 1);
    });

    test('stale download cannot renew its plan when signed out', () async {
      final client = _RecoveryClient();
      await createController(client: client, knownTaskId: 42);
      await seedMetadata(taskId: 42, episodeId: 123);
      await controller.initialize();
      addTearDown(controller.dispose);
      final plan = await controller.recoverStaleDownloadPlan(
        manager.task(42)!,
        const VesperDownloadStaleResource(taskId: 42, message: 'expired'),
      );
      expect(plan, isNull);
      expect(client.requestedEpisodes, isEmpty);
      expect(client.optionRequests, 0);
    });

    test('failed SDK start rolls back its newly created task', () async {
      final client = _RecoveryClient()
        ..restoreCookies({'SESSDATA': 's', 'bili_jct': 'c'});
      await createController(client: client);
      await controller.initialize();
      addTearDown(controller.dispose);
      manager
        ..createResult = 43
        ..startResult = false;
      final detail = await client.fetchVideoDetail('BV1xx411c7mD');
      await expectLater(
        controller.enqueueBiliPage(
          detail: detail,
          page: detail.pages.single,
          qualityId: 80,
        ),
        throwsA(isA<BiliOfflineDownloadException>()),
      );
      expect(manager.removedTaskIds, [43]);
      expect(controller.entries.single.metadata.taskId, isNull);
      expect(controller.entries.single.needsAttention, isTrue);
    });

    test('stale episode recovery uses the persisted episode ID', () async {
      final client = _RecoveryClient()
        ..restoreCookies({'SESSDATA': 's', 'bili_jct': 'c'});
      await createController(client: client, knownTaskId: 42);
      await seedMetadata(taskId: 42, episodeId: 123);
      await controller.initialize();
      addTearDown(controller.dispose);
      final plan = await controller.recoverStaleDownloadPlan(
        manager.task(42)!,
        const VesperDownloadStaleResource(taskId: 42, message: 'expired'),
      );
      expect(client.requestedEpisodes, [123]);
      expect(plan, isNotNull);
    });

    test('stale recovery stops when the original CID disappeared', () async {
      final client = _RecoveryClient(pageCid: 22)
        ..restoreCookies({'SESSDATA': 's', 'bili_jct': 'c'});
      await createController(client: client, knownTaskId: 42);
      await seedMetadata(taskId: 42);
      await controller.initialize();
      addTearDown(controller.dispose);

      final plan = await controller.recoverStaleDownloadPlan(
        manager.task(42)!,
        const VesperDownloadStaleResource(taskId: 42, message: 'HTTP 403'),
      );

      expect(plan, isNull);
      expect(client.optionRequests, 0);
      expect(client.preparedRequests, 0);
    });

    test('stale recovery rejects a changed prepared asset identity', () async {
      final client = _RecoveryClient(preparedAssetId: 'different-asset')
        ..restoreCookies({'SESSDATA': 's', 'bili_jct': 'c'});
      await createController(client: client, knownTaskId: 42);
      await seedMetadata(taskId: 42);
      await controller.initialize();
      addTearDown(controller.dispose);

      final plan = await controller.recoverStaleDownloadPlan(
        manager.task(42)!,
        const VesperDownloadStaleResource(taskId: 42, message: 'HTTP 403'),
      );

      expect(client.preparedRequests, 1);
      expect(plan, isNull);
    });

    test('stale recovery accepts refreshed URLs for the same asset', () async {
      final client = _RecoveryClient()
        ..restoreCookies({'SESSDATA': 's', 'bili_jct': 'c'});
      await createController(client: client, knownTaskId: 42);
      await seedMetadata(taskId: 42);
      await controller.initialize();
      addTearDown(controller.dispose);

      final plan = await controller.recoverStaleDownloadPlan(
        manager.task(42)!,
        const VesperDownloadStaleResource(taskId: 42, message: 'HTTP 403'),
      );

      expect(plan, isNotNull);
      expect(plan?.source.source.uri, 'https://example.com/refreshed.mp4');
    });

    test(
      'integrity scan tolerates metadata removal during a file probe',
      () async {
        final probing = Completer<void>();
        final resumeProbe = Completer<void>();
        var blockProbes = false;
        await createController(
          cachePathResolver: ({required cacheRoot, required candidates}) async {
            if (blockProbes) {
              probing.complete();
              await resumeProbe.future;
            }
            return null;
          },
        );
        await seedMetadata();
        await controller.initialize();
        addTearDown(controller.dispose);
        final entry = controller.entries.single;
        blockProbes = true;

        final scanning = controller.refreshCacheInventory();
        await probing.future;
        await controller.removeEntry(entry);
        resumeProbe.complete();
        await scanning;

        expect(controller.entries, isEmpty);
        expect(await store.loadEntries(), isEmpty);
      },
    );

    test(
      'integrity scan rechecks early results after later probes await',
      () async {
        final probing = Completer<void>();
        final resumeProbe = Completer<void>();
        var blockProbes = false;
        final client = _RecoveryClient()
          ..restoreCookies(const <String, String>{
            'SESSDATA': 'sess',
            'bili_jct': 'csrf',
            'DedeUserID': '42',
          });
        await createController(
          client: client,
          cachePathResolver: ({required cacheRoot, required candidates}) async {
            if (blockProbes &&
                candidates.any((path) => path.endsWith('/second-asset'))) {
              probing.complete();
              await resumeProbe.future;
            }
            return null;
          },
        );
        final original = await seedMetadata();
        await store.saveEntries(<BiliOfflineDownloadMetadata>[
          original,
          const BiliOfflineDownloadMetadata(
            assetId: 'second-asset',
            bvid: 'BV1second',
            cid: 22,
            videoTitle: '另一个缓存',
            pageTitle: 'P1',
            coverUrl: '',
            qualityLabel: '1080P',
            createdAtMs: 0,
          ),
        ]);
        await controller.initialize();
        addTearDown(controller.dispose);
        manager.createResult = 43;
        blockProbes = true;

        final scanning = controller.refreshCacheInventory();
        await probing.future;
        final detail = await client.fetchVideoDetail('BV1xx411c7mD');
        await controller.enqueueBiliPage(
          detail: detail,
          page: detail.pages.single,
          qualityId: 80,
        );
        resumeProbe.complete();
        await scanning;

        final replacement = controller.entries.firstWhere(
          (entry) => entry.metadata.assetId == original.assetId,
        );
        expect(replacement.metadata.taskId, 43);
        expect(replacement.integrityError, isNull);
      },
    );

    test(
      'enqueueBiliPage fails fast when the stale SDK task cannot be removed',
      () async {
        final client = _RecoveryClient()
          ..restoreCookies({'SESSDATA': 's', 'bili_jct': 'c'});
        // 重建失败任务时必须先删除旧 SDK 任务：删除失败意味着旧任务可能
        // 仍在运行/占用输出，继续对同一 asset 创建新任务会冲突，必须中止。
        await createController(
          knownTaskId: 42,
          removeResult: false,
          taskState: VesperDownloadState.failed,
          taskError: '下载失败',
          snapshotIncludesTask: true,
          client: client,
        );
        await seedMetadata(taskId: 42);
        await controller.initialize();
        addTearDown(controller.dispose);
        final detail = await client.fetchVideoDetail('BV1xx411c7mD');
        final page = detail.pages.single;
        final options = await client.resolveDownloadOptions(
          detail: detail,
          page: page,
        );

        await expectLater(
          controller.enqueueBiliPage(
            detail: detail,
            page: page,
            qualityId: 80,
            options: options,
          ),
          throwsA(isA<BiliOfflineDownloadException>()),
        );
        // 旧任务删除失败时不得继续创建新任务。
        expect(manager.removedTaskIds, <int>[42]);
        expect(manager.createCalls, 0);
      },
    );

    test('dispose reports a rethrown manager dispose error', () async {
      final reported = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });

      await createController(
        knownTaskId: null,
        disposeError: StateError('platform release failed'),
      );
      await controller.initialize();

      controller.dispose();
      // Let the detached dispose future run and reach reportError.
      await pumpEventQueue(times: 20);

      expect(manager.disposeCalls, 1);
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      expect(reported.single.library, 'offline_download_controller');
    });

    test(
      'dispose flushes a pending metadata write without dropping errors',
      () async {
        final reported = <FlutterErrorDetails>[];
        final originalOnError = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() {
          FlutterError.onError = originalOnError;
        });

        await createController(knownTaskId: null);
        await seedMetadata();
        await controller.initialize();

        // 触发一次 snapshot 驱动写入，让防抖计时器挂起（dispose 时 flush）。
        manager.snapshotsController.add(const VesperDownloadSnapshot.initial());
        // 把存储根目录替换成普通文件：flush 写盘必然失败。
        await root.delete(recursive: true);
        await File(root.path).create();
        controller.dispose();
        await pumpEventQueue(times: 20);

        expect(reported, isNotEmpty);
        expect(
          reported.single.context.toString(),
          contains('flushing cached metadata'),
        );
      },
    );

    test('initialize after dispose is rejected', () async {
      await createController(knownTaskId: null);
      await controller.initialize();

      controller.dispose();

      expect(controller.isInitialized, isFalse);
      // initialize() 同步抛错：disposed 控制器不得重新初始化。
      expect(controller.initialize, throwsA(isA<StateError>()));
    });

    test(
      'dispose during initialization aborts without wiring the manager',
      () async {
        // 初始化进行中（挂在插件库解析上）时销毁控制器：_doInitialize 的
        // 剩余 await 必须中止，不得创建/重接 manager、订阅 snapshot 流或
        // notifyListeners——后者会在 ChangeNotifier 已销毁后触发断言错误。
        final gate = Completer<void>();
        await createController(knownTaskId: null, pluginGate: gate.future);
        final init = controller.initialize();
        // 让 initialize 推进到 plugin references 的 gate。
        await pumpEventQueue(times: 20);
        controller.dispose();
        gate.complete();

        await expectLater(init, throwsA(isA<StateError>()));
        // 中止后不得订阅 snapshot 流，manager 只能被 dispose() 本身销毁一次。
        expect(manager.snapshotsController.hasListener, isFalse);
        expect(manager.disposeCalls, 1);
        expect(manager.createCalls, 0);
        expect(controller.isInitialized, isFalse);
      },
    );

    test(
      'debounced metadata write failures are reported, not dropped',
      () async {
        final reported = <FlutterErrorDetails>[];
        final originalOnError = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() {
          FlutterError.onError = originalOnError;
        });

        await createController(knownTaskId: null);
        await seedMetadata();
        await controller.initialize();

        // 触发一次 snapshot 驱动写入，让防抖计时器挂起。
        manager.snapshotsController.add(const VesperDownloadSnapshot.initial());
        // 把存储根目录替换成普通文件：防抖写盘必然失败。
        await root.delete(recursive: true);
        await File(root.path).create();
        // 等防抖计时器触发（1.5s）后写盘失败：必须走 FlutterError 上报，
        // 不能成为未处理的异步错误。
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        await pumpEventQueue(times: 20);

        expect(reported, isNotEmpty);
        expect(
          reported.single.context.toString(),
          contains('persisting offline cache metadata'),
        );
      },
    );
  });
}

final class _FakeDownloadManagerHost implements BiliDownloadManagerHost {
  _FakeDownloadManagerHost({
    this.knownTaskId,
    this.removeResult = true,
    this.disposeError,
    this.taskState = VesperDownloadState.completed,
    this.taskError,
    this.snapshotIncludesTask = false,
  });

  final int? knownTaskId;
  bool removeResult;
  Object? disposeError;
  final VesperDownloadState taskState;
  final String? taskError;
  final bool snapshotIncludesTask;
  final List<int> removedTaskIds = <int>[];
  int disposeCalls = 0;
  int createCalls = 0;
  int? createResult;
  bool startResult = true;
  final StreamController<VesperDownloadSnapshot> snapshotsController =
      StreamController<VesperDownloadSnapshot>.broadcast();

  @override
  Future<int?> createTask({
    required String assetId,
    required VesperDownloadSource source,
    VesperDownloadProfile profile = const VesperDownloadProfile(),
    VesperDownloadAssetIndex assetIndex = const VesperDownloadAssetIndex(),
  }) async {
    createCalls += 1;
    return createResult;
  }

  @override
  Future<bool> removeTask(int taskId) async {
    removedTaskIds.add(taskId);
    return removeResult;
  }

  @override
  Future<bool> pauseTask(int taskId) async => true;

  @override
  Future<bool> resumeTask(int taskId) async => true;

  @override
  Future<bool> startTask(int taskId) async => startResult;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    final error = disposeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  VesperDownloadTaskSnapshot? task(int taskId) {
    if (taskId == knownTaskId) {
      final errorMessage = taskError;
      return VesperDownloadTaskSnapshot(
        taskId: taskId,
        assetId: 'bili-BV1xx411c7mD-11-q80-avc-audio30280',
        source: const VesperDownloadSource(
          source: VesperPlayerSource(
            uri: 'file:///tmp/offline.mp4',
            label: '离线视频',
            kind: VesperPlayerSourceKind.local,
            protocol: VesperPlayerSourceProtocol.file,
          ),
          contentFormat: VesperDownloadContentFormat.singleFile,
        ),
        profile: const VesperDownloadProfile(
          targetOutputFormat: VesperDownloadOutputFormat.mp4,
        ),
        state: taskState,
        error: errorMessage == null
            ? null
            : VesperDownloadError(
                code: VesperPlayerErrorCode.invalidSource,
                category: VesperPlayerErrorCategory.source,
                retriable: false,
                message: errorMessage,
              ),
        progress: const VesperDownloadProgressSnapshot(
          receivedBytes: 10,
          totalBytes: 10,
        ),
        assetIndex: const VesperDownloadAssetIndex(
          contentFormat: VesperDownloadContentFormat.singleFile,
          completedPath: '/tmp/offline.mp4',
        ),
      );
    }
    return null;
  }

  @override
  VesperDownloadSnapshot get snapshot {
    if (!snapshotIncludesTask) {
      return const VesperDownloadSnapshot.initial();
    }
    final taskId = knownTaskId;
    final known =
        taskId == null || (removeResult && removedTaskIds.contains(taskId))
        ? null
        : task(taskId);
    return known == null
        ? const VesperDownloadSnapshot.initial()
        : VesperDownloadSnapshot(tasks: <VesperDownloadTaskSnapshot>[known]);
  }

  @override
  Stream<VesperDownloadSnapshot> get snapshots => snapshotsController.stream;
}

final class _RecoveryClient extends BiliClient {
  _RecoveryClient({
    this.pageCid = 11,
    this.totalSizeBytes,
    this.preparedAssetId = 'bili-BV1xx411c7mD-11-q80-avc-audio30280',
  });

  final int pageCid;
  final int? totalSizeBytes;
  final requestedEpisodes = <int>[];
  final String preparedAssetId;
  int optionRequests = 0;
  int preparedRequests = 0;

  static const _video = BiliDashStream(
    id: 80,
    baseUrl: 'https://example.com/video.m4s',
    backupUrls: <String>[],
    mimeType: 'video/mp4',
    codecs: 'avc1.640028',
    bandwidth: 1200000,
    segmentInfo: BiliDashSegmentInfo(
      initialization: '0-10',
      indexRange: '11-20',
    ),
  );
  static const _audio = BiliDashStream(
    id: 30280,
    baseUrl: 'https://example.com/audio.m4s',
    backupUrls: <String>[],
    mimeType: 'audio/mp4',
    codecs: 'mp4a.40.2',
    bandwidth: 192000,
    segmentInfo: BiliDashSegmentInfo(
      initialization: '0-10',
      indexRange: '11-20',
    ),
  );

  @override
  Future<BiliVideoDetail> fetchPgcEpisodeDetail(int episodeId) {
    requestedEpisodes.add(episodeId);
    return fetchVideoDetail('BV1xx411c7mD');
  }

  @override
  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async {
    return BiliVideoDetail(
      aid: 1,
      bvid: bvid,
      title: '离线视频',
      ownerMid: 1,
      ownerName: 'UP',
      ownerAvatarUrl: '',
      coverUrl: '',
      description: '',
      publishedAtLabel: null,
      playCountLabel: '0',
      danmakuCountLabel: '0',
      replyCountLabel: '0',
      likeCountLabel: '0',
      coinCountLabel: '0',
      favoriteCountLabel: '0',
      shareCountLabel: '0',
      pages: <BiliVideoPageEntry>[
        BiliVideoPageEntry(
          cid: pageCid,
          pageNumber: 2,
          title: '第二集',
          durationSeconds: 60,
        ),
      ],
    );
  }

  @override
  Future<BiliDownloadOptions> resolveDownloadOptions({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
  }) async {
    optionRequests += 1;
    return BiliDownloadOptions(
      bvid: detail.bvid,
      cid: page.cid,
      videoTitle: detail.title,
      pageTitle: page.title,
      coverUrl: '',
      referer: '',
      headers: const <String, String>{},
      manifest: const BiliDashManifestData(
        durationMs: 60000,
        minBufferTimeMs: 1500,
        videoStreams: <BiliDashStream>[_video],
        audioStreams: <BiliDashStream>[_audio],
      ),
      qualities: const <BiliDownloadQualityOption>[],
      variantLabel: 'test',
    );
  }

  @override
  BiliPreparedDownloadAsset prepareDownloadAsset({
    required BiliDownloadOptions options,
    required int qualityId,
    BiliVideoCodecPreference codecPreference =
        BiliVideoCodecPreference.automatic,
    String? targetDirectory,
  }) {
    return BiliPreparedDownloadAsset(
      assetId: preparedAssetId,
      source: const VesperDownloadSource(
        source: VesperPlayerSource(
          uri: 'https://example.com/refreshed.mp4',
          label: '离线视频',
          kind: VesperPlayerSourceKind.remote,
          protocol: VesperPlayerSourceProtocol.progressive,
        ),
        contentFormat: VesperDownloadContentFormat.singleFile,
      ),
      profile: VesperDownloadProfile(targetDirectory: targetDirectory),
      assetIndex: VesperDownloadAssetIndex(totalSizeBytes: totalSizeBytes),
      selectedVideo: _video,
      selectedAudio: _audio,
      qualityLabel: '1080P',
    );
  }

  @override
  Future<BiliPreparedDownloadAsset> prepareVerifiedDownloadAsset({
    required BiliDownloadOptions options,
    required int qualityId,
    BiliVideoCodecPreference codecPreference =
        BiliVideoCodecPreference.automatic,
    String? targetDirectory,
  }) async {
    preparedRequests += 1;
    return prepareDownloadAsset(
      options: options,
      qualityId: qualityId,
      codecPreference: codecPreference,
      targetDirectory: targetDirectory,
    );
  }
}
