import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaExternalPlaybackManager', () {
    const channel = MethodChannel(
      'dev.ikaros.vesper_player_test/external_playback',
    );
    const routesChannel = EventChannel(
      'dev.ikaros.vesper_player_test/external_playback/routes',
    );
    const eventsChannel = EventChannel(
      'dev.ikaros.vesper_player_test/external_playback/events',
    );
    late _ExternalPlaybackHarness externalPlayback;
    late MediaExternalPlaybackManager manager;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      externalPlayback = _ExternalPlaybackHarness(
        methodChannel: channel,
        routesChannel: routesChannel,
        eventsChannel: eventsChannel,
      )..install();
      manager = MediaExternalPlaybackManager(
        detail: _detail,
        formatAdaptation: mediaDlnaFormatAdaptationConfig,
        dlnaController: VesperExternalPlaybackController(
          methodChannel: channel,
          routesEventChannel: routesChannel,
          sessionEventChannel: eventsChannel,
        ),
      );
    });

    tearDown(() {
      manager.dispose();
      externalPlayback.uninstall();
      debugDefaultTargetPlatformOverride = null;
    });

    test('initializes in idle state', () {
      expect(manager.state, MediaDlnaState.idle);
    });

    test('initializes with empty routes', () {
      expect(manager.routes, isEmpty);
    });

    test('initializes with null message', () {
      expect(manager.message, isNull);
    });

    test(
      'transfers position and resumes from the remote position on disconnect',
      () async {
        final player = _LocalPlayer();
        await _connectToRoute(manager, externalPlayback);
        expect(
          await manager.loadMedia(
            resolved: _resolvedPlayback,
            controller: player,
          ),
          isNull,
        );

        final load = externalPlayback.calls.singleWhere(
          (call) => call.method == 'load',
        );
        expect((load.arguments as Map)['startPositionMs'], 45000);
        expect((load.arguments as Map)['autoplay'], isTrue);
        expect(player.pauseCalls, 1);
        externalPlayback.emitEvent(<String, Object?>{
          'kind': 'playing',
          'routeId': 'uuid:tv',
          'positionMs': 72000,
        });
        await Future<void>.delayed(Duration.zero);
        await manager.disconnect();
        expect(player.seekDeltas, <int>[27000]);
        expect(player.playCalls, 1);
      },
    );

    test('paused playback remains paused on both devices', () async {
      final player = _LocalPlayer(playing: false);
      await _connectToRoute(manager, externalPlayback);
      await manager.loadMedia(resolved: _resolvedPlayback, controller: player);
      final load = externalPlayback.calls.singleWhere(
        (call) => call.method == 'load',
      );
      expect((load.arguments as Map)['autoplay'], isFalse);
      await manager.disconnect();
      expect(player.pauseCalls, 0);
      expect(player.playCalls, 0);
    });

    test(
      'reloading the same cast retains remote position and resume intent',
      () async {
        final player = _LocalPlayer();
        await _connectToRoute(manager, externalPlayback);
        await manager.loadMedia(
          resolved: _resolvedPlayback,
          controller: player,
        );
        externalPlayback.emitEvent(<String, Object?>{
          'kind': 'playing',
          'routeId': 'uuid:tv',
          'positionMs': 72000,
        });
        await Future<void>.delayed(Duration.zero);
        await manager.loadMedia(
          resolved: _refreshedPlayback,
          controller: player,
        );
        final load = externalPlayback.calls.lastWhere(
          (call) => call.method == 'load',
        );
        expect((load.arguments as Map)['startPositionMs'], 72000);
        expect((load.arguments as Map)['autoplay'], isTrue);
        expect(player.pauseCalls, 1);
        await manager.disconnect();
        expect(player.playCalls, 1);
      },
    );

    test(
      'remote pause is preserved when returning to local playback',
      () async {
        final player = _LocalPlayer();
        await _connectToRoute(manager, externalPlayback);
        await manager.loadMedia(
          resolved: _resolvedPlayback,
          controller: player,
        );
        externalPlayback.emitEvent(<String, Object?>{
          'kind': 'paused',
          'routeId': 'uuid:tv',
          'positionMs': 72000,
        });
        await Future<void>.delayed(Duration.zero);
        await manager.disconnect();
        expect(player.seekDeltas, <int>[27000]);
        expect(player.playCalls, 0);
      },
    );

    test(
      'route disconnect during explicit disconnect restores local playback once',
      () async {
        final player = _LocalPlayer();
        await _connectToRoute(manager, externalPlayback);
        await manager.loadMedia(
          resolved: _resolvedPlayback,
          controller: player,
        );
        externalPlayback.disconnectHandler = () async {
          externalPlayback.emitEvent(<String, Object?>{
            'kind': 'routeDisconnected',
            'routeId': 'uuid:tv',
            'positionMs': 72000,
          });
          await Future<void>.delayed(Duration.zero);
        };
        await manager.disconnect();
        expect(player.seekDeltas, <int>[27000]);
        expect(player.playCalls, 1);
      },
    );

    test(
      'a new route invalidates restoration waiting for an old local pause',
      () async {
        final player = _LocalPlayer()..pauseGate = Completer<void>();
        await _connectToRoute(manager, externalPlayback);
        final load = manager.loadMedia(
          resolved: _resolvedPlayback,
          controller: player,
        );
        await Future<void>.delayed(Duration.zero);
        externalPlayback.emitEvent(<String, Object?>{
          'kind': 'routeDisconnected',
          'routeId': 'uuid:tv',
        });
        await Future<void>.delayed(Duration.zero);
        externalPlayback.emitEvent(<String, Object?>{
          'kind': 'routeConnected',
          'routeId': 'uuid:new-tv',
        });
        await Future<void>.delayed(Duration.zero);
        player.pauseGate!.complete();
        await load;
        await Future<void>.delayed(Duration.zero);
        expect(player.playCalls, 0);
        expect(manager.state, MediaDlnaState.connected);
      },
    );

    test('failed remote load leaves local playback running', () async {
      final player = _LocalPlayer();
      externalPlayback.loadResult = <String, Object?>{'status': 'failed'};
      await _connectToRoute(manager, externalPlayback);
      expect(
        await manager.loadMedia(
          resolved: _resolvedPlayback,
          controller: player,
        ),
        isNotNull,
      );
      expect(player.pauseCalls, 0);
      expect(player.playCalls, 0);
    });

    test(
      'late load completion after disconnect does not pause local playback',
      () async {
        final player = _LocalPlayer();
        final gate = Completer<Map<String, Object?>>();
        externalPlayback.loadHandler = () => gate.future;
        await _connectToRoute(manager, externalPlayback);
        final load = manager.loadMedia(
          resolved: _resolvedPlayback,
          controller: player,
        );
        await Future<void>.delayed(Duration.zero);
        await manager.disconnect();
        gate.complete(<String, Object?>{'status': 'success'});
        await load;
        expect(player.pauseCalls, 0);
        expect(manager.state, MediaDlnaState.idle);
      },
    );

    test('disconnect waits for the local pause before resuming', () async {
      final player = _LocalPlayer()..pauseGate = Completer<void>();
      await _connectToRoute(manager, externalPlayback);
      final load = manager.loadMedia(
        resolved: _resolvedPlayback,
        controller: player,
      );
      await Future<void>.delayed(Duration.zero);
      final disconnect = manager.disconnect();
      await Future<void>.delayed(Duration.zero);
      expect(player.playCalls, 0);
      player.pauseGate!.complete();
      await load;
      await disconnect;
      expect(player.playCalls, 1);
    });

    test(
      'disconnect does not resume a replaced source or controller',
      () async {
        final player = _LocalPlayer();
        var current = true;
        await _connectToRoute(manager, externalPlayback);
        await manager.loadMedia(
          resolved: _resolvedPlayback,
          controller: player,
          isCurrentPlayback: () => current,
        );
        current = false;
        externalPlayback.emitEvent(<String, Object?>{
          'kind': 'routeDisconnected',
          'routeId': 'uuid:tv',
          'positionMs': 72000,
        });
        await Future<void>.delayed(Duration.zero);
        expect(player.seekDeltas, isEmpty);
        expect(player.playCalls, 0);
      },
    );

    test('builds system playback metadata with resolved data', () {
      final resolved = ResolvedMediaPlayback(
        title: '测试视频',
        subtitle: 'P1 · 正片',
        uri: 'https://example.com/video.mpd',
        protocol: VesperPlayerSourceProtocol.dash,
        transportLabel: 'test',
        isLocalFile: false,
      );

      final metadata = manager.buildSystemPlaybackMetadata(
        resolved,
        const MediaPlaybackEntry(
          entryId: '11',
          pageNumber: 1,
          title: '正片',
          durationSeconds: 120,
        ),
      );

      expect(metadata.title, contains('测试视频'));
      expect(metadata.artist, '测试UP');
      expect(metadata.durationMs, 120000);
    });

    test('load failure disconnects DLNA and keeps error state', () async {
      externalPlayback.loadResult = <String, Object?>{
        'status': 'unsupported',
        'message':
            'Host-prepared relay remux v1 only accepts remote HTTP(S) DASH sources.',
      };

      await _connectToRoute(manager, externalPlayback);

      final message = await manager.loadMedia(resolved: _resolvedPlayback);

      expect(
        message,
        'Host-prepared relay remux v1 only accepts remote HTTP(S) DASH sources.',
      );
      expect(manager.state, MediaDlnaState.error);
      expect(manager.message, message);
      expect(
        externalPlayback.calls.map((call) => call.method),
        contains('disconnect'),
      );
    });

    test(
      'refreshes resolved playback and retries transient DASH sidx failure',
      () async {
        externalPlayback.loadResults = <Map<String, Object?>>[
          <String, Object?>{
            'status': 'unsupported',
            'message':
                'Failed to fetch DASH sidx for host-prepared relay remux.',
          },
          <String, Object?>{
            'status': 'success',
            'routeId': 'uuid:tv',
            'relayEnabled': true,
          },
        ];

        await _connectToRoute(manager, externalPlayback);

        var refreshCount = 0;
        final message = await manager.loadMedia(
          resolved: _resolvedPlayback,
          refreshResolved: () async {
            refreshCount += 1;
            return _refreshedPlayback;
          },
        );

        expect(message, isNull);
        expect(refreshCount, 1);
        expect(manager.state, MediaDlnaState.connected);
        expect(manager.message, '已投放到 DLNA 设备');
        expect(
          externalPlayback.calls.where((call) => call.method == 'load'),
          hasLength(2),
        );
        expect(externalPlayback.loadedUris, <String>[
          'https://example.com/video.mpd',
          'https://example.com/refreshed.mpd',
        ]);
        expect(
          externalPlayback.calls.map((call) => call.method),
          isNot(contains('disconnect')),
        );
      },
    );

    test(
      'disconnects after retryable DASH load failure is retried once',
      () async {
        externalPlayback.loadResults = <Map<String, Object?>>[
          <String, Object?>{
            'status': 'unsupported',
            'message':
                'Failed to fetch DASH sidx for host-prepared relay remux.',
          },
          <String, Object?>{
            'status': 'unsupported',
            'message':
                'Failed to fetch DASH sidx for host-prepared relay remux.',
          },
        ];

        await _connectToRoute(manager, externalPlayback);

        final message = await manager.loadMedia(
          resolved: _resolvedPlayback,
          refreshResolved: () async => _refreshedPlayback,
        );

        expect(
          message,
          'Failed to fetch DASH sidx for host-prepared relay remux.',
        );
        expect(manager.state, MediaDlnaState.error);
        expect(
          externalPlayback.calls.where((call) => call.method == 'load'),
          hasLength(2),
        );
        expect(
          externalPlayback.calls.map((call) => call.method),
          contains('disconnect'),
        );
      },
    );

    test(
      'holds retryable load diagnostic until retry result is known',
      () async {
        externalPlayback.loadHandler = () async {
          if (externalPlayback.loadCallCount == 1) {
            externalPlayback.emitEvent(<String, Object?>{
              'kind': 'discoveryDiagnostic',
              'routeId': 'uuid:tv',
              'routeName': 'Living Room TV',
              'message':
                  'Failed to fetch DASH sidx for host-prepared relay remux.',
              'code': 'host_fetch_failed',
              'details': <String, Object?>{
                'severity': 'warning',
                'inputMode': 'host_prepared_dash_fmp4_tracks',
              },
            });
            await Future<void>.delayed(Duration.zero);
            return <String, Object?>{
              'status': 'unsupported',
              'message': 'Failed to prepare DASH input for relay remux.',
            };
          }
          return <String, Object?>{
            'status': 'success',
            'routeId': 'uuid:tv',
            'relayEnabled': true,
          };
        };

        await _connectToRoute(manager, externalPlayback);

        final message = await manager.loadMedia(
          resolved: _resolvedPlayback,
          refreshResolved: () async => _refreshedPlayback,
        );

        expect(message, isNull);
        expect(manager.state, MediaDlnaState.connected);
        expect(
          externalPlayback.calls.where((call) => call.method == 'load'),
          hasLength(2),
        );
        expect(
          externalPlayback.calls.map((call) => call.method),
          isNot(contains('disconnect')),
        );
      },
    );

    test('relay warning diagnostic disconnects connected DLNA route', () async {
      await _connectToRoute(manager, externalPlayback);

      externalPlayback.emitEvent(<String, Object?>{
        'kind': 'discoveryDiagnostic',
        'routeId': 'uuid:tv',
        'routeName': 'Living Room TV',
        'message':
            'Host-prepared relay remux v1 only accepts remote HTTP(S) DASH sources.',
        'code': 'unsupported_dash_layout',
        'details': <String, Object?>{
          'severity': 'warning',
          'inputMode': 'host-prepared-dash-v1',
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(manager.state, MediaDlnaState.error);
      expect(
        manager.message,
        'Host-prepared relay remux v1 only accepts remote HTTP(S) DASH sources.',
      );
      expect(
        externalPlayback.calls.map((call) => call.method),
        contains('disconnect'),
      );
    });

    test(
      'mixed DASH origin diagnostic disconnects connected DLNA route',
      () async {
        await _connectToRoute(manager, externalPlayback);

        externalPlayback.emitEvent(<String, Object?>{
          'kind': 'discoveryDiagnostic',
          'routeId': 'uuid:tv',
          'routeName': 'Living Room TV',
          'message':
              'DASH references must stay within the source origin for relay remux.',
          'code': 'unsupported_mixed_dash_origin',
          'details': <String, Object?>{
            'severity': 'error',
            'inputMode': 'host_prepared_dash_fmp4_tracks',
            'sourceOrigin': 'remote',
          },
        });
        await Future<void>.delayed(Duration.zero);

        expect(manager.state, MediaDlnaState.error);
        expect(
          manager.message,
          'DASH references must stay within the source origin for relay remux.',
        );
        expect(
          externalPlayback.calls.map((call) => call.method),
          contains('disconnect'),
        );
      },
    );

    test('DLNA error event disconnects connected route', () async {
      await _connectToRoute(manager, externalPlayback);

      externalPlayback.emitEvent(<String, Object?>{
        'kind': 'error',
        'routeId': 'uuid:tv',
        'routeName': 'Living Room TV',
        'message': 'DLNA playback failed.',
      });
      await Future<void>.delayed(Duration.zero);

      expect(manager.state, MediaDlnaState.error);
      expect(manager.message, 'DLNA playback failed.');
      expect(
        externalPlayback.calls.map((call) => call.method),
        contains('disconnect'),
      );
    });
  });
}

const _detail = MediaDetail(
  mediaId: 'BV1xx411c7mD',
  title: '测试视频',
  coverUrl: '',
  ownerName: '测试UP',
  pages: <MediaPlaybackEntry>[
    MediaPlaybackEntry(
      entryId: '11',
      pageNumber: 1,
      title: '正片',
      durationSeconds: 120,
    ),
  ],
);

final _resolvedPlayback = ResolvedMediaPlayback(
  title: '测试视频',
  subtitle: 'P1 · 正片',
  uri: 'https://example.com/video.mpd',
  protocol: VesperPlayerSourceProtocol.dash,
  transportLabel: 'test',
  isLocalFile: false,
);

final _refreshedPlayback = ResolvedMediaPlayback(
  title: '测试视频',
  subtitle: 'P1 · 正片',
  uri: 'https://example.com/refreshed.mpd',
  protocol: VesperPlayerSourceProtocol.dash,
  transportLabel: 'test refreshed',
  isLocalFile: false,
);

Future<void> _connectToRoute(
  MediaExternalPlaybackManager manager,
  _ExternalPlaybackHarness externalPlayback,
) async {
  await manager.startDiscovery();
  await Future<void>.delayed(Duration.zero);
  externalPlayback.emitRoutes(<Object?>[
    <String, Object?>{
      'routeId': 'uuid:tv',
      'name': 'Living Room TV',
      'kind': 'dlna',
    },
  ]);
  await Future<void>.delayed(Duration.zero);

  final error = await manager.connect('uuid:tv');
  expect(error, isNull);
  expect(manager.state, MediaDlnaState.connected);
}

final class _LocalPlayer implements VesperPlayerController {
  _LocalPlayer({bool playing = true})
    : snapshot = const VesperPlayerSnapshot.initial().copyWith(
        playbackState: playing
            ? VesperPlaybackState.playing
            : VesperPlaybackState.paused,
        timeline: VesperTimeline(
          kind: VesperTimelineKind.vod,
          isSeekable: true,
          seekableRange: null,
          liveEdgeMs: null,
          positionMs: 45000,
          durationMs: 120000,
        ),
      );

  @override
  VesperPlayerSnapshot snapshot;
  int pauseCalls = 0;
  int playCalls = 0;
  final seekDeltas = <int>[];
  Completer<void>? pauseGate;

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    await pauseGate?.future;
    snapshot = snapshot.copyWith(playbackState: VesperPlaybackState.paused);
  }

  @override
  Future<void> play() async {
    playCalls += 1;
  }

  @override
  Future<void> seekBy(int deltaMs) async {
    seekDeltas.add(deltaMs);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ExternalPlaybackHarness {
  _ExternalPlaybackHarness({
    required this.methodChannel,
    required this.routesChannel,
    required this.eventsChannel,
  });

  final MethodChannel methodChannel;
  final EventChannel routesChannel;
  final EventChannel eventsChannel;
  final calls = <MethodCall>[];
  final loadedUris = <String>[];
  late dynamic _routesSink;
  late dynamic _eventsSink;
  Map<String, Object?> loadResult = const <String, Object?>{
    'status': 'success',
    'routeId': 'uuid:tv',
    'relayEnabled': true,
  };
  List<Map<String, Object?>>? loadResults;
  Future<Map<String, Object?>> Function()? loadHandler;
  Future<void> Function()? disconnectHandler;
  int loadCallCount = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'startDiscovery':
            case 'stopDiscovery':
              return null;
            case 'connect':
              return <String, Object?>{
                'status': 'success',
                'routeId': 'uuid:tv',
              };
            case 'load':
              loadCallCount += 1;
              loadedUris.add(_sourceUriFromLoadCall(call));
              final handler = loadHandler;
              if (handler != null) {
                return handler();
              }
              final queuedResults = loadResults;
              if (queuedResults != null && queuedResults.isNotEmpty) {
                return queuedResults.removeAt(0);
              }
              return loadResult;
            case 'disconnect':
              await disconnectHandler?.call();
              return <String, Object?>{'status': 'success'};
          }
          return <String, Object?>{
            'status': 'failed',
            'message': 'Unexpected method ${call.method}',
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          routesChannel,
          MockStreamHandler.inline(
            onListen: (_, events) {
              _routesSink = events;
            },
          ),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          eventsChannel,
          MockStreamHandler.inline(
            onListen: (_, events) {
              _eventsSink = events;
            },
          ),
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(routesChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventsChannel, null);
  }

  void emitRoutes(Object? routes) {
    _routesSink.success(routes);
  }

  void emitEvent(Object? event) {
    _eventsSink.success(event);
  }

  String _sourceUriFromLoadCall(MethodCall call) {
    final arguments = call.arguments;
    if (arguments is! Map) {
      return '';
    }
    final item = arguments['item'];
    if (item is! Map) {
      return '';
    }
    final sources = item['sources'];
    if (sources is! List || sources.isEmpty) {
      return '';
    }
    final firstSource = sources.first;
    if (firstSource is! Map) {
      return '';
    }
    return firstSource['uri'] as String? ?? '';
  }
}
