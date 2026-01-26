import 'package:flutter/material.dart';

class EchoColors {
  // Midnight Velvet palette.
  static const background = Color(0xFF0F1115);
  static const surface = Color(0xFF181A1E);
  static const textPrimary = Color(0xFFECECEC);
  static const textSecondary = Color(0xFF6B7280);
  static const accent = Color(0xFFC5B4A3);
  static const action = Color(0xFFBC5D5D);

  // Derived system colors.
  static const border = Color(0xFF24272E);
  static const borderSubtle = Color(0x1AFFFFFF);
  static const muted = Color(0xFF20242B);
  static const overlay = Color(0xCC0F1115);
  static const focus = accent;
}

class EchoRadii {
  static const card = 22.0;
  static const button = 18.0;
  static const input = 18.0;
  static const pill = 24.0;
}

class EchoTheme {
  static ThemeData base() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: EchoColors.textPrimary,
      onPrimary: EchoColors.background,
      secondary: EchoColors.muted,
      onSecondary: EchoColors.textPrimary,
      tertiary: EchoColors.accent,
      onTertiary: EchoColors.background,
      error: EchoColors.action,
      onError: EchoColors.background,
      surface: EchoColors.surface,
      onSurface: EchoColors.textPrimary,
      outline: EchoColors.border,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final textTheme = _textTheme(colorScheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Lora',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: EchoColors.background,
      canvasColor: EchoColors.background,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: EchoColors.background,
        foregroundColor: EchoColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: EchoColors.textPrimary,
          letterSpacing: -0.1,
        ),
      ),
      cardTheme: CardThemeData(
        color: EchoColors.surface,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EchoRadii.card),
          side: const BorderSide(color: EchoColors.borderSubtle),
        ),
      ),
      dividerColor: EchoColors.border,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: EchoColors.surface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: EchoColors.textPrimary,
        ),
        actionTextColor: EchoColors.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: EchoColors.borderSubtle),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: EchoColors.accent,
        circularTrackColor: EchoColors.muted,
        linearTrackColor: EchoColors.muted,
      ),
      iconTheme: const IconThemeData(color: EchoColors.textPrimary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EchoColors.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: EchoColors.textSecondary,
        ),
        labelStyle: textTheme.bodySmall?.copyWith(
          color: EchoColors.textSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EchoRadii.input),
          borderSide: const BorderSide(color: EchoColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EchoRadii.input),
          borderSide: const BorderSide(color: EchoColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EchoRadii.input),
          borderSide: const BorderSide(color: EchoColors.focus, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: EchoColors.accent,
          foregroundColor: EchoColors.background,
          disabledBackgroundColor: EchoColors.accent.withValues(alpha: 0.45),
          disabledForegroundColor: EchoColors.background.withValues(alpha: 0.7),
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EchoRadii.button),
          ),
          textStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: EchoColors.textPrimary,
          disabledForegroundColor: EchoColors.textPrimary.withValues(
            alpha: 0.5,
          ),
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          side: const BorderSide(color: EchoColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EchoRadii.button),
          ),
          textStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: EchoColors.textSecondary,
          disabledForegroundColor: EchoColors.textSecondary.withValues(
            alpha: 0.55,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return EchoColors.textSecondary.withValues(alpha: 0.5);
          }
          return states.contains(WidgetState.selected)
              ? EchoColors.accent
              : EchoColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return EchoColors.accent.withValues(alpha: 0.45);
          }
          return EchoColors.muted;
        }),
        trackOutlineColor: WidgetStateProperty.all(
          EchoColors.border.withValues(alpha: 0.7),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: EchoColors.accent,
        inactiveTrackColor: EchoColors.muted,
        thumbColor: EchoColors.accent,
        overlayColor: EchoColors.accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: EchoColors.surface,
        disabledColor: EchoColors.surface.withValues(alpha: 0.6),
        selectedColor: EchoColors.accent,
        secondarySelectedColor: EchoColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: textTheme.bodySmall?.copyWith(
          color: EchoColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: textTheme.bodySmall?.copyWith(
          color: EchoColors.background,
          fontWeight: FontWeight.w700,
        ),
        side: const BorderSide(color: EchoColors.borderSubtle),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EchoRadii.pill),
        ),
      ),
      splashFactory: InkRipple.splashFactory,
      highlightColor: EchoColors.accent.withValues(alpha: 0.08),
      hoverColor: EchoColors.accent.withValues(alpha: 0.04),
      focusColor: EchoColors.accent.withValues(alpha: 0.12),
    );
  }

  static TextTheme _textTheme(ColorScheme colorScheme) {
    final base = const TextTheme(
      displayLarge: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.15,
      ),
      displayMedium: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        height: 1.18,
      ),
      displaySmall: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.24,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
        height: 1.26,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.05,
        height: 1.32,
      ),
      titleSmall: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodyLarge: TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w500,
        height: 1.46,
      ),
      bodyMedium: TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        height: 1.46,
      ),
      bodySmall: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        height: 1.42,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.05,
      ),
      labelMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    );

    return base.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );
  }
}

class AppTheme {
  // Both theme variants intentionally use the same dark-first system.
  static ThemeData light() => EchoTheme.base();

  static ThemeData dark() => EchoTheme.base();
}
