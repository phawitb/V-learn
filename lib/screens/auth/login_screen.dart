import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/google_auth_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../home/root_shell.dart';
import 'profile_completion_screen.dart';

/// Google is the only sign-in method — see [GoogleAuthService]. A first-time
/// sign-in always lands on [ProfileCompletionScreen] next, since name/phone
/// aren't required by Google and this app requires them.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSigningIn = false;

  Future<void> _signIn() async {
    setState(() => _isSigningIn = true);
    try {
      final idToken = await GoogleAuthService.instance.signIn();
      if (idToken == null) return; // user cancelled the Google picker
      if (!mounted) return;
      final appState = context.read<AppState>();
      await appState.signInWithGoogle(idToken);
      if (!mounted) return;
      final next = appState.currentUser!.profileComplete ? const RootShell() : const ProfileCompletionScreen();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.headerGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: AppColors.blueDark, size: 44),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'V-Learn',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'เตรียมสอบให้ครบทุกสนาม',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 48),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 30, offset: const Offset(0, 12))],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'เข้าสู่ระบบเพื่อเริ่มฝึกทำข้อสอบ',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _isSigningIn ? null : _signIn,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.ink,
                                side: const BorderSide(color: AppColors.border),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isSigningIn
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2.4),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 20,
                                          height: 20,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppColors.border),
                                          ),
                                          child: const Text(
                                            'G',
                                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF4285F4)),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text('เข้าสู่ระบบด้วย Google', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'V-Learn ใช้บัญชี Google ในการเข้าสู่ระบบเท่านั้น',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
