import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';

class OnboardingWelcome extends StatelessWidget {
  const OnboardingWelcome({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      child: Padding(
        padding: EchoLayout.pagePadding(
          context,
          top: 32,
          bottom: 32,
        ),
        child: Column(
          children: [
            const Spacer(),
            Container(
              height: 96,
              width: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EchoColors.accent,
                border: Border.all(
                  color: EchoColors.accent.withValues(alpha: 0.45),
                ),
              ),
              child: Icon(
                Icons.graphic_eq,
                color: EchoColors.background,
                size: 42,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Human ambiance, in 12 seconds.',
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 16),
            Text(
              'Listen to short voice thoughts by topic. Post if you want. No pressure.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: EchoColors.textSecondary,
                height: 1.5,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go('/onboarding/interests'),
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
