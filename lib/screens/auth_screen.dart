import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    final mode = GoRouterState.of(context).uri.queryParameters['mode'];
    final next = GoRouterState.of(context).uri.queryParameters['next'];
    final isSignUp = mode == 'signup';

    return AppScaffold(
      child: Padding(
        padding: EchoLayout.pagePadding(context, top: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isSignUp ? 'Create account' : 'Sign in to post',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Authentication is temporarily unavailable in this build. '
              'You can continue as a guest.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                if (next == 'post') {
                  context.pop();
                } else {
                  context.go('/listen');
                }
              },
              child: const Text('Continue as guest'),
            ),
            if (appState.isAuthenticated)
              OutlinedButton(
                onPressed: () async {
                  await appState.signOut();
                  if (!context.mounted) return;
                  context.go('/listen');
                },
                child: const Text('Sign out'),
              ),
          ],
        ),
      ),
    );
  }
}
