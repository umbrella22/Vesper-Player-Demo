import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_player/vesper_player.dart';

import '../models/resolved_media.dart';
import 'media_playback_widgets.dart';

/// codec 子选项（播放策略区）：标签 + 当前清晰度下是否可用。
/// [id] 是策略身份（同一策略组的轨道共享），选择与匹配按 id 进行；
/// [label] 是展示文案（可独立于身份，如 Dolby Vision 归 HEVC 组）。
final class TuningCodecOption {
  const TuningCodecOption({
    required this.id,
    required this.label,
    required this.enabled,
    this.supportingText,
  });

  final String id;
  final String label;
  final bool enabled;
  final String? supportingText;
}

/// 通用音画调校面板：分辨率（质量选项）/ 播放策略（codec）/ 倍速 / 字幕。
///
/// 所有数据与回调由调用方（平台页面）组装，本面板不接触平台类型：
/// - 质量选项来自 [MediaQualityOption]（适配器分组）
/// - codec 策略来自 [TuningCodecOption]（调用方按平台能力计算 enabled）
/// - 离线缓存入口经 [cacheEntry] 槽位注入（下载保持 app 级）
class MediaPlaybackTuningPanel extends StatelessWidget {
  const MediaPlaybackTuningPanel({
    super.key,
    required this.snapshot,
    required this.qualityOptions,
    required this.qualitySupportingTextFor,
    required this.selectedQualityOptionId,
    required this.codecOptions,
    required this.selectedCodecIdentity,
    required this.playbackRates,
    required this.subtitleTracks,
    required this.subtitleSelection,
    required this.subtitleSelectionEnabled,
    required this.subtitleEmptyMessage,
    required this.playbackStateLabel,
    required this.timelineLabel,
    required this.transportLabel,
    required this.resolvedUri,
    this.debugPath,
    this.cacheEntry,
    required this.onSelectQuality,
    required this.onSelectCodec,
    required this.onSetRate,
    required this.onSelectSubtitle,
  });

  final VesperPlayerSnapshot snapshot;
  final List<MediaQualitySelectionOption> qualityOptions;
  final String? Function(MediaQualitySelectionOption option)
  qualitySupportingTextFor;
  final String? selectedQualityOptionId;
  final List<TuningCodecOption> codecOptions;
  final String? selectedCodecIdentity;
  final List<double> playbackRates;
  final List<VesperMediaTrack> subtitleTracks;
  final VesperTrackSelection subtitleSelection;
  final bool subtitleSelectionEnabled;
  final String? subtitleEmptyMessage;
  final String playbackStateLabel;
  final String timelineLabel;
  final String? transportLabel;
  final String? resolvedUri;
  final String? debugPath;
  final Widget? cacheEntry;
  final ValueChanged<String?> onSelectQuality;
  final ValueChanged<String?> onSelectCodec;
  final ValueChanged<double> onSetRate;
  final ValueChanged<VesperTrackSelection> onSelectSubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelHeading(title: '播放设置'),
        const SizedBox(height: 16),
        Text(
          '分辨率',
          style: theme.textTheme.titleMedium?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _buildQualitySelector(context),
        if (codecOptions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '播放策略',
            style: theme.textTheme.titleMedium?.copyWith(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _buildCodecStrategySelector(),
        ],
        const SizedBox(height: 18),
        Text(
          '倍速',
          style: theme.textTheme.titleMedium?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _buildPlaybackRateSelector(),
        const SizedBox(height: 18),
        Text(
          '字幕',
          style: theme.textTheme.titleMedium?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _buildSubtitleSelector(context),
        if (cacheEntry != null) ...[
          const SizedBox(height: 18),
          Text(
            '离线缓存',
            style: theme.textTheme.titleMedium?.copyWith(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          cacheEntry!,
        ],
        const SizedBox(height: 18),
        _InfoBlock(
          title: '会话信息',
          children: [
            _SnapshotRow(label: '播放状态', value: playbackStateLabel),
            _SnapshotRow(label: '时间线', value: timelineLabel),
            _SnapshotRow(label: '当前链路', value: transportLabel ?? '未知'),
            _SnapshotRow(label: '资源地址', value: resolvedUri ?? '未知'),
            if ((debugPath ?? '').isNotEmpty)
              _SnapshotRow(label: 'Manifest', value: debugPath!),
            if (snapshot.effectiveVideoTrackId != null)
              _SnapshotRow(
                label: '实际轨道',
                value: snapshot.effectiveVideoTrackId!,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildQualitySelector(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    if (qualityOptions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TuningOptionButton(
            key: const ValueKey<String>('tuning-quality-auto'),
            label: '自动',
            selected: selectedQualityOptionId == null,
            onTap: () => onSelectQuality(null),
          ),
          const SizedBox(height: 8),
          Text(
            '当前播放链路无可选清晰度。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: visualTheme.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TuningOptionButton(
          key: const ValueKey<String>('tuning-quality-auto'),
          label: '自动',
          selected: selectedQualityOptionId == null,
          onTap: () => onSelectQuality(null),
        ),
        for (final option in qualityOptions)
          TuningOptionButton(
            key: ValueKey<String>('tuning-quality-${option.id}'),
            label: option.label,
            selected: selectedQualityOptionId == option.id,
            enabled: option.canSelect,
            supportingText: qualitySupportingTextFor(option),
            onTap: () => onSelectQuality(option.id),
          ),
      ],
    );
  }

  Widget _buildCodecStrategySelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: codecOptions
          .map((option) {
            // 选中与切换都按策略身份（id）进行；展示 label 独立。
            final selected = option.id == selectedCodecIdentity;
            return TuningOptionButton(
              label: option.label,
              selected: selected,
              enabled: option.enabled,
              supportingText: option.supportingText,
              onTap: () => onSelectCodec(selected ? null : option.id),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildPlaybackRateSelector() {
    final rate = snapshot.playbackRate;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: playbackRates
          .map((option) {
            final selected = (option - rate).abs() < 0.05;
            return TuningOptionButton(
              label: '${option}x',
              selected: selected,
              onTap: () => onSetRate(option),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildSubtitleSelector(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    if (subtitleTracks.isEmpty) {
      return Text(
        subtitleEmptyMessage ?? '当前视频没有可用字幕。',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: visualTheme.textTertiary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final selection = subtitleSelection;
    final selectedTrackId = selection.mode == VesperTrackSelectionMode.track
        ? selection.trackId
        : null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TuningOptionButton(
          label: '关闭',
          selected: selection.mode == VesperTrackSelectionMode.disabled,
          enabled: subtitleSelectionEnabled,
          onTap: () => onSelectSubtitle(const VesperTrackSelection.disabled()),
        ),
        TuningOptionButton(
          label: '自动',
          selected: selection.mode == VesperTrackSelectionMode.auto,
          enabled: subtitleSelectionEnabled,
          onTap: () => onSelectSubtitle(const VesperTrackSelection.auto()),
        ),
        for (final track in subtitleTracks)
          TuningOptionButton(
            label: _subtitleTrackLabel(track),
            selected: track.id == selectedTrackId,
            enabled: subtitleSelectionEnabled,
            onTap: () => onSelectSubtitle(VesperTrackSelection.track(track.id)),
          ),
      ],
    );
  }

  String _subtitleTrackLabel(VesperMediaTrack track) {
    final label = track.label?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    final language = track.language?.trim();
    return language == null || language.isEmpty ? '字幕' : language;
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: visualTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: visualTheme.textTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: visualTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
