import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_media/common/widgets/app_network_image.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HttpServer server;
  late String url;
  late CacheManager manager;
  var requests = 0;
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==',
  );

  CacheManager createManager() => CacheManager(
    Config(
      'test-images',
      repo: JsonCacheInfoRepository(path: '${directory.path}/index.json'),
    ),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('app-images-test-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      request.response.headers.set(
        HttpHeaders.cacheControlHeader,
        'max-age=86400',
      );
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    url = 'http://127.0.0.1:${server.port}/cover.png';
    manager = HttpOverrides.runWithHttpOverrides(
      createManager,
      _RealHttpOverrides(),
    );
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await manager.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  test(
    'concurrent requests and a recreated cache reuse one downloaded file',
    () async {
      final results = await Future.wait([
        manager.getSingleFile(url),
        manager.getSingleFile(url),
      ]);
      expect(requests, 1);
      expect(await results.first.readAsBytes(), bytes);
      await manager.dispose();
      manager = HttpOverrides.runWithHttpOverrides(
        createManager,
        _RealHttpOverrides(),
      );
      expect(await (await manager.getSingleFile(url)).readAsBytes(), bytes);
      expect(requests, 1);
    },
  );

  testWidgets('covers, resized images and avatars use the same scoped cache', (
    tester,
  ) async {
    await tester.runAsync(() => manager.getSingleFile(url));
    ImageProvider? avatar;
    await tester.pumpWidget(
      AppImageCacheScope(
        getCacheManager: () => manager,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              avatar = appNetworkImageProvider(context, url);
              return AppNetworkImage(url, cacheWidth: 96, cacheHeight: 96);
            },
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect(resized.width, 96);
    expect(resized.height, 96);
    final provider = resized.imageProvider as CachedNetworkImageProvider;
    expect(provider.cacheManager, same(manager));
    expect((avatar as CachedNetworkImageProvider).cacheManager, same(manager));
    await tester.runAsync(() async {
      final finished = Completer<void>();
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (_, _) {
          if (!finished.isCompleted) finished.complete();
        },
        onError: (Object error, StackTrace? trace) {
          if (!finished.isCompleted) finished.completeError(error, trace);
        },
      );
      stream.addListener(listener);
      try {
        await finished.future.timeout(const Duration(seconds: 10));
      } finally {
        stream.removeListener(listener);
      }
    });
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _RealHttpOverrides extends HttpOverrides {}
