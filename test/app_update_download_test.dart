import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/app/updates/app_update_release.dart';
import 'package:vesper_media/app/updates/github_app_update_client.dart';

import 'support/app_update_fakes.dart';

void main() {
  late HttpServer server;
  late Directory root;
  late GithubAppUpdateClient client;
  late Future<void> Function(HttpRequest) handler;
  final payload = utf8.encode('test installer bytes');
  final hash = sha256.convert(payload).toString();
  final requests = <Uri>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vesper-update-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handler = (request) async {
      request.response.add(payload);
      await request.response.close();
    };
    server.listen((request) => unawaited(handler(request)));
    requests.clear();
    client = GithubAppUpdateClient(
      httpClientFactory: () => _LocalHttpClient(server.port, requests),
      temporaryDirectory: () async => root,
    );
  });

  tearDown(() async {
    client.dispose();
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  AppUpdateAsset asset({String? digest, int? size, bool sidecar = false}) =>
      AppUpdateAsset(
        name: 'vesper-v1.15.0-android-arm64-release.apk',
        url: Uri.https('github.com', '/update.apk'),
        size: size ?? payload.length,
        sha256: sidecar ? null : digest ?? hash,
        checksumUrl: sidecar
            ? Uri.https('github.com', '/update.apk.sha256')
            : null,
      );

  test('retrieves latest release from the configured repository', () async {
    handler = (request) async {
      expect(
        request.headers.value(HttpHeaders.userAgentHeader),
        'Vesper-App-Updater',
      );
      expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
      request.response.write(jsonEncode(releaseJson()));
      await request.response.close();
    };
    final release = await client.latestRelease(AppUpdatePlatform.playCover);
    expect(
      requests.single.toString(),
      'https://api.github.com/repos/umbrella22/Vesper-Player-Demo/releases/latest',
    );
    expect(release!.asset!.name, endsWith('-ios-playcover.ipa'));
  });

  test(
    'successful download checks bytes before exposing a final installer',
    () async {
      final progress = <int>[];
      final file = await client.download(
        asset(),
        onProgress: (received, _) => progress.add(received),
      );
      expect(await file.readAsBytes(), payload);
      expect(
        file.path,
        endsWith('/vesper-updates/vesper-v1.15.0-android-arm64-release.apk'),
      );
      expect(progress.first, 0);
      expect(progress.last, payload.length);
      expect(await File('${file.path}.part').exists(), isFalse);
    },
  );

  test(
    'corrupt, short and oversized downloads leave no installer or partial file',
    () async {
      for (final expected in [
        asset(digest: 'b' * 64),
        asset(size: payload.length + 1),
        asset(size: payload.length - 1),
      ]) {
        await expectLater(
          client.download(expected, onProgress: (_, _) {}),
          throwsA(isA<AppUpdateException>()),
        );
        final directory = Directory('${root.path}/vesper-updates');
        expect(await directory.list().toList(), isEmpty);
      }
    },
  );

  test(
    'sidecar must identify the exact file before downloading its bytes',
    () async {
      handler = (request) async {
        if (request.uri.path.endsWith('.sha256')) {
          request.response.write('$hash  ${asset().name}\n');
        } else {
          request.response.add(payload);
        }
        await request.response.close();
      };
      final file = await client.download(
        asset(sidecar: true),
        onProgress: (_, _) {},
      );
      expect(await file.readAsBytes(), payload);
      expect(requests.length, 2);
      handler = (request) async {
        request.response.write('$hash  other.apk\n');
        await request.response.close();
      };
      await expectLater(
        client.download(asset(sidecar: true), onProgress: (_, _) {}),
        throwsA(isA<AppUpdateException>()),
      );
      expect(requests.length, 3);
    },
  );

  test(
    'cancellation aborts a stalled transfer and permits a clean retry',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      handler = (request) async {
        try {
          request.response.add(payload.sublist(0, 4));
          await request.response.flush();
          started.complete();
          await finish.future;
          await request.response.close();
        } on SocketException {
          // Cancellation closes the connection while the server is streaming.
        }
      };
      final download = client.download(asset(), onProgress: (_, _) {});
      final expectation = expectLater(
        download,
        throwsA(isA<AppUpdateCancelled>()),
      );
      await started.future;
      client.cancelDownload();
      finish.complete();
      await expectation;
      expect(
        await Directory('${root.path}/vesper-updates').list().toList(),
        isEmpty,
      );
      handler = (request) async {
        request.response.add(payload);
        await request.response.close();
      };
      expect(
        await (await client.download(
          asset(),
          onProgress: (_, _) {},
        )).readAsBytes(),
        payload,
      );
    },
  );

  test('rate limiting produces a retryable message', () async {
    handler = (request) async {
      request.response.statusCode = 403;
      await request.response.close();
    };
    await expectLater(
      client.latestRelease(AppUpdatePlatform.androidArm64),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.message,
          'message',
          contains('稍后重试'),
        ),
      ),
    );
  });
}

/// Keep the production URLs observable while serving fixture bytes locally.
class _LocalHttpClient extends Fake implements HttpClient {
  _LocalHttpClient(this.port, this.requests);
  final int port;
  final List<Uri> requests;
  final HttpClient inner = HttpClient();
  @override
  set connectionTimeout(Duration? value) {
    inner.connectionTimeout = value;
  }

  @override
  set userAgent(String? value) {
    inner.userAgent = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requests.add(url);
    return inner.getUrl(
      url.replace(scheme: 'http', host: '127.0.0.1', port: port),
    );
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}
