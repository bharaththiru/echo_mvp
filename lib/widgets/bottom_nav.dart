import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import 'app_scaffold.dart';

class BottomNavShell extends StatelessWidget {
  const BottomNavShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
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
        onTap: _onTap,
      ),
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

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: EchoColors.surface,
          border: Border(
            top: BorderSide(color: EchoColors.border.withValues(alpha: 0.7)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: items.map((item) {
            final isActive = currentIndex == item.index;
            final backgroundColor = isActive
                ? EchoColors.accent.withValues(alpha: 0.14)
                : Colors.transparent;
            final foregroundColor = isActive
                ? EchoColors.accent
                : EchoColors.textSecondary;
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(item.index),
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(20),
                    border: isActive
                        ? Border.all(
                            color: EchoColors.accent.withValues(alpha: 0.28),
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, size: 22, color: foregroundColor),
                      const SizedBox(height: 4),
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
