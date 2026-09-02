import 'package:flutter/foundation.dart';

import 'package:vesper_media/bili/common/services/bili_ui_mode_resolver.dart';

/// Owns the effective phone/TV UI mode and exposes a [ValueNotifier] so the
/// app shell and [HomePage] can rebuild when the mode changes at runtime.
///
/// Replaces the top-level mutable globals (`_resolvedUiMode`, `_tvMode`,
/// `initialUiMode`, `refreshUiMode`) that used to live in `main.dart`: the
/// mode state is now constructed once in the composition root and injected
/// down the widget tree, which keeps `HomePage`/settings/TV pages free of
/// hidden global dependencies.
final class BiliUiModeController {
  BiliUiModeController({BiliUiModeResolver? resolver})
    : _resolver = resolver ?? BiliUiModeResolver();

  final BiliUiModeResolver _resolver;
  final ValueNotifier<bool> _tvMode = ValueNotifier<bool>(false);
  bool _isDisposed = false;

  BiliUiMode get currentMode =>
      _tvMode.value ? BiliUiMode.tv : BiliUiMode.phone;

  ValueListenable<bool> get tvModeListenable => _tvMode;

  Future<BiliUiMode> refresh({bool? knownForceTvMode}) async {
    final mode = await _resolver.resolveEffectiveUiMode(
      knownForceTvMode: knownForceTvMode,
    );
    if (!_isDisposed) {
      _tvMode.value = mode == BiliUiMode.tv;
    }
    return mode;
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _tvMode.dispose();
  }
}
