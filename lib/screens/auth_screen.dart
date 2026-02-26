import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    final mode = GoRouterState.of(context).uri.queryParameters['mode'];
    final next = GoRouterState.of(context).uri.queryParameters['next'];
    final isSignUp = mode == 'signup';

    Future<void> handleSuccess() async {
      if (!context.mounted) return;
      if (next == 'post') {
        context.pop();
        return;
      }
      context.go('/listen');
    }

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
              'Listening works without login. Posting requires an account.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ClerkAuthCard(
                initialMode: isSignUp ? ClerkAuthMode.signUp : ClerkAuthMode.signIn,
                onSignedIn: handleSuccess,
              ),
            ),
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
