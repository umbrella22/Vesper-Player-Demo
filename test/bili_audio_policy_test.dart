import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_media/bili/bili_media_platform_adapter.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/media/models/resolved_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_audio_policy.dart';
import 'package:vesper_media/bili/common/services/bili_audio_policy_controller.dart';
import 'package:vesper_media/bili/common/services/bili_platform_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const quirks = BiliAudioQuirkTable(
    entries: [
      BiliAudioQuirk(brandPrefix: 'oppo', model: 'verified-model'),
      BiliAudioQuirk(
        brandPrefix: 'test',
        model: 'family-',
        modelIsPrefix: true,
      ),
    ],
  );
  test(
    'quirks require a known brand/model; explicit intent takes precedence',
    () {
      BiliAudioPolicy resolve({
        String brand = 'OPPO',
        String model = 'verified-model',
        BiliAudioPolicyOverride override = BiliAudioPolicyOverride.automatic,
        bool recovered = false,
      }) => BiliAudioPolicy.resolve(
        override: override,
        brand: brand,
        model: model,
        quirks: quirks,
        recoveryAttemptedThisSession: recovered,
      );
      expect(resolve().reason, BiliAudioPolicyReason.quirk);
      expect(resolve(model: 'other').allowDolby, isTrue);
      expect(resolve(brand: '').allowDolby, isTrue);
      expect(resolve(model: '').allowDolby, isTrue);
      expect(
        resolve(brand: 'test brand', model: 'family-123').allowDolby,
        isFalse,
      );
      expect(
        resolve(
          override: BiliAudioPolicyOverride.allowDolby,
          recovered: true,
        ).allowDolby,
        isTrue,
      );
      expect(
        resolve(
          model: 'other',
          override: BiliAudioPolicyOverride.blockDolby,
        ).reason,
        BiliAudioPolicyReason.override,
      );
      expect(
        resolve(model: 'other', recovered: true).reason,
        BiliAudioPolicyReason.watchdog,
      );
      expect(
        const BiliAudioQuirkTable().blocksDolby('OPPO', 'anything'),
        isFalse,
      );
    },
  );

  test(
    'filter recognizes ids and codecs, preserves FLAC and never removes all audio',
    () {
      final aac = audio(30280, 'mp4a.40.2');
      final flac = audio(30251, 'fLaC');
      final manifest = BiliDashManifestData(
        durationMs: 60000,
        minBufferTimeMs: 1500,
        videoStreams: const [],
        audioStreams: [aac, audio(30250, 'unknown'), audio(999, 'EAC3'), flac],
      );
      const policy = BiliAudioPolicy(
        allowDolby: false,
        reason: BiliAudioPolicyReason.quirk,
      );
      final filtered = policy.filter(manifest);
      expect(filtered.audioStreams, [aac, flac]);
      expect(
        policy.diagnosticLabel(manifest, filtered),
        contains('dolby-blocked(quirk)'),
      );
      final dolbyOnly = manifest.copyWith(audioStreams: [audio(30255, 'ec-3')]);
      expect(policy.filter(dolbyOnly), same(dolbyOnly));
      expect(
        policy.diagnosticLabel(dolbyOnly, dolbyOnly),
        contains('filter-skipped=no-alternative'),
      );
    },
  );

  test(
    'automatic recovery is session-only and explicit preference survives restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('audio-policy-');
      addTearDown(() => dir.delete(recursive: true));
      final store = AppSettingsStore(baseDirectory: dir, legacyDirectory: dir);
      final controller = BiliAudioPolicyController(store: store);
      expect(controller.recordRecoveryAttempt(), isTrue);
      expect(controller.recordRecoveryAttempt(), isFalse);
      expect(
        (await controller.resolve()).reason,
        BiliAudioPolicyReason.watchdog,
      );
      expect(
        (await store.loadSnapshot()).audioPolicyOverride,
        BiliAudioPolicyOverride.automatic,
      );
      await controller.setOverride(BiliAudioPolicyOverride.allowDolby);
      expect((await controller.resolve()).allowDolby, isTrue);
      expect(
        (await store.loadSnapshot()).audioPolicyOverride,
        BiliAudioPolicyOverride.allowDolby,
      );
      final fresh = BiliAudioPolicyController(
        initialOverride: (await store.loadSnapshot()).audioPolicyOverride,
      );
      expect(fresh.recoveryAttemptedThisSession, isFalse);
      expect(fresh.recordRecoveryAttempt(), isFalse);
    },
  );

  test(
    'Bilibili recovery respects audio intent and uses native catalog ids',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final client = BiliClient();
      addTearDown(() => client.transport.httpClient.close(force: true));
      final compatibility = BiliMediaPlatformAdapter(
        client: client,
      ).audioCompatibility!;
      const tracks = [
        VesperMediaTrack(
          id: 'opaque-dolby',
          kind: VesperMediaTrackKind.audio,
          codec: 'ec-3',
        ),
        VesperMediaTrack(
          id: 'native-aac-high',
          kind: VesperMediaTrackKind.audio,
          codec: 'mp4a.40.2',
          bitRate: 192000,
        ),
        VesperMediaTrack(
          id: 'native-aac-low',
          kind: VesperMediaTrackKind.audio,
          codec: 'mp4a.40.2',
          bitRate: 128000,
        ),
      ];
      ResolvedMediaPlayback source({
        bool restricted = false,
        bool refreshable = true,
      }) => ResolvedMediaPlayback(
        title: 't',
        subtitle: '',
        uri: 'file:///manifest.mpd',
        protocol: VesperPlayerSourceProtocol.dash,
        transportLabel: '',
        isLocalFile: true,
        canRefreshSource: refreshable,
        audioTracks: tracks,
        audioCompatibilityRestricted: restricted,
      );
      final snapshot = const VesperPlayerSnapshot.initial().copyWith(
        capabilities: const VesperPlayerCapabilities(
          supportsAudioTrackSelection: true,
        ),
        trackCatalog: const VesperTrackCatalog(tracks: tracks),
      );
      expect(compatibility.canRecover(source(), snapshot), isTrue);
      expect(
        compatibility.canRecover(
          source(),
          snapshot.copyWith(
            playbackDiagnostics: const VesperPlaybackDiagnosticsSnapshot(
              playbackEpoch: 1,
              audio: VesperAudioPlaybackDiagnostics(
                evidence: VesperAudioDiagnosticEvidence.runtimeFormat,
                codec: 'mp4a.40.2',
              ),
            ),
          ),
        ),
        isFalse,
      );
      expect(
        compatibility.canRecover(source(refreshable: false), snapshot),
        isFalse,
      );
      expect(
        compatibility.canRecover(source(restricted: true), snapshot),
        isFalse,
      );
      expect(
        compatibility.canRecover(
          source(),
          snapshot.copyWith(
            trackSelection: const VesperTrackSelectionSnapshot(
              audio: VesperTrackSelection.track('native-aac-high'),
            ),
          ),
        ),
        isFalse,
      );
      expect(
        compatibility.fallbackTrackId(source(restricted: true), snapshot),
        'native-aac-high',
      );
      expect(compatibility.fallbackTrackId(source(), snapshot), isNull);
      expect(compatibility.claimRecovery(), isTrue);
      expect(compatibility.canRecover(source(), snapshot), isFalse);
      expect(compatibility.claimRecovery(), isFalse);
    },
  );

  test(
    'missing and failed platform methods leave device identity unknown',
    () async {
      const channel = MethodChannel('dev.ikaros.vesper_player/platform');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final failure in [
        MissingPluginException(),
        PlatformException(code: 'unavailable'),
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => throw failure);
        expect(await BiliPlatformInfo.instance.deviceBrand(), '');
        expect(await BiliPlatformInfo.instance.deviceModel(), '');
      }
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}

BiliDashStream audio(int id, String codec) => BiliDashStream(
  id: id,
  baseUrl: 'https://example.test/$id',
  mimeType: 'audio/mp4',
  codecs: codec,
  bandwidth: 192000,
  segmentInfo: const BiliDashSegmentInfo(
    initialization: '0-10',
    indexRange: '11-20',
  ),
);
