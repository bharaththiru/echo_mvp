import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../services/autoplay_controller.dart';
import '../theme/echo_theme.dart';
import '../utils/responsive.dart';
import 'listenable_selector.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.bottomNavigationBar,
    this.showMiniPlayer = true,
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
            SizedBox(width: double.infinity, child: child),
            if (showMiniPlayer) const _MiniPlayer(),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
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
        final statusText = state.isBuffering
            ? 'Buffering'
            : state.isPlaying
                ? 'Now listening'
                : state.phase == AutoplayPhase.paused
                    ? 'Paused'
                    : 'Ready';

        return Positioned(
          left: 0,
          right: 0,
          bottom: max(bottomInset, bottomPadding),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: EchoLayout.contentHorizontalPadding(context),
            ),
            child: GestureDetector(
              onTap: () {
                if (hashtagId == null || hashtagId.isEmpty) {
                  return;
                }
                context.push('/player/$hashtagId');
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
                  decoration: BoxDecoration(
                    color: tokens.surface1,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _MiniPulseDot(
                            color: buttonFill,
                            reduceMotion: appState.settings.reduceMotion,
                            isActive: state.isPlaying,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hashtag?.name ?? 'Station',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: tokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  note.transcriptPreview ?? statusText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: state.isMuted
                                ? 'Unmute current note'
                                : 'Mute current note',
                            onPressed: () => autoplay.toggleMute(),
                            icon: Icon(
                              state.isMuted
                                  ? Icons.volume_off
                                  : Icons.volume_up,
                            ),
                            iconSize: 19,
                            constraints: const BoxConstraints.tightFor(
                              width: 40,
                              height: 40,
                            ),
                          ),
                          IconButton(
                            tooltip: state.isPlaying ? 'Pause' : 'Play',
                            onPressed: () => autoplay.togglePlayPause(),
                            icon: Icon(
                              state.isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            iconSize: 20,
                            constraints: const BoxConstraints.tightFor(
                              width: 40,
                              height: 40,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _MiniPlayerProgress(
                        autoplay: autoplay,
                        fallbackDuration: note.duration,
                        trackColor: tokens.textSecondary.withValues(alpha: 0.2),
                        progressColor: buttonFill,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPulseDot extends StatefulWidget {
  const _MiniPulseDot({
    required this.color,
    required this.reduceMotion,
    required this.isActive,
  });

  final Color color;
  final bool reduceMotion;
  final bool isActive;

  @override
  State<_MiniPulseDot> createState() => _MiniPulseDotState();
}

class _MiniPulseDotState extends State<_MiniPulseDot>
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
    if (!widget.reduceMotion && widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _MiniPulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion || !widget.isActive) {
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
      ),
    );
    if (widget.reduceMotion || !widget.isActive) {
      return base;
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final scale = lerpDouble(0.8, 1.1, _animation.value)!;
        final opacity = lerpDouble(0.6, 1.0, _animation.value)!;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: base),
        );
      },
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
  return false;
}

class _MiniPlayerProgress extends StatelessWidget {
  const _MiniPlayerProgress({
    required this.autoplay,
    required this.fallbackDuration,
    required this.trackColor,
    required this.progressColor,
  });

  final AutoplayController autoplay;
  final Duration fallbackDuration;
  final Color trackColor;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    return ListenableSelector<_MiniProgressSnapshot>(
      listenable: autoplay,
      selector: () {
        final state = autoplay.state;
        final duration = state.duration.inMilliseconds > 0
            ? state.duration
            : fallbackDuration;
        final ratio = duration.inMilliseconds == 0
            ? 0.0
            : (state.position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble();
        return _MiniProgressSnapshot(ratio);
      },
      shouldRebuild: (previous, next) => previous != next,
      builder: (context, snapshot) {
        return LayoutBuilder(
          builder: (context, constraints) {
            const dotSize = 7.0;
            final trackWidth = constraints.maxWidth;
            final left = (trackWidth - dotSize) * snapshot.progress;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: snapshot.progress,
                  child: Container(
                    height: 3,
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

class _MiniProgressSnapshot {
  const _MiniProgressSnapshot(this.progress);

  final double progress;

  @override
  bool operator ==(Object other) {
    return other is _MiniProgressSnapshot && other.progress == progress;
  }

  @override
  int get hashCode => progress.hashCode;
}
