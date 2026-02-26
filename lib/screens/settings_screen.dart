import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final appState = AppScope.of(context);

    return AppScaffold(
      child: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          final settings = appState.settings;
          return Column(
            children: [
              EchoHeaderShell(
                padding: EchoLayout.pagePadding(
                  context,
                  top: 8,
                  bottom: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                    SizedBox(height: EchoLayout.space(context, 8)),
                    Text('Settings', style: theme.textTheme.displaySmall),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EchoLayout.listPadding(context, bottom: 8),
                  children: [
                    const EchoSectionTitle('Appearance'),
                    const SizedBox(height: 12),
                    EchoCard(
                      padding: const EdgeInsets.all(16),
                      radius: 18,
                      color: tokens.surface2,
                      child: Row(
                        children: [
                          Icon(
                            Icons.nightlight_round,
                            size: 20,
                            color: tokens.accentPrimary,
                          ),
                          const SizedBox(width: 12),
                          Text('Dark mode',
                              style: theme.textTheme.titleSmall),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ToggleTile(
                      title: 'Subtle mood tint',
                      subtitle: 'Soft accent on active stations',
                      value: settings.moodTintEnabled,
                      onChanged: appState.updateMoodTint,
                    ),
                    const SizedBox(height: 12),
                    _ToggleTile(
                      title: 'Caption preview',
                      subtitle: 'Show the caption under each note',
                      value: settings.transcriptsEnabled,
                      onChanged: appState.updateTranscripts,
                    ),
                    const SizedBox(height: 12),
                    _ToggleTile(
                      title: 'Reduce motion',
                      subtitle: 'Minimize animations and transitions',
                      value: settings.reduceMotion,
                      onChanged: appState.updateReduceMotion,
                    ),
                    const SizedBox(height: 24),
                    const EchoSectionTitle('Notifications'),
                    const SizedBox(height: 12),
                    _ToggleTile(
                      title: 'Private replies',
                      subtitle:
                          'Get notified when someone replies to your post',
                      value: settings.repliesNotifications,
                      onChanged: appState.updateRepliesNotifications,
                    ),
                    const SizedBox(height: 12),
                    _ToggleTile(
                      title: 'New posts in saved hashtags',
                      subtitle: 'Optional gentle reminders',
                      value: settings.hashtagNotifications,
                      onChanged: appState.updateHashtagNotifications,
                    ),
                    const SizedBox(height: 24),
                    const EchoSectionTitle('Privacy and safety'),
                    const SizedBox(height: 12),
                    _LinkTile(
                      title: 'Blocked accounts',
                      subtitle: 'Manage your blocklist',
                    ),
                    const SizedBox(height: 8),
                    _LinkTile(
                      title: 'Report history',
                      subtitle: 'View your past reports',
                    ),

                    const SizedBox(height: 24),
                    const EchoSectionTitle('Account'),
                    const SizedBox(height: 12),
                    EchoCard(
                      padding: const EdgeInsets.all(16),
                      radius: 18,
                      color: tokens.surface2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            appState.isAuthenticated
                                ? (appState.userEmail ?? 'Signed in')
                                : 'Guest mode',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            appState.isAuthenticated
                                ? 'You can sign out or delete your account.'
                                : 'Sign in from here any time to post.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () async {
                              if (appState.isAuthenticated) {
                                await appState.signOut();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Signed out.')),
                                );
                                return;
                              }
                              context.push('/auth?mode=signup');
                            },
                            child: Text(
                              appState.isAuthenticated ? 'Sign out' : 'Sign up / sign in',
                            ),
                          ),
                          if (appState.isAuthenticated) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: const Text('Delete account?'),
                                      content: const Text(
                                        'This permanently deletes your Echo account from Clerk.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                                if (confirmed != true) {
                                  return;
                                }
                                await appState.deleteAccount();
                                if (!context.mounted) return;
                                context.go('/listen');
                              },
                              child: const Text('Delete account'),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const EchoSectionTitle('Legal'),
                    const SizedBox(height: 12),
                    _LinkTile(title: 'Community guidelines'),
                    const SizedBox(height: 8),
                    _LinkTile(title: 'Privacy policy'),
                    const SizedBox(height: 8),
                    _LinkTile(title: 'Terms of service'),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Echo v1.0.0',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return EchoCard(
      padding: const EdgeInsets.all(16),
      radius: 18,
      color: tokens.surface2,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return EchoCard(
      padding: const EdgeInsets.all(16),
      radius: 18,
      color: tokens.surface2,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: tokens.textSecondary),
        ],
      ),
    );
  }
}
