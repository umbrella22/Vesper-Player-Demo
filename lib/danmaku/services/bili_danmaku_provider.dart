import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';
import 'package:vesper_media/media/media.dart';

import '../../bili/common/services/bili_api_core.dart';
import '../../bili/common/services/bili_client.dart';
import '../models/danmaku_models.dart';
import 'bili_advanced_danmaku_parser.dart';
import 'bili_danmaku_repository.dart';

const int biliDanmakuSegmentDurationMs = 360000;

/// Bilibili's segmented danmaku source. Each playback target receives an
/// isolated session so stale requests from a previous page cannot mutate the
/// current overlay.
final class BiliDanmakuProvider implements MediaDanmakuProvider {
  factory BiliDanmakuProvider({
    BiliClient? client,
    BiliDanmakuRepository? repository,
  }) {
    if (repository != null) {
      return BiliDanmakuProvider._(repository);
    }
    if (client == null) {
      throw ArgumentError('client or repository must be provided');
    }
    return BiliDanmakuProvider._(BiliNetworkDanmakuRepository(client));
  }

  BiliDanmakuProvider._(this._repository);

  final BiliDanmakuRepository _repository;
  final Set<_BiliDanmakuSession> _sessions = <_BiliDanmakuSession>{};
  ValueListenable<BiliDanmakuSourceFilterSettings>? _filterListenable;
  BiliDanmakuSourceFilterSettings _sourceFilter =
      const BiliDanmakuSourceFilterSettings();

  void bindSourceFilter(
    ValueListenable<BiliDanmakuSourceFilterSettings> listenable,
  ) {
    if (identical(_filterListenable, listenable)) {
      return;
    }
    _filterListenable?.removeListener(_handleSourceFilterChanged);
    _filterListenable = listenable;
    _filterListenable?.addListener(_handleSourceFilterChanged);
    _handleSourceFilterChanged();
  }

  void _handleSourceFilterChanged() {
    final next =
        _filterListenable?.value ?? const BiliDanmakuSourceFilterSettings();
    if (_sourceFilter == next) {
      return;
    }
    _sourceFilter = next;
    for (final session in _sessions.toList(growable: false)) {
      session.updateSourceFilter(next);
    }
  }

  @override
  MediaDanmakuSession openSession(MediaPlaybackTarget target) {
    final bvid =
        target.entry.platformExtras['bvid'] as String? ?? target.detail.mediaId;
    final cid = int.tryParse(target.entry.entryId) ?? 0;
    final aid =
        target.entry.platformExtras['aid'] as int? ??
        target.detail.platformExtras['aid'] as int? ??
        0;
    late final _BiliDanmakuSession session;
    session = _BiliDanmakuSession(
      repository: _repository,
      bvid: bvid,
      cid: cid,
      aid: aid,
      durationMs: target.entry.durationSeconds * 1000,
      validTarget: bvid.isNotEmpty && cid > 0,
      sourceFilter: _sourceFilter,
      onClosed: () => _sessions.remove(session),
    );
    _sessions.add(session);
    return session;
  }

  void dispose() {
    _filterListenable?.removeListener(_handleSourceFilterChanged);
    _filterListenable = null;
    for (final session in _sessions.toList(growable: false)) {
      unawaited(session.close());
    }
    _sessions.clear();
  }
}

final class _BiliDanmakuSession
    implements MediaDanmakuSessionSender, MediaDanmakuSessionInteractions {
  _BiliDanmakuSession({
    required this._repository,
    required this._bvid,
    required this._cid,
    required this._aid,
    required int durationMs,
    required this._validTarget,
    required this._sourceFilter,
    required this._onClosed,
  }) : _maximumSegment = _segmentCountForDuration(durationMs);

  final BiliDanmakuRepository _repository;
  final String _bvid;
  final int _cid;
  final int _aid;
  final int _maximumSegment;
  final bool _validTarget;
  final VoidCallback _onClosed;
  final StreamController<MediaDanmakuSnapshot> _snapshotController =
      StreamController<MediaDanmakuSnapshot>.broadcast(sync: true);
  final Map<int, List<BiliDanmakuEntry>> _segments =
      <int, List<BiliDanmakuEntry>>{};
  final Set<int> _loadingSegments = <int>{};

  /// 本地发送成功的弹幕，按 dmid 保存。
  ///
  /// 每次快照重建都会从分段数据重新生成事件，因此发送成功的事件必须留在这
  /// 里参与重建，否则下一次分段刷新就会把它冲掉。键是 dmid，与分段返回的
  /// rowId 同域——服务端回传同一条弹幕时按 id 去重，不会出现两份。
  final Map<String, BiliDanmakuEntry> _locallySentEntries =
      <String, BiliDanmakuEntry>{};
  final _interactionStates = signal<Map<String, MediaDanmakuInteractionState>>(
    {},
  );
  final _interactionRevisions = <String, int>{};
  final _ownedSentRevisions = <String, int>{};
  final _retractedIds = <String>{};

  BiliDanmakuInteractionRepository? get _interactionRepository =>
      switch (_repository) {
        BiliDanmakuInteractionRepository repository => repository,
        _ => null,
      };

  @override
  MediaDanmakuInteractionState interactionStateFor(MediaDanmakuEvent event) {
    if (_closed) return const MediaDanmakuInteractionState();
    final repository = _interactionRepository;
    final saved = _interactionStates.value[event.id];
    final state = _interactionRevisions[event.id] == repository?.sessionRevision
        ? saved
        : null;
    final canLike =
        _validTarget &&
        event.hasServerId &&
        event.id.isNotEmpty &&
        !_retractedIds.contains(event.id) &&
        repository != null;
    return MediaDanmakuInteractionState(
      liked: state?.liked ?? false,
      pending: state?.pending ?? false,
      canLike: canLike,
      canRetract:
          canLike &&
          repository.hasAuthenticatedSession &&
          _ownedSentRevisions[event.id] == repository.sessionRevision,
    );
  }

  @override
  Future<String?> toggleLike(MediaDanmakuEvent event) =>
      _performInteraction(event, retracting: false);

  @override
  Future<String?> retract(MediaDanmakuEvent event) =>
      _performInteraction(event, retracting: true);

  Future<String?> _performInteraction(
    MediaDanmakuEvent event, {
    required bool retracting,
  }) async {
    final repository = _interactionRepository;
    final previous = interactionStateFor(event);
    if (repository == null || !previous.canLike) return '这条弹幕没有可用的互动入口。';
    if (!repository.hasAuthenticatedSession) return '请先登录后再操作。';
    if (retracting && !previous.canRetract) return '只能撤回本次会话中由当前账号发送的弹幕。';
    if (previous.pending) return '操作正在进行中，请稍候。';
    final revision = repository.sessionRevision;
    final liked = retracting ? previous.liked : !previous.liked;
    void update(bool pending, bool value) {
      _interactionRevisions[event.id] = revision;
      _interactionStates.value = {
        ..._interactionStates.peek(),
        event.id: MediaDanmakuInteractionState(liked: value, pending: pending),
      };
    }

    bool current() => !_closed && repository.sessionRevision == revision;
    update(true, liked);
    try {
      if (retracting) {
        await repository.retractDanmaku(bvid: _bvid, cid: _cid, dmid: event.id);
      } else {
        await repository.setDanmakuLike(
          bvid: _bvid,
          cid: _cid,
          dmid: event.id,
          liked: liked,
        );
      }
      if (!current()) return '播放会话或登录账号已变化。';
      if (retracting) {
        _retractedIds.add(event.id);
        _locallySentEntries.remove(event.id);
        _ownedSentRevisions.remove(event.id);
        _emitSnapshot();
      }
      update(false, liked);
      return null;
    } catch (error) {
      if (!current()) return '播放会话或登录账号已变化。';
      update(false, previous.liked);
      if (error is BiliApiException && error.outcomeUnknown) {
        return '操作结果未确认，请稍后重新查看，避免重复操作。';
      }
      return biliErrorMessage(error);
    }
  }

  Set<int> _desiredSegments = const <int>{};
  int? _currentSegment;
  List<BiliDanmakuEntry>? _legacyEntries;
  Future<void>? _legacyRequest;
  List<BiliDanmakuEntry> _specialEntries = const <BiliDanmakuEntry>[];
  bool _specialRequestStarted = false;
  bool _legacyLoading = false;
  Object? _error;
  bool _closed = false;
  BiliDanmakuSourceFilterSettings _sourceFilter;

  @override
  Stream<MediaDanmakuSnapshot> get snapshots => _snapshotController.stream;

  @override
  void updatePosition(int positionMs) {
    if (_closed) {
      return;
    }
    if (!_validTarget) {
      _emitSnapshot();
      return;
    }
    if (!_specialRequestStarted) {
      _specialRequestStarted = true;
      unawaited(_loadSpecialEntries());
    }
    if (_legacyEntries != null || _legacyRequest != null) {
      return;
    }

    final segment = _segmentForPosition(positionMs);
    if (_currentSegment == segment) {
      return;
    }
    _currentSegment = segment;
    _error = null;
    _desiredSegments = _segmentsAround(segment);
    _segments.removeWhere((index, _) => !_desiredSegments.contains(index));
    _emitSnapshot();

    unawaited(_loadSegment(segment, requiredForDisplay: true));
    for (final adjacent in _desiredSegments) {
      if (adjacent != segment) {
        unawaited(_loadSegment(adjacent, requiredForDisplay: false));
      }
    }
  }

  Future<void> _loadSpecialEntries() async {
    final repository = _repository is BiliSpecialDanmakuRepository
        ? _repository as BiliSpecialDanmakuRepository
        : null;
    if (repository == null) {
      return;
    }
    try {
      final entries = await repository.loadSpecialEntries(
        bvid: _bvid,
        cid: _cid,
        aid: _aid,
      );
      if (!_closed) {
        _specialEntries = entries;
        _emitSnapshot();
      }
    } catch (error) {
      debugPrint(
        '[BiliDanmaku] special package load failed: ${error.runtimeType}',
      );
      // Special packages are additive. Their failure must not hide ordinary
      // segmented danmaku or trigger the legacy full-list fallback.
    }
  }

  Future<void> _loadSegment(
    int segmentIndex, {
    required bool requiredForDisplay,
  }) async {
    if (_closed ||
        _legacyRequest != null ||
        _legacyEntries != null ||
        _segments.containsKey(segmentIndex) ||
        !_loadingSegments.add(segmentIndex)) {
      return;
    }
    _emitSnapshot();
    try {
      final entries = await _repository.loadSegment(
        bvid: _bvid,
        cid: _cid,
        aid: _aid,
        segmentIndex: segmentIndex,
      );
      if (!_closed && _desiredSegments.contains(segmentIndex)) {
        _segments[segmentIndex] = entries;
      }
    } catch (error) {
      if (!_closed && requiredForDisplay && _currentSegment == segmentIndex) {
        await _loadLegacyFallback(error);
      }
    } finally {
      _loadingSegments.remove(segmentIndex);
      if (!_closed) {
        _emitSnapshot();
      }
    }
  }

  Future<void> _loadLegacyFallback(Object segmentError) {
    final existing = _legacyRequest;
    if (existing != null) {
      return existing;
    }
    _legacyLoading = true;
    final request = () async {
      try {
        final entries = await _repository.loadLegacyEntries(
          bvid: _bvid,
          cid: _cid,
        );
        if (!_closed) {
          _legacyEntries = entries;
          _segments.clear();
          _error = null;
        }
      } catch (legacyError) {
        if (!_closed) {
          _error = legacyError;
        }
      } finally {
        _legacyLoading = false;
      }
    }();
    _legacyRequest = request;
    _error = segmentError;
    _emitSnapshot();
    return request;
  }

  void _emitSnapshot() {
    if (_closed) {
      return;
    }
    final sourceEntries =
        _legacyEntries ??
        <BiliDanmakuEntry>[
          for (final segment in _desiredSegments.toList()..sort())
            ...?_segments[segment],
        ];
    final allEntries = <BiliDanmakuEntry>[
      ...sourceEntries,
      ..._specialEntries,
      // 本地已发送的弹幕参与每次重建；按 rowId 与分段数据去重。
      ..._locallySentEntries.values,
    ];
    final seenIds = <String>{};
    final events = <MediaDanmakuEvent>[];
    final advancedEvents = <MediaAdvancedDanmakuEvent>[];
    const advancedParser = BiliAdvancedDanmakuParser();
    for (final entry in allEntries) {
      if (!_sourceFilter.allows(entry)) {
        continue;
      }
      final id = entry.rowId.isNotEmpty
          ? entry.rowId
          : '${entry.appearAtMs}:${entry.mode.name}:${entry.text}';
      if (_retractedIds.contains(id) || !seenIds.add(id)) {
        continue;
      }
      if (entry.mode == BiliDanmakuMode.advanced) {
        final advanced = advancedParser.tryParse(entry);
        if (advanced != null) {
          advancedEvents.add(advanced);
        }
        continue;
      }
      // mode 8 is third-party code and mode 9 requires a BAS runtime. Both
      // remain explicitly non-executable; pool-2 packages are fetched only so
      // their entries can be classified here.
      if (!entry.mode.isStandard || entry.pool == 2) {
        continue;
      }
      final channel = entry.pool == 1
          ? MediaDanmakuChannel.caption
          : MediaDanmakuChannel.standard;
      events.add(
        MediaDanmakuEvent(
          id: id,
          timeMs: entry.appearAtMs,
          text: entry.text,
          channel: channel,
          // 合成键只用于本地去重，交互入口据此禁用服务端动作。
          hasServerId: entry.hasServerId && entry.rowId.isNotEmpty,
          senderHash: entry.senderHash,
          style: MediaDanmakuStyle(
            color: entry.colorValue,
            position: channel == MediaDanmakuChannel.caption
                ? MediaDanmakuPosition.bottom
                : _positionForMode(entry.mode),
            fontSizeScale: entry.fontSize > 0 ? entry.fontSize / 25 : 1,
          ),
        ),
      );
    }
    events.sort((left, right) {
      final byTime = left.timeMs.compareTo(right.timeMs);
      return byTime != 0 ? byTime : left.id.compareTo(right.id);
    });
    advancedEvents.sort((left, right) {
      final byTime = left.timeMs.compareTo(right.timeMs);
      return byTime != 0 ? byTime : left.id.compareTo(right.id);
    });
    _snapshotController.add(
      MediaDanmakuSnapshot(
        events: List<MediaDanmakuEvent>.unmodifiable(events),
        advancedEvents: List<MediaAdvancedDanmakuEvent>.unmodifiable(
          advancedEvents,
        ),
        isLoading:
            _legacyLoading ||
            (_currentSegment != null &&
                !_segments.containsKey(_currentSegment) &&
                _legacyEntries == null),
        error: _error,
      ),
    );
  }

  void updateSourceFilter(BiliDanmakuSourceFilterSettings sourceFilter) {
    if (_closed || _sourceFilter == sourceFilter) {
      return;
    }
    _sourceFilter = sourceFilter;
    _emitSnapshot();
  }

  Set<int> _segmentsAround(int current) {
    final values = <int>{current};
    if (current > 1) {
      values.add(current - 1);
    }
    if (_maximumSegment == 0 || current < _maximumSegment) {
      values.add(current + 1);
    }
    return Set<int>.unmodifiable(values);
  }

  int _segmentForPosition(int positionMs) {
    final normalizedPosition = positionMs < 0 ? 0 : positionMs;
    final calculated = normalizedPosition ~/ biliDanmakuSegmentDurationMs + 1;
    if (_maximumSegment > 0 && calculated > _maximumSegment) {
      return _maximumSegment;
    }
    return calculated;
  }

  /// 发送一条普通弹幕。
  ///
  /// 只有服务端接受后（拿到 dmid）才把事件插入本地快照：失败与超时都不修改
  /// 快照，界面按返回结果保留草稿或提示失败。不自动重发。
  @override
  Future<MediaDanmakuSendResult> send(MediaDanmakuSendRequest request) async {
    if (_closed) {
      return const MediaDanmakuSendResult.failure('弹幕会话已结束。');
    }
    if (!_validTarget) {
      return const MediaDanmakuSendResult.failure('当前视频缺少弹幕参数。');
    }
    final repository = _repository is BiliDanmakuSendRepository
        ? _repository as BiliDanmakuSendRepository
        : null;
    if (repository == null) {
      return const MediaDanmakuSendResult.failure('当前平台不支持发送弹幕。');
    }
    final text = request.text.trim();
    if (text.isEmpty) {
      return const MediaDanmakuSendResult.failure('弹幕内容不能为空。');
    }
    final progressMs = request.positionMs < 0 ? 0 : request.positionMs;
    final mode = _modeForPosition(request.style.position);
    final color = (request.style.color ?? 16777215).clamp(0, 0xFFFFFF).toInt();
    final fontSize = (25 * request.style.fontSizeScale).round().clamp(18, 36);
    final String dmid;
    final revision = _interactionRepository?.sessionRevision;
    try {
      dmid = await repository.postDanmaku(
        bvid: _bvid,
        cid: _cid,
        aid: _aid,
        text: text,
        progressMs: progressMs,
        mode: mode,
        fontSize: fontSize,
        color: color,
      );
    } on BiliApiException catch (error) {
      if (error.outcomeUnknown) {
        return const MediaDanmakuSendResult.pending();
      }
      return MediaDanmakuSendResult.failure(biliErrorMessage(error));
    } catch (error) {
      // 超时等结果未知的情况保留草稿，由对账决定，不自动重发。
      return const MediaDanmakuSendResult.pending();
    }
    if (_closed) {
      return const MediaDanmakuSendResult.failure('弹幕会话已结束。');
    }
    if (revision != _interactionRepository?.sessionRevision) {
      return const MediaDanmakuSendResult.pending();
    }
    final entry = BiliDanmakuEntry(
      appearAtMs: progressMs,
      mode: BiliDanmakuMode.fromCode(mode),
      fontSize: fontSize.toDouble(),
      colorValue: color,
      text: text,
      rowId: dmid,
      weight: null,
      pool: 0,
    );
    _locallySentEntries[dmid] = entry;
    if (revision != null) _ownedSentRevisions[dmid] = revision;
    _emitSnapshot();
    return MediaDanmakuSendResult.success(
      MediaDanmakuEvent(
        id: dmid,
        timeMs: progressMs,
        text: text,
        hasServerId: true,
        style: MediaDanmakuStyle(
          color: color,
          position: request.style.position,
          fontSizeScale: fontSize / 25,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _interactionStates.dispose();
    _onClosed();
    await _snapshotController.close();
  }
}

/// 归一化位置 → B 站弹幕 mode。只映射普通弹幕池的四种模式。
int _modeForPosition(MediaDanmakuPosition position) {
  return switch (position) {
    MediaDanmakuPosition.roll => 1,
    MediaDanmakuPosition.bottom => 4,
    MediaDanmakuPosition.top => 5,
    MediaDanmakuPosition.reverse => 6,
  };
}

int _segmentCountForDuration(int durationMs) {
  if (durationMs <= 0) {
    return 0;
  }
  return (durationMs + biliDanmakuSegmentDurationMs - 1) ~/
      biliDanmakuSegmentDurationMs;
}

MediaDanmakuPosition _positionForMode(BiliDanmakuMode mode) {
  return switch (mode) {
    BiliDanmakuMode.scroll => MediaDanmakuPosition.roll,
    BiliDanmakuMode.reverse => MediaDanmakuPosition.reverse,
    BiliDanmakuMode.top => MediaDanmakuPosition.top,
    BiliDanmakuMode.bottom => MediaDanmakuPosition.bottom,
    BiliDanmakuMode.advanced ||
    BiliDanmakuMode.code ||
    BiliDanmakuMode.bas ||
    BiliDanmakuMode.unsupported => MediaDanmakuPosition.roll,
  };
}
