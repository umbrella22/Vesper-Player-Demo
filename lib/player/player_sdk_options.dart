import 'package:flutter/foundation.dart';
import 'package:vesper_player/vesper_player.dart';

const _mib = 1024 * 1024;

const biliPlayerResiliencePolicy = VesperPlaybackResiliencePolicy.streaming();

const biliPlayerTrackPreferencePolicy = VesperTrackPreferencePolicy(
  preferredAudioLanguage: 'zh',
  preferredSubtitleLanguage: 'zh-Hans',
  subtitleSelection: VesperTrackSelection.disabled(),
);

const biliPlayerPreloadBudgetPolicy = VesperPreloadBudgetPolicy(
  maxConcurrentTasks: 2,
  maxMemoryBytes: 16 * _mib,
  maxDiskBytes: 256 * _mib,
  warmupWindowMs: 30000,
);

const biliDlnaFormatAdaptationConfig =
    VesperExternalFormatAdaptationConfig.dlnaRemux(
      allowRemoteDashMediaReferences: true,
      remoteDashMediaRequestHeaders: <String>{
        'Accept',
        'Accept-Language',
        'Cookie',
        'Origin',
        'Referer',
        'User-Agent',
      },
    );

VesperBenchmarkConfiguration biliPlayerBenchmarkConfiguration() {
  if (!kDebugMode) {
    return const VesperBenchmarkConfiguration.disabled();
  }

  return const VesperBenchmarkConfiguration(
    enabled: true,
    maxBufferedEvents: 4096,
    includeRawEvents: true,
  );
}

VesperSystemPlaybackMetadata biliPlayerSystemPlaybackMetadata({
  required String title,
  String? subtitle,
  String? artist,
  String? artworkUri,
  String? contentUri,
  int? durationMs,
  bool isLive = false,
}) {
  final normalizedSubtitle = subtitle?.trim();
  return VesperSystemPlaybackMetadata(
    title: normalizedSubtitle == null || normalizedSubtitle.isEmpty
        ? title
        : '$title · $normalizedSubtitle',
    artist: artist,
    albumTitle: subtitle,
    artworkUri: artworkUri,
    contentUri: contentUri,
    durationMs: durationMs,
    isLive: isLive,
  );
}

VesperSystemPlaybackConfiguration biliPlayerSystemPlaybackConfiguration({
  required VesperSystemPlaybackMetadata metadata,
}) {
  return VesperSystemPlaybackConfiguration(
    showSystemControls: true,
    showSeekActions: true,
    metadata: metadata,
  );
}
