import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app_scope.dart';
import 'app/app_state.dart';
import 'app/echo_app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final appState = await AppState.create();
  runApp(
    AppScope(
      state: appState,
      child: EchoApp(appState: appState),
    ),
  );
}
