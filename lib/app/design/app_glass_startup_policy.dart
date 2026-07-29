import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

@immutable
final class AppGlassStartupPolicy {
  const AppGlassStartupPolicy._({
    required this.isConstrained,
    required this.maxQuality,
    required this.initialQuality,
    required this.allowStepUp,
  });

  factory AppGlassStartupPolicy.resolve({
    required TargetPlatform platform,
    required bool isHcppPlatformSupported,
    required bool areShaderFiltersSupported,
    required GlassQuality? savedQuality,
  }) {
    final isConstrained =
        platform == TargetPlatform.android &&
        (!isHcppPlatformSupported || !areShaderFiltersSupported);

    if (isConstrained) {
      return const AppGlassStartupPolicy._(
        isConstrained: true,
        maxQuality: GlassQuality.minimal,
        initialQuality: GlassQuality.minimal,
        allowStepUp: false,
      );
    }

    return AppGlassStartupPolicy._(
      isConstrained: false,
      maxQuality: GlassQuality.premium,
      initialQuality: savedQuality,
      allowStepUp: true,
    );
  }

  final bool isConstrained;
  final GlassQuality maxQuality;
  final GlassQuality? initialQuality;
  final bool allowStepUp;

  bool get shouldInitializeShaders => !isConstrained;

  bool get shouldPersistAdaptiveQuality => !isConstrained;
}
