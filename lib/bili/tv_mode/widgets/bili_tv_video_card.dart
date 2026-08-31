import 'package:material_ui/material_ui.dart';

import 'package:vesper_media/media/tv/media_tv_focusable.dart';

/// The shared visual contract for standard 16:9 video cards in TV mode.
class BiliTvVideoCard extends StatelessWidget {
  const BiliTvVideoCard({
    super.key,
    required this.coverUrl,
    required this.coverCacheWidth,
    required this.title,
    required this.subtitle,
    required this.durationLabel,
    required this.leadingLabel,
    required this.onTap,
    this.autofocus = false,
    this.debugLabel,
    this.onFocusChange,
    this.focusArea = TvFocusArea.content,
  });

  static const double focusScale = 1.07;
  static const double focusPadding = 12;
  static const double surfaceBorderRadius = 14;
  static const double coverBorderRadius = 10;

  final String coverUrl;
  final int coverCacheWidth;
  final String title;
  final String subtitle;
  final String durationLabel;
  final String leadingLabel;
  final VoidCallback onTap;
  final bool autofocus;
  final String? debugLabel;
  final ValueChanged<bool>? onFocusChange;
  final TvFocusArea focusArea;

  @override
  Widget build(BuildContext context) {
    final effectiveDebugLabel = debugLabel ?? 'video_$title';
    return TvFocusableSurface(
      key: ValueKey<String>('bili-tv-video-card-surface-$effectiveDebugLabel'),
      autofocus: autofocus,
      scale: focusScale,
      borderRadius: surfaceBorderRadius,
      focusPadding: focusPadding,
      useOverlayLift: true,
      focusArea: focusArea,
      debugLabel: effectiveDebugLabel,
      onFocusChange: onFocusChange,
      onTap: onTap,
      builder: (context, focused) => LayoutBuilder(
        builder: (context, constraints) {
          final boundedHeight = constraints.hasBoundedHeight;
          final tight = boundedHeight && constraints.maxHeight < 116;
          final condensed = boundedHeight && constraints.maxHeight < 136;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(coverBorderRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFF1A1A24),
                        child: coverUrl.isEmpty
                            ? const Icon(
                                Icons.video_library_outlined,
                                color: Color(0x55FFFFFF),
                                size: 40,
                              )
                            : Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: coverCacheWidth,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: Color(0xFF1A1A24)),
                              ),
                      ),
                      if (leadingLabel.isNotEmpty)
                        Positioned(
                          left: 8,
                          bottom: 6,
                          child: Text(
                            leadingLabel,
                            style: const TextStyle(
                              color: Color(0xDDFFFFFF),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (durationLabel.isNotEmpty)
                        Positioned(
                          right: 8,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              durationLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: condensed ? 4 : 5),
              Text(
                title,
                maxLines: tight ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: focused ? Colors.white : const Color(0xEEFFFFFF),
                  fontSize: condensed ? 12 : 12.2,
                  fontWeight: focused ? FontWeight.w800 : FontWeight.w600,
                  height: 1.17,
                ),
              ),
              if (!condensed && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x66FFFFFF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
