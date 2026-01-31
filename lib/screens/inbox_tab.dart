import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../utils/time_format.dart';
import '../utils/responsive.dart';
import '../widgets/echo_components.dart';

class InboxTab extends StatefulWidget {
  const InboxTab({super.key});

  @override
  State<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<InboxTab> {
  bool _loaded = false;
  String? _loadingNoteId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    final appState = AppScope.of(context);
    appState.refreshMyPosts();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = AppScope.of(context);
    final myPosts = appState.userPosts();
    final showTranscript = appState.settings.transcriptsEnabled;
    final isLoading = appState.myPostsLoading;
    final loadError = appState.myPostsError;

    return Column(
      children: [
        Padding(
          padding: EchoLayout.pagePadding(
            context,
            top: 32,
            bottom: 16,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Inbox', style: theme.textTheme.displaySmall),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EchoLayout.listPadding(context),
            children: [
              if (!appState.isAuthenticated && !appState.skipAuth)
                EchoCard(
                  padding: const EdgeInsets.all(16),
                  radius: 18,
                  color: EchoColors.muted,
                  child: Text(
                    'Sign in to see your posted notes here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: EchoColors.textSecondary,
                    ),
                  ),
                )
              else
                EchoCard(
                  padding: const EdgeInsets.all(16),
                  radius: 18,
                  color: EchoColors.muted,
                  child: Text(
                    'Replies are coming soon. Your latest posts show up here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: EchoColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const EchoSectionTitle('Your posts'),
              const SizedBox(height: 12),
              if (isLoading && myPosts.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (loadError != null && myPosts.isEmpty)
                _EmptyState(
                  title: 'Unable to load posts',
                  subtitle: loadError,
                  onRetry: () => appState.refreshMyPosts(force: true),
                )
              else if (myPosts.isEmpty)
                EchoCard(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'No posts yet. Record a note to see it here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: EchoColors.textSecondary,
                    ),
                  ),
                )
              else
                ...myPosts.map((post) {
                  final isPreparing = _loadingNoteId == post.id;
                  return EchoCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    radius: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              post.hashtagLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: EchoColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatRelativeTime(post.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: EchoColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          showTranscript
                              ? (post.transcriptPreview ?? 'Voice note')
                              : 'Voice note',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: EchoColors.textSecondary.withValues(
                              alpha: 0.92,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IconButton.filled(
                              onPressed: isPreparing
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      setState(() => _loadingNoteId = post.id);
                                      final path = await appState
                                          .ensureLocalAudioPath(post);
                                      if (!mounted) {
                                        return;
                                      }
                                      setState(() => _loadingNoteId = null);
                                      if (path == null || path.isEmpty) {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Playback is not available.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      appState.audio.toggle(
                                        sourceId: post.id,
                                        path: path,
                                      );
                                    },
                              icon: isPreparing
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              EchoColors.background,
                                            ),
                                      ),
                                    )
                                  : const Icon(Icons.play_arrow),
                              style: IconButton.styleFrom(
                                backgroundColor: EchoColors.accent,
                                foregroundColor: EchoColors.background,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              post.allowReplies
                                  ? 'Replies enabled'
                                  : 'Replies disabled',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: EchoColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: EchoLayout.horizontalPadding(context),
        ),
        child: EchoCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: EchoColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
