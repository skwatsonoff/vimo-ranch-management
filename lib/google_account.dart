part of 'main.dart';

/// Sign in with Google, sign up with Google, and adding Google to an account
/// that was created with email and password.
///
/// The browser (the production PWA) uses Firebase's Google pop-up and falls
/// back to a full-page redirect where pop-ups are blocked (some installed
/// iPhone web apps). Android and iOS builds use Firebase's provider flow.
/// The Google provider must be switched on in the Firebase console
/// (Authentication → Sign-in method → Google); until it is, every call
/// explains that instead of failing silently.
class GoogleAccount {
  const GoogleAccount._();

  static GoogleAuthProvider get _provider => GoogleAuthProvider()
    ..addScope('email')
    ..setCustomParameters({'prompt': 'select_account'});

  /// True when the signed-in account can already sign in with Google.
  static bool get linked =>
      firebaseReady &&
      (FirebaseAuth.instance.currentUser?.providerData.any(
            (p) => p.providerId == 'google.com',
          ) ??
          false);

  /// Signs in (or creates the account) with Google. Returns null when the
  /// browser is moving to Google's page instead (redirect fallback); the app
  /// signs in when it comes back.
  static Future<UserCredential?> signIn() async {
    final auth = FirebaseAuth.instance;
    if (!kIsWeb) return auth.signInWithProvider(_provider);
    try {
      await auth.setPersistence(Persistence.LOCAL);
    } catch (_) {
      /* Storage restrictions must not stop the sign-in itself. */
    }
    try {
      return await auth.signInWithPopup(_provider);
    } on FirebaseAuthException catch (e) {
      if (_popupUnavailable(e)) {
        await auth.signInWithRedirect(_provider);
        return null;
      }
      rethrow;
    }
  }

  /// Adds Google as a second way into the signed-in account, keeping its
  /// email and password, ranch and records exactly as they are.
  static Future<void> link() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError(ui('Please sign in again'));
    if (!kIsWeb) {
      await user.linkWithProvider(_provider);
      return;
    }
    try {
      await user.linkWithPopup(_provider);
    } on FirebaseAuthException catch (e) {
      if (_popupUnavailable(e)) {
        await user.linkWithRedirect(_provider);
        return;
      }
      rethrow;
    }
  }

  static bool _popupUnavailable(FirebaseAuthException e) => const {
    'popup-blocked',
    'operation-not-supported-in-this-environment',
    'web-storage-unsupported',
  }.contains(e.code);

  /// Plain words for what went wrong, and what to do next.
  static String friendlyError(Object error) {
    final code = error is FirebaseAuthException ? error.code : '';
    return switch (code) {
      'popup-closed-by-user' ||
      'cancelled-popup-request' ||
      'web-context-canceled' => bi(
        'Google sign-in was cancelled',
        'Google உள்நுழைவு ரத்து செய்யப்பட்டது',
      ),
      'operation-not-allowed' => bi(
        'Google sign-in is not switched on for VIMO yet. Use email and password for now.',
        'VIMO-வில் Google உள்நுழைவு இன்னும் இயக்கப்படவில்லை. இப்போது மின்னஞ்சல், கடவுச்சொல் பயன்படுத்தவும்.',
      ),
      'account-exists-with-different-credential' => bi(
        'This email already has a VIMO account. Sign in with your password, then add Google in Settings.',
        'இந்த மின்னஞ்சலுக்கு ஏற்கனவே VIMO கணக்கு உள்ளது. கடவுச்சொல்லுடன் உள்நுழைந்து, Settings-ல் Google-ஐச் சேர்க்கவும்.',
      ),
      'credential-already-in-use' || 'email-already-in-use' => bi(
        'That Google account already belongs to another VIMO account.',
        'அந்த Google கணக்கு ஏற்கனவே வேறு VIMO கணக்குடன் உள்ளது.',
      ),
      'provider-already-linked' => bi(
        'Google is already added to this account.',
        'இந்தக் கணக்கில் Google ஏற்கனவே சேர்க்கப்பட்டுள்ளது.',
      ),
      'requires-recent-login' => bi(
        'For safety, sign out and sign in again, then add Google.',
        'பாதுகாப்புக்காக வெளியேறி மீண்டும் உள்நுழைந்து, பிறகு Google-ஐச் சேர்க்கவும்.',
      ),
      'network-request-failed' => bi(
        'No network. Check your connection and try again',
        'இணையம் இல்லை. இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்',
      ),
      'unauthorized-domain' => bi(
        'Google sign-in is not allowed on this web address.',
        'இந்த இணைய முகவரியில் Google உள்நுழைவு அனுமதிக்கப்படவில்லை.',
      ),
      _ => bi(
        'Google sign-in failed. Please try again',
        'Google உள்நுழைவு தோல்வி. மீண்டும் முயற்சிக்கவும்',
      ),
    };
  }
}

/// The secondary "Continue with Google" button on sign-in and sign-up: a
/// gray capsule (the prominent one stays the email action), 44 pt or taller.
class GoogleSignInButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const GoogleSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        style: liquidActionStyle().copyWith(
          backgroundColor: WidgetStatePropertyAll(Ink.surface),
          foregroundColor: WidgetStatePropertyAll(Ink.navy),
          side: WidgetStatePropertyAll(
            BorderSide(color: Ink.separator.withValues(alpha: .6)),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(44, 50)),
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const CupertinoActivityIndicator()
            : Icon(CupertinoIcons.person_crop_circle, color: Ink.violetDeep),
        label: AppText(label),
      ),
    );
  }
}

/// A thin "or" between the email form and the Google button.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s12),
    child: Row(
      children: [
        Expanded(child: Divider(color: Ink.separator, thickness: .5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s12),
          child: AppText(
            bi('or', 'அல்லது'),
            style: TextStyle(color: Ink.muted, fontSize: 13),
          ),
        ),
        Expanded(child: Divider(color: Ink.separator, thickness: .5)),
      ],
    ),
  );
}

/// After a first Google sign-in the account still needs its VIMO details
/// (name, VIMO ID, mobile, place). This opens the sign-up form in Google
/// mode on top of whatever the app shows next.
Future<void> completeGoogleProfile(UserCredential? credential) async {
  if (credential == null) return;
  final user = credential.user;
  if (user == null) return;
  final isNew = credential.additionalUserInfo?.isNewUser ?? false;
  if (!isNew) return;
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;
  // Let the sign-in screen give way to the app first.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await navigator.push(LiquidRoute<void>(builder: (_) => const SignupScreen()));
}
