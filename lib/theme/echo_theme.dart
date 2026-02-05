import 'package:flutter/material.dart';

class EchoColors {
  static const deepNavy = Color(0xFF071952);
  static const deepTeal = Color(0xFF1F3B3E);
  static const teal = Color(0xFF2A4F52);
  static const mint = Color(0xFF3A6063);
  static const bgBaseNearBlack = Color(0xFF050B16);
  static const bgGlowNavy = Color(0xFF0B1733);
  static const bgEdgeNearBlack = Color(0xFF03060B);

  static const textPrimary = Color(0xFFF2F4F7);
  static const textSecondary = Color(0xFFA3ACBC);
  static const textTertiary = Color(0xFF6D7687);

  static const danger = Color(0xFFB56D6D);
}

class EchoRadii {
  static const double card = 16;
  static const double button = 14;
  static const double input = 14;
  static const double pill = 24;
  static const double sheet = 20;
  static const double nav = 22;
}

@immutable
class EchoSemantic extends ThemeExtension<EchoSemantic> {
  const EchoSemantic({
    required this.bg,
    required this.bgBaseNearBlack,
    required this.bgGlowNavy,
    required this.bgEdgeNearBlack,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.accentMuted,
    required this.danger,
    required this.dangerMuted,
    required this.overlay,
    required this.shadow,
  });

  final Color bg;
  final Color bgBaseNearBlack;
  final Color bgGlowNavy;
  final Color bgEdgeNearBlack;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accentPrimary;
  final Color accentSecondary;
  final Color accentMuted;
  final Color danger;
  final Color dangerMuted;
  final Color overlay;
  final Color shadow;

  factory EchoSemantic.fromBrightness(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    if (isDark) {
      const bgBaseNearBlack = EchoColors.bgBaseNearBlack;
      const bgGlowNavy = EchoColors.bgGlowNavy;
      final surface1 =
          Color.lerp(bgBaseNearBlack, Colors.white, 0.07)!;
      final surface2 =
          Color.lerp(bgBaseNearBlack, EchoColors.deepTeal, 0.24)!;
      final surface3 =
          Color.lerp(bgGlowNavy, Colors.white, 0.08)!;
      return EchoSemantic(
        bg: bgBaseNearBlack,
        bgBaseNearBlack: bgBaseNearBlack,
        bgGlowNavy: bgGlowNavy,
        bgEdgeNearBlack: EchoColors.bgEdgeNearBlack,
        surface1: surface1,
        surface2: surface2,
        surface3: surface3,
        border: EchoColors.deepTeal,
        borderSubtle: EchoColors.deepTeal,
        textPrimary: EchoColors.textPrimary,
        textSecondary: EchoColors.textSecondary,
        textTertiary: EchoColors.textTertiary,
        accentPrimary: EchoColors.teal,
        accentSecondary: EchoColors.mint,
        accentMuted: const Color(0x1F2A4F52),
        danger: EchoColors.danger,
        dangerMuted: EchoColors.danger.withValues(alpha: 0.7),
        overlay: bgBaseNearBlack.withValues(alpha: 0.9),
        shadow: Colors.black.withValues(alpha: 0.35),
      );
    }

    return const EchoSemantic(
      bg: Color(0xFFF4F7FF),
      bgBaseNearBlack: Color(0xFFF4F7FF),
      bgGlowNavy: Color(0xFFEAF1FA),
      bgEdgeNearBlack: Color(0xFFF1F5FB),
      surface1: Color(0xFFFFFFFF),
      surface2: Color(0xFFEAF1FA),
      surface3: Color(0xFFF1F5FB),
      border: Color(0xFFD6DFEB),
      borderSubtle: Color(0xFFE7EEF6),
      textPrimary: EchoColors.deepNavy,
      textSecondary: Color(0xFF4E5E77),
      textTertiary: Color(0xFF7A8BA3),
      accentPrimary: EchoColors.teal,
      accentSecondary: EchoColors.mint,
      accentMuted: Color(0x1F2A4F52),
      danger: EchoColors.danger,
      dangerMuted: Color(0xB3B56D6D),
      overlay: Color(0xE6FFFFFF),
      shadow: Color(0x1A000000),
    );
  }

  @override
  EchoSemantic copyWith({
    Color? bg,
    Color? bgBaseNearBlack,
    Color? bgGlowNavy,
    Color? bgEdgeNearBlack,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accentPrimary,
    Color? accentSecondary,
    Color? accentMuted,
    Color? danger,
    Color? dangerMuted,
    Color? overlay,
    Color? shadow,
  }) {
    return EchoSemantic(
      bg: bg ?? this.bg,
      bgBaseNearBlack: bgBaseNearBlack ?? this.bgBaseNearBlack,
      bgGlowNavy: bgGlowNavy ?? this.bgGlowNavy,
      bgEdgeNearBlack: bgEdgeNearBlack ?? this.bgEdgeNearBlack,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      accentMuted: accentMuted ?? this.accentMuted,
      danger: danger ?? this.danger,
      dangerMuted: dangerMuted ?? this.dangerMuted,
      overlay: overlay ?? this.overlay,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  EchoSemantic lerp(ThemeExtension<EchoSemantic>? other, double t) {
    if (other is! EchoSemantic) {
      return this;
    }
    return EchoSemantic(
      bg: Color.lerp(bg, other.bg, t)!,
      bgBaseNearBlack:
          Color.lerp(bgBaseNearBlack, other.bgBaseNearBlack, t)!,
      bgGlowNavy: Color.lerp(bgGlowNavy, other.bgGlowNavy, t)!,
      bgEdgeNearBlack:
          Color.lerp(bgEdgeNearBlack, other.bgEdgeNearBlack, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerMuted: Color.lerp(dangerMuted, other.dangerMuted, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

ThemeData buildEchoTheme(Brightness brightness) {
  final resolvedBrightness = brightness == Brightness.dark
      ? Brightness.dark
      : Brightness.light;
  final tokens = EchoSemantic.fromBrightness(resolvedBrightness);
  final colorScheme = ColorScheme(
    brightness: resolvedBrightness,
    primary: tokens.accentPrimary,
    onPrimary: tokens.bg,
    secondary: tokens.surface2,
    onSecondary: tokens.textPrimary,
    tertiary: tokens.accentSecondary,
    onTertiary: resolvedBrightness == Brightness.dark
        ? tokens.bg
        : tokens.textPrimary,
    error: tokens.danger,
    onError: resolvedBrightness == Brightness.dark
        ? tokens.bg
        : tokens.textPrimary,
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
    fontFamily: 'Lora',
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
      elevation: 0,
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
      elevation: 6,
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
      circularTrackColor: tokens.surface3,
      linearTrackColor: tokens.surface3,
    ),
    iconTheme: IconThemeData(color: tokens.textPrimary),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface2,
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: tokens.textTertiary,
      ),
      labelStyle: textTheme.bodySmall?.copyWith(
        color: tokens.textSecondary,
      ),
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
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black.withValues(alpha: 0.55),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
        elevation: 1.5,
        shadowColor: Colors.white.withValues(alpha: 0.18),
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
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
        backgroundColor: Colors.black,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EchoRadii.button),
        ),
        textStyle: textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ).copyWith(
        elevation: WidgetStateProperty.all(1),
        shadowColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.18),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
        backgroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ).copyWith(
        elevation: WidgetStateProperty.all(1),
        shadowColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.18),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.white.withValues(alpha: 0.6);
          }
          return Colors.white;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.black.withValues(alpha: 0.55);
          }
          return Colors.black;
        }),
        elevation: WidgetStateProperty.all(1),
        shadowColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.18),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 1.5,
      highlightElevation: 2,
      focusElevation: 1.5,
      hoverElevation: 1.5,
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
            ? tokens.accentPrimary
            : tokens.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return tokens.accentPrimary.withValues(alpha: 0.45);
        }
        return tokens.surface3;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: tokens.accentPrimary,
      inactiveTrackColor: tokens.surface3,
      thumbColor: tokens.accentPrimary,
      overlayColor: tokens.accentPrimary.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.surface2,
      disabledColor: tokens.surface2.withValues(alpha: 0.6),
      selectedColor: tokens.accentPrimary,
      secondarySelectedColor: tokens.accentPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: textTheme.bodySmall?.copyWith(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: textTheme.bodySmall?.copyWith(
        color: tokens.bg,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EchoRadii.pill),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: tokens.surface1.withValues(alpha: 0.9),
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white.withValues(alpha: 0.6),
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.surface1.withValues(alpha: 0.9),
      indicatorColor: Colors.black.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return textTheme.labelSmall?.copyWith(
          color: isSelected
              ? Colors.white
              : Colors.white.withValues(alpha: 0.6),
          fontWeight: FontWeight.w600,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: isSelected
              ? Colors.white
              : Colors.white.withValues(alpha: 0.6),
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
    highlightColor: Colors.white.withValues(alpha: 0.08),
    hoverColor: Colors.white.withValues(alpha: 0.04),
    focusColor: Colors.white.withValues(alpha: 0.14),
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
  static LinearGradient tonal({
    required Color base,
    required Color depth,
    double top = 0.03,
    double bottom = 0.12,
    Alignment begin = Alignment.topLeft,
    Alignment end = Alignment.bottomRight,
  }) {
    final topColor = Color.lerp(base, depth, top)!;
    final bottomColor = Color.lerp(base, depth, bottom)!;
    return LinearGradient(
      begin: begin,
      end: end,
      colors: [topColor, bottomColor],
    );
  }

  static Color depthFor(EchoSemantic tokens, Brightness brightness) {
    return brightness == Brightness.dark ? tokens.bg : tokens.surface2;
  }

  static LinearGradient shell(EchoSemantic tokens, Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Color.lerp(tokens.bg, tokens.surface1, 0.08)!
        : tokens.bg;
    final depth = depthFor(tokens, brightness);
    return tonal(base: base, depth: depth, top: 0.04, bottom: 0.16);
  }

  static LinearGradient appBackground(
    EchoSemantic tokens,
    Brightness brightness,
  ) {
    if (brightness == Brightness.dark) {
      final topColor = tokens.bgEdgeNearBlack;
      final midColor = tokens.bgGlowNavy;
      final baseColor = tokens.bgBaseNearBlack;
      final bottomColor = tokens.bgEdgeNearBlack;
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, baseColor, midColor, baseColor, bottomColor],
        stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
      );
    }
    final topColor = Color.lerp(tokens.bg, tokens.surface2, 0.35)!;
    final midColor = tokens.bg;
    final bottomColor = Color.lerp(tokens.bg, tokens.surface2, 0.35)!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [topColor, midColor, bottomColor],
      stops: const [0.0, 0.5, 1.0],
    );
  }

  static LinearGradient hashtagCard(
    EchoSemantic tokens,
    Brightness brightness,
  ) {
    if (brightness == Brightness.dark) {
      final edge = Color.lerp(tokens.bgGlowNavy, tokens.bgBaseNearBlack, 0.22)!;
      final center = Color.lerp(tokens.bgBaseNearBlack, tokens.bgEdgeNearBlack, 0.65)!;
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [edge, center, edge],
        stops: const [0.0, 0.52, 1.0],
      );
    }
    final edge = Color.lerp(tokens.bgGlowNavy, tokens.bg, 0.25)!;
    final center = Color.lerp(tokens.bg, tokens.bgEdgeNearBlack, 0.5)!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [edge, center, edge],
      stops: const [0.0, 0.52, 1.0],
    );
  }
}
