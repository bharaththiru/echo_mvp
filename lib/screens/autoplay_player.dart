import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../models/voice_note.dart';
import '../services/audio_playback_controller.dart';
import '../services/autoplay_controller.dart';
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
              final metricsMatchesCurrent = metrics.sourceId == note.id;
              final isEnginePlaying = metricsMatchesCurrent
                  ? metrics.playing
                  : (state.isPlaying && state.currentNote?.id == note.id);
              final isEngineBuffering = metricsMatchesCurrent &&
                  (metrics.processingState == PlaybackProcessingState.loading ||
                      metrics.processingState ==
                          PlaybackProcessingState.buffering);
              final hasPlaybackStarted = metricsMatchesCurrent
                  ? (metrics.position > Duration.zero || metrics.playing)
                  : (state.position > Duration.zero || state.isPlaying);
              final isUiLoading =
                  !isEnginePlaying &&
                  ((metricsMatchesCurrent &&
                          metrics.processingState ==
                              PlaybackProcessingState.loading) ||
                      ((state.phase == AutoplayPhase.loading ||
                              state.isPreparing) &&
                          !hasPlaybackStarted));
              final showSpinner = isUiLoading || (isEngineBuffering && !isEnginePlaying);
              final isError = state.phase == AutoplayPhase.error;
              final statusLabel =
                  _statusLabel(
                    state,
                    metrics: metrics,
                    currentNoteId: note.id,
                  ) ??
                  'Ready';
              final centerShowsSpinner = showSpinner && !isEnginePlaying;

              return Column(
                children: [
                  _PlayerHeader(
                    stationTitle: hashtag.name,
                    noteCountLabel: noteCountLabel,
                    onBack: () => context.pop(),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EchoLayout.listPadding(
                        context,
                        bottom: 12,
                        includeBottomSafeArea: true,
                      ),
                      children: [
                        SizedBox(height: EchoLayout.space(context, 8)),
                        _StationAvatar(icon: hashtag.icon),
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
                          showSpinner: showSpinner,
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
                                foregroundColor: tokens.textPrimary,
                              ),
                              icon: Icon(
                                state.isMuted ? Icons.volume_off : Icons.volume_up,
                              ),
                              iconSize: 28,
                            ),
                            const SizedBox(width: 14),
                            SizedBox(
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
                                        isEnginePlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        size: 36,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            IconButton(
                              tooltip: 'Next note',
                              onPressed: state.queue.length <= 1
                                  ? null
                                  : () => autoplay.skip(),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: tokens.textPrimary,
                              ),
                              icon: const Icon(Icons.skip_next),
                              iconSize: 30,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                'Clip actions',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
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
      padding: EchoLayout.pagePadding(context, top: 8, bottom: 8),
      child: Container(
        height: EchoLayout.space(context, 94).clamp(84.0, 108.0).toDouble(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface1,
          borderRadius: BorderRadius.circular(30),
        ),
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
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 44),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stationTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      noteCountLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
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

class _StationAvatar extends StatelessWidget {
  const _StationAvatar({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.echo;
    final size = EchoLayout.space(context, 228).clamp(184.0, 254.0).toDouble();
    final haloColor = tokens.accentPrimary.withValues(alpha: 0.2);

    return Center(
      child: Container(
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
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 22,
              offset: const Offset(0, 10),
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
              icon,
              size: size * 0.22,
              color: tokens.textPrimary,
            ),
          ),
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
            const dotSize = 10.0;
            final trackWidth = constraints.maxWidth;
            final left = (trackWidth - dotSize) * clamped;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.textSecondary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: bufferedClamped,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.textSecondary.withValues(alpha: 0.36),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: clamped,
                  child: Container(
                    height: 4,
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
      height: 10,
      width: 10,
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
    // data from the previous track for one frame during a transition.
    final useLiveMetrics = _metrics.sourceId == widget.currentNoteId;
    final duration = useLiveMetrics && _metrics.duration.inMilliseconds > 0
        ? _metrics.duration
        : widget.fallbackDuration;
    final position = useLiveMetrics ? _interpolatedPosition : Duration.zero;
    final buffered =
        useLiveMetrics ? _metrics.bufferedPosition : Duration.zero;
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

String? _statusLabel(
  AutoplayState state, {
  required PlaybackMetrics metrics,
  required String currentNoteId,
}) {
  if (state.transientMessage != null && state.transientMessage!.isNotEmpty) {
    return state.transientMessage;
  }
  if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
    return state.errorMessage;
  }
  final metricsMatchCurrent = metrics.sourceId == currentNoteId;
  final isEngineBuffering =
      metricsMatchCurrent &&
      (metrics.processingState == PlaybackProcessingState.loading ||
          metrics.processingState == PlaybackProcessingState.buffering);
  if (isEngineBuffering && !metrics.playing) {
    return 'Buffering...';
  }
  if (isEngineBuffering && metrics.playing && !metrics.isPositionAdvancing) {
    return 'Buffering...';
  }
  final hasStarted = metricsMatchCurrent
      ? (metrics.position > Duration.zero || metrics.playing)
      : (state.position > Duration.zero || state.isPlaying);
  if ((state.phase == AutoplayPhase.loading || state.isPreparing) &&
      !hasStarted) {
    return 'Loading clip...';
  }
  if (state.phase == AutoplayPhase.transitioning) {
    return 'Moving to next clip...';
  }
  if (metricsMatchCurrent ? metrics.playing : state.isPlaying) {
    return 'Now listening';
  }
  if (state.phase == AutoplayPhase.paused) {
    return 'Paused';
  }
  if (state.phase == AutoplayPhase.completed && state.statusText != null) {
    return state.statusText;
  }
  return state.statusText;
}
