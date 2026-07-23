import 'package:vesper_player/vesper_player.dart';

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
    };
  }
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
