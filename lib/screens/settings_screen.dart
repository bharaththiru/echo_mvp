import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = AppScope.of(context);

    return AppScaffold(
      child: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          final settings = appState.settings;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                    const SizedBox(height: 12),
                    Text('Settings', style: theme.textTheme.displaySmall),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    const EchoSectionTitle('Appearance'),
                    const SizedBox(height: 12),
                    Text('Theme', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _ThemeOption(
                            label: 'Light',
                            icon: Icons.wb_sunny,
                            isSelected: settings.themeMode == ThemeMode.light,
                            onTap: () =>
                                appState.updateThemeMode(ThemeMode.light),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ThemeOption(
                            label: 'Dark',
                            icon: Icons.nightlight_round,
                            isSelected: settings.themeMode == ThemeMode.dark,
                            onTap: () =>
                                appState.updateThemeMode(ThemeMode.dark),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ThemeOption(
                            label: 'System',
                            icon: Icons.desktop_windows,
                            isSelected: settings.themeMode == ThemeMode.system,
                            onTap: () =>
                                appState.updateThemeMode(ThemeMode.system),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ToggleTile(
                      title: 'Subtle mood tint',
                      subtitle: 'Gentle background gradients per hashtag',
                      value: settings.moodTintEnabled,
                      onChanged: appState.updateMoodTint,
                    ),
                    const SizedBox(height: 12),
                    _ToggleTile(
                      title: 'Caption preview',
                      subtitle: 'Show the caption under each note',
                      value: settings.transcriptsEnabled,
                      onChanged: appState.updateTranscripts,
                    ),
                    const SizedBox(height: 12),
                    _ToggleTile(
                      title: 'Reduce motion',
                      subtitle: 'Minimize animations and transitions',
                      value: settings.reduceMotion,
                      onChanged: appState.updateReduceMotion,
                    ),
                    const SizedBox(height: 24),
                    const EchoSectionTitle('Notifications'),
                    const SizedBox(height: 12),
                    _ToggleTile(
                      title: 'Private replies',
                      subtitle:
                          'Get notified when someone replies to your post',
                      value: settings.repliesNotifications,
                      onChanged: appState.updateRepliesNotifications,
                    ),
                    const SizedBox(height: 12),
                    _ToggleTile(
                      title: 'New posts in saved hashtags',
                      subtitle: 'Optional gentle reminders',
                      value: settings.hashtagNotifications,
                      onChanged: appState.updateHashtagNotifications,
                    ),
                    const SizedBox(height: 24),
                    const EchoSectionTitle('Privacy and safety'),
                    const SizedBox(height: 12),
                    _LinkTile(
                      title: 'Blocked accounts',
                      subtitle: 'Manage your blocklist',
                    ),
                    const SizedBox(height: 8),
                    _LinkTile(
                      title: 'Report history',
                      subtitle: 'View your past reports',
                    ),
                    const SizedBox(height: 24),
                    const EchoSectionTitle('Legal'),
                    const SizedBox(height: 12),
                    _LinkTile(title: 'Community guidelines'),
                    const SizedBox(height: 8),
                    _LinkTile(title: 'Privacy policy'),
                    const SizedBox(height: 8),
                    _LinkTile(title: 'Terms of service'),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Echo v1.0.0',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: EchoColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = isSelected
        ? EchoColors.accent.withValues(alpha: 0.18)
        : EchoColors.surface;
    final borderColor = isSelected
        ? EchoColors.accent.withValues(alpha: 0.48)
        : EchoColors.borderSubtle;
    final foregroundColor = isSelected
        ? EchoColors.accent
        : EchoColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: foregroundColor),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? EchoColors.textPrimary
                    : EchoColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EchoCard(
      padding: const EdgeInsets.all(16),
      radius: 18,
      color: EchoColors.muted,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: EchoColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EchoCard(
      padding: const EdgeInsets.all(16),
      radius: 18,
      color: EchoColors.muted,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: EchoColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: EchoColors.textSecondary),
        ],
      ),
    );
  }
}
