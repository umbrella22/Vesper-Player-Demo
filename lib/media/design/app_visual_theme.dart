import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

abstract final class AppVisualTokens {
  static const Color primaryBlue = Color(0xFF409EFF);
  static const Color primaryActionBlue = Color(0xFF0066CC);
  static const Color primaryActionBlueHighContrast = Color(0xFF004080);
  static const Color primaryActionBlueDark = Color(0xFF1470DB);
  static const Color primaryActionBlueDarkHighContrast = Color(0xFF0E62C4);
  static const Color primaryBlue20 = Color(0x33409EFF);
  static const Color primaryBlue40 = Color(0x66409EFF);
  static const Color primaryBlue60 = Color(0x99409EFF);
  static const Color primaryBlue80 = Color(0xCC409EFF);

  /// Reserved for explicit Bilibili source, identity, and account semantics.
  static const Color biliSourcePink = Color(0xFFFB7299);

  static const Color mobileBackground = Color(0xFFF4F6F8);
  static const Color mobileSurface = Color(0xFFFFFFFF);
  static const Color mobileSurfaceRaised = Color(0xFFEDF0F4);
  static const Color mobileSurfaceMuted = Color(0xFFF7F8FA);
  static const Color mobileTextPrimary = Color(0xFF1D222B);
  static const Color mobileTextSecondary = Color(0xFF5B6370);
  static const Color mobileTextTertiary = Color(0xFF666E79);
  static const Color mobileDivider = Color(0xFFDDE1E6);

  static const Color darkBackground = Color(0xFF111318);
  static const Color darkSurface = Color(0xFF1B1E24);
  static const Color darkSurfaceRaised = Color(0xFF252932);
  static const Color darkSurfaceMuted = Color(0xFF20242B);
  static const Color darkTextPrimary = Color(0xFFF4F6FA);
  static const Color darkTextSecondary = Color(0xFFA9B0BB);
  static const Color darkTextTertiary = Color(0xFF89929F);
  static const Color darkDivider = Color(0xFF2F343E);

  // Compatibility aliases while page-level hard-coded colors are migrated.
  static const Color neutralSelection = mobileSurfaceRaised;
  static const Color tvBackground = darkBackground;
  static const Color textPrimary = mobileTextPrimary;
  static const Color textSecondary = mobileTextSecondary;
  static const Color error = Color(0xFFB3261E);

  static const double contentRadius = 8;
  static const double controlRadius = 14;
  static const double sheetRadius = 30;
  static const double minimumTapTarget = 44;
  static const double pressedScale = 0.96;

  static const Duration buttonPressDuration = Duration(milliseconds: 150);
  static const Duration tvFocusDuration = Duration(milliseconds: 180);
  static const Duration overlayDuration = Duration(milliseconds: 220);
  static const Duration tvHeroDuration = Duration(milliseconds: 260);

  static bool reduceMotion(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true ||
        View.maybeOf(context)
                ?.platformDispatcher
                .accessibilityFeatures
                .reduceMotion ==
            true;
  }

  static Duration motionDuration(BuildContext context, Duration duration) {
    return reduceMotion(context) ? Duration.zero : duration;
  }

  static double interactionScale(BuildContext context, double scale) {
    return reduceMotion(context) ? 1 : scale;
  }

  static ThemeData mobileLightTheme() {
    return _baseTheme(
      brightness: Brightness.light,
      visualTheme: AppVisualTheme.light,
    );
  }

  static ThemeData mobileDarkTheme() {
    return _baseTheme(
      brightness: Brightness.dark,
      visualTheme: AppVisualTheme.dark,
    );
  }

  static ThemeData tvTheme() {
    return _baseTheme(
      brightness: Brightness.dark,
      visualTheme: AppVisualTheme.tv,
    );
  }

  static ThemeData mobileLightHighContrastTheme() {
    return _baseTheme(
      brightness: Brightness.light,
      visualTheme: AppVisualTheme.lightHighContrast,
      highContrast: true,
    );
  }

  static ThemeData mobileDarkHighContrastTheme() {
    return _baseTheme(
      brightness: Brightness.dark,
      visualTheme: AppVisualTheme.darkHighContrast,
      highContrast: true,
    );
  }

  static ThemeData lightTheme() => mobileLightTheme();

  static ThemeData darkTheme() => mobileDarkTheme();

  static ThemeData _baseTheme({
    required Brightness brightness,
    required AppVisualTheme visualTheme,
    bool highContrast = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final filledPrimary = switch ((isDark, highContrast)) {
      (false, false) => primaryActionBlue,
      (false, true) => primaryActionBlueHighContrast,
      (true, false) => primaryActionBlueDark,
      (true, true) => primaryActionBlueDarkHighContrast,
    };
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primaryBlue,
          brightness: brightness,
          contrastLevel: highContrast ? 1.0 : 0.0,
          surface: visualTheme.surface,
          error: isDark ? const Color(0xFFFFB4AB) : error,
        ).copyWith(
          primary: filledPrimary,
          onPrimary: Colors.white,
          surface: visualTheme.surface,
          onSurface: visualTheme.textPrimary,
          outline: visualTheme.divider,
          shadow: visualTheme.shadow,
        );

    final outlineWidth = highContrast ? 1.5 : 1.0;
    final actionBlue = visualTheme.accent;
    final modalBorderColor = highContrast
        ? visualTheme.glassBorder
        : (isDark ? const Color(0x38FFFFFF) : const Color(0x26000000));
    final modalBorder = BorderSide(
      color: modalBorderColor,
      width: outlineWidth,
    );
    final outlinedButtonBorder = highContrast
        ? visualTheme.textPrimary
        : (isDark ? const Color(0x47FFFFFF) : const Color(0x3D000000));
    final snackBarBackground = switch ((isDark, highContrast)) {
      (false, false) => const Color(0xFF1D222B),
      (false, true) => Colors.black,
      (true, false) => const Color(0xFF2B313D),
      (true, true) => const Color(0xFFF4F6FA),
    };
    final snackBarForeground = isDark && highContrast
        ? Colors.black
        : const Color(0xFFF4F6FA);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: visualTheme.background,
      canvasColor: visualTheme.background,
      dividerColor: visualTheme.divider,
      disabledColor: visualTheme.textTertiary.withValues(alpha: 0.55),
      extensions: <ThemeExtension<dynamic>>[visualTheme],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: visualTheme.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: mediaSystemUiStyleForBrightness(brightness),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: visualTheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: highContrast
              ? BorderSide(color: visualTheme.textPrimary, width: outlineWidth)
              : BorderSide.none,
          borderRadius: const BorderRadius.all(Radius.circular(contentRadius)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: visualTheme.opaqueGlassFallback,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shadowColor: visualTheme.shadow.withValues(alpha: isDark ? 0.9 : 0.35),
        barrierColor: visualTheme.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: modalBorder,
        ),
        titleTextStyle: TextStyle(
          color: visualTheme.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          color: visualTheme.textSecondary,
          fontSize: 15,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: visualTheme.opaqueGlassFallback,
        modalBackgroundColor: visualTheme.opaqueGlassFallback,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: visualTheme.scrim,
        elevation: 16,
        modalElevation: 16,
        shadowColor: visualTheme.shadow.withValues(alpha: isDark ? 0.85 : 0.35),
        dragHandleColor: visualTheme.textSecondary.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          side: modalBorder,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        elevation: 10,
        backgroundColor: snackBarBackground,
        contentTextStyle: TextStyle(
          color: snackBarForeground,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        actionTextColor: isDark && highContrast
            ? const Color(0xFF004080)
            : const Color(0xFF7CC4FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: highContrast
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? const Color(0x3DFFFFFF) : const Color(0x26FFFFFF)),
            width: outlineWidth,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minimumTapTarget, minimumTapTarget),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: visualTheme.textPrimary.withValues(
            alpha: 0.12,
          ),
          disabledForegroundColor: visualTheme.textPrimary.withValues(
            alpha: 0.38,
          ),
          side: highContrast
              ? BorderSide(
                  color: isDark ? Colors.white : Colors.black,
                  width: outlineWidth,
                )
              : null,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(minimumTapTarget, minimumTapTarget),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? visualTheme.textPrimary.withValues(alpha: 0.38)
                : actionBlue,
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return actionBlue.withValues(alpha: 0.22);
            }
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)) {
              return actionBlue.withValues(alpha: 0.12);
            }
            return null;
          }),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minimumTapTarget, minimumTapTarget),
          foregroundColor: actionBlue,
          side: BorderSide(color: outlinedButtonBorder, width: outlineWidth),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: visualTheme.surfaceRaised,
        hintStyle: TextStyle(color: visualTheme.textTertiary),
        border: OutlineInputBorder(
          borderSide: highContrast
              ? BorderSide(color: visualTheme.textPrimary)
              : BorderSide.none,
          borderRadius: const BorderRadius.all(Radius.circular(controlRadius)),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: highContrast
              ? BorderSide(color: visualTheme.textPrimary)
              : BorderSide.none,
          borderRadius: const BorderRadius.all(Radius.circular(controlRadius)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: highContrast ? visualTheme.textPrimary : actionBlue,
            width: highContrast ? 2.5 : 1.5,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(controlRadius)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? actionBlue : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? actionBlue.withValues(alpha: 0.42)
              : visualTheme.surfaceRaised,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: actionBlue),
      tabBarTheme: TabBarThemeData(
        labelColor: visualTheme.textPrimary,
        unselectedLabelColor: visualTheme.textSecondary,
        indicatorColor: visualTheme.neutralSelection,
      ),
    );
  }
}

@immutable
final class AppVisualTheme extends ThemeExtension<AppVisualTheme> {
  const AppVisualTheme({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.imageOutline,
    required this.glassTint,
    required this.glassBorder,
    required this.focusMarker,
    required this.neutralSelection,
    required this.scrim,
    required this.shadow,
    required this.destructive,
    required this.opaqueGlassFallback,
    required this.accent,
    required this.sourceAccent,
  });

  static const AppVisualTheme light = AppVisualTheme(
    background: AppVisualTokens.mobileBackground,
    surface: AppVisualTokens.mobileSurface,
    surfaceRaised: AppVisualTokens.mobileSurfaceRaised,
    surfaceMuted: AppVisualTokens.mobileSurfaceMuted,
    textPrimary: AppVisualTokens.mobileTextPrimary,
    textSecondary: AppVisualTokens.mobileTextSecondary,
    textTertiary: AppVisualTokens.mobileTextTertiary,
    divider: AppVisualTokens.mobileDivider,
    imageOutline: Color(0x1A000000),
    glassTint: Color(0xB8FFFFFF),
    glassBorder: Color(0x1F000000),
    focusMarker: AppVisualTokens.primaryBlue,
    neutralSelection: AppVisualTokens.mobileSurfaceRaised,
    scrim: Color(0x99000000),
    shadow: Color(0x1A000000),
    destructive: Color(0xFFD9485F),
    opaqueGlassFallback: AppVisualTokens.mobileSurface,
    accent: Color(0xFF0B5CAD),
    sourceAccent: Color(0xFFC93763),
  );

  static const AppVisualTheme dark = AppVisualTheme(
    background: AppVisualTokens.darkBackground,
    surface: AppVisualTokens.darkSurface,
    surfaceRaised: AppVisualTokens.darkSurfaceRaised,
    surfaceMuted: AppVisualTokens.darkSurfaceMuted,
    textPrimary: AppVisualTokens.darkTextPrimary,
    textSecondary: AppVisualTokens.darkTextSecondary,
    textTertiary: AppVisualTokens.darkTextTertiary,
    divider: AppVisualTokens.darkDivider,
    imageOutline: Color(0x1AFFFFFF),
    glassTint: Color(0xB81B1E24),
    glassBorder: Color(0x24FFFFFF),
    focusMarker: AppVisualTokens.primaryBlue,
    neutralSelection: AppVisualTokens.darkSurfaceRaised,
    scrim: Color(0xC2000000),
    shadow: Color(0x66000000),
    destructive: Color(0xFFFF7B83),
    opaqueGlassFallback: AppVisualTokens.darkSurface,
    accent: AppVisualTokens.primaryBlue,
    sourceAccent: AppVisualTokens.biliSourcePink,
  );

  static const AppVisualTheme tv = AppVisualTheme(
    background: AppVisualTokens.darkBackground,
    surface: AppVisualTokens.darkSurface,
    surfaceRaised: AppVisualTokens.darkSurfaceRaised,
    surfaceMuted: AppVisualTokens.darkSurfaceMuted,
    textPrimary: AppVisualTokens.darkTextPrimary,
    textSecondary: AppVisualTokens.darkTextSecondary,
    textTertiary: AppVisualTokens.darkTextTertiary,
    divider: AppVisualTokens.darkDivider,
    imageOutline: Color(0x1AFFFFFF),
    glassTint: Color(0xC21B1E24),
    glassBorder: Color(0x38FFFFFF),
    focusMarker: AppVisualTokens.primaryBlue,
    neutralSelection: AppVisualTokens.darkSurfaceRaised,
    scrim: Color(0xD1000000),
    shadow: Color(0x80000000),
    destructive: Color(0xFFFF7B83),
    opaqueGlassFallback: AppVisualTokens.darkSurface,
    accent: AppVisualTokens.primaryBlue,
    sourceAccent: AppVisualTokens.biliSourcePink,
  );

  static const AppVisualTheme lightHighContrast = AppVisualTheme(
    background: Colors.white,
    surface: Colors.white,
    surfaceRaised: Color(0xFFE7E9ED),
    surfaceMuted: Color(0xFFF2F3F5),
    textPrimary: Colors.black,
    textSecondary: Color(0xFF30343A),
    textTertiary: Color(0xFF51565E),
    divider: Color(0xFF5F646B),
    imageOutline: Color(0x33000000),
    glassTint: Colors.white,
    glassBorder: Colors.black,
    focusMarker: AppVisualTokens.primaryBlue,
    neutralSelection: Color(0xFFE2E4E8),
    scrim: Color(0xCC000000),
    shadow: Color(0x33000000),
    destructive: Color(0xFF9E1E32),
    opaqueGlassFallback: Colors.white,
    accent: Color(0xFF004080),
    sourceAccent: Color(0xFF8C163B),
  );

  static const AppVisualTheme darkHighContrast = AppVisualTheme(
    background: Colors.black,
    surface: Color(0xFF111318),
    surfaceRaised: Color(0xFF2E333D),
    surfaceMuted: Color(0xFF20242B),
    textPrimary: Colors.white,
    textSecondary: Color(0xFFE0E3E8),
    textTertiary: Color(0xFFBEC3CC),
    divider: Color(0xFF9BA1AC),
    imageOutline: Color(0x33FFFFFF),
    glassTint: Color(0xFF111318),
    glassBorder: Colors.white,
    focusMarker: AppVisualTokens.primaryBlue,
    neutralSelection: Color(0xFF343A45),
    scrim: Color(0xE6000000),
    shadow: Colors.black,
    destructive: Color(0xFFFFA1A7),
    opaqueGlassFallback: Color(0xFF111318),
    accent: Color(0xFF70B8FF),
    sourceAccent: Color(0xFFFF94B3),
  );

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color imageOutline;
  final Color glassTint;
  final Color glassBorder;
  final Color focusMarker;
  final Color neutralSelection;
  final Color scrim;
  final Color shadow;
  final Color destructive;
  final Color opaqueGlassFallback;
  final Color accent;
  final Color sourceAccent;

  static AppVisualTheme of(BuildContext context) {
    return Theme.of(context).extension<AppVisualTheme>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  @override
  AppVisualTheme copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? imageOutline,
    Color? glassTint,
    Color? glassBorder,
    Color? focusMarker,
    Color? neutralSelection,
    Color? scrim,
    Color? shadow,
    Color? destructive,
    Color? opaqueGlassFallback,
    Color? accent,
    Color? sourceAccent,
  }) {
    return AppVisualTheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      divider: divider ?? this.divider,
      imageOutline: imageOutline ?? this.imageOutline,
      glassTint: glassTint ?? this.glassTint,
      glassBorder: glassBorder ?? this.glassBorder,
      focusMarker: focusMarker ?? this.focusMarker,
      neutralSelection: neutralSelection ?? this.neutralSelection,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
      destructive: destructive ?? this.destructive,
      opaqueGlassFallback: opaqueGlassFallback ?? this.opaqueGlassFallback,
      accent: accent ?? this.accent,
      sourceAccent: sourceAccent ?? this.sourceAccent,
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
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      imageOutline: Color.lerp(imageOutline, other.imageOutline, t)!,
      glassTint: Color.lerp(glassTint, other.glassTint, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      focusMarker: Color.lerp(focusMarker, other.focusMarker, t)!,
      neutralSelection: Color.lerp(
        neutralSelection,
        other.neutralSelection,
        t,
      )!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      opaqueGlassFallback: Color.lerp(
        opaqueGlassFallback,
        other.opaqueGlassFallback,
        t,
      )!,
      accent: Color.lerp(accent, other.accent, t)!,
      sourceAccent: Color.lerp(sourceAccent, other.sourceAccent, t)!,
    );
  }
}

const _appSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

const _darkSurfaceSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

/// 主题库内置的系统栏样式：亮色主题用深色图标，暗色主题用浅色图标。
/// app 层的 `appSystemUiStyleForBrightness`（bili 语义版本）保留在
/// `lib/app/system_presentation.dart`，本函数是 media 模板包的自包含版本。
SystemUiOverlayStyle mediaSystemUiStyleForBrightness(Brightness brightness) {
  return brightness == Brightness.dark
      ? _darkSurfaceSystemUiStyle
      : _appSystemUiStyle;
}
