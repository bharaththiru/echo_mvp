import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';

Future<void> requireAuth(
  BuildContext context,
  Future<void> Function() onAuthed,
) async {
  final appState = AppScope.of(context);
  if (appState.isAuthenticated) {
    await onAuthed();
    return;
  }

  await context.push('/auth?next=post');
  if (!context.mounted) {
    return;
  }
  if (!appState.isAuthenticated) {
    return;
  }
  await onAuthed();
}
