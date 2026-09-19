import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/bili/app_mode/pages/bili_favorites_page.dart';
import 'package:vesper_media/bili/common/models/bili_favorites_models.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/pages/bili_playback_content_surfaces.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'package:vesper_media/bili/common/view_models/bili_favorites_view_model.dart';
import 'package:vesper_media/bili/common/view_models/bili_playback_view_model.dart';
import 'package:vesper_media/download/download.dart';
import 'package:vesper_media/danmaku/danmaku.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_media/media/models/media_hdr_status.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'deleting first-page favorite must not skip shifted next-page item',
    () async {
      final client = _FavoritesClient();
      final vm = BiliFavoritesViewModel(client: client);
      addTearDown(vm.dispose);
      await vm.initialize();
      expect(vm.items.value.length, 20);
      await vm.removeItems(['1:2']);
      await vm.loadMore();
      expect(vm.items.value.map((e) => e.id), contains(21));
    },
  );

  test(
    'late folder A deletion must not delete the same item from folder B',
    () async {
      final client = _FavoritesClient()..removal = Completer<void>();
      final vm = BiliFavoritesViewModel(client: client);
      addTearDown(vm.dispose);
      await vm.initialize();
      final pending = vm.removeItems(['1:2']);
      await vm.selectFolder(2);
      expect(vm.items.value.single.id, 1);
      client.removal!.complete();
      await pending;
      expect(vm.items.value.map((e) => e.id), contains(1));
    },
  );

  testWidgets('account with no folders can create its first folder', (
    tester,
  ) async {
    final client = _FavoritesClient()..emptyFolders = true;
    await tester.pumpWidget(
      MaterialApp(home: BiliFavoritesPage(client: client)),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有收藏夹。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bili-favorites-create-folder')),
      findsOneWidget,
    );
  });

  test(
    'a removal completed after account change discards old account data',
    () async {
      final client = _FavoritesClient()..removal = Completer<void>();
      final vm = BiliFavoritesViewModel(client: client);
      addTearDown(vm.dispose);
      await vm.initialize();
      final pending = vm.removeItems(['1:2']);
      client.restoreCookies({'DedeUserID': '2'});
      client.removal!.complete();
      expect(await pending, isNull);
      expect(vm.items.value, isEmpty);
      expect(vm.folders.value, isEmpty);
      expect(vm.isMutating.value, isFalse);
    },
  );

  test('10-bit AV1 without HDR transfer metadata is not proof of HDR10', () {
    final source = mediaHdrSourceForTrack(
      const VesperMediaTrack(
        id: 'video-80-13-1-0',
        kind: VesperMediaTrackKind.video,
        codec: 'av01.0.08M.10',
        label: '1080P',
      ),
      qualityId: 80,
    );
    expect(source, isNot(MediaHdrSource.hdr10));
  });

  test(
    'P010 session probe with unsupported display is not confirmed HDR output',
    () {
      final state = mediaHdrStatusFromProbe(
        probe: const VesperPlaybackCapabilityProbeResult(
          status: VesperPlaybackCapabilityProbeStatus.unsupported,
          codecFamily: VesperPlaybackCodecFamily.hevc,
          systemPlaybackSupported: false,
          hardwareDecodeSupported: true,
          sdkManagedNativeFrameSupported: false,
          recommendedPlaybackPath: VesperRecommendedPlaybackPath.systemPlayer,
          outputFormat: VesperPlaybackCapabilityOutputFormat.p010,
          hdrKind: VesperPlaybackCapabilityHdrKind.hdr10,
          dolbyVisionMode: VesperPlaybackCapabilityDolbyVisionMode.none,
          confidence: VesperPlaybackCapabilityConfidence.sessionProbe,
          diagnostics: {'displayHdrSupported': false},
        ),
        source: MediaHdrSource.hdr10,
        playability: MediaHdrPlayability.unplayable,
      );
      expect(state.isOutputConfirmed, isFalse);
    },
  );

  test(
    'production timeout exception must leave danmaku result pending',
    () async {
      final provider = BiliDanmakuProvider(repository: _DanmakuRepository());
      addTearDown(provider.dispose);
      final session =
          provider.openSession(_target) as MediaDanmakuSessionSender;
      final result = await session.send(
        const MediaDanmakuSendRequest(text: 'test', positionMs: 0),
      );
      expect(result.isPending, isTrue);
    },
  );

  test(
    'protobuf synthetic identity must not be marked as server dmid',
    () async {
      final parsed = const BiliDanmakuSegmentParser().parse([
        10,
        7,
        16,
        0,
        24,
        1,
        58,
        1,
        120,
      ]);
      expect(parsed.single.rowId, '0:1:x');
      final provider = BiliDanmakuProvider(
        repository: _DanmakuRepository(entries: parsed),
      );
      addTearDown(provider.dispose);
      final session = provider.openSession(_target);
      final snapshots = <MediaDanmakuSnapshot>[];
      final subscription = session.snapshots.listen(snapshots.add);
      addTearDown(subscription.cancel);
      session.updatePosition(0);
      await pumpEventQueue();
      expect(snapshots.last.events.single.hasServerId, isFalse);
    },
  );

  testWidgets(
    'comment like repaint follows its shared signal without parent rebuild',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final client = _CommentClient();
      final historyDirectory = Directory.systemTemp.createTempSync(
        'vesper-acceptance-history-',
      );
      addTearDown(() => historyDirectory.deleteSync(recursive: true));
      final vm = BiliPlaybackViewModel(
        detail: _detail,
        initialPage: _detail.pages.first,
        client: client,
        historyStore: BiliHistoryStore(baseDirectory: historyDirectory),
        offlineController: _OfflineClient(),
      );
      addTearDown(vm.dispose);
      unawaited(vm.controllerFuture.then<void>((_) {}, onError: (Object _) {}));
      final controllers = List.generate(3, (_) => ScrollController());
      final input = TextEditingController();
      final focus = FocusNode();
      addTearDown(() {
        for (final c in controllers) {
          c.dispose();
        }
        input.dispose();
        focus.dispose();
      });
      final host = MediaPlaybackContentHost(
        surfaceHost: MediaSurfaceHost(pushPlayback: (_, _) {}),
        relatedScrollController: controllers[0],
        commentsScrollController: controllers[1],
        commentRepliesScrollController: controllers[2],
        commentComposerController: input,
        commentComposerFocusNode: focus,
        onContentScroll: (_) => false,
        onCommentRepliesVisibilityChanged: (_) {},
        onSeekToTime: (_) async {},
      );
      final surfaces = BiliPlaybackContentSurfaces(
        viewModel: vm,
        detail: _detail,
        host: host,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  surfaces.buildCommentsSurface(context, _target)!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('comment-like-action'));
      expect(
        find.descendant(of: action, matching: find.text('37')),
        findsOneWidget,
      );
      await tester.tap(action);
      await tester.pump();
      expect(vm.commentLikeStateFor(_comment).liked, isTrue);
      expect(
        find.descendant(of: action, matching: find.text('38')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

BiliFavoriteItem _item(int id) => BiliFavoriteItem(
  id: id,
  bvid: 'BV$id',
  title: 'item $id',
  coverUrl: '',
  ownerName: '',
  durationLabel: '',
  playCountLabel: '',
  favoritedAtLabel: '',
  isAvailable: true,
);

class _FavoritesClient extends BiliClient {
  final data = <int, List<BiliFavoriteItem>>{
    1: List.generate(21, (i) => _item(i + 1)),
    2: [_item(1)],
  };
  Completer<void>? removal;
  bool emptyFolders = false;
  @override
  bool get hasAuthenticatedSession => true;
  @override
  Future<List<BiliFavoriteFolder>> fetchFavoriteFolders() async => emptyFolders
      ? []
      : [
          for (final e in data.entries)
            BiliFavoriteFolder(
              id: e.key,
              title: 'folder ${e.key}',
              containsCurrentVideo: false,
              mediaCount: e.value.length,
            ),
        ];
  @override
  Future<BiliFavoritePage> fetchFavoriteItems({
    required int folderId,
    int page = 1,
    int pageSize = 20,
    String keyword = '',
    BiliFavoriteOrder order = BiliFavoriteOrder.recent,
  }) async => BiliFavoritePage(
    items: data[folderId]!.skip((page - 1) * pageSize).take(pageSize).toList(),
    page: page,
    pageSize: pageSize,
    hasMore: page * pageSize < data[folderId]!.length,
  );
  @override
  Future<void> removeFavoriteItems({
    required int folderId,
    required List<String> resourceIds,
  }) async {
    if (removal != null) await removal!.future;
    data[folderId]!.removeWhere((e) => resourceIds.contains(e.resourceKey));
  }
}

class _DanmakuRepository
    implements BiliDanmakuRepository, BiliDanmakuSendRepository {
  _DanmakuRepository({this.entries = const []});
  final List<BiliDanmakuEntry> entries;
  @override
  Future<List<BiliDanmakuEntry>> loadSegment({
    required String bvid,
    required int cid,
    required int aid,
    required int segmentIndex,
  }) async => entries;
  @override
  Future<List<BiliDanmakuEntry>> loadLegacyEntries({
    required String bvid,
    required int cid,
  }) async => entries;
  @override
  Future<String> postDanmaku({
    required String bvid,
    required int cid,
    required int aid,
    required String text,
    required int progressMs,
    required int mode,
    required int fontSize,
    required int color,
  }) async => throw const BiliApiException(
    'Bilibili request timed out after 15s.',
    outcomeUnknown: true,
  );
}

const _target = MediaPlaybackTarget(
  detail: MediaDetail(
    mediaId: 'BVTEST',
    title: 'test',
    coverUrl: '',
    pages: [],
  ),
  entry: MediaPlaybackEntry(
    entryId: '11',
    pageNumber: 1,
    title: 'test',
    durationSeconds: 120,
  ),
);
const _detail = BiliVideoDetail(
  aid: 1,
  bvid: 'BVTEST',
  title: 'test',
  ownerMid: 1,
  ownerName: '',
  ownerAvatarUrl: '',
  coverUrl: '',
  description: '',
  publishedAtLabel: '',
  playCountLabel: '',
  danmakuCountLabel: '',
  replyCountLabel: '',
  likeCountLabel: '',
  coinCountLabel: '',
  favoriteCountLabel: '',
  shareCountLabel: '',
  pages: [
    BiliVideoPageEntry(
      cid: 11,
      pageNumber: 1,
      title: 'P1',
      durationSeconds: 120,
    ),
  ],
);
const _comment = BiliVideoComment(
  id: 1,
  authorName: 'review',
  authorAvatarUrl: '',
  createdAtLabel: '',
  message: 'comment',
  likeCountLabel: '37',
  likeCount: 37,
  pictures: [],
  replies: [],
  timeLinks: [],
);

class _OfflineClient extends BiliOfflineDownloadController {
  _OfflineClient() : super(client: BiliClient());
}

class _CommentClient extends BiliClient {
  @override
  Future<BiliResolvedPlayback> resolvePlayback({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
    required TargetPlatform platform,
  }) async => throw const BiliApiException(
    'No native player required for comment widget acceptance',
  );
  @override
  Future<bool> isVideoInWatchLater({required String bvid, int? aid}) async =>
      false;
  @override
  Future<BiliVideoEngagement> fetchVideoEngagement(
    BiliVideoDetail detail,
  ) async => const BiliVideoEngagement.guest();
  @override
  Future<List<BiliFeedVideo>> fetchRelatedVideos(
    BiliVideoDetail detail, {
    int limit = 12,
  }) async => [];
  @override
  Future<BiliVideoCommentPage> fetchVideoCommentPage(
    BiliVideoDetail detail, {
    int page = 1,
    int pageSize = 20,
  }) async => BiliVideoCommentPage(
    comments: [_comment],
    page: 1,
    pageSize: 20,
    totalCount: 1,
    hasMore: false,
  );
  @override
  Future<void> setVideoCommentLike({
    required BiliVideoDetail detail,
    required int commentId,
    required bool liked,
  }) async {}
}
