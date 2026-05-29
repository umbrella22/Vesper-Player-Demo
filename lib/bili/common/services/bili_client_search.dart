part of 'bili_client.dart';

extension _BiliClientSearchParsing on BiliClient {
  BiliSearchResult? _parseSearchResult(Map<String, Object?> value) {
    final bvid = readString(value['bvid']) ?? '';
    if (bvid.isEmpty) {
      return null;
    }

    return BiliSearchResult(
      aid: readInt(value['aid']) ?? 0,
      bvid: bvid,
      title: biliStripHtmlTags(readString(value['title']) ?? bvid),
      author: readString(value['author']) ?? 'UP',
      coverUrl: biliNormalizeImageUrl(readString(value['pic']) ?? ''),
      durationLabel: readDurationLabel(value['duration']),
      playCountLabel: biliFormatCount(readDouble(value['play'])),
      danmakuCountLabel: biliFormatCount(readDouble(value['video_review'])),
      description: biliStripHtmlTags(readString(value['description']) ?? ''),
      publishedAtLabel: readPublishedAtLabel(value['pubdate']),
    );
  }
}
