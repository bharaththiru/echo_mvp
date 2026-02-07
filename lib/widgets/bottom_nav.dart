import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
import 'app_scaffold.dart';

class BottomNavShell extends StatelessWidget {
  const BottomNavShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(BuildContext context, int index) {
    if (index == 1) {
      unawaited(AppScope.of(context).autoplay.detach(stopPlayback: true));
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      bottomNavigationBar: BottomNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => _onTap(context, index),
      ),
      showMiniPlayer: navigationShell.currentIndex != 1,
      child: navigationShell,
    );
  }
}

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final buttonFill = tokens.accentPrimary;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottomGap = safeBottom > 0
        ? (safeBottom * 0.34).clamp(6.0, 12.0).toDouble()
        : 6.0;
    final reduceMotion = AppScope.of(context).settings.reduceMotion;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final items = [
      _NavItem('Listen', Icons.headphones, 0),
      _NavItem('Record', Icons.mic, 1),
      _NavItem('Inbox', Icons.inbox, 2),
      _NavItem('Profile', Icons.person, 3),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomGap),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.bg,
          borderRadius: BorderRadius.circular(EchoRadii.nav),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: items.map((item) {
            final isActive = currentIndex == item.index;
            final backgroundColor = isActive
                ? buttonFill.withValues(alpha: 0.16)
                : Colors.transparent;
            final foregroundColor = isActive
                ? tokens.accentPrimary
                : tokens.textSecondary.withValues(alpha: 0.6);
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(item.index),
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, size: 20, color: foregroundColor),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.index);

  final String label;
  final IconData icon;
  final int index;
}
