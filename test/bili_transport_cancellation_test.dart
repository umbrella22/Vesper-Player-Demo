import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_transport.dart';

void main() {
  final uri = Uri.https('api.bilibili.com', '/x/test');

  Future<BiliHttpResponse> send(BiliTransport transport) =>
      transport.sendRequest(uri, referer: 'https://www.bilibili.com/');

  testWidgets('complete responses settle in the caller scheduling zone', (
    tester,
  ) async {
    final request = _Request()
      ..response.complete(
        _Response(
          Stream.value(utf8.encode('complete')),
          cookies: [Cookie('SESSDATA', 'accepted')],
        ),
      );
    final transport = _transport(request);
    BiliHttpResponse? response;
    unawaited(send(transport).then((value) => response = value));

    await tester.pump();

    expect(response?.body, 'complete');
    expect(transport.cookieValue('SESSDATA'), 'accepted');
  });

  for (final sendHeaders in [false, true]) {
    test(
      'timeout closes a real socket while waiting for ${sendHeaders ? 'body' : 'headers'}',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <Socket>[];
        addTearDown(() async {
          for (final socket in sockets) {
            socket.destroy();
          }
          await server.close();
        });
        final disconnected = Completer<void>();
        server.listen((socket) {
          sockets.add(socket);
          var started = false;
          socket.listen(
            (_) {
              if (sendHeaders && !started) {
                started = true;
                socket.write(
                  'HTTP/1.1 200 OK\r\nContent-Length: 10000\r\n\r\nx',
                );
              }
            },
            onDone: disconnected.complete,
            onError: disconnected.completeError,
          );
        });
        final transport = HttpOverrides.runWithHttpOverrides(
          () =>
              BiliTransport(requestTimeout: const Duration(milliseconds: 150)),
          _RealHttpOverrides(),
        );
        addTearDown(() => transport.httpClient.close(force: true));

        await expectLater(
          transport.sendRequest(
            Uri.parse('http://${server.address.address}:${server.port}/'),
            referer: 'https://www.bilibili.com/',
          ),
          throwsA(isA<BiliApiException>()),
        );
        await disconnected.future.timeout(const Duration(seconds: 2));
      },
    );
  }

  test('timeout aborts a request still waiting for response headers', () async {
    final request = _Request();
    final transport = _transport(request);

    await expectLater(
      send(transport),
      throwsA(
        isA<BiliApiException>().having(
          (e) => e.outcomeUnknown,
          'outcomeUnknown',
          isTrue,
        ),
      ),
    );

    expect(request.abortCalls, 1);
    expect(request.closeCalls, 1);
  });

  test(
    'a connection opened after timeout is aborted without sending',
    () async {
      final opened = Completer<HttpClientRequest>();
      final transport = BiliTransport(
        httpClient: _Client((_) => opened.future),
        requestTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(send(transport), throwsA(isA<BiliApiException>()));

      final request = _Request();
      opened.complete(request);
      await Future<void>.delayed(Duration.zero);

      expect(request.abortCalls, 1);
      expect(request.closeCalls, 0);
    },
  );

  test(
    'a response returned after timeout is cancelled without cookies',
    () async {
      final request = _Request(ignoreAbort: true);
      final transport = _transport(request)..setCookie('SESSDATA', 'current');
      await expectLater(send(transport), throwsA(isA<BiliApiException>()));

      final body = StreamController<List<int>>();
      final cancelled = Completer<void>();
      body.onCancel = cancelled.complete;
      request.response.complete(
        _Response(body.stream, cookies: [Cookie('SESSDATA', 'late')]),
      );
      await cancelled.future;
      await body.close();

      expect(transport.cookieValue('SESSDATA'), 'current');
    },
  );

  test(
    'timeout cancels an unfinished response body and its cookie updates',
    () async {
      final body = StreamController<List<int>>();
      final cancelled = Completer<void>();
      body.onCancel = cancelled.complete;
      final request = _Request()
        ..response.complete(
          _Response(body.stream, cookies: [Cookie('SESSDATA', 'partial')]),
        );
      final transport = _transport(request)..setCookie('SESSDATA', 'current');
      body.add(utf8.encode('{'));

      await expectLater(send(transport), throwsA(isA<BiliApiException>()));
      await cancelled.future;
      await body.close();

      expect(request.abortCalls, 1);
      expect(transport.cookieValue('SESSDATA'), 'current');
    },
  );

  test(
    'timeout does not close the shared client or abort another request',
    () async {
      final stalled = _Request();
      final successful = _Request()
        ..response.complete(_Response(Stream.value(utf8.encode('ok'))));
      var requests = 0;
      final httpClient = _Client(
        (_) async => requests++ == 0 ? stalled : successful,
      );
      final transport = BiliTransport(
        httpClient: httpClient,
        requestTimeout: const Duration(milliseconds: 20),
      );
      final timeout = expectLater(
        send(transport),
        throwsA(isA<BiliApiException>()),
      );

      expect((await send(transport)).body, 'ok');
      await timeout;
      expect(httpClient.closeCalls, 0);
      expect(successful.abortCalls, 0);
    },
  );

  test('QR cookies stay isolated until the result is accepted', () async {
    final request = _Request()
      ..response.complete(
        _Response(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'code': 0,
                'data': {
                  'code': 0,
                  'message': 'confirmed',
                  'url':
                      'https://www.bilibili.com/?SESSDATA=url-session&bili_jct=csrf',
                },
              }),
            ),
          ),
          cookies: [
            Cookie('SESSDATA', 'header-session')..domain = '.bilibili.com',
            Cookie('DedeUserID', '123')..domain = '.bilibili.com',
            Cookie('obsolete', '')..maxAge = 0,
            Cookie('untrusted', 'ignored')..domain = '.example.com',
          ],
        ),
      );
    final transport = _transport(request)
      ..restoreCookies({
        'SESSDATA': 'existing',
        'buvid3': 'visitor',
        'obsolete': 'old',
      });
    final client = BiliClient(transport: transport);

    final result = await client.pollQrLogin('ticket');

    expect(transport.snapshotCookies(), {
      'SESSDATA': 'existing',
      'buvid3': 'visitor',
      'obsolete': 'old',
    });
    client.acceptQrLogin(result);
    expect(transport.snapshotCookies(), {
      'SESSDATA': 'url-session',
      'bili_jct': 'csrf',
      'DedeUserID': '123',
      'buvid3': 'visitor',
    });
  });
}

BiliTransport _transport(_Request request) => BiliTransport(
  httpClient: _Client((_) async => request),
  requestTimeout: const Duration(milliseconds: 20),
);

final class _RealHttpOverrides extends HttpOverrides {}

final class _Client implements HttpClient {
  _Client(this.openRequest);

  final Future<HttpClientRequest> Function(Uri) openRequest;
  int closeCalls = 0;

  @override
  String? userAgent;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = Duration.zero;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openRequest(url);

  @override
  void close({bool force = false}) => closeCalls += 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Request implements HttpClientRequest {
  _Request({this.ignoreAbort = false});

  final bool ignoreAbort;
  final Completer<HttpClientResponse> response =
      Completer<HttpClientResponse>();
  int abortCalls = 0;
  int closeCalls = 0;

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> get done => response.future;

  @override
  Future<HttpClientResponse> close() {
    closeCalls += 1;
    return done;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    abortCalls += 1;
    if (!ignoreAbort && !response.isCompleted) {
      response.completeError(exception ?? const HttpException('aborted'));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.body, {this.cookies = const []});

  final Stream<List<int>> body;

  @override
  final List<Cookie> cookies;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
