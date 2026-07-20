import 'package:google_sign_in/google_sign_in.dart';

/// Wraps `google_sign_in` for the app's Google-only login. The client id
/// below is the public OAuth client id (safe to embed in a client app) —
/// never the client secret, which this app never needs since it verifies
/// Google ID tokens server-side instead of doing an auth-code exchange.
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  static const _clientId = '842886803912-qp05cvv2c4ekpflbha8sl0vp41f89b66.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: _clientId,
    scopes: const ['email', 'profile'],
  );

  /// Returns the Google ID token to send to the backend, or null if the
  /// user cancelled the sign-in flow.
  Future<String?> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.idToken;
  }

  Future<void> signOut() => _googleSignIn.signOut();
}
