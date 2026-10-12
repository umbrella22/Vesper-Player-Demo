import 'package:vesper_player/vesper_player.dart';
import '../models/resolved_media.dart';

/// Optional provider policy. The shell observes stalls; the provider decides
/// whether an alternate audio representation can justify one recovery attempt.
abstract interface class MediaAudioCompatibility {
  bool canRecover(
    ResolvedMediaPlayback playback,
    VesperPlayerSnapshot snapshot,
  );
  bool claimRecovery();
  String? fallbackTrackId(
    ResolvedMediaPlayback playback,
    VesperPlayerSnapshot snapshot,
  );
}
