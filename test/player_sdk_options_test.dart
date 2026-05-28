import 'package:bilibili_player/player/player_sdk_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_player/vesper_player.dart';

void main() {
  group('player SDK options', () {
    test('system playback metadata keeps Bili card labels', () {
      final metadata = biliPlayerSystemPlaybackMetadata(
        title: '测试视频',
        subtitle: 'P1',
        artist: 'Owner',
        artworkUri: 'https://example.com/cover.jpg',
        contentUri: 'https://example.com/video.mpd',
        durationMs: 60000,
      );

      expect(metadata.title, '测试视频 · P1');
      expect(metadata.artist, 'Owner');
      expect(metadata.albumTitle, 'P1');
      expect(metadata.artworkUri, 'https://example.com/cover.jpg');
      expect(metadata.contentUri, 'https://example.com/video.mpd');
      expect(metadata.durationMs, 60000);
      expect(metadata.isLive, isFalse);
    });

    test('system playback configuration enables media card controls', () {
      final metadata = biliPlayerSystemPlaybackMetadata(title: '测试视频');
      final configuration = biliPlayerSystemPlaybackConfiguration(
        metadata: metadata,
      );

      expect(configuration.enabled, isTrue);
      expect(configuration.showSystemControls, isTrue);
      expect(configuration.showSeekActions, isTrue);
      expect(configuration.metadata, same(metadata));
      expect(configuration.toMap(), <String, Object?>{
        'enabled': true,
        'backgroundMode': 'continueAudio',
        'showSystemControls': true,
        'showSeekActions': true,
        'metadata': metadata.toMap(),
        'controls': <String, Object?>{
          'compactButtons': <Object?>[
            <String, Object?>{'kind': 'seekBack', 'seekOffsetMs': 10000},
            <String, Object?>{'kind': 'playPause'},
            <String, Object?>{'kind': 'seekForward', 'seekOffsetMs': 10000},
          ],
        },
      });
    });

    test('DLNA format adaptation enables DASH remux fallback', () {
      expect(biliDlnaFormatAdaptationConfig.enabled, isTrue);
      expect(
        biliDlnaFormatAdaptationConfig.preferredFallback,
        VesperExternalFallbackFormat.mpegTs,
      );
      expect(biliDlnaFormatAdaptationConfig.allowHls, isTrue);
      expect(biliDlnaFormatAdaptationConfig.enableRangeCache, isTrue);
      expect(
        biliDlnaFormatAdaptationConfig.allowRemoteDashMediaReferences,
        isTrue,
      );
      expect(
        biliDlnaFormatAdaptationConfig.allowPrivateRemoteDashMediaAddresses,
        isFalse,
      );
      expect(
        biliDlnaFormatAdaptationConfig.remoteDashMediaRequestHeaders,
        <String>{
          'Accept',
          'Accept-Language',
          'Cookie',
          'Origin',
          'Referer',
          'User-Agent',
        },
      );
    });
  });
}
