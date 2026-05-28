part of 'bili_client.dart';

extension _BiliClientSearchParsing on BiliClient {
  BiliSearchResult? _parseSearchResult(Map<String, Object?> value) {
    final bvid = value['bvid'] as String? ?? '';
    if (bvid.isEmpty) {
      return null;
    }

    return BiliSearchResult(
      aid: (value['aid'] as num?)?.toInt() ?? 0,
      bvid: bvid,
      title: biliStripHtmlTags(value['title'] as String? ?? bvid),
      author: value['author'] as String? ?? 'UP',
      coverUrl: biliNormalizeImageUrl(value['pic'] as String? ?? ''),
      durationLabel: value['duration'] as String? ?? '--:--',
      playCountLabel: biliFormatCount((value['play'] as num?)?.toDouble()),
      danmakuCountLabel: biliFormatCount(
        (value['video_review'] as num?)?.toDouble(),
      ),
      description: biliStripHtmlTags(value['description'] as String? ?? ''),
      publishedAtLabel: value['pubdate'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              ((value['pubdate'] as num).toInt()) * 1000,
            ).toLocal().toString().split(' ').first
          : null,
    );
  }
}
