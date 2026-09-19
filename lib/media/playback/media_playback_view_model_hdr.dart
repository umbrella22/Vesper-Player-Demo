part of 'media_playback_view_model.dart';

/// HDR 表达链路：源标识 → 可播性 → 输出证据。
///
/// 三条信息分别来自不同证据源，任何一条都不能由另一条推导：
/// - 源标识来自清单解析（codec 字符串与清晰度选项），轨道声明阶段即可确定；
/// - 可播性来自轨道 `support`，与 `_trackSelectionAvailability` 同源；
/// - 输出确认需要 SDK 提供当前显示链路的实际证据，能力探测不足以确认。
///
/// 本扩展同时是播放页读取 HDR 表达的公开入口。
extension MediaPlaybackHdrView on MediaPlaybackViewModel {
  /// 清晰度按钮的 HDR 角标：源标识来自选项自身，确认态来自当前 HDR 状态。
  ///
  /// 只有该选项是当前生效档位、且输出已确认时，角标才点亮；其他档位一律是
  /// 未确认的源标识。
  TuningQualityHdrBadge? tuningHdrBadgeFor(MediaQualitySelectionOption option) {
    final declared = option.option;
    final qualityId = int.tryParse(declared.id);
    MediaHdrSource source = MediaHdrSource.none;
    for (final track in declared.tracks) {
      final trackSource = mediaHdrSourceForTrack(track, qualityId: qualityId);
      if (trackSource != MediaHdrSource.none) {
        source = trackSource;
        break;
      }
    }
    if (source == MediaHdrSource.none && qualityId != null) {
      source = switch (qualityId) {
        126 => MediaHdrSource.dolbyVision,
        125 => MediaHdrSource.hdr10,
        _ => MediaHdrSource.none,
      };
    }
    if (source == MediaHdrSource.none) {
      return null;
    }
    final label = switch (source) {
      MediaHdrSource.dolbyVision => 'DV',
      MediaHdrSource.hlg => 'HLG',
      _ => 'HDR',
    };
    return TuningQualityHdrBadge(
      label: label,
      confirmed:
          _selectedQualityOptionId.value == declared.id &&
          hdrStatus.isOutputConfirmed,
    );
  }

  /// 会话信息里的 HDR 行；无 HDR 源时返回 null（不渲染该行）。
  String? get hdrDiagnosticsLabel {
    final status = hdrStatus;
    return status.hasHdrSource ? status.diagnosticsLabel : null;
  }
}

extension _MediaPlaybackHdr on MediaPlaybackViewModel {
  /// HDR 原生帧处理不受支持时的告警处理。
  ///
  /// 与 `runtimeTrackRejected` 分开归类：这不是轨道被拒绝，而是 HDR 输出
  /// 通路不可用。因此不把轨道加入拒绝集合、不清空用户选择——设备可能仍能
  /// 用 SDR 通路播放同一档位。只更新输出证据并提示一次。
  ///
  /// 与轨道拒绝一致：只记录证据，不自动改选轨道。
  void _handleHdrCapabilityWarning(VesperCapabilityWarning warning) {
    final detail = switch (warning.recommendedPlaybackPath) {
      VesperRecommendedPlaybackPath.systemPlayer => '建议改用系统播放器链路',
      VesperRecommendedPlaybackPath.nativeFramePipeline => '建议改用原生帧处理链路',
    };
    final label = warning.message ?? '当前链路不支持该 HDR 格式的原生帧处理';
    if (!_hdrWarningsReported.add(label)) {
      return;
    }
    _emitMessage('$label（$detail）。当前画面可能以降级格式输出。');
    _refreshHdrStatusFromWarning(warning);
  }

  void _refreshHdrStatusFromWarning(VesperCapabilityWarning warning) {
    if (_isDisposed) {
      return;
    }
    final current = _hdrStatus.value;
    if (!current.hasHdrSource) {
      return;
    }
    // 告警只能把已确认降为未确认，不能反向确认输出。
    _hdrStatus.value = current.copyWith(
      output: MediaHdrOutputState.unconfirmed,
      outputDetail: '收到 HDR 能力告警',
    );
  }

  /// 由当前生效的视频轨道重建 HDR 状态。
  ///
  /// 在轨道变化（切分 P、重载、自动换轨、运行时拒绝）后调用；不发网络请求，
  /// 不阻塞播放。
  void _refreshHdrStatus(VesperPlayerSnapshot snapshot) {
    if (_isDisposed) {
      return;
    }
    final track = _effectiveVideoTrack(snapshot);
    if (track == null) {
      // 没有生效轨道证据时清空源标识，不把任意轨道标成 HDR。
      if (_hdrStatus.value != MediaHdrStatus.none) {
        _hdrStatus.value = MediaHdrStatus.none;
      }
      return;
    }
    final declaredOption = _declaredOptionForTrack(track);
    final qualityId = int.tryParse(declaredOption?.id ?? '');
    final source = mediaHdrSourceForTrack(track, qualityId: qualityId);
    final playability = switch (track.support.status) {
      VesperTrackSupportStatus.supported => MediaHdrPlayability.playable,
      VesperTrackSupportStatus.unknown => MediaHdrPlayability.unknown,
      VesperTrackSupportStatus.exceedsCapabilities ||
      VesperTrackSupportStatus.unsupported => MediaHdrPlayability.unplayable,
    };
    final probe = _hdrCapabilityProbe;
    if (probe == null) {
      // 尚未（或无法）探测：源与可播性照常表达，输出保持未确认。
      _hdrStatus.value = MediaHdrStatus(
        source: source,
        playability: playability,
        output: MediaHdrOutputState.unknown,
        outputDetail: '未获取到能力探测结果',
        sourceLabel: declaredOption?.label,
      );
      return;
    }
    _hdrStatus.value = mediaHdrStatusFromProbe(
      probe: probe,
      source: source,
      playability: playability,
      sourceLabel: declaredOption?.label,
    );
  }

  /// 原生轨道对应的声明清晰度选项；无匹配时返回 null。
  MediaQualityOption? _declaredOptionForTrack(VesperMediaTrack track) {
    final options = availableQualityOptions();
    if (options.isEmpty) {
      return null;
    }
    final optionId = adapter.qualityPolicy.qualityOptionIdForNativeTrack?.call(
      track,
      options,
    );
    if (optionId == null) {
      return null;
    }
    for (final option in options) {
      if (option.id == optionId) {
        return option;
      }
    }
    return null;
  }

  /// 同一源和实际轨道只探测一次；新代次立即丢弃旧结果，包括 A→B→A。
  void _syncHdrCapability(VesperPlayerSnapshot snapshot) {
    if (_isDisposed) return;
    final controller = _controller;
    final resolved = _resolvedPlayback.peek();
    final track = _effectiveVideoTrack(snapshot);
    if (_playbackSourceTransitionInFlight.value ||
        _playbackRecoveryInFlight ||
        _sourceMode != MediaPlaybackSourceMode.video ||
        track == null ||
        controller == null ||
        resolved == null) {
      if (_hdrProbeKey != null) _resetHdrStatus();
      return;
    }
    final key = (
      resolved,
      _sourceGeneration,
      snapshot.trackCatalog.catalogRevision,
      track.id,
      track.codec,
      track.width,
      track.height,
      track.frameRate,
    );
    if (_hdrProbeKey == key) return;
    final probeGeneration = ++_hdrProbeGeneration;
    _hdrProbeKey = key;
    _hdrCapabilityProbe = null;
    _refreshHdrStatus(snapshot);
    unawaited(
      _probeHdrCapability(
        controller,
        _controllerGeneration,
        probeGeneration,
        VesperPlaybackCapabilityProbeRequest(
          source: resolved.toSource(),
          codec: track.codec,
          width: track.width,
          height: track.height,
          frameRate: track.frameRate,
          sourceNormalizerConfiguration: _hdrSourceNormalizerConfiguration,
        ),
      ),
    );
  }

  Future<void> _probeHdrCapability(
    VesperPlayerController controller,
    int generation,
    int probeGeneration,
    VesperPlaybackCapabilityProbeRequest request,
  ) async {
    try {
      final result = await controller.probeAssociatedPlaybackCapability(
        request,
      );
      if (_isDisposed ||
          generation != _controllerGeneration ||
          probeGeneration != _hdrProbeGeneration) {
        return;
      }
      _hdrCapabilityProbe = result;
      _refreshHdrStatus(controller.snapshot);
    } catch (_) {
      // 探测失败只影响输出证据：界面会显示未确认，而不是「已开启 HDR」。
    }
  }

  VesperMediaTrack? _effectiveVideoTrack(VesperPlayerSnapshot snapshot) {
    final effectiveTrackId = snapshot.effectiveVideoTrackId;
    if (effectiveTrackId == null) {
      return null;
    }
    for (final track in snapshot.trackCatalog.videoTracks) {
      if (track.id == effectiveTrackId) {
        return track;
      }
    }
    return null;
  }

  /// 清空探测结果。切换分集与重载会重建控制器，旧证据不得串到新会话。
  void _resetHdrStatus() {
    ++_hdrProbeGeneration;
    _hdrProbeKey = null;
    _hdrCapabilityProbe = null;
    _hdrWarningsReported.clear();
    if (!_isDisposed) {
      _hdrStatus.value = MediaHdrStatus.none;
    }
  }
}
