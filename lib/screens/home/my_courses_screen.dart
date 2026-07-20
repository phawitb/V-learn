import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/mission_node.dart';
import '../../theme/app_theme.dart';
import '../../widgets/daily_egg_card.dart';
import '../../widgets/mock_exam_section.dart';
import '../../widgets/sub_course_tile.dart';
import '../eggspace/step_solution_screen.dart';

String? _mostRecentUnitId(List<MissionUnit> units) {
  MissionUnit? best;
  for (final u in units) {
    if (u.lastActivityAt == null) continue;
    if (best == null || u.lastActivityAt!.isAfter(best.lastActivityAt!)) best = u;
  }
  return best?.id;
}

/// One illustrated banner per exam category, matching the course's own
/// accent color — falls back to the plain gradient for any course id we
/// don't have art for.
String? _headerBannerAsset(String courseId) {
  const known = {'gpa-phak-a', 'local-exam', 'police-sergeant', 'military-prep'};
  if (!known.contains(courseId)) return null;
  return 'assets/images/course_banner_$courseId.jpg';
}

/// Home tab: the active course's subject list. The active course itself is
/// loaded once by [RootShell] and shared across all bottom-nav tabs — see
/// the DEV ONLY note on [AppState.activeCourseId] for how it's picked.
class MyCoursesScreen extends StatelessWidget {
  final Course course;
  final VoidCallback onShowSwitcher;
  final Future<void> Function() onReload;

  const MyCoursesScreen({
    super.key,
    required this.course,
    required this.onShowSwitcher,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final recentUnitId = _mostRecentUnitId(course.missionUnits);
    final bannerAsset = _headerBannerAsset(course.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: onReload,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Stack(
                      children: [
                        if (bannerAsset != null)
                          Positioned.fill(
                            child: Image.asset(bannerAsset, fit: BoxFit.cover, alignment: Alignment.centerRight),
                          )
                        else
                          const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: AppColors.headerGradient))),
                        if (bannerAsset != null)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [Colors.black.withValues(alpha: 0.34), Colors.black.withValues(alpha: 0.0)],
                                  stops: const [0, 0.68],
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'คลังข้อสอบ',
                                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
                                    tooltip: 'DEV: เลือกคอร์ส',
                                    onPressed: onShowSwitcher,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                course.title,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontSize: 26),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                DailyEggCard(courseId: course.id),
                MockExamSection(courseId: course.id),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('คลังข้อสอบ (${course.missionUnits.length})', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      if (course.missionUnits.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'ยังไม่มีเนื้อหาสำหรับคอร์สนี้ในขณะนี้',
                            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                          ),
                        )
                      else
                        ...course.missionUnits.map(
                          (unit) => SubCourseTile(
                            unit: unit,
                            isRecent: unit.id == recentUnitId,
                            onTap: () async {
                              final resumeIndex = unit.questions.indexWhere((q) => !q.answered);
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => StepSolutionScreen(
                                    courseId: course.id,
                                    questions: unit.questions,
                                    initialIndex: resumeIndex == -1 ? 0 : resumeIndex,
                                    unit: unit,
                                    course: course,
                                  ),
                                ),
                              );
                              onReload();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
