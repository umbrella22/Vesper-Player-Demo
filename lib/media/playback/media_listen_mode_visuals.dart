import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../design/app_visual_theme.dart';

final class MediaListenAmbientBackground extends StatelessWidget {
  const MediaListenAmbientBackground({
    super.key,
    required this.coverUrl,
    required this.child,
  });

  final String coverUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppVisualTokens.darkBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverUrl.isNotEmpty)
            Positioned(
              top: -120,
              left: -80,
              right: -80,
              height: MediaQuery.sizeOf(context).height * 0.7,
              child: Opacity(
                opacity: 0.18,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 52, sigmaY: 52),
                  child: Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          const Positioned.fill(child: ColoredBox(color: Color(0xB8111318))),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

final class MediaListenPhoneHeader extends StatelessWidget {
  const MediaListenPhoneHeader({super.key, required this.onReturnToVideo});

  final VoidCallback onReturnToVideo;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                key: const ValueKey<String>('listen-return-video'),
                tooltip: '退出听视频',
                onPressed: onReturnToVideo,
                icon: const Icon(Icons.arrow_back_rounded, size: 26),
                color: visualTheme.textPrimary,
              ),
            ),
            Text(
              '听视频',
              style: TextStyle(
                color: visualTheme.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class MediaListenCover extends StatelessWidget {
  const MediaListenCover({
    super.key,
    required this.url,
    required this.size,
    required this.semanticLabel,
  });

  final String url;
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Semantics(
      image: true,
      label: semanticLabel,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: visualTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
          border: Border.all(color: visualTheme.imageOutline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: url.isEmpty
            ? Icon(
                Icons.graphic_eq_rounded,
                size: size * 0.28,
                color: visualTheme.textTertiary,
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => Icon(
                  Icons.graphic_eq_rounded,
                  size: size * 0.28,
                  color: visualTheme.textTertiary,
                ),
              ),
      ),
    );
  }
}
