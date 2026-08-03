import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vesper_media/bili/common/services/bili_endpoints.dart';
import 'package:vesper_media/bili/common/services/bili_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// 定向测试：锁定 `_buildBiliHeaders` 的外部 wire 契约。
///
/// 关键原则：期望值一律用**外部字面量**，绝不引用生产常量。这样当集中
/// 常量出现域名拼写错误、尾斜杠丢失、字段遗漏或多余字段时，测试才会
/// 真正失败。媒体侧断言完整 map（精确字段集合）；API 侧断言契约字段
/// 与隔离边界。Cookie 三态 + 空值协议清理也被覆盖。
void main() {
  group('BiliTransport.buildBiliMediaSourceHeaders', () {
    test('emits the exact media header contract (no Sec-Fetch, no Cookie)', () {
      final transport = BiliTransport();
      addTearDown(() => transport.httpClient.close(force: true));

      // 期望值用外部字面量，不引用 biliMediaReferer / biliUserAgent：
      // 这样常量回归（域名错、尾斜杠丢、UA 漂移）能被本断言挡住。
      expect(transport.buildBiliMediaSourceHeaders(), {
        'accept': '*/*',
        'user-agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/136.0.0.0 Safari/537.36',
        'referer': 'https://www.bilibili.com',
        'Origin': 'https://www.bilibili.com',
        'accept-language': 'zh-CN,zh;q=0.9',
      });
    });

    test('omits Cookie header when no session is present', () {
      final transport = BiliTransport();
      addTearDown(() => transport.httpClient.close(force: true));

      expect(
        transport.buildBiliMediaSourceHeaders().containsKey(
          HttpHeaders.cookieHeader,
        ),
        isFalse,
      );
    });

    test(
      'omits Cookie header even when an authenticated session is present',
      () {
        // 媒体 URL 在 playurl 解析时已带会话签名，CDN 凭 URL 鉴权，无需 Cookie。
        // 向第三方 CDN（Akamai、PCDN 等）发送 SESSDATA/bili_jct 会扩大会话令牌
        // 暴露面，因此媒体路径即使已登录也绝不携带 Cookie。
        final transport = BiliTransport()
          ..setCookie('SESSDATA', 'session-token')
          ..setCookie('bili_jct', 'csrf-token');
        addTearDown(() => transport.httpClient.close(force: true));

        expect(
          transport.buildBiliMediaSourceHeaders().containsKey(
            HttpHeaders.cookieHeader,
          ),
          isFalse,
        );
      },
    );

    test('omits Cookie header when session holds only empty values '
        '(protocol cleanup: serialization-based gating)', () {
      // 持久化层（bili_session_store）可恢复空串值。旧 API 路径只要
      // map 非空就写 Cookie（会发出 `SESSDATA=` 畸形头）；现在统一由
      // buildCookieHeader 过滤空值后决定，序列化为空则省略头。
      final transport = BiliTransport()..setCookie('SESSDATA', '');
      addTearDown(() => transport.httpClient.close(force: true));

      expect(
        transport.buildBiliMediaSourceHeaders().containsKey(
          HttpHeaders.cookieHeader,
        ),
        isFalse,
      );
    });
  });

  group('BiliTransport.sendRequest header contract', () {
    test(
      'API path carries Sec-Fetch-* and omits explicit User-Agent',
      () async {
        final stub = _HeaderCapturingHttpClient();
        final transport = BiliTransport(httpClient: stub);

        await transport.sendRequest(
          Uri.https(biliApiHost, BiliApiPaths.nav),
          referer: biliDefaultReferer,
        );

        final captured = stub.lastRequest!.capturedHeaders;

        // API 路径必须携带 Sec-Fetch-*（外部契约字面量作期望值）。
        expect(captured['Sec-Fetch-Dest'], <String>['empty']);
        expect(captured['Sec-Fetch-Mode'], <String>['cors']);
        expect(captured['Sec-Fetch-Site'], <String>['same-site']);

        // API 路径不显式写 User-Agent（依赖 HttpClient 全局 UA）。
        expect(captured.containsKey(HttpHeaders.userAgentHeader), isFalse);
      },
    );

    test('API path never leaks Cookie when includeCookies is false', () async {
      final stub = _HeaderCapturingHttpClient();
      final transport = BiliTransport(httpClient: stub)
        ..setCookie('SESSDATA', 'session-token');

      await transport.sendRequest(
        Uri.https(biliApiHost, BiliApiPaths.nav),
        referer: biliDefaultReferer,
        includeCookies: false,
      );

      // 即使已登录，includeCookies=false 也绝不产生 Cookie 头。
      expect(
        stub.lastRequest!.capturedHeaders.containsKey(HttpHeaders.cookieHeader),
        isFalse,
      );
    });

    test(
      'API path emits Cookie when session present and includeCookies true',
      () async {
        final stub = _HeaderCapturingHttpClient();
        final transport = BiliTransport(httpClient: stub)
          ..setCookie('SESSDATA', 'session-token');

        await transport.sendRequest(
          Uri.https(biliApiHost, BiliApiPaths.nav),
          referer: biliDefaultReferer,
        );

        expect(
          stub.lastRequest!.capturedHeaders.containsKey(
            HttpHeaders.cookieHeader,
          ),
          isTrue,
        );
      },
    );

    test('API path omits Cookie when session holds only empty values '
        '(protocol cleanup)', () async {
      final stub = _HeaderCapturingHttpClient();
      final transport = BiliTransport(httpClient: stub)
        ..setCookie('SESSDATA', '');

      await transport.sendRequest(
        Uri.https(biliApiHost, BiliApiPaths.nav),
        referer: biliDefaultReferer,
      );

      // 旧 API 路径行为：map 非空即写头 -> 会发出 Cookie: SESSDATA=
      // 新行为：序列化为空 -> 省略头。锁定新行为。
      expect(
        stub.lastRequest!.capturedHeaders.containsKey(HttpHeaders.cookieHeader),
        isFalse,
      );
    });
  });
}

/// 一个最小 HttpClient 桩：仅捕获最终写入 request 的 header 集合，
/// 然后立即返回一个空 200 JSON 响应。不发起任何真实网络 IO。
final class _HeaderCapturingHttpClient implements HttpClient {
  _HeaderCapturingHttpClientRequest? lastRequest;

  // BiliTransport 构造器会设置全局 UA 与超时；桩无需生效，静默吞掉即可。
  @override
  set userAgent(String? value) {}

  @override
  set connectionTimeout(Duration? value) {}

  @override
  set idleTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    lastRequest = _HeaderCapturingHttpClientRequest();
    return lastRequest!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('_HeaderCapturingHttpClient only supports getUrl');
}

final class _HeaderCapturingHttpClientRequest implements HttpClientRequest {
  final Map<String, List<String>> _store = <String, List<String>>{};
  late final _CapturingHeaders _headers = _CapturingHeaders(_store);

  Map<String, List<String>> get capturedHeaders => _store;

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _EmptyResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('_HeaderCapturingHttpClientRequest: $invocation');
}

final class _CapturingHeaders implements HttpHeaders {
  _CapturingHeaders(this._store);

  final Map<String, List<String>> _store;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _store[name] = <String>[value.toString()];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('_CapturingHeaders only supports set');
}

final class _EmptyResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => 0;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  HttpHeaders get headers => _CapturingHeaders(<String, List<String>>{});

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    // 返回一个空 JSON 对象体，满足 sendRequest 内的 utf8.decodeStream。
    return Stream<List<int>>.fromIterable(<List<int>>[
      utf8.encode(jsonEncode(<String, Object?>{'code': 0})),
    ]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('_EmptyResponse only supports listen/statusCode');
}
