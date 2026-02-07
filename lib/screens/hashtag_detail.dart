import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../models/hashtag.dart';
import '../models/voice_note.dart';
import '../services/audio_controller.dart';
import '../services/autoplay_controller.dart';
import '../theme/echo_theme.dart';
import '../utils/responsive.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';
import '../widgets/listenable_selector.dart';

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

  @override
  void didUpdateWidget(covariant HashtagDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hashtagId == widget.hashtagId) {
      return;
    }
    final appState = AppScope.of(context);
    appState.loadNotesForHashtag(widget.hashtagId);
  }

  void _openStation(Hashtag hashtag) {
    final appState = AppScope.of(context);
    appState.markStationListened(hashtag.id);
    context.go('/hashtag/${hashtag.id}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = AppScope.of(context);
    final tokens = context.echo;
    final hashtag = appState.hashtagById(widget.hashtagId);
    if (hashtag == null && appState.hashtagsLoading) {
      return const AppScaffold(child: Center(child: CircularProgressIndicator()));
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
    final stationOrder = appState.hashtags;
    final stationIndex = stationOrder.indexWhere((item) => item.id == hashtag.id);
    final previousStation =
        stationIndex > 0 ? stationOrder[stationIndex - 1] : null;
    final nextStation = stationIndex >= 0 && stationIndex < stationOrder.length - 1
        ? stationOrder[stationIndex + 1]
        : null;
    final autoplay = appState.autoplay;
    final audio = appState.audio;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final fabRightOffset =
        EchoLayout.contentHorizontalPadding(context) + EchoLayout.space(context, 4);

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
          final fabBottomOffset = safeBottom +
              EchoLayout.space(context, miniPlayerVisible ? 126 : 26);
          final listBottomPadding = miniPlayerVisible ? 196.0 : 124.0;

          Widget content;
          if (isLoading && notes.isEmpty) {
            content = const Center(child: CircularProgressIndicator());
          } else if (loadError != null && notes.isEmpty) {
            content = _EmptyState(
              title: 'Unable to load notes',
              subtitle: loadError,
              onRetry: () => appState.loadNotesForHashtag(hashtag.id, force: true),
            );
          } else if (notes.isEmpty) {
            content = _EmptyState(
              title: 'No notes yet',
              subtitle: 'Be the first to post in ${hashtag.name}.',
              onRetry: () => appState.loadNotesForHashtag(hashtag.id, force: true),
            );
          } else {
            content = ListView.builder(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EchoLayout.listPadding(
                context,
                top: 6,
                bottom: listBottomPadding,
                includeBottomSafeArea: true,
              ),
              itemCount: notes.length * 2 + 3,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _StationHeroPanel(
                    station: hashtag,
                    noteCount: notes.length,
                    previousLabel: previousStation?.name,
                    nextLabel: nextStation?.name,
                    onPrevious: previousStation == null
                        ? null
                        : () => _openStation(previousStation!),
                    onNext:
                        nextStation == null ? null : () => _openStation(nextStation!),
                  );
                }
                if (index == 1) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
                    child: Text(
                      'Notes',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }
                if (index == 2) {
                  return const SizedBox(height: 2);
                }
                final rowIndex = index - 3;
                if (rowIndex.isOdd) {
                  return const SizedBox(height: 10);
                }
                final note = notes[rowIndex ~/ 2];
                final isPreparing = _loadingNoteId == note.id;
                return _VoiceNoteRow(
                  note: note,
                  isPreparing: isPreparing,
                  audio: audio,
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
                );
              },
            );
          }

          return Stack(
            children: [
              Column(
                children: [
                  _StationTopBar(
                    title: hashtag.name,
                    onBack: () => context.go('/listen'),
                  ),
                  Expanded(child: content),
                ],
              ),
              Positioned(
                right: fabRightOffset,
                bottom: fabBottomOffset,
                child: _AutoplayFloatingButton(
                  onTap: () {
                    context.push('/player/${hashtag.id}');
                  },
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

class _StationTopBar extends StatelessWidget {
  const _StationTopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return EchoHeaderShell(
      padding: EchoLayout.pagePadding(
        context,
        top: 8,
        bottom: 6,
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
            style: TextButton.styleFrom(
              backgroundColor: tokens.surface1,
              foregroundColor: tokens.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationHeroPanel extends StatelessWidget {
  const _StationHeroPanel({
    required this.station,
    required this.noteCount,
    required this.previousLabel,
    required this.nextLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final Hashtag station;
  final int noteCount;
  final String? previousLabel;
  final String? nextLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final circleSize =
        EchoLayout.space(context, 178).clamp(146.0, 214.0).toDouble();

    return EchoCard(
      radius: 30,
      color: tokens.surface1,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      child: Column(
        children: [
          Text(
            station.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$noteCount ${noteCount == 1 ? 'note' : 'notes'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StationNavButton(
                icon: Icons.chevron_left_rounded,
                label: previousLabel ?? 'Previous',
                onPressed: onPrevious,
              ),
              const Spacer(),
              Container(
                height: circleSize,
                width: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(station.color, tokens.surface2, 0.18)!,
                      Color.lerp(tokens.surface1, station.color, 0.34)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  station.icon,
                  size: circleSize * 0.38,
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              _StationNavButton(
                icon: Icons.chevron_right_rounded,
                label: nextLabel ?? 'Next',
                onPressed: onNext,
              ),
            ],
          ),
          if (station.description.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              station.description,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StationNavButton extends StatelessWidget {
  const _StationNavButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final isEnabled = onPressed != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: label,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: tokens.surface2.withValues(alpha: isEnabled ? 1 : 0.6),
            foregroundColor: isEnabled ? tokens.textPrimary : tokens.textTertiary,
          ),
          iconSize: 28,
          icon: Icon(icon),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 76,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isEnabled ? tokens.textSecondary : tokens.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _VoiceNoteRow extends StatelessWidget {
  const _VoiceNoteRow({
    required this.note,
    required this.isPreparing,
    required this.audio,
    required this.onPlay,
  });

  final VoiceNote note;
  final bool isPreparing;
  final AudioController audio;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final buttonFill = tokens.accentPrimary;
    final onButtonFill = theme.colorScheme.onPrimary;
    final loadingForeground = onButtonFill.withValues(alpha: 0.5);

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
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          radius: 18,
          color: tokens.surface1,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _resolvedNoteTitle(note),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _resolvedPosterLabel(note),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          formatRelativeTime(note.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatDuration(playback.duration),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    if (playback.isActive) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: playback.progress.clamp(0.0, 1.0).toDouble(),
                          minHeight: 4,
                          backgroundColor: tokens.textSecondary.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation(tokens.accentPrimary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: playback.isPlaying ? 'Pause note' : 'Play note',
                onPressed: onPlay,
                style: IconButton.styleFrom(
                  backgroundColor: buttonFill,
                  foregroundColor: onButtonFill,
                ),
                icon: isPreparing
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            loadingForeground,
                          ),
                        ),
                      )
                    : Icon(
                        playback.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 22,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AutoplayFloatingButton extends StatelessWidget {
  const _AutoplayFloatingButton({required this.onTap, required this.heroTag});

  final VoidCallback onTap;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final onButtonFill = theme.colorScheme.onPrimary;
    return Semantics(
      button: true,
      label: 'Start autoplay',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: 72,
          child: FloatingActionButton(
            heroTag: heroTag,
            tooltip: 'Autoplay',
            onPressed: onTap,
            backgroundColor: tokens.accentPrimary,
            foregroundColor: onButtonFill,
            elevation: 0,
            highlightElevation: 0,
            shape: const CircleBorder(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome_rounded, color: onButtonFill, size: 20),
                const SizedBox(height: 1),
                Text(
                  'AUTO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: onButtonFill,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
  int get hashCode =>
      Object.hash(isActive, isPlaying, progress, position, duration);
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

String _resolvedNoteTitle(VoiceNote note) {
  final title = note.transcriptPreview?.trim();
  if (title == null || title.isEmpty) {
    return 'Untitled';
  }
  return title;
}

String _resolvedPosterLabel(VoiceNote note) {
  final username = note.authorId?.trim();
  if (username == null || username.isEmpty) {
    return 'Anonymous';
  }
  return username;
}
