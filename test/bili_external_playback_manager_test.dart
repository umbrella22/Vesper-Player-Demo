import 'package:bilibili_player/bili/common/models/bili_models.dart';
import 'package:bilibili_player/bili/common/view_models/bili_external_playback_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_player/vesper_player.dart';
import 'package:vesper_player_external_playback/vesper_player_external_playback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiliExternalPlaybackManager', () {
    const channel = MethodChannel(
      'dev.ikaros.bilibili_player_test/external_playback',
    );
    const routesChannel = EventChannel(
      'dev.ikaros.bilibili_player_test/external_playback/routes',
    );
    const eventsChannel = EventChannel(
      'dev.ikaros.bilibili_player_test/external_playback/events',
    );
    late _ExternalPlaybackHarness externalPlayback;
    late BiliExternalPlaybackManager manager;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      externalPlayback = _ExternalPlaybackHarness(
        methodChannel: channel,
        routesChannel: routesChannel,
        eventsChannel: eventsChannel,
      )..install();
      manager = BiliExternalPlaybackManager(
        detail: _detail,
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
      expect(manager.state, BiliDlnaState.idle);
    });

    test('initializes with empty routes', () {
      expect(manager.routes, isEmpty);
    });

    test('initializes with null message', () {
      expect(manager.message, isNull);
    });

    test('builds system playback metadata with resolved data', () {
      final resolved = BiliResolvedPlayback(
        bvid: 'BV1xx411c7mD',
        cid: 11,
        title: '测试视频',
        subtitle: 'P1 · 正片',
        uri: 'https://example.com/video.mpd',
        protocol: VesperPlayerSourceProtocol.dash,
        transportLabel: 'test',
        isLocalFile: false,
      );

      final metadata = manager.buildSystemPlaybackMetadata(
        resolved,
        const BiliVideoPageEntry(
          cid: 11,
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
      expect(manager.state, BiliDlnaState.error);
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
        expect(manager.state, BiliDlnaState.connected);
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
        expect(manager.state, BiliDlnaState.error);
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
        expect(manager.state, BiliDlnaState.connected);
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

      expect(manager.state, BiliDlnaState.error);
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

        expect(manager.state, BiliDlnaState.error);
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

      expect(manager.state, BiliDlnaState.error);
      expect(manager.message, 'DLNA playback failed.');
      expect(
        externalPlayback.calls.map((call) => call.method),
        contains('disconnect'),
      );
    });
  });
}

const _detail = BiliVideoDetail(
  aid: 1,
  bvid: 'BV1xx411c7mD',
  title: '测试视频',
  ownerMid: 2,
  ownerName: '测试UP',
  ownerAvatarUrl: '',
  coverUrl: '',
  description: '',
  publishedAtLabel: null,
  playCountLabel: '100',
  danmakuCountLabel: '10',
  replyCountLabel: '5',
  likeCountLabel: '20',
  coinCountLabel: '3',
  favoriteCountLabel: '8',
  shareCountLabel: '2',
  pages: <BiliVideoPageEntry>[
    BiliVideoPageEntry(
      cid: 11,
      pageNumber: 1,
      title: '正片',
      durationSeconds: 120,
    ),
  ],
);

final _resolvedPlayback = BiliResolvedPlayback(
  bvid: 'BV1xx411c7mD',
  cid: 11,
  title: '测试视频',
  subtitle: 'P1 · 正片',
  uri: 'https://example.com/video.mpd',
  protocol: VesperPlayerSourceProtocol.dash,
  transportLabel: 'test',
  isLocalFile: false,
);

final _refreshedPlayback = BiliResolvedPlayback(
  bvid: 'BV1xx411c7mD',
  cid: 11,
  title: '测试视频',
  subtitle: 'P1 · 正片',
  uri: 'https://example.com/refreshed.mpd',
  protocol: VesperPlayerSourceProtocol.dash,
  transportLabel: 'test refreshed',
  isLocalFile: false,
);

Future<void> _connectToRoute(
  BiliExternalPlaybackManager manager,
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
  expect(manager.state, BiliDlnaState.connected);
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
