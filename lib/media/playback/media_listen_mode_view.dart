import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vesper_player/vesper_player.dart';

import '../design/app_visual_theme.dart';
import '../models/media_detail.dart';
import 'media_listen_mode_sections.dart';
import 'media_listen_mode_transport.dart';
import 'media_listen_mode_visuals.dart';

/// Audio-focused presentation for an existing playback session.
///
/// This widget deliberately owns presentation only. Playback, source changes,
/// history, and recovery stay with the page's existing controller and view
/// model, so entering and leaving listen mode does not rebuild the session.
final class MediaListenModeView extends StatefulWidget {
  const MediaListenModeView({
    super.key,
    required this.controller,
    required this.snapshot,
    required this.detail,
    required this.selectedEntry,
    required this.isTv,
    required this.onReturnToVideo,
    required this.onSelectEntry,
    required this.onSeek,
    this.onOpenSubtitleSettings,
  });

  final VesperPlayerController controller;
  final VesperPlayerSnapshot snapshot;
  final MediaDetail detail;
  final MediaPlaybackEntry selectedEntry;
  final bool isTv;
  final VoidCallback onReturnToVideo;
  final Future<void> Function(MediaPlaybackEntry entry) onSelectEntry;
  final ValueChanged<double> onSeek;
  final VoidCallback? onOpenSubtitleSettings;

  @override
  State<MediaListenModeView> createState() => _MediaListenModeViewState();
}

final class _MediaListenModeViewState extends State<MediaListenModeView> {
  MediaListenSection _section = MediaListenSection.subtitles;

  bool get _isPlaying =>
      widget.snapshot.playbackState == VesperPlaybackState.playing;

  int get _selectedEntryIndex => widget.detail.pages.indexWhere(
    (entry) => entry.entryId == widget.selectedEntry.entryId,
  );

  double get _displayedRatio {
    final timeline = widget.snapshot.timeline;
    final ratio = timeline.displayedRatio;
    if (ratio != null && ratio.isFinite) {
      return ratio.clamp(0.0, 1.0).toDouble();
    }
    final durationMs = timeline.durationMs ?? 0;
    return durationMs <= 0
        ? 0
        : (timeline.positionMs / durationMs).clamp(0.0, 1.0).toDouble();
  }

  String get _coverUrl {
    final entryCover = widget.selectedEntry.coverUrl?.trim();
    final raw = entryCover != null && entryCover.isNotEmpty
        ? entryCover
        : widget.detail.coverUrl.trim();
    return raw.startsWith('//') ? 'https:$raw' : raw;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppVisualTokens.tvTheme(),
      child: MediaListenAmbientBackground(
        coverUrl: _coverUrl,
        child: widget.isTv ? _buildTv(context) : _buildPhone(context),
      ),
    );
  }

  Widget _buildPhone(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableCoverWidth = math.max(0.0, constraints.maxWidth - 64);
          final preferredCoverSize = math.max(
            176.0,
            constraints.maxHeight * 0.37,
          );
          final coverSize = math.min(preferredCoverSize, availableCoverWidth);
          return Column(
            children: [
              MediaListenPhoneHeader(onReturnToVideo: widget.onReturnToVideo),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
                  child: Column(
                    children: [
                      MediaListenCover(
                        key: const ValueKey<String>('listen-mode-cover'),
                        url: _coverUrl,
                        size: coverSize,
                        semanticLabel: widget.detail.title,
                      ),
                      const SizedBox(height: 22),
                      Text(
                        widget.detail.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: visualTheme.textPrimary,
                          fontSize: 20,
                          height: 1.28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _metadataLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: visualTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (widget.detail.pages.length > 1)
                        MediaListenPhoneTabs(
                          section: _section,
                          onChanged: (section) {
                            setState(() => _section = section);
                          },
                        ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: AppVisualTokens.motionDuration(
                          context,
                          const Duration(milliseconds: 180),
                        ),
                        child:
                            _section == MediaListenSection.episodes &&
                                widget.detail.pages.length > 1
                            ? MediaListenPhoneEpisodes(
                                entries: widget.detail.pages,
                                selectedEntryId: widget.selectedEntry.entryId,
                                onSelectEntry: widget.onSelectEntry,
                              )
                            : MediaListenSubtitleFocus(
                                subtitleState: widget.snapshot.subtitleState,
                                title: widget.selectedEntry.title,
                                isTv: false,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              MediaListenTransport(
                snapshot: widget.snapshot,
                isPlaying: _isPlaying,
                ratio: _displayedRatio,
                isTv: false,
                onSeek: widget.onSeek,
                onTogglePlayback: _togglePlayback,
                onPrevious: _hasPreviousEntry ? _playPreviousEntry : null,
                onNext: _hasNextEntry ? _playNextEntry : null,
                onSubtitles: widget.onOpenSubtitleSettings,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTv(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 28, 48, 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.headphones_rounded,
                  size: 28,
                  color: visualTheme.textPrimary,
                ),
                const SizedBox(width: 12),
                Text(
                  '听视频',
                  style: TextStyle(
                    color: visualTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                MediaListenTvAction(
                  debugLabel: 'tv_listen_return_video',
                  icon: Icons.ondemand_video_rounded,
                  label: '返回视频',
                  onTap: widget.onReturnToVideo,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(flex: 5, child: _buildTvNowPlaying(visualTheme)),
                  const SizedBox(width: 56),
                  Flexible(flex: 6, child: _buildTvContext(visualTheme)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTvNowPlaying(AppVisualTheme visualTheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final transport = MediaListenTransport(
          snapshot: widget.snapshot,
          isPlaying: _isPlaying,
          ratio: _displayedRatio,
          isTv: true,
          onSeek: widget.onSeek,
          onTogglePlayback: _togglePlayback,
          onPrevious: _hasPreviousEntry ? _playPreviousEntry : null,
          onNext: _hasNextEntry ? _playNextEntry : null,
        );

        // Short TV viewports need the title area for the transport controls.
        // The context pane already carries the title and playback status.
        if (constraints.maxHeight < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, coverConstraints) {
                    final coverSize = math.max(
                      0.0,
                      math.min(
                        constraints.maxWidth,
                        coverConstraints.maxHeight,
                      ),
                    );
                    return Align(
                      alignment: Alignment.topLeft,
                      child: MediaListenCover(
                        key: const ValueKey<String>('listen-mode-cover'),
                        url: _coverUrl,
                        size: coverSize,
                        semanticLabel: widget.detail.title,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              transport,
            ],
          );
        }

        final coverSize = math.max(
          0.0,
          math.min(constraints.maxWidth, constraints.maxHeight * 0.62),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MediaListenCover(
              key: const ValueKey<String>('listen-mode-cover'),
              url: _coverUrl,
              size: coverSize,
              semanticLabel: widget.detail.title,
            ),
            const SizedBox(height: 18),
            Text(
              widget.detail.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: visualTheme.textPrimary,
                fontSize: 22,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _metadataLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: visualTheme.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            transport,
          ],
        );
      },
    );
  }

  Widget _buildTvContext(AppVisualTheme visualTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MediaListenTvTab(
              label: '字幕',
              selected: _section == MediaListenSection.subtitles,
              onTap: () {
                setState(() => _section = MediaListenSection.subtitles);
              },
            ),
            if (widget.detail.pages.length > 1) ...[
              const SizedBox(width: 22),
              MediaListenTvTab(
                label: '合集',
                selected: _section == MediaListenSection.episodes,
                onTap: () {
                  setState(() => _section = MediaListenSection.episodes);
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 28),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppVisualTokens.motionDuration(
              context,
              const Duration(milliseconds: 180),
            ),
            child:
                _section == MediaListenSection.episodes &&
                    widget.detail.pages.length > 1
                ? MediaListenTvEpisodes(
                    entries: widget.detail.pages,
                    selectedEntryId: widget.selectedEntry.entryId,
                    onSelectEntry: widget.onSelectEntry,
                  )
                : MediaListenSubtitleFocus(
                    subtitleState: widget.snapshot.subtitleState,
                    title: widget.selectedEntry.title,
                    isTv: true,
                  ),
          ),
        ),
      ],
    );
  }

  String get _metadataLabel {
    final owner = widget.detail.ownerName?.trim();
    final index = _selectedEntryIndex;
    final collection = widget.detail.pages.length > 1 && index >= 0
        ? '合集 ${index + 1} / ${widget.detail.pages.length}'
        : null;
    return <String>[
      if (owner != null && owner.isNotEmpty) owner,
      ?collection,
    ].join(' · ');
  }

  bool get _hasPreviousEntry => _selectedEntryIndex > 0;

  bool get _hasNextEntry =>
      _selectedEntryIndex >= 0 &&
      _selectedEntryIndex < widget.detail.pages.length - 1;

  void _playPreviousEntry() {
    if (_hasPreviousEntry) {
      unawaited(
        widget.onSelectEntry(widget.detail.pages[_selectedEntryIndex - 1]),
      );
    }
  }

  void _playNextEntry() {
    if (_hasNextEntry) {
      unawaited(
        widget.onSelectEntry(widget.detail.pages[_selectedEntryIndex + 1]),
      );
    }
  }

  void _togglePlayback() {
    if (widget.snapshot.isBuffering) {
      return;
    }
    if (_isPlaying) {
      unawaited(widget.controller.pause());
    } else {
      unawaited(widget.controller.play());
    }
  }
}
