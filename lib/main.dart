import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/app_scope.dart';
import 'app/app_state.dart';
import 'app/echo_app.dart';
import 'firebase_options.dart';
import 'theme/echo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await dotenv.load(fileName: '.env').catchError((_) {
    // Optional local development fallback.
  });

  final appState = await AppState.create();
  final lightTheme = buildEchoTheme(Brightness.light);
  final darkTheme = buildEchoTheme(Brightness.dark);
  runApp(
    AppScope(
      state: appState,
      child: EchoApp(
        appState: appState,
        theme: lightTheme,
        darkTheme: darkTheme,
      ),
    ),
  );
}
