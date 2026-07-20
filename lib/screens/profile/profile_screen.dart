import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/egg_counter_chip.dart';
import '../auth/login_screen.dart';

String _initial(String? name) => (name == null || name.isEmpty) ? '?' : name.substring(0, 1).toUpperCase();

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                decoration: const BoxDecoration(
                  gradient: AppColors.headerGradient,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: Text(
                        _initial(user?.displayName),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.blueDark),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      user?.displayName ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(user?.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EggCounterChip(balance: user?.eggBalance ?? 0),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            'เลเวล ${user?.level ?? 1}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ข้อมูลส่วนตัว', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.inkFaint)),
                    const SizedBox(height: 10),
                    _InfoTile(icon: Icons.badge_outlined, label: 'ชื่อ-นามสกุล', value: '${user?.firstName ?? ''} ${user?.lastName ?? ''}'.trim()),
                    _InfoTile(icon: Icons.phone_outlined, label: 'เบอร์โทรศัพท์', value: user?.phone ?? '-'),
                    _InfoTile(icon: Icons.mail_outline_rounded, label: 'อีเมล', value: user?.email ?? '-'),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await context.read<AppState>().logout();
                          if (context.mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                              (route) => false,
                            );
                          }
                        },
                        icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.red),
                        label: const Text('ออกจากระบบ', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.red),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.inkFaint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.inkFaint, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '-' : value,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.ink, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
