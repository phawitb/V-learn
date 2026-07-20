import 'package:flutter/material.dart';

import 'episode.dart';
import 'mission_node.dart';

Color _colorFromHex(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}

/// A purchased/enrolled course — the root object shown on "คอร์สของฉัน" and
/// the course detail screen. [chapters] back the classic episode player;
/// [missionUnits] back the eggspace mission path (only present when
/// [hasEggspace] is true). Both lists are empty until fetched via
/// `GET /courses/{id}` — the summary list endpoint only returns metadata.
class Course {
  final String id;
  final String code;
  final String title;
  final String instructor;
  final List<Color> thumbnailGradient;
  final int totalHours;
  final int totalEpisodes;
  final double progress;
  final DateTime expiresAt;
  final String? lastEpisodeId;
  final bool hasEggspace;
  final List<Chapter> chapters;
  final List<MissionUnit> missionUnits;

  const Course({
    required this.id,
    required this.code,
    required this.title,
    required this.instructor,
    required this.thumbnailGradient,
    required this.totalHours,
    required this.totalEpisodes,
    required this.progress,
    required this.expiresAt,
    this.lastEpisodeId,
    this.hasEggspace = false,
    this.chapters = const [],
    this.missionUnits = const [],
  });

  List<Episode> get allEpisodes => chapters.expand((c) => c.episodes).toList();

  bool get hasVideoContent => chapters.isNotEmpty;

  int get totalQuestions => missionUnits.fold(0, (sum, u) => sum + u.questions.length);

  Duration get timeRemaining => expiresAt.difference(DateTime.now());

  String get remainingLabel {
    final d = timeRemaining;
    if (d.isNegative) return 'หมดอายุแล้ว';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours >= 24) {
      final days = (hours / 24).floor();
      return 'เหลือ $days วัน';
    }
    return 'เหลือ $hours ชั่วโมง $minutes นาที';
  }

  String get expiresAtLabel {
    final e = expiresAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(e.day)}/${two(e.month)}/${e.year} ${two(e.hour)}:${two(e.minute)} น.';
  }

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String,
        code: json['code'] as String,
        title: json['title'] as String,
        instructor: json['instructor'] as String,
        thumbnailGradient: [
          _colorFromHex(json['thumb_color_start'] as String),
          _colorFromHex(json['thumb_color_end'] as String),
        ],
        totalHours: json['total_hours'] as int,
        totalEpisodes: json['total_episodes'] as int,
        progress: (json['progress'] as num).toDouble(),
        expiresAt: DateTime.parse('${json['expires_at']}Z').toLocal(),
        lastEpisodeId: json['last_episode_id'] as String?,
        hasEggspace: json['has_eggspace'] as bool,
        chapters: (json['chapters'] as List? ?? [])
            .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
            .toList(),
        missionUnits: (json['mission_units'] as List? ?? [])
            .map((u) => MissionUnit.fromJson(u as Map<String, dynamic>))
            .toList(),
      );
}
