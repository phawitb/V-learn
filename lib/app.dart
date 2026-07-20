import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/profile_completion_screen.dart';
import 'screens/home/root_shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

class VLearnApp extends StatelessWidget {
  const VLearnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'V-Learn',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Consumer<AppState>(
        builder: (context, appState, _) {
          if (!appState.isAuthenticated) return const LoginScreen();
          if (!appState.currentUser!.profileComplete) return const ProfileCompletionScreen();
          return const RootShell();
        },
      ),
    );
  }
}
