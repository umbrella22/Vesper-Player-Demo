import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/view_models/bili_playback_view_model.dart';
import 'package:vesper_media/download/services/offline_download_controller.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Avoid the Android-only cast/DLNA platform subscriptions in the VM and
    // external-playback manager constructors.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('construction and pure getters', () {
    test('initial state reflects detail and initial page', () async {
      final vm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(),
        _detail().pages.first,
      );

      expect(vm.selectedPage.cid, 11);
      expect(vm.coinCountLabel, '2.3万');
      expect(vm.shareCountLabel, '12');
      expect(vm.comments, isEmpty);
      expect(vm.commentReplies, isEmpty);
      expect(vm.relatedVideos, isEmpty);
      // The constructor kicks off an unawaited engagement load, so by the time
      // the test runs the guest profile is already resolved.
      expect(vm.engagement, isNotNull);
      expect(vm.engagement!.isAuthenticated, isFalse);
      expect(vm.controller, isNull);
      expect(vm.isFullscreen, isFalse);
      expect(vm.pendingEngagementAction, isNull);
      expect(vm.selectedCodecStrategy, BiliCodecStrategy.defaultStrategy);
      expect(vm.consumePendingMessage(), isNull);
      expect(vm.consumePendingPlaybackRecoveryNotice(), isNull);
    });

    test('ownerSubtitle formats phone and PGC titles', () async {
      final phoneVm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(),
        _detail().pages.first,
      );
      expect(phoneVm.ownerSubtitle, 'UP 主 · 2 个分 P');

      final pgcVm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(pgc: true),
        _detail(pgc: true).pages.first,
      );
      expect(pgcVm.ownerSubtitle, '2 话/集');

      final singlePgcVm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(pgc: true, pages: 1),
        _detail(pgc: true, pages: 1).pages.first,
      );
      expect(singlePgcVm.ownerSubtitle, '番剧');
    });

    test('videoMetaLine joins play count, date, and page', () async {
      final vm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(),
        _detail().pages.first,
      );
      expect(vm.videoMetaLine, '1.2万播放 · 2024-01-01 · P1');
    });

    test('quality label mapping covers known and unknown ids', () async {
      final vm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(),
        _detail().pages.first,
      );
      expect(vm.biliQualityLabelFromQualityId(127), '8K 超高清');
      expect(vm.biliQualityLabelFromQualityId(120), '4K 超清');
      expect(vm.biliQualityLabelFromQualityId(64), '720P');
      expect(vm.biliQualityLabelFromQualityId(999), isNull);
    });

    test('download codec preference follows default strategy', () async {
      final vm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(),
        _detail().pages.first,
      );
      expect(
        vm.currentDownloadCodecPreference(),
        BiliVideoCodecPreference.automatic,
      );
    });

    test('track helpers parse quality ids and codec strategy', () async {
      final vm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(),
        _detail().pages.first,
      );
      const tracks = <VesperMediaTrack>[
        VesperMediaTrack(
          id: 'video-80-7-1000',
          kind: VesperMediaTrackKind.video,
          codec: 'avc1.640028',
          height: 1080,
        ),
        VesperMediaTrack(
          id: 'video-120-12-2000',
          kind: VesperMediaTrackKind.video,
          codec: 'hev1.1.6.L153.B0',
          height: 2160,
        ),
        VesperMediaTrack(
          id: 'video-32-7-500',
          kind: VesperMediaTrackKind.video,
          codec: 'avc1.4d401f',
          height: 480,
        ),
      ];

      expect(vm.availableBiliQualityIds(tracks), <int>[120, 80, 32]);
      expect(
        vm.hasTrackForSelection(tracks, 120, BiliCodecStrategy.hevc),
        isTrue,
      );
      expect(
        vm.hasTrackForSelection(tracks, 120, BiliCodecStrategy.avc),
        isFalse,
      );
      expect(vm.biliQualityIdForTrack(tracks.first), 80);
    });

    test('track quality id falls back to label and shape', () async {
      final vm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(),
        _detail().pages.first,
      );
      const labelTrack = VesperMediaTrack(
        id: 'x',
        kind: VesperMediaTrackKind.video,
        label: '1080P60',
      );
      expect(vm.biliQualityIdForTrack(labelTrack), 116);

      const shapeTrack = VesperMediaTrack(
        id: 'y',
        kind: VesperMediaTrackKind.video,
        height: 720,
        frameRate: 30,
      );
      expect(vm.biliQualityIdForTrack(shapeTrack), 64);
    });
  });

  group('comments', () {
    test('loads page one and appends page two with deduplication', () async {
      final client = _FakePlaybackVmClient()
        ..comments = <BiliVideoComment>[
          _comment(1, '用户A', '第一条'),
          _comment(2, '用户B', '第二条'),
          _comment(3, '用户C', '第三条'),
        ]
        ..extraComments = <BiliVideoComment>[
          _comment(4, '用户D', '第四条'),
          _comment(2, '用户B', '重复第二条'),
        ];
      final vm = await _createVm(client, _detail(), _detail().pages.first);

      await vm.loadComments();

      expect(vm.comments, hasLength(3));
      expect(vm.commentsHasMore, isTrue);

      await vm.loadMoreComments();

      expect(vm.comments, hasLength(4));
      expect(vm.comments.map((c) => c.id), <int>[1, 2, 3, 4]);
      expect(vm.commentsHasMore, isFalse);
    });

    test('surfaces comment load errors', () async {
      final client = _FakePlaybackVmClient()
        ..commentError = const BiliApiException('评论接口失败', code: -400);
      final vm = await _createVm(client, _detail(), _detail().pages.first);

      await vm.loadComments();

      expect(vm.comments, isEmpty);
      expect(vm.commentsError, contains('评论加载失败'));
    });

    test('loads comment replies with paging and totals', () async {
      final client = _FakePlaybackVmClient()
        ..commentReplyPages[1] = List<BiliVideoComment>.generate(
          20,
          (i) => _comment(500 + i, '回复${i + 1}', '内容${i + 1}'),
        )
        ..commentReplyPages[2] = <BiliVideoComment>[
          _comment(520, '回复21', '内容21'),
        ]
        ..commentReplyTotalCount = 21;
      final rootComment = _comment(501, '楼主', '主评论', replyCount: 21);
      final vm = await _createVm(client, _detail(), _detail().pages.first);

      await vm.loadCommentReplies(rootComment);

      expect(vm.commentReplies, hasLength(20));
      expect(vm.commentRepliesTotalCount, 21);
      expect(vm.commentRepliesHasMore, isTrue);

      await vm.loadMoreCommentReplies();

      expect(vm.commentReplies, hasLength(21));
      expect(vm.commentRepliesHasMore, isFalse);
    });

    test('rejects empty comment messages and prepends sent comments', () async {
      final client = _FakePlaybackVmClient();
      final vm = await _createVm(client, _detail(), _detail().pages.first);

      final emptyResult = await vm.submitComment('   ');
      expect(emptyResult, '评论内容不能为空');
      expect(client.sentComments, isEmpty);

      final result = await vm.submitComment('好看，支持一下');
      expect(result, '已发送评论');
      expect(client.sentComments, <String>['好看，支持一下']);
      expect(vm.comments.first.message, '好看，支持一下');
    });
  });

  group('engagement and watch later', () {
    Future<BiliPlaybackViewModel> authenticatedVm(
      _FakePlaybackVmClient client,
    ) async {
      client.restoreCookies(const <String, String>{
        'SESSDATA': 'sess',
        'bili_jct': 'csrf',
      });
      return _createVm(client, _detail(), _detail().pages.first);
    }

    test('guest engagement is not authenticated', () async {
      final client = _FakePlaybackVmClient();
      final vm = await _createVm(client, _detail(), _detail().pages.first);

      await vm.loadEngagementState();

      expect(vm.engagement, isNotNull);
      expect(vm.engagement!.isAuthenticated, isFalse);
    });

    test('authenticated engagement also fetches coin count', () async {
      final client = _FakePlaybackVmClient()
        ..engagement = const BiliVideoEngagement(
          isAuthenticated: true,
          isLiked: false,
          isFavorited: false,
          isFollowingOwner: false,
          favoriteMediaIds: <int>[],
          defaultFavoriteMediaId: 1,
        )
        ..coinCount = 2;
      final vm = await authenticatedVm(client);

      await vm.loadEngagementState();

      expect(vm.engagement!.isAuthenticated, isTrue);
      expect(vm.sentCoinCount, 2);
    });

    test('toggleLike flips state and reports a message', () async {
      final client = _FakePlaybackVmClient()
        ..engagement = const BiliVideoEngagement(
          isAuthenticated: true,
          isLiked: false,
          isFavorited: false,
          isFollowingOwner: false,
          favoriteMediaIds: <int>[],
          defaultFavoriteMediaId: 1,
        );
      final vm = await authenticatedVm(client);

      final message = await vm.toggleLike();

      expect(message, '已点赞');
      expect(vm.engagement!.isLiked, isTrue);
      expect(vm.pendingEngagementAction, isNull);
    });

    test('addCoin updates coin count and like state', () async {
      final client = _FakePlaybackVmClient()
        ..engagement = const BiliVideoEngagement(
          isAuthenticated: true,
          isLiked: false,
          isFavorited: false,
          isFollowingOwner: false,
          favoriteMediaIds: <int>[],
          defaultFavoriteMediaId: 1,
        );
      final vm = await authenticatedVm(client);

      final message = await vm.addCoin();

      expect(message, contains('已投币'));
      expect(vm.sentCoinCount, 1);
      expect(vm.engagement!.isLiked, isTrue);
    });

    test('toggleFavorite and toggleFollow mutate engagement', () async {
      final client = _FakePlaybackVmClient()
        ..engagement = const BiliVideoEngagement(
          isAuthenticated: true,
          isLiked: false,
          isFavorited: false,
          isFollowingOwner: false,
          favoriteMediaIds: <int>[],
          defaultFavoriteMediaId: 1,
        );
      final vm = await authenticatedVm(client);

      expect(await vm.toggleFavorite(), '已收藏');
      expect(vm.engagement!.isFavorited, isTrue);

      expect(await vm.toggleFollow(), '已关注 UP 主');
      expect(vm.engagement!.isFollowingOwner, isTrue);
    });

    test(
      'pending engagement action deduplicates concurrent operations',
      () async {
        final client = _FakePlaybackVmClient()
          ..engagement = const BiliVideoEngagement(
            isAuthenticated: true,
            isLiked: false,
            isFavorited: false,
            isFollowingOwner: false,
            favoriteMediaIds: <int>[],
            defaultFavoriteMediaId: 1,
          )
          ..likeCompleter = Completer<BiliVideoEngagement>();
        final vm = await authenticatedVm(client);

        final first = vm.toggleLike();
        await pumpEventQueue();
        expect(vm.pendingEngagementAction, BiliEngagementAction.like);

        final second = await vm.toggleLike();
        expect(second, isNull);

        client.likeCompleter!.complete(
          client.engagement.copyWith(isLiked: true),
        );
        expect(await first, '已点赞');
        expect(vm.pendingEngagementAction, isNull);
      },
    );

    test('watch later prompts for login when unauthenticated', () async {
      final client = _FakePlaybackVmClient();
      final vm = await _createVm(client, _detail(), _detail().pages.first);

      final message = await vm.toggleWatchLater();

      expect(message, '请先登录 Bilibili 后使用稍后再看。');
      expect(vm.isInWatchLater, isFalse);
    });

    test(
      'watch later degrades gracefully when membership is unavailable',
      () async {
        final client = _FakePlaybackVmClient();
        final vm = await authenticatedVm(client);

        // Watch-later endpoints are extension methods on BiliClient and cannot
        // be faked by subclassing; in the test environment they fail over the
        // network. The VM must degrade gracefully (membership is optional).
        await vm.loadWatchLaterState();
        expect(vm.watchLaterKnown, isFalse);
        expect(vm.isInWatchLater, isFalse);

        final message = await vm.toggleWatchLater();
        expect(message, contains('操作失败'));
        expect(vm.isInWatchLater, isFalse);
      },
    );
  });

  group('related videos', () {
    test('loads related videos excluding the current video', () async {
      final detail = _detail();
      final client = _FakePlaybackVmClient()
        ..relatedVideos = <BiliFeedVideo>[
          _feed(1, 'BV1OTHER1', '相关一'),
          _feed(2, 'BV1OTHER2', '相关二'),
          _feed(3, detail.bvid, '自己（应被过滤）'),
        ];
      final vm = await _createVm(client, detail, detail.pages.first);

      await vm.loadRelatedVideos();

      expect(vm.relatedVideos.map((v) => v.bvid), <String>[
        'BV1OTHER1',
        'BV1OTHER2',
      ]);
      expect(vm.relatedVideosError, isNull);
    });

    test('falls back to recommended feed and reports errors', () async {
      final detail = _detail();
      final fallbackClient = _FakePlaybackVmClient()
        ..relatedError = const BiliApiException('相关接口失败', code: -400)
        ..recommended = <BiliFeedVideo>[_feed(9, 'BV1RECOMMEND', '推荐一')];
      final fallbackVm = await _createVm(
        fallbackClient,
        detail,
        detail.pages.first,
      );

      await fallbackVm.loadRelatedVideos();
      expect(fallbackVm.relatedVideos.map((v) => v.bvid), <String>[
        'BV1RECOMMEND',
      ]);
      expect(fallbackVm.relatedVideosError, isNull);

      final failingClient = _FakePlaybackVmClient()
        ..relatedError = const BiliApiException('相关接口失败', code: -400)
        ..recommendedError = const BiliApiException('推荐接口失败', code: -400);
      final failingVm = await _createVm(
        failingClient,
        detail,
        detail.pages.first,
      );

      await failingVm.loadRelatedVideos();
      expect(failingVm.relatedVideos, isEmpty);
      expect(failingVm.relatedVideosError, contains('相关视频加载失败'));
    });
  });

  group('controller-gated operations', () {
    test('switch page is a no-op without a controller', () async {
      final detail = _detail();
      final vm = await _createVm(
        _FakePlaybackVmClient(),
        detail,
        detail.pages.first,
      );

      final result = await vm.switchPage(detail.pages[1]);

      expect(result, isNull);
      expect(vm.selectedPage.cid, 11);
    });

    test('playback controls are no-ops without a controller', () async {
      final vm = await _createVm(
        _FakePlaybackVmClient(),
        _detail(),
        _detail().pages.first,
      );

      expect(await vm.setPlaybackRate(1.5), isNull);
      expect(await vm.selectBiliQuality(80), isNull);
      expect(await vm.selectCodecStrategy(BiliCodecStrategy.av1), isNull);
      expect(
        await vm.selectSubtitle(VesperTrackSelection.disabled()),
        '播放器尚未准备好。',
      );
    });
  });

  group('dispose', () {
    test('ignores constructor load completion after disposal', () async {
      final root = await Directory.systemTemp.createTemp(
        'bili-playback-vm-dispose-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final engagementCompleter = Completer<BiliVideoEngagement>();
      final client = _FakePlaybackVmClient()
        ..engagementCompleter = engagementCompleter;
      final vm = BiliPlaybackViewModel(
        detail: _detail(),
        initialPage: _detail().pages.first,
        client: client,
        historyStore: BiliHistoryStore(
          baseDirectory: Directory('${root.path}/history'),
        ),
        offlineController: _FakeVmOfflineController(),
      );
      unawaited(vm.controllerFuture.then<void>((_) {}, onError: (Object _) {}));

      await pumpEventQueue();
      vm.dispose();
      engagementCompleter.complete(const BiliVideoEngagement.guest());
      await pumpEventQueue();
    });

    test('ignores an engagement action completion after disposal', () async {
      final client = _FakePlaybackVmClient();
      final vm = await _createVm(client, _detail(), _detail().pages.first);
      final likeCompleter = Completer<BiliVideoEngagement>();
      client.likeCompleter = likeCompleter;

      final likeFuture = vm.toggleLike();
      await pumpEventQueue();
      vm.dispose();
      likeCompleter.complete(
        const BiliVideoEngagement.guest().copyWith(isLiked: true),
      );

      expect(await likeFuture, isNull);
      await pumpEventQueue();
    });
  });
}

/// Constructs a VM with a temp history store, attaches an error handler to the
/// always-failing controller future, and flushes the constructor's unawaited
/// loads.
Future<BiliPlaybackViewModel> _createVm(
  _FakePlaybackVmClient client,
  BiliVideoDetail detail,
  BiliVideoPageEntry page,
) async {
  final root = await Directory.systemTemp.createTemp('bili-playback-vm-test-');
  addTearDown(() => root.delete(recursive: true));
  final vm = BiliPlaybackViewModel(
    detail: detail,
    initialPage: page,
    client: client,
    historyStore: BiliHistoryStore(
      baseDirectory: Directory('${root.path}/history'),
    ),
    offlineController: _FakeVmOfflineController(),
  );
  // The controller future always fails (the fake client cannot create a real
  // player); attach a handler so the error is not reported as unhandled.
  unawaited(vm.controllerFuture.then<void>((_) {}, onError: (Object _) {}));
  addTearDown(vm.dispose);
  await pumpEventQueue();
  return vm;
}

BiliVideoDetail _detail({bool pgc = false, int pages = 2}) {
  return BiliVideoDetail(
    aid: 100,
    bvid: 'BV1TESTVIDEO',
    title: '测试视频',
    ownerMid: pgc ? 0 : 10001,
    ownerName: pgc ? '番剧' : '测试UP',
    ownerAvatarUrl: '',
    coverUrl: '',
    description: '视频描述',
    publishedAtLabel: '2024-01-01',
    playCountLabel: '1.2万',
    danmakuCountLabel: '345',
    replyCountLabel: '78',
    likeCountLabel: '1.1万',
    coinCountLabel: '2.3万',
    favoriteCountLabel: '456',
    shareCountLabel: '12',
    pages: List<BiliVideoPageEntry>.generate(pages, (index) {
      return BiliVideoPageEntry(
        cid: 11 + index,
        pageNumber: index + 1,
        title: 'P${index + 1}',
        durationSeconds: 120,
        aid: 100,
        bvid: 'BV1TESTVIDEO',
        coverUrl: '',
      );
    }),
  );
}

BiliVideoComment _comment(
  int id,
  String author,
  String message, {
  int replyCount = 0,
}) {
  return BiliVideoComment(
    id: id,
    authorName: author,
    authorAvatarUrl: '',
    authorLevelLabel: 'LV1',
    createdAtLabel: '刚刚',
    message: message,
    likeCountLabel: '0',
    replyCount: replyCount,
    pictures: const <BiliCommentPicture>[],
    replies: const <BiliVideoComment>[],
    timeLinks: const <BiliCommentTimeLink>[],
  );
}

BiliFeedVideo _feed(int aid, String bvid, String title) {
  return BiliFeedVideo(
    aid: aid,
    bvid: bvid,
    title: title,
    author: 'UP',
    coverUrl: '',
    durationLabel: '01:00',
    playCountLabel: '1',
    danmakuCountLabel: '0',
  );
}

final class _FakePlaybackVmClient extends BiliClient {
  List<BiliVideoComment> comments = const <BiliVideoComment>[];
  List<BiliVideoComment> extraComments = const <BiliVideoComment>[];
  Object? commentError;
  final Map<int, List<BiliVideoComment>> commentReplyPages =
      <int, List<BiliVideoComment>>{};
  int commentReplyTotalCount = 0;
  Object? commentReplyError;
  BiliVideoEngagement engagement = const BiliVideoEngagement.guest();
  List<BiliFeedVideo> relatedVideos = const <BiliFeedVideo>[];
  List<BiliFeedVideo> recommended = const <BiliFeedVideo>[];
  Object? relatedError;
  Object? recommendedError;
  int coinCount = 0;
  Completer<BiliVideoEngagement>? engagementCompleter;
  Completer<BiliVideoEngagement>? likeCompleter;
  final List<String> sentComments = <String>[];

  @override
  Future<BiliVideoCommentPage> fetchVideoCommentPage(
    BiliVideoDetail detail, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final error = commentError;
    if (error != null) {
      throw error;
    }
    final pageComments = switch (page) {
      1 => comments.take(pageSize).toList(growable: false),
      2 => extraComments.take(pageSize).toList(growable: false),
      _ => const <BiliVideoComment>[],
    };
    return BiliVideoCommentPage(
      comments: pageComments,
      page: page,
      pageSize: pageSize,
      totalCount: comments.length + extraComments.length,
      hasMore: page == 1 && extraComments.isNotEmpty,
    );
  }

  @override
  Future<BiliVideoCommentReplyPage> fetchVideoCommentReplyPage(
    BiliVideoDetail detail, {
    required int rootReplyId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final error = commentReplyError;
    if (error != null) {
      throw error;
    }
    final replies = commentReplyPages[page] ?? const <BiliVideoComment>[];
    return BiliVideoCommentReplyPage(
      replies: replies.take(pageSize).toList(growable: false),
      page: page,
      pageSize: pageSize,
      totalCount: commentReplyTotalCount,
      hasMore: replies.isNotEmpty && page * pageSize < commentReplyTotalCount,
    );
  }

  @override
  Future<BiliVideoComment?> addVideoComment({
    required BiliVideoDetail detail,
    required String message,
  }) async {
    sentComments.add(message);
    return _comment(700 + sentComments.length, '我', message);
  }

  @override
  Future<BiliVideoEngagement> fetchVideoEngagement(
    BiliVideoDetail detail,
  ) async {
    final completer = engagementCompleter;
    if (completer != null) {
      return completer.future;
    }
    return engagement;
  }

  @override
  Future<int> fetchVideoCoinCount(BiliVideoDetail detail) async {
    return coinCount;
  }

  @override
  Future<BiliVideoEngagement> setVideoLike({
    required BiliVideoDetail detail,
    required bool liked,
    BiliVideoEngagement? current,
  }) async {
    final completer = likeCompleter;
    if (completer != null) {
      return completer.future;
    }
    engagement = (current ?? engagement).copyWith(isLiked: liked);
    return engagement;
  }

  @override
  Future<int> addVideoCoin({
    required BiliVideoDetail detail,
    int multiply = 1,
    bool selectLike = true,
  }) async {
    coinCount += multiply;
    engagement = engagement.copyWith(isAuthenticated: true, isLiked: true);
    return coinCount;
  }

  @override
  Future<BiliVideoEngagement> setVideoFavorite({
    required BiliVideoDetail detail,
    required bool favorited,
    BiliVideoEngagement? current,
  }) async {
    engagement = (current ?? engagement).copyWith(isFavorited: favorited);
    return engagement;
  }

  @override
  Future<BiliVideoEngagement> setOwnerFollow({
    required BiliVideoDetail detail,
    required bool following,
    BiliVideoEngagement? current,
  }) async {
    engagement = (current ?? engagement).copyWith(isFollowingOwner: following);
    return engagement;
  }

  @override
  Future<int?> recordVideoShare({required BiliVideoDetail detail}) async {
    return null;
  }

  @override
  Future<List<BiliFeedVideo>> fetchRelatedVideos(
    BiliVideoDetail detail, {
    int limit = 12,
  }) async {
    final error = relatedError;
    if (error != null) {
      throw error;
    }
    return relatedVideos.take(limit).toList(growable: false);
  }

  @override
  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) async {
    final error = recommendedError;
    if (error != null) {
      throw error;
    }
    return page == 1 ? recommended : const <BiliFeedVideo>[];
  }
}

final class _FakeVmOfflineController extends BiliOfflineDownloadController {
  _FakeVmOfflineController() : super(client: BiliClient());
}
