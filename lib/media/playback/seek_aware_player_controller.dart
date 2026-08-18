import 'package:flutter/foundation.dart';
import 'package:vesper_player/vesper_player.dart';

/// Player-controller proxy that reports user-initiated seek commands.
///
/// The SDK stage talks directly to its controller, so view-model wrappers do
/// not see progress-bar seeks. This proxy keeps the controller contract intact
/// while letting the playback owner invalidate stale history-resume work.
final class SeekAwarePlayerController implements VesperPlayerController {
  SeekAwarePlayerController(this._inner, this._onUserSeek);

  final VesperPlayerController _inner;
  final VoidCallback _onUserSeek;

  @override
  String get playerId => _inner.playerId;

  @override
  ValueNotifier<VesperPlayerSnapshot> get snapshotListenable =>
      _inner.snapshotListenable;

  @override
  VesperPlayerSnapshot get snapshot => _inner.snapshot;

  @override
  VesperPlayerPlatform get platformForSequence => _inner.platformForSequence;

  @override
  List<VesperPluginDiagnostic> get pluginDiagnostics =>
      _inner.pluginDiagnostics;

  @override
  VesperPlayerCapabilities get capabilities => _inner.capabilities;

  @override
  Stream<VesperPlayerEvent> get events => _inner.events;

  @override
  Stream<VesperPlayerSnapshot> get snapshots => _inner.snapshots;

  @override
  Stream<VesperPlayerPictureInPictureEvent> get pictureInPictureEvents =>
      _inner.pictureInPictureEvents;

  @override
  Future<VesperPlaybackCapabilityProbeResult> probeAssociatedPlaybackCapability(
    VesperPlaybackCapabilityProbeRequest request,
  ) => _inner.probeAssociatedPlaybackCapability(request);

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  Future<void> selectSource(VesperPlayerSource source) =>
      _inner.selectSource(source);

  @override
  Future<void> refresh() => _inner.refresh();

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> togglePause() => _inner.togglePause();

  @override
  Future<void> stop() => _inner.stop();

  @override
  Future<void> seekBy(int deltaMs) {
    _onUserSeek();
    return _inner.seekBy(deltaMs);
  }

  @override
  Future<void> seekToRatio(double ratio) {
    _onUserSeek();
    return _inner.seekToRatio(ratio);
  }

  @override
  Future<void> seekToLiveEdge() {
    _onUserSeek();
    return _inner.seekToLiveEdge();
  }

  @override
  Future<void> setPlaybackRate(double rate) => _inner.setPlaybackRate(rate);

  @override
  Future<void> setVideoTrackSelection(VesperTrackSelection selection) =>
      _inner.setVideoTrackSelection(selection);

  @override
  Future<void> setAudioTrackSelection(VesperTrackSelection selection) =>
      _inner.setAudioTrackSelection(selection);

  @override
  Future<void> setSubtitleTrackSelection(VesperTrackSelection selection) =>
      _inner.setSubtitleTrackSelection(selection);

  @override
  Future<void> setSubtitleStyle(VesperSubtitleStyle style) =>
      _inner.setSubtitleStyle(style);

  @override
  Future<void> setAbrPolicy(
    VesperAbrPolicy policy, {
    int? expectedCatalogRevision,
  }) => _inner.setAbrPolicy(
    policy,
    expectedCatalogRevision: expectedCatalogRevision,
  );

  @override
  Future<void> setPlaybackResiliencePolicy(
    VesperPlaybackResiliencePolicy policy,
  ) => _inner.setPlaybackResiliencePolicy(policy);

  @override
  Future<void> setResiliencePolicy(VesperPlaybackResiliencePolicy policy) =>
      _inner.setResiliencePolicy(policy);

  @override
  Future<void> setKeepScreenOnDuringPlayback(bool enabled) =>
      _inner.setKeepScreenOnDuringPlayback(enabled);

  @override
  Future<void> updateViewport(VesperPlayerViewport viewport) =>
      _inner.updateViewport(viewport);

  @override
  Future<void> clearViewport() => _inner.clearViewport();

  @override
  Future<void> configureSystemPlayback(
    VesperSystemPlaybackConfiguration configuration,
  ) => _inner.configureSystemPlayback(configuration);

  @override
  Future<void> updateSystemPlaybackMetadata(
    VesperSystemPlaybackMetadata metadata,
  ) => _inner.updateSystemPlaybackMetadata(metadata);

  @override
  Future<void> clearSystemPlayback() => _inner.clearSystemPlayback();

  @override
  Future<VesperPictureInPictureAvailability> isPictureInPictureAvailable() =>
      _inner.isPictureInPictureAvailable();

  @override
  Future<void> requestPictureInPicture({
    VesperPictureInPictureConfiguration? configuration,
  }) => _inner.requestPictureInPicture(configuration: configuration);

  @override
  Future<void> exitPictureInPicture() => _inner.exitPictureInPicture();

  @override
  Future<void> setPictureInPictureConfiguration(
    VesperPictureInPictureConfiguration configuration,
  ) => _inner.setPictureInPictureConfiguration(configuration);

  @override
  Future<VesperSystemPlaybackPermissionStatus>
  requestSystemPlaybackPermissions() =>
      _inner.requestSystemPlaybackPermissions();

  @override
  Future<VesperSystemPlaybackPermissionStatus>
  getSystemPlaybackPermissionStatus() =>
      _inner.getSystemPlaybackPermissionStatus();
}
