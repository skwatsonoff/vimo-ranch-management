part of 'main.dart';

// -----------------------------------------------------------------------------
//  First launch: Welcome → Language → Purpose, then sign in or create an
//  account. Only Ranch users are asked for a Ranch ID; Vendor and Market users
//  need just their VIMO ID and can add a ranch later from Preferences.
// -----------------------------------------------------------------------------

/// Bumped whenever ranch access changes from inside the app (create, join,
/// cancel), so the access gate re-resolves without a restart.
final ranchGateRevision = ValueNotifier<int>(0);
void refreshRanchGate() => ranchGateRevision.value++;

/// Devices that already signed in before this flow existed skip it.
bool get introCompleted =>
    settingValue('introCompleted', false) == true ||
    settingText('firebaseUid', '').isNotEmpty;

/// Private account details from sign-up, kept per account on this device.
Map<String, dynamic> get accountDetails =>
    asMap(asMap(settingValue('accountProfiles', {}))[_profileKey] ?? {});
String get accountFullName => txt(accountDetails, 'name');
String get accountPhone => txt(accountDetails, 'phone');
String get accountPlace => txt(accountDetails, 'place');

Future<void> saveAccountDetails(Map<String, dynamic> details) =>
    setSetting('accountProfiles', {
      ...asMap(settingValue('accountProfiles', {})),
      _profileKey: {...accountDetails, ...details},
    });

String normalizePhone(String value) =>
    value.replaceAll(RegExp(r'[\s()-]'), '').trim();
bool validPhone(String value) =>
    RegExp(r'^[+]?[0-9]{10,13}$').hasMatch(normalizePhone(value));

class IntroFlow extends StatefulWidget {
  const IntroFlow({super.key});
  @override
  State<IntroFlow> createState() => _IntroFlowState();
}

class _IntroFlowState extends State<IntroFlow> {
  int _step = 0;
  late String _purpose = settingText('introPurpose', 'Ranch');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _browserRuntime.dismissBootSplash(),
    );
  }

  Future<void> _finish() async {
    await setSetting('introPurpose', _purpose);
    await setSetting('introCompleted', true);
  }

  Widget _stepBody() => switch (_step) {
    0 => _Welcome(onNext: () => setState(() => _step = 1)),
    1 => _LanguageStep(onNext: () => setState(() => _step = 2)),
    _ => _PurposeStep(
      value: _purpose,
      onChanged: (v) => setState(() => _purpose = v),
      onNext: _finish,
    ),
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _step > 0) setState(() => _step--);
    },
    child: Scaffold(
      backgroundColor: Ink.canvasTop,
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: .30,
              child: Image(
                image: heroArtImage,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Ink.canvasTop.withValues(alpha: .20),
                    Ink.canvasTop.withValues(alpha: .86),
                    Ink.canvasTop,
                  ],
                  stops: const [0, Gold.minor, Gold.invPhi],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Gold.contentWidth),
                child: Column(
                  children: [
                    SizedBox(
                      height: Gold.s55,
                      child: Row(
                        children: [
                          if (_step > 0)
                            IconButton(
                              tooltip: bi('Back', 'பின் செல்'),
                              icon: const Icon(CupertinoIcons.chevron_back),
                              onPressed: () => setState(() => _step--),
                            ),
                          const Spacer(),
                          _Dots(index: _step, count: 3),
                          const Spacer(),
                          if (_step > 0) const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: Gold.slow,
                        switchInCurve: Gold.ease,
                        switchOutCurve: Gold.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(.06, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: _stepBody(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Dots extends StatelessWidget {
  final int index, count;
  const _Dots({required this.index, required this.count});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: Gold.base,
          curve: Gold.ease,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == index ? 21 : 7,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: i == index
                ? Ink.violetDeep
                : Ink.faint.withValues(alpha: .35),
          ),
        ),
    ],
  );
}

class _StepFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final String action;
  final VoidCallback onNext;
  const _StepFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.action,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(Gold.s21, Gold.s13, Gold.s21, Gold.s34),
    children: [
      Text(
        title,
        style: const TextStyle(
          color: Ink.navy,
          fontSize: Gold.t34,
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
          height: 1.15,
        ),
      ),
      const SizedBox(height: Gold.s8),
      Text(
        subtitle,
        style: const TextStyle(
          color: Ink.muted,
          fontSize: Gold.t16,
          height: 1.4,
        ),
      ),
      const SizedBox(height: Gold.s34),
      child,
      const SizedBox(height: Gold.s34),
      LiquidButton(label: action, onPressed: onNext),
    ],
  );
}

class _Welcome extends StatelessWidget {
  final VoidCallback onNext;
  const _Welcome({required this.onNext});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gold.s21, 0, Gold.s21, Gold.s34),
    child: Column(
      children: [
        const Spacer(flex: 3),
        const Reveal(index: 0, child: BrandMark(size: Gold.s89 + Gold.s34)),
        const SizedBox(height: Gold.s34),
        const Reveal(
          index: 1,
          child: Text(
            'Welcome to VIMO',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Ink.navy,
              fontSize: Gold.t34,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
            ),
          ),
        ),
        const SizedBox(height: Gold.s8),
        const Reveal(
          index: 2,
          child: Text(
            'VIMO-க்கு வரவேற்கிறோம்',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Ink.violetDeep,
              fontSize: Gold.t21,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: Gold.s13),
        const Reveal(
          index: 3,
          child: Text(
            'Ranch · Vendor · Market',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Ink.muted,
              fontSize: Gold.t16,
              fontWeight: FontWeight.w600,
              letterSpacing: .4,
            ),
          ),
        ),
        const Spacer(flex: 5),
        Reveal(
          index: 4,
          child: LiquidButton(
            label: 'Get started · தொடங்கலாம்',
            onPressed: onNext,
          ),
        ),
      ],
    ),
  );
}

class _LanguageStep extends StatelessWidget {
  final VoidCallback onNext;
  const _LanguageStep({required this.onNext});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Box<dynamic>>(
    valueListenable: Hive.box(
      'settings',
    ).listenable(keys: const ['languageMode']),
    builder: (context, _, _) {
      final tamil = tamilUi;
      return _StepFrame(
        title: bi('Choose your language', 'உங்கள் மொழியைத் தேர்வு செய்யுங்கள்'),
        subtitle: bi(
          'You can change it anytime in Settings.',
          'செட்டிங்ஸில் எப்போது வேண்டுமானாலும் மாற்றலாம்.',
        ),
        action: bi('Continue', 'தொடரவும்'),
        onNext: onNext,
        child: Column(
          children: [
            _ChoiceCard(
              selected: !tamil,
              title: 'English',
              subtitle: 'Use VIMO in English',
              leading: const Text(
                'Aa',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              onTap: () => setSetting('languageMode', 'English'),
            ),
            const SizedBox(height: Gold.s13),
            _ChoiceCard(
              selected: tamil,
              title: 'தமிழ்',
              subtitle: 'VIMO-வைத் தமிழில் பயன்படுத்துங்கள்',
              leading: const Text(
                'அ',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              onTap: () => setSetting('languageMode', 'Tamil'),
            ),
          ],
        ),
      );
    },
  );
}

class _PurposeStep extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  const _PurposeStep({
    required this.value,
    required this.onChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => _StepFrame(
    title: bi(
      'What will you use VIMO for?',
      'VIMO-வை எதற்காகப் பயன்படுத்தப் போகிறீர்கள்?',
    ),
    subtitle: bi(
      'Pick one to begin. You can switch on the others later.',
      'தொடங்க ஒன்றைத் தேர்வு செய்யுங்கள். மற்றவற்றைப் பின்னர் இயக்கலாம்.',
    ),
    action: bi('Continue', 'தொடரவும்'),
    onNext: onNext,
    child: Column(
      children: [
        for (final kind in workspaceKinds) ...[
          _ChoiceCard(
            selected: value == kind,
            title: workspaceTitle(kind),
            subtitle: workspaceSubtitle(kind),
            leading: workspaceIcon(
              kind,
              color: value == kind ? Colors.white : Ink.violetDeep,
              size: 22,
            ),
            onTap: () => onChanged(kind),
          ),
          const SizedBox(height: Gold.s13),
        ],
      ],
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  final bool selected;
  final String title, subtitle;
  final Widget leading;
  final VoidCallback onTap;
  const _ChoiceCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Pressable(
      radius: Gold.r27,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Gold.base,
        curve: Gold.ease,
        padding: const EdgeInsets.all(Gold.s16),
        decoration: ShapeDecoration(
          shape: SquircleBorder(
            radius: Gold.r27,
            side: BorderSide(
              color: selected ? Ink.violetDeep : Colors.white,
              width: 1.2,
            ),
          ),
          color: selected
              ? Ink.violetDeep
              : Colors.white.withValues(alpha: .66),
          shadows: [
            BoxShadow(
              color: Ink.violetDeep.withValues(alpha: selected ? .22 : .06),
              blurRadius: Gold.s21,
              offset: const Offset(0, Gold.s8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: Gold.s55 - Gold.s8,
              height: Gold.s55 - Gold.s8,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                shape: const SquircleBorder(radius: Gold.r13),
                color: selected
                    ? Colors.white.withValues(alpha: .18)
                    : Ink.lavender,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: selected ? Colors.white : Ink.violetDeep,
                ),
                child: leading,
              ),
            ),
            const SizedBox(width: Gold.s13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? Colors.white : Ink.navy,
                      fontSize: Gold.t16 + 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Gold.s2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: selected
                          ? Colors.white.withValues(alpha: .84)
                          : Ink.muted,
                      fontSize: Gold.t13,
                      height: 1.35,
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

/// Asks a user who just switched Ranch on how they want to start it.
Future<void> promptRanchSetup(BuildContext context) async {
  final choice = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gold.s21, 0, Gold.s21, Gold.s21),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              bi('Set up your ranch', 'உங்கள் தொழுவத்தை அமைக்கவும்'),
              style: const TextStyle(
                color: Ink.navy,
                fontSize: Gold.t21,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Gold.s5),
            Text(
              bi(
                'Create a new ranch or join one with its Ranch ID.',
                'புதிய தொழுவத்தை உருவாக்கவும் அல்லது Ranch ID மூலம் இருக்கும் தொழுவத்தில் சேரவும்.',
              ),
              style: const TextStyle(color: Ink.muted, height: 1.4),
            ),
            const SizedBox(height: Gold.s21),
            LiquidButton(
              label: bi('Create a ranch', 'புதிய தொழுவம் உருவாக்கு'),
              icon: Icons.add_home_work_rounded,
              onPressed: () => Navigator.pop(sheet, 0),
            ),
            const SizedBox(height: Gold.s13),
            GhostButton(
              label: bi('Join with Ranch ID', 'Ranch ID மூலம் சேர்'),
              icon: Icons.key_rounded,
              onPressed: () => Navigator.pop(sheet, 1),
            ),
            const SizedBox(height: Gold.s8),
            TextButton(
              onPressed: () => Navigator.pop(sheet),
              child: Text(bi('Later', 'பிறகு')),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  await push(
    context,
    RanchOnboardingScreen(pageMode: true, initialMode: choice),
  );
}

/// Shown in the Ranch tab until the account belongs to a ranch.
class RanchSetupPrompt extends StatelessWidget {
  const RanchSetupPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final pending = pendingRanchId();
    if (pending.isNotEmpty) {
      return WaitingApprovalScreen(ranch: pending, onChanged: refreshRanchGate);
    }
    return Shell(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Gold.contentWidth),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(Gold.s21),
            children: [
              Glass(
                radius: Gold.r34,
                padding: const EdgeInsets.all(Gold.s27),
                elevation: 1.1,
                child: Column(
                  children: [
                    const CowMark(size: Gold.s89),
                    const SizedBox(height: Gold.s16),
                    Text(
                      bi('Set up your ranch', 'உங்கள் தொழுவத்தை அமைக்கவும்'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Ink.navy,
                        fontSize: Gold.t21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Gold.s8),
                    Text(
                      bi(
                        'Create a new ranch, or enter an existing Ranch ID to join it.',
                        'புதிய தொழுவத்தை உருவாக்குங்கள், அல்லது இருக்கும் Ranch ID-ஐ உள்ளிட்டுச் சேருங்கள்.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Ink.muted, height: 1.45),
                    ),
                    const SizedBox(height: Gold.s21),
                    LiquidButton(
                      label: bi('Create a ranch', 'புதிய தொழுவம் உருவாக்கு'),
                      icon: Icons.add_home_work_rounded,
                      onPressed: () => push(
                        context,
                        const RanchOnboardingScreen(pageMode: true),
                      ),
                    ),
                    const SizedBox(height: Gold.s13),
                    GhostButton(
                      label: bi('Join with Ranch ID', 'Ranch ID மூலம் சேர்'),
                      icon: Icons.key_rounded,
                      onPressed: () => push(
                        context,
                        const RanchOnboardingScreen(
                          pageMode: true,
                          initialMode: 1,
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

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _place = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _photo = '';
  bool _busy = false;
  bool _picking = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _username,
      _phone,
      _place,
      _email,
      _password,
      _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_picking || _busy) return;
    setState(() => _picking = true);
    try {
      final selected = await pickImageDataUrl(social: true);
      if (selected == null) return;
      final photo = await compressSocialPhoto(selected);
      if (photo == null) {
        throw StateError(
          bi('Could not load this photo.', 'புகைப்படத்தை ஏற்ற முடியவில்லை.'),
        );
      }
      if (mounted) setState(() => _photo = photo);
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _createAccount() async {
    final name = _fullName.text.trim();
    final phone = normalizePhone(_phone.text);
    final place = _place.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (name.isEmpty) {
      snack(
        context,
        bi('Enter your full name', 'உங்கள் முழுப் பெயரை எழுதவும்'),
      );
      return;
    }
    if (!validUsername(normalizeUsername(_username.text))) {
      snack(
        context,
        bi('Choose a valid VIMO ID', 'சரியான VIMO ID-ஐத் தேர்வு செய்யவும்'),
      );
      return;
    }
    if (!validPhone(phone)) {
      snack(
        context,
        bi('Enter a valid mobile number', 'சரியான மொபைல் எண்ணை எழுதவும்'),
      );
      return;
    }
    if (place.isEmpty) {
      snack(
        context,
        bi('Enter your town or district', 'உங்கள் ஊர் / மாவட்டத்தை எழுதவும்'),
      );
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      snack(context, 'Please enter a valid email');
      return;
    }
    if (password.length < 6) {
      snack(context, 'Password needs at least 6 characters');
      return;
    }
    if (password != _confirm.text) {
      snack(context, 'Passwords do not match');
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await UsernameService.available(_username.text)) {
        throw StateError(
          bi('VIMO ID unavailable', 'இந்த VIMO ID கிடைக்கவில்லை'),
        );
      }
      if (kIsWeb) {
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        } catch (_) {
          /* Storage restrictions must not disable Firebase itself. */
        }
      }
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      final user = FirebaseAuth.instance.currentUser!;
      try {
        await user.updateDisplayName(name);
      } catch (_) {
        /* The profile document below also carries the name. */
      }
      await saveAccountDetails({'name': name, 'phone': phone, 'place': place});
      await setSetting('currentUser', name);
      await UsernameService.save(_username.text);
      final db = FirebaseFirestore.instance;
      await Future.wait([
        db.collection('profiles').doc(user.uid).set({
          'username': accountUsername,
          'displayName': name,
          'displayNameFold': name.toLowerCase(),
          'place': place,
          'photo': _photo,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
        // The mobile number stays private in the account document.
        db.collection('users').doc(user.uid).set({
          'fullName': name,
          'phone': phone,
          'place': place,
          'displayName': name,
        }, SetOptions(merge: true)),
      ]).timeout(const Duration(seconds: 20));
      if (mounted) {
        snack(context, bi('Account created', 'கணக்கு உருவாக்கப்பட்டது'));
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'email-already-in-use' =>
          'That email already has an account. Please sign in',
        'invalid-email' => 'That email address does not look right',
        'weak-password' => 'Please choose a stronger password',
        'network-request-failed' => 'No network. Check your connection',
        _ => error.message ?? 'Could not create the account',
      };
      snack(context, message);
    } catch (error) {
      if (mounted) snack(context, accountError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = Gold.s89 + Gold.s13;
    return FormPage(
      title: 'Create Account',
      children: [
        Center(
          child: Semantics(
            button: true,
            label: bi('Add profile photo', 'ப்ரொஃபைல் படம் சேர்'),
            child: Pressable(
              radius: size,
              onTap: _pickPhoto,
              child: SizedBox(
                width: size + Gold.s5,
                height: size + Gold.s5,
                child: Stack(
                  children: [
                    Center(
                      child: _photo.isEmpty
                          ? Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Ink.lavender,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                CupertinoIcons.person_fill,
                                color: Ink.violet,
                                size: Gold.s55,
                              ),
                            )
                          : profileAvatar(_photo, radius: size / 2),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: Gold.s34 + Gold.s5,
                        height: Gold.s34 + Gold.s5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Ink.violetDeep,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: _picking
                            ? const Padding(
                                padding: EdgeInsets.all(Gold.s8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                CupertinoIcons.camera_fill,
                                color: Colors.white,
                                size: Gold.t16,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gold.s8),
        Text(
          bi('Profile photo (optional)', 'ப்ரொஃபைல் படம் (விருப்பம்)'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Ink.muted, fontSize: Gold.t13),
        ),
        const SizedBox(height: Gold.s21),
        TextField(
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          decoration: fieldStyle(
            bi('Full name', 'முழுப் பெயர்'),
            icon: Icons.person_outline_rounded,
          ),
        ),
        const SizedBox(height: Gold.s13),
        UsernameField(controller: _username),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: fieldStyle(
            bi('Mobile number', 'மொபைல் எண்'),
            icon: Icons.phone_iphone_rounded,
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _place,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: fieldStyle(
            bi('Town / District', 'ஊர் / மாவட்டம்'),
            icon: Icons.place_outlined,
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.newUsername],
          textInputAction: TextInputAction.next,
          decoration: fieldStyle('Email', icon: Icons.mail_outline_rounded),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          decoration: fieldStyle(
            'Create Password',
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _confirm,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _createAccount(),
          decoration: fieldStyle(
            'Confirm Password',
            icon: Icons.verified_user_outlined,
          ),
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: 'Create Account',
          icon: Icons.person_add_alt_1_rounded,
          busy: _busy,
          onPressed: _createAccount,
        ),
      ],
    );
  }
}
