import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Shares downloaded image files across routes, decode sizes and app launches.
/// HTTP freshness still applies, so an avatar replaced at the same URL can update.
class AppImageCacheScope extends InheritedWidget {
  const AppImageCacheScope({
    super.key,
    required this.getCacheManager,
    required super.child,
  });

  final BaseCacheManager Function() getCacheManager;

  static BaseCacheManager? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppImageCacheScope>()
      ?.getCacheManager();

  @override
  bool updateShouldNotify(AppImageCacheScope oldWidget) =>
      getCacheManager != oldWidget.getCacheManager;
}

CacheManager createAppImageCacheManager() => CacheManager(
  Config(
    'vesper-images-v1',
    // Retain recently browsed libraries, while bounding the on-disk file count.
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 1000,
  ),
);

ImageProvider appNetworkImageProvider(BuildContext context, String url) {
  final cacheManager = AppImageCacheScope.maybeOf(context);
  // Standalone widgets can be embedded without an application cache owner.
  if (cacheManager == null) return NetworkImage(url);
  return CachedNetworkImageProvider(url, cacheManager: cacheManager);
}

class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.errorBuilder,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.gaplessPlayback = false,
    this.excludeFromSemantics = false,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final ImageErrorWidgetBuilder? errorBuilder;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) => Image(
    image: ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      appNetworkImageProvider(context, url),
    ),
    fit: fit,
    width: width,
    height: height,
    errorBuilder: errorBuilder,
    alignment: alignment,
    filterQuality: filterQuality,
    gaplessPlayback: gaplessPlayback,
    excludeFromSemantics: excludeFromSemantics,
  );
}
