import 'package:flutter/material.dart';

Color _colorFromHex(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}

/// A main course as shown before enrollment — the catalog picker. No
/// progress/expiry here since those only exist once a user has enrolled.
class CourseCatalogEntry {
  final String id;
  final String code;
  final String title;
  final String instructor;
  final List<Color> thumbnailGradient;
  final int subjectCount;
  final int totalQuestions;
  final bool hasEggspace;
  final bool enrolled;

  const CourseCatalogEntry({
    required this.id,
    required this.code,
    required this.title,
    required this.instructor,
    required this.thumbnailGradient,
    required this.subjectCount,
    required this.totalQuestions,
    required this.hasEggspace,
    required this.enrolled,
  });

  factory CourseCatalogEntry.fromJson(Map<String, dynamic> json) => CourseCatalogEntry(
        id: json['id'] as String,
        code: json['code'] as String,
        title: json['title'] as String,
        instructor: json['instructor'] as String,
        thumbnailGradient: [
          _colorFromHex(json['thumb_color_start'] as String),
          _colorFromHex(json['thumb_color_end'] as String),
        ],
        subjectCount: json['subject_count'] as int,
        totalQuestions: json['total_questions'] as int,
        hasEggspace: json['has_eggspace'] as bool,
        enrolled: json['enrolled'] as bool,
      );
}
