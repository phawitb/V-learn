import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/course_catalog_entry.dart';
import '../../services/api_client.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../chat/ai_chat_screen.dart';
import '../eggspace/mistake_hunter_screen.dart';
import '../profile/profile_screen.dart';
import 'my_courses_screen.dart';

/// Root shell once signed in: loads the active course once and shares it
/// across the bottom-nav tabs (instead of each tab fetching its own copy),
/// and owns the DEV-only course switcher since switching it should affect
/// every tab, not just the home one.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late Future<Course> _future;
  List<CourseCatalogEntry> _catalog = [];
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _future = _loadActiveCourse();
  }

  Future<Course> _loadActiveCourse() async {
    final appState = context.read<AppState>();
    _catalog = await appState.loadCatalog();

    var targetId = appState.activeCourseId;
    if (targetId == null || !_catalog.any((c) => c.id == targetId)) {
      targetId = _catalog.firstWhere((c) => c.hasEggspace, orElse: () => _catalog.first).id;
    }

    await appState.enrollInCourse(targetId);
    final course = await appState.loadCourseDetail(targetId);
    if (appState.activeCourseId != targetId) {
      await appState.setActiveCourseId(targetId);
    }
    return course;
  }

  Future<void> _reload() async {
    final next = _loadActiveCourse();
    setState(() => _future = next);
    await next;
  }

  // DEV ONLY: lets whoever is testing this shared codebase switch which of
  // the 4 main courses this "app" represents, without rebuilding. Remove
  // this sheet and the gear IconButton that opens it before a real
  // per-course production deploy.
  void _showCourseSwitcher(BuildContext context) {
    final appState = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'DEV: เลือกคอร์สที่จะแสดง',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.inkFaint),
                ),
              ),
            ),
            const Divider(height: 1),
            for (final entry in _catalog)
              ListTile(
                title: Text(entry.title),
                subtitle: Text(
                  entry.hasEggspace ? '${entry.subjectCount} วิชา · ${entry.totalQuestions} ข้อ' : 'ยังไม่มีเนื้อหา',
                ),
                trailing: entry.id == appState.activeCourseId
                    ? const Icon(Icons.check_circle, color: AppColors.blueDark)
                    : null,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await appState.setActiveCourseId(entry.id);
                  setState(() => _tabIndex = 0);
                  _reload();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Course>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: _ErrorState(
              message: snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : 'เชื่อมต่อ backend ไม่ได้ ตรวจสอบว่ารัน uvicorn อยู่ที่ :8000',
              onRetry: _reload,
            ),
          );
        }

        final course = snapshot.data!;
        final tabs = [
          MyCoursesScreen(
            course: course,
            onShowSwitcher: () => _showCourseSwitcher(context),
            onReload: _reload,
          ),
          const MistakeHunterScreen(),
          const AiChatScreen(),
          const ProfileScreen(),
        ];

        return Scaffold(
          body: IndexedStack(index: _tabIndex, children: tabs),
          bottomNavigationBar: NavigationBar(
            height: 62,
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) => setState(() => _tabIndex = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'หน้าหลัก'),
              NavigationDestination(
                icon: Icon(Icons.track_changes_outlined),
                selectedIcon: Icon(Icons.track_changes_rounded),
                label: 'ทบทวน',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'แชท',
              ),
              NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'โปรไฟล์'),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.inkFaint),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
          ],
        ),
      ),
    );
  }
}
