part of 'media_playback_view_model.dart';

extension _MediaPlaybackTrackSelection on MediaPlaybackViewModel {
  Future<String?> _applyPlaybackSelection({
    required String? optionId,
    required String? codecIdentity,
  }) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    try {
      if (optionId == null && codecIdentity == null) {
        await controller.setAbrPolicy(const VesperAbrPolicy.auto());
        return null;
      }

      final snapshot = controller.snapshot;
      final track = _selectBestTrackForPlaybackSelection(
        snapshot,
        optionId: optionId,
        codecIdentity: codecIdentity,
      );
      if (track == null) {
        return '当前视频没有可用的清晰度轨道。';
      }
      final nativeTrack = _nativeVideoTrack(snapshot, track.id);
      if (nativeTrack != null && snapshot.capabilities.supportsAbrFixedTrack) {
        await controller.setAbrPolicy(
          VesperAbrPolicy.fixedTrack(track.id),
          expectedCatalogRevision: snapshot.trackCatalog.catalogRevision,
        );
        return null;
      }

      final bitRate = track.bitRate;
      if (snapshot.capabilities.supportsAbrConstrained &&
          bitRate != null &&
          bitRate > 0) {
        await controller.setAbrPolicy(
          VesperAbrPolicy.constrained(maxBitRate: bitRate),
        );
        return null;
      }

      return '当前播放内核不支持切换到该清晰度。';
    } on VesperFixedTrackSelectionException catch (error) {
      _suppressCurrentPlaybackCommandError(controller);
      if (error.code == VesperFixedTrackSelectionErrorCode.staleCatalog) {
        try {
          await controller.refresh();
        } catch (_) {
          // The original typed rejection remains the actionable result.
          _suppressCurrentPlaybackCommandError(controller);
        }
      }
      return '清晰度切换失败：${_fixedTrackSelectionErrorMessage(error)}';
    } catch (error) {
      return '清晰度切换失败：${mediaErrorMessage(error)}';
    }
  }

  VesperMediaTrack? _nativeVideoTrack(
    VesperPlayerSnapshot snapshot,
    String trackId,
  ) {
    for (final track in snapshot.trackCatalog.videoTracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  bool _canAttemptExplicitTrack(
    VesperPlayerSnapshot snapshot,
    VesperMediaTrack track,
  ) {
    if (_runtimeRejectedVideoTrackIds.contains(track.id)) {
      return false;
    }
    final nativeTrack = _nativeVideoTrack(snapshot, track.id);
    return (nativeTrack?.support ?? track.support).canAttemptExplicitSelection;
  }

  MediaQualitySelectionOption? _qualitySelectionOption(
    VesperPlayerSnapshot snapshot,
    String optionId, {
    String? codecIdentity,
  }) {
    for (final option in availableQualityOptions()) {
      if (option.id == optionId) {
        final availability = _optionSelectionAvailability(
          snapshot,
          option,
          codecIdentity: codecIdentity,
        );
        return MediaQualitySelectionOption(
          option: option,
          availability: availability.availability,
          candidateTracks: availability.candidateTracks,
          unavailableReason: availability.unavailableReason,
        );
      }
    }
    return null;
  }

  _TrackSelectionAvailability _optionSelectionAvailability(
    VesperPlayerSnapshot snapshot,
    MediaQualityOption option, {
    String? codecIdentity,
  }) {
    final identityForTrack = adapter.qualityPolicy.codecStrategyIdentityFor;
    final declaredTracks = option.tracks
        .where(
          (track) =>
              codecIdentity == null ||
              identityForTrack?.call(track) == codecIdentity,
        )
        .toList(growable: false);
    return _trackSelectionAvailability(
      snapshot,
      declaredTracks,
      optionIds: <String>{option.id},
      codecIdentity: codecIdentity,
    );
  }

  _TrackSelectionAvailability _codecSelectionAvailability(
    VesperPlayerSnapshot snapshot,
    String identity, {
    String? optionId,
  }) {
    final identityForTrack = adapter.qualityPolicy.codecStrategyIdentityFor;
    final declaredTracks = <VesperMediaTrack>[];
    final optionIds = <String>{};
    for (final option in availableQualityOptions()) {
      if (optionId != null && option.id != optionId) {
        continue;
      }
      optionIds.add(option.id);
      declaredTracks.addAll(
        option.tracks.where(
          (track) => identityForTrack?.call(track) == identity,
        ),
      );
    }
    return _trackSelectionAvailability(
      snapshot,
      declaredTracks,
      optionIds: optionIds,
      codecIdentity: identity,
    );
  }

  _TrackSelectionAvailability _trackSelectionAvailability(
    VesperPlayerSnapshot snapshot,
    List<VesperMediaTrack> declaredTracks, {
    required Set<String> optionIds,
    String? codecIdentity,
  }) {
    if (declaredTracks.isEmpty) {
      return const _TrackSelectionAvailability(
        availability: MediaQualityAvailability.unavailable,
        declaredTracks: <VesperMediaTrack>[],
        candidateTracks: <VesperMediaTrack>[],
      );
    }
    final nativeTracks = snapshot.trackCatalog.videoTracks;
    final policy = adapter.qualityPolicy;
    final nativeOptionIdFor = policy.qualityOptionIdForNativeTrack;
    final codecIdentityFor = policy.codecStrategyIdentityFor;
    final candidateTracks = nativeTracks.isEmpty
        ? List<VesperMediaTrack>.of(declaredTracks)
        : () {
            final declaredTrackIds = declaredTracks
                .map((track) => track.id)
                .toSet();
            final declaredOptions = availableQualityOptions();
            return nativeTracks
                .where((track) {
                  final mappedOptionId = nativeOptionIdFor?.call(
                    track,
                    declaredOptions,
                  );
                  final matchesQuality = mappedOptionId == null
                      ? declaredTrackIds.contains(track.id)
                      : optionIds.contains(mappedOptionId);
                  if (!matchesQuality) {
                    return false;
                  }
                  return codecIdentity == null ||
                      codecIdentityFor?.call(track) == codecIdentity;
                })
                .toList(growable: false);
          }();
    if (candidateTracks.isEmpty) {
      return _TrackSelectionAvailability(
        availability: MediaQualityAvailability.unavailable,
        declaredTracks: declaredTracks,
        candidateTracks: candidateTracks,
        unavailableReason: VesperTrackSupportReason.platformUnknown,
      );
    }

    var hasUnknown = false;
    VesperTrackSupportReason? unavailableReason;
    for (final track in candidateTracks) {
      if (_runtimeRejectedVideoTrackIds.contains(track.id)) {
        unavailableReason ??= VesperTrackSupportReason.runtimeFailure;
        continue;
      }
      switch (track.support.status) {
        case VesperTrackSupportStatus.supported:
          return _TrackSelectionAvailability(
            availability: MediaQualityAvailability.available,
            declaredTracks: declaredTracks,
            candidateTracks: candidateTracks,
          );
        case VesperTrackSupportStatus.unknown:
          hasUnknown = true;
        case VesperTrackSupportStatus.exceedsCapabilities:
        case VesperTrackSupportStatus.unsupported:
          unavailableReason ??= track.support.reason;
      }
    }
    return _TrackSelectionAvailability(
      availability: hasUnknown
          ? MediaQualityAvailability.unknown
          : MediaQualityAvailability.unavailable,
      declaredTracks: declaredTracks,
      candidateTracks: candidateTracks,
      unavailableReason: hasUnknown ? null : unavailableReason,
    );
  }

  String _unavailableSelectionMessage(
    VesperTrackSupportReason? reason, {
    required bool noMatchingTracks,
  }) {
    if (noMatchingTracks) {
      return '当前清晰度没有匹配的播放轨道。';
    }
    return switch (reason) {
      VesperTrackSupportReason.routeUnavailable ||
      VesperTrackSupportReason.presentationUnavailable => '当前播放链路不支持该清晰度。',
      VesperTrackSupportReason.unsupportedDrm => '当前内容保护方式不支持该清晰度。',
      _ => '当前设备无法播放该清晰度。',
    };
  }

  String _unavailableSelectionSupportingText(VesperTrackSupportReason? reason) {
    return switch (reason) {
      VesperTrackSupportReason.routeUnavailable ||
      VesperTrackSupportReason.presentationUnavailable => '当前播放链路不支持',
      VesperTrackSupportReason.unsupportedDrm => '内容保护方式不支持',
      VesperTrackSupportReason.runtimeFailure => '本次播放已自动降级',
      _ => '当前设备不支持',
    };
  }

  /// 策略身份的展示文案：显式规范标签优先；缺省取组内首个匹配
  /// 身份轨道的展示 label——身份是内部键，绝不直接显示。
  String _codecDisplayLabel(String identity) {
    final explicit = adapter.qualityPolicy.codecIdentityLabelFor?.call(
      identity,
    );
    if (explicit != null) {
      return explicit;
    }
    final labelFor = adapter.qualityPolicy.codecLabelFor;
    final identityFor = adapter.qualityPolicy.codecStrategyIdentityFor;
    for (final option in availableQualityOptions()) {
      for (final track in option.tracks) {
        if (identityFor?.call(track) == identity) {
          final label = labelFor?.call(track);
          if (label != null) {
            return label;
          }
        }
      }
    }
    return identity;
  }

  VesperMediaTrack? _selectBestTrackForPlaybackSelection(
    VesperPlayerSnapshot snapshot, {
    required String? optionId,
    required String? codecIdentity,
  }) {
    final tracks = _sortedVideoTracks(playbackSelectionTracks(snapshot));
    Iterable<VesperMediaTrack> candidates = tracks.where(
      (track) => _canAttemptExplicitTrack(snapshot, track),
    );
    if (optionId != null) {
      final option = _qualitySelectionOption(
        snapshot,
        optionId,
        codecIdentity: codecIdentity,
      );
      final optionTracks = _sortedVideoTracks(
        option?.candidateTracks ?? const <VesperMediaTrack>[],
      );
      candidates = optionTracks.where(
        (track) => _canAttemptExplicitTrack(snapshot, track),
      );
    }

    if (codecIdentity != null) {
      final identityForTrack = adapter.qualityPolicy.codecStrategyIdentityFor;
      final codecMatches = candidates
          .where((track) => identityForTrack?.call(track) == codecIdentity)
          .toList(growable: false);
      return codecMatches.isEmpty ? null : codecMatches.first;
    }

    for (final candidate in candidates) {
      return candidate;
    }
    return null;
  }

  String _fixedTrackSelectionErrorMessage(
    VesperFixedTrackSelectionException error,
  ) {
    if (error.codeRawValue == 'runtimeTrackRejected') {
      return '当前设备无法继续播放该清晰度，已恢复自动选择。';
    }
    return switch (error.code) {
      VesperFixedTrackSelectionErrorCode.trackUnavailable => '该清晰度已不可用，请重新选择。',
      VesperFixedTrackSelectionErrorCode.trackExceedsCapabilities =>
        '当前设备无法播放该清晰度。',
      VesperFixedTrackSelectionErrorCode.trackUnsupported => '当前播放内核不支持该清晰度。',
      VesperFixedTrackSelectionErrorCode.staleCatalog => '清晰度列表已更新，请重试。',
      VesperFixedTrackSelectionErrorCode.unknown => '当前无法切换到该清晰度。',
    };
  }

  void _suppressCurrentPlaybackCommandError(VesperPlayerController controller) {
    if (_isDisposed) {
      return;
    }
    final commandError = controller.snapshot.lastError;
    if (commandError != null) {
      _suppressedPlaybackCommandError.value = commandError;
    }
  }

  String _subtitleSelectionErrorMessage(VesperSubtitleException error) {
    return switch (error.code) {
      'subtitle_selection_timeout' => '字幕轨道仍在准备，请稍后重试。',
      'subtitle_track_not_found' ||
      'subtitle_platform_track_unavailable' ||
      'subtitle_auto_candidate_unavailable' => '该字幕轨道暂不可用，请重新选择。',
      'subtitle_selection_superseded' ||
      'subtitle_selection_cancelled' ||
      'subtitle_source_changed' => '字幕选择已失效，请重试。',
      'subtitle_selection_invalid' ||
      'subtitle_selection_mismatch' => '当前无法应用该字幕选择。',
      'subtitle_resource_failed' ||
      'subtitle_manifest_parse_failed' ||
      'subtitle_transport_failure' => '字幕加载失败，请稍后重试。',
      'subtitle_uri_invalid' => '字幕地址无效，请重新选择。',
      'subtitle_encoding_unsupported' => '当前字幕编码不受支持。',
      'subtitle_default_track_ambiguous' ||
      'subtitle_request_identity_ambiguous' ||
      'subtitle_track_identity_ambiguous' => '字幕轨道无法唯一确定，请重新选择。',
      'subtitle_selection_failed' => '字幕切换失败，请稍后重试。',
      _ => error.retriable ? '字幕切换暂未完成，请稍后重试。' : '当前无法切换字幕。',
    };
  }

  List<VesperMediaTrack> _sortedVideoTracks(List<VesperMediaTrack> tracks) {
    final sorted = List<VesperMediaTrack>.of(tracks);
    sorted.sort((left, right) {
      final heightCompare = (right.height ?? 0).compareTo(left.height ?? 0);
      if (heightCompare != 0) {
        return heightCompare;
      }
      final bitRateCompare = (right.bitRate ?? 0).compareTo(left.bitRate ?? 0);
      if (bitRateCompare != 0) {
        return bitRateCompare;
      }
      return (left.codec ?? '').compareTo(right.codec ?? '');
    });
    return sorted;
  }
}
