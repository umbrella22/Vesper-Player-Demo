import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_hub_page.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_region_video_page.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/models/bili_region_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/services/bili_session_store.dart';

void main() {
  for (final home in [true, false]) {
    testWidgets(
      'phone ${home ? 'feed' : 'region'} pagination waits for explicit retry after failure',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final client = _PagedClient();
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('phone-paging-'),
        ))!;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() => root.delete(recursive: true));
        });
        await tester.pumpWidget(
          MaterialApp(
            home: home
                ? BiliHubPage(
                    client: client,
                    historyStore: BiliHistoryStore(
                      baseDirectory: root,
                      legacyDirectory: root,
                    ),
                    sessionStore: BiliSessionStore(
                      baseDirectory: root,
                      legacyDirectory: root,
                    ),
                  )
                : BiliRegionVideoPage(
                    client: client,
                    section: const BiliRegionSection(
                      id: 'series',
                      name: '番剧',
                      icon: 'P',
                    ),
                  ),
          ),
        );
        for (var i = 0; i < 100 && find.text('视频 0').evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(find.text('视频 0'), findsOneWidget);
        final controller = home
            ? tester
                  .widget<CustomScrollView>(find.byType(CustomScrollView))
                  .controller!
            : tester.widget<GridView>(find.byType(GridView)).controller!;
        final end = controller.position.maxScrollExtent;
        controller.jumpTo(end);
        await tester.pump();
        expect(client.requested, [1, 2]);
        for (var i = 1; i <= 5; i++) {
          controller.jumpTo(end - i);
          await tester.pump();
        }
        expect(client.requested, [1, 2]);
        final retry = find.widgetWithText(TextButton, '重试加载更多');
        expect(retry, findsOneWidget);
        // Let the transient error Snackbar clear before tapping the footer.
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pump();
        expect(client.requested, [1, 2, 2]);
      },
    );
  }
}

final class _PagedClient extends BiliClient {
  final requested = <int>[];
  @override
  bool get hasAuthenticatedSession => true;

  int _count(int page) {
    requested.add(page);
    if (page == 2 && requested.length == 2) {
      throw const SocketException('offline');
    }
    return page == 1 ? 20 : 0;
  }

  @override
  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) async =>
      List.generate(
        _count(page),
        (i) => BiliFeedVideo(
          aid: i + 1,
          bvid: 'BV$i',
          title: '视频 $i',
          author: 'UP',
          coverUrl: '',
          durationLabel: '',
          playCountLabel: '',
          danmakuCountLabel: '',
        ),
      );

  @override
  Future<void> prefetchFeedPlayback(List<BiliFeedVideo> items) async {}

  @override
  Future<BiliUserProfile> fetchCurrentUserProfile() async =>
      const BiliUserProfile(isLoggedIn: false, name: '未登录', avatarUrl: '');

  @override
  Future<List<BiliRegionVideo>> fetchRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) async => List.generate(
    _count(page),
    (i) => BiliRegionVideo(id: '$i', title: '视频 $i', coverUrl: '', url: ''),
  );
}
