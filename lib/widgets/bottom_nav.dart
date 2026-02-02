import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
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
    final tokens = context.echo;
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(EchoRadii.nav),
            boxShadow: [
              BoxShadow(
                color: tokens.shadow.withValues(alpha: 0.4),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(EchoRadii.nav),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tokens.surface1.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(EchoRadii.nav),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: items.map((item) {
                    final isActive = currentIndex == item.index;
                    final backgroundColor = isActive
                        ? tokens.accentPrimary.withValues(alpha: 0.16)
                        : Colors.transparent;
                    final foregroundColor = isActive
                        ? tokens.accentPrimary
                        : tokens.textTertiary;
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
                                    color: tokens.accentPrimary.withValues(
                                      alpha: 0.28,
                                    ),
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
            ),
          ),
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
