import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_user_space_page.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_endpoints.dart';
import 'package:vesper_media/bili/common/services/bili_transport.dart';

void main() {
  test('space parser preserves unknown and zero statistics', () async {
    final transport = _SpaceTransport();
    final client = BiliClient(transport: transport);
    addTearDown(() => transport.httpClient.close(force: true));

    var profile = await client.fetchUserSpaceProfile(42);
    expect(profile.archiveCount, isNull);
    expect(profile.followerCount, isNull);
    expect(profile.followingCount, isNull);
    expect(profile.vipLabel, isNull);

    transport.card = {
      ...transport.card,
      'fans': 0,
      'friend': 0,
      'archive_count': 0,
      'vip': {
        'label': {'text': '年度大会员'},
        'nickname_color': '#FB7299',
      },
    };
    profile = await client.fetchUserSpaceProfile(42);
    expect(profile.archiveCount, 0);
    expect(profile.followerCount, 0);
    expect(profile.followingCount, 0);
    expect(profile.vipLabel, '年度大会员');
    expect(profile.officialLabel, '个人认证');
    expect(
      BiliUserSpaceProfile.fromFollowing(
        const BiliFollowingUser(mid: 42, name: '我', avatarUrl: ''),
      ).followerCount,
      isNull,
    );
  });

  for (final hasStatistics in [false, true]) {
    testWidgets(
      'own space badges and statistics fit a narrow screen (known=$hasStatistics)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final transport = _SpaceTransport();
        transport.card = {
          ...transport.card,
          if (hasStatistics) ...{'fans': 0, 'friend': 0, 'archive_count': 0},
          'vip': {
            'label': {'text': '年度大会员'},
          },
        };
        addTearDown(() => transport.httpClient.close(force: true));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: BiliUserSpacePage(
                client: BiliClient(transport: transport),
                user: const BiliFollowingUser(
                  mid: 42,
                  name: '我',
                  avatarUrl: '',
                ),
                isSelf: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('我的空间'), findsOneWidget);
        expect(find.text('个人认证'), findsOneWidget);
        expect(find.text('年度大会员'), findsOneWidget);
        for (final label in ['投稿 0', '关注 0', '粉丝 0']) {
          expect(
            find.text(label),
            hasStatistics ? findsOneWidget : findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _SpaceTransport extends BiliTransport {
  Map<String, Object?> card = {
    'mid': 42,
    'name': '我的账号',
    'official_verify': {'desc': '个人认证'},
    'vip': {'nickname_color': '#FB7299'},
  };

  @override
  bool get hasAuthenticatedSession => true;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<Map<String, Object?>> getData({
    required String host,
    required String path,
    Map<String, Object?> params = const {},
    bool useWbi = false,
    String referer = biliDefaultReferer,
    bool ensureReady = true,
    Set<int> allowedCodes = const {0},
  }) async => switch (path) {
    '/x/web-interface/card' => {'card': card},
    '/x/space/wbi/arc/search' => {
      'list': {'vlist': []},
      'page': {'count': 0, 'pn': 1, 'ps': 30},
    },
    _ => throw StateError('Unexpected request $path'),
  };
}
