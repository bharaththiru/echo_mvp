import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../services/audio_playback_controller.dart';
import '../services/autoplay_controller.dart';
import '../services/autoplay_ui_sync.dart';
import '../theme/echo_theme.dart';
import '../utils/responsive.dart';
import 'listenable_selector.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.bottomNavigationBar,
    this.showMiniPlayer = false,
  });

  final Widget child;
  final Widget? bottomNavigationBar;
  final bool showMiniPlayer;

  @override
  Widget build(BuildContext context) {
    final tokens = context.echo;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: tokens.bg,
        resizeToAvoidBottomInset: true,
        bottomNavigationBar: bottomNavigationBar,
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: EchoGradients.appBackground,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 420,
                    height: 300,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          tokens.accentSecondary.withValues(alpha: 0.09),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: double.infinity, child: child),
            if (showMiniPlayer) const _MiniPlayer(),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer();

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> {
  static const _collapseDelay = Duration(seconds: 30);

  Timer? _collapseTimer;
  bool _isCollapsed = false;

  @override
  void initState() {
    super.initState();
    _resetCollapseTimer();
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  void _resetCollapseTimer() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_collapseDelay, () {
      if (!mounted || _isCollapsed) {
        return;
      }
      setState(() {
        _isCollapsed = true;
      });
    });
  }

  void _registerInteraction() {
    if (_isCollapsed) {
      setState(() {
        _isCollapsed = false;
      });
    }
    _resetCollapseTimer();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    final audio = appState.audio;
    final autoplay = appState.autoplay;
    final tokens = context.echo;
    final theme = Theme.of(context);
    final buttonFill = tokens.accentPrimary;

    return ListenableSelector<AutoplayState>(
      listenable: autoplay,
      selector: () => autoplay.state,
      shouldRebuild: _miniPlayerShouldRebuild,
      builder: (context, state) {
        if (state.queue.isEmpty || state.currentNote == null) {
          return const SizedBox.shrink();
        }
        if (state.phase == AutoplayPhase.idle ||
            state.phase == AutoplayPhase.completed) {
          return const SizedBox.shrink();
        }
        final note = state.currentNote ??
            state.queue[
                state.currentIndex.clamp(0, state.queue.length - 1)];
        final hashtagId = state.hashtagId;
        final hashtag =
            hashtagId == null ? null : appState.hashtagById(hashtagId);
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        final bottomPadding = EchoLayout.space(context, 8);
        return StreamBuilder<PlaybackMetrics>(
          stream: audio.playbackMetrics,
          initialData: audio.currentMetrics,
          builder: (context, snapshot) {
            final metrics = snapshot.data ?? audio.currentMetrics;
            final ui = resolveAutoplayUiSnapshot(
              state: state,
              metrics: metrics,
              currentNoteId: note.id,
            );
            final isEnginePlaying = ui.isEnginePlaying;
            final statusText = ui.statusLabel;

            return Positioned(
              left: 0,
              right: 0,
              bottom: max(bottomInset, bottomPadding),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: EchoLayout.contentHorizontalPadding(context),
                ),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _registerInteraction(),
                  // Outer container: carries shadow/glow outside the clip
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.shadowHeavy,
                          blurRadius: 28,
                          offset: const Offset(0, 8),
                          spreadRadius: -2,
                        ),
                        if (isEnginePlaying)
                          BoxShadow(
                            color: tokens.accentPrimary.withValues(alpha: 0.22),
                            blurRadius: 34,
                            spreadRadius: 0,
                          ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.lerp(
                                  tokens.surface2,
                                  tokens.accentPrimary,
                                  0.05,
                                )!.withValues(alpha: 0.93),
                                tokens.surface1.withValues(alpha: 0.89),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isEnginePlaying
                                  ? tokens.accentPrimary.withValues(alpha: 0.30)
                                  : tokens.border.withValues(alpha: 0.55),
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MiniPlayerHeader(
                                appState: appState,
                                hashtagName: hashtag?.name ?? 'Station',
                                subtitle: note.transcriptPreview ?? statusText,
                                isCollapsed: _isCollapsed,
                                isMuted: state.isMuted,
                                isEnginePlaying: isEnginePlaying,
                                buttonFill: buttonFill,
                                tokens: tokens,
                                theme: theme,
                                onMuteTap: () {
                                  _registerInteraction();
                                  autoplay.toggleMute();
                                },
                                onPlayPauseTap: () {
                                  _registerInteraction();
                                  autoplay.togglePlayPause();
                                },
                                tracker: _MiniPlayerTracker(
                                  audio: audio,
                                  currentNoteId: note.id,
                                  fallbackDuration: note.duration,
                                  textStyle: theme.textTheme.labelSmall
                                      ?.copyWith(color: tokens.textSecondary),
                                ),
                              ),
                              if (!_isCollapsed) ...[
                                const SizedBox(height: 10),
                                _MiniPlayerProgress(
                                  audio: audio,
                                  currentNoteId: note.id,
                                  fallbackDuration: note.duration,
                                  trackColor: tokens.textSecondary
                                      .withValues(alpha: 0.15),
                                  progressColor: buttonFill,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Three-bar animated EQ wave indicator — standard music player active state.
class _MiniWaveIndicator extends StatefulWidget {
  const _MiniWaveIndicator({
    required this.color,
    required this.reduceMotion,
    required this.isActive,
  });

  final Color color;
  final bool reduceMotion;
  final bool isActive;

  @override
  State<_MiniWaveIndicator> createState() => _MiniWaveIndicatorState();
}

class _MiniWaveIndicatorState extends State<_MiniWaveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _barWidth = 3.0;
  static const _barGap = 2.5;
  static const _minH = 3.0;
  static const _maxH = 13.0;
  // Phase offsets in radians for each bar (120° apart = organic ripple)
  static const _phases = [0.0, 2 * pi / 3, 4 * pi / 3];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (!widget.reduceMotion && widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _MiniWaveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion || !widget.isActive) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const totalWidth = 3 * _barWidth + 2 * _barGap;
    return SizedBox(
      width: totalWidth,
      height: _maxH,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 2 * pi;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final double h;
              if (!widget.isActive) {
                h = _minH;
              } else if (widget.reduceMotion) {
                // Static mid-height bars when reduce motion is on
                h = _maxH * (0.45 + i * 0.15);
              } else {
                final wave = (sin(t + _phases[i]) + 1) / 2;
                h = _minH + (_maxH - _minH) * wave;
              }
              return Padding(
                padding: EdgeInsets.only(right: i < 2 ? _barGap : 0),
                child: Container(
                  width: _barWidth,
                  height: h,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

bool _miniPlayerShouldRebuild(AutoplayState previous, AutoplayState next) {
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
  if (previous.isMuted != next.isMuted) {
    return true;
  }
  if (previous.userPaused != next.userPaused) {
    return true;
  }
  if (previous.hashtagId != next.hashtagId) {
    return true;
  }
  return false;
}

class _MiniPlayerProgress extends StatelessWidget {
  const _MiniPlayerProgress({
    required this.audio,
    required this.currentNoteId,
    required this.fallbackDuration,
    required this.trackColor,
    required this.progressColor,
  });

  final AudioPlaybackController audio;
  final String currentNoteId;
  final Duration fallbackDuration;
  final Color trackColor;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackMetrics>(
      stream: audio.playbackMetrics,
      initialData: audio.currentMetrics,
      builder: (context, snapshot) {
        final metrics = snapshot.data ?? audio.currentMetrics;
        // Only use live metrics when sourceId matches the current note.
        // The previous `|| metrics.playing` guard leaked stale position
        // from the departing track for a frame during transitions.
        final useLiveMetrics = metrics.sourceId == currentNoteId;
        final duration = useLiveMetrics && metrics.duration.inMilliseconds > 0
            ? metrics.duration
            : fallbackDuration;
        final ratio = duration.inMilliseconds == 0
            ? 0.0
            : ((useLiveMetrics ? metrics.position.inMilliseconds : 0) /
                      duration.inMilliseconds)
                  .clamp(0.0, 1.0)
                  .toDouble();
        return LayoutBuilder(
          builder: (context, constraints) {
            const dotSize = 9.0;
            final trackWidth = constraints.maxWidth;
            final left = (trackWidth - dotSize) * ratio;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: progressColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                Positioned(
                  left: left,
                  child: Container(
                    height: dotSize,
                    width: dotSize,
                    decoration: BoxDecoration(
                      color: progressColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: progressColor.withValues(alpha: 0.55),
                          blurRadius: 6,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerHeader extends StatelessWidget {
  const _MiniPlayerHeader({
    required this.appState,
    required this.hashtagName,
    required this.subtitle,
    required this.isCollapsed,
    required this.isMuted,
    required this.isEnginePlaying,
    required this.buttonFill,
    required this.tokens,
    required this.theme,
    required this.onMuteTap,
    required this.onPlayPauseTap,
    required this.tracker,
  });

  final AppScopeState appState;
  final String hashtagName;
  final String subtitle;
  final bool isCollapsed;
  final bool isMuted;
  final bool isEnginePlaying;
  final Color buttonFill;
  final EchoTokens tokens;
  final ThemeData theme;
  final VoidCallback onMuteTap;
  final VoidCallback onPlayPauseTap;
  final Widget tracker;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!isCollapsed) ...[
          _MiniWaveIndicator(
            color: buttonFill,
            reduceMotion: appState.settings.reduceMotion,
            isActive: isEnginePlaying,
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hashtagName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              if (isCollapsed)
                tracker
              else
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: isMuted ? 'Unmute current note' : 'Mute current note',
          onPressed: onMuteTap,
          icon: Icon(
            isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          ),
          iconSize: 19,
          constraints: const BoxConstraints.tightFor(
            width: 40,
            height: 40,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: isMuted ? tokens.textPrimary : tokens.textSecondary,
          ),
        ),
        GestureDetector(
          onTap: onPlayPauseTap,
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buttonFill,
              boxShadow: isEnginePlaying
                  ? [
                      BoxShadow(
                        color: buttonFill.withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isEnginePlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.black,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniPlayerTracker extends StatelessWidget {
  const _MiniPlayerTracker({
    required this.audio,
    required this.currentNoteId,
    required this.fallbackDuration,
    this.textStyle,
  });

  final AudioPlaybackController audio;
  final String currentNoteId;
  final Duration fallbackDuration;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackMetrics>(
      stream: audio.playbackMetrics,
      initialData: audio.currentMetrics,
      builder: (context, snapshot) {
        final metrics = snapshot.data ?? audio.currentMetrics;
        // Match only by sourceId to avoid leaking the previous track's
        // position/duration during transitions.
        final useLiveMetrics = metrics.sourceId == currentNoteId;
        final duration = useLiveMetrics && metrics.duration.inMilliseconds > 0
            ? metrics.duration
            : fallbackDuration;
        final position = useLiveMetrics ? metrics.position : Duration.zero;
        return Text(
          '${_formatDuration(position)} / ${_formatDuration(duration)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        );
      },
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
