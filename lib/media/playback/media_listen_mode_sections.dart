import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vesper_player/vesper_player.dart';

import '../design/app_visual_theme.dart';
import '../models/media_detail.dart';
import '../tv/media_tv_focusable.dart';
import 'media_listen_mode_transport.dart';

enum MediaListenSection { subtitles, episodes }

final class MediaListenPhoneTabs extends StatelessWidget {
  const MediaListenPhoneTabs({
    super.key,
    required this.section,
    required this.onChanged,
  });

  final MediaListenSection section;
  final ValueChanged<MediaListenSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MediaListenPhoneTab(
          label: '字幕',
          selected: section == MediaListenSection.subtitles,
          onTap: () => onChanged(MediaListenSection.subtitles),
        ),
        const SizedBox(width: 42),
        _MediaListenPhoneTab(
          label: '合集',
          selected: section == MediaListenSection.episodes,
          onTap: () => onChanged(MediaListenSection.episodes),
        ),
      ],
    );
  }
}

final class MediaListenSubtitleFocus extends StatelessWidget {
  const MediaListenSubtitleFocus({
    super.key,
    required this.subtitleState,
    required this.title,
    required this.isTv,
  });

  final VesperSubtitleState subtitleState;
  final String title;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Align(
      key: const ValueKey<String>('listen-subtitle-focus'),
      alignment: isTv ? Alignment.topLeft : Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: isTv ? 28 : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isTv
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Text(
              '正在播放',
              style: TextStyle(
                color: AppVisualTokens.primaryBlue,
                fontSize: isTv ? 15 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: isTv ? 18 : 12),
            Text(
              title,
              maxLines: isTv ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              textAlign: isTv ? TextAlign.left : TextAlign.center,
              style: TextStyle(
                color: visualTheme.textPrimary,
                fontSize: isTv ? 34 : 19,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: isTv ? 22 : 14),
            Text(
              _subtitleStatusLabel(subtitleState),
              style: TextStyle(
                color: visualTheme.textTertiary,
                fontSize: isTv ? 17 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class MediaListenPhoneEpisodes extends StatelessWidget {
  const MediaListenPhoneEpisodes({
    super.key,
    required this.entries,
    required this.selectedEntryId,
    required this.onSelectEntry,
  });

  final List<MediaPlaybackEntry> entries;
  final String selectedEntryId;
  final Future<void> Function(MediaPlaybackEntry entry) onSelectEntry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('listen-phone-episodes'),
      children: [
        for (final entry in entries)
          _MediaListenPhoneEpisodeRow(
            entry: entry,
            selected: entry.entryId == selectedEntryId,
            onTap: () => unawaited(onSelectEntry(entry)),
          ),
      ],
    );
  }
}

final class MediaListenTvEpisodes extends StatelessWidget {
  const MediaListenTvEpisodes({
    super.key,
    required this.entries,
    required this.selectedEntryId,
    required this.onSelectEntry,
  });

  final List<MediaPlaybackEntry> entries;
  final String selectedEntryId;
  final Future<void> Function(MediaPlaybackEntry entry) onSelectEntry;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const ValueKey<String>('listen-tv-episodes'),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected = entry.entryId == selectedEntryId;
        return _MediaListenTvEpisodeRow(
          entry: entry,
          selected: selected,
          autofocus: selected,
          onTap: () => unawaited(onSelectEntry(entry)),
        );
      },
    );
  }
}

final class MediaListenTvTab extends StatelessWidget {
  const MediaListenTvTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return TvFocusable(
      debugLabel: 'tv_listen_tab_$label',
      focusArea: TvFocusArea.playbackControls,
      scale: 1.04,
      showGlow: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? visualTheme.textPrimary
                    : visualTheme.textTertiary,
                fontSize: 21,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: AppVisualTokens.motionDuration(
                context,
                AppVisualTokens.tvFocusDuration,
              ),
              width: selected ? 38 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: AppVisualTokens.primaryBlue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class MediaListenTvAction extends StatelessWidget {
  const MediaListenTvAction({
    super.key,
    required this.debugLabel,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String debugLabel;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return TvFocusable(
      debugLabel: debugLabel,
      focusArea: TvFocusArea.playbackControls,
      scale: 1.035,
      focusCornerRadius: AppVisualTokens.contentRadius,
      baseCornerRadius: AppVisualTokens.contentRadius,
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
          border: Border.all(color: visualTheme.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: visualTheme.textPrimary),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: visualTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MediaListenPhoneTab extends StatelessWidget {
  const _MediaListenPhoneTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? visualTheme.textPrimary
                    : visualTheme.textTertiary,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: AppVisualTokens.motionDuration(
                context,
                const Duration(milliseconds: 160),
              ),
              width: selected ? 24 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: AppVisualTokens.primaryBlue,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MediaListenPhoneEpisodeRow extends StatelessWidget {
  const _MediaListenPhoneEpisodeRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final MediaPlaybackEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppVisualTokens.primaryBlue.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
          child: SizedBox(
            height: 54,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 3,
                  height: selected ? 28 : 0,
                  color: AppVisualTokens.primaryBlue,
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 28,
                  child: Text(
                    entry.pageNumber.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: selected
                          ? AppVisualTokens.primaryBlue
                          : visualTheme.textTertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: visualTheme.textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatMediaListenSeconds(entry.durationSeconds),
                  style: TextStyle(color: visualTheme.textTertiary),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _MediaListenTvEpisodeRow extends StatelessWidget {
  const _MediaListenTvEpisodeRow({
    required this.entry,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  final MediaPlaybackEntry entry;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return TvFocusable(
      debugLabel: 'tv_listen_episode_${entry.entryId}',
      focusArea: TvFocusArea.playbackControls,
      autofocus: autofocus,
      scale: 1.025,
      focusCornerRadius: AppVisualTokens.contentRadius,
      baseCornerRadius: AppVisualTokens.contentRadius,
      onTap: onTap,
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: selected
              ? AppVisualTokens.primaryBlue.withValues(alpha: 0.18)
              : visualTheme.surface.withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
          border: Border(
            left: BorderSide(
              color: selected
                  ? AppVisualTokens.primaryBlue
                  : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 18),
            SizedBox(
              width: 42,
              child: Text(
                entry.pageNumber.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: selected
                      ? AppVisualTokens.primaryBlue
                      : visualTheme.textTertiary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: visualTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              formatMediaListenSeconds(entry.durationSeconds),
              style: TextStyle(
                color: selected
                    ? visualTheme.textPrimary
                    : visualTheme.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}

String _subtitleStatusLabel(VesperSubtitleState state) {
  if (state.catalogError case final error?) {
    final message = error.message.trim();
    return message.isEmpty ? '字幕暂不可用' : message;
  }
  return switch (state.catalogState) {
    VesperSubtitleCatalogState.loading => '字幕正在准备',
    VesperSubtitleCatalogState.ready when state.selectableTrackCount > 0 =>
      '字幕已就绪',
    VesperSubtitleCatalogState.ready => '当前视频没有可用字幕',
    VesperSubtitleCatalogState.failed => '字幕暂不可用',
    VesperSubtitleCatalogState.unavailable => '当前视频没有可用字幕',
    VesperSubtitleCatalogState.unknown => '字幕状态未知',
  };
}
