import 'package:flutter/foundation.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_media/media/capabilities/media_audio_compatibility.dart';
import 'common/services/bili_audio_policy.dart';
import 'common/services/bili_audio_policy_controller.dart';
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

  late final _audioCompatibility = _BiliAudioCompatibility(_client.audioPolicy);

  @override
  MediaAudioCompatibility? get audioCompatibility =>
      defaultTargetPlatform == TargetPlatform.android
      ? _audioCompatibility
      : null;

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

final class _BiliAudioCompatibility implements MediaAudioCompatibility {
  _BiliAudioCompatibility(this.policy);
  final BiliAudioPolicyController policy;

  @override
  bool canRecover(
    ResolvedMediaPlayback playback,
    VesperPlayerSnapshot snapshot,
  ) {
    if (!playback.canRefreshSource ||
        policy.recoveryAttemptedThisSession ||
        policy.override != BiliAudioPolicyOverride.automatic ||
        playback.audioCompatibilityRestricted) {
      return false;
    }
    final declared = playback.audioTracks;
    // Offline/progressive sources do not advertise replaceable DASH audio.
    if (!declared.any((track) => BiliAudioPolicy.isDolbyCodec(track.codec)) ||
        !declared.any((track) => !BiliAudioPolicy.isDolbyCodec(track.codec))) {
      return false;
    }
    final selection = snapshot.trackSelection.audio;
    if (selection.mode == VesperTrackSelectionMode.disabled) return false;
    final observedAudio = snapshot.playbackDiagnostics?.audio;
    if (observedAudio != null &&
        observedAudio.evidence != VesperAudioDiagnosticEvidence.unknown &&
        (observedAudio.codec?.isNotEmpty ?? false) &&
        !BiliAudioPolicy.isDolbyCodec(observedAudio.codec)) {
      return false;
    }
    if (selection.mode == VesperTrackSelectionMode.track) {
      final selected = snapshot.trackCatalog.audioTracks
          .where((track) => track.id == selection.trackId)
          .firstOrNull;
      if (selected != null && !BiliAudioPolicy.isDolbyCodec(selected.codec)) {
        return false;
      }
    }
    return true;
  }

  @override
  bool claimRecovery() => policy.recordRecoveryAttempt();

  @override
  String? fallbackTrackId(
    ResolvedMediaPlayback playback,
    VesperPlayerSnapshot snapshot,
  ) {
    if (!playback.audioCompatibilityRestricted ||
        !snapshot.capabilities.supportsAudioTrackSelection ||
        snapshot.trackSelection.audio.mode ==
            VesperTrackSelectionMode.disabled) {
      return null;
    }
    final tracks = snapshot.trackCatalog.audioTracks;
    if (!tracks.any((track) => BiliAudioPolicy.isDolbyCodec(track.codec))) {
      return null;
    }
    final candidates =
        tracks
            .where(
              (track) =>
                  (track.codec?.toLowerCase().startsWith('mp4a') ?? false) &&
                  track.support.status != VesperTrackSupportStatus.unsupported,
            )
            .toList()
          ..sort((a, b) => (b.bitRate ?? 0).compareTo(a.bitRate ?? 0));
    final id = candidates.firstOrNull?.id;
    return id == snapshot.trackSelection.audio.trackId ? null : id;
  }
}
