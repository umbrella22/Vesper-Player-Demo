enum BiliFavoriteOrder {
  recent('最近收藏', 'mtime'),
  mostPlayed('最多播放', 'view'),
  newestPublished('最新投稿', 'pubtime');

  const BiliFavoriteOrder(this.label, this.apiValue);

  final String label;
  final String apiValue;
}

final class BiliFavoriteItem {
  const BiliFavoriteItem({
    required this.id,
    this.type = 2,
    required this.bvid,
    required this.title,
    required this.coverUrl,
    required this.ownerName,
    required this.durationLabel,
    required this.playCountLabel,
    required this.favoritedAtLabel,
    required this.isAvailable,
  });

  final int id;
  final int type;
  final String bvid;
  final String title;
  final String coverUrl;
  final String ownerName;
  final String durationLabel;
  final String playCountLabel;
  final String favoritedAtLabel;
  final bool isAvailable;

  String get resourceKey => '$id:$type';
}

final class BiliFavoritePage {
  const BiliFavoritePage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.totalCount,
  });

  final List<BiliFavoriteItem> items;
  final int page;
  final int pageSize;
  final bool hasMore;
  final int? totalCount;
}
