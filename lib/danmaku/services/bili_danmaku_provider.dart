import 'package:vesper_media/media/media.dart';

import '../../bili/common/services/bili_client.dart';
import '../models/danmaku_models.dart';
import 'bili_danmaku_repository.dart';

/// Bilibili 的 [MediaDanmakuProvider] 参考实现：
/// 仓库解析（protobuf/XML）→ 归一化 [MediaDanmakuEvent] 事件流。
///
/// client 必须显式注入（与播放会话同源的登录态/Cookie），
/// 不得回退到 `BiliClient.instance`，避免与注入的会话状态分叉。
final class BiliDanmakuProvider implements MediaDanmakuProvider {
  BiliDanmakuProvider({
    required BiliClient client,
    BiliDanmakuRepository? repository,
  }) : _repository = repository ?? BiliDanmakuRepository(client: client);

  final BiliDanmakuRepository _repository;

  @override
  Stream<MediaDanmakuEvent> danmakuFor(MediaPlaybackTarget target) async* {
    final bvid = target.detail.mediaId;
    final cid = int.tryParse(target.entry.entryId) ?? 0;
    if (bvid.isEmpty || cid <= 0) {
      return;
    }
    final List<BiliDanmakuEntry> entries;
    try {
      entries = await _repository.loadEntries(bvid: bvid, cid: cid);
    } catch (_) {
      // 弹幕加载失败不阻塞播放。
      return;
    }
    for (final entry in entries) {
      // 无法渲染的模式（如 B 站旧版特殊弹幕）跳过，与旧 overlay 语义一致。
      if (!entry.mode.isSupported) {
        continue;
      }
      yield MediaDanmakuEvent(
        timeMs: entry.appearAtMs,
        text: entry.text,
        style: MediaDanmakuStyle(
          color: entry.colorValue,
          position: _positionForMode(entry.mode),
          // B 站 XML 的 25 为标准档；scale 以 25 为 1.0。
          fontSizeScale: entry.fontSize > 0 ? entry.fontSize / 25 : 1.0,
        ),
      );
    }
  }

  MediaDanmakuPosition _positionForMode(BiliDanmakuMode mode) {
    return switch (mode) {
      BiliDanmakuMode.scroll => MediaDanmakuPosition.roll,
      BiliDanmakuMode.reverse => MediaDanmakuPosition.reverse,
      BiliDanmakuMode.top => MediaDanmakuPosition.top,
      BiliDanmakuMode.bottom => MediaDanmakuPosition.bottom,
      BiliDanmakuMode.unsupported => MediaDanmakuPosition.roll,
    };
  }
}
