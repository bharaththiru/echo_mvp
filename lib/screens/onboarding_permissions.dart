import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';

class OnboardingPermissions extends StatefulWidget {
  const OnboardingPermissions({super.key});

  @override
  State<OnboardingPermissions> createState() => _OnboardingPermissionsState();
}

class _OnboardingPermissionsState extends State<OnboardingPermissions> {
  bool _micEnabled = false;
  bool _notificationsEnabled = false;

  Future<void> _enableMic() async {
    final appState = AppScope.of(context);
    final granted = await appState.audio.requestMicrophonePermission();
    if (!mounted) {
      return;
    }
    setState(() => _micEnabled = granted);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted ? 'Microphone enabled.' : 'Microphone permission denied.',
        ),
      ),
    );
  }

  void _enableNotifications() {
    final appState = AppScope.of(context);
    setState(() => _notificationsEnabled = true);
    appState.updateRepliesNotifications(true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notifications preference saved.')),
    );
  }

  void _finish() {
    final appState = AppScope.of(context);
    appState.completeOnboarding();
    context.go('/listen');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A couple quick things', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'These are optional. You can enable them later in settings.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: EchoColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _PermissionCard(
                      title: 'Microphone',
                      description: 'Only needed if you want to post.',
                      icon: Icons.mic,
                      enabled: _micEnabled,
                      onEnable: _enableMic,
                    ),
                    const SizedBox(height: 16),
                    _PermissionCard(
                      title: 'Notifications',
                      description:
                          'Only for private replies if you enable them.',
                      icon: Icons.notifications,
                      enabled: _notificationsEnabled,
                      onEnable: _enableNotifications,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: EchoPrimaryButton(
                label: 'Get started',
                onPressed: _finish,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.enabled,
    required this.onEnable,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool enabled;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return EchoCard(
      padding: const EdgeInsets.all(20),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: EchoColors.muted,
                  shape: BoxShape.circle,
                  border: Border.all(color: EchoColors.borderSubtle),
                ),
                child: Icon(icon, color: EchoColors.accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: EchoColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: EchoSecondaryButton(label: 'Not now', onPressed: () {}),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: EchoPrimaryButton(
                  onPressed: enabled ? null : onEnable,
                  label: enabled ? 'Enabled' : 'Enable',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
