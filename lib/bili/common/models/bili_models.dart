import 'package:vesper_player/vesper_player.dart';

final class BiliSearchResult {
  const BiliSearchResult({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.durationLabel,
    required this.playCountLabel,
    required this.danmakuCountLabel,
    this.description,
    this.publishedAtLabel,
  });

  final int aid;
  final String bvid;
  final String title;
  final String author;
  final String coverUrl;
  final String durationLabel;
  final String playCountLabel;
  final String danmakuCountLabel;
  final String? description;
  final String? publishedAtLabel;
}

final class BiliFeedVideo {
  const BiliFeedVideo({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.durationLabel,
    required this.playCountLabel,
    required this.danmakuCountLabel,
    this.description,
    this.publishedAtLabel,
  });

  final int aid;
  final String bvid;
  final String title;
  final String author;
  final String coverUrl;
  final String durationLabel;
  final String playCountLabel;
  final String danmakuCountLabel;
  final String? description;
  final String? publishedAtLabel;
}

final class BiliVideoPageEntry {
  const BiliVideoPageEntry({
    required this.cid,
    required this.pageNumber,
    required this.title,
    required this.durationSeconds,
    this.aid,
    this.bvid,
    this.coverUrl,
    this.episodeId,
  });

  final int cid;
  final int pageNumber;
  final String title;
  final int durationSeconds;
  final int? aid;
  final String? bvid;
  final String? coverUrl;
  final int? episodeId;
}

final class BiliVideoDetail {
  const BiliVideoDetail({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.ownerMid,
    required this.ownerName,
    required this.ownerAvatarUrl,
    required this.coverUrl,
    required this.description,
    required this.publishedAtLabel,
    required this.playCountLabel,
    required this.danmakuCountLabel,
    required this.replyCountLabel,
    required this.likeCountLabel,
    required this.coinCountLabel,
    required this.favoriteCountLabel,
    required this.shareCountLabel,
    required this.pages,
  });

  final int aid;
  final String bvid;
  final String title;
  final int ownerMid;
  final String ownerName;
  final String ownerAvatarUrl;
  final String coverUrl;
  final String description;
  final String? publishedAtLabel;
  final String playCountLabel;
  final String danmakuCountLabel;
  final String replyCountLabel;
  final String likeCountLabel;
  final String coinCountLabel;
  final String favoriteCountLabel;
  final String shareCountLabel;
  final List<BiliVideoPageEntry> pages;
}

final class BiliFavoriteFolder {
  const BiliFavoriteFolder({
    required this.id,
    required this.title,
    required this.containsCurrentVideo,
  });

  final int id;
  final String title;
  final bool containsCurrentVideo;
}

/// A user returned by the authenticated following-list endpoint.
final class BiliFollowingUser {
  const BiliFollowingUser({
    required this.mid,
    required this.name,
    required this.avatarUrl,
    this.sign = '',
    this.officialLabel,
    this.vipLabel,
    this.isSpecial = false,
  });

  final int mid;
  final String name;
  final String avatarUrl;
  final String sign;
  final String? officialLabel;
  final String? vipLabel;
  final bool isSpecial;
}

/// A video item returned by Bilibili's server-side playback history API.
final class BiliRemoteHistoryEntry {
  const BiliRemoteHistoryEntry({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.title,
    required this.pageTitle,
    required this.coverUrl,
    required this.ownerName,
    required this.durationMs,
    required this.progressMs,
    required this.viewedAtMs,
    this.episodeId = 0,
    this.business,
  });

  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final String pageTitle;
  final String coverUrl;
  final String ownerName;
  final int durationMs;
  final int progressMs;
  final int viewedAtMs;
  final int episodeId;
  final String? business;

  bool get isFinished => durationMs > 0 && progressMs >= durationMs - 3000;
}

final class BiliRemoteHistoryPage {
  const BiliRemoteHistoryPage({
    required this.entries,
    required this.hasMore,
    this.nextMax = 0,
    this.nextViewAtMs = 0,
  });

  final List<BiliRemoteHistoryEntry> entries;
  final bool hasMore;
  final int nextMax;
  final int nextViewAtMs;
}

/// A video item in the user's Bilibili "watch later" queue.
final class BiliWatchLaterEntry {
  const BiliWatchLaterEntry({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.title,
    required this.pageTitle,
    required this.coverUrl,
    required this.ownerName,
    required this.durationMs,
    required this.progressMs,
    this.episodeId = 0,
    this.addedAtMs,
    this.business,
  });

  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final String pageTitle;
  final String coverUrl;
  final String ownerName;
  final int durationMs;
  final int progressMs;
  final int episodeId;
  final int? addedAtMs;
  final String? business;
}

/// A subtitle rendition advertised by `/x/player/v2`.
///
/// `url` is a local WebVTT file after [BiliClient.fetchVideoSubtitles]
/// materializes the Bilibili JSON subtitle payload.
final class BiliSubtitleTrack {
  const BiliSubtitleTrack({
    required this.id,
    required this.language,
    required this.languageLabel,
    required this.url,
    this.isDefault = false,
    this.format = 'webvtt',
  });

  final String id;
  final String language;
  final String languageLabel;
  final String url;
  final bool isDefault;
  final String format;
}

final class BiliCommentPicture {
  const BiliCommentPicture({required this.url, this.width, this.height});

  final String url;
  final int? width;
  final int? height;
}

final class BiliCommentTimeLink {
  const BiliCommentTimeLink({
    required this.label,
    required this.seconds,
    this.start,
    this.end,
  });

  final String label;
  final int seconds;
  final int? start;
  final int? end;
}

final class BiliVideoComment {
  const BiliVideoComment({
    required this.id,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.createdAtLabel,
    required this.message,
    required this.likeCountLabel,
    required this.pictures,
    required this.replies,
    required this.timeLinks,
    this.authorLevelLabel,
    this.replyCount = 0,
    this.liked = false,
  });

  final int id;
  final String authorName;
  final String authorAvatarUrl;
  final String? authorLevelLabel;
  final String createdAtLabel;
  final String message;
  final String likeCountLabel;
  final int replyCount;
  final bool liked;
  final List<BiliCommentPicture> pictures;
  final List<BiliVideoComment> replies;
  final List<BiliCommentTimeLink> timeLinks;
}

final class BiliVideoCommentPage {
  const BiliVideoCommentPage({
    required this.comments,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.totalCount,
  });

  final List<BiliVideoComment> comments;
  final int page;
  final int pageSize;
  final int? totalCount;
  final bool hasMore;
}

final class BiliVideoCommentReplyPage {
  const BiliVideoCommentReplyPage({
    required this.replies,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.totalCount,
  });

  final List<BiliVideoComment> replies;
  final int page;
  final int pageSize;
  final int? totalCount;
  final bool hasMore;
}

final class BiliVideoEngagement {
  const BiliVideoEngagement({
    required this.isAuthenticated,
    required this.isLiked,
    required this.isFavorited,
    required this.isFollowingOwner,
    required this.favoriteMediaIds,
    this.defaultFavoriteMediaId,
  });

  const BiliVideoEngagement.guest()
    : isAuthenticated = false,
      isLiked = false,
      isFavorited = false,
      isFollowingOwner = false,
      favoriteMediaIds = const <int>[],
      defaultFavoriteMediaId = null;

  final bool isAuthenticated;
  final bool isLiked;
  final bool isFavorited;
  final bool isFollowingOwner;
  final List<int> favoriteMediaIds;
  final int? defaultFavoriteMediaId;

  BiliVideoEngagement copyWith({
    bool? isAuthenticated,
    bool? isLiked,
    bool? isFavorited,
    bool? isFollowingOwner,
    List<int>? favoriteMediaIds,
    int? defaultFavoriteMediaId,
  }) {
    return BiliVideoEngagement(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLiked: isLiked ?? this.isLiked,
      isFavorited: isFavorited ?? this.isFavorited,
      isFollowingOwner: isFollowingOwner ?? this.isFollowingOwner,
      favoriteMediaIds: favoriteMediaIds ?? this.favoriteMediaIds,
      defaultFavoriteMediaId:
          defaultFavoriteMediaId ?? this.defaultFavoriteMediaId,
    );
  }
}

final class BiliUserProfile {
  const BiliUserProfile({
    required this.isLoggedIn,
    required this.name,
    required this.avatarUrl,
    this.mid,
    this.level,
    this.vipLabel,
    this.bCoinBalance,
    this.coinBalance,
    this.dynamicCount,
    this.followingCount,
    this.followerCount,
  });

  final bool isLoggedIn;
  final String name;
  final String avatarUrl;
  final int? mid;
  final int? level;
  final String? vipLabel;
  final double? bCoinBalance;
  final double? coinBalance;
  final int? dynamicCount;
  final int? followingCount;
  final int? followerCount;
}

final class BiliQrLoginTicket {
  const BiliQrLoginTicket({required this.url, required this.qrcodeKey});

  final String url;
  final String qrcodeKey;
}

enum BiliQrLoginStatus {
  waitingForScan,
  scannedAwaitingConfirm,
  confirmed,
  expired,
  failed;

  static BiliQrLoginStatus fromCode(int code) {
    return switch (code) {
      0 => BiliQrLoginStatus.confirmed,
      86038 => BiliQrLoginStatus.expired,
      86090 => BiliQrLoginStatus.scannedAwaitingConfirm,
      86101 => BiliQrLoginStatus.waitingForScan,
      _ => BiliQrLoginStatus.failed,
    };
  }

  bool get isTerminal =>
      this == BiliQrLoginStatus.confirmed ||
      this == BiliQrLoginStatus.expired ||
      this == BiliQrLoginStatus.failed;
}

final class BiliQrLoginPollResult {
  const BiliQrLoginPollResult({
    required this.status,
    required this.message,
    this.timestampMs,
    this.refreshToken,
  });

  final BiliQrLoginStatus status;
  final String message;
  final int? timestampMs;
  final String? refreshToken;
}

final class BiliPlaybackHistoryEntry {
  const BiliPlaybackHistoryEntry({
    required this.bvid,
    required this.cid,
    required this.videoTitle,
    required this.pageTitle,
    required this.coverUrl,
    required this.ownerName,
    required this.playedAtMs,
    required this.lastPositionMs,
    this.aid = 0,
    this.episodeId = 0,
    this.business,
    this.durationMs,
  });

  factory BiliPlaybackHistoryEntry.fromJson(Map<String, Object?> json) {
    return BiliPlaybackHistoryEntry(
      bvid: json['bvid'] as String? ?? '',
      aid: json['aid'] as int? ?? 0,
      episodeId: json['episodeId'] as int? ?? 0,
      business: json['business'] as String?,
      cid: json['cid'] as int? ?? 0,
      videoTitle: json['videoTitle'] as String? ?? '',
      pageTitle: json['pageTitle'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      playedAtMs: json['playedAtMs'] as int? ?? 0,
      lastPositionMs: json['lastPositionMs'] as int? ?? 0,
      durationMs: json['durationMs'] as int?,
    );
  }

  final String bvid;
  final int aid;
  final int episodeId;
  final String? business;
  final int cid;
  final String videoTitle;
  final String pageTitle;
  final String coverUrl;
  final String ownerName;
  final int playedAtMs;
  final int lastPositionMs;
  final int? durationMs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'bvid': bvid,
      'aid': aid,
      'episodeId': episodeId,
      'business': business,
      'cid': cid,
      'videoTitle': videoTitle,
      'pageTitle': pageTitle,
      'coverUrl': coverUrl,
      'ownerName': ownerName,
      'playedAtMs': playedAtMs,
      'lastPositionMs': lastPositionMs,
      'durationMs': durationMs,
    };
  }
}

final class BiliResolvedPlayback {
  const BiliResolvedPlayback({
    required this.bvid,
    required this.cid,
    required this.title,
    required this.subtitle,
    required this.uri,
    required this.protocol,
    required this.transportLabel,
    required this.isLocalFile,
    this.headers = const <String, String>{},
    this.videoTracks = const <VesperMediaTrack>[],
    this.subtitleTracks = const <BiliSubtitleTrack>[],
    this.subtitleError,
    this.debugPath,
  });

  final String bvid;
  final int cid;
  final String title;
  final String subtitle;
  final String uri;
  final VesperPlayerSourceProtocol protocol;
  final String transportLabel;
  final bool isLocalFile;
  final Map<String, String> headers;
  final List<VesperMediaTrack> videoTracks;
  final List<BiliSubtitleTrack> subtitleTracks;
  final String? subtitleError;
  final String? debugPath;

  VesperPlayerSource toSource() {
    final sourceLabel = subtitle.isEmpty ? title : '$title · $subtitle';
    final externalSubtitles = subtitleTracks
        .map(
          (track) => VesperExternalSubtitleSource(
            id: track.id,
            uri: track.url,
            mimeType: VesperExternalSubtitleSource.mimeWebvtt,
            language: track.language,
            label: track.languageLabel,
            isDefault: track.isDefault,
          ),
        )
        .toList(growable: false);
    if (isLocalFile) {
      return VesperPlayerSource(
        uri: uri,
        label: sourceLabel,
        kind: VesperPlayerSourceKind.local,
        protocol: protocol,
        headers: headers,
        externalSubtitles: externalSubtitles,
      );
    }

    return VesperPlayerSource.remote(
      uri: uri,
      label: sourceLabel,
      protocol: protocol,
      headers: headers,
      externalSubtitles: externalSubtitles,
    );
  }
}

final class BiliDashSegmentInfo {
  const BiliDashSegmentInfo({
    required this.initialization,
    required this.indexRange,
  });

  final String initialization;
  final String indexRange;
}

final class BiliDashStream {
  const BiliDashStream({
    required this.id,
    required this.baseUrl,
    required this.mimeType,
    required this.codecs,
    required this.bandwidth,
    required this.segmentInfo,
    this.backupUrls = const <String>[],
    this.width,
    this.height,
    this.frameRate,
    this.audioSamplingRate,
    this.codecid,
    this.startWithSap,
    this.representationId,
    this.qualityLabel,
    this.sizeBytes,
  });

  final int id;
  final String baseUrl;
  final String mimeType;
  final String codecs;
  final int bandwidth;
  final BiliDashSegmentInfo segmentInfo;
  final List<String> backupUrls;
  final int? width;
  final int? height;
  final String? frameRate;
  final String? audioSamplingRate;
  final int? codecid;
  final int? startWithSap;
  final String? representationId;
  final String? qualityLabel;
  final int? sizeBytes;

  bool get isVideo => mimeType.startsWith('video/');

  bool get isAudio => mimeType.startsWith('audio/');

  BiliDashStream copyWith({
    String? baseUrl,
    List<String>? backupUrls,
    String? representationId,
    String? qualityLabel,
    int? sizeBytes,
  }) {
    return BiliDashStream(
      id: id,
      baseUrl: baseUrl ?? this.baseUrl,
      mimeType: mimeType,
      codecs: codecs,
      bandwidth: bandwidth,
      segmentInfo: segmentInfo,
      backupUrls: backupUrls ?? this.backupUrls,
      width: width,
      height: height,
      frameRate: frameRate,
      audioSamplingRate: audioSamplingRate,
      codecid: codecid,
      startWithSap: startWithSap,
      representationId: representationId ?? this.representationId,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }
}

final class BiliDashManifestData {
  const BiliDashManifestData({
    required this.durationMs,
    required this.minBufferTimeMs,
    required this.videoStreams,
    required this.audioStreams,
  });

  final int durationMs;
  final int minBufferTimeMs;
  final List<BiliDashStream> videoStreams;
  final List<BiliDashStream> audioStreams;

  BiliDashManifestData copyWith({
    int? durationMs,
    int? minBufferTimeMs,
    List<BiliDashStream>? videoStreams,
    List<BiliDashStream>? audioStreams,
  }) {
    return BiliDashManifestData(
      durationMs: durationMs ?? this.durationMs,
      minBufferTimeMs: minBufferTimeMs ?? this.minBufferTimeMs,
      videoStreams: videoStreams ?? this.videoStreams,
      audioStreams: audioStreams ?? this.audioStreams,
    );
  }
}

enum BiliVideoCodecPreference {
  automatic('默认'),
  av1('AV1'),
  hevc('HEVC'),
  avc('AVC');

  const BiliVideoCodecPreference(this.label);

  final String label;
}

final class BiliDownloadQualityOption {
  const BiliDownloadQualityOption({
    required this.qualityId,
    required this.label,
    required this.videoStreams,
  });

  final int qualityId;
  final String label;
  final List<BiliDashStream> videoStreams;
}

final class BiliDownloadOptions {
  const BiliDownloadOptions({
    required this.bvid,
    required this.cid,
    required this.videoTitle,
    required this.pageTitle,
    required this.coverUrl,
    required this.referer,
    required this.headers,
    required this.manifest,
    required this.qualities,
    required this.variantLabel,
  });

  final String bvid;
  final int cid;
  final String videoTitle;
  final String pageTitle;
  final String coverUrl;
  final String referer;
  final Map<String, String> headers;
  final BiliDashManifestData manifest;
  final List<BiliDownloadQualityOption> qualities;
  final String variantLabel;

  BiliDownloadQualityOption? quality(int qualityId) {
    for (final option in qualities) {
      if (option.qualityId == qualityId) {
        return option;
      }
    }
    return null;
  }

  BiliDownloadOptions copyWith({
    BiliDashManifestData? manifest,
    List<BiliDownloadQualityOption>? qualities,
  }) {
    return BiliDownloadOptions(
      bvid: bvid,
      cid: cid,
      videoTitle: videoTitle,
      pageTitle: pageTitle,
      coverUrl: coverUrl,
      referer: referer,
      headers: headers,
      manifest: manifest ?? this.manifest,
      qualities: qualities ?? this.qualities,
      variantLabel: variantLabel,
    );
  }
}

final class BiliPreparedDownloadAsset {
  const BiliPreparedDownloadAsset({
    required this.assetId,
    required this.source,
    required this.profile,
    required this.assetIndex,
    required this.selectedVideo,
    required this.selectedAudio,
    required this.qualityLabel,
  });

  final String assetId;
  final VesperDownloadSource source;
  final VesperDownloadProfile profile;
  final VesperDownloadAssetIndex assetIndex;
  final BiliDashStream selectedVideo;
  final BiliDashStream selectedAudio;
  final String qualityLabel;
}

String? biliQualityLabelForId(int qualityId) {
  return switch (qualityId) {
    127 => '8K 超高清',
    126 => '杜比视界',
    125 => 'HDR 真彩',
    120 => '4K 超清',
    116 => '1080P60',
    112 => '1080P 高码率',
    80 => '1080P',
    74 => '720P60',
    64 => '720P',
    32 => '480P',
    16 => '360P',
    6 => '240P',
    _ => null,
  };
}

int biliQualityRank(int qualityId) {
  return switch (qualityId) {
    127 => 1200,
    126 => 1190,
    125 => 1180,
    120 => 1100,
    116 => 1000,
    112 => 990,
    80 => 900,
    74 => 800,
    64 => 700,
    32 => 600,
    16 => 500,
    6 => 400,
    _ => qualityId,
  };
}
