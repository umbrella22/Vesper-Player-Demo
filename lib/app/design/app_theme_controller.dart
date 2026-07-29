import 'package:material_ui/material_ui.dart';

import '../services/app_settings_store.dart';

final class AppThemeController extends ChangeNotifier {
  AppThemeController({
    required this.settings,
    AppThemePreference initialPreference = AppThemePreference.system,
  }) : _preference = initialPreference;

  final AppSettingsStore settings;
  AppThemePreference _preference;

  AppThemePreference get preference => _preference;

  ThemeMode get themeMode => switch (_preference) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  Future<void> setPreference(AppThemePreference value) async {
    if (_preference == value) {
      return;
    }
    final previous = _preference;
    _preference = value;
    notifyListeners();
    try {
      await settings.setThemePreference(value);
    } catch (_) {
      if (_preference == value) {
        _preference = previous;
        notifyListeners();
      }
      rethrow;
    }
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
