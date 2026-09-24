import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_icons.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';

/// Marks the immersive settings presentation without changing embedded panels.
class MediaPlaybackDrawerScope extends InheritedWidget {
  const MediaPlaybackDrawerScope({super.key, required super.child});

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaPlaybackDrawerScope>() !=
      null;

  @override
  bool updateShouldNotify(MediaPlaybackDrawerScope oldWidget) => false;
}

/// A pinned, shared header above independently scrollable drawer content.
class MediaPlaybackSettingsPage extends StatelessWidget {
  const MediaPlaybackSettingsPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.onBack,
    this.scrollKey,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(onBack == null ? 18 : 4, 4, 6, 4),
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  tooltip: '返回清晰度',
                  onPressed: onBack,
                  icon: const Icon(AppIcons.arrowLeftLine, size: 22),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...actions,
              IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                key: const ValueKey('playback-settings-close'),
                tooltip: '关闭设置',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(AppIcons.closeFill, size: 24),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: scrollKey,
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: child,
          ),
        ),
      ],
    );
  }
}

class MediaPlaybackSettingsGroup extends StatelessWidget {
  const MediaPlaybackSettingsGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppVisualTheme.of(context).surfaceRaised,
    borderRadius: BorderRadius.circular(10),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
