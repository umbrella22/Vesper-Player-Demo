import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/common/state/optimistic_value.dart';

import '../services/app_settings_store.dart';

final class AppThemeController extends ChangeNotifier {
  AppThemeController({
    required this.settings,
    AppThemePreference initialPreference = AppThemePreference.system,
  }) {
    _preference = OptimisticValue(
      initialValue: initialPreference,
      persist: settings.setThemePreference,
      onChanged: (_) => notifyListeners(),
    );
  }

  final AppSettingsStore settings;
  late final OptimisticValue<AppThemePreference> _preference;

  AppThemePreference get preference => _preference.value;

  ThemeMode get themeMode => switch (preference) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  Future<void> setPreference(AppThemePreference value) {
    return _preference.setValue(value);
  }

  @override
  void dispose() {
    _preference.dispose();
    super.dispose();
  }
}

class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope is missing above this context.');
    return scope!.notifier!;
  }
}
