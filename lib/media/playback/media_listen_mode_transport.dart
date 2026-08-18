import 'package:material_ui/material_ui.dart';
import 'package:vesper_player/vesper_player.dart';

import '../design/app_visual_theme.dart';
import '../tv/media_tv_focusable.dart';

final class MediaListenTransport extends StatelessWidget {
  const MediaListenTransport({
    super.key,
    required this.snapshot,
    required this.isPlaying,
    required this.ratio,
    required this.isTv,
    required this.onSeek,
    required this.onTogglePlayback,
    this.onPrevious,
    this.onNext,
    this.onSubtitles,
  });

  final VesperPlayerSnapshot snapshot;
  final bool isPlaying;
  final double ratio;
  final bool isTv;
  final ValueChanged<double> onSeek;
  final VoidCallback onTogglePlayback;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSubtitles;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final timeline = snapshot.timeline;
    final enabled = timeline.isSeekable && (timeline.durationMs ?? 0) > 0;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              formatMediaListenMilliseconds(timeline.positionMs),
              style: TextStyle(
                color: visualTheme.textSecondary,
                fontSize: isTv ? 14 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: isTv ? 4 : 3,
                  activeTrackColor: AppVisualTokens.primaryBlue,
                  inactiveTrackColor: visualTheme.divider,
                  thumbColor: AppVisualTokens.primaryBlue,
                  overlayColor: AppVisualTokens.primaryBlue20,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: isTv ? 6 : 5,
                  ),
                  overlayShape: RoundSliderOverlayShape(
                    overlayRadius: isTv ? 14 : 12,
                  ),
                ),
                child: Slider(value: ratio, onChanged: enabled ? onSeek : null),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatMediaListenMilliseconds(timeline.durationMs ?? 0),
              style: TextStyle(
                color: visualTheme.textSecondary,
                fontSize: isTv ? 14 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: isTv ? 8 : 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MediaListenControlButton(
              semanticLabel: '上一集',
              icon: Icons.skip_previous_rounded,
              isTv: isTv,
              onTap: onPrevious,
            ),
            SizedBox(width: isTv ? 22 : 24),
            _MediaListenControlButton(
              key: const ValueKey<String>('listen-play-pause'),
              semanticLabel: isPlaying ? '暂停' : '播放',
              icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              isTv: isTv,
              primary: true,
              autofocus: isTv,
              onTap: onTogglePlayback,
            ),
            SizedBox(width: isTv ? 22 : 24),
            _MediaListenControlButton(
              semanticLabel: '下一集',
              icon: Icons.skip_next_rounded,
              isTv: isTv,
              onTap: onNext,
            ),
          ],
        ),
        if (!isTv && onSubtitles != null) ...[
          const SizedBox(height: 4),
          IconButton(
            tooltip: '字幕设置',
            onPressed: onSubtitles,
            color: visualTheme.textSecondary,
            icon: const Icon(Icons.subtitles_outlined, size: 21),
          ),
        ],
      ],
    );
    if (isTv) {
      return content;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppVisualTokens.darkBackground.withValues(alpha: 0.88),
        border: Border(top: BorderSide(color: visualTheme.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
        child: content,
      ),
    );
  }
}

final class _MediaListenControlButton extends StatelessWidget {
  const _MediaListenControlButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.isTv,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
  });

  final String semanticLabel;
  final IconData icon;
  final bool isTv;
  final VoidCallback? onTap;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final size = primary ? (isTv ? 66.0 : 64.0) : (isTv ? 48.0 : 46.0);
    final button = Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.34 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: primary
                ? visualTheme.textPrimary
                : visualTheme.surfaceRaised.withValues(alpha: 0.74),
            shape: BoxShape.circle,
            border: primary && isTv
                ? Border.all(color: AppVisualTokens.primaryBlue, width: 3)
                : null,
          ),
          child: Icon(
            icon,
            size: primary ? (isTv ? 34 : 32) : (isTv ? 28 : 26),
            color: primary
                ? AppVisualTokens.darkBackground
                : visualTheme.textPrimary,
          ),
        ),
      ),
    );
    if (isTv) {
      return TvFocusable(
        debugLabel: 'tv_listen_$semanticLabel',
        focusArea: TvFocusArea.playbackControls,
        autofocus: autofocus,
        scale: primary ? 1.08 : 1.06,
        showGlow: primary,
        focusCornerRadius: size / 2,
        baseCornerRadius: size / 2,
        onTap: onTap ?? () {},
        child: button,
      );
    }
    return IconButton(
      tooltip: semanticLabel,
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      icon: button,
    );
  }
}

String formatMediaListenMilliseconds(int milliseconds) {
  return formatMediaListenSeconds((milliseconds / 1000).floor());
}

String formatMediaListenSeconds(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final remainingSeconds = safeSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainingSeconds.toString().padLeft(2, '0')}';
}
