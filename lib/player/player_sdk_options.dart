import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

final class BiliPlayerPluginResolver {
  const BiliPlayerPluginResolver({
    MethodChannel channel = const MethodChannel(
      'dev.ikaros.bilibili_player/player_plugins',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<List<String>> bundledSourceNormalizerPluginLibraryPaths() async {
    try {
      final result = await _channel.invokeListMethod<String>(
        'bundledSourceNormalizerPluginLibraryPaths',
      );
      return (result ?? const <String>[])
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      return const <String>[];
    } on PlatformException {
      return const <String>[];
    }
  }
}

Future<VesperSourceNormalizerConfiguration>
biliPlayerSourceNormalizerConfiguration({
  BiliPlayerPluginResolver pluginResolver = const BiliPlayerPluginResolver(),
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const VesperSourceNormalizerConfiguration();
  }

  final pluginLibraryPaths = await pluginResolver
      .bundledSourceNormalizerPluginLibraryPaths();
  if (pluginLibraryPaths.isEmpty) {
    return const VesperSourceNormalizerConfiguration();
  }

  return VesperSourceNormalizerConfiguration(
    mode: VesperSourceNormalizerMode.preferNormalized,
    pluginLibraryPaths: pluginLibraryPaths,
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
