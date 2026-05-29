import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'bili_api_core.dart';
import 'bili_wbi.dart';

const Duration _defaultBiliConnectionTimeout = Duration(seconds: 15);
const Duration _defaultBiliRequestTimeout = Duration(seconds: 30);

class BiliTransport {
  BiliTransport({
    HttpClient? httpClient,
    BiliWbiSigner? signer,
    Duration connectionTimeout = _defaultBiliConnectionTimeout,
    Duration requestTimeout = _defaultBiliRequestTimeout,
  }) : _httpClient = httpClient ?? HttpClient(),
       _signer = signer ?? const BiliWbiSigner(),
       _requestTimeout = requestTimeout {
    _httpClient.userAgent = biliUserAgent;
    _configureClientTimeouts(connectionTimeout, requestTimeout);
  }

  final HttpClient _httpClient;
  final BiliWbiSigner _signer;
  final Duration _requestTimeout;
  final Map<String, String> _cookies = <String, String>{};

  String? _imgKey;
  String? _subKey;

  HttpClient get httpClient => _httpClient;

  bool get hasAuthenticatedSession =>
      (_cookies['SESSDATA'] ?? '').isNotEmpty &&
      (_cookies['bili_jct'] ?? '').isNotEmpty;

  Map<String, String> snapshotCookies() => Map<String, String>.from(_cookies);

  void restoreCookies(Map<String, String> cookies) {
    _cookies
      ..clear()
      ..addAll(cookies);
  }

  void clearSession() {
    _cookies.clear();
  }

  String? get imgKey => _imgKey;

  String? get subKey => _subKey;

  Map<String, String> get cookies => Map<String, String>.unmodifiable(_cookies);

  String? cookieValue(String name) => _cookies[name];

  void setCookie(String name, String value) {
    _cookies[name] = value;
  }

  Future<void> ensureReady() async {
    if (_cookies.isEmpty) {
      await _primeCookies();
    }

    if (!_hasBuvidCookies) {
      await _ensureBuvidCookies();
    }

    if (_imgKey == null || _subKey == null) {
      await _refreshWbiKeys();
    }
  }

  Future<Map<String, Object?>> getData({
    required String host,
    required String path,
    Map<String, Object?> params = const <String, Object?>{},
    bool useWbi = false,
    String referer = 'https://www.bilibili.com/',
    bool ensureReady = true,
    Set<int> allowedCodes = const <int>{0},
  }) async {
    if (ensureReady) {
      await this.ensureReady();
    }

    for (var attempt = 0; attempt < 2; attempt += 1) {
      final query = _buildQuery(params: params, useWbi: useWbi);
      final response = await sendRequest(
        Uri.https(host, path, _stringifyQuery(query)),
        referer: referer,
      );
      try {
        return decodeDataResponse(response.body, allowedCodes: allowedCodes);
      } on BiliApiException catch (error) {
        if (error.code != biliRiskControlCode ||
            allowedCodes.contains(biliRiskControlCode) ||
            attempt > 0) {
          rethrow;
        }

        final recovered = await _recoverFromRiskControl(response.body);
        if (!recovered) {
          rethrow;
        }
      }
    }

    throw const BiliApiException(
      'Bilibili 风控重试失败，请稍后重试或登录后再试。',
      code: biliRiskControlCode,
    );
  }

  Map<String, Object?> _buildQuery({
    required Map<String, Object?> params,
    required bool useWbi,
  }) {
    if (!useWbi) {
      return params;
    }

    final imgKey = _imgKey;
    final subKey = _subKey;
    if (imgKey == null || subKey == null) {
      throw const BiliApiException('WBI keys are unavailable.');
    }
    return _signer.sign(params: params, imgKey: imgKey, subKey: subKey);
  }

  Future<Map<String, Object?>> postData({
    required String host,
    required String path,
    Map<String, Object?> data = const <String, Object?>{},
    String referer = 'https://www.bilibili.com/',
    bool ensureReady = true,
  }) async {
    final responseData = await postApiData(
      host: host,
      path: path,
      data: data,
      referer: referer,
      ensureReady: ensureReady,
    );
    return readObjectMap(responseData);
  }

  Future<Object?> postApiData({
    required String host,
    required String path,
    Map<String, Object?> data = const <String, Object?>{},
    String referer = 'https://www.bilibili.com/',
    bool ensureReady = true,
  }) async {
    if (ensureReady) {
      await this.ensureReady();
    }

    final csrf = requireCsrfToken();
    final fields = _stringifyQuery(data)
      ..['csrf'] = csrf
      ..['csrf_token'] = csrf;
    final response = await sendRequest(
      Uri.https(host, path),
      method: 'POST',
      requestBody: _formEncode(fields),
      referer: referer,
    );
    return decodeApiData(response.body);
  }

  Map<String, Object?> decodeDataResponse(
    String body, {
    Set<int> allowedCodes = const <int>{0},
  }) {
    final data = decodeApiData(body, allowedCodes: allowedCodes);
    return readObjectMap(data);
  }

  Object? decodeApiData(String body, {Set<int> allowedCodes = const <int>{0}}) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const BiliApiException('Unexpected Bilibili API response.');
    }

    final map = Map<String, Object?>.from(decoded);
    final code = readInt(map['code']) ?? -1;
    if (!allowedCodes.contains(code)) {
      final message =
          readString(map['message']) ??
          readString(map['msg']) ??
          'Unknown Bilibili error.';
      if (code == biliRiskControlCode) {
        final data = readObjectMap(map['data']);
        final needsCaptcha = readString(data['v_voucher']) != null;
        throw BiliApiException(
          needsCaptcha
              ? 'Bilibili 触发风控，需要完成验证码验证后重试。'
              : 'Bilibili 触发风控，请稍后重试或登录后再试。',
          code: code,
        );
      }
      throw BiliApiException(message, code: code);
    }

    if (map.containsKey('data')) {
      return map['data'];
    }
    return map['result'];
  }

  Future<BiliHttpResponse> sendRequest(
    Uri uri, {
    required String referer,
    String method = 'GET',
    String? requestBody,
    String acceptHeader = 'application/json, */*',
  }) async {
    return _sendRequest(
      uri,
      referer: referer,
      method: method,
      requestBody: requestBody,
      acceptHeader: acceptHeader,
    ).timeout(
      _requestTimeout,
      onTimeout: () => throw BiliApiException(
        'Bilibili request timed out after ${_requestTimeout.inSeconds}s.',
      ),
    );
  }

  Future<BiliHttpResponse> _sendRequest(
    Uri uri, {
    required String referer,
    required String method,
    required String? requestBody,
    required String acceptHeader,
  }) async {
    final request = method == 'POST'
        ? await _httpClient.postUrl(uri)
        : await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, acceptHeader);
    request.headers.set(HttpHeaders.refererHeader, referer);
    request.headers.set('Origin', originFromReferer(referer));
    request.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');
    request.headers.set('Sec-Fetch-Dest', 'empty');
    request.headers.set('Sec-Fetch-Mode', 'cors');
    request.headers.set('Sec-Fetch-Site', 'same-site');
    if (requestBody != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      final payload = utf8.encode(requestBody);
      request.contentLength = payload.length;
      request.add(payload);
    }

    if (_cookies.isNotEmpty) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        buildCookieHeader(_cookies),
      );
    }

    final response = await request.close();
    _storeResponseCookies(uri, response.cookies);

    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BiliApiException(
        'HTTP ${response.statusCode} from Bilibili.',
        code: response.statusCode,
      );
    }

    return BiliHttpResponse(statusCode: response.statusCode, body: body);
  }

  void _configureClientTimeouts(
    Duration connectionTimeout,
    Duration idleTimeout,
  ) {
    try {
      _httpClient.connectionTimeout = connectionTimeout;
      _httpClient.idleTimeout = idleTimeout;
    } catch (_) {
      // Test doubles may only implement the HttpClient members they exercise.
    }
  }

  void _storeResponseCookies(Uri uri, List<Cookie> cookies) {
    for (final cookie in cookies) {
      if (!_shouldStoreCookie(uri, cookie)) {
        continue;
      }
      if (_isExpiredCookie(cookie)) {
        _cookies.remove(cookie.name);
      } else {
        _cookies[cookie.name] = cookie.value;
      }
    }
  }

  bool _shouldStoreCookie(Uri uri, Cookie cookie) {
    if (cookie.name.isEmpty || !_isTrustedBiliCookieHost(uri.host)) {
      return false;
    }
    if (cookie.secure && uri.scheme != 'https') {
      return false;
    }

    final domain = cookie.domain;
    if (domain != null &&
        domain.isNotEmpty &&
        !_cookieDomainMatches(uri.host, domain)) {
      return false;
    }

    final path = cookie.path;
    if (path != null &&
        path.isNotEmpty &&
        !_cookiePathMatches(uri.path, path)) {
      return false;
    }
    return true;
  }

  bool _isTrustedBiliCookieHost(String host) {
    return host == 'bilibili.com' || host.endsWith('.bilibili.com');
  }

  bool _cookieDomainMatches(String host, String domain) {
    final normalized = domain.startsWith('.') ? domain.substring(1) : domain;
    return host == normalized || host.endsWith('.$normalized');
  }

  bool _cookiePathMatches(String requestPath, String cookiePath) {
    if (requestPath == cookiePath) {
      return true;
    }
    final normalized = cookiePath.endsWith('/') ? cookiePath : '$cookiePath/';
    return requestPath.startsWith(normalized);
  }

  bool _isExpiredCookie(Cookie cookie) {
    final maxAge = cookie.maxAge;
    if (maxAge != null && maxAge <= 0) {
      return true;
    }
    final expires = cookie.expires;
    return expires != null && !expires.isAfter(DateTime.now().toUtc());
  }

  String requireCsrfToken() {
    final csrf = _cookies['bili_jct'] ?? '';
    if ((_cookies['SESSDATA'] ?? '').isEmpty || csrf.isEmpty) {
      throw const BiliApiException('请先登录 Bilibili 后再操作。', code: -101);
    }
    return csrf;
  }

  static String buildCookieHeader(Map<String, String> cookies) {
    return cookies.entries
        .where((entry) => entry.key.isNotEmpty && entry.value.isNotEmpty)
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  String buildSessionValue() {
    final buvid3 = _cookies['buvid3'] ?? _generatePseudoBuvid3();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return md5.convert(utf8.encode('$buvid3$timestamp')).toString();
  }

  static String extractKey(String url) {
    final uri = Uri.parse(url);
    final lastSegment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dotIndex = lastSegment.lastIndexOf('.');
    return dotIndex <= 0 ? lastSegment : lastSegment.substring(0, dotIndex);
  }

  Map<String, String> buildBiliMediaSourceHeaders() {
    final headers = <String, String>{
      HttpHeaders.acceptHeader: '*/*',
      HttpHeaders.userAgentHeader: biliUserAgent,
      HttpHeaders.refererHeader: biliMediaReferer,
      'Origin': originFromReferer(biliMediaReferer),
      HttpHeaders.acceptLanguageHeader: 'zh-CN,zh;q=0.9',
    };
    final cookieHeader = buildCookieHeader(_cookies);
    if (cookieHeader.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = cookieHeader;
    }
    return headers;
  }

  Future<void> _primeCookies() async {
    await sendRequest(
      Uri.https('www.bilibili.com', '/'),
      referer: 'https://www.bilibili.com/',
    );
  }

  Future<void> _refreshWbiKeys() async {
    final data = await getData(
      host: 'api.bilibili.com',
      path: '/x/web-interface/nav',
      referer: 'https://www.bilibili.com/',
      ensureReady: false,
      allowedCodes: const <int>{0, -101},
    );

    final wbiImg = readObjectMap(data['wbi_img']);
    final imgUrl = readString(wbiImg['img_url']) ?? '';
    final subUrl = readString(wbiImg['sub_url']) ?? '';

    _imgKey = extractKey(imgUrl);
    _subKey = extractKey(subUrl);
  }

  Future<void> _ensureBuvidCookies() async {
    if (_hasBuvidCookies) {
      return;
    }

    await _refreshBuvidCookies();
  }

  Future<void> _refreshBuvidCookies() async {
    try {
      final response = await sendRequest(
        Uri.https('api.bilibili.com', '/x/frontend/finger/spi'),
        referer: 'https://www.bilibili.com/',
      );
      final data = decodeApiData(response.body);
      if (data is! Map) {
        return;
      }

      final map = Map<String, Object?>.from(data);
      final buvid3 = readString(map['b_3']);
      final buvid4 = readString(map['b_4']);
      if (buvid3 != null && buvid3.isNotEmpty) {
        _cookies['buvid3'] = buvid3;
      }
      if (buvid4 != null && buvid4.isNotEmpty) {
        _cookies['buvid4'] = buvid4;
      }
    } catch (_) {
      return;
    }
  }

  Future<bool> _recoverFromRiskControl(String body) async {
    if (_riskResponseNeedsCaptcha(body)) {
      return false;
    }

    try {
      await Future<void>.delayed(
        Duration(milliseconds: 250 + Random.secure().nextInt(350)),
      );
      await _primeCookies();
      await _refreshBuvidCookies();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _riskResponseNeedsCaptcha(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return false;
      }
      final map = Map<String, Object?>.from(decoded);
      final data = readObjectMap(map['data']);
      return readString(data['v_voucher']) != null;
    } catch (_) {
      return false;
    }
  }

  bool get _hasBuvidCookies =>
      (_cookies['buvid3'] ?? '').isNotEmpty &&
      (_cookies['buvid4'] ?? '').isNotEmpty;

  Map<String, String> _stringifyQuery(Map<String, Object?> params) {
    final query = <String, String>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      query[entry.key] = value.toString();
    }
    return query;
  }

  String _formEncode(Map<String, String> fields) {
    return fields.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  static String _generatePseudoBuvid3() {
    const alphabet = '0123456789abcdef';
    final random = Random.secure();
    final chunks = List<String>.generate(
      32,
      (_) => alphabet[random.nextInt(alphabet.length)],
    );
    return '${chunks.join()}infoc';
  }
}

final class BiliHttpResponse {
  const BiliHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
