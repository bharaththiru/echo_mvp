import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
import '../models/hashtag.dart';
import '../models/voice_note.dart';
import '../services/audio_controller.dart';
import '../utils/time_format.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';
import '../widgets/report_reason_sheet.dart';

class HashtagDetail extends StatefulWidget {
  const HashtagDetail({super.key, required this.hashtagId});

  final String hashtagId;

  @override
  State<HashtagDetail> createState() => _HashtagDetailState();
}

class _HashtagDetailState extends State<HashtagDetail> {
  String? _loadingNoteId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = AppScope.of(context);
    if (appState.hashtags.isEmpty && !appState.hashtagsLoading) {
      appState.refreshHashtags();
    }
    appState.loadNotesForHashtag(widget.hashtagId);
  }

  Future<void> _handleMenuAction(VoiceNote note, String action) async {
    final appState = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    switch (action) {
      case 'save':
        messenger.showSnackBar(
          const SnackBar(content: Text('Saved to your library.')),
        );
        return;
      case 'share':
        messenger.showSnackBar(
          const SnackBar(content: Text('Link copied.')),
        );
        return;
      case 'hide':
        final result = appState.hideClip(note);
        messenger.showSnackBar(SnackBar(content: Text(result.message)));
        return;
      case 'report':
        final reason = await showReportReasonSheet(context);
        if (!mounted || reason == null) {
          return;
        }
        final result = await appState.reportClip(
          note: note,
          reason: reason,
        );
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(SnackBar(content: Text(result.message)));
        return;
      case 'block':
        final result = await appState.blockAuthor(note);
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(SnackBar(content: Text(result.message)));
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final appState = AppScope.of(context);
    final hashtag = appState.hashtagById(widget.hashtagId);
    if (hashtag == null && appState.hashtagsLoading) {
      return const AppScaffold(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (hashtag == null) {
      return AppScaffold(
        child: Center(
          child: Text('Hashtag not found.', style: theme.textTheme.titleMedium),
        ),
      );
    }
    final notes = appState.notesForHashtag(hashtag.id);
    final isLoading = appState.isLoadingNotes(hashtag.id);
    final loadError = appState.notesError(hashtag.id);
    final audio = appState.audio;
    final moodTint = appState.settings.moodTintEnabled;
    final horizontal = EchoLayout.contentHorizontalPadding(context);
    final safeTop = MediaQuery.paddingOf(context).top;

    return AppScaffold(
      child: AnimatedBuilder(
        animation: audio,
        builder: (context, _) {
          if (isLoading && notes.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (loadError != null && notes.isEmpty) {
            return _EmptyState(
              title: 'Unable to load notes',
              subtitle: loadError,
              onRetry: () =>
                  appState.loadNotesForHashtag(hashtag.id, force: true),
            );
          }
          if (notes.isEmpty) {
            return _EmptyState(
              title: 'No notes yet',
              subtitle: 'Be the first to post in ${hashtag.name}.',
              onRetry: () =>
                  appState.loadNotesForHashtag(hashtag.id, force: true),
            );
          }

          return NestedScrollView(
            physics: const BouncingScrollPhysics(),
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                pinned: true,
                automaticallyImplyLeading: false,
                backgroundColor: tokens.bg,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                expandedHeight: 338,
                collapsedHeight: 72,
                titleSpacing: horizontal,
                title: Text(
                  hashtag.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _AutoplayChip(
                      onTap: () => context.push('/player/${hashtag.id}'),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      safeTop + EchoLayout.space(context, 4),
                      horizontal,
                      EchoLayout.space(context, 8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton.icon(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back'),
                        ),
                        const SizedBox(height: 8),
                        _HashtagHeader(
                          hashtag: hashtag,
                          moodTintEnabled: moodTint,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${notes.length} notes',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: EchoLayout.listPadding(
                context,
                top: 6,
                bottom: 8,
                includeBottomSafeArea: true,
              ),
              itemCount: notes.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final note = notes[index];
                final isPreparing = _loadingNoteId == note.id;
                final canBlock =
                    note.authorId != null &&
                    note.authorId!.isNotEmpty &&
                    note.authorId != appState.userId;
                return _VoiceNoteCard(
                  note: note,
                  isPreparing: isPreparing,
                  audioState: audio.state,
                  transcriptsEnabled: appState.settings.transcriptsEnabled,
                  canBlock: canBlock,
                  onPlay: () async {
                    if (isPreparing) {
                      return;
                    }
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _loadingNoteId = note.id);
                    final path = await appState.ensureLocalAudioPath(note);
                    if (!mounted) {
                      return;
                    }
                    setState(() => _loadingNoteId = null);
                    if (path == null || path.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Playback is not available.'),
                        ),
                      );
                      return;
                    }
                    audio.toggle(sourceId: note.id, path: path);
                  },
                  onMenuSelected: (action) => _handleMenuAction(note, action),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AutoplayChip extends StatelessWidget {
  const _AutoplayChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.echo;
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: const Icon(Icons.play_arrow, size: 18),
      label: const Text('Auto-play'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        backgroundColor: tokens.accentPrimary.withValues(alpha: 0.16),
        foregroundColor: tokens.accentPrimary,
      ),
    );
  }
}

class _HashtagHeader extends StatelessWidget {
  const _HashtagHeader({required this.hashtag, required this.moodTintEnabled});

  final Hashtag hashtag;
  final bool moodTintEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final tint = hashtag.gradient.first;
    final surfaceColor = moodTintEnabled
        ? Color.lerp(tokens.surface1, tint, 0.6) ?? tokens.surface1
        : tokens.surface1;
    final borderColor = moodTintEnabled
        ? tint.withValues(alpha: 0.6)
        : tokens.borderSubtle;

    return EchoCard(
      padding: const EdgeInsets.all(22),
      radius: 24,
      color: surfaceColor,
      borderColor: borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(hashtag.icon, size: 40, color: tokens.accentPrimary),
          const SizedBox(height: 12),
          Text(hashtag.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            hashtag.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceNoteCard extends StatelessWidget {
  const _VoiceNoteCard({
    required this.note,
    required this.isPreparing,
    required this.audioState,
    required this.transcriptsEnabled,
    required this.canBlock,
    required this.onPlay,
    required this.onMenuSelected,
  });

  final VoiceNote note;
  final bool isPreparing;
  final AudioPlaybackState audioState;
  final bool transcriptsEnabled;
  final bool canBlock;
  final VoidCallback onPlay;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final isActive = audioState.sourceId == note.id;
    final isPlaying = isActive && audioState.isPlaying;
    final progress = isActive ? audioState.progress : 0.0;
    final timestamp = formatRelativeTime(note.createdAt);

    return EchoCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Anonymous - $timestamp',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    if (transcriptsEnabled &&
                        note.transcriptPreview != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        note.transcriptPreview!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary.withValues(
                            alpha: 0.92,
                          ),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: tokens.surface1,
                onSelected: onMenuSelected,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'save', child: Text('Save')),
                  const PopupMenuItem(
                    value: 'share',
                    child: Text('Share link'),
                  ),
                  const PopupMenuItem(value: 'hide', child: Text('Hide clip')),
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Report & hide'),
                  ),
                  PopupMenuItem(
                    value: 'block',
                    enabled: canBlock,
                    child: const Text('Block user'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton.filled(
                onPressed: onPlay,
                icon: isPreparing
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            tokens.bg,
                          ),
                        ),
                      )
                    : Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                style: IconButton.styleFrom(
                  backgroundColor: tokens.accentPrimary,
                  foregroundColor: tokens.bg,
                  padding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress.isNaN ? 0 : progress.clamp(0, 1),
                        minHeight: 6,
                        backgroundColor: tokens.surface3,
                        valueColor: AlwaysStoppedAnimation(
                          tokens.accentPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatDuration(
                            isActive ? audioState.position : Duration.zero,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surface2,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            formatDuration(note.duration),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
    final tokens = context.echo;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: EchoLayout.contentHorizontalPadding(context),
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
                  color: tokens.textSecondary,
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
