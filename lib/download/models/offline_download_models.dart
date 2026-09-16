import 'package:vesper_player/vesper_player.dart';

import '../../bili/common/models/bili_models.dart';

final class BiliOfflineDownloadMetadata {
  const BiliOfflineDownloadMetadata({
    required this.assetId,
    required this.bvid,
    required this.cid,
    required this.videoTitle,
    required this.pageTitle,
    required this.coverUrl,
    required this.qualityLabel,
    required this.createdAtMs,
    this.taskId,
    this.outputPath,
    this.errorMessage,
    this.playbackMetadata,
  });

  factory BiliOfflineDownloadMetadata.fromJson(Map<String, Object?> json) {
    return BiliOfflineDownloadMetadata(
      assetId: json['assetId'] as String? ?? '',
      taskId: json['taskId'] as int?,
      bvid: json['bvid'] as String? ?? '',
      cid: json['cid'] as int? ?? 0,
      videoTitle: json['videoTitle'] as String? ?? '',
      pageTitle: json['pageTitle'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      qualityLabel: json['qualityLabel'] as String? ?? '',
      outputPath: json['outputPath'] as String?,
      createdAtMs: json['createdAtMs'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
      playbackMetadata: switch (json['playbackMetadata']) {
        final Map<Object?, Object?> value =>
          BiliOfflinePlaybackMetadata.fromJson(
            Map<String, Object?>.from(value),
          ),
        _ => null,
      },
    );
  }

  final String assetId;
  final int? taskId;
  final String bvid;
  final int cid;
  final String videoTitle;
  final String pageTitle;
  final String coverUrl;
  final String qualityLabel;
  final String? outputPath;
  final int createdAtMs;
  final String? errorMessage;
  final BiliOfflinePlaybackMetadata? playbackMetadata;

  /// Old cache records already contain the content identity and display titles.
  /// Unknown duration/owner fields remain unknown instead of requiring a fetch.
  BiliVideoDetail toVideoDetail() {
    final playback = playbackMetadata;
    final legacyTitle = RegExp(r'^P(\d+) · (.*)$').firstMatch(pageTitle);
    final page = BiliVideoPageEntry(
      cid: cid,
      bvid: bvid,
      aid: playback?.aid,
      pageNumber:
          playback?.pageNumber ??
          int.tryParse(legacyTitle?.group(1) ?? '') ??
          1,
      title: playback?.pageTitle ?? legacyTitle?.group(2) ?? pageTitle,
      durationSeconds: playback?.durationSeconds ?? 0,
      coverUrl: coverUrl,
      episodeId: playback?.episodeId,
    );
    return BiliVideoDetail(
      aid: playback?.aid ?? 0,
      bvid: bvid,
      title: videoTitle,
      ownerMid: playback?.ownerMid ?? 0,
      ownerName: playback?.ownerName ?? '',
      ownerAvatarUrl: playback?.ownerAvatarUrl ?? '',
      coverUrl: coverUrl,
      description: playback?.description ?? '',
      publishedAtLabel: null,
      playCountLabel: '—',
      danmakuCountLabel: '—',
      replyCountLabel: '—',
      likeCountLabel: '—',
      coinCountLabel: '—',
      favoriteCountLabel: '—',
      shareCountLabel: '—',
      pages: <BiliVideoPageEntry>[page],
    );
  }

  BiliOfflineDownloadMetadata copyWith({
    int? taskId,
    String? outputPath,
    bool clearOutputPath = false,
    int? createdAtMs,
    String? errorMessage,
    bool clearError = false,
  }) {
    return BiliOfflineDownloadMetadata(
      assetId: assetId,
      taskId: taskId ?? this.taskId,
      bvid: bvid,
      cid: cid,
      videoTitle: videoTitle,
      pageTitle: pageTitle,
      coverUrl: coverUrl,
      qualityLabel: qualityLabel,
      outputPath: clearOutputPath ? null : outputPath ?? this.outputPath,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      playbackMetadata: playbackMetadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'assetId': assetId,
      'taskId': taskId,
      'bvid': bvid,
      'cid': cid,
      'videoTitle': videoTitle,
      'pageTitle': pageTitle,
      'coverUrl': coverUrl,
      'qualityLabel': qualityLabel,
      'outputPath': outputPath,
      'createdAtMs': createdAtMs,
      'errorMessage': errorMessage,
      if (playbackMetadata case final playback?)
        'playbackMetadata': playback.toJson(),
    };
  }
}

/// Playback fields captured with the downloaded page, separate from mutable
/// download progress. The containing record owns the canonical bvid/cid pair.
final class BiliOfflinePlaybackMetadata {
  const BiliOfflinePlaybackMetadata({
    required this.aid,
    required this.pageNumber,
    required this.pageTitle,
    required this.durationSeconds,
    required this.ownerMid,
    required this.ownerName,
    required this.ownerAvatarUrl,
    required this.description,
    this.episodeId,
  });

  factory BiliOfflinePlaybackMetadata.fromVideo({
    required BiliVideoDetail detail,
    required BiliVideoPageEntry page,
  }) => BiliOfflinePlaybackMetadata(
    aid: page.aid ?? detail.aid,
    pageNumber: page.pageNumber,
    pageTitle: page.title,
    durationSeconds: page.durationSeconds,
    ownerMid: detail.ownerMid,
    ownerName: detail.ownerName,
    ownerAvatarUrl: detail.ownerAvatarUrl,
    description: detail.description,
    episodeId: page.episodeId,
  );

  factory BiliOfflinePlaybackMetadata.fromJson(Map<String, Object?> json) =>
      BiliOfflinePlaybackMetadata(
        aid: json['aid'] as int? ?? 0,
        pageNumber: json['pageNumber'] as int? ?? 1,
        pageTitle: json['pageTitle'] as String? ?? '',
        durationSeconds: json['durationSeconds'] as int? ?? 0,
        ownerMid: json['ownerMid'] as int? ?? 0,
        ownerName: json['ownerName'] as String? ?? '',
        ownerAvatarUrl: json['ownerAvatarUrl'] as String? ?? '',
        description: json['description'] as String? ?? '',
        episodeId: json['episodeId'] as int?,
      );

  final int aid;
  final int pageNumber;
  final String pageTitle;
  final int durationSeconds;
  final int ownerMid;
  final String ownerName;
  final String ownerAvatarUrl;
  final String description;
  final int? episodeId;

  Map<String, Object?> toJson() => <String, Object?>{
    'aid': aid,
    'pageNumber': pageNumber,
    'pageTitle': pageTitle,
    'durationSeconds': durationSeconds,
    'ownerMid': ownerMid,
    'ownerName': ownerName,
    'ownerAvatarUrl': ownerAvatarUrl,
    'description': description,
    'episodeId': episodeId,
  };
}

final class BiliOfflineDownloadEntry {
  const BiliOfflineDownloadEntry({
    required this.metadata,
    this.task,
    this.metadataMissing = false,
    this.integrityError,
  });

  final BiliOfflineDownloadMetadata metadata;
  final VesperDownloadTaskSnapshot? task;

  /// True when the SDK task or cache directory has no matching Bili metadata.
  ///
  /// Such an entry is intentionally kept visible so that users can remove the
  /// bytes it owns. It must never be sent to the playback resolver because
  /// there is no reliable bvid/cid pair to resolve.
  final bool metadataMissing;

  /// A detected mismatch between persisted metadata, the restored SDK task,
  /// or the completed cache file on disk.
  final String? integrityError;

  VesperDownloadState? get state => task?.state;

  int get receivedBytes => task?.progress.receivedBytes ?? 0;

  int? get totalBytes => task?.progress.totalBytes;

  double? get progressRatio => task?.progress.completionRatio;

  String? get errorMessage => task?.error?.message ?? metadata.errorMessage;
  String? get displayErrorMessage {
    if (isUnplayable) {
      return unplayableReason;
    }
    return _friendlyOfflineDownloadError(
      task?.error?.message ?? metadata.errorMessage,
    );
  }

  bool get isUnplayable {
    return metadataMissing ||
        integrityError != null ||
        metadata.bvid.trim().isEmpty ||
        metadata.cid <= 0;
  }

  String get unplayableReason {
    final integrityError = this.integrityError;
    if (integrityError != null) {
      return integrityError;
    }
    if (metadataMissing) {
      return '缓存视频信息已丢失，无法播放。请清理这条失效缓存。';
    }
    if (metadata.bvid.trim().isEmpty || metadata.cid <= 0) {
      return '缓存视频元数据不完整，无法播放。请清理这条失效缓存。';
    }
    return '缓存视频无法播放。';
  }

  bool get isActive {
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return false;
    }
    return switch (state) {
      VesperDownloadState.queued ||
      VesperDownloadState.preparing ||
      VesperDownloadState.downloading ||
      VesperDownloadState.paused => true,
      _ => false,
    };
  }

  bool get isCompleted =>
      state == VesperDownloadState.completed ||
      (metadata.outputPath != null && metadata.outputPath!.isNotEmpty);

  String get statusLabel {
    if (isUnplayable) {
      return '无法播放';
    }
    final error = errorMessage;
    if (error != null && error.isNotEmpty) {
      return '失败';
    }
    return switch (state) {
      VesperDownloadState.queued => '等待中',
      VesperDownloadState.preparing => '准备中',
      VesperDownloadState.downloading => '缓存中',
      VesperDownloadState.paused => '已暂停',
      VesperDownloadState.completed => '已完成',
      VesperDownloadState.failed => '失败',
      VesperDownloadState.removed => '已移除',
      VesperDownloadState.unknown => '未知状态',
      null => isCompleted ? '已完成' : '等待恢复',
    };
  }
}

String? _friendlyOfflineDownloadError(String? message) {
  if (message == null || message.isEmpty) {
    return message;
  }
  final lower = message.toLowerCase();
  if (lower.contains('stale or expired') ||
      lower.contains('http 401') ||
      lower.contains('http 403') ||
      lower.contains('http 404') ||
      lower.contains('http 410')) {
    return '缓存资源链接已过期或被拒绝，请重新打开页面后再试。';
  }
  return message;
}

String biliFormatDownloadBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 100 ? 0 : 1)} GB';
}
