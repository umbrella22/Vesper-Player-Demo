/// Bilibili 网络端点的单一真相源。
///
/// 本文件是网络层的无依赖叶子文件：不 import 其它 bili 文件，避免循环依赖。
/// 所有 host、referer、CDN host、API path 的字面量集中在此定义，
/// service 层其余文件只应引用这里的常量，不应再写裸字符串。
///
/// 修改端点（如切换 API host、调整 referer 形式）请只改本文件。
library;

/// 主 API host。绝大多数 `/x/...`、`/pgc/...` 接口都走这里。
const String biliApiHost = 'api.bilibili.com';

/// 登录/扫码 host。
const String biliPassportHost = 'passport.bilibili.com';

/// 站点主域名，用于 cookie 预热与默认 referer 的基址。
const String biliWebHost = 'www.bilibili.com';

/// 个人空间 host，用于关注操作等的 referer。
const String biliSpaceHost = 'space.bilibili.com';

/// 媒体 CDN 的备用 host（PCDN 全军覆没时回退）。
const String biliBackupMediaHost = 'upos-sz-mirrorcoso1.bilivideo.com';

/// 字幕/资源等 URL 的解析基址（带尾斜杠，用于 Uri.resolve）。
///
/// 从 [biliApiHost] 派生：切换 API host 时，相对 URL 解析随之跟随，
/// 不会出现"请求已切域名、字幕仍解析到旧 host"的漂移。
const String biliApiBaseUrl = 'https://$biliApiHost/';

/// API 请求的默认 referer（带尾斜杠）。从 [biliWebHost] 派生。
const String biliDefaultReferer = 'https://$biliWebHost/';

/// 媒体请求的 referer / Origin 基址（无尾斜杠）。从 [biliWebHost] 派生。
const String biliMediaReferer = 'https://$biliWebHost';

/// 历史/稍后再看页面的 referer。从 [biliWebHost] 派生。
const String biliHistoryReferer = 'https://$biliWebHost/account/history';
const String biliWatchlaterReferer = 'https://$biliWebHost/watchlater/list';

/// 视频页 HTTP Referer（用于播放、评论、互动等接口）。从 [biliWebHost] 派生。
String biliVideoReferer(String bvid) => 'https://$biliWebHost/video/$bvid';

/// 视频页对象 URL（用于列表项的 fallback 链接，区别于 referer 的语义）。
String biliVideoUrl(String bvid) => 'https://$biliWebHost/video/$bvid';

/// 关注/取关 UP 主时的 referer。从 [biliSpaceHost] 派生。
String biliSpaceReferer(int mid) => 'https://$biliSpaceHost/$mid';

/// 投稿列表页面的 referer。保持空间卡片和投稿请求的来源一致。
String biliSpaceVideosReferer(int mid) => 'https://$biliSpaceHost/$mid/video';

/// 查看粉丝/关注列表时的 referer。从 [biliSpaceHost] 派生。
String biliFansFollowReferer(int mid) =>
    'https://$biliSpaceHost/$mid/fans/follow';

/// Bilibili 接口路径登记表。
///
/// 用 `abstract final class` 收口，避免顶层命名空间被几十个 `/x/...` 污染，
/// 同时保证路径只能是编译期常量。新增接口时在此追加即可。
abstract final class BiliApiPaths {
  // ---- 搜索 ----
  static const searchType = '/x/web-interface/wbi/search/type';

  // ---- 视频/导航 ----
  static const videoView = '/x/web-interface/view';
  static const userCard = '/x/web-interface/card';
  static const nav = '/x/web-interface/nav';
  static const navStat = '/x/web-interface/nav/stat';
  static const feedRcmd = '/x/web-interface/index/top/feed/rcmd';
  static const archiveRelated = '/x/web-interface/archive/related';

  // ---- 视频互动 ----
  static const archiveRelation = '/x/web-interface/archive/relation';
  static const archiveLike = '/x/web-interface/archive/like';
  static const archiveCoins = '/x/web-interface/archive/coins';
  static const coinAdd = '/x/web-interface/coin/add';
  static const shareAdd = '/x/web-interface/share/add';

  // ---- 排行/分区 ----
  static const rankingV2 = '/x/web-interface/ranking/v2';

  // ---- 评论/弹幕 ----
  static const replyList = '/x/v2/reply';
  static const replyReply = '/x/v2/reply/reply';
  static const replyAdd = '/x/v2/reply/add';
  static const danmakuList = '/x/v1/dm/list.so';
  static const danmakuSegWeb = '/x/v2/dm/web/seg.so';
  static const danmakuViewWeb = '/x/v2/dm/web/view';

  // ---- 收藏 ----
  static const favResourceDeal = '/x/v3/fav/resource/deal';
  static const favFolderListAll = '/x/v3/fav/folder/created/list-all';

  // ---- 关注 ----
  static const relationModify = '/x/relation/modify';
  static const relationFollowings = '/x/relation/followings';

  // ---- 用户空间 ----
  static const spaceArchiveSearch = '/x/space/wbi/arc/search';

  // ---- 播放器 ----
  static const playerV2 = '/x/player/v2';
  static const playerWbiV2 = '/x/player/wbi/v2';
  static const playerWbiPlayUrl = '/x/player/wbi/playurl';

  // ---- 登录/扫码 ----
  static const qrcodeGenerate = '/x/passport-login/web/qrcode/generate';
  static const qrcodePoll = '/x/passport-login/web/qrcode/poll';

  // ---- 设备指纹（buvid 预热）----
  static const frontendFingerSpi = '/x/frontend/finger/spi';

  // ---- 历史/稍后再看 ----
  static const historyCursor = '/x/web-interface/history/cursor';
  static const historyV2 = '/x/v2/history';
  static const historyToviewWeb = '/x/v2/history/toview/web';
  static const historyToview = '/x/v2/history/toview';
  static const historyToviewAdd = '/x/v2/history/toview/add';
  static const historyToviewDel = '/x/v2/history/toview/del';

  // ---- 番剧（PGC）----
  static const pgcSeasonResult = '/pgc/season/index/result';
  static const pgcViewSeason = '/pgc/view/web/season';
}
