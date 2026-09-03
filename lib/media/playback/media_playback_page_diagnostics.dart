part of 'media_playback_page.dart';

enum _PerformanceDiagnosticsDrawerAction { guidedAb }

extension _MediaPlaybackPageDiagnostics on _MediaPlaybackPageState {
  Future<void> _openPerformanceDiagnosticsSurface() async {
    if (!mediaPerformanceDiagnosticsAvailable ||
        _performanceDiagnosticsSurfaceOpen ||
        !mounted) {
      return;
    }
    _mutate(() {
      _performanceDiagnosticsSurfaceOpen = true;
    });
    _performanceDiagnosticsController.setDrawerVisible(true);
    _PerformanceDiagnosticsDrawerAction? action;
    try {
      action = await showGeneralDialog<_PerformanceDiagnosticsDrawerAction>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭性能诊断',
        barrierColor: const Color(0x99000000),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, _, _) {
          final isTv = _isTvMode;
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: isTv ? 520 : 440,
                child: FractionallySizedBox(
                  widthFactor: isTv ? 1 : 0.94,
                  child: _PerformanceDiagnosticsDrawer(
                    controller: _performanceDiagnosticsController,
                    isTv: isTv,
                    onClose: () => Navigator.of(dialogContext).pop(),
                    onRunGuidedAb: () => Navigator.of(
                      dialogContext,
                    ).pop(_PerformanceDiagnosticsDrawerAction.guidedAb),
                    onCopy: (json) => _copyPerformanceDiagnosticsReport(json),
                    onShare: (json) => _sharePerformanceDiagnosticsReport(json),
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
      );
    } finally {
      _performanceDiagnosticsController.setDrawerVisible(false);
      if (mounted) {
        _mutate(() {
          _performanceDiagnosticsSurfaceOpen = false;
        });
      }
    }
    if (action == _PerformanceDiagnosticsDrawerAction.guidedAb && mounted) {
      unawaited(_performanceDiagnosticsController.runGuidedAb());
    }
  }

  Future<void> _copyPerformanceDiagnosticsReport(String json) async {
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('诊断报告已复制')));
    }
  }

  Future<void> _sharePerformanceDiagnosticsReport(String json) async {
    try {
      await const MediaDiagnosticsReportShare().shareJson(
        json,
        clipboardOnly: _isTvMode,
      );
      if (mounted && _isTvMode) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('诊断报告已复制')));
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开系统分享面板')));
      }
    }
  }
}

class _PerformanceDiagnosticsDrawer extends StatelessWidget {
  const _PerformanceDiagnosticsDrawer({
    required this.controller,
    required this.isTv,
    required this.onClose,
    required this.onRunGuidedAb,
    required this.onCopy,
    required this.onShare,
  });

  final MediaPlaybackPerformanceDiagnosticsController controller;
  final bool isTv;
  final VoidCallback onClose;
  final VoidCallback onRunGuidedAb;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onShare;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      left: false,
      child: DecoratedBox(
        key: const ValueKey<String>('performance-diagnostics-drawer'),
        decoration: const BoxDecoration(
          color: Color(0xF51A1A1C),
          border: Border(left: BorderSide(color: Color(0x22FFFFFF))),
        ),
        child: SignalBuilder(
          builder: (context) {
            final state = controller.state.value;
            final report = state.report;
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(isTv ? 28 : 20, 16, 10, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.monitor_heart_outlined,
                        color: Colors.white,
                        size: 23,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '性能诊断',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0x1FFFFFFF)),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      isTv ? 28 : 20,
                      18,
                      isTv ? 28 : 20,
                      28,
                    ),
                    children: [
                      _DiagnosticsStatus(state: state),
                      const SizedBox(height: 18),
                      _DiagnosticsActions(
                        state: state,
                        onStart: () => unawaited(controller.start()),
                        onStop: () => unawaited(controller.stop()),
                        onRunGuidedAb: onRunGuidedAb,
                        onCancelGuided: controller.cancelGuidedCollection,
                      ),
                      const SizedBox(height: 24),
                      if (report == null)
                        const _DiagnosticsEmptyReport()
                      else ...[
                        _DiagnosticsReportSummary(report: report),
                        const SizedBox(height: 20),
                        _DiagnosticsCohortTable(report: report),
                        const SizedBox(height: 20),
                        _DiagnosticsPlaybackSummary(report: report),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => onCopy(report.toJson()),
                                icon: const Icon(Icons.copy_rounded),
                                label: const Text('复制 JSON'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => onShare(report.toJson()),
                                icon: Icon(
                                  isTv
                                      ? Icons.content_copy_rounded
                                      : Icons.ios_share_rounded,
                                ),
                                label: Text(isTv ? '复制报告' : '系统分享'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DiagnosticsStatus extends StatelessWidget {
  const _DiagnosticsStatus({required this.state});

  final MediaPerformanceDiagnosticsViewState state;

  @override
  Widget build(BuildContext context) {
    final color = state.errorCode == null
        ? const Color(0xFF69D8A3)
        : const Color(0xFFFFB36A);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              if (state.errorCode case final code?) ...[
                const SizedBox(height: 3),
                Text(
                  code,
                  style: const TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DiagnosticsActions extends StatelessWidget {
  const _DiagnosticsActions({
    required this.state,
    required this.onStart,
    required this.onStop,
    required this.onRunGuidedAb,
    required this.onCancelGuided,
  });

  final MediaPerformanceDiagnosticsViewState state;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRunGuidedAb;
  final VoidCallback onCancelGuided;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (!state.sessionActive)
          FilledButton.icon(
            key: const ValueKey<String>('start-performance-diagnostics'),
            onPressed: state.busy ? null : onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始'),
          )
        else
          FilledButton.icon(
            key: const ValueKey<String>('stop-performance-diagnostics'),
            onPressed: state.busy ? null : onStop,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('停止'),
          ),
        if (state.guidedActive)
          OutlinedButton.icon(
            key: const ValueKey<String>('cancel-guided-diagnostics'),
            onPressed: onCancelGuided,
            icon: const Icon(Icons.close_rounded),
            label: const Text('取消 A/B'),
          )
        else
          OutlinedButton.icon(
            key: const ValueKey<String>('start-guided-diagnostics'),
            onPressed: state.busy ? null : onRunGuidedAb,
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('引导 A/B'),
          ),
      ],
    );
  }
}

class _DiagnosticsEmptyReport extends StatelessWidget {
  const _DiagnosticsEmptyReport();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          '等待诊断快照',
          style: TextStyle(color: Color(0x99FFFFFF), fontSize: 14),
        ),
      ),
    );
  }
}

class _DiagnosticsReportSummary extends StatelessWidget {
  const _DiagnosticsReportSummary({required this.report});

  final VesperPerformanceDiagnosticsReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DiagnosticsSectionTitle('结论'),
        const SizedBox(height: 10),
        Text(
          _diagnosisLabel(report.diagnosis.kind.rawValue),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _DiagnosticsValueRow(
          label: '置信度',
          value: _confidenceLabel(report.diagnosis.confidence.rawValue),
        ),
        _DiagnosticsValueRow(label: '探针', value: report.probe.rawValue),
        _DiagnosticsValueRow(
          label: '帧预算',
          value: '${report.frameBudgetMs.toStringAsFixed(2)} ms',
        ),
        _DiagnosticsValueRow(
          label: '采集时长',
          value: '${(report.durationMs / 1000).toStringAsFixed(1)} s',
        ),
        _DiagnosticsValueRow(
          label: '接收 / 丢弃',
          value: '${report.acceptedEvents} / ${report.droppedEvents}',
        ),
        if (report.diagnosis.evidenceCodes.isNotEmpty)
          _DiagnosticsValueRow(
            label: '证据',
            value: report.diagnosis.evidenceCodes.join(', '),
          ),
      ],
    );
  }
}

class _DiagnosticsCohortTable extends StatelessWidget {
  const _DiagnosticsCohortTable({required this.report});

  final VesperPerformanceDiagnosticsReport report;

  @override
  Widget build(BuildContext context) {
    final off = report.cohorts['overlayInactive'];
    final on = report.cohorts['overlayActive'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DiagnosticsSectionTitle('帧表现'),
        const SizedBox(height: 10),
        _DiagnosticsCohortRow(label: '弹幕关闭', cohort: off),
        const Divider(height: 18, color: Color(0x18FFFFFF)),
        _DiagnosticsCohortRow(label: '弹幕开启', cohort: on),
      ],
    );
  }
}

class _DiagnosticsCohortRow extends StatelessWidget {
  const _DiagnosticsCohortRow({required this.label, required this.cohort});

  final String label;
  final VesperPerformanceFrameCohort? cohort;

  @override
  Widget build(BuildContext context) {
    final value = cohort;
    if (value == null) {
      return Text(label, style: const TextStyle(color: Colors.white));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label  ${value.sampleCount} 帧',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        _DiagnosticsValueRow(
          label: 'Jank',
          value: '${(value.jankRatio * 100).toStringAsFixed(1)}%',
        ),
        _DiagnosticsValueRow(
          label: '严重 Jank',
          value: '${(value.severeJankRatio * 100).toStringAsFixed(1)}%',
        ),
        _DiagnosticsValueRow(
          label: 'P95',
          value: '${value.p95LoadMs.toStringAsFixed(2)} ms',
        ),
      ],
    );
  }
}

class _DiagnosticsPlaybackSummary extends StatelessWidget {
  const _DiagnosticsPlaybackSummary({required this.report});

  final VesperPerformanceDiagnosticsReport report;

  @override
  Widget build(BuildContext context) {
    final playback = report.playback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DiagnosticsSectionTitle('播放压力'),
        const SizedBox(height: 10),
        _DiagnosticsValueRow(
          label: '掉帧',
          value: '${playback.droppedVideoFrames}',
        ),
        _DiagnosticsValueRow(
          label: '缓冲',
          value:
              '${playback.bufferingCount} 次 / ${(playback.bufferingDurationMs / 1000).toStringAsFixed(2)} s',
        ),
        _DiagnosticsValueRow(label: 'Stall', value: '${playback.stallCount}'),
      ],
    );
  }
}

class _DiagnosticsSectionTitle extends StatelessWidget {
  const _DiagnosticsSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xB3FFFFFF),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _DiagnosticsValueRow extends StatelessWidget {
  const _DiagnosticsValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

String _diagnosisLabel(String rawValue) => switch (rawValue) {
  'insufficientEvidence' => '样本不足',
  'noSignificantPressure' => '未发现明显帧压力',
  'overlayCorrelatedUiPressure' => '帧压力与 Overlay 活跃相关',
  'hostUiPressureUncorrelated' => '存在 UI 帧压力，未发现 Overlay 相关性',
  'playbackPressure' => '播放器侧存在播放压力',
  'mixedPressure' => 'UI 与播放器侧均存在压力',
  _ => rawValue,
};

String _confidenceLabel(String rawValue) => switch (rawValue) {
  'low' => '低',
  'medium' => '中',
  'high' => '高',
  _ => rawValue,
};
