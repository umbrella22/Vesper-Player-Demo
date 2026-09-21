import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_icons.dart';

import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/bili/common/models/bili_region_models.dart';

final class BiliRegionVisual {
  const BiliRegionVisual({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

BiliRegionVisual biliRegionVisualFor(BiliRegionSection section) {
  return switch (section.id) {
    'bangumi' => const BiliRegionVisual(
      icon: AppIcons.liveLine,
      color: Color(0xFF00A1D6),
    ),
    'guochuang' => const BiliRegionVisual(
      icon: AppIcons.stackLine,
      color: AppVisualTokens.primaryBlue,
    ),
    'movie' => const BiliRegionVisual(
      icon: AppIcons.movieLine,
      color: Color(0xFF7C6BEA),
    ),
    'tv' => const BiliRegionVisual(
      icon: AppIcons.tv2Line,
      color: Color(0xFF22A06B),
    ),
    'documentary' => const BiliRegionVisual(
      icon: AppIcons.cameraLine,
      color: Color(0xFFE78A1E),
    ),
    'variety' => const BiliRegionVisual(
      icon: AppIcons.movie2Line,
      color: Color(0xFFD756A9),
    ),
    'douga' => const BiliRegionVisual(
      icon: AppIcons.paletteLine,
      color: Color(0xFF27A8E0),
    ),
    'music' => const BiliRegionVisual(
      icon: AppIcons.music2Line,
      color: Color(0xFFF05D5E),
    ),
    'game' => const BiliRegionVisual(
      icon: AppIcons.gamepadLine,
      color: Color(0xFF5A7CF6),
    ),
    'knowledge' => const BiliRegionVisual(
      icon: AppIcons.schoolLine,
      color: Color(0xFF19A58B),
    ),
    'tech' => const BiliRegionVisual(
      icon: AppIcons.cpuLine,
      color: Color(0xFF4C8DFF),
    ),
    'life' => const BiliRegionVisual(
      icon: AppIcons.home5Line,
      color: Color(0xFFFF8A4C),
    ),
    _ => const BiliRegionVisual(
      icon: AppIcons.filmLine,
      color: Color(0xFF00A1D6),
    ),
  };
}

class BiliRegionIcon extends StatelessWidget {
  const BiliRegionIcon({
    super.key,
    required this.section,
    this.size = 44,
    this.iconSize = 24,
  });

  final BiliRegionSection section;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final visual = biliRegionVisualFor(section);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visual.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(visual.icon, color: visual.color, size: iconSize),
      ),
    );
  }
}
