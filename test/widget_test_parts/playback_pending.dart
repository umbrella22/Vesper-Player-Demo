part of '../widget_test.dart';

void _registerPlaybackPendingWidgetTests() {
  testWidgets(
    'pending playback renders immediately, retries inline and records source timing',
    (tester) async {
      var gate = Completer<BiliPlaybackTarget>();
      final harness = await _pumpPlaybackPage(
        tester,
        pendingTarget: const BiliPendingPlaybackTarget(bvid: 'BV1playback01'),
        configureClient: (client) => client.targetResolver = (_) => gate.future,
      );
      expect(
        find.byKey(const ValueKey('bili-playback-pending')),
        findsOneWidget,
      );
      expect(find.byType(MediaPlaybackLoadingState), findsOneWidget);
      expect(harness.client.resolvedPlaybackRequests, isEmpty);
      gate.completeError(const BiliApiException('详情加载失败'));
      await tester.pumpAndSettle();
      expect(find.textContaining('详情加载失败'), findsOneWidget);
      expect(find.text('重新尝试'), findsOneWidget);
      gate = Completer<BiliPlaybackTarget>();
      await tester.tap(find.text('重新尝试'));
      await tester.pump();
      expect(find.byType(MediaPlaybackLoadingState), findsOneWidget);
      final detail = _playbackDetail();
      gate.complete(
        BiliPlaybackTarget(detail: detail, initialPage: detail.pages.first),
      );
      await tester.pump();
      await _flushRealAsync(tester);
      await tester.pump();
      expect(harness.client.resolvedPlaybackRequests, [detail.pages.first.cid]);
      final page = tester.widget<MediaPlaybackPage>(
        find.byType(MediaPlaybackPage),
      );
      expect(page.viewModel.startupTiming!.label, contains('tap→push='));
      expect(
        page.viewModel.startupTiming!.label,
        contains('resolveStart→sourceReady='),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('leaving a pending route discards late target resolution', (
    tester,
  ) async {
    final gate = Completer<BiliPlaybackTarget>();
    final harness = await _pumpPlaybackPage(
      tester,
      pendingTarget: const BiliPendingPlaybackTarget(bvid: 'BV1playback01'),
      configureClient: (client) => client.targetResolver = (_) => gate.future,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    final detail = _playbackDetail();
    gate.complete(
      BiliPlaybackTarget(detail: detail, initialPage: detail.pages.first),
    );
    await tester.pump();
    expect(harness.client.resolvedPlaybackRequests, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
