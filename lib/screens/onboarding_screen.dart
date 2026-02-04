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
  static const _pages = [
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
      microcopy: 'You can post too - only if you feel like it.',
    ),
  ];

  late final PageController _controller;
  int _currentIndex = 0;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _controller.addListener(_handleScroll);
  }

  void _handleScroll() {
    final nextPage = _controller.page;
    if (nextPage == null) {
      return;
    }
    if ((nextPage - _page).abs() < 0.001) {
      return;
    }
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

  Future<void> _onPrimaryCta(AppState appState, bool reduceMotion) async {
    HapticFeedback.lightImpact();
    final isLast = _currentIndex == _pages.length - 1;
    if (isLast) {
      _completeOnboarding(appState);
      return;
    }
    final nextIndex = _currentIndex + 1;
    if (reduceMotion) {
      _controller.jumpToPage(nextIndex);
      return;
    }
    await _controller.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
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
    final showSkip = _currentIndex < _pages.length - 1;
    final buttonLabel = _currentIndex == _pages.length - 1
        ? 'Choose a hashtag'
        : 'Continue';
    final semanticsLabel =
        '$buttonLabel, page ${_currentIndex + 1} of ${_pages.length}';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: tokens.bg,
        body: SafeArea(
          child: Column(
            children: [
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
                    if (showSkip)
                      TextButton(
                        onPressed: () => _completeOnboarding(appState),
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.textSecondary,
                          textStyle: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('Skip'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableHeight = constraints.maxHeight;
                    final clampedHeight = availableHeight < 280
                        ? availableHeight
                        : availableHeight.clamp(280.0, 400.0);
                    final minHeight = availableHeight > 0
                        ? availableHeight
                        : clampedHeight;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: minHeight),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                            ),
                            child: SizedBox(
                              height: clampedHeight,
                              child: PageView.builder(
                                controller: _controller,
                                itemCount: _pages.length,
                                onPageChanged: (index) {
                                  setState(() {
                                    _currentIndex = index;
                                    _page = index.toDouble();
                                  });
                                },
                                itemBuilder: (context, index) {
                                  final page = _pages[index];
                                  return _OnboardingCard(
                                    data: page,
                                    reduceMotion: reduceMotion,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
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
                      count: _pages.length,
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      button: true,
                      label: semanticsLabel,
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () =>
                              _onPrimaryCta(appState, reduceMotion),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tokens.accentPrimary,
                            foregroundColor: tokens.bg,
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
                    const SizedBox(height: 8),
                    Text(
                      'Audio-only. No camera.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontSize: 13,
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
    final indicatorDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return AnimatedContainer(
      duration: indicatorDuration,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.borderSubtle),
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
