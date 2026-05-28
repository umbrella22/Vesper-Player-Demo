export 'models/danmaku_models.dart';
export 'services/bili_danmaku_parser.dart';
export 'services/bili_danmaku_repository.dart';
export 'widgets/danmaku_overlay.dart';

final class DanmakuModule {
  const DanmakuModule._();

  static const plannedScope =
      'Bilibili playback page now loads XML danmaku, aligns it to the player '
      'timeline, and renders a Flutter overlay with density and opacity '
      'controls. Advanced scripted danmaku is still intentionally skipped.';
}
