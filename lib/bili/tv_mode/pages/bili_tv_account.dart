part of 'bili_tv_home_page.dart';

class _TvLibraryAction extends StatelessWidget {
  const _TvLibraryAction({
    super.key,
    required this.icon,
    required this.label,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvGlassSelectable(
      scale: 1.045,
      borderRadius: 12,
      focusArea: TvFocusArea.content,
      debugLabel: 'mine_library_$label',
      onTap: onTap,
      builder: (context, state) => SizedBox(
        width: double.infinity,
        height: compact ? 68 : 104,
        child: Flex(
          direction: compact ? Axis.horizontal : Axis.vertical,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xCCFFFFFF), size: compact ? 22 : 30),
            SizedBox(width: compact ? 9 : 0, height: compact ? 0 : 10),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xDDFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvMineCommand extends StatelessWidget {
  const _TvMineCommand({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TvGlassSelectable(
      autofocus: autofocus,
      scale: 1.045,
      borderRadius: 12,
      selected: primary,
      focusArea: TvFocusArea.content,
      debugLabel: 'mine_command_$label',
      onTap: onTap,
      builder: (context, state) => SizedBox(
        width: double.infinity,
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
