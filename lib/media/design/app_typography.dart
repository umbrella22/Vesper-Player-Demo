import 'package:material_ui/material_ui.dart';

/// Mobile content typography uses logical layout width and the theme's font.
/// System text scaling remains the responsibility of Text and TextPainter.
abstract final class AppTypography {
  static const FontWeight titleWeight = FontWeight.w600;

  static TextStyle videoCardTitle(
    BuildContext context, {
    required double cardWidth,
  }) {
    return Theme.of(context).textTheme.titleSmall!.copyWith(
      fontSize: cardWidth < 180 ? 13 : 14,
      fontWeight: titleWeight,
      letterSpacing: 0,
      height: 1.35,
    );
  }

  static TextStyle playbackTitle(
    BuildContext context, {
    required double contentWidth,
  }) {
    return Theme.of(context).textTheme.titleLarge!.copyWith(
      fontSize: contentWidth < 360 ? 20 : 22,
      fontWeight: titleWeight,
      letterSpacing: 0,
      height: 1.3,
    );
  }
}
