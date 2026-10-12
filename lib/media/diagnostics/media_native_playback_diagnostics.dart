import 'package:vesper_player/vesper_player.dart';

String mediaFirstFrameLabel(VesperFirstFrameObservation frame) =>
    'nativeLoad→firstFrame=${frame.elapsedSinceLoadStartMs}ms; '
    '${frame.kindRawValue ?? frame.kind.name}; epoch=${frame.playbackEpoch}';

/// Only fields actually observed by the SDK are described as audio evidence.
String mediaAudioDiagnosticsLabel(VesperAudioPlaybackDiagnostics audio) => [
  'evidence=${audio.evidenceRawValue ?? audio.evidence.name}',
  if (audio.trackId case final value?) 'track=$value',
  if (audio.formatId case final value?) 'format=$value',
  if (audio.codec case final value?) 'codec=$value',
  if (audio.sampleMimeType case final value?) 'mime=$value',
  if (audio.decoderName case final value?) 'decoder=$value',
  if (audio.channels case final value?) 'channels=$value',
  if (audio.sampleRate case final value?) 'sampleRate=$value',
  if (audio.lastIssue case final issue?)
    'issue=${issue.kindRawValue ?? issue.kind.name}'
        '${issue.platformCode == null ? '' : '(${issue.platformCode})'}',
].join('; ');

String mediaAudioDecoderCapabilityLabel(
  VesperAudioDecoderCapabilityResult result,
) => [
  result.statusRawValue ?? result.status.name,
  'evidence=${result.evidence}',
  'reason=${result.reason}',
  if (result.candidates.isNotEmpty)
    'candidates=${result.candidates.map((candidate) => '${candidate.name}:${candidate.statusRawValue ?? candidate.status.name}').join(', ')}',
].join('; ');

String mediaPlaybackStallLabel(VesperPlaybackStallObservation stall) =>
    '${stall.kindRawValue ?? stall.kind.name}; '
    'stalled=${stall.stalledForMs}ms; position=${stall.mediaPositionMs}ms; '
    'epoch=${stall.playbackEpoch}';
