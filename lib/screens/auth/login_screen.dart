import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/google_auth_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/google_sign_in_button.dart';
import '../home/root_shell.dart';
import 'profile_completion_screen.dart';

/// Google is the only sign-in method — see [GoogleAuthService]. A first-time
/// sign-in always lands on [ProfileCompletionScreen] next, since name/phone
/// aren't required by Google and this app requires them.
///
/// Web and native diverge here: on web, `GoogleSignIn.authenticate()` drives
/// an OAuth popup that browsers can silently block outside a real DOM click
/// — so web renders Google's own GIS button ([buildGoogleSignInButton]) and
/// listens for [GoogleAuthService.authenticationEvents] instead of calling
/// [GoogleAuthService.signIn] directly.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSigningIn = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _webAuthSub;

  @override
  void initState() {
    super.initState();
    GoogleAuthService.instance.ensureInitialized();
    if (kIsWeb) {
      _webAuthSub = GoogleAuthService.instance.authenticationEvents.listen(_onWebAuthEvent);
    }
  }

  @override
  void dispose() {
    _webAuthSub?.cancel();
    super.dispose();
  }

  Future<void> _onWebAuthEvent(GoogleSignInAuthenticationEvent event) async {
    if (event is! GoogleSignInAuthenticationEventSignIn || _isSigningIn) return;
    setState(() => _isSigningIn = true);
    try {
      final idToken = GoogleAuthService.instance.idTokenOf(event.user);
      if (idToken == null) return;
      await _completeSignIn(idToken);
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _signIn() async {
    setState(() => _isSigningIn = true);
    try {
      final idToken = await GoogleAuthService.instance.signIn();
      if (idToken == null) return; // user cancelled the Google picker
      await _completeSignIn(idToken);
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _completeSignIn(String idToken) async {
    if (!mounted) return;
    try {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.blueDark, AppColors.blueMid]),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: AppColors.blueDark.withValues(alpha: 0.22), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'V-Learn',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'เตรียมสอบให้ครบทุกสนาม',
                    style: TextStyle(color: AppColors.inkFaint, fontSize: 13.5),
                  ),
                  const SizedBox(height: 44),
                  if (kIsWeb)
                    SizedBox(width: double.infinity, height: 46, child: buildGoogleSignInButton())
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isSigningIn ? null : _signIn,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.ink,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'G',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF4285F4)),
                            ),
                            const SizedBox(width: 10),
                            const Text('เข้าสู่ระบบด้วย Google', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  if (_isSigningIn) ...[
                    const SizedBox(height: 18),
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
