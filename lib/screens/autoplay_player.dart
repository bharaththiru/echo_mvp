import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../models/voice_note.dart';
import '../services/audio_playback_controller.dart';
import '../services/autoplay_controller.dart';
import '../services/autoplay_ui_sync.dart';
import '../theme/echo_theme.dart';
import '../utils/responsive.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';
import '../widgets/listenable_selector.dart';
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final state = AppScope.of(context);
        if (state.hashtags.isEmpty && !state.hashtagsLoading) {
          state.refreshHashtags();
        }
      });
    }
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
    final audio = appState.audio;
    final autoplay = _autoplay ?? appState.autoplay;
    final reduceMotion = appState.settings.reduceMotion;
    final hashtag = appState.hashtagById(widget.hashtagId);

    if (hashtag == null && appState.hashtagsLoading) {
      return const AppScaffold(
        showMiniPlayer: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (hashtag == null) {
      return AppScaffold(
        showMiniPlayer: false,
        child: Center(
          child: Text('Hashtag not found.', style: theme.textTheme.titleMedium),
        ),
      );
    }

    return AppScaffold(
      showMiniPlayer: false,
      child: ListenableSelector<AutoplayState>(
        listenable: autoplay,
        selector: () => autoplay.state,
        shouldRebuild: _autoplayShouldRebuild,
        builder: (context, state) {
          final noteCountLabel = _noteCountLabel(
            _resolvedStationNoteCount(
              fallback: state.queue.length,
              hashtagCount: hashtag.noteCount,
            ),
          );
          if (state.queue.isEmpty) {
            final resolvedStatus = (state.statusText ?? '').trim();
            final isRecovering =
                state.phase == AutoplayPhase.loading ||
                state.phase == AutoplayPhase.buffering ||
                state.phase == AutoplayPhase.transitioning ||
                state.isPreparing;
            Widget emptyChild = Text(
              resolvedStatus.isNotEmpty ? resolvedStatus : 'No notes yet.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            );
            if (state.isLoadingNotes || isRecovering) {
              emptyChild = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    resolvedStatus.isNotEmpty
                        ? resolvedStatus
                        : 'Loading clips...',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              );
            } else if (state.loadError != null) {
              emptyChild = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Unable to load notes', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    state.loadError!,
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

            final emptyContent = state.isLoadingNotes || isRecovering
                ? emptyChild
                : EchoCard(
                    padding: const EdgeInsets.all(24),
                    radius: 20,
                    color: tokens.surface1,
                    child: emptyChild,
                  );

            return Column(
              children: [
                _PlayerHeader(
                  stationTitle: hashtag.name,
                  noteCountLabel: noteCountLabel,
                  onBack: () => context.pop(),
                ),
                Expanded(child: Center(child: emptyContent)),
              ],
            );
          }
          final resolvedIndex = state.currentIndex.clamp(
            0,
            state.queue.length - 1,
          );
          final index = resolvedIndex.toInt();
          final note = state.currentNote ?? state.queue[index];
          final noteIndex = state.queue.indexWhere((item) => item.id == note.id);
          final currentIndex = noteIndex < 0 ? index : noteIndex;
          final canBlock =
              note.authorId != null &&
              note.authorId!.isNotEmpty &&
              note.authorId != appState.userId;
          final buttonSize = state.handsFree ? 96.0 : 82.0;
          final noteTitle = _resolvedNoteTitle(note);
          final posterLabel = _resolvedPosterLabel(note);

          return StreamBuilder<PlaybackMetrics>(
            stream: audio.playbackMetrics,
            initialData: audio.currentMetrics,
            builder: (context, metricsSnapshot) {
              final metrics = metricsSnapshot.data ?? audio.currentMetrics;
              final ui = resolveAutoplayUiSnapshot(
                state: state,
                metrics: metrics,
                currentNoteId: note.id,
              );
              final isError = state.phase == AutoplayPhase.error;
              final statusLabel = ui.statusLabel;
              final centerShowsSpinner = ui.showSpinner && !ui.isEnginePlaying;

              return Column(
                children: [
                  _PlayerHeader(
                    stationTitle: hashtag.name,
                    noteCountLabel: noteCountLabel,
                    onBack: () => context.pop(),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        // Fixed radial bloom behind the avatar area
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: EchoLayout.space(context, 340),
                          child: Center(
                            child: Container(
                              width: 340,
                              height: 340,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    tokens.accentPrimary.withValues(alpha: 0.07),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        ListView(
                          padding: EchoLayout.listPadding(
                            context,
                            bottom: 12,
                            includeBottomSafeArea: true,
                          ),
                          children: [
                            SizedBox(height: EchoLayout.space(context, 8)),
                            _StationAvatar(
                              icon: hashtag.icon,
                              isPlaying: ui.isEnginePlaying,
                              reduceMotion: reduceMotion,
                            ),
                            SizedBox(height: EchoLayout.space(context, 22)),
                            Text(
                              noteTitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: tokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              posterLabel,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${currentIndex + 1} of ${state.queue.length}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.textTertiary,
                              ),
                            ),
                            SizedBox(height: EchoLayout.space(context, 14)),
                            _AutoplayProgress(
                              audio: audio,
                              currentNoteId: note.id,
                              fallbackDuration: note.duration,
                              label: statusLabel,
                              showSpinner: ui.showSpinner,
                              reduceMotion: reduceMotion,
                              isError: isError,
                            ),
                            if (state.phase == AutoplayPhase.error &&
                                state.errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: EchoCard(
                                  padding: const EdgeInsets.all(14),
                                  radius: 16,
                                  color: tokens.surface2,
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
                                      const SizedBox(height: 10),
                                      EchoSecondaryButton(
                                        label: 'Retry',
                                        onPressed: () => autoplay.restart(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            SizedBox(height: EchoLayout.space(context, 28)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: state.isMuted
                                      ? 'Unmute current note'
                                      : 'Mute current note',
                                  onPressed: () => autoplay.toggleMute(),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: state.isMuted
                                        ? tokens.textPrimary
                                        : tokens.textSecondary,
                                  ),
                                  icon: Icon(
                                    state.isMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                  ),
                                  iconSize: 26,
                                ),
                                const SizedBox(width: 16),
                                // Play/pause button with ambient glow when playing
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: ui.isEnginePlaying
                                        ? [
                                            BoxShadow(
                                              color: tokens.accentPrimary
                                                  .withValues(alpha: 0.32),
                                              blurRadius: 38,
                                              spreadRadius: 2,
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: SizedBox(
                                    height: buttonSize,
                                    width: buttonSize,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        shape: const CircleBorder(),
                                        padding: EdgeInsets.zero,
                                        backgroundColor: tokens.accentPrimary,
                                        foregroundColor: theme.colorScheme.onPrimary,
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                      ),
                                      onPressed: () => autoplay.togglePlayPause(),
                                      child: centerShowsSpinner
                                          ? SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<Color>(
                                                      theme.colorScheme.onPrimary,
                                                    ),
                                              ),
                                            )
                                          : Icon(
                                              ui.isEnginePlaying
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                              size: 38,
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                IconButton(
                                  tooltip: 'Next note',
                                  onPressed: state.queue.length <= 1
                                      ? null
                                      : () => autoplay.skip(),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: state.queue.length <= 1
                                        ? tokens.textTertiary
                                        : tokens.textSecondary,
                                  ),
                                  icon: const Icon(Icons.skip_next_rounded),
                                  iconSize: 30,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: PopupMenuButton<String>(
                                color: tokens.surface1,
                                onSelected: (action) => _handleMenuAction(note, action),
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
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.more_horiz_rounded,
                                    size: 22,
                                    color: tokens.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({
    required this.stationTitle,
    required this.noteCountLabel,
    required this.onBack,
  });

  final String stationTitle;
  final String noteCountLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return EchoHeaderShell(
      padding: EchoLayout.pagePadding(context, top: 4, bottom: 4),
      child: SizedBox(
        height: 52,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: tokens.textPrimary,
                ),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stationTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      noteCountLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationAvatar extends StatefulWidget {
  const _StationAvatar({
    required this.icon,
    required this.isPlaying,
    required this.reduceMotion,
  });

  final IconData icon;
  final bool isPlaying;
  final bool reduceMotion;

  @override
  State<_StationAvatar> createState() => _StationAvatarState();
}

class _StationAvatarState extends State<_StationAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.isPlaying && !widget.reduceMotion) {
      _ring.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _StationAvatar old) {
    super.didUpdateWidget(old);
    final shouldAnimate = widget.isPlaying && !widget.reduceMotion;
    if (shouldAnimate && !_ring.isAnimating) {
      _ring.repeat();
    } else if (!shouldAnimate && _ring.isAnimating) {
      _ring.stop();
      _ring.reset();
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  Widget _buildRing(double size, double value, double offset, EchoSemantic tokens) {
    final t = (value + offset) % 1.0;
    final scale = 1.0 + t * 0.32;
    final opacity = (1.0 - t) * 0.20;
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.accentPrimary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.echo;
    final size = EchoLayout.space(context, 228).clamp(184.0, 254.0).toDouble();
    final haloColor = tokens.accentPrimary.withValues(alpha: 0.20);

    final disc = Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(tokens.accentPrimary, tokens.surface1, 0.45)!,
            tokens.surface2,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.shadowMedium,
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Center(
        child: Container(
          height: size * 0.42,
          width: size * 0.42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: haloColor,
          ),
          child: Icon(
            widget.icon,
            size: size * 0.22,
            color: tokens.textPrimary,
          ),
        ),
      ),
    );

    return Center(
      child: SizedBox(
        width: size * 1.5,
        height: size * 1.5,
        child: AnimatedBuilder(
          animation: _ring,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                if (widget.isPlaying && !widget.reduceMotion)
                  _buildRing(size, _ring.value, 0.0, tokens),
                if (widget.isPlaying && !widget.reduceMotion)
                  _buildRing(size, _ring.value, 0.5, tokens),
                child!,
              ],
            );
          },
          child: disc,
        ),
      ),
    );
  }
}

class _NowListeningBar extends StatelessWidget {
  const _NowListeningBar({
    required this.label,
    required this.showSpinner,
    required this.progress,
    required this.bufferedProgress,
    required this.reduceMotion,
    required this.isError,
  });

  final String label;
  final bool showSpinner;
  final double progress;
  final double bufferedProgress;
  final bool reduceMotion;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final clamped = progress.clamp(0.0, 1.0);
    final rawBuffered = bufferedProgress.clamp(0.0, 1.0);
    final bufferedClamped = rawBuffered < clamped ? clamped : rawBuffered;
    final showStatus =
        showSpinner || isError || (label != 'Now listening' && label != 'Ready');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStatus)
          Row(
            children: [
              if (showSpinner)
                SizedBox(
                  height: 12,
                  width: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      tokens.accentPrimary,
                    ),
                  ),
                ),
              if (showSpinner) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isError ? tokens.danger : tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        if (showStatus) const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const dotSize = 12.0;
            final trackWidth = constraints.maxWidth;
            final left = (trackWidth - dotSize) * clamped;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: tokens.textSecondary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: bufferedClamped,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: tokens.textSecondary.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(6),
                    ),
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
                    color: tokens.accentPrimary,
                    reduceMotion: reduceMotion,
                  ),
                ),
              ],
            );
          },
        ),
      ],
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
      height: 12,
      width: 12,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
      ),
    );
    if (widget.reduceMotion) {
      return base;
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final scale = lerpDouble(0.84, 1.12, _animation.value)!;
        final opacity = lerpDouble(0.65, 1.0, _animation.value)!;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: base),
        );
      },
    );
  }
}

bool _autoplayShouldRebuild(AutoplayState previous, AutoplayState next) {
  if (previous.currentNote?.id != next.currentNote?.id) {
    return true;
  }
  if (previous.currentIndex != next.currentIndex) {
    return true;
  }
  if (previous.queue.length != next.queue.length) {
    return true;
  }
  if (previous.phase != next.phase) {
    return true;
  }
  if (previous.isPreparing != next.isPreparing ||
      previous.isTransitioning != next.isTransitioning) {
    return true;
  }
  if (previous.isLoadingNotes != next.isLoadingNotes) {
    return true;
  }
  if (previous.loadError != next.loadError) {
    return true;
  }
  if (previous.errorMessage != next.errorMessage) {
    return true;
  }
  if (previous.statusText != next.statusText) {
    return true;
  }
  if (previous.transientMessage != next.transientMessage) {
    return true;
  }
  if (previous.handsFree != next.handsFree) {
    return true;
  }
  if (previous.userPaused != next.userPaused) {
    return true;
  }
  if (previous.isMuted != next.isMuted) {
    return true;
  }
  return false;
}

// Drives the progress bar at the display refresh rate (60/120 Hz) by
// extrapolating the last known playback position forward using wall-clock
// elapsed time.  A vsync Ticker replaces the previous StreamBuilder-only
// approach, which was capped at ~10 FPS by the engine's 100 ms throttle.
class _AutoplayProgress extends StatefulWidget {
  const _AutoplayProgress({
    required this.audio,
    required this.currentNoteId,
    required this.fallbackDuration,
    required this.label,
    required this.showSpinner,
    required this.reduceMotion,
    required this.isError,
  });

  final AudioPlaybackController audio;
  final String currentNoteId;
  final Duration fallbackDuration;
  final String label;
  final bool showSpinner;
  final bool reduceMotion;
  final bool isError;

  @override
  State<_AutoplayProgress> createState() => _AutoplayProgressState();
}

class _AutoplayProgressState extends State<_AutoplayProgress>
    with SingleTickerProviderStateMixin {
  late PlaybackMetrics _metrics;

  // Wall-clock timestamp of the last metrics arrival used as the
  // interpolation baseline, preventing drift relative to the engine.
  late DateTime _metricsAt;

  late Ticker _ticker;
  StreamSubscription<PlaybackMetrics>? _metricsSub;

  @override
  void initState() {
    super.initState();
    _metrics = widget.audio.currentMetrics;
    _metricsAt = DateTime.now();
    _metricsSub = widget.audio.playbackMetrics.listen(_onMetrics);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant _AutoplayProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audio != widget.audio) {
      _metricsSub?.cancel();
      _metrics = widget.audio.currentMetrics;
      _metricsAt = DateTime.now();
      _metricsSub = widget.audio.playbackMetrics.listen(_onMetrics);
    }
  }

  @override
  void dispose() {
    _metricsSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onMetrics(PlaybackMetrics metrics) {
    // Anchor the extrapolation baseline to the moment the engine reports.
    _metrics = metrics;
    _metricsAt = DateTime.now();
    // The Ticker calls setState every frame while playing, so we only need
    // an explicit rebuild here for non-playing state changes (pause, error…).
    if (mounted && !metrics.playing) {
      setState(() {});
    }
  }

  // Called every vsync frame (~16 ms at 60 Hz).
  void _onTick(Duration _) {
    if (mounted && _metrics.playing) {
      setState(() {});
    }
  }

  // Linear extrapolation: lastKnownPosition + wallClockElapsed, clamped to
  // duration.  Falls back to the raw engine position when paused or stalled
  // (buffering) since no forward progress is expected.
  Duration get _interpolatedPosition {
    if (!_metrics.playing || !_metrics.isPositionAdvancing) {
      return _metrics.position;
    }
    final elapsed = DateTime.now().difference(_metricsAt);
    final extrapolated = _metrics.position + elapsed;
    final dur = _metrics.duration;
    if (dur.inMilliseconds > 0) {
      return Duration(
        milliseconds: min(extrapolated.inMilliseconds, dur.inMilliseconds),
      );
    }
    return extrapolated;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;

    // Only treat metrics as valid for this note when sourceId matches.
    // The previous `|| metrics.playing` guard could show stale position
    // data from the previous track for one frame during a transition,
    // causing the progress bar to jump backwards then forward.
    final useLiveMetrics = _metrics.sourceId == widget.currentNoteId;
    final duration = useLiveMetrics && _metrics.duration.inMilliseconds > 0
        ? _metrics.duration
        : widget.fallbackDuration;
    final position = useLiveMetrics
        ? _interpolatedPosition
        : Duration.zero;
    final buffered = useLiveMetrics
        ? _metrics.bufferedPosition
        : Duration.zero;
    final ratio = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();
    final bufferedRatio = duration.inMilliseconds == 0
        ? 0.0
        : (buffered.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();
    return Column(
      children: [
        _NowListeningBar(
          label: widget.label,
          showSpinner: widget.showSpinner,
          progress: ratio,
          bufferedProgress: bufferedRatio,
          reduceMotion: widget.reduceMotion,
          isError: widget.isError,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatDuration(position),
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
    );
  }
}

int _resolvedStationNoteCount({
  required int fallback,
  required int hashtagCount,
}) {
  return hashtagCount > 0 ? hashtagCount : fallback;
}

String _noteCountLabel(int count) {
  return '$count ${count == 1 ? 'note' : 'notes'}';
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
