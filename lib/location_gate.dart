part of 'main.dart';

/// Location for Market. Asked once right after an account is made, with the
/// reason first; Market (finding sellers, buying, listing a shop or ranch)
/// does not open without it. The rest of VIMO — cows, milk, money — works
/// either way, as App Review guideline 5.1.1 requires.
class MarketLocation {
  const MarketLocation._();

  /// Location was allowed once for this account on this phone. After that
  /// Market never asks again by itself: browsers (Safari above all) forget
  /// a site's permission, and asking on every open is what people hate.
  ///
  /// Kept for the phone, not the account: at launch the account is still
  /// loading, and a per-account key read then looked like "never allowed",
  /// so Market asked again on every open.
  static bool get remembered {
    if (settingValue('locationOk', false) == true) return true;
    // Allowed before this was kept per phone (per account, or a place
    // already searched from): count it, so nobody is asked again.
    if (!Hive.isBoxOpen('settings')) return false;
    final box = Hive.box('settings');
    return box.keys.any(
      (k) =>
          k is String &&
          ((k.endsWith('_locationOk') && box.get(k) == true) ||
              k == 'marketHere' ||
              (k.startsWith('acct_') && k.endsWith('_marketHere'))),
    );
  }

  static Future<void> remember() => setSetting('locationOk', true);

  /// Whether Market may use location now. A platform without location
  /// (tests, some desktops) is not held up.
  static Future<bool> granted() async {
    if (remembered) return true;
    try {
      if (!await geo.Geolocator.isLocationServiceEnabled()) return false;
      final p = await geo.Geolocator.checkPermission();
      return p == geo.LocationPermission.always ||
          p == geo.LocationPermission.whileInUse;
    } on MissingPluginException {
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Asks the system. When the answer was "never", the only way back is the
  /// phone's Settings, so that opens instead.
  static Future<bool> request() async {
    try {
      if (!await geo.Geolocator.isLocationServiceEnabled()) {
        await geo.Geolocator.openLocationSettings();
        return await granted();
      }
      var p = await geo.Geolocator.checkPermission();
      if (p == geo.LocationPermission.denied) {
        p = await geo.Geolocator.requestPermission();
      }
      if (p == geo.LocationPermission.deniedForever) {
        await geo.Geolocator.openAppSettings();
        return await granted();
      }
      final ok =
          p == geo.LocationPermission.always ||
          p == geo.LocationPermission.whileInUse;
      if (ok) await remember();
      return ok;
    } on MissingPluginException {
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _askedKey() => 'locationAsked_$signedInUid';

  /// Only when the account was just made: explain, then let the system ask.
  /// Never on a later sign-in or app open; Market asks itself, once, if it
  /// is opened without location.
  static Future<void> askAfterSignUp(BuildContext context, User user) async {
    final made = user.metadata.creationTime;
    final fresh =
        made != null &&
        DateTime.now().difference(made) < const Duration(minutes: 10);
    if (!fresh ||
        signedInUid.isEmpty ||
        settingValue(_askedKey(), false) == true) {
      return;
    }
    await setSetting(_askedKey(), true);
    if (await granted() || !context.mounted) return;
    await showAppleSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => const _LocationPrimer(),
    );
  }

  /// Before buying or listing: true when location is on, otherwise the
  /// primer explains and asks.
  static Future<bool> require(BuildContext context) async {
    if (await granted()) return true;
    if (!context.mounted) return false;
    final ok = await showAppleSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => const _LocationPrimer(),
    );
    return ok == true;
  }
}

class _LocationPrimer extends StatefulWidget {
  const _LocationPrimer();

  @override
  State<_LocationPrimer> createState() => _LocationPrimerState();
}

class _LocationPrimerState extends State<_LocationPrimer> {
  bool _busy = false;

  Widget _point(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Ink.violetDeep, size: 22),
        const SizedBox(width: Space.s12),
        Expanded(
          child: Text(text, style: TextStyle(color: Ink.body, fontSize: 15)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s24, 0, Space.s24, Space.s24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          CupertinoIcons.location_circle_fill,
          size: 56,
          color: Ink.violetDeep,
        ),
        const SizedBox(height: Space.s12),
        Text(
          bi('Allow location for Market', 'சந்தைக்கு location அனுமதி'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -.4,
          ),
        ),
        const SizedBox(height: Space.s16),
        _point(
          CupertinoIcons.scope,
          bi(
            'Find milk sellers, shops and ranches within 2, 5 or 10 km.',
            '2, 5 அல்லது 10 கி.மீ.க்குள் பால் விற்பவர், கடை, பண்ணையைக் கண்டறிய.',
          ),
        ),
        _point(
          CupertinoIcons.bag_fill,
          bi(
            'Buy and sell safely with people near you.',
            'அருகிலுள்ளவர்களுடன் பாதுகாப்பாக வாங்க, விற்க.',
          ),
        ),
        _point(
          CupertinoIcons.lock_shield_fill,
          bi(
            'Your exact spot is never shown — only an area of about 200 m.',
            'உங்கள் சரியான இடம் காட்டப்படாது — சுமார் 200 மீ பகுதி மட்டும்.',
          ),
        ),
        const SizedBox(height: Space.s20),
        // HIG privacy.md: one button, titled Continue (not "Allow"), that
        // opens the system prompt; the choice itself is made there.
        LiquidButton(
          label: bi('Continue', 'தொடரவும்'),
          busy: _busy,
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  final ok = await MarketLocation.request();
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  if (ok) {
                    UiSound.play(UiSoundKind.success);
                  } else {
                    snack(
                      context,
                      bi(
                        'Market needs location. Turn it on in Settings when you are ready.',
                        'சந்தைக்கு location தேவை. தயாரானதும் Settings-ல் இயக்கவும்.',
                      ),
                      tone: SnackTone.error,
                      messenger: messenger,
                    );
                  }
                  Navigator.pop(context, ok);
                },
        ),
      ],
    ),
  );
}

/// Market's door: until location is allowed, Market shows why it needs it
/// and one button to allow. Checks again when the person comes back from
/// the phone's Settings.
class MarketLocationGate extends StatefulWidget {
  final Widget child;
  const MarketLocationGate({super.key, required this.child});

  @override
  State<MarketLocationGate> createState() => _MarketLocationGateState();
}

class _MarketLocationGateState extends State<MarketLocationGate>
    with WidgetsBindingObserver {
  bool? _ok;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await MarketLocation.granted();
    if (mounted && ok != _ok) setState(() => _ok = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_ok == null) return const Shell(child: SkeletonList(rows: 4));
    if (_ok!) return widget.child;
    return Shell(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Glass(
              radius: Gold.r27,
              padding: const EdgeInsets.all(Space.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.location_slash_fill,
                    size: 48,
                    color: Ink.violetDeep,
                  ),
                  const SizedBox(height: Space.s12),
                  Text(
                    bi(
                      'Market needs your location',
                      'சந்தைக்கு உங்கள் location தேவை',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Space.s8),
                  Text(
                    bi(
                      'To show sellers near you and keep buying and selling local. Your ranch, milk and money records work without it.',
                      'அருகிலுள்ள விற்பவர்களைக் காட்டவும் வாங்குதல், விற்றலை உள்ளூரில் வைக்கவும். உங்கள் பண்ணை, பால், பணக் கணக்குகள் இது இல்லாமலும் இயங்கும்.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Ink.muted, fontSize: 15),
                  ),
                  const SizedBox(height: Space.s20),
                  LiquidButton(
                    label: bi('Continue', 'தொடரவும்'),
                    icon: CupertinoIcons.location_fill,
                    onPressed: () async {
                      final ok = await MarketLocation.request();
                      if (mounted) setState(() => _ok = ok);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
