import 'package:flutter/material.dart';

import '../data/hashtag_styles.dart';

class Hashtag {
  const Hashtag({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.gradient,
    required this.noteCount,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final List<Color> gradient;
  final int noteCount;

  factory Hashtag.fromRow(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final name = row['name'] as String? ?? '#$id';
    final style = resolveHashtagStyle(id, name: name);
    return Hashtag(
      id: id,
      name: name,
      description: row['description'] as String? ?? '',
      icon: style.icon,
      gradient: style.gradient,
      noteCount: row['note_count'] as int? ?? 0,
    );
  }
}
