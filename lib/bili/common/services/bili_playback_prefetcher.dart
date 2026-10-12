import 'dart:async';
import 'dart:collection';

import '../models/bili_models.dart';
import 'bili_api_core.dart';

typedef BiliPlaybackPrefetchKey = ({String bvid, int? cid});

/// Raw playurl response, or detail-only fallback for feed items without a cid.
final class BiliPrefetchedPlayback {
  const BiliPrefetchedPlayback({this.detail, this.dashData, this.variant});
  final BiliVideoDetail? detail;
  final Map<String, Object?>? dashData;
  final BiliDashRequestVariant? variant;
}

/// Feed-only speculative work. Product budgets: 12 entries, 120s TTL, 2 workers.
final class BiliPlaybackPrefetcher {
  BiliPlaybackPrefetcher({
    this.capacity = 12,
    this.ttl = const Duration(seconds: 120),
    this.concurrency = 2,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final int capacity;
  final Duration ttl;
  final int concurrency;
  final DateTime Function() _now;
  final _cache =
      <
        BiliPlaybackPrefetchKey,
        ({DateTime expires, BiliPrefetchedPlayback value})
      >{};
  final _jobs = <BiliPlaybackPrefetchKey, _PrefetchJob>{};
  final _queue = Queue<_PrefetchJob>();
  int _running = 0;

  Future<void> prefetch(
    BiliPlaybackPrefetchKey key,
    Future<BiliPrefetchedPlayback?> Function(bool Function() isCurrent) loader,
  ) {
    final cached = _cache.remove(key);
    if (cached != null && _now().isBefore(cached.expires)) {
      _cache[key] = cached;
      return Future.value();
    }
    final existing = _jobs[key];
    if (existing != null) return existing.done.future;
    // Bound queued work as well as completed responses when scrolling quickly.
    while (_queue.length >= capacity) {
      _cancel(_queue.removeFirst());
    }
    final job = _PrefetchJob(key, loader);
    _jobs[key] = job;
    _queue.add(job);
    _drain();
    return job.done.future;
  }

  BiliPrefetchedPlayback? take(BiliPlaybackPrefetchKey key) {
    final job = _jobs[key];
    if (job != null) _cancel(job);
    final cached = _cache.remove(key);
    return cached != null && _now().isBefore(cached.expires)
        ? cached.value
        : null;
  }

  void stopPrefetching(String bvid) {
    for (final job in _jobs.values.toList()) {
      if (job.key.bvid == bvid) _cancel(job);
    }
  }

  void clear() {
    _cache.clear();
    for (final job in _jobs.values.toList()) {
      _cancel(job);
    }
  }

  void _cancel(_PrefetchJob job) {
    job.cancelled = true;
    _queue.remove(job);
    if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
    if (!job.done.isCompleted) job.done.complete();
  }

  void _drain() {
    while (_running < concurrency && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _running++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_PrefetchJob job) async {
    try {
      final value = await job.loader(() => !job.cancelled);
      if (!job.cancelled && value != null) {
        _cache.remove(job.key);
        _cache[job.key] = (expires: _now().add(ttl), value: value);
        while (_cache.length > capacity) {
          _cache.remove(_cache.keys.first);
        }
      }
    } catch (_) {
      // Foreground playback always retains its normal request/retry path.
    } finally {
      if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
      if (!job.done.isCompleted) job.done.complete();
      _running--;
      _drain();
    }
  }
}

final class _PrefetchJob {
  _PrefetchJob(this.key, this.loader);
  final BiliPlaybackPrefetchKey key;
  final Future<BiliPrefetchedPlayback?> Function(bool Function()) loader;
  final done = Completer<void>();
  bool cancelled = false;
}
