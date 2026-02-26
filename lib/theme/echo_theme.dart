import 'package:flutter/material.dart';

class EchoColors {
  static const voidBg = Color(0xFF080A09);
  static const clearing = Color(0xFF141C18);
  static const pulse = Color(0xFF769586);
  static const fog = Color(0xFFB8C4BE);
  static const ember = Color(0xFFC4877A);
}

class EchoRadii {
  static const double card = 18;
  static const double button = 16;
  static const double input = 16;
  static const double pill = 24;
  static const double sheet = 22;
  static const double nav = 20;
}

class EchoColorUtils {
  static Color onColor(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.35 ? EchoColors.voidBg : EchoColors.fog;
  }

  static Color pressedOverlay(Color background, {double alpha = 0.12}) {
    return EchoColors.pulse.withValues(alpha: alpha);
  }

  static Color mutedOn(Color background, double alpha) {
    return onColor(background).withValues(alpha: alpha);
  }

  static Color darken(Color color, double amount) {
    return Color.lerp(color, Colors.black, amount)!;
  }
}

@immutable
class EchoSemantic extends ThemeExtension<EchoSemantic> {
  const EchoSemantic({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accentPrimary,
    required this.accentMuted,
    required this.danger,
    required this.dangerMuted,
    required this.overlay,
    required this.shadow,
    required this.shadowMedium,
    required this.shadowHeavy,
  });

  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accentPrimary;
  final Color accentMuted;
  final Color danger;
  final Color dangerMuted;
  final Color overlay;
  final Color shadow;
  final Color shadowMedium;
  final Color shadowHeavy;

  factory EchoSemantic.fromBrightness(Brightness brightness) {
    const neutral = EchoColors.clearing;
    final surface1 = neutral;
    final surface2 = Color.lerp(neutral, EchoColors.fog, 0.04)!;
    final surface3 = Color.lerp(neutral, EchoColors.fog, 0.08)!;
    final border = EchoColors.fog.withValues(alpha: 0.12);
    return EchoSemantic(
      bg: EchoColors.voidBg,
      surface1: surface1,
      surface2: surface2,
      surface3: surface3,
      border: border,
      borderSubtle: border.withValues(alpha: 0.5),
      textPrimary: EchoColors.fog,
      textSecondary: EchoColors.fog.withValues(alpha: 0.72),
      textTertiary: EchoColors.fog.withValues(alpha: 0.55),
      accentPrimary: EchoColors.pulse,
      accentMuted: EchoColors.pulse.withValues(alpha: 0.18),
      danger: EchoColors.ember,
      dangerMuted: EchoColors.ember.withValues(alpha: 0.6),
      overlay: EchoColors.voidBg.withValues(alpha: 0.9),
      shadow: Colors.black.withValues(alpha: 0.2),
      shadowMedium: Colors.black.withValues(alpha: 0.3),
      shadowHeavy: Colors.black.withValues(alpha: 0.44),
    );
  }

  @override
  EchoSemantic copyWith({
    Color? bg,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accentPrimary,
    Color? accentMuted,
    Color? danger,
    Color? dangerMuted,
    Color? overlay,
    Color? shadow,
    Color? shadowMedium,
    Color? shadowHeavy,
  }) {
    return EchoSemantic(
      bg: bg ?? this.bg,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentMuted: accentMuted ?? this.accentMuted,
      danger: danger ?? this.danger,
      dangerMuted: dangerMuted ?? this.dangerMuted,
      overlay: overlay ?? this.overlay,
      shadow: shadow ?? this.shadow,
      shadowMedium: shadowMedium ?? this.shadowMedium,
      shadowHeavy: shadowHeavy ?? this.shadowHeavy,
    );
  }

  @override
  EchoSemantic lerp(ThemeExtension<EchoSemantic>? other, double t) {
    if (other is! EchoSemantic) {
      return this;
    }
    return EchoSemantic(
      bg: Color.lerp(bg, other.bg, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerMuted: Color.lerp(dangerMuted, other.dangerMuted, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      shadowMedium: Color.lerp(shadowMedium, other.shadowMedium, t)!,
      shadowHeavy: Color.lerp(shadowHeavy, other.shadowHeavy, t)!,
    );
  }
}

ThemeData buildEchoTheme(Brightness _brightness) {
  const resolvedBrightness = Brightness.dark;
  final tokens = EchoSemantic.fromBrightness(resolvedBrightness);
  final buttonFill = tokens.accentPrimary;
  final onButtonFill = Colors.black;
  final colorScheme = ColorScheme(
    brightness: resolvedBrightness,
    primary: tokens.accentPrimary,
    onPrimary: onButtonFill,
    secondary: tokens.surface1,
    onSecondary: tokens.textPrimary,
    tertiary: tokens.surface2,
    onTertiary: tokens.textPrimary,
    error: tokens.danger,
    onError: EchoColorUtils.onColor(tokens.danger),
    surface: tokens.surface1,
    onSurface: tokens.textPrimary,
    surfaceContainerHighest: tokens.surface2,
    onSurfaceVariant: tokens.textSecondary,
    outline: Colors.transparent,
    outlineVariant: Colors.transparent,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: tokens.textPrimary,
    onInverseSurface: tokens.bg,
  );

  final textTheme = _textTheme(tokens);

  return ThemeData(
    useMaterial3: true,
    brightness: resolvedBrightness,
    fontFamily: 'Satoshi',
    colorScheme: colorScheme,
    extensions: [tokens],
    scaffoldBackgroundColor: tokens.bg,
    canvasColor: tokens.bg,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bg,
      foregroundColor: tokens.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
    ),
    cardTheme: CardThemeData(
      color: tokens.surface1,
      shadowColor: tokens.shadow,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EchoRadii.card),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Colors.transparent,
      thickness: 0,
      space: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tokens.surface2,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: tokens.textPrimary,
      ),
      actionTextColor: tokens.accentPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface1,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EchoRadii.sheet),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.surface1,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: tokens.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EchoRadii.sheet),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.accentPrimary,
      circularTrackColor: tokens.textSecondary.withValues(alpha: 0.2),
      linearTrackColor: tokens.textSecondary.withValues(alpha: 0.2),
    ),
    iconTheme: IconThemeData(color: tokens.textPrimary),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface1,
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: tokens.textTertiary.withValues(alpha: 0.7),
      ),
      labelStyle: textTheme.bodySmall?.copyWith(
        color: tokens.textSecondary,
      ),
      prefixIconColor: tokens.textSecondary,
      suffixIconColor: tokens.textSecondary,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EchoRadii.input),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EchoRadii.input),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EchoRadii.input),
        borderSide: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return buttonFill.withValues(alpha: 0.4);
          }
          if (states.contains(WidgetState.pressed)) {
            return EchoColorUtils.darken(buttonFill, 0.08);
          }
          return buttonFill;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return onButtonFill.withValues(alpha: 0.55);
          }
          return onButtonFill;
        }),
        overlayColor: WidgetStateProperty.all(
          EchoColorUtils.pressedOverlay(buttonFill),
        ),
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        minimumSize: WidgetStateProperty.all(const Size.fromHeight(54)),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EchoRadii.button),
          ),
        ),
        textStyle: WidgetStateProperty.all(
          textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.surface1.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.pressed)) {
            return tokens.surface1;
          }
          return tokens.surface1;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          final resolved = tokens.textPrimary;
          if (states.contains(WidgetState.disabled)) {
            return resolved.withValues(alpha: 0.5);
          }
          return resolved;
        }),
        overlayColor: WidgetStateProperty.all(
          EchoColorUtils.pressedOverlay(tokens.surface1, alpha: 0.12),
        ),
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
        side: WidgetStateProperty.all(BorderSide.none),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EchoRadii.button),
          ),
        ),
        textStyle: WidgetStateProperty.all(
          textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.surface1.withValues(alpha: 0.4);
          }
          if (states.contains(WidgetState.pressed)) {
            return tokens.surface1;
          }
          return tokens.surface1;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          final resolved = tokens.textPrimary;
          if (states.contains(WidgetState.disabled)) {
            return resolved.withValues(alpha: 0.5);
          }
          return resolved;
        }),
        overlayColor: WidgetStateProperty.all(
          EchoColorUtils.pressedOverlay(tokens.surface1, alpha: 0.12),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        textStyle: WidgetStateProperty.all(
          textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EchoRadii.button),
          ),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          final resolved = tokens.textPrimary;
          if (states.contains(WidgetState.disabled)) {
            return resolved.withValues(alpha: 0.5);
          }
          return resolved;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.surface1.withValues(alpha: 0.5);
          }
          if (states.contains(WidgetState.pressed)) {
            return tokens.surface1;
          }
          return tokens.surface1;
        }),
        overlayColor: WidgetStateProperty.all(
          EchoColorUtils.pressedOverlay(tokens.surface1, alpha: 0.12),
        ),
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EchoRadii.button),
          ),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: buttonFill,
      foregroundColor: onButtonFill,
      elevation: 0,
      highlightElevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      disabledElevation: 0,
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return tokens.textSecondary.withValues(alpha: 0.5);
        }
        return states.contains(WidgetState.selected)
            ? buttonFill
            : tokens.textSecondary.withValues(alpha: 0.6);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return buttonFill.withValues(alpha: 0.55);
        }
        return tokens.textSecondary.withValues(alpha: 0.2);
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: buttonFill,
      inactiveTrackColor: tokens.textSecondary.withValues(alpha: 0.2),
      thumbColor: buttonFill,
      overlayColor: buttonFill.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.surface1,
      disabledColor: tokens.surface1.withValues(alpha: 0.6),
      selectedColor: buttonFill,
      secondarySelectedColor: buttonFill,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: textTheme.bodySmall?.copyWith(
        color: tokens.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: textTheme.bodySmall?.copyWith(
        color: onButtonFill,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EchoRadii.pill),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: tokens.bg,
      selectedItemColor: tokens.accentPrimary,
      unselectedItemColor: tokens.textSecondary.withValues(alpha: 0.6),
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.bg,
      indicatorColor: buttonFill.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return textTheme.labelSmall?.copyWith(
          color: isSelected
              ? tokens.accentPrimary
              : tokens.textSecondary.withValues(alpha: 0.6),
          fontWeight: FontWeight.w600,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: isSelected
              ? tokens.accentPrimary
              : tokens.textSecondary.withValues(alpha: 0.6),
          size: 22,
        );
      }),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.textSecondary,
      textColor: tokens.textPrimary,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accentPrimary,
      selectionColor: tokens.accentPrimary.withValues(alpha: 0.25),
      selectionHandleColor: tokens.accentPrimary,
    ),
    splashFactory: InkRipple.splashFactory,
    highlightColor: buttonFill.withValues(alpha: 0.08),
    hoverColor: buttonFill.withValues(alpha: 0.06),
    focusColor: buttonFill.withValues(alpha: 0.1),
    dividerColor: Colors.transparent,
  );
}

TextTheme _textTheme(EchoSemantic tokens) {
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
    bodyColor: tokens.textPrimary,
    displayColor: tokens.textPrimary,
  );
}

extension EchoThemeX on BuildContext {
  EchoSemantic get echo => Theme.of(this).extension<EchoSemantic>()!;
}

class EchoGradients {
  static const Color background = EchoColors.voidBg;
}
