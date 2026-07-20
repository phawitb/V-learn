import 'package:flutter/widgets.dart';

import 'google_sign_in_button_stub.dart'
    if (dart.library.js_interop) 'google_sign_in_button_web.dart' as impl;

/// Cross-platform entry point: renders Google's real GIS button on web,
/// nothing on native platforms (which use [GoogleAuthService.signIn] via a
/// normal app-drawn button instead — see [LoginScreen]).
Widget buildGoogleSignInButton() => impl.buildGoogleSignInButton();
