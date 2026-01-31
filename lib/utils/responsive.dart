import 'package:flutter/material.dart';

class EchoLayout {
  static double screenWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

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

  static EdgeInsets pagePadding(
    BuildContext context, {
    double top = 32,
    double bottom = 24,
  }) {
    final horizontal = horizontalPadding(context);
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  static EdgeInsets listPadding(
    BuildContext context, {
    double top = 0,
    double bottom = 24,
  }) {
    final horizontal = horizontalPadding(context);
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
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
