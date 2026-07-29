import 'package:bilibili_player/app/design/app_glass_startup_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  test('Android without HCPP is locked to minimal glass', () {
    final policy = AppGlassStartupPolicy.resolve(
      platform: TargetPlatform.android,
      isHcppPlatformSupported: false,
      areShaderFiltersSupported: true,
      savedQuality: GlassQuality.premium,
    );

    expect(policy.isConstrained, isTrue);
    expect(policy.shouldInitializeShaders, isFalse);
    expect(policy.maxQuality, GlassQuality.minimal);
    expect(policy.initialQuality, GlassQuality.minimal);
    expect(policy.allowStepUp, isFalse);
    expect(policy.shouldPersistAdaptiveQuality, isFalse);
  });

  test('Android without Impeller is locked to minimal glass', () {
    final policy = AppGlassStartupPolicy.resolve(
      platform: TargetPlatform.android,
      isHcppPlatformSupported: true,
      areShaderFiltersSupported: false,
      savedQuality: GlassQuality.standard,
    );

    expect(policy.isConstrained, isTrue);
    expect(policy.shouldInitializeShaders, isFalse);
    expect(policy.maxQuality, GlassQuality.minimal);
  });

  test('HCPP-capable Android restores adaptive glass quality', () {
    final policy = AppGlassStartupPolicy.resolve(
      platform: TargetPlatform.android,
      isHcppPlatformSupported: true,
      areShaderFiltersSupported: true,
      savedQuality: GlassQuality.standard,
    );

    expect(policy.isConstrained, isFalse);
    expect(policy.shouldInitializeShaders, isTrue);
    expect(policy.maxQuality, GlassQuality.premium);
    expect(policy.initialQuality, GlassQuality.standard);
    expect(policy.allowStepUp, isTrue);
    expect(policy.shouldPersistAdaptiveQuality, isTrue);
  });

  test('iOS glass quality does not depend on Android HCPP', () {
    final policy = AppGlassStartupPolicy.resolve(
      platform: TargetPlatform.iOS,
      isHcppPlatformSupported: false,
      areShaderFiltersSupported: true,
      savedQuality: GlassQuality.premium,
    );

    expect(policy.isConstrained, isFalse);
    expect(policy.shouldInitializeShaders, isTrue);
    expect(policy.maxQuality, GlassQuality.premium);
    expect(policy.initialQuality, GlassQuality.premium);
  });
}
