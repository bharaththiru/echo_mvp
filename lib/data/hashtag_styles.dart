import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/echo_theme.dart';

class HashtagStyle {
  const HashtagStyle({required this.icon, required this.gradient});

  final IconData icon;
  final List<Color> gradient;
}

final Map<String, HashtagStyle> _styleMap = {
  'nightwalk': HashtagStyle(
    icon: Icons.nightlight_round,
    gradient: [_tint(EchoColors.deepTeal, 0.32), _tint(EchoColors.deepTeal, 0.48)],
  ),
  'studysession': HashtagStyle(
    icon: Icons.menu_book,
    gradient: [_tint(EchoColors.teal, 0.26), _tint(EchoColors.teal, 0.42)],
  ),
  'newmom': HashtagStyle(
    icon: Icons.child_friendly,
    gradient: [_tint(EchoColors.mint, 0.2), _tint(EchoColors.mint, 0.34)],
  ),
  'anime': HashtagStyle(
    icon: Icons.movie,
    gradient: [_tint(EchoColors.teal, 0.3), _tint(EchoColors.deepTeal, 0.5)],
  ),
  'comedy': HashtagStyle(
    icon: Icons.emoji_emotions,
    gradient: [_tint(EchoColors.deepTeal, 0.22), _tint(EchoColors.teal, 0.36)],
  ),
  'bookworm': HashtagStyle(
    icon: Icons.auto_stories,
    gradient: [_tint(EchoColors.deepTeal, 0.28), _tint(EchoColors.teal, 0.4)],
  ),
  'quietwin': HashtagStyle(
    icon: Icons.star,
    gradient: [_tint(EchoColors.deepTeal, 0.24), _tint(EchoColors.mint, 0.3)],
  ),
  'cooking': HashtagStyle(
    icon: Icons.restaurant,
    gradient: [_tint(EchoColors.deepTeal, 0.2), _tint(EchoColors.teal, 0.32)],
  ),
};

HashtagStyle resolveHashtagStyle(String id, {String? name}) {
  final normalizedId = _normalizeKey(id);
  final normalizedName = _normalizeKey(name ?? '');
  final style =
      _styleMap[id] ??
      _styleMap[normalizedId] ??
      _styleMap[normalizedName];
  if (style != null) {
    return style;
  }
  final seed = normalizedId.isNotEmpty
      ? normalizedId
      : (normalizedName.isNotEmpty ? normalizedName : id);
  return HashtagStyle(
    icon: _inferMinimalIcon('$normalizedId $normalizedName'),
    gradient: _fallbackGradient(seed),
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

List<Color> _fallbackGradient(String seed) {
  final random = Random(seed.hashCode);
  final first = _colorFrom(random);
  final second = _colorFrom(random);
  return [first, second];
}

Color _colorFrom(Random random) {
  final palette = [
    EchoColors.deepTeal,
    EchoColors.teal,
    EchoColors.mint,
  ];
  final target = palette[random.nextInt(palette.length)];
  final strength = 0.22 + random.nextDouble() * 0.28;
  return _tint(target, strength);
}

Color _tint(Color tint, double amount) {
  return Color.lerp(EchoColors.deepNavy, tint, amount)!;
}
