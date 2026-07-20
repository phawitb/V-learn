import 'package:google_sign_in/google_sign_in.dart';

/// Wraps `google_sign_in` for the app's Google-only login. The client id
/// below is the public OAuth client id (safe to embed in a client app) —
/// never the client secret, which this app never needs since it verifies
/// Google ID tokens server-side instead of doing an auth-code exchange.
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  static const _clientId = '777681711265-cv3elhc2hkqe8bji12cg9ijcol1l9kd5.apps.googleusercontent.com';

  Future<void>? _initFuture;

  /// `GoogleSignIn.instance` requires this to complete before any other
  /// call. Idempotent — safe to call from multiple places (both
  /// [LoginScreen.initState] and the web renderButton widget wait on it).
  Future<void> ensureInitialized() {
    return _initFuture ??= GoogleSignIn.instance.initialize(clientId: _clientId);
  }

  /// Fires on sign-in/sign-out — this is how the web flow reports
  /// completion, since the real GIS button (rendered by Google's own JS,
  /// not this app) drives the popup and can't hand back a result via a
  /// normal awaited call. See [buildGoogleSignInButton].
  Stream<GoogleSignInAuthenticationEvent> get authenticationEvents => GoogleSignIn.instance.authenticationEvents;

  String? idTokenOf(GoogleSignInAccount account) => account.authentication.idToken;

  /// Native/mobile sign-in: opens the platform's own account picker and
  /// returns the resulting ID token, or null if the user cancelled. Not
  /// used on web — see [buildGoogleSignInButton] for why.
  Future<String?> signIn() async {
    await ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      return idTokenOf(account);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  Future<void> signOut() => GoogleSignIn.instance.signOut();
}
