import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';

/// A phone grid tile. Each feed supplies its own artwork ratio and metadata.
class BiliVideoGridCard extends StatelessWidget {
  const BiliVideoGridCard({
    super.key,
    required this.cover,
    required this.details,
    required this.onTap,
  });

  final Widget cover;
  final Widget details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = AppVisualTheme.of(context);
    return Material(
      color: visual.surface,
      elevation: Theme.of(context).brightness == Brightness.dark ? 0 : 1,
      shadowColor: visual.shadow,
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cover,
            Expanded(child: details),
          ],
        ),
      ),
    );
  }
}
