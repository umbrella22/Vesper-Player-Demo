import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_endpoints.dart';
import 'package:vesper_media/bili/common/services/bili_transport.dart';
import 'package:vesper_media/danmaku/danmaku.dart';

List<int> _varint(int value) {
  final bytes = <int>[];
  var remaining = value;
  while (true) {
    final byte = remaining & 0x7F;
    remaining >>= 7;
    if (remaining == 0) {
      bytes.add(byte);
      return bytes;
    }
    bytes.add(byte | 0x80);
  }
}

List<int> _tag(int field, int wireType) => _varint(field << 3 | wireType);

List<int> _varintField(int field, int value) => <int>[
  ..._tag(field, 0),
  ..._varint(value),
];

List<int> _bytesField(int field, List<int> value) => <int>[
  ..._tag(field, 2),
  ..._varint(value.length),
  ...value,
];

void main() {
  group('BiliTransport binary response', () {
    test('聚合并原样返回非 UTF-8 字节', () async {
      final httpClient = _BytesHttpClient(<List<int>>[
        <int>[0x0A, 0x03],
        <int>[0xFF, 0x80, 0x00],
      ]);
      final transport = BiliTransport(httpClient: httpClient);
      addTearDown(() => transport.httpClient.close(force: true));

      final bytes = await transport.getBinaryData(
        host: biliApiHost,
        path: BiliApiPaths.danmakuSegWeb,
        ensureReady: false,
      );

      expect(bytes, <int>[0x0A, 0x03, 0xFF, 0x80, 0x00]);
      expect(
        httpClient.lastRequest.headers.value(HttpHeaders.acceptHeader),
        'application/octet-stream, */*',
      );
    });

    test('二进制端点返回 JSON 错误时保留 API 错误码', () async {
      final httpClient = _BytesHttpClient(<List<int>>[
        utf8.encode(
          jsonEncode(<String, Object?>{
            'code': -400,
            'message': 'bad request',
            'data': null,
          }),
        ),
      ]);
      final transport = BiliTransport(httpClient: httpClient);
      addTearDown(() => transport.httpClient.close(force: true));

      expect(
        transport.getBinaryData(
          host: biliApiHost,
          path: BiliApiPaths.danmakuSegWeb,
          ensureReady: false,
        ),
        throwsA(
          isA<BiliApiException>()
              .having((error) => error.code, 'code', -400)
              .having((error) => error.message, 'message', 'bad request'),
        ),
      );
    });
  });

  test('BiliClient 使用分段端点、WBI 和当前视频 Referer', () async {
    final transport = _RecordingBinaryTransport();
    final client = BiliClient(transport: transport);
    addTearDown(() => transport.httpClient.close(force: true));

    final result = await client.fetchDanmakuSegment(
      bvid: 'BV1TEST',
      cid: 123,
      aid: 456,
      segmentIndex: 7,
    );

    expect(result, <int>[1, 2, 3]);
    expect(transport.host, biliApiHost);
    expect(transport.path, BiliApiPaths.danmakuSegWeb);
    expect(transport.params, <String, Object?>{
      'type': 1,
      'oid': 123,
      'segment_index': 7,
      'pid': 456,
    });
    expect(transport.useWbi, isTrue);
    expect(transport.referer, biliVideoReferer('BV1TEST'));
  });

  test('BiliClient 使用 view 端点获取特殊弹幕元数据', () async {
    final transport = _RecordingBinaryTransport();
    final client = BiliClient(transport: transport);
    addTearDown(() => transport.httpClient.close(force: true));

    await client.fetchDanmakuView(bvid: 'BV1VIEW', cid: 321, aid: 654);

    expect(transport.host, biliApiHost);
    expect(transport.path, BiliApiPaths.danmakuViewWeb);
    expect(transport.params, <String, Object?>{
      'type': 1,
      'oid': 321,
      'pid': 654,
    });
    expect(transport.useWbi, isTrue);
    expect(transport.referer, biliVideoReferer('BV1VIEW'));
  });

  test('特殊弹幕资源接受公开 CDN 形态且拒绝日志不泄露 URL 参数', () async {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        logs.add(message);
      }
    };
    addTearDown(() {
      debugPrint = originalDebugPrint;
    });
    final httpClient = _BytesHttpClient(<List<int>>[
      <int>[1, 2, 3],
    ]);
    final transport = BiliTransport(httpClient: httpClient)
      ..setCookie('SESSDATA', 'session-secret');
    final client = BiliClient(transport: transport);
    addTearDown(() => transport.httpClient.close(force: true));

    const acceptedUrls = <String>[
      'https://i0.hdslb.com/bfs/dm/special.bin?token=a%2Fb&part=1&part=2',
      'https://comment.bilibili.com/special.bin',
      'https://api.bilibili.com/x/v2/dm/special.bin',
    ];
    for (final url in acceptedUrls) {
      final result = await client.fetchDanmakuSpecialResource(
        bvid: 'BV1SPECIAL',
        resourceUrl: url,
      );
      expect(result, <int>[1, 2, 3], reason: url);
      expect(httpClient.lastUri, Uri.parse(url), reason: url);
    }
    expect(
      httpClient.lastRequest.headers.value(HttpHeaders.refererHeader),
      biliVideoReferer('BV1SPECIAL'),
    );
    expect(
      httpClient.lastRequest.headers.value(HttpHeaders.cookieHeader),
      isNull,
    );

    for (final url in <String>[
      'http://i0.hdslb.com/bfs/dm/special.bin',
      'https://user@i0.hdslb.com/bfs/dm/special.bin',
      'https://hdslb.com.example.test/special.bin',
      'https://bilibili.com.example.test/special.bin',
      'https://notbilibili.com/special.bin',
      'https://example.test/special.bin?token=do-not-log-this-secret',
      'not a URL',
    ]) {
      expect(
        () => client.fetchDanmakuSpecialResource(
          bvid: 'BV1SPECIAL',
          resourceUrl: url,
        ),
        throwsFormatException,
        reason: url,
      );
    }

    final joinedLogs = logs.join('\n');
    expect(joinedLogs, contains('example.test'));
    expect(joinedLogs, isNot(contains('do-not-log-this-secret')));
  });

  test('网络仓库在后台 isolate 解析分段响应', () async {
    final transport = _RecordingBinaryTransport(
      responseBytes: const <int>[
        0x0A,
        0x08,
        0x10,
        0xE8,
        0x07,
        0x18,
        0x01,
        0x3A,
        0x01,
        0x78,
      ],
    );
    final repository = BiliNetworkDanmakuRepository(
      BiliClient(transport: transport),
    );
    addTearDown(() => transport.httpClient.close(force: true));

    final entries = await repository.loadSegment(
      bvid: 'BV1TEST',
      cid: 123,
      aid: 456,
      segmentIndex: 1,
    );

    expect(entries, hasLength(1));
    expect(entries.single.appearAtMs, 1000);
    expect(entries.single.text, 'x');
    expect(entries.single.mode, BiliDanmakuMode.scroll);
  });

  test('网络仓库解析 view 后获取并合并特殊 protobuf 包', () async {
    const resourceUrl = 'https://i0.hdslb.com/bfs/dm/special.bin';
    final viewBytes = _bytesField(6, utf8.encode(resourceUrl));
    final specialEntry = <int>[
      ..._varintField(2, 1200),
      ..._varintField(3, 8),
      ..._bytesField(6, utf8.encode('sender-hash')),
      ..._bytesField(7, utf8.encode('code payload')),
      ..._bytesField(12, utf8.encode('special-id')),
    ];
    final transport = _SpecialPackageTransport(
      viewBytes: viewBytes,
      packageBytes: _bytesField(1, specialEntry),
    );
    final repository = BiliNetworkDanmakuRepository(
      BiliClient(transport: transport),
    );
    addTearDown(() => transport.httpClient.close(force: true));

    final entries = await repository.loadSpecialEntries(
      bvid: 'BV1SPECIAL',
      cid: 123,
      aid: 456,
    );

    expect(entries, hasLength(1));
    expect(entries.single.rowId, 'special-id');
    expect(entries.single.mode, BiliDanmakuMode.code);
    expect(entries.single.senderHash, 'sender-hash');
    expect(entries.single.text, 'code payload');
    expect(transport.requestedPaths, <String>[
      BiliApiPaths.danmakuViewWeb,
      '/bfs/dm/special.bin',
    ]);
    expect(transport.requestedIncludeCookies, <bool>[true, false]);
    expect(() => entries.add(entries.single), throwsUnsupportedError);
  });
}

final class _RecordingBinaryTransport extends BiliTransport {
  _RecordingBinaryTransport({this.responseBytes = const <int>[1, 2, 3]})
    : super(httpClient: _BytesHttpClient(const []));

  final List<int> responseBytes;

  String? host;
  String? path;
  Map<String, Object?>? params;
  bool? useWbi;
  String? referer;

  @override
  Future<List<int>> getBinaryData({
    required String host,
    required String path,
    Map<String, Object?> params = const <String, Object?>{},
    bool useWbi = false,
    String referer = biliDefaultReferer,
    bool ensureReady = true,
  }) async {
    this.host = host;
    this.path = path;
    this.params = params;
    this.useWbi = useWbi;
    this.referer = referer;
    return responseBytes;
  }
}

final class _SpecialPackageTransport extends BiliTransport {
  _SpecialPackageTransport({
    required this.viewBytes,
    required this.packageBytes,
  }) : super(httpClient: _BytesHttpClient(const []));

  final List<int> viewBytes;
  final List<int> packageBytes;
  final List<String> requestedPaths = <String>[];
  final List<bool> requestedIncludeCookies = <bool>[];

  @override
  Future<List<int>> getBinaryData({
    required String host,
    required String path,
    Map<String, Object?> params = const <String, Object?>{},
    bool useWbi = false,
    String referer = biliDefaultReferer,
    bool ensureReady = true,
  }) async {
    requestedPaths.add(path);
    requestedIncludeCookies.add(true);
    if (path == BiliApiPaths.danmakuViewWeb) {
      return viewBytes;
    }
    throw StateError('unexpected binary request: $host$path');
  }

  @override
  Future<BiliHttpResponse> sendRequest(
    Uri uri, {
    required String referer,
    String method = 'GET',
    String? requestBody,
    String acceptHeader = 'application/json, */*',
    bool includeCookies = true,
  }) async {
    requestedPaths.add(uri.path);
    requestedIncludeCookies.add(includeCookies);
    if (uri.host == 'i0.hdslb.com' &&
        uri.path == '/bfs/dm/special.bin' &&
        acceptHeader == 'application/octet-stream, */*') {
      return BiliHttpResponse(
        statusCode: HttpStatus.ok,
        bodyBytes: packageBytes,
      );
    }
    throw StateError('unexpected request: $uri');
  }
}

final class _BytesHttpClient implements HttpClient {
  _BytesHttpClient(this.chunks);

  final List<List<int>> chunks;
  late _BytesHttpClientRequest lastRequest;
  Uri? lastUri;
  String? _userAgent;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) {
    _userAgent = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    lastUri = url;
    return lastRequest = _BytesHttpClientRequest(chunks);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BytesHttpClientRequest implements HttpClientRequest {
  _BytesHttpClientRequest(this.chunks);

  final List<List<int>> chunks;
  final _MemoryHttpHeaders _headers = _MemoryHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _BytesHttpClientResponse(chunks);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BytesHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  const _BytesHttpClientResponse(this.chunks);

  final List<List<int>> chunks;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  HttpHeaders get headers => _MemoryHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(chunks).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _MemoryHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = <String>[value.toString()];
  }

  @override
  String? value(String name) => _values[name.toLowerCase()]?.join(', ');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
