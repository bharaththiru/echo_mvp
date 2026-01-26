import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_scope.dart';
import 'app/app_state.dart';
import 'app/echo_app.dart';
import 'app/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseConfig.validate();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  final appState = await AppState.create();
  runApp(
    AppScope(
      state: appState,
      child: EchoApp(appState: appState),
    ),
  );
}
