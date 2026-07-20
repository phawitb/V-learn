import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  String? _error;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // Cache-first: AppState.loadCourseDetail/loadCatalog/loadMockExams each
  // apply a cached response immediately (if one exists from a previous
  // visit) before this even finishes awaiting the network, so build() below
  // can paint the last-known state on the very first frame instead of
  // waiting on this whole chain. The network calls that follow only touch
  // the UI again if the backend's answer actually changed.
  Future<void> _bootstrap() async {
    final appState = context.read<AppState>();
    final knownTargetId = appState.activeCourseId;
    try {
      final loads = <Future>[appState.loadCatalog()];
      if (knownTargetId != null) {
        loads.addAll([appState.loadCourseDetail(knownTargetId), appState.loadMockExams(knownTargetId)]);
      }
      await Future.wait(loads);

      final catalog = appState.catalog;
      var targetId = knownTargetId;
      if (targetId == null || !catalog.any((c) => c.id == targetId)) {
        targetId = catalog.firstWhere((c) => c.hasEggspace, orElse: () => catalog.first).id;
      }

      // The catalog we just loaded already says whether this course is
      // enrolled — skip the extra round trip to /enroll (whose response is
      // thrown away anyway) unless it's genuinely a first-time enrollment.
      final alreadyEnrolled = catalog.any((c) => c.id == targetId && c.enrolled);
      if (!alreadyEnrolled) {
        await appState.enrollInCourse(targetId);
      }
      if (targetId != knownTargetId) {
        await Future.wait([appState.loadCourseDetail(targetId), appState.loadMockExams(targetId)]);
      }
      if (appState.activeCourseId != targetId) {
        await appState.setActiveCourseId(targetId);
      }
      if (mounted) setState(() => _error = null);
    } catch (e) {
      // If we already have something on screen (from cache or an earlier
      // successful load), keep showing it rather than replacing it with an
      // error — only a truly empty first load surfaces the error state.
      if (mounted) {
        setState(() {
          _error = e is ApiException ? e.message : 'เชื่อมต่อ backend ไม่ได้ ตรวจสอบว่ารัน uvicorn อยู่ที่ :8000';
        });
      }
    }
  }

  Future<void> _reload() => _bootstrap();

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
            for (final entry in appState.catalog)
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
    final appState = context.watch<AppState>();
    final course = appState.activeCourse;

    if (course == null) {
      if (_error != null) {
        return Scaffold(body: _ErrorState(message: _error!, onRetry: _reload));
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
      bottomNavigationBar: _BottomNavBar(
        selectedIndex: _tabIndex,
        onSelect: (i) => setState(() => _tabIndex = i),
        items: const [
          _NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'หน้าหลัก'),
          _NavItem(icon: Icons.track_changes_outlined, selectedIcon: Icons.track_changes_rounded, label: 'ทบทวน'),
          _NavItem(icon: Icons.chat_bubble_outline_rounded, selectedIcon: Icons.chat_bubble_rounded, label: 'แชท'),
          _NavItem(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'โปรไฟล์'),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavItem({required this.icon, required this.selectedIcon, required this.label});
}

/// Same look as Material's NavigationBar (indicator pill, colors pulled
/// from the theme) but with a tighter icon-label gap — NavigationBar's
/// spacing there isn't exposed via any public theme property.
class _BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onSelect;

  const _BottomNavBar({required this.selectedIndex, required this.items, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 3,
      child: SafeArea(
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    selected: i == selectedIndex,
                    scheme: scheme,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _NavButton({required this.item, required this.selected, required this.scheme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(selected ? item.selectedIcon : item.icon, color: iconColor, size: 23),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
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
