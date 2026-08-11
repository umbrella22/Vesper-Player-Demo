import 'package:flutter/foundation.dart';
import 'package:vesper_player/vesper_player.dart';

final class PlayerModule {
  const PlayerModule._();

  static const plannedScope =
      'Playback pages, control surfaces, source switching, quality UI, and '
      'track/ABR-facing affordances are owned by the app shell while native '
      'video rendering stays inside the SDK.';
}

const _mib = 1024 * 1024;

const mediaPlayerResiliencePolicy = VesperPlaybackResiliencePolicy.streaming();

const mediaPlayerTrackPreferencePolicy = VesperTrackPreferencePolicy(
  preferredAudioLanguage: 'zh',
  preferredSubtitleLanguage: 'zh-Hans',
  subtitleSelection: VesperTrackSelection.disabled(),
);

const mediaPlayerPreloadBudgetPolicy = VesperPreloadBudgetPolicy(
  maxConcurrentTasks: 2,
  maxMemoryBytes: 16 * _mib,
  maxDiskBytes: 256 * _mib,
  warmupWindowMs: 30000,
);

const mediaDlnaFormatAdaptationConfig =
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

VesperBenchmarkConfiguration mediaPlayerBenchmarkConfiguration() {
  if (!kDebugMode) {
    return const VesperBenchmarkConfiguration.disabled();
  }

  return const VesperBenchmarkConfiguration(
    enabled: true,
    maxBufferedEvents: 4096,
    includeRawEvents: true,
  );
}

Future<VesperSourceNormalizerConfiguration>
mediaPlayerSourceNormalizerConfiguration() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const VesperSourceNormalizerConfiguration();
  }

  return VesperSourceNormalizerConfiguration.preferBundled();
}

VesperSystemPlaybackMetadata mediaPlayerSystemPlaybackMetadata({
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

VesperSystemPlaybackConfiguration mediaPlayerSystemPlaybackConfiguration({
  required VesperSystemPlaybackMetadata metadata,
  VesperBackgroundPlaybackMode backgroundMode =
      VesperBackgroundPlaybackMode.continueAudio,
}) {
  return VesperSystemPlaybackConfiguration(
    backgroundMode: backgroundMode,
    showSystemControls: true,
    showSeekActions: true,
    metadata: metadata,
  );
}
