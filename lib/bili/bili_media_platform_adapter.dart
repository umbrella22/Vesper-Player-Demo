import 'package:flutter/foundation.dart';
import 'package:vesper_media/media/media.dart';

import 'common/services/bili_client.dart';
import 'common/services/bili_history_store.dart';
import 'common/services/bili_media_history_adapter.dart';
import 'common/services/bili_media_mapper.dart';
import 'common/services/bili_quality_mapping.dart';
import '../danmaku/services/bili_danmaku_provider.dart';

/// Bilibili 的 [MediaPlatformAdapter] 实现（参考实现）。
///
/// 包装 [BiliClient]：其现有 `resolvePlayback` 采用 B 站类型签名，
/// 适配器在边界做双向映射，B 站内部调用链不改动。
/// 能力接线：history 已接入（[BiliMediaHistoryStoreAdapter]）、danmaku 已接入
/// （[BiliDanmakuProvider]）。互动和内容面板由 B 站播放页通过
/// [MediaPlaybackBinding] 绑定，不进入长期存活的 adapter。
final class BiliMediaPlatformAdapter extends MediaPlatformAdapter {
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
  MediaDanmakuProvider? get danmaku => _danmaku;

  @override
  MediaHistoryStore? get history => _history;

  @override
  MediaQualityPolicy get qualityPolicy =>
      BiliQualityMapping.buildQualityPolicy();

  @override
  MediaDlnaConfig? get dlnaConfig =>
      MediaDlnaConfig(formatAdaptation: mediaDlnaFormatAdaptationConfig);
}
