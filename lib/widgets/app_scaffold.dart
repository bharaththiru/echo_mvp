import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../services/autoplay_controller.dart';
import '../theme/echo_theme.dart';
import '../utils/time_format.dart';
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
        final bottomPadding = max(12.0, safeBottom);
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
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF071C4A).withValues(alpha: 0.94),
                          const Color(0xFF0A2A5A).withValues(alpha: 0.9),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: tokens.borderSubtle),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.shadow.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              height: 36,
                              width: 36,
                              decoration: BoxDecoration(
                                color: tokens.surface3,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: tokens.borderSubtle,
                                ),
                              ),
                              child: Icon(
                                hashtag?.icon ?? Icons.headphones,
                                color: tokens.accentPrimary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _MiniPulseDot(
                                        color: tokens.accentSecondary,
                                        reduceMotion:
                                            appState.settings.reduceMotion,
                                        isActive: state.isPlaying,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        statusText,
                                        style:
                                            theme.textTheme.labelMedium?.copyWith(
                                          color: tokens.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (state.queueRemaining > 0)
                                        Text(
                                          '${state.queueRemaining} ready',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: tokens.textTertiary,
                                              ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    hashtag?.name ?? 'Station',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  Text(
                                    note.transcriptPreview ?? 'Voice note',
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
                              onPressed: () => autoplay.toggleMute(),
                              icon: Icon(
                                state.isMuted
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                              ),
                              iconSize: 20,
                              constraints: const BoxConstraints.tightFor(
                                width: 34,
                                height: 34,
                              ),
                            ),
                            IconButton(
                              onPressed: () => autoplay.togglePlayPause(),
                              icon: Icon(
                                state.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              iconSize: 20,
                              constraints: const BoxConstraints.tightFor(
                                width: 34,
                                height: 34,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final dotSize = 7.0;
                            final trackWidth = constraints.maxWidth;
                            final left = (trackWidth - dotSize) * progress;
                            return Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: tokens.surface3,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: progress,
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
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(state.position),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: tokens.textTertiary,
                              ),
                            ),
                            Text(
                              formatDuration(duration),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: tokens.textTertiary,
                              ),
                            ),
                          ],
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
