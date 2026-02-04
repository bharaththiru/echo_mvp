import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
import '../data/seed_data.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';

class OnboardingInterests extends StatefulWidget {
  const OnboardingInterests({super.key});

  @override
  State<OnboardingInterests> createState() => _OnboardingInterestsState();
}

class _OnboardingInterestsState extends State<OnboardingInterests> {
  final Set<String> _selected = {};
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      final appState = AppScope.of(context);
      if (appState.hashtags.isEmpty && !appState.hashtagsLoading) {
        appState.refreshHashtags();
      }
    }
    if (_selected.isEmpty) {
      final appState = AppScope.of(context);
      _selected.addAll(appState.onboardingInterests);
    }
  }

  void _toggle(String tag) {
    setState(() {
      if (_selected.contains(tag)) {
        _selected.remove(tag);
      } else {
        _selected.add(tag);
      }
    });
  }

  void _continue() {
    final appState = AppScope.of(context);
    appState.setOnboardingInterests(_selected.toList());
    context.go('/onboarding/permissions');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final appState = AppScope.of(context);
    final reduceMotion = appState.settings.reduceMotion;
    final hashtags = appState.hashtags;
    final tags = hashtags.isNotEmpty
        ? hashtags.map((tag) => tag.name).toList()
        : suggestedHashtags;

    return AppScaffold(
      child: Padding(
        padding: EchoLayout.pagePadding(
          context,
          top: 8,
          bottom: 8,
          includeBottomSafeArea: true,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick a few hashtags to start',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'You can always explore more later.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: tags.map((tag) {
                    final isSelected = _selected.contains(tag);
                    final backgroundColor = isSelected
                        ? tokens.accentPrimary
                        : tokens.surface1.withValues(alpha: 0.85);
                    final borderColor = isSelected
                        ? tokens.accentPrimary.withValues(alpha: 0.75)
                        : tokens.borderSubtle;
                    final textColor = isSelected
                        ? tokens.bg
                        : tokens.textPrimary;
                    return GestureDetector(
                      onTap: () => _toggle(tag),
                      child: AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: borderColor, width: 1.5),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color:
                                        tokens.accentSecondary.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          tag,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected.isEmpty ? null : _continue,
                child: const Text('Start listening'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
