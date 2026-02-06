import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
import '../models/hashtag.dart';
import '../models/voice_note.dart';
import '../services/audio_controller.dart';
import '../services/autoplay_controller.dart';
import '../utils/time_format.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';
import '../widgets/listenable_selector.dart';
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
    final horizontal = EchoLayout.contentHorizontalPadding(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final expandedHeight = kToolbarHeight + EchoLayout.space(context, 244);
    final collapsedHeight = kToolbarHeight + EchoLayout.space(context, 52);
    final fabRightOffset = horizontal + EchoLayout.space(context, 7);
    final autoplay = appState.autoplay;
    final audio = appState.audio;

    return AppScaffold(
      child: ListenableSelector<bool>(
        listenable: autoplay,
        selector: () {
          final state = autoplay.state;
          return state.queue.isNotEmpty &&
              state.currentNote != null &&
              state.phase != AutoplayPhase.idle &&
              state.phase != AutoplayPhase.completed;
        },
        shouldRebuild: (previous, next) => previous != next,
        builder: (context, miniPlayerVisible) {
          final fabBottomOffset = safeBottom + EchoLayout.space(
            context,
            miniPlayerVisible ? 126 : 28,
          );
          final listBottomPadding = miniPlayerVisible ? 196.0 : 124.0;

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

          return Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    leading: IconButton(
                      tooltip: 'Back',
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    backgroundColor: tokens.bg,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    expandedHeight: expandedHeight,
                    collapsedHeight: collapsedHeight,
                    flexibleSpace: _HashtagHeaderFlexibleSpace(
                      hashtag: hashtag,
                      noteCount: notes.length,
                    ),
                  ),
                  SliverPadding(
                    padding: EchoLayout.listPadding(
                      context,
                      top: 2,
                      bottom: listBottomPadding,
                      includeBottomSafeArea: true,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index.isOdd) {
                            return const SizedBox(height: 12);
                          }
                          final note = notes[index ~/ 2];
                          final isPreparing = _loadingNoteId == note.id;
                          final canBlock =
                              note.authorId != null &&
                              note.authorId!.isNotEmpty &&
                              note.authorId != appState.userId;
                          return _VoiceNoteCard(
                            note: note,
                            isPreparing: isPreparing,
                            audio: audio,
                            transcriptsEnabled:
                                appState.settings.transcriptsEnabled,
                            canBlock: canBlock,
                            onPlay: () async {
                              if (isPreparing) {
                                return;
                              }
                              final messenger = ScaffoldMessenger.of(context);
                              setState(() => _loadingNoteId = note.id);
                              final path = await appState.ensureLocalAudioPath(
                                note,
                              );
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
                              audio.toggle(sourceId: note.id, path: path);
                            },
                            onMenuSelected: (action) =>
                                _handleMenuAction(note, action),
                          );
                        },
                        childCount: notes.isEmpty ? 0 : (notes.length * 2 - 1),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: fabRightOffset,
                bottom: fabBottomOffset,
                child: _AutoplayFab(
                  onTap: () => context.push('/player/${hashtag.id}'),
                  heroTag: 'autoplay-fab-${hashtag.id}',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HashtagHeaderFlexibleSpace extends StatelessWidget {
  const _HashtagHeaderFlexibleSpace({
    required this.hashtag,
    required this.noteCount,
  });

  final Hashtag hashtag;
  final int noteCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final horizontal = EchoLayout.contentHorizontalPadding(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final maxExtent = settings?.maxExtent ?? 1.0;
    final minExtent = settings?.minExtent ?? 1.0;
    final currentExtent = settings?.currentExtent ?? maxExtent;
    final range = (maxExtent - minExtent).abs() < 1 ? 1.0 : (maxExtent - minExtent);
    final collapseProgress = ((maxExtent - currentExtent) / range).clamp(
      0.0,
      1.0,
    );
    final easedProgress = Curves.easeOutCubic.transform(collapseProgress);
    final notesFactor = 1 - Curves.easeOut.transform(easedProgress);
    final gap = lerpDouble(6, 2, easedProgress) ?? 4;

    return DecoratedBox(
      decoration: BoxDecoration(color: tokens.bg),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontal,
          safeTop + kToolbarHeight + EchoLayout.space(context, 2),
          horizontal,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HashtagHeader(
              hashtag: hashtag,
              collapseProgress: easedProgress,
            ),
            SizedBox(height: gap),
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                heightFactor: notesFactor.clamp(0.0, 1.0),
                child: Text(
                  '$noteCount notes',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoplayFab extends StatelessWidget {
  const _AutoplayFab({required this.onTap, required this.heroTag});

  final VoidCallback onTap;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final tokens = context.echo;
    final buttonFill = tokens.accentPrimary;
    final onButtonFill = EchoColorUtils.onColor(buttonFill);
    return Semantics(
      button: true,
      label: 'Start autoplay',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: 64,
          child: FloatingActionButton(
            heroTag: heroTag,
            tooltip: 'Start autoplay',
            onPressed: onTap,
            backgroundColor: buttonFill,
            foregroundColor: onButtonFill,
            elevation: 0,
            highlightElevation: 0,
            child: const Icon(Icons.play_arrow_rounded, size: 36),
          ),
        ),
      ),
    );
  }
}

class _HashtagHeader extends StatelessWidget {
  const _HashtagHeader({
    required this.hashtag,
    this.collapseProgress = 0,
  });

  final Hashtag hashtag;
  final double collapseProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final tileColor = tokens.surface1;
    final onTile = tokens.textPrimary;
    final mutedOnTile = tokens.textSecondary;
    final compactEase = Curves.easeOutCubic.transform(collapseProgress);
    final iconFactor = (1 - Curves.easeOut.transform(compactEase)).clamp(0.0, 1.0);
    final descriptionFactor = (1 - Curves.easeIn.transform(compactEase)).clamp(
      0.0,
      1.0,
    );
    final cardPadding = EdgeInsets.lerp(
      const EdgeInsets.all(22),
      const EdgeInsets.fromLTRB(18, 12, 18, 12),
      compactEase,
    )!;
    final iconSize = lerpDouble(40, 28, compactEase) ?? 40;
    final radius = lerpDouble(24, 18, compactEase) ?? 24;
    final baseTitleStyle = TextStyle.lerp(
      theme.textTheme.headlineSmall,
      theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      compactEase,
    );
    final titleStyle = baseTitleStyle?.copyWith(color: onTile);
    final titleGap = lerpDouble(10, 0, compactEase) ?? 6;
    final descriptionGap = lerpDouble(8, 2, compactEase) ?? 5;

    return EchoCard(
      padding: cardPadding,
      radius: radius,
      color: tileColor,
      overlayColor: EchoColorUtils.pressedOverlay(tileColor, alpha: 0.14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              heightFactor: iconFactor,
              child: Icon(
                hashtag.icon,
                size: iconSize,
                color: tokens.textSecondary,
              ),
            ),
          ),
          SizedBox(height: titleGap),
          Text(hashtag.name, style: titleStyle),
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              heightFactor: descriptionFactor,
              child: Padding(
                padding: EdgeInsets.only(top: descriptionGap),
                child: Text(
                  hashtag.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: mutedOnTile,
                    height: 1.45,
                  ),
                ),
              ),
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
    required this.audio,
    required this.transcriptsEnabled,
    required this.canBlock,
    required this.onPlay,
    required this.onMenuSelected,
  });

  final VoiceNote note;
  final bool isPreparing;
  final AudioController audio;
  final bool transcriptsEnabled;
  final bool canBlock;
  final VoidCallback onPlay;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final buttonFill = tokens.accentPrimary;
    final loadingForeground = EchoColorUtils.onColor(
      buttonFill.withValues(alpha: 0.35),
    ).withValues(alpha: 0.5);
    final timestamp = formatRelativeTime(note.createdAt);

    return ListenableSelector<_NotePlaybackSnapshot>(
      listenable: audio,
      selector: () {
        final state = audio.state;
        if (state.sourceId != note.id) {
          return _NotePlaybackSnapshot.inactive(note.duration);
        }
        final duration = state.duration.inMilliseconds > 0
            ? state.duration
            : note.duration;
        final ratio = duration.inMilliseconds == 0
            ? 0.0
            : (state.position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble();
        return _NotePlaybackSnapshot(
          isActive: true,
          isPlaying: state.isPlaying,
          progress: ratio,
          position: state.position,
          duration: duration,
        );
      },
      shouldRebuild: (previous, next) => previous != next,
      builder: (context, playback) {
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
                      const PopupMenuItem(
                        value: 'hide',
                        child: Text('Hide clip'),
                      ),
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
                    style: IconButton.styleFrom(
                      backgroundColor: buttonFill,
                      foregroundColor: EchoColorUtils.onColor(buttonFill),
                    ),
                    icon: isPreparing
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                loadingForeground,
                              ),
                            ),
                          )
                        : Icon(
                            playback.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                    padding: const EdgeInsets.all(16),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value:
                                playback.progress.isNaN
                                    ? 0
                                    : playback.progress.clamp(0, 1),
                            minHeight: 6,
                            backgroundColor:
                                tokens.textSecondary.withValues(alpha: 0.2),
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
                                playback.isActive
                                    ? playback.position
                                    : Duration.zero,
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
                                formatDuration(playback.duration),
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
      },
    );
  }
}

class _NotePlaybackSnapshot {
  const _NotePlaybackSnapshot({
    required this.isActive,
    required this.isPlaying,
    required this.progress,
    required this.position,
    required this.duration,
  });

  const _NotePlaybackSnapshot.inactive(Duration duration)
    : isActive = false,
      isPlaying = false,
      progress = 0.0,
      position = Duration.zero,
      duration = duration;

  final bool isActive;
  final bool isPlaying;
  final double progress;
  final Duration position;
  final Duration duration;

  @override
  bool operator ==(Object other) {
    return other is _NotePlaybackSnapshot &&
        other.isActive == isActive &&
        other.isPlaying == isPlaying &&
        other.progress == progress &&
        other.position == position &&
        other.duration == duration;
  }

  @override
  int get hashCode => Object.hash(
        isActive,
        isPlaying,
        progress,
        position,
        duration,
      );
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
