export 'adapter/media_platform_adapter.dart';
export 'capabilities/media_content_surfaces.dart';
export 'capabilities/media_danmaku.dart';
export 'danmaku/media_danmaku_overlay.dart';
export 'diagnostics/media_playback_performance_diagnostics.dart';
export 'capabilities/media_engagement.dart';
export 'capabilities/media_history.dart';
export 'models/media_detail.dart';
export 'models/media_playback_notice.dart';
export 'models/media_playback_target.dart';
export 'models/resolved_media.dart';
export 'playback/media_external_playback_manager.dart';
export 'playback/media_playback_binding.dart';
export 'playback/media_playback_page.dart';
export 'playback/media_playback_presentation.dart';
export 'playback/media_playback_dlna_widgets.dart';
export 'playback/media_playback_errors.dart';
export 'playback/media_playback_tv_widgets.dart';
export 'playback/media_playback_settings_surface.dart';
export 'playback/media_playback_tuning_panel.dart';
export 'playback/media_playback_widgets.dart';
export 'playback/media_playback_view_model.dart';
export 'player/media_text.dart';
export 'tv/media_tv_focusable.dart';
export 'player/player_options.dart';

final class MediaModule {
  const MediaModule._();

  static const plannedScope =
      'Platform-agnostic playback shell: media models, adapter contract, '
      'capability declarations, and the generic playback page owned by the '
      'app shell. Platforms (bilibili, ...) implement MediaPlatformAdapter '
      'to onboard the full playback experience.';
}
