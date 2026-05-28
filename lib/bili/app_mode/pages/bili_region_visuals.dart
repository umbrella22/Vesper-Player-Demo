import 'package:material_ui/material_ui.dart';

import 'package:bilibili_player/bili/common/models/bili_region_models.dart';

final class BiliRegionVisual {
  const BiliRegionVisual({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

BiliRegionVisual biliRegionVisualFor(BiliRegionSection section) {
  return switch (section.id) {
    'bangumi' => const BiliRegionVisual(
      icon: Icons.live_tv_outlined,
      color: Color(0xFF00A1D6),
    ),
    'guochuang' => const BiliRegionVisual(
      icon: Icons.auto_awesome_motion_outlined,
      color: Color(0xFFFB7299),
    ),
    'movie' => const BiliRegionVisual(
      icon: Icons.movie_outlined,
      color: Color(0xFF7C6BEA),
    ),
    'tv' => const BiliRegionVisual(
      icon: Icons.connected_tv_outlined,
      color: Color(0xFF22A06B),
    ),
    'documentary' => const BiliRegionVisual(
      icon: Icons.camera_alt_outlined,
      color: Color(0xFFE78A1E),
    ),
    'variety' => const BiliRegionVisual(
      icon: Icons.theater_comedy_outlined,
      color: Color(0xFFD756A9),
    ),
    'douga' => const BiliRegionVisual(
      icon: Icons.palette_outlined,
      color: Color(0xFF27A8E0),
    ),
    'music' => const BiliRegionVisual(
      icon: Icons.music_note_outlined,
      color: Color(0xFFF05D5E),
    ),
    'game' => const BiliRegionVisual(
      icon: Icons.sports_esports_outlined,
      color: Color(0xFF5A7CF6),
    ),
    'knowledge' => const BiliRegionVisual(
      icon: Icons.school_outlined,
      color: Color(0xFF19A58B),
    ),
    'tech' => const BiliRegionVisual(
      icon: Icons.memory_outlined,
      color: Color(0xFF4C8DFF),
    ),
    'life' => const BiliRegionVisual(
      icon: Icons.home_outlined,
      color: Color(0xFFFF8A4C),
    ),
    _ => const BiliRegionVisual(
      icon: Icons.video_library_outlined,
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
