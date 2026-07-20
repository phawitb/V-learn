import 'package:flutter/material.dart';
import 'package:google_identity_services_web/id.dart' as gis;

import '../services/google_auth_service.dart';

/// The real Google Identity Services button, rendered by Google's own JS
/// into the page. Required on web: `GoogleSignIn.authenticate()` only drives
/// an OAuth popup there (easily blocked as a non-user-gesture popup, and
/// discouraged by the plugin itself) — a GIS button is the officially
/// supported way to authenticate and get an idToken back reliably.
///
/// This renders the button directly against `google_identity_services_web`
/// (rather than going through `google_sign_in_web`'s own `renderButton()`)
/// because that package's `FlexHtmlElementView` throws at runtime on this
/// Flutter version — its `getViewById(viewId) as web.Element` cast fails.
/// `HtmlElementView.fromTagName` hands back the created element directly,
/// sidestepping that cast entirely. The click still flows through the same
/// global `google.accounts.id` client that
/// `GoogleAuthService.ensureInitialized` sets up, so
/// `GoogleAuthService.authenticationEvents` still fires normally.
Widget buildGoogleSignInButton() => const _GsiButton();

class _GsiButton extends StatelessWidget {
  const _GsiButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        height: 46,
        child: FutureBuilder<void>(
          // Must not create the platform view (and call gis.id.renderButton)
          // until the GIS SDK script has actually finished loading — doing
          // so earlier means `gis.id` isn't ready and the button never
          // appears, with `onElementCreated` never retried.
          future: GoogleAuthService.instance.ensureInitialized(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            return HtmlElementView.fromTagName(
              tagName: 'div',
              onElementCreated: (Object element) {
                gis.id.renderButton(
                  element,
                  gis.GsiButtonConfiguration(
                    theme: gis.ButtonTheme.outline,
                    size: gis.ButtonSize.large,
                    shape: gis.ButtonShape.pill,
                    text: gis.ButtonText.signin_with,
                    logo_alignment: gis.ButtonLogoAlignment.center,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
