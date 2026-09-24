import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_library_page.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';

void main() {
  for (final overlap in ['local', 'remote', 'stalled']) {
    testWidgets('history cursor pagination handles $overlap overlap', (
      tester,
    ) async {
      late Directory root;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('vesper-history-pages-');
      });
      addTearDown(() => root.delete(recursive: true));
      final store = BiliHistoryStore(baseDirectory: root);
      await tester.runAsync(
        () => store.saveEntry(
          const BiliPlaybackHistoryEntry(
            bvid: 'BV-local',
            cid: 2,
            videoTitle: '本地补充',
            pageTitle: 'P1',
            coverUrl: '',
            ownerName: 'UP',
            playedAtMs: 100,
            lastPositionMs: 1000,
          ),
        ),
      );
      final client = _HistoryClient([
        BiliRemoteHistoryPage(
          entries: [_entry(1, '云端第一页')],
          hasMore: true,
          nextMax: 100,
        ),
        BiliRemoteHistoryPage(
          entries: [_entry(overlap == 'local' ? 2 : 1, '云端重合记录')],
          hasMore: true,
          nextMax: overlap == 'stalled' ? 100 : 90,
        ),
        BiliRemoteHistoryPage(entries: [_entry(3, '云端第三页')], hasMore: false),
      ]);
      addTearDown(() => client.transport.httpClient.close(force: true));
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: BiliLibraryPage(
            client: client,
            historyStore: store,
            initialSection: BiliLibrarySection.history,
          ),
        ),
      );
      await _pumpUntil(tester, find.text('云端第一页'));
      expect(find.text('本地补充'), findsOneWidget);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      if (overlap == 'stalled') {
        expect(find.text('加载更多'), findsNothing);
      } else {
        expect(find.text('加载更多'), findsOneWidget);
        if (overlap == 'local') {
          expect(find.text('云端重合记录'), findsOneWidget);
          expect(find.text('本地补充'), findsNothing);
        }
        await tester.tap(find.text('加载更多'));
        await tester.pumpAndSettle();
        expect(find.text('云端第三页'), findsOneWidget);
        expect(client.requestedCursors, [0, 100, 90]);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

BiliRemoteHistoryEntry _entry(int cid, String title) => BiliRemoteHistoryEntry(
  aid: cid,
  bvid: 'BV-$cid',
  cid: cid,
  title: title,
  pageTitle: 'P1',
  coverUrl: '',
  ownerName: 'UP',
  durationMs: 120000,
  progressMs: 1000,
  viewedAtMs: 1000,
);

final class _HistoryClient extends BiliClient {
  _HistoryClient(this.pages);
  final List<BiliRemoteHistoryPage> pages;
  final requestedCursors = <int>[];

  @override
  bool get hasAuthenticatedSession => true;

  @override
  Future<BiliRemoteHistoryPage> fetchRemoteHistoryPage({
    int page = 1,
    int pageSize = 20,
    int max = 0,
    int viewAtMs = 0,
  }) async {
    requestedCursors.add(max);
    return pages[page - 1];
  }
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
}
