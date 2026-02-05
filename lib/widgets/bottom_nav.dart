import 'dart:async';
import 'dart:ui';

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
    final brightness = theme.brightness;
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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
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
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  gradient: EchoGradients.tonal(
                    base: tokens.surface1.withValues(alpha: 0.92),
                    depth: EchoGradients.depthFor(tokens, brightness)
                        .withValues(alpha: 0.92),
                    top: 0.02,
                    bottom: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(EchoRadii.nav),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: items.map((item) {
                    final isActive = currentIndex == item.index;
                    final backgroundColor = isActive
                        ? Colors.black.withValues(alpha: 0.16)
                        : Colors.transparent;
                    final foregroundColor = isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.6);
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
