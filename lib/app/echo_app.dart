import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_state.dart';
import 'router.dart';
import '../theme/echo_theme.dart';

class EchoApp extends StatefulWidget {
  const EchoApp({
    super.key,
    required this.appState,
    this.theme,
    this.darkTheme,
  });

  final AppState appState;
  final ThemeData? theme;
  final ThemeData? darkTheme;

  @override
  State<EchoApp> createState() => _EchoAppState();
}

class _EchoAppState extends State<EchoApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRouter.create(widget.appState);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'Echo',
          debugShowCheckedModeBanner: false,
          theme: widget.theme ?? buildEchoTheme(Brightness.light),
          darkTheme: widget.darkTheme ?? buildEchoTheme(Brightness.dark),
          themeMode: widget.appState.settings.themeMode,
          routerConfig: _router,
        );
      },
    );
  }
}
