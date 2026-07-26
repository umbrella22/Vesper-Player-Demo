import 'package:material_ui/material_ui.dart';

abstract final class AppVisualTokens {
  static const Color primaryBlue = Color(0xFF409EFF);
  static const Color primaryBlue20 = Color(0x33409EFF);
  static const Color primaryBlue40 = Color(0x66409EFF);
  static const Color primaryBlue60 = Color(0x99409EFF);
  static const Color primaryBlue80 = Color(0xCC409EFF);
  static const Color neutralSelection = Color(0x1A20232B);

  /// Reserved for explicit Bilibili source, identity, and account semantics.
  static const Color biliSourcePink = Color(0xFFFB7299);

  static const Color mobileBackground = Color(0xFFF3F6FB);
  static const Color mobileSurface = Color(0xFFFFFFFF);
  static const Color mobileSurfaceMuted = Color(0xFFF6F8FC);
  static const Color tvBackground = Color(0xFF0A0A0E);
  static const Color textPrimary = Color(0xFF20232B);
  static const Color textSecondary = Color(0xFF6D7480);
  static const Color error = Color(0xFFB3261E);

  static const double contentRadius = 8;
  static const double controlRadius = 14;
  static const double sheetRadius = 30;
  static const double minimumTapTarget = 44;
  static const double pressedScale = 0.96;

  static const Duration buttonPressDuration = Duration(milliseconds: 150);
  static const Duration tvFocusDuration = Duration(milliseconds: 180);
  static const Duration overlayDuration = Duration(milliseconds: 220);

  static Duration motionDuration(BuildContext context, Duration duration) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true) {
      return Duration.zero;
    }
    return duration;
  }

  static ThemeData lightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.light,
      surface: mobileSurface,
      error: error,
    ).copyWith(primary: primaryBlue, onPrimary: Colors.white);
    return _baseTheme(
      colorScheme: colorScheme,
      background: mobileBackground,
      extension: AppVisualTheme.light,
    );
  }

  static ThemeData darkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.dark,
      surface: const Color(0xFF17181E),
      error: const Color(0xFFFFB4AB),
    ).copyWith(primary: primaryBlue, onPrimary: Colors.white);
    return _baseTheme(
      colorScheme: colorScheme,
      background: tvBackground,
      extension: AppVisualTheme.dark,
    );
  }

  static ThemeData _baseTheme({
    required ColorScheme colorScheme,
    required Color background,
    required AppVisualTheme extension,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      extensions: <ThemeExtension<dynamic>>[extension],
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppVisualTokens.contentRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            AppVisualTokens.minimumTapTarget,
            AppVisualTokens.minimumTapTarget,
          ),
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colorScheme.onSurface.withValues(
            alpha: 0.12,
          ),
          disabledForegroundColor: colorScheme.onSurface.withValues(
            alpha: 0.38,
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(AppVisualTokens.controlRadius),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : mobileSurfaceMuted,
        border: const OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(
            Radius.circular(AppVisualTokens.controlRadius),
          ),
        ),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(
            Radius.circular(AppVisualTokens.controlRadius),
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0x66409EFF)),
          borderRadius: BorderRadius.all(
            Radius.circular(AppVisualTokens.controlRadius),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primaryBlue : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryBlue.withValues(alpha: 0.42)
              : null,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryBlue,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryBlue,
        indicatorColor: primaryBlue,
      ),
    );
  }
}

@immutable
final class AppVisualTheme extends ThemeExtension<AppVisualTheme> {
  const AppVisualTheme({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.glassTint,
    required this.glassBorder,
    required this.focusMarker,
  });

  static const AppVisualTheme light = AppVisualTheme(
    background: AppVisualTokens.mobileBackground,
    surface: AppVisualTokens.mobileSurface,
    surfaceMuted: AppVisualTokens.mobileSurfaceMuted,
    textPrimary: AppVisualTokens.textPrimary,
    textSecondary: AppVisualTokens.textSecondary,
    glassTint: Color(0x18409EFF),
    glassBorder: Color(0x33409EFF),
    focusMarker: AppVisualTokens.primaryBlue,
  );

  static const AppVisualTheme dark = AppVisualTheme(
    background: AppVisualTokens.tvBackground,
    surface: Color(0xFF17181E),
    surfaceMuted: Color(0xFF22242B),
    textPrimary: Colors.white,
    textSecondary: Color(0xAAFFFFFF),
    glassTint: Color(0x22409EFF),
    glassBorder: Color(0x88409EFF),
    focusMarker: AppVisualTokens.primaryBlue,
  );

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color glassTint;
  final Color glassBorder;
  final Color focusMarker;

  static AppVisualTheme of(BuildContext context) {
    return Theme.of(context).extension<AppVisualTheme>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  @override
  AppVisualTheme copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? glassTint,
    Color? glassBorder,
    Color? focusMarker,
  }) {
    return AppVisualTheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      glassTint: glassTint ?? this.glassTint,
      glassBorder: glassBorder ?? this.glassBorder,
      focusMarker: focusMarker ?? this.focusMarker,
    );
  }

  @override
  AppVisualTheme lerp(covariant AppVisualTheme? other, double t) {
    if (other == null) {
      return this;
    }
    return AppVisualTheme(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      glassTint: Color.lerp(glassTint, other.glassTint, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      focusMarker: Color.lerp(focusMarker, other.focusMarker, t)!,
    );
  }
}
