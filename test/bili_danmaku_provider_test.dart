import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

typedef _SegmentLoader =
    Future<List<BiliDanmakuEntry>> Function(_SegmentRequest request);

typedef _SpecialLoader = Future<List<BiliDanmakuEntry>> Function();

final class _FakeDanmakuRepository
    implements BiliDanmakuRepository, BiliSpecialDanmakuRepository {
  _FakeDanmakuRepository({
    this._loadSegment,
    this.specialLoader,
    this.legacyEntries = const <BiliDanmakuEntry>[],
  });

  final _SegmentLoader? _loadSegment;
  final _SpecialLoader? specialLoader;
  final List<BiliDanmakuEntry> legacyEntries;
  final List<_SegmentRequest> requests = <_SegmentRequest>[];
  int legacyCalls = 0;
  int specialCalls = 0;

  List<int> get segmentIndexes =>
      requests.map((request) => request.segmentIndex).toList(growable: false);

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
