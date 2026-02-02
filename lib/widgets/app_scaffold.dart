import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/echo_theme.dart';
import '../utils/responsive.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, required this.child, this.bottomNavigationBar});

  final Widget child;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final maxWidth = EchoLayout.maxContentWidth(context);
    final tokens = context.echo;
    final brightness = Theme.of(context).brightness;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: tokens.bg,
        resizeToAvoidBottomInset: true,
        bottomNavigationBar: bottomNavigationBar,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
