part of 'bili_playback_page.dart';

extension _BiliPlaybackTuning on _BiliPlaybackPageState {
  Widget _buildTuningPanel(
    BuildContext context,
    VesperPlayerController controller,
    VesperPlayerSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final timeline = snapshot.timeline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelHeading(title: '播放设置'),
        const SizedBox(height: 16),
        Text(
          '分辨率',
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF162033),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _buildQualitySelector(context, snapshot),
        const SizedBox(height: 18),
        Text(
          '播放策略',
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF162033),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _buildCodecStrategySelector(snapshot),
        const SizedBox(height: 18),
        Text(
          '倍速',
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF162033),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _buildPlaybackRateSelector(snapshot),
        const SizedBox(height: 18),
        Text(
          '离线缓存',
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF162033),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _CacheEntryButton(
          onTap: () => unawaited(_openCacheSurfaceFromSettings(context)),
        ),
        const SizedBox(height: 18),
        _InfoBlock(
          title: '会话信息',
          children: [
            _SnapshotRow(label: '播放状态', value: _playbackStateLabel(snapshot)),
            _SnapshotRow(
              label: '时间线',
              value:
                  '${biliFormatDurationSeconds(timeline.positionMs ~/ 1000)} / ${biliFormatDurationSeconds((timeline.durationMs ?? 0) ~/ 1000)}',
            ),
            _SnapshotRow(
              label: '当前链路',
              value: _resolvedPlayback?.transportLabel ?? '未知',
            ),
            _SnapshotRow(label: '资源地址', value: _resolvedPlayback?.uri ?? '未知'),
            if ((_resolvedPlayback?.debugPath ?? '').isNotEmpty)
              _SnapshotRow(
                label: 'Manifest',
                value: _resolvedPlayback!.debugPath!,
              ),
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

  Widget _buildQualitySelector(
    BuildContext context,
    VesperPlayerSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final biliTracks = _playbackSelectionTracks(snapshot);
    final availableIds = _availableBiliQualityIds(biliTracks);
    final selectedId = _selectedBiliQualityId;
    if (availableIds.isEmpty) {
      return Text(
        '当前播放链路无可选清晰度。',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF8B9098),
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: availableIds
          .map((qualityId) {
            final label = _biliQualityLabelFromQualityId(qualityId);
            final isSelected = selectedId == qualityId;
            return _TuningOptionButton(
              label: label ?? '$qualityId',
              selected: isSelected,
              onTap: () => unawaited(_selectBiliQuality(qualityId)),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildCodecStrategySelector(VesperPlayerSnapshot snapshot) {
    final selectedStrategy = _selectedCodecStrategy;
    final biliTracks = _playbackSelectionTracks(snapshot);
    final selectedId = _selectedBiliQualityId;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: BiliCodecStrategy.values
          .map((strategy) {
            final enabled =
                strategy == BiliCodecStrategy.defaultStrategy ||
                _hasTrackForSelection(biliTracks, selectedId, strategy);
            final selected = strategy == selectedStrategy;
            return _TuningOptionButton(
              label: strategy.label,
              selected: selected,
              enabled: enabled,
              onTap: () => unawaited(_selectCodecStrategy(strategy)),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildPlaybackRateSelector(VesperPlayerSnapshot snapshot) {
    final rate = snapshot.playbackRate;
    final rates = _playbackRates(snapshot);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rates
          .map((option) {
            final selected = (option - rate).abs() < 0.05;
            return _TuningOptionButton(
              label: '${option}x',
              selected: selected,
              onTap: () => unawaited(_setPlaybackRate(option)),
            );
          })
          .toList(growable: false),
    );
  }
}
