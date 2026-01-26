import 'dart:math';

import 'package:flutter/material.dart';

class HashtagStyle {
  const HashtagStyle({required this.icon, required this.gradient});

  final IconData icon;
  final List<Color> gradient;
}

final Map<String, HashtagStyle> _styleMap = {
  'nightwalk': HashtagStyle(
    icon: Icons.nightlight_round,
    gradient: [Color(0xFF1A202A), Color(0xFF232A35)],
  ),
  'studysession': HashtagStyle(
    icon: Icons.menu_book,
    gradient: [Color(0xFF1A232E), Color(0xFF243140)],
  ),
  'newmom': HashtagStyle(
    icon: Icons.child_friendly,
    gradient: [Color(0xFF251F2A), Color(0xFF322A38)],
  ),
  'anime': HashtagStyle(
    icon: Icons.movie,
    gradient: [Color(0xFF211F2E), Color(0xFF2D2A3E)],
  ),
  'comedy': HashtagStyle(
    icon: Icons.emoji_emotions,
    gradient: [Color(0xFF2A241E), Color(0xFF382F25)],
  ),
  'bookworm': HashtagStyle(
    icon: Icons.auto_stories,
    gradient: [Color(0xFF1E2823), Color(0xFF28342C)],
  ),
  'quietwin': HashtagStyle(
    icon: Icons.star,
    gradient: [Color(0xFF2A251C), Color(0xFF3A3326)],
  ),
  'cooking': HashtagStyle(
    icon: Icons.restaurant,
    gradient: [Color(0xFF2B201D), Color(0xFF3A2B25)],
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
  final red = 42 + random.nextInt(70);
  final green = 46 + random.nextInt(68);
  final blue = 52 + random.nextInt(66);
  return Color.fromARGB(255, red, green, blue);
}
