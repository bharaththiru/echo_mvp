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

HashtagStyle resolveHashtagStyle(String id) {
  final style = _styleMap[id];
  if (style != null) {
    return style;
  }
  return HashtagStyle(icon: Icons.local_offer, gradient: _fallbackGradient(id));
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
