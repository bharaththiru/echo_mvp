import 'package:clerk_flutter/clerk_flutter.dart';
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
        child: SafeArea(
          child: ClerkErrorListener(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isSignUp ? 'Create account' : 'Sign in to post',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ClerkAuthBuilder(
                    signedInBuilder: (context, authState) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        appState.refreshAuthStatus();
                      });
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          const ClerkUserButton(),
                          const SizedBox(height: 12),
                          Text(
                            'You are signed in and can post to Echo.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () {
                              if (next == 'post') {
                                context.pop();
                              } else {
                                context.go('/listen');
                              }
                            },
                            child: const Text('Continue'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () async {
                              await appState.signOut();
                              if (!context.mounted) return;
                              context.go('/listen');
                            },
                            child: const Text('Sign out'),
                          ),
                        ],
                      );
                    },
                    signedOutBuilder: (context, authState) {
                      return const ClerkAuthentication();
                    },
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
