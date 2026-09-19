import 'package:vesper_media/media/media.dart';

import '../models/bili_models.dart';
import 'bili_quality_mapping.dart';

/// Bilibili 模型 <-> 通用媒体模型 的双向映射。
///
/// [MediaDetail] 只承载壳需要的字段；aid/ownerMid 等 B 站私有字段通过
/// [MediaDetail.platformExtras] 不透明传递，保证映射无损。
final class BiliMediaMapper {
  const BiliMediaMapper._();

  static const String _aidKey = 'aid';
  static const String _ownerMidKey = 'ownerMid';
  static const String _ownerNameKey = 'ownerName';
  static const String _ownerAvatarUrlKey = 'ownerAvatarUrl';
  static const String _descriptionKey = 'description';
  static const String _publishedAtLabelKey = 'publishedAtLabel';
  static const String _playCountLabelKey = 'playCountLabel';
  static const String _likeCountLabelKey = 'likeCountLabel';
  static const String _coinCountLabelKey = 'coinCountLabel';
  static const String _favoriteCountLabelKey = 'favoriteCountLabel';
  static const String _shareCountLabelKey = 'shareCountLabel';
  static const String _episodeIdKey = 'episodeId';
  static const String _dimensionKey = 'dimension';

  static MediaDetail toGenericDetail(BiliVideoDetail detail) {
    return MediaDetail(
      mediaId: detail.bvid,
      title: detail.title,
      coverUrl: detail.coverUrl,
      pages: detail.pages
          .map(
            (page) => toGenericEntry(
              page,
              fallbackAid: detail.aid,
              fallbackBvid: detail.bvid,
            ),
          )
          .toList(growable: false),
      isEpisodic: detail.ownerMid <= 0 && detail.ownerName == '番剧',
      ownerName: detail.ownerName,
      replyCountLabel: detail.replyCountLabel,
      danmakuCountLabel: detail.danmakuCountLabel,
      declaredAspectRatio: detail.dimension?.displayAspectRatio,
      platformExtras: <String, Object?>{
        _aidKey: detail.aid,
        _ownerMidKey: detail.ownerMid,
        _ownerNameKey: detail.ownerName,
        _ownerAvatarUrlKey: detail.ownerAvatarUrl,
        _descriptionKey: detail.description,
        _publishedAtLabelKey: detail.publishedAtLabel,
        _playCountLabelKey: detail.playCountLabel,
        _likeCountLabelKey: detail.likeCountLabel,
        _coinCountLabelKey: detail.coinCountLabel,
        _favoriteCountLabelKey: detail.favoriteCountLabel,
        _shareCountLabelKey: detail.shareCountLabel,
        _dimensionKey: _dimensionMap(detail.dimension),
      },
    );
  }

  static BiliVideoDetail toBiliDetail(MediaDetail detail) {
    final extras = detail.platformExtras;
    return BiliVideoDetail(
      aid: extras[_aidKey] as int? ?? 0,
      bvid: detail.mediaId,
      title: detail.title,
      ownerMid: extras[_ownerMidKey] as int? ?? 0,
      ownerName: extras[_ownerNameKey] as String? ?? '',
      ownerAvatarUrl: extras[_ownerAvatarUrlKey] as String? ?? '',
      coverUrl: detail.coverUrl,
      description: extras[_descriptionKey] as String? ?? '',
      publishedAtLabel: extras[_publishedAtLabelKey] as String?,
      playCountLabel: extras[_playCountLabelKey] as String? ?? '',
      danmakuCountLabel: detail.danmakuCountLabel ?? '',
      replyCountLabel: detail.replyCountLabel ?? '',
      likeCountLabel: extras[_likeCountLabelKey] as String? ?? '',
      coinCountLabel: extras[_coinCountLabelKey] as String? ?? '',
      favoriteCountLabel: extras[_favoriteCountLabelKey] as String? ?? '',
      shareCountLabel: extras[_shareCountLabelKey] as String? ?? '',
      pages: detail.pages.map(toBiliEntry).toList(growable: false),
      dimension: _dimensionFromMap(extras[_dimensionKey]),
    );
  }

  static MediaPlaybackEntry toGenericEntry(
    BiliVideoPageEntry page, {
    int? fallbackAid,
    String? fallbackBvid,
  }) {
    return MediaPlaybackEntry(
      entryId: page.cid.toString(),
      pageNumber: page.pageNumber,
      title: page.title,
      durationSeconds: page.durationSeconds,
      coverUrl: page.coverUrl,
      declaredAspectRatio: page.dimension?.displayAspectRatio,
      platformExtras: <String, Object?>{
        _aidKey: page.aid ?? fallbackAid,
        'bvid': page.bvid ?? fallbackBvid,
        _episodeIdKey: page.episodeId,
        _dimensionKey: _dimensionMap(page.dimension),
      },
    );
  }

  static BiliVideoPageEntry toBiliEntry(MediaPlaybackEntry entry) {
    final extras = entry.platformExtras;
    return BiliVideoPageEntry(
      cid: int.tryParse(entry.entryId) ?? 0,
      pageNumber: entry.pageNumber,
      title: entry.title,
      durationSeconds: entry.durationSeconds,
      coverUrl: entry.coverUrl,
      aid: extras[_aidKey] as int?,
      bvid: extras['bvid'] as String?,
      episodeId: extras[_episodeIdKey] as int?,
      dimension: _dimensionFromMap(extras[_dimensionKey]),
    );
  }

  static Map<String, Object?>? _dimensionMap(BiliVideoDimension? dimension) =>
      dimension == null
      ? null
      : {
          'width': dimension.width,
          'height': dimension.height,
          'rotate': dimension.rotateDegrees,
        };

  static BiliVideoDimension? _dimensionFromMap(Object? value) =>
      switch (value) {
        {
          'width': final int width,
          'height': final int height,
          'rotate': final int rotate,
        } =>
          BiliVideoDimension(
            width: width,
            height: height,
            rotateDegrees: rotate,
          ),
        _ => null,
      };

  static ResolvedMediaPlayback toResolvedPlayback(
    BiliResolvedPlayback resolved,
  ) {
    return ResolvedMediaPlayback(
      title: resolved.title,
      subtitle: resolved.subtitle,
      uri: resolved.uri,
      protocol: resolved.protocol,
      transportLabel: resolved.transportLabel,
      isLocalFile: resolved.isLocalFile,
      headers: resolved.headers,
      videoTracks: resolved.videoTracks,
      subtitleTracks: resolved.subtitleTracks
          .map(toResolvedSubtitle)
          .toList(growable: false),
      subtitleError: resolved.subtitleError,
      debugPath: resolved.debugPath,
      qualityOptions: BiliQualityMapping.buildQualityOptions(
        resolved.videoTracks,
      ),
      supportsCodecSelection: true,
      audioOnlySource: switch (resolved.audioOnlySource) {
        final variant? => ResolvedMediaSourceVariant(
          uri: variant.uri,
          protocol: variant.protocol,
          transportLabel: variant.transportLabel,
          isLocalFile: variant.isLocalFile,
          headers: variant.headers,
          debugPath: variant.debugPath,
        ),
        null => null,
      },
    );
  }

  static ResolvedSubtitleTrack toResolvedSubtitle(BiliSubtitleTrack track) {
    return ResolvedSubtitleTrack(
      id: track.id,
      language: track.language,
      languageLabel: track.languageLabel,
      url: track.url,
      isDefault: track.isDefault,
      format: track.format,
    );
  }

  /// 反向转换（薄包装层使用）：通用解析结果 → B 站形态。
  /// [bvid]/[cid] 由包装层从当前 detail/entry 还原。
  static BiliResolvedPlayback? toBiliResolved(
    ResolvedMediaPlayback? resolved, {
    required String bvid,
    required int cid,
  }) {
    if (resolved == null) {
      return null;
    }
    return BiliResolvedPlayback(
      bvid: bvid,
      cid: cid,
      title: resolved.title,
      subtitle: resolved.subtitle,
      uri: resolved.uri,
      protocol: resolved.protocol,
      transportLabel: resolved.transportLabel,
      isLocalFile: resolved.isLocalFile,
      headers: resolved.headers,
      videoTracks: resolved.videoTracks,
      subtitleTracks: resolved.subtitleTracks
          .map(
            (track) => BiliSubtitleTrack(
              id: track.id,
              language: track.language,
              languageLabel: track.languageLabel,
              url: track.url,
              isDefault: track.isDefault,
              format: track.format,
            ),
          )
          .toList(growable: false),
      subtitleError: resolved.subtitleError,
      debugPath: resolved.debugPath,
      audioOnlySource: switch (resolved.audioOnlySource) {
        final variant? => BiliResolvedPlaybackVariant(
          uri: variant.uri,
          protocol: variant.protocol,
          transportLabel: variant.transportLabel,
          isLocalFile: variant.isLocalFile,
          headers: variant.headers,
          debugPath: variant.debugPath,
        ),
        null => null,
      },
    );
  }
}
