import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
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
    final tokens = context.echo;
    final appState = AppScope.of(context);
    final autoplay = _autoplay ?? appState.autoplay;
    final moodTint = appState.settings.moodTintEnabled;
    final reduceMotion = appState.settings.reduceMotion;
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
                color: tokens.textSecondary,
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
              ? Color.lerp(tokens.surface1, tint, 0.62) ?? tokens.surface1
              : tokens.surface1;
          final cardBorder = moodTint
              ? tint.withValues(alpha: 0.62)
              : tokens.borderSubtle;

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
          final statusLabel = _statusLabel(state) ?? 'Ready';
          final showSpinner =
              state.isBuffering ||
              state.isPreparing ||
              state.phase == AutoplayPhase.transitioning;
          final isError = state.phase == AutoplayPhase.error;
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
                                color: tokens.accentPrimary,
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tokens.surface2,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: tokens.borderSubtle,
                                      ),
                                    ),
                                    child: Text(
                                      '${currentIndex + 1} of ${state.queue.length}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: tokens.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  PopupMenuButton<String>(
                                    color: tokens.surface1,
                                    icon: Icon(
                                      Icons.more_horiz,
                                      color: tokens.textSecondary,
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
                                color: tokens.textSecondary.withValues(
                                  alpha: 0.92,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'Anonymous - ${formatRelativeTime(note.createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _NowListeningBar(
                            label: statusLabel,
                            showSpinner: showSpinner,
                            progress: (progress.isNaN ? 0.0 : progress)
                                .clamp(0.0, 1.0)
                                .toDouble(),
                            reduceMotion: reduceMotion,
                            isError: isError,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                formatDuration(state.position),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                              Text(
                                formatDuration(duration),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
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
                          color: tokens.surface2,
                          borderColor: tokens.borderSubtle,
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
                                  color: tokens.textSecondary,
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
                                ? SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        tokens.bg,
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
                      color: tokens.surface2,
                      borderColor: tokens.borderSubtle,
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
                                    color: tokens.textSecondary,
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
                        color: tokens.textSecondary,
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
                                  color: tokens.surface2,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: tokens.borderSubtle,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '${absoluteIndex + 1}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: tokens.accentPrimary,
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
                                            color: tokens.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                formatDuration(nextNote.duration),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
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
                      color: tokens.surface2,
                      borderColor: tokens.border,
                      child: Text(
                        'Message slot (disabled in MVP)',
                        textAlign: TextAlign.center,
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

class _NowListeningBar extends StatelessWidget {
  const _NowListeningBar({
    required this.label,
    required this.showSpinner,
    required this.progress,
    required this.reduceMotion,
    required this.isError,
  });

  final String label;
  final bool showSpinner;
  final double progress;
  final bool reduceMotion;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final clamped = progress.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: tokens.surface1.withValues(alpha: 0.9),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (showSpinner)
                    SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          tokens.accentSecondary,
                        ),
                      ),
                    ),
                  if (showSpinner) const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isError ? tokens.danger : tokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  const dotSize = 8.0;
                  final trackWidth = constraints.maxWidth;
                  final left = (trackWidth - dotSize) * clamped;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: tokens.surface3,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: clamped,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: tokens.accentPrimary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      Positioned(
                        left: left,
                        child: _PulseDot(
                          color: tokens.accentSecondary,
                          reduceMotion: reduceMotion,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.reduceMotion});

  final Color color;
  final bool reduceMotion;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    if (!widget.reduceMotion) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Container(
      height: 8,
      width: 8,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.55),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
    if (widget.reduceMotion) {
      return base;
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final scale = lerpDouble(0.85, 1.1, _animation.value)!;
        final opacity = lerpDouble(0.6, 1.0, _animation.value)!;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: base),
        );
      },
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
