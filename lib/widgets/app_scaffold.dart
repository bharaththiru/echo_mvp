import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../services/autoplay_controller.dart';
import '../theme/echo_theme.dart';
import '../utils/responsive.dart';

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
    final brightness = Theme.of(context).brightness;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: tokens.bg,
        resizeToAvoidBottomInset: true,
        bottomNavigationBar: bottomNavigationBar,
        body: SafeArea(
          child: Stack(
            children: [
              SizedBox(width: double.infinity, child: child),
              if (showMiniPlayer) const _MiniPlayer(),
            ],
          ),
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

    return AnimatedBuilder(
      animation: autoplay,
      builder: (context, _) {
        final state = autoplay.state;
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
        final hashtag = hashtagId == null ? null : appState.hashtagById(hashtagId);
        final duration = state.duration.inMilliseconds > 0
            ? state.duration
            : note.duration;
        final progress = duration.inMilliseconds == 0
            ? 0.0
            : (state.position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble();
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        final safeBottom = MediaQuery.paddingOf(context).bottom;
        final bottomPadding = max(10.0, safeBottom);
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
              horizontal: EchoLayout.horizontalPadding(context),
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
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF071C4A).withValues(alpha: 0.94),
                          const Color(0xFF0A2A5A).withValues(alpha: 0.9),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: tokens.borderSubtle),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.shadow.withValues(alpha: 0.3),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            _MiniPulseDot(
                              color: tokens.accentSecondary,
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
                                    style: theme.textTheme.titleSmall,
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
                                state.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
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
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const dotSize = 7.0;
                            final trackWidth = constraints.maxWidth;
                            final left = (trackWidth - dotSize) * progress;
                            return Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: tokens.surface3,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: progress,
                                  child: Container(
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: tokens.accentPrimary,
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
                                      color: tokens.accentSecondary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: tokens.accentSecondary
                                              .withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
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
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.5),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
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
