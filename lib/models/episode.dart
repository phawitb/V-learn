/// A single video lesson within a course chapter.
class Episode {
  final String id;
  final String title;
  final int durationSeconds;
  final String youtubeId;
  final bool completed;
  final int positionSeconds;

  const Episode({
    required this.id,
    required this.title,
    required this.durationSeconds,
    required this.youtubeId,
    this.completed = false,
    this.positionSeconds = 0,
  });

  String get durationLabel {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: json['id'] as String,
        title: json['title'] as String,
        durationSeconds: json['duration_seconds'] as int,
        youtubeId: json['youtube_id'] as String,
        completed: json['completed'] as bool? ?? false,
        positionSeconds: json['position_seconds'] as int? ?? 0,
      );
}

/// Groups episodes the way the "เลือกตอน" screen groups them under a
/// chapter heading (e.g. "บทที่ 1 การเคลื่อนที่ 2 มิติ...").
class Chapter {
  final String title;
  final List<Episode> episodes;

  const Chapter({required this.title, required this.episodes});

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        title: json['title'] as String,
        episodes: (json['episodes'] as List)
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
