import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../models/voice_note.dart';
import '../services/autoplay_controller.dart';
import '../utils/time_format.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';
import '../widgets/report_reason_sheet.dart';

class AutoplayPlayer extends StatefulWidget {
  const AutoplayPlayer({super.key, required this.hashtagId});

  final String hashtagId;

  @override
  State<AutoplayPlayer> createState() => _AutoplayPlayerState();
}

class _AutoplayPlayerState extends State<AutoplayPlayer> {
  AutoplayController? _autoplay;
  String? _attachedHashtagId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = AppScope.of(context);
    _autoplay ??= appState.autoplay;
    if (_attachedHashtagId != widget.hashtagId) {
      final targetId = widget.hashtagId;
      _attachedHashtagId = targetId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _attachedHashtagId != targetId) {
          return;
        }
        _autoplay?.attach(targetId);
      });
    }
    if (appState.hashtags.isEmpty && !appState.hashtagsLoading) {
      appState.refreshHashtags();
    }
  }

  @override
  void dispose() {
    _autoplay?.detach(stopPlayback: true, hashtagId: widget.hashtagId);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AutoplayPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hashtagId == widget.hashtagId) {
      return;
    }
    final targetId = widget.hashtagId;
    _attachedHashtagId = targetId;
    _autoplay ??= AppScope.of(context).autoplay;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _attachedHashtagId != targetId) {
        return;
      }
      _autoplay?.attach(targetId);
    });
  }

  Future<void> _handleMenuAction(VoiceNote note, String action) async {
    final appState = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    switch (action) {
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
    final appState = AppScope.of(context);
    final autoplay = _autoplay ?? appState.autoplay;
    final moodTint = appState.settings.moodTintEnabled;
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

    final autoplayState = autoplay.state;
    final notes = autoplayState.queue;
    final isLoading = autoplayState.isLoadingNotes;
    final loadError = autoplayState.loadError;

    if (notes.isEmpty) {
      Widget emptyChild = Text(
        'No notes yet.',
        style: theme.textTheme.titleMedium,
        textAlign: TextAlign.center,
      );
      if (isLoading) {
        emptyChild = const CircularProgressIndicator();
      } else if (loadError != null) {
        emptyChild = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Unable to load notes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              loadError,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: EchoColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () =>
                  autoplay.attach(widget.hashtagId, forceRefresh: true),
              child: const Text('Retry'),
            ),
          ],
        );
      }
      final emptyContent = isLoading
          ? emptyChild
          : EchoCard(padding: const EdgeInsets.all(24), child: emptyChild);

      return AppScaffold(
        child: Column(
          children: [
            Padding(
              padding: EchoLayout.pagePadding(
                context,
                top: 24,
                bottom: 16,
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: Text('Back to ${hashtag.name}'),
                  ),
                ],
              ),
            ),
            Expanded(child: Center(child: emptyContent)),
          ],
        ),
      );
    }

    return AppScaffold(
      child: AnimatedBuilder(
        animation: autoplay,
        builder: (context, _) {
          final state = autoplay.state;
          if (state.queue.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final resolvedIndex = state.currentIndex.clamp(
            0,
            state.queue.length - 1,
          );
          final index = resolvedIndex.toInt();
          final note = state.currentNote ?? state.queue[index];
          final noteIndex = state.queue.indexWhere(
            (item) => item.id == note.id,
          );
          final currentIndex = noteIndex < 0 ? index : noteIndex;
          final tint = hashtag.gradient.first;
          final cardColor = moodTint
              ? Color.lerp(EchoColors.surface, tint, 0.62) ?? EchoColors.surface
              : EchoColors.surface;
          final cardBorder = moodTint
              ? tint.withValues(alpha: 0.62)
              : EchoColors.borderSubtle;

          final duration = state.duration.inMilliseconds > 0
              ? state.duration
              : note.duration;
          final progress = duration.inMilliseconds == 0
              ? 0.0
              : (state.position.inMilliseconds / duration.inMilliseconds).clamp(
                  0,
                  1,
                );
          final isPreparing = state.isPreparing || state.isTransitioning;
          final statusLabel = _statusLabel(state);
          final showStatus = statusLabel != null && statusLabel.isNotEmpty;
          final showSpinner =
              state.isBuffering ||
              state.isPreparing ||
              state.phase == AutoplayPhase.transitioning;
          final upcoming = state.upcoming(take: 3);
          final canBlock =
              note.authorId != null &&
              note.authorId!.isNotEmpty &&
              note.authorId != appState.userId;

          return Column(
            children: [
              Padding(
                padding: EchoLayout.pagePadding(
                  context,
                  top: 24,
                  bottom: 16,
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: Text('Back to ${hashtag.name}'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EchoLayout.listPadding(context),
                  children: [
                    EchoCard(
                      padding: const EdgeInsets.all(24),
                      radius: 28,
                      color: cardColor,
                      borderColor: cardBorder,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(
                                hashtag.icon,
                                size: 44,
                                color: EchoColors.accent,
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: EchoColors.muted,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: EchoColors.borderSubtle,
                                      ),
                                    ),
                                    child: Text(
                                      '${currentIndex + 1} of ${state.queue.length}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: EchoColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  PopupMenuButton<String>(
                                    color: EchoColors.surface,
                                    icon: const Icon(
                                      Icons.more_horiz,
                                      color: EchoColors.textSecondary,
                                    ),
                                    onSelected: (action) =>
                                        _handleMenuAction(note, action),
                                    itemBuilder: (context) => [
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
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hashtag.name,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          if (appState.settings.transcriptsEnabled &&
                              note.transcriptPreview != null)
                            Text(
                              '"${note.transcriptPreview!}"',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: EchoColors.textSecondary.withValues(
                                  alpha: 0.92,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'Anonymous - ${formatRelativeTime(note.createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: EchoColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 20),
                            child: showStatus
                                ? Row(
                                    children: [
                                      if (showSpinner)
                                        const SizedBox(
                                          height: 14,
                                          width: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      if (showSpinner) const SizedBox(width: 8),
                                      Text(
                                        statusLabel,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  state.phase ==
                                                      AutoplayPhase.error
                                                  ? EchoColors.action
                                                  : EchoColors.textSecondary,
                                            ),
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: LinearProgressIndicator(
                              value: (progress.isNaN ? 0.0 : progress)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                              minHeight: 8,
                              backgroundColor: EchoColors.muted,
                              valueColor: const AlwaysStoppedAnimation(
                                EchoColors.accent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                formatDuration(state.position),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: EchoColors.textSecondary,
                                ),
                              ),
                              Text(
                                formatDuration(duration),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: EchoColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (state.phase == AutoplayPhase.error &&
                        state.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: EchoCard(
                          padding: const EdgeInsets.all(16),
                          radius: 18,
                          color: EchoColors.muted,
                          borderColor: EchoColors.borderSubtle,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Playback issue',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                state.errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: EchoColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              EchoSecondaryButton(
                                label: 'Retry',
                                onPressed: () => autoplay.restart(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: currentIndex == 0
                              ? null
                              : () => autoplay.playPrevious(),
                          icon: const Icon(Icons.skip_previous),
                          iconSize: 28,
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: state.handsFree ? 96 : 80,
                          width: state.handsFree ? 96 : 80,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: isPreparing
                                ? null
                                : () => autoplay.togglePlayPause(),
                            child: isPreparing
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        EchoColors.background,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    state.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    size: 36,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: state.queue.length <= 1
                              ? null
                              : () => autoplay.skip(),
                          icon: const Icon(Icons.skip_next),
                          iconSize: 28,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => autoplay.toggleMute(),
                          icon: Icon(
                            state.isMuted
                                ? Icons.volume_off
                                : Icons.volume_up,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Slider(
                            value: state.volume,
                            onChanged: (value) => autoplay.setVolume(value),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${(state.volume * 100).round()}%',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    EchoCard(
                      padding: const EdgeInsets.all(16),
                      radius: 18,
                      color: EchoColors.muted,
                      borderColor: EchoColors.borderSubtle,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hands-free mode',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Bigger controls, easier tapping',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: EchoColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: state.handsFree,
                            onChanged: (value) => autoplay.setHandsFree(value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Up next',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: EchoColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...upcoming.asMap().entries.map((entry) {
                      final indexOffset = entry.key + 1;
                      final absoluteIndex = currentIndex + indexOffset;
                      final nextNote = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: EchoCard(
                          onTap: () => autoplay.playFromUpNext(absoluteIndex),
                          radius: 16,
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                height: 38,
                                width: 38,
                                decoration: BoxDecoration(
                                  color: EchoColors.muted,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: EchoColors.borderSubtle,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '${absoluteIndex + 1}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: EchoColors.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nextNote.transcriptPreview ??
                                          'Voice note',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    Text(
                                      formatRelativeTime(nextNote.createdAt),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: EchoColors.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                formatDuration(nextNote.duration),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: EchoColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    EchoCard(
                      padding: const EdgeInsets.all(16),
                      radius: 16,
                      color: EchoColors.muted,
                      borderColor: EchoColors.border,
                      child: Text(
                        'Message slot (disabled in MVP)',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: EchoColors.textSecondary,
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

String? _statusLabel(AutoplayState state) {
  if (state.transientMessage != null && state.transientMessage!.isNotEmpty) {
    return state.transientMessage;
  }
  if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
    return state.errorMessage;
  }
  if (state.isPreparing) {
    return 'Loading clip...';
  }
  if (state.phase == AutoplayPhase.transitioning) {
    return 'Moving to next clip...';
  }
  if (state.isBuffering) {
    return state.statusText ?? 'Buffering...';
  }
  if (state.isPlaying) {
    return 'Now listening';
  }
  return state.statusText;
}
