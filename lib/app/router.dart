import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/autoplay_player.dart';
import '../screens/auth_screen.dart';
import '../screens/hashtag_detail.dart';
import '../screens/listen_tab.dart';
import '../screens/onboarding_screen.dart';
import '../screens/post_options.dart';
import '../screens/profile_tab.dart';
import '../screens/record_tab.dart';
import '../screens/settings_screen.dart';
import '../widgets/bottom_nav.dart';
import 'app_state.dart';

class AppRouter {
  static GoRouter create(AppState appState) {
    final rootNavigatorKey = GlobalKey<NavigatorState>();

    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/',
      refreshListenable: appState,
      redirect: (context, state) {
        final onboardingComplete = appState.onboardingComplete;
        final isOnboardingRoute = state.matchedLocation.startsWith(
          '/onboarding',
        );
        if (!onboardingComplete && !isOnboardingRoute) {
          return '/onboarding';
        }
        if (onboardingComplete && isOnboardingRoute) {
          return '/listen';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          redirect: (context, state) =>
              appState.onboardingComplete ? '/listen' : '/onboarding',
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return BottomNavShell(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/listen',
                  builder: (context, state) => const ListenTab(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/record',
                  builder: (context, state) => const RecordTab(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (context, state) => const ProfileTab(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/hashtag/:id',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            return HashtagDetail(hashtagId: id);
          },
        ),
        GoRoute(
          path: '/player/:hashtagId',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) {
            final id = state.pathParameters['hashtagId'] ?? '';
            return AutoplayPlayer(hashtagId: id);
          },
        ),
        GoRoute(
          path: '/post-options',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const PostOptions(),
        ),
        GoRoute(
          path: '/settings',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );
  }
}
