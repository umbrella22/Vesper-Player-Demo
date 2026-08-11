part of 'bili_library_page.dart';

const _tvLibraryVideoMaxCrossAxisExtent = 278.0;
// Decode at the largest library tile size so rail animation never changes the
// ResizeImage key for an already visible cover.
const _tvLibraryCoverDecodeLogicalWidth = _tvLibraryVideoMaxCrossAxisExtent;

int _tvLibraryCoverCacheWidth(BuildContext context, double logicalWidth) {
  return (logicalWidth * MediaQuery.devicePixelRatioOf(context))
      .ceil()
      .clamp(160, 720)
      .toInt();
}

class _TvLibraryHeaderButton extends StatelessWidget {
  const _TvLibraryHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: TvFocusableSurface(
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.05,
        borderRadius: 12,
        focusArea: TvFocusArea.content,
        debugLabel: 'tv_library_$tooltip',
        onTap: onTap,
        builder: (context, focused) {
          return Tooltip(
            message: tooltip,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white.withValues(alpha: 0.20)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused
                      ? Colors.white.withValues(alpha: 0.78)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppVisualTokens.primaryBlue,
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: 24),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TvLibraryTab extends StatelessWidget {
  const _TvLibraryTab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 146,
      height: 48,
      child: TvGlassSelectable(
        selected: selected,
        useOwnLayer: true,
        scale: 1.04,
        borderRadius: 12,
        focusArea: TvFocusArea.content,
        debugLabel: 'tv_library_tab_$label',
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        builder: (context, state) {
          final focused =
              state == TvGlassSelectableState.focused ||
              state == TvGlassSelectableState.pressed;
          final foreground = selected || focused
              ? Colors.white
              : const Color(0x99FFFFFF);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 21),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: selected || focused
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                key: ValueKey<String>('bili-tv-library-tab-marker-$label'),
                duration: AppVisualTokens.motionDuration(
                  context,
                  AppVisualTokens.tvFocusDuration,
                ),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: selected
                      ? AppVisualTokens.primaryBlue
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TvLibraryLoadingView extends StatelessWidget {
  const _TvLibraryLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppVisualTokens.primaryBlue,
            ),
          ),
          SizedBox(height: 18),
          Text(
            '正在加载内容',
            style: TextStyle(
              color: Color(0x99FFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvLibraryStatusView extends StatelessWidget {
  const _TvLibraryStatusView({
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
    this.autofocusPrimary = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;
  final bool autofocusPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0x88FFFFFF), size: 54),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              if (onPrimary != null && primaryLabel != null) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _TvLibraryActionButton(
                      autofocus: autofocusPrimary,
                      icon: primaryIcon ?? Icons.check_rounded,
                      label: primaryLabel!,
                      primary: true,
                      onTap: onPrimary!,
                    ),
                    if (onSecondary != null && secondaryLabel != null)
                      _TvLibraryActionButton(
                        icon: secondaryIcon ?? Icons.more_horiz_rounded,
                        label: secondaryLabel!,
                        onTap: onSecondary!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TvLibraryActionButton extends StatelessWidget {
  const _TvLibraryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 50,
      child: TvFocusableSurface(
        autofocus: autofocus,
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.04,
        borderRadius: 12,
        focusArea: TvFocusArea.content,
        debugLabel: 'tv_library_action_$label',
        onTap: onTap,
        builder: (context, focused) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.22)
                  : primary
                  ? AppVisualTokens.primaryBlue
                  : Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused
                    ? Colors.white.withValues(alpha: 0.85)
                    : primary
                    ? const Color(0x44FFFFFF)
                    : const Color(0x18FFFFFF),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TvLibraryVideoCard extends StatelessWidget {
  const _TvLibraryVideoCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.progressMs,
    required this.durationMs,
    required this.autofocus,
    required this.debugLabel,
    required this.onTap,
    this.durationLabel,
    this.onFocusChange,
    this.removeKey,
    this.onRemove,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final int progressMs;
  final int durationMs;
  final bool autofocus;
  final String debugLabel;
  final VoidCallback onTap;
  final String? durationLabel;
  final ValueChanged<bool>? onFocusChange;
  final Key? removeKey;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final progress = durationMs <= 0
        ? 0.0
        : (progressMs / durationMs).clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(
      builder: (context, _) {
        final cacheWidth = _tvLibraryCoverCacheWidth(
          context,
          _tvLibraryCoverDecodeLogicalWidth,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: TvFocusableSurface(
                autofocus: autofocus,
                scale: 1.07,
                borderRadius: AppVisualTokens.contentRadius,
                focusArea: TvFocusArea.content,
                debugLabel: debugLabel,
                onFocusChange: onFocusChange,
                onTap: onTap,
                builder: (context, focused) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          foregroundDecoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              AppVisualTokens.contentRadius,
                            ),
                            border: Border.all(color: visualTheme.imageOutline),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppVisualTokens.contentRadius,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(
                                  color: visualTheme.surfaceRaised,
                                  child: coverUrl.isEmpty
                                      ? Icon(
                                          Icons.video_library_outlined,
                                          color: visualTheme.textTertiary,
                                          size: 42,
                                        )
                                      : Image.network(
                                          coverUrl,
                                          fit: BoxFit.cover,
                                          cacheWidth: cacheWidth,
                                          gaplessPlayback: true,
                                          errorBuilder: (_, _, _) => ColoredBox(
                                            color: visualTheme.surfaceRaised,
                                            child: Icon(
                                              Icons.broken_image_outlined,
                                              color: visualTheme.textTertiary,
                                              size: 36,
                                            ),
                                          ),
                                        ),
                                ),
                                if (progress > 0)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 4,
                                      backgroundColor: Colors.black.withValues(
                                        alpha: 0.42,
                                      ),
                                      color: AppVisualTokens.primaryBlue,
                                    ),
                                  ),
                                if (durationLabel != null &&
                                    durationLabel!.isNotEmpty)
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Container(
                                      margin: const EdgeInsets.all(7),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.68,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        durationLabel!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: focused
                              ? visualTheme.textPrimary
                              : visualTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: focused
                              ? FontWeight.w800
                              : FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: visualTheme.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 8,
                right: 8,
                child: _TvLibraryRemoveButton(key: removeKey, onTap: onRemove!),
              ),
          ],
        );
      },
    );
  }
}

class _TvLibraryRemoveButton extends StatelessWidget {
  const _TvLibraryRemoveButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      width: 42,
      height: 42,
      child: TvFocusableSurface(
        useOverlayLift: false,
        focusPadding: 0,
        scale: 1.06,
        borderRadius: 10,
        focusArea: TvFocusArea.content,
        debugLabel: 'tv_library_remove_watch_later',
        onTap: onTap,
        builder: (context, focused) {
          return Tooltip(
            message: '移出稍后再看',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: focused
                    ? visualTheme.destructive.withValues(alpha: 0.92)
                    : visualTheme.scrim.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused
                      ? visualTheme.destructive
                      : visualTheme.glassBorder,
                ),
              ),
              child: const Icon(
                Icons.remove_circle_outline_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TvLibraryLoadMoreTile extends StatelessWidget {
  const _TvLibraryLoadMoreTile({
    super.key,
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return TvFocusableSurface(
      scale: 1.07,
      borderRadius: AppVisualTokens.contentRadius,
      focusArea: TvFocusArea.content,
      debugLabel: 'tv_library_load_more',
      onTap: loading ? () {} : onTap,
      builder: (context, focused) {
        return Material(
          color: visualTheme.surface,
          borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
          clipBehavior: Clip.antiAlias,
          child: AnimatedContainer(
            duration: AppVisualTokens.motionDuration(
              context,
              AppVisualTokens.tvFocusDuration,
            ),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(
                AppVisualTokens.contentRadius,
              ),
              border: Border.all(color: visualTheme.imageOutline),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppVisualTokens.primaryBlue,
                      ),
                    )
                  else
                    Icon(
                      Icons.expand_more_rounded,
                      color: visualTheme.textSecondary,
                      size: 32,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    loading ? '加载中' : '加载更多',
                    style: TextStyle(
                      color: visualTheme.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
