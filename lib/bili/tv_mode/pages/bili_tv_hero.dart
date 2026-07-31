part of 'bili_tv_home_page.dart';

class _TvHeroAction extends StatelessWidget {
  const _TvHeroAction({
    required this.label,
    required this.icon,
    required this.debugLabel,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final String debugLabel;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TvGlassSelectable(
      useOwnLayer: false,
      scale: 1.025,
      borderRadius: AppVisualTokens.controlRadius,
      focusArea: TvFocusArea.content,
      debugLabel: debugLabel,
      onTap: onTap,
      builder: (context, state) {
        final focused = state == TvGlassSelectableState.focused;
        final pressed = state == TvGlassSelectableState.pressed;
        return AnimatedContainer(
          duration: AppVisualTokens.motionDuration(
            context,
            AppVisualTokens.buttonPressDuration,
          ),
          width: primary ? 174 : 142,
          height: 52,
          decoration: BoxDecoration(
            color: primary
                ? AppVisualTokens.primaryBlue
                : focused || pressed
                ? const Color(0x3DFFFFFF)
                : const Color(0x24FFFFFF),
            borderRadius: BorderRadius.circular(AppVisualTokens.controlRadius),
            boxShadow: primary
                ? const [
                    BoxShadow(
                      color: Color(0x33409EFF),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          padding: const EdgeInsets.only(left: 17, right: 19),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: icon == Icons.play_arrow_rounded ? 2 : 0,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
