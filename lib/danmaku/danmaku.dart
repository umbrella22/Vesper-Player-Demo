export 'models/danmaku_models.dart';
export 'services/bili_advanced_danmaku_parser.dart';
export 'services/bili_danmaku_parser.dart';
export 'services/bili_danmaku_provider.dart';
export 'services/bili_danmaku_repository.dart';
export 'services/bili_danmaku_segment_parser.dart';
export 'services/bili_danmaku_view_parser.dart';

final class DanmakuModule {
  const DanmakuModule._();

  static const plannedScope =
      'Bilibili playback sessions load segmented danmaku with an XML fallback, '
      'align immutable snapshots to the player timeline, and render them in a '
      'shared Flutter overlay. Declarative mode-7 danmaku is supported; mode-8 '
      'code and mode-9 BAS remain non-executable.';
}
