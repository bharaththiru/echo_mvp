import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/echo_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';

class OnboardingWelcome extends StatelessWidget {
  const OnboardingWelcome({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;

    return AppScaffold(
      child: Padding(
        padding: EchoLayout.pagePadding(
          context,
          top: 8,
          bottom: 8,
          includeBottomSafeArea: true,
        ),
        child: Column(
          children: [
            const Spacer(),
            Container(
              height: 96,
              width: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.accentPrimary,
              ),
              child: Icon(
                Icons.graphic_eq,
                color: tokens.bg,
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
                color: tokens.textSecondary,
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
