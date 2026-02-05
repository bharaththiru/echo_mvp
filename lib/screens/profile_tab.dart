import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
import '../utils/time_format.dart';
import '../utils/responsive.dart';
import '../widgets/echo_components.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final appState = AppScope.of(context);
    final isAuthenticated = appState.isAuthenticated;
    final skipAuth = appState.skipAuth;
    final userEmail = appState.userEmail;
    final savedHashtags = appState.savedHashtags;
    final myPosts = appState.userPosts();
    final showTranscript = appState.settings.transcriptsEnabled;

    return Column(
      children: [
        EchoHeaderShell(
          padding: EchoLayout.pagePadding(
            context,
            top: 8,
            bottom: 6,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('Profile', style: theme.textTheme.displaySmall),
              ),
              IconButton(
                onPressed: () => context.push('/settings'),
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EchoLayout.listPadding(context),
            children: [
              EchoCard(
                padding: const EdgeInsets.all(20),
                radius: 24,
                child: Column(
                  children: [
                    Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tokens.accentPrimary,
                      ),
                      child: Icon(
                        Icons.person,
                        color: tokens.bg,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      userEmail ?? 'Echo Listener',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      skipAuth
                          ? 'Dev mode: auth skipped'
                          : userEmail != null
                          ? 'Signed in'
                          : 'Sign in to sync your notes',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: isAuthenticated
                          ? () async {
                              await appState.signOut();
                            }
                          : () => context.go('/auth'),
                      child: Text(isAuthenticated ? 'Sign out' : 'Sign in'),
                    ),
                  ],
                ),
              ),
              SizedBox(height: EchoLayout.space(context, 14)),
              Row(
                children: [
                  Icon(Icons.bookmark, color: tokens.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Saved hashtags',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: savedHashtags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surface2,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      tag,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: EchoLayout.space(context, 14)),
              const EchoSectionTitle('My posts'),
              SizedBox(height: EchoLayout.space(context, 8)),
              if (myPosts.isEmpty)
                EchoCard(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'Record a note to see it here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                )
              else
                ...myPosts.map((post) {
                  return EchoCard(
                    margin: EdgeInsets.only(
                      bottom: EchoLayout.space(context, 8),
                    ),
                    padding: const EdgeInsets.all(14),
                    radius: 20,
                    child: Row(
                      children: [
                        Container(
                          height: 36,
                          width: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.18),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    post.hashtagLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: tokens.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    formatRelativeTime(post.createdAt),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                showTranscript
                                    ? (post.transcriptPreview ?? 'Voice note')
                                    : 'Voice note',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary.withValues(
                                    alpha: 0.92,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              SizedBox(height: EchoLayout.space(context, 14)),
              const EchoSectionTitle('Preferences'),
              SizedBox(height: EchoLayout.space(context, 8)),
              _PreferenceTile(
                title: 'Listening preferences',
                onTap: () => context.push('/settings'),
              ),
              const SizedBox(height: 8),
              _PreferenceTile(
                title: 'Privacy and safety',
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return EchoCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      radius: 18,
      color: tokens.surface2,
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
          Icon(Icons.chevron_right, color: tokens.textSecondary),
        ],
      ),
    );
  }
}
