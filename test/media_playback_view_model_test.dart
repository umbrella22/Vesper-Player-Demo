import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';

/// 抽取计划 §6.3 红测试：泛化 view model 由 fake adapter 驱动，
/// 不依赖任何平台实现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('构造与解析', () {
    test('创建过程通过 adapter 解析并写入 resolved', () async {
      final adapter = _FakeMediaAdapter();
      final vm = _createVm(adapter);
      unawaited(vm.controllerFuture.then<void>((_) {}, onError: (Object _) {}));
      await pumpEventQueue();

      expect(adapter.resolveCallCount, greaterThanOrEqualTo(1));
      expect(vm.resolvedPlayback, isNotNull);
      expect(vm.resolvedPlayback!.title, '测试视频');
      expect(vm.selectedEntry.entryId, '11');
      expect(vm.isFullscreen, isFalse);
      expect(vm.dlnaManager.state, MediaDlnaState.idle);
      expect(vm.consumePendingMessage(), isNull);
      expect(vm.consumePendingPlaybackRecoveryNotice(), isNull);
    });

    test('解析失败时 controllerFuture 报错且不悬挂', () async {
      final adapter = _FakeMediaAdapter(failResolve: true);
      final vm = _createVm(adapter);
      Object? error;
      await vm.controllerFuture.then<void>(
        (_) {},
        onError: (Object caught) {
          error = caught;
        },
      );
      await pumpEventQueue();
      expect(error, isNotNull);
      expect(vm.resolvedPlayback, isNull);
    });
  });

  group('清晰度选项（适配器分组）', () {
    test('availableQualityOptions 来自解析结果的 qualityOptions', () async {
      final adapter = _FakeMediaAdapter(
        qualityOptions: const <MediaQualityOption>[
          MediaQualityOption(
            id: '120',
            label: '4K 超清',
            tracks: <VesperMediaTrack>[],
          ),
          MediaQualityOption(
            id: '64',
            label: '720P',
            tracks: <VesperMediaTrack>[],
          ),
        ],
      );
      final vm = _createVm(adapter);
      unawaited(vm.controllerFuture.then<void>((_) {}, onError: (Object _) {}));
      await pumpEventQueue();

      expect(vm.availableQualityOptions(), hasLength(2));
      expect(vm.availableQualityOptions().first.id, '120');
      expect(vm.supportsCodecSelection, isFalse);
    });

    test('无 controller 时清晰度/倍速/字幕选择为 no-op', () async {
      final vm = _createVm(_FakeMediaAdapter());
      expect(await vm.selectQualityOption('120'), isNull);
      expect(await vm.selectQualityOption(null), isNull);
      expect(await vm.selectCodecIdentity('AV1'), isNull);
      expect(await vm.setPlaybackRate(2.0), isNull);
      expect(
        await vm.selectSubtitle(const VesperTrackSelection.auto()),
        '播放器尚未准备好。',
      );
      expect(vm.selectedQualityOptionId, isNull);
      expect(vm.selectedCodecIdentity, isNull);
    });

    test('切换条目无 controller 时为 no-op', () async {
      final vm = _createVm(_FakeMediaAdapter());
      expect(
        await vm.switchEntry(
          const MediaPlaybackEntry(
            entryId: '22',
            pageNumber: 2,
            title: 'P2',
            durationSeconds: 60,
          ),
        ),
        isNull,
      );
      expect(vm.selectedEntry.entryId, '11');
    });
  });

  group('能力缺省与清理', () {
    test('空能力适配器下 view model 正常工作', () async {
      final vm = _createVm(_FakeMediaAdapter());
      unawaited(vm.controllerFuture.then<void>((_) {}, onError: (Object _) {}));
      await pumpEventQueue();
      expect(vm.dlnaManager.state, MediaDlnaState.idle);
      vm.setFullscreen(true);
      expect(vm.isFullscreen, isTrue);
    });

    test('dispose 后消息消费安全', () async {
      final vm = _createVm(_FakeMediaAdapter());
      vm.dispose();
      expect(vm.consumePendingMessage(), isNull);
      expect(vm.consumePendingPlaybackRecoveryNotice(), isNull);
    });
  });
}

MediaPlaybackViewModel _createVm(_FakeMediaAdapter adapter) {
  final vm = MediaPlaybackViewModel(
    detail: const MediaDetail(
      mediaId: 'BV1TEST',
      title: '测试视频',
      coverUrl: '',
      ownerName: '测试UP',
      pages: <MediaPlaybackEntry>[
        MediaPlaybackEntry(
          entryId: '11',
          pageNumber: 1,
          title: 'P1',
          durationSeconds: 120,
        ),
        MediaPlaybackEntry(
          entryId: '22',
          pageNumber: 2,
          title: 'P2',
          durationSeconds: 60,
        ),
      ],
    ),
    initialEntry: const MediaPlaybackEntry(
      entryId: '11',
      pageNumber: 1,
      title: 'P1',
      durationSeconds: 120,
    ),
    adapter: adapter,
  );
  // 测试环境无原生播放器：controllerFuture 必然失败，挂错误处理避免
  // unhandled async error 污染测试结果。
  unawaited(vm.controllerFuture.then<void>((_) {}, onError: (Object _) {}));
  return vm;
}

final class _FakeMediaAdapter extends MediaPlatformAdapter {
  _FakeMediaAdapter({
    this.failResolve = false,
    this.qualityOptions = const <MediaQualityOption>[],
  });

  final bool failResolve;
  final List<MediaQualityOption> qualityOptions;
  int resolveCallCount = 0;

  @override
  Future<ResolvedMediaPlayback> resolvePlayback({
    required MediaDetail detail,
    required MediaPlaybackEntry entry,
  }) async {
    resolveCallCount += 1;
    if (failResolve) {
      throw Exception('resolve failed');
    }
    return ResolvedMediaPlayback(
      title: detail.title,
      subtitle: 'P${entry.pageNumber} · ${entry.title}',
      uri: 'https://example.com/media.mpd',
      protocol: VesperPlayerSourceProtocol.dash,
      transportLabel: 'fake',
      isLocalFile: false,
      qualityOptions: qualityOptions,
    );
  }
}
