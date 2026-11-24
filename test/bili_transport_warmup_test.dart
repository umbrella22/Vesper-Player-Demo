import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/services/bili_endpoints.dart';
import 'package:vesper_media/bili/common/services/bili_transport.dart';

void main() {
  test(
    'warmup and foreground requests share one ordered preparation',
    () async {
      final transport = _WarmupTransport();
      addTearDown(() => transport.httpClient.close(force: true));
      final prime = transport.primeGate = Completer<void>();
      final warmup = transport.ensureReady();
      final second = transport.ensureReady();
      final request = transport.getData(
        host: biliApiHost,
        path: '/foreground',
        useWbi: true,
      );
      expect(transport.paths, ['/']);
      prime.complete();
      await Future.wait<Object?>([warmup, second, request]);
      expect(transport.paths, [
        '/',
        BiliApiPaths.frontendFingerSpi,
        BiliApiPaths.nav,
        '/foreground',
      ]);
      await transport.ensureReady();
      expect(transport.paths, hasLength(4));
    },
  );

  test('late visitor identity cannot replace a restored session', () async {
    final transport = _WarmupTransport();
    addTearDown(() => transport.httpClient.close(force: true));
    final finger = transport.fingerGate = Completer<void>();
    final old = transport.ensureReady();
    await pumpEventQueue();
    transport.restoreCookies({
      'buvid3': 'new-3',
      'buvid4': 'new-4',
      'SESSDATA': 'session',
    });
    finger.complete();
    await old;
    expect(transport.cookieValue('buvid3'), 'new-3');
    expect(transport.cookieValue('buvid4'), 'new-4');
    expect(transport.paths, ['/', BiliApiPaths.frontendFingerSpi]);
    await transport.ensureReady();
    expect(transport.paths.last, BiliApiPaths.nav);
  });

  test(
    'WBI request concurrent with restoreCookies completes ready checks and succeeds',
    () async {
      final transport = _WarmupTransport();
      addTearDown(() => transport.httpClient.close(force: true));
      final finger = transport.fingerGate = Completer<void>();
      final wbiRequest = transport.getData(
        host: biliApiHost,
        path: '/foreground',
        useWbi: true,
      );
      await pumpEventQueue();
      transport.restoreCookies({
        'buvid3': 'new-3',
        'buvid4': 'new-4',
        'SESSDATA': 'session',
      });
      finger.complete();
      await wbiRequest;
      expect(transport.paths.last, '/foreground');
    },
  );

  test('empty nav wbi_img does not poison WBI keys', () async {
    final transport = _WarmupTransport()..omitWbiOnce = true;
    addTearDown(() => transport.httpClient.close(force: true));
    transport.restoreCookies({'buvid3': 'b3', 'buvid4': 'b4'});
    await transport.ensureReady();
    expect(transport.imgKey, isNull);
    expect(transport.subKey, isNull);
    await transport.ensureReady();
    expect(transport.imgKey, isNotEmpty);
    expect(transport.subKey, isNotEmpty);
  });
}

class _WarmupTransport extends BiliTransport {
  final paths = <String>[];
  Completer<void>? primeGate;
  Completer<void>? fingerGate;
  bool omitWbiOnce = false;
  @override
  Future<BiliHttpResponse> sendRequest(
    Uri uri, {
    required String referer,
    String method = 'GET',
    String? requestBody,
    String acceptHeader = 'application/json, */*',
    bool includeCookies = true,
    bool storeResponseCookies = true,
  }) async {
    paths.add(uri.path);
    Map<String, Object?> data = {};
    if (uri.path == '/') {
      await primeGate?.future;
      setCookie('visitor', 'test');
    } else if (uri.path == BiliApiPaths.frontendFingerSpi) {
      await fingerGate?.future;
      data = {'b_3': 'old-3', 'b_4': 'old-4'};
    } else if (uri.path == BiliApiPaths.nav) {
      if (omitWbiOnce) {
        omitWbiOnce = false;
        data = {'isLogin': false};
      } else {
        data = {
          'wbi_img': {
            'img_url':
                'https://example.test/abcdefghijklmnopqrstuvwxyz123456.png',
            'sub_url':
                'https://example.test/abcdefghijklmnopqrstuvwxyz654321.png',
          },
        };
      }
    }
    return BiliHttpResponse(
      statusCode: 200,
      bodyBytes: utf8.encode(jsonEncode({'code': 0, 'data': data})),
      cookieUpdates: const {},
    );
  }
}
