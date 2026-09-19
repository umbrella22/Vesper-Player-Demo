import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/danmaku/danmaku.dart';
import 'package:vesper_media/media/media.dart';

const _entryTarget = MediaPlaybackTarget(
  detail: MediaDetail(
    mediaId: 'BV-COLLECTION',
    title: '测试合集',
    coverUrl: '',
    pages: <MediaPlaybackEntry>[],
    platformExtras: <String, Object?>{'aid': 100},
  ),
  entry: MediaPlaybackEntry(
    entryId: '9001',
    pageNumber: 1,
    title: '第一集',
    durationSeconds: 2000,
    platformExtras: <String, Object?>{'aid': 200, 'bvid': 'BV-EPISODE'},
  ),
);

BiliDanmakuEntry _entry({
  required String id,
  required int timeMs,
  BiliDanmakuMode mode = BiliDanmakuMode.scroll,
  int pool = 0,
  int? weight = 0,
  String senderHash = '',
  String? text,
}) {
  return BiliDanmakuEntry(
    appearAtMs: timeMs,
    mode: mode,
    fontSize: 25,
    colorValue: 0xFFFFFF,
    text: text ?? id,
    rowId: id,
    weight: weight,
    pool: pool,
    senderHash: senderHash,
  );
}

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 6; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('BiliDanmakuProvider session', () {
    test('360 秒边界切段并只请求当前段前后窗口', () async {
      final repository = _FakeDanmakuRepository();
      final session = BiliDanmakuProvider(
        repository: repository,
      ).openSession(_entryTarget);
      addTearDown(session.close);

      session.updatePosition(biliDanmakuSegmentDurationMs - 1);
      await _flushAsyncWork();
      expect(repository.segmentIndexes, <int>[1, 2]);

      session.updatePosition(biliDanmakuSegmentDurationMs);
      await _flushAsyncWork();
      expect(repository.segmentIndexes, <int>[1, 2, 3]);
      expect(
        repository.requests.every((request) => request.cid == 9001),
        isTrue,
      );
      expect(
        repository.requests.every((request) => request.aid == 200),
        isTrue,
      );
      expect(
        repository.requests.every((request) => request.bvid == 'BV-EPISODE'),
        isTrue,
      );
    });

    test('同段更新合并请求，跨段 seek 淘汰迟到结果', () async {
      final completions = <int, Completer<List<BiliDanmakuEntry>>>{};
      final repository = _FakeDanmakuRepository(
        loadSegment: (request) {
          return completions
              .putIfAbsent(
                request.segmentIndex,
                Completer<List<BiliDanmakuEntry>>.new,
              )
              .future;
        },
      );
      final session = BiliDanmakuProvider(
        repository: repository,
      ).openSession(_entryTarget);
      final snapshots = <MediaDanmakuSnapshot>[];
      final subscription = session.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
      });

      session
        ..updatePosition(0)
        ..updatePosition(1000);
      expect(repository.segmentIndexes, <int>[1, 2]);

      session.updatePosition(biliDanmakuSegmentDurationMs * 3);
      expect(repository.segmentIndexes, <int>[1, 2, 4, 3, 5]);

      completions[1]!.complete(<BiliDanmakuEntry>[
        _entry(id: 'stale-1', timeMs: 100),
      ]);
      completions[2]!.complete(<BiliDanmakuEntry>[
        _entry(id: 'stale-2', timeMs: 200),
      ]);
      await _flushAsyncWork();
      expect(
        snapshots.last.events.map((event) => event.id),
        isNot(contains(startsWith('stale-'))),
      );

      for (final segment in <int>[3, 4, 5]) {
        completions[segment]!.complete(<BiliDanmakuEntry>[
          _entry(id: 'current-$segment', timeMs: segment * 1000),
        ]);
      }
      await _flushAsyncWork();
      expect(
        snapshots.last.events.map((event) => event.id),
        containsAll(<String>['current-3', 'current-4', 'current-5']),
      );
    });

    test('跨段按 dmid 去重并映射字幕池，过滤特殊池与高级模式', () async {
      final repository = _FakeDanmakuRepository(
        loadSegment: (request) async {
          if (request.segmentIndex == 1) {
            return <BiliDanmakuEntry>[
              _entry(id: 'same', timeMs: 100),
              _entry(id: 'caption', timeMs: 200, pool: 1),
              _entry(id: 'special', timeMs: 300, pool: 2),
              _entry(
                id: 'advanced',
                timeMs: 400,
                mode: BiliDanmakuMode.unsupported,
              ),
            ];
          }
          return <BiliDanmakuEntry>[
            _entry(id: 'same', timeMs: 100),
            _entry(id: 'reverse', timeMs: 500, mode: BiliDanmakuMode.reverse),
          ];
        },
      );
      final session = BiliDanmakuProvider(
        repository: repository,
      ).openSession(_entryTarget);
      final snapshots = <MediaDanmakuSnapshot>[];
      final subscription = session.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
      });

      session.updatePosition(0);
      await _flushAsyncWork();

      final events = snapshots.last.events;
      expect(events.map((event) => event.id), <String>[
        'same',
        'caption',
        'reverse',
      ]);
      expect(events.where((event) => event.id == 'same'), hasLength(1));
      final caption = events.singleWhere((event) => event.id == 'caption');
      expect(caption.channel, MediaDanmakuChannel.caption);
      expect(caption.style.position, MediaDanmakuPosition.bottom);
      expect(
        events.singleWhere((event) => event.id == 'reverse').style.position,
        MediaDanmakuPosition.reverse,
      );
      expect(() => events.add(events.first), throwsUnsupportedError);
    });

    test('mode 7 输出高级事件，mode 8、mode 9 与损坏 mode 7 被丢弃', () async {
      final repository = _FakeDanmakuRepository(
        loadSegment: (request) async => request.segmentIndex == 1
            ? <BiliDanmakuEntry>[
                _entry(id: 'standard', timeMs: 100),
                _entry(
                  id: 'advanced',
                  timeMs: 200,
                  mode: BiliDanmakuMode.advanced,
                  text: '[0,0,"0.4-1",4,"advanced",0,0,672,438,2000,100]',
                ),
                _entry(
                  id: 'broken-advanced',
                  timeMs: 300,
                  mode: BiliDanmakuMode.advanced,
                  text: 'not json',
                ),
                _entry(
                  id: 'code',
                  timeMs: 400,
                  mode: BiliDanmakuMode.code,
                  pool: 2,
                  text: 'thirdParty.execute()',
                ),
                _entry(
                  id: 'bas',
                  timeMs: 500,
                  mode: BiliDanmakuMode.bas,
                  pool: 2,
                  text: '<bas>payload</bas>',
                ),
              ]
            : const <BiliDanmakuEntry>[],
      );
      final session = BiliDanmakuProvider(
        repository: repository,
      ).openSession(_entryTarget);
      final snapshots = <MediaDanmakuSnapshot>[];
      final subscription = session.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
      });

      session.updatePosition(0);
      await _flushAsyncWork();

      expect(snapshots.last.events.map((event) => event.id), <String>[
        'standard',
      ]);
      expect(snapshots.last.advancedEvents.map((event) => event.id), <String>[
        'advanced',
      ]);
      final advanced = snapshots.last.advancedEvents.single;
      expect(advanced.path, hasLength(2));
      expect(advanced.alphaFrom, 0.4);
      expect(advanced.alphaTo, 1);
      expect(
        () => snapshots.last.advancedEvents.add(advanced),
        throwsUnsupportedError,
      );
    });

    test('特殊包失败不影响普通段、不触发 XML 降级且每会话只请求一次', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logs.add(message);
        }
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
      });
      final repository = _FakeDanmakuRepository(
        loadSegment: (_) async => <BiliDanmakuEntry>[
          _entry(id: 'ordinary', timeMs: 100),
        ],
        specialLoader: () async {
          throw const FormatException(
            'bad special package token=do-not-log-this-secret',
          );
        },
      );
      final session = BiliDanmakuProvider(
        repository: repository,
      ).openSession(_entryTarget);
      final snapshots = <MediaDanmakuSnapshot>[];
      final subscription = session.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
      });

      session
        ..updatePosition(0)
        ..updatePosition(biliDanmakuSegmentDurationMs);
      await _flushAsyncWork();

      expect(repository.specialCalls, 1);
      expect(repository.legacyCalls, 0);
      expect(
        snapshots.last.events.map((event) => event.id),
        contains('ordinary'),
      );
      expect(snapshots.last.error, isNull);
      expect(logs.join('\n'), contains('FormatException'));
      expect(logs.join('\n'), isNot(contains('do-not-log-this-secret')));
    });

    test('weight 边界和 sender hash 精确过滤可在会话中动态更新', () async {
      final repository = _FakeDanmakuRepository(
        loadSegment: (request) async => request.segmentIndex == 1
            ? <BiliDanmakuEntry>[
                _entry(id: 'low', timeMs: 100, weight: 2),
                _entry(id: 'boundary', timeMs: 200, weight: 3),
                _entry(
                  id: 'blocked',
                  timeMs: 300,
                  weight: 9,
                  senderHash: 'Sender Hash',
                ),
              ]
            : const <BiliDanmakuEntry>[],
      );
      final filter = ValueNotifier<BiliDanmakuSourceFilterSettings>(
        const BiliDanmakuSourceFilterSettings(
          minimumWeight: 3,
          blockedSenderHashes: <String>['Sender Hash'],
        ),
      );
      final provider = BiliDanmakuProvider(repository: repository)
        ..bindSourceFilter(filter);
      final session = provider.openSession(_entryTarget);
      final snapshots = <MediaDanmakuSnapshot>[];
      final subscription = session.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
        provider.dispose();
        filter.dispose();
      });

      session.updatePosition(0);
      await _flushAsyncWork();
      expect(snapshots.last.events.map((event) => event.id), <String>[
        'boundary',
      ]);

      filter.value = const BiliDanmakuSourceFilterSettings(
        blockedSenderHashes: <String>['sender hash'],
      );

      expect(snapshots.last.events.map((event) => event.id), <String>[
        'low',
        'boundary',
        'blocked',
      ]);
    });

    test('当前段失败时回退 XML 且缺失权重不触发云过滤', () async {
      final repository = _FakeDanmakuRepository(
        loadSegment: (request) async {
          if (request.segmentIndex == 1) {
            throw const FormatException('bad segment');
          }
          return const <BiliDanmakuEntry>[];
        },
        legacyEntries: const BiliDanmakuParser().parse('''
<i>
  <d p="1,1,25,16777215,0,0,hash,legacy">legacy</d>
</i>
'''),
      );
      final filter = ValueNotifier<BiliDanmakuSourceFilterSettings>(
        const BiliDanmakuSourceFilterSettings(minimumWeight: 1),
      );
      final provider = BiliDanmakuProvider(repository: repository)
        ..bindSourceFilter(filter);
      final session = provider.openSession(_entryTarget);
      final snapshots = <MediaDanmakuSnapshot>[];
      final subscription = session.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
        provider.dispose();
        filter.dispose();
      });

      session.updatePosition(0);
      await _flushAsyncWork();

      expect(repository.legacyCalls, 1);
      expect(snapshots.last.events.single.id, 'legacy');
      expect(snapshots.last.isLoading, isFalse);
      expect(snapshots.last.error, isNull);
    });

    test('相邻段失败不触发全量降级', () async {
      final repository = _FakeDanmakuRepository(
        loadSegment: (request) async {
          if (request.segmentIndex == 2) {
            throw const FormatException('bad adjacent segment');
          }
          return <BiliDanmakuEntry>[_entry(id: 'current', timeMs: 100)];
        },
      );
      final session = BiliDanmakuProvider(
        repository: repository,
      ).openSession(_entryTarget);
      final snapshots = <MediaDanmakuSnapshot>[];
      final subscription = session.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
      });

      session.updatePosition(0);
      await _flushAsyncWork();

      expect(repository.legacyCalls, 0);
      expect(snapshots.last.events.single.id, 'current');
      expect(snapshots.last.error, isNull);
    });
  });

  group('BiliDanmakuProvider send', () {
    Future<
      ({
        _FakeDanmakuRepository repository,
        MediaDanmakuSession session,
        List<MediaDanmakuSnapshot> snapshots,
      })
    >
    openSendSession({Object? sendError, bool pendingSend = false}) async {
      final repository = _FakeDanmakuRepository(
        loadSegment: (request) async => <BiliDanmakuEntry>[],
        sendError: sendError,
        pendingSend: pendingSend,
      );
      final provider = BiliDanmakuProvider(repository: repository);
      final session = provider.openSession(_entryTarget);
      final snapshots = <MediaDanmakuSnapshot>[];
      final subscription = session.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
        provider.dispose();
      });
      session.updatePosition(0);
      await _flushAsyncWork();
      return (repository: repository, session: session, snapshots: snapshots);
    }

    test('成功后才把弹幕插入快照，并保留在后续刷新中', () async {
      final harness = await openSendSession();
      final sender = harness.session as MediaDanmakuSessionSender;
      expect(harness.repository.sends, isEmpty);

      final result = await sender.send(
        const MediaDanmakuSendRequest(text: '  测试弹幕  ', positionMs: 4200),
      );

      expect(result.isSuccess, isTrue);
      expect(result.event!.text, '测试弹幕');
      expect(result.event!.timeMs, 4200);
      final send = harness.repository.sends.single;
      expect(send.text, '测试弹幕');
      expect(send.progressMs, 4200);
      expect(send.mode, 1);
      expect(send.color, 16777215);
      expect(harness.snapshots.last.events.single.id, result.event!.id);

      // 分段刷新会重建快照，本地弹幕不应被冲掉。
      harness.session.updatePosition(1000);
      await _flushAsyncWork();
      expect(
        harness.snapshots.last.events.map((event) => event.id),
        contains(result.event!.id),
      );
    });

    test('位置与颜色映射到普通弹幕池的 mode', () async {
      final harness = await openSendSession();
      final sender = harness.session as MediaDanmakuSessionSender;

      await sender.send(
        const MediaDanmakuSendRequest(
          text: '顶部',
          positionMs: 100,
          style: MediaDanmakuStyle(
            position: MediaDanmakuPosition.top,
            color: 0xFF0000,
          ),
        ),
      );
      await sender.send(
        const MediaDanmakuSendRequest(
          text: '底部',
          positionMs: 200,
          style: MediaDanmakuStyle(position: MediaDanmakuPosition.bottom),
        ),
      );

      expect(harness.repository.sends.map((send) => send.mode), [5, 4]);
      expect(harness.repository.sends.first.color, 0xFF0000);
    });

    test('失败不修改快照，并返回可展示文案', () async {
      final harness = await openSendSession(
        sendError: const BiliApiException('弹幕发送过于频繁'),
      );
      final sender = harness.session as MediaDanmakuSessionSender;
      final before = harness.snapshots.last;

      final result = await sender.send(
        const MediaDanmakuSendRequest(text: '失败弹幕', positionMs: 100),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('弹幕发送过于频繁'));
      expect(harness.snapshots.last.events, before.events);
    });

    test('超时返回 pending 且不插入、不自动重发', () async {
      final harness = await openSendSession(pendingSend: true);
      final sender = harness.session as MediaDanmakuSessionSender;

      final result = await sender.send(
        const MediaDanmakuSendRequest(text: '超时弹幕', positionMs: 100),
      );

      expect(result.isPending, isTrue);
      expect(result.isSuccess, isFalse);
      expect(harness.snapshots.last.events, isEmpty);
      // 只提交一次，不重发。
      expect(harness.repository.sends, hasLength(1));
    });

    test('空文本与非法 mode 在本地被拒绝，不发出写请求', () async {
      final harness = await openSendSession();
      final sender = harness.session as MediaDanmakuSessionSender;

      expect(
        (await sender.send(
          const MediaDanmakuSendRequest(text: '   ', positionMs: 0),
        )).errorMessage,
        contains('不能为空'),
      );
      expect(harness.repository.sends, isEmpty);
    });

    test('点赞去重、成功保留状态，失败回滚', () async {
      final harness = await openSendSession();
      final interactions = harness.session as MediaDanmakuSessionInteractions;
      const event = MediaDanmakuEvent(id: '701', timeMs: 100, text: '测试');
      final gate = Completer<void>();
      harness.repository.likeHandler = () => gate.future;

      final pending = interactions.toggleLike(event);
      expect(interactions.interactionStateFor(event).liked, isTrue);
      expect(interactions.interactionStateFor(event).pending, isTrue);
      expect(await interactions.toggleLike(event), contains('正在进行'));
      expect(harness.repository.likes, hasLength(1));
      gate.complete();
      expect(await pending, isNull);
      expect(interactions.interactionStateFor(event).pending, isFalse);

      harness.repository.likeHandler = () async {
        throw const BiliApiException('请求被拒绝');
      };
      expect(await interactions.toggleLike(event), contains('请求被拒绝'));
      expect(interactions.interactionStateFor(event).liked, isTrue);
      expect(interactions.interactionStateFor(event).pending, isFalse);
      expect(harness.repository.likes.map((request) => request.liked), [
        true,
        false,
      ]);
    });

    test('合成 ID、其他人的弹幕和游客不发出写请求', () async {
      final harness = await openSendSession();
      final interactions = harness.session as MediaDanmakuSessionInteractions;
      const synthetic = MediaDanmakuEvent(
        id: 'local:100',
        timeMs: 100,
        text: '合成',
        hasServerId: false,
      );
      const event = MediaDanmakuEvent(id: '701', timeMs: 100, text: '他人');
      expect(interactions.interactionStateFor(synthetic).canLike, isFalse);
      expect(await interactions.toggleLike(synthetic), isNotNull);
      expect(await interactions.retract(event), contains('只能撤回'));
      harness.repository.hasAuthenticatedSession = false;
      expect(await interactions.toggleLike(event), contains('先登录'));
      expect(harness.repository.likes, isEmpty);
      expect(harness.repository.retractions, isEmpty);
    });

    test('账号变化后丢弃旧点赞结果，不覆盖新账号的请求', () async {
      final harness = await openSendSession();
      final interactions = harness.session as MediaDanmakuSessionInteractions;
      const event = MediaDanmakuEvent(id: '701', timeMs: 100, text: '测试');
      final oldGate = Completer<void>();
      harness.repository.likeHandler = () => oldGate.future;
      final oldRequest = interactions.toggleLike(event);

      harness.repository.sessionRevision++;
      expect(interactions.interactionStateFor(event).liked, isFalse);
      expect(interactions.interactionStateFor(event).pending, isFalse);
      harness.repository.likeHandler = null;
      expect(await interactions.toggleLike(event), isNull);
      oldGate.completeError(const BiliApiException('旧请求失败'));
      expect(await oldRequest, contains('账号已变化'));
      expect(interactions.interactionStateFor(event).liked, isTrue);
      expect(interactions.interactionStateFor(event).pending, isFalse);
    });

    test('本人撤回成功后缓存分段不能让弹幕重新出现', () async {
      final harness = await openSendSession();
      final sender = harness.session as MediaDanmakuSessionSender;
      final interactions = harness.session as MediaDanmakuSessionInteractions;
      final result = await sender.send(
        const MediaDanmakuSendRequest(text: '我的弹幕', positionMs: 100),
      );
      final event = result.event!;
      expect(interactions.interactionStateFor(event).canRetract, isTrue);
      harness.repository.cachedEntries = [_entry(id: event.id, timeMs: 100)];
      expect(await interactions.retract(event), isNull);
      expect(harness.repository.retractions.single, (
        bvid: 'BV-EPISODE',
        cid: 9001,
        dmid: event.id,
      ));
      expect(harness.snapshots.last.events, isEmpty);
      harness.session.updatePosition(biliDanmakuSegmentDurationMs * 3);
      await _flushAsyncWork();
      expect(harness.snapshots.last.events, isEmpty);
      expect(interactions.interactionStateFor(event).canLike, isFalse);
      expect(interactions.interactionStateFor(event).canRetract, isFalse);
    });

    test('撤回失败保留弹幕，切账号失去本人撤回资格', () async {
      final harness = await openSendSession();
      final sender = harness.session as MediaDanmakuSessionSender;
      final interactions = harness.session as MediaDanmakuSessionInteractions;
      final result = await sender.send(
        const MediaDanmakuSendRequest(text: '我的弹幕', positionMs: 100),
      );
      final event = result.event!;
      harness.repository.retractHandler = () async {
        throw const BiliApiException('已超过撤回时限');
      };
      expect(await interactions.retract(event), contains('撤回时限'));
      expect(harness.snapshots.last.events.single.id, event.id);
      harness.repository.sessionRevision++;
      expect(interactions.interactionStateFor(event).canRetract, isFalse);
      expect(await interactions.retract(event), contains('只能撤回'));
      expect(harness.repository.retractions, hasLength(1));
    });

    test('发送中切换账号不把旧账号弹幕归为本人所有', () async {
      final harness = await openSendSession();
      final gate = Completer<String>();
      harness.repository.sendGate = gate;
      final result = (harness.session as MediaDanmakuSessionSender).send(
        const MediaDanmakuSendRequest(text: '旧账号', positionMs: 100),
      );
      harness.repository.sessionRevision++;
      gate.complete('701');
      expect((await result).isPending, isTrue);
      expect(harness.snapshots.last.events, isEmpty);
      const event = MediaDanmakuEvent(id: '701', timeMs: 100, text: '旧账号');
      expect(
        (harness.session as MediaDanmakuSessionInteractions)
            .interactionStateFor(event)
            .canRetract,
        isFalse,
      );
    });

    test('点赞中关闭会话不再写入已释放的状态', () async {
      final harness = await openSendSession();
      final interactions = harness.session as MediaDanmakuSessionInteractions;
      final gate = Completer<void>();
      harness.repository.likeHandler = () => gate.future;
      const event = MediaDanmakuEvent(id: '701', timeMs: 100, text: '测试');
      final pending = interactions.toggleLike(event);
      await harness.session.close();
      gate.complete();
      expect(await pending, contains('会话或登录账号已变化'));
      expect(interactions.interactionStateFor(event).canLike, isFalse);
    });
  });
}

typedef _SegmentLoader =
    Future<List<BiliDanmakuEntry>> Function(_SegmentRequest request);

typedef _SpecialLoader = Future<List<BiliDanmakuEntry>> Function();

final class _FakeDanmakuRepository
    implements
        BiliDanmakuRepository,
        BiliSpecialDanmakuRepository,
        BiliDanmakuSendRepository,
        BiliDanmakuInteractionRepository {
  _FakeDanmakuRepository({
    this._loadSegment,
    this.specialLoader,
    this.legacyEntries = const <BiliDanmakuEntry>[],
    this.sendError,
    this.pendingSend = false,
  });

  final _SegmentLoader? _loadSegment;
  final _SpecialLoader? specialLoader;
  final List<BiliDanmakuEntry> legacyEntries;
  final List<_SegmentRequest> requests = <_SegmentRequest>[];
  final List<_SendRequest> sends = <_SendRequest>[];
  Object? sendError;
  bool pendingSend;
  int legacyCalls = 0;
  int specialCalls = 0;
  int _nextDmid = 5000;
  @override
  int sessionRevision = 0;
  @override
  bool hasAuthenticatedSession = true;
  Completer<String>? sendGate;
  List<BiliDanmakuEntry>? cachedEntries;
  final likes = <({String bvid, int cid, String dmid, bool liked})>[];
  final retractions = <({String bvid, int cid, String dmid})>[];
  Future<void> Function()? likeHandler;
  Future<void> Function()? retractHandler;

  @override
  Future<void> setDanmakuLike({
    required String bvid,
    required int cid,
    required String dmid,
    required bool liked,
  }) async {
    likes.add((bvid: bvid, cid: cid, dmid: dmid, liked: liked));
    await likeHandler?.call();
  }

  @override
  Future<void> retractDanmaku({
    required String bvid,
    required int cid,
    required String dmid,
  }) async {
    retractions.add((bvid: bvid, cid: cid, dmid: dmid));
    await retractHandler?.call();
  }

  List<int> get segmentIndexes =>
      requests.map((request) => request.segmentIndex).toList(growable: false);

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
  }) async {
    sends.add(
      _SendRequest(
        bvid: bvid,
        cid: cid,
        aid: aid,
        text: text,
        progressMs: progressMs,
        mode: mode,
        fontSize: fontSize,
        color: color,
      ),
    );
    final error = sendError;
    if (error != null) throw error;
    if (pendingSend) throw TimeoutException('send timeout');
    if (sendGate case final gate?) return gate.future;
    return '${_nextDmid++}';
  }

  @override
  Future<List<BiliDanmakuEntry>> loadSegment({
    required String bvid,
    required int cid,
    required int aid,
    required int segmentIndex,
  }) {
    final request = _SegmentRequest(
      bvid: bvid,
      cid: cid,
      aid: aid,
      segmentIndex: segmentIndex,
    );
    requests.add(request);
    if (cachedEntries case final entries?) return Future.value(entries);
    return _loadSegment?.call(request) ??
        Future<List<BiliDanmakuEntry>>.value(const <BiliDanmakuEntry>[]);
  }

  @override
  Future<List<BiliDanmakuEntry>> loadLegacyEntries({
    required String bvid,
    required int cid,
  }) async {
    legacyCalls += 1;
    return legacyEntries;
  }

  @override
  Future<List<BiliDanmakuEntry>> loadSpecialEntries({
    required String bvid,
    required int cid,
    required int aid,
  }) {
    specialCalls += 1;
    return specialLoader?.call() ??
        Future<List<BiliDanmakuEntry>>.value(const <BiliDanmakuEntry>[]);
  }
}

final class _SegmentRequest {
  const _SegmentRequest({
    required this.bvid,
    required this.cid,
    required this.aid,
    required this.segmentIndex,
  });

  final String bvid;
  final int cid;
  final int aid;
  final int segmentIndex;
}

final class _SendRequest {
  const _SendRequest({
    required this.bvid,
    required this.cid,
    required this.aid,
    required this.text,
    required this.progressMs,
    required this.mode,
    required this.fontSize,
    required this.color,
  });

  final String bvid;
  final int cid;
  final int aid;
  final String text;
  final int progressMs;
  final int mode;
  final int fontSize;
  final int color;
}
