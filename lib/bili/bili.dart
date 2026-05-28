export 'app_mode/pages/bili_hub_page.dart';
export 'app_mode/pages/bili_settings_page.dart';
export 'app_mode/pages/bili_video_detail_page.dart';
export 'common/models/bili_models.dart';
export 'common/pages/bili_playback_page.dart';
export 'common/services/bili_app_settings.dart';
export 'common/services/bili_client.dart';
export 'common/services/bili_history_store.dart';
export 'common/services/bili_logout_service.dart';
export 'common/services/bili_platform_info.dart';
export 'common/services/bili_session_store.dart';
export 'common/services/bili_ui_mode_resolver.dart';
export 'tv_mode/pages/bili_tv_home_page.dart';

final class BiliModule {
  const BiliModule._();

  static const plannedScope =
      'Bilibili API access, WBI signing, cookie/session state, search, '
      'detail pages, favorites, and playback history all stay in the app '
      'layer instead of the player SDK.';
}
