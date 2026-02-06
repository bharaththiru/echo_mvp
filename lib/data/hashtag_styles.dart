import 'package:flutter/material.dart';

import '../theme/echo_theme.dart';

class HashtagStyle {
  const HashtagStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

final Map<String, IconData> _iconMap = {
  'nightwalk': Icons.nightlight_round,
  'studysession': Icons.menu_book,
  'newmom': Icons.child_friendly,
  'anime': Icons.movie,
  'comedy': Icons.emoji_emotions,
  'bookworm': Icons.auto_stories,
  'quietwin': Icons.star,
  'cooking': Icons.restaurant,
};

HashtagStyle resolveHashtagStyle(String id, {String? name}) {
  final normalizedId = _normalizeKey(id);
  final normalizedName = _normalizeKey(name ?? '');
  final icon =
      _iconMap[id] ??
      _iconMap[normalizedId] ??
      _iconMap[normalizedName];
  final seed = normalizedId.isNotEmpty
      ? normalizedId
      : (normalizedName.isNotEmpty ? normalizedName : id);
  return HashtagStyle(
    icon: icon ?? _inferMinimalIcon('$normalizedId $normalizedName'),
    color: EchoColors.clearing,
  );
}

IconData _inferMinimalIcon(String text) {
  for (final rule in _iconRules) {
    for (final token in rule.tokens) {
      if (text.contains(token)) {
        return rule.icon;
      }
    }
  }
  final seed = text.isEmpty ? 0 : text.hashCode.abs();
  return _fallbackIcons[seed % _fallbackIcons.length];
}

String _normalizeKey(String input) {
  return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

const _iconRules = <_IconRule>[
  _IconRule(tokens: ['night', 'sleep', 'late', 'moon'], icon: Icons.nights_stay_outlined),
  _IconRule(tokens: ['study', 'book', 'read', 'learn'], icon: Icons.menu_book_outlined),
  _IconRule(tokens: ['mom', 'baby', 'parent', 'kid'], icon: Icons.child_care_outlined),
  _IconRule(tokens: ['anime', 'film', 'movie', 'show'], icon: Icons.smart_display_outlined),
  _IconRule(tokens: ['comedy', 'funny', 'laugh'], icon: Icons.sentiment_satisfied_alt_outlined),
  _IconRule(tokens: ['cook', 'food', 'kitchen', 'recipe'], icon: Icons.restaurant_outlined),
  _IconRule(tokens: ['quiet', 'calm', 'meditate', 'focus'], icon: Icons.self_improvement_outlined),
  _IconRule(tokens: ['music', 'audio', 'radio', 'sound'], icon: Icons.graphic_eq_outlined),
  _IconRule(tokens: ['work', 'career', 'office'], icon: Icons.work_outline),
  _IconRule(tokens: ['travel', 'trip', 'explore', 'adventure'], icon: Icons.explore_outlined),
];

const _fallbackIcons = <IconData>[
  Icons.circle_outlined,
  Icons.spa_outlined,
  Icons.wb_twilight_outlined,
  Icons.auto_awesome_outlined,
  Icons.track_changes_outlined,
  Icons.change_history_outlined,
  Icons.landscape_outlined,
  Icons.blur_on_outlined,
];

class _IconRule {
  const _IconRule({required this.tokens, required this.icon});

  final List<String> tokens;
  final IconData icon;
}

Color _paletteColor(String seed) {
  return EchoColors.clearing;
}
