import 'package:flutter/material.dart';

class EchoLayout {
  static double screenWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static double verticalScale(BuildContext context) =>
      (screenHeight(context) / 844).clamp(0.85, 1.1).toDouble();

  static double space(BuildContext context, double base) =>
      (base * verticalScale(context)).toDouble();

  static bool isCompact(BuildContext context) => screenWidth(context) < 360;

  static bool isTight(BuildContext context) => screenWidth(context) < 420;

  static double horizontalPadding(BuildContext context) {
    if (isCompact(context)) {
      return 16;
    }
    if (isTight(context)) {
      return 20;
    }
    return 24;
  }

  static double contentHorizontalPadding(BuildContext context) {
    return (horizontalPadding(context) * 0.55).clamp(10.0, 14.0).toDouble();
  }

  static EdgeInsets pagePadding(
    BuildContext context, {
    double top = 8,
    double bottom = 8,
    bool includeTopSafeArea = true,
    bool includeBottomSafeArea = false,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final horizontal = contentHorizontalPadding(context);
    final safeTop = includeTopSafeArea ? mediaQuery.padding.top : 0.0;
    final safeBottom = includeBottomSafeArea ? mediaQuery.padding.bottom : 0.0;
    return EdgeInsets.fromLTRB(
      horizontal,
      safeTop + space(context, top),
      horizontal,
      safeBottom + space(context, bottom),
    );
  }

  static EdgeInsets listPadding(
    BuildContext context, {
    double top = 0,
    double bottom = 10,
    bool includeBottomSafeArea = false,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final horizontal = contentHorizontalPadding(context);
    final safeBottom = includeBottomSafeArea ? mediaQuery.padding.bottom : 0.0;
    return EdgeInsets.fromLTRB(
      horizontal,
      space(context, top),
      horizontal,
      safeBottom + space(context, bottom),
    );
  }

  static double buttonHeight(
    BuildContext context, {
    double base = 54,
  }) {
    return isCompact(context) ? base - 4 : base;
  }

  static double secondaryButtonHeight(
    BuildContext context, {
    double base = 52,
  }) {
    return isCompact(context) ? base - 4 : base;
  }

  static double maxContentWidth(BuildContext context) {
    final width = screenWidth(context);
    return width < 520 ? width : 520;
  }
}
