import 'package:flutter/foundation.dart';
import 'package:vesper_media/media/media.dart';

import 'common/services/bili_client.dart';
import 'common/services/bili_history_store.dart';
import 'common/services/bili_media_history_adapter.dart';
import 'common/services/bili_media_mapper.dart';
import 'common/services/bili_quality_mapping.dart';
import 'common/view_models/bili_playback_view_model.dart';
import '../danmaku/services/bili_danmaku_provider.dart';

/// Bilibili 的 [MediaPlatformAdapter] 实现（参考实现）。
///
/// 包装 [BiliClient]：其现有 `resolvePlayback` 采用 B 站类型签名，
/// 适配器在边界做双向映射，B 站内部调用链不改动。
/// 能力接线：history 已接入（[BiliMediaHistoryStoreAdapter]）、danmaku 已接入
/// （[BiliDanmakuProvider]）；engagement 由 [attachEngagement] 回填
/// （view model 构造完成后注入，规避构造循环）；contentSurfaces 保持能力缺省
/// ——B 站内容面板（简介/评论/相关视频）经薄包装层注入，不走 adapter 槽位。
final class BiliMediaPlatformAdapter implements MediaPlatformAdapter {
  BiliMediaPlatformAdapter({
    required BiliClient client,
    BiliHistoryStore? historyStore,
    BiliDanmakuProvider? danmakuProvider,
  }) : _client = client,
       _history = BiliMediaHistoryStoreAdapter(
         historyStore ?? const BiliHistoryStore(),
       ),
       // 弹幕 provider 必须是稳定实例：播放快照会持续重建舞台并读取
       // adapter.danmaku，若每次返回新实例，MediaDanmakuLayer 会因
       // provider 身份变化清空事件并重新订阅，反复请求弹幕 XML。
       _danmaku = danmakuProvider ?? BiliDanmakuProvider(client: client);

  final BiliClient _client;
  final BiliMediaHistoryStoreAdapter _history;
  final BiliDanmakuProvider _danmaku;

  BiliPlaybackViewModel? _engagementVm;

  /// view model 构造完成后回填，供 [engagement] 组装运行时动作快照。
  void attachEngagement(BiliPlaybackViewModel vm) {
    _engagementVm = vm;
  }

  @override
  Future<ResolvedMediaPlayback> resolvePlayback({
    required MediaDetail detail,
    required MediaPlaybackEntry entry,
  }) async {
    final biliDetail = BiliMediaMapper.toBiliDetail(detail);
    final biliPage = BiliMediaMapper.toBiliEntry(entry);
    final resolved = await _client.resolvePlayback(
      detail: biliDetail,
      page: biliPage,
      platform: defaultTargetPlatform,
    );
    return BiliMediaMapper.toResolvedPlayback(resolved);
  }

  @override
  MediaEngagementCapability? get engagement {
    final vm = _engagementVm;
    if (vm == null) {
      return null;
    }
    final isPgc = vm.detail.ownerMid <= 0 && vm.detail.ownerName == '番剧';
    // PGC 隐藏点赞/投币/收藏/分享，但保留稍后再看
    // （迁移前 _WatchLaterButton 位于 !isPgc 之外，番剧也有入口）。
    final actions = <MediaEngagementActionSpec>[
      if (!isPgc) ...[
        MediaEngagementActionSpec(
          id: MediaEngagementActionId.like,
          label: '点赞',
          countLabel: vm.detail.likeCountLabel,
          selected: vm.engagement?.isLiked ?? false,
          busy: vm.pendingEngagementAction == BiliEngagementAction.like,
          perform: vm.toggleLike,
        ),
        MediaEngagementActionSpec(
          id: MediaEngagementActionId.coin,
          label: '硬币',
          countLabel: vm.coinCountLabel,
          selected: vm.sentCoinCount > 0,
          busy: vm.pendingEngagementAction == BiliEngagementAction.coin,
          perform: vm.addCoin,
        ),
        MediaEngagementActionSpec(
          id: MediaEngagementActionId.favorite,
          label: '收藏',
          countLabel: vm.detail.favoriteCountLabel,
          selected: vm.engagement?.isFavorited ?? false,
          busy: vm.pendingEngagementAction == BiliEngagementAction.favorite,
          perform: vm.toggleFavorite,
        ),
        MediaEngagementActionSpec(
          id: MediaEngagementActionId.share,
          label: '分享',
          countLabel: vm.shareCountLabel,
          busy: vm.pendingEngagementAction == BiliEngagementAction.share,
          perform: vm.shareVideo,
        ),
      ],
      MediaEngagementActionSpec(
        id: MediaEngagementActionId.watchLater,
        label: vm.isInWatchLater ? '移出稍后再看' : '加入稍后再看',
        selected: vm.isInWatchLater,
        busy:
            vm.watchLaterLoading ||
            vm.pendingEngagementAction == BiliEngagementAction.watchLater,
        perform: vm.toggleWatchLater,
      ),
    ];
    return MediaEngagementCapability(
      actions: actions,
      placement: MediaEngagementPlacement.intro,
    );
  }

  @override
  MediaDanmakuProvider? get danmaku => _danmaku;

  @override
  MediaContentSurfaces? get contentSurfaces => null;

  @override
  MediaHistoryStore? get history => _history;

  @override
  MediaQualityPolicy get qualityPolicy => BiliQualityMapping.buildQualityPolicy();

  @override
  MediaDlnaConfig? get dlnaConfig =>
      MediaDlnaConfig(formatAdaptation: mediaDlnaFormatAdaptationConfig);
}
