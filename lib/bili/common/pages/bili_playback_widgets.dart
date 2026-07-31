part of 'bili_playback_page.dart';

class _TuningOptionButton extends StatelessWidget {
  const _TuningOptionButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final color = enabled
        ? selected
              ? AppVisualTokens.primaryBlue
              : visualTheme.textPrimary
        : visualTheme.textTertiary;
    return Material(
      color: selected
          ? Color.alphaBlend(
              AppVisualTokens.primaryBlue.withValues(alpha: 0.12),
              visualTheme.surfaceRaised,
            )
          : visualTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              fontSize: 14,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

class _CacheEntryButton extends StatelessWidget {
  const _CacheEntryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: visualTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              const Icon(
                Icons.download_for_offline_outlined,
                size: 20,
                color: AppVisualTokens.primaryBlue,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '缓存',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: visualTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: visualTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        color: visualTheme.textPrimary,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _PlaybackContextTabs extends StatelessWidget {
  const _PlaybackContextTabs({
    required this.controller,
    required this.replyCountLabel,
    required this.danmakuCountLabel,
  });

  final TabController controller;
  final String replyCountLabel;
  final String danmakuCountLabel;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: visualTheme.divider)),
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: TabBar(
                controller: controller,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                indicatorColor: AppVisualTokens.primaryBlue,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 3,
                labelColor: AppVisualTokens.primaryBlue,
                unselectedLabelColor: visualTheme.textSecondary,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                splashBorderRadius: BorderRadius.circular(8),
                labelStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
                unselectedLabelStyle: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                tabs: [
                  const _PlaybackTab(
                    key: ValueKey<String>('playback-intro-tab'),
                    label: '简介',
                  ),
                  _PlaybackTab(
                    key: const ValueKey<String>('playback-comments-tab'),
                    label: '评论 $replyCountLabel',
                  ),
                ],
              ),
            ),
            _DanmakuEntryPill(danmakuCountLabel: danmakuCountLabel),
          ],
        ),
      ),
    );
  }
}

class _PlaybackTab extends StatelessWidget {
  const _PlaybackTab({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _CollapsedPlaybackBar extends StatelessWidget {
  const _CollapsedPlaybackBar({
    required this.title,
    required this.isPlaying,
    required this.onBack,
    required this.onHome,
    required this.onPlayPause,
    required this.onMore,
  });

  final String title;
  final bool isPlaying;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onPlayPause;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      key: const ValueKey<String>('playback-collapsed-bar'),
      decoration: BoxDecoration(
        color: visualTheme.surface,
        border: Border(bottom: BorderSide(color: visualTheme.divider)),
        boxShadow: [
          BoxShadow(
            color: visualTheme.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _CollapsedBarIcon(icon: Icons.arrow_back_rounded, onTap: onBack),
              _CollapsedBarIcon(icon: Icons.home_outlined, onTap: onHome),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onPlayPause,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: AppVisualTokens.primaryBlue,
                          size: 34,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isPlaying ? '正在播放' : '继续播放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: visualTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _CollapsedBarIcon(icon: Icons.more_vert_rounded, onTap: onMore),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsedBarIcon extends StatelessWidget {
  const _CollapsedBarIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return IconButton(
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
      icon: Icon(icon, color: visualTheme.textPrimary, size: 30),
    );
  }
}

class _PlaybackBottomSheetScaffold extends StatelessWidget {
  const _PlaybackBottomSheetScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: visualTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 30,
                    color: visualTheme.textTertiary,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Divider(height: 1, color: visualTheme.divider),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

final class _BiliStageDeviceControls
    implements vesper_ui.VesperPlayerDeviceControls {
  const _BiliStageDeviceControls();

  @override
  Future<double?> currentBrightnessRatio() {
    return BiliDeviceControls.instance.getBrightness();
  }

  @override
  Future<double?> setBrightnessRatio(double ratio) {
    return BiliDeviceControls.instance.setBrightness(ratio);
  }

  @override
  Future<double?> currentVolumeRatio() {
    return BiliDeviceControls.instance.getVolume();
  }

  @override
  Future<double?> setVolumeRatio(double ratio) {
    return BiliDeviceControls.instance.setVolume(ratio);
  }
}
