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

/// 一次收藏夹归属的增删差异。
///
/// 调用方只在确认后提交差异，不在点击瞬间推断目标收藏夹——取消收藏时
/// 只移出用户明确取消的收藏夹，而不是服务端返回的全部归属。
final class BiliFavoriteSelection {
  const BiliFavoriteSelection({
    required this.addFolderIds,
    required this.removeFolderIds,
  });

  final List<int> addFolderIds;
  final List<int> removeFolderIds;

  bool get isEmpty => addFolderIds.isEmpty && removeFolderIds.isEmpty;

  /// 计算从 [current] 到 [target] 的差异，两者都是收藏夹 ID 集合。
  factory BiliFavoriteSelection.diff({
    required Iterable<int> current,
    required Iterable<int> target,
  }) {
    final currentSet = current.toSet();
    final targetSet = target.toSet();
    return BiliFavoriteSelection(
      addFolderIds: targetSet
          .where((id) => !currentSet.contains(id))
          .toList(growable: false),
      removeFolderIds: currentSet
          .where((id) => !targetSet.contains(id))
          .toList(growable: false),
    );
  }
}
