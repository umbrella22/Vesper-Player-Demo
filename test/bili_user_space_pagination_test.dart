import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_user_space_page.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';

void main() {
  for (final exactBvid in [false, true]) {
    testWidgets(
      'search during pagination invalidates old page (exact=$exactBvid)',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = _SpaceClient();
        await tester.pumpWidget(
          MaterialApp(
            home: BiliUserSpacePage(
              client: client,
              user: const BiliFollowingUser(mid: 1, name: 'UP', avatarUrl: ''),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('加载更多'));
        await tester.pump();
        final stalePage = client.pendingPage!;
        final input = find.byKey(
          const ValueKey('bili-user-space-video-search'),
        );
        await tester.enterText(input, exactBvid ? 'BV1xx411c7mD' : 'new');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        stalePage.complete(_page('old-second', page: 2));
        await tester.pumpAndSettle();
        expect(find.text('old-second'), findsNothing);
        expect(find.text('加载中'), findsNothing);
        if (exactBvid) {
          expect(find.text('old-first'), findsOneWidget);
          expect(find.text('加载更多'), findsNothing);
        } else {
          expect(find.text('new-first'), findsOneWidget);
          await tester.tap(find.text('加载更多'));
          await tester.pump();
          expect(client.requests, [':1', ':2', 'new:1', 'new:2']);
          client.pendingPage!.complete(_page('new-second', page: 2));
          await tester.pumpAndSettle();
          expect(find.text('new-second'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _SpaceClient extends BiliClient {
  Completer<BiliUserSpaceVideoPage>? pendingPage;
  final requests = <String>[];

  @override
  bool get hasAuthenticatedSession => true;

  @override
  Future<BiliUserSpaceProfile> fetchUserSpaceProfile(int mid) async =>
      const BiliUserSpaceProfile(mid: 1, name: 'UP', avatarUrl: '');

  @override
  Future<BiliUserSpaceVideoPage> fetchUserSpaceVideos({
    required int mid,
    int page = 1,
    int pageSize = 30,
    String keyword = '',
  }) async {
    requests.add('$keyword:$page');
    if (page > 1) {
      pendingPage = Completer<BiliUserSpaceVideoPage>();
      return pendingPage!.future;
    }
    return _page(keyword.isEmpty ? 'old-first' : 'new-first');
  }
}

BiliUserSpaceVideoPage _page(String title, {int page = 1}) =>
    BiliUserSpaceVideoPage(
      mid: 1,
      page: page,
      pageSize: 30,
      total: 60,
      hasMore: page == 1,
      videos: [
        BiliUserSpaceVideo(
          aid: 1,
          bvid: title == 'old-first' ? 'BV1xx411c7mD' : 'BV$title',
          title: title,
          coverUrl: '',
          durationLabel: '',
          publishedAtLabel: '',
          playCountLabel: '',
          ownerMid: 1,
          ownerName: 'UP',
        ),
      ],
    );
