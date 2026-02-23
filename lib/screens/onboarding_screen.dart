import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../theme/echo_theme.dart';
import '../utils/responsive.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _contentPages = [
    _OnboardingPageData(
      title: 'Welcome to Echo.',
      body: 'A quiet place for short human voices.',
    ),
    _OnboardingPageData(
      title: 'Listening is enough.',
      body: 'No likes, no followers, no public comments. Just voices.',
      microcopy: "You don't have to respond. Listening is participation.",
    ),
    _OnboardingPageData(
      title: 'Keep it gentle.',
      body:
          '12 seconds. Skips are limited to keep Echo listen-first. You can always mute a clip.',
      microcopy: 'You can post too — only if you feel like it.',
    ),
  ];

  // The permissions step is appended after the content pages.
  static int get _totalPages => _contentPages.length + 1;
  static int get _permissionsIndex => _contentPages.length; // = 3

  late final PageController _controller;
  int _currentIndex = 0;
  double _page = 0;

  bool _micGranted = false;
  bool _micRequesting = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _controller.addListener(_handleScroll);
  }

  void _handleScroll() {
    final nextPage = _controller.page;
    if (nextPage == null) return;
    if ((nextPage - _page).abs() < 0.001) return;
    setState(() => _page = nextPage);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _completeOnboarding(AppState appState) {
    appState.completeOnboarding();
    context.go('/listen');
  }

  // Skip jumps to the permissions page so users always see the mic prompt.
  void _skipToPermissions(bool reduceMotion) {
    HapticFeedback.lightImpact();
    if (reduceMotion) {
      _controller.jumpToPage(_permissionsIndex);
    } else {
      _controller.animateToPage(
        _permissionsIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _onPrimaryCta(AppState appState, bool reduceMotion) async {
    HapticFeedback.lightImpact();
    if (_currentIndex == _permissionsIndex) {
      _completeOnboarding(appState);
      return;
    }
    final nextIndex = _currentIndex + 1;
    if (reduceMotion) {
      _controller.jumpToPage(nextIndex);
    } else {
      await _controller.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _requestMic() async {
    if (_micRequesting || _micGranted) return;
    setState(() => _micRequesting = true);
    final appState = AppScope.of(context);
    final granted = await appState.audio.requestMicrophonePermission();
    if (!mounted) return;
    setState(() {
      _micGranted = granted;
      _micRequesting = false;
    });
    if (granted) HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    final mediaQuery = MediaQuery.of(context);
    final reduceMotion =
        mediaQuery.disableAnimations ||
        mediaQuery.accessibleNavigation ||
        appState.settings.reduceMotion;

    final theme = Theme.of(context);
    final tokens = context.echo;
    final overlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final horizontalPadding = EchoLayout.contentHorizontalPadding(context);
    final isPermissionsPage = _currentIndex == _permissionsIndex;
    // Skip is visible on all pages except the permissions page.
    final showSkip = _currentIndex < _permissionsIndex;
    final buttonLabel = isPermissionsPage ? 'Get started' : 'Continue';
    final semanticsLabel =
        '$buttonLabel, page ${_currentIndex + 1} of $_totalPages';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: tokens.bg,
        body: SafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  EchoLayout.space(context, 8),
                  horizontalPadding,
                  EchoLayout.space(context, 6),
                ),
                child: Row(
                  children: [
                    Text(
                      'Echo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    // Animate skip in/out instead of hard show/hide.
                    AnimatedOpacity(
                      opacity: showSkip ? 1.0 : 0.0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !showSkip,
                        child: TextButton(
                          onPressed: () => _skipToPermissions(reduceMotion),
                          style: TextButton.styleFrom(
                            foregroundColor: tokens.textSecondary,
                            textStyle: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: const Text('Skip'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── PageView — fills all remaining vertical space ─────────────
              //
              // Previously, a SizedBox capped the PageView at 400 px, leaving
              // dead space on tall screens. Now the PageView expands to fill
              // the Expanded slot; each card handles overflow via its own
              // internal SingleChildScrollView.
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _totalPages,
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                        _page = index.toDouble();
                      });
                    },
                    itemBuilder: (context, index) {
                      if (index == _permissionsIndex) {
                        return _PermissionPageCard(
                          micGranted: _micGranted,
                          micRequesting: _micRequesting,
                          onRequestMic: _requestMic,
                          reduceMotion: reduceMotion,
                        );
                      }
                      return _OnboardingCard(
                        data: _contentPages[index],
                        reduceMotion: reduceMotion,
                      );
                    },
                  ),
                ),
              ),

              // ── Footer ────────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  EchoLayout.space(context, 6),
                  horizontalPadding,
                  EchoLayout.space(context, 8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DotsIndicator(
                      page: _page,
                      count: _totalPages,
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      button: true,
                      label: semanticsLabel,
                      child: SizedBox(
                        width: double.infinity,
                        height: EchoLayout.buttonHeight(context),
                        // AnimatedSwitcher cross-fades the label when it changes.
                        child: AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: ElevatedButton(
                            key: ValueKey(buttonLabel),
                            onPressed: () =>
                                _onPrimaryCta(appState, reduceMotion),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tokens.accentPrimary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.1,
                              ),
                            ),
                            child: Text(buttonLabel),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Tagline fades out on the permissions page.
                    AnimatedOpacity(
                      opacity: isPermissionsPage ? 0.0 : 1.0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      child: Text(
                        'Audio-only. No camera.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Permission page card ───────────────────────────────────────────────────────

class _PermissionPageCard extends StatelessWidget {
  const _PermissionPageCard({
    required this.micGranted,
    required this.micRequesting,
    required this.onRequestMic,
    required this.reduceMotion,
  });

  final bool micGranted;
  final bool micRequesting;
  final VoidCallback onRequestMic;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final animDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return AnimatedContainer(
      duration: animDuration,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = constraints.maxHeight > 48
              ? constraints.maxHeight - 48
              : 0.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Mic icon — animates between states.
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: micGranted
                          ? tokens.accentPrimary.withValues(alpha: 0.15)
                          : tokens.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Icon(
                        micGranted ? Icons.check_rounded : Icons.mic_rounded,
                        key: ValueKey(micGranted),
                        color: micGranted
                            ? tokens.accentPrimary
                            : tokens.textSecondary,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Semantics(
                    header: true,
                    child: Text(
                      'Microphone access',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Body
                  Text(
                    'Echo needs the microphone to record your voice. '
                    'Listening works without it.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: tokens.textPrimary.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Permission action row — cross-fades between states.
                  AnimatedSize(
                    duration: animDuration,
                    curve: Curves.easeOut,
                    child: AnimatedSwitcher(
                      duration: animDuration,
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: micGranted
                          ? _GrantedBadge(tokens: tokens, key: const ValueKey('granted'))
                          : SizedBox(
                              key: const ValueKey('allow'),
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: micRequesting ? null : onRequestMic,
                                icon: micRequesting
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: tokens.accentPrimary,
                                        ),
                                      )
                                    : const Icon(Icons.mic_rounded, size: 18),
                                label: Text(
                                  micRequesting
                                      ? 'Requesting…'
                                      : 'Allow microphone',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: tokens.accentPrimary,
                                  side: BorderSide(
                                    color: tokens.accentPrimary.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      EchoRadii.button,
                                    ),
                                  ),
                                  textStyle: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Fine print
                  Text(
                    'You can change this any time in Settings.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13.5,
                      height: 1.4,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GrantedBadge extends StatelessWidget {
  const _GrantedBadge({super.key, required this.tokens});

  final EchoSemantic tokens;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.accentPrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(EchoRadii.button),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, color: tokens.accentPrimary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Microphone enabled',
              style: TextStyle(
                color: tokens.accentPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Content card ──────────────────────────────────────────────────────────────

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({required this.data, required this.reduceMotion});

  final _OnboardingPageData data;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: tokens.textPrimary,
    );
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.45,
      fontWeight: FontWeight.w500,
      color: tokens.textPrimary.withValues(alpha: 0.88),
    );
    final microStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13.5,
      height: 1.4,
      color: tokens.textSecondary,
    );
    final animDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return AnimatedContainer(
      duration: animDuration,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = constraints.maxHeight > 48
              ? constraints.maxHeight - 48
              : 0.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(data.title, style: titleStyle),
                  ),
                  const SizedBox(height: 14),
                  Text(data.body, style: bodyStyle),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 22),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: data.microcopy == null
                          ? const SizedBox.shrink()
                          : Text(data.microcopy!, style: microStyle),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Dots indicator ────────────────────────────────────────────────────────────

class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({
    required this.page,
    required this.count,
    required this.reduceMotion,
  });

  final double page;
  final int count;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final tokens = context.echo;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final distance = (page - index).abs().clamp(0.0, 1.0);
        final selectedness = 1.0 - distance;
        final width = lerpDouble(8, 18, selectedness) ?? 8;
        final color =
            Color.lerp(
              tokens.textSecondary.withValues(alpha: 0.65),
              tokens.accentPrimary,
              selectedness,
            ) ??
            tokens.textSecondary;
        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          height: 8,
          width: width,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.title,
    required this.body,
    this.microcopy,
  });

  final String title;
  final String body;
  final String? microcopy;
}
