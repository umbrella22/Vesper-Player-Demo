final class BiliRegionSection {
  const BiliRegionSection({
    required this.id,
    required this.name,
    required this.icon,
    this.apiType = BiliRegionApiType.pgc,
    this.seasonType,
    this.rid,
  });

  final String id;
  final String name;
  final String icon;
  final BiliRegionApiType apiType;
  final int? seasonType;
  final int? rid;
}

enum BiliRegionApiType { pgc, ranking }

final class BiliRegionVideo {
  const BiliRegionVideo({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.url,
    this.aid,
    this.bvid,
    this.cid,
    this.epId,
    this.seasonId,
    this.subtitle,
    this.scoreLabel,
    this.indexLabel,
    this.followCountLabel,
    this.description,
  });

  final String id;
  final String title;
  final String coverUrl;
  final String url;
  final int? aid;
  final String? bvid;
  final int? cid;
  final int? epId;
  final int? seasonId;
  final String? subtitle;
  final String? scoreLabel;
  final String? indexLabel;
  final String? followCountLabel;
  final String? description;
}

const List<BiliRegionSection> biliRegionSections = <BiliRegionSection>[
  BiliRegionSection(
    id: 'bangumi',
    name: '番剧',
    icon: '📺',
    apiType: BiliRegionApiType.pgc,
    seasonType: 1,
  ),
  BiliRegionSection(
    id: 'guochuang',
    name: '国创',
    icon: '🐼',
    apiType: BiliRegionApiType.pgc,
    seasonType: 4,
  ),
  BiliRegionSection(
    id: 'movie',
    name: '电影',
    icon: '🎬',
    apiType: BiliRegionApiType.pgc,
    seasonType: 2,
  ),
  BiliRegionSection(
    id: 'tv',
    name: '电视剧',
    icon: '📡',
    apiType: BiliRegionApiType.pgc,
    seasonType: 5,
  ),
  BiliRegionSection(
    id: 'documentary',
    name: '纪录片',
    icon: '🎥',
    apiType: BiliRegionApiType.pgc,
    seasonType: 3,
  ),
  BiliRegionSection(
    id: 'variety',
    name: '综艺',
    icon: '🎪',
    apiType: BiliRegionApiType.pgc,
    seasonType: 7,
  ),
  BiliRegionSection(
    id: 'douga',
    name: '动画',
    icon: '🎨',
    apiType: BiliRegionApiType.ranking,
    rid: 1,
  ),
  BiliRegionSection(
    id: 'music',
    name: '音乐',
    icon: '🎵',
    apiType: BiliRegionApiType.ranking,
    rid: 3,
  ),
  BiliRegionSection(
    id: 'game',
    name: '游戏',
    icon: '🎮',
    apiType: BiliRegionApiType.ranking,
    rid: 4,
  ),
  BiliRegionSection(
    id: 'knowledge',
    name: '知识',
    icon: '📚',
    apiType: BiliRegionApiType.ranking,
    rid: 36,
  ),
  BiliRegionSection(
    id: 'tech',
    name: '科技',
    icon: '💻',
    apiType: BiliRegionApiType.ranking,
    rid: 188,
  ),
  BiliRegionSection(
    id: 'life',
    name: '生活',
    icon: '🏠',
    apiType: BiliRegionApiType.ranking,
    rid: 160,
  ),
];
