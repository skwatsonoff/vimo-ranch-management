part of 'main.dart';

// -----------------------------------------------------------------------------
//  Route maps
//
//  A vendor walks or rides the milk round once while the phone records the
//  path. Each home is marked on the way, and notes (text, voice or a photo)
//  can be pinned to a home or anywhere on the path between two homes. A saved
//  route starts a normal ride in map order, or is lent for a few days to a
//  person through VIMO chat. The lent copy carries only name, place, litres
//  and, when chosen, the balance to collect; never history, contact or photo.
//
//  Routes stay on this device (the vendor_routes box is not a ranch backup).
//  A lent route lives in route_shares/{id} so the owner can extend or stop it.
// -----------------------------------------------------------------------------

/// Set by a route's "Start route"; the ride screen starts it in map order.
final vendorRouteRequest = ValueNotifier<String?>(null);

const ll.LatLng vimoDefaultCenter = ll.LatLng(11.1271, 78.6569);

/// A point as stored on the phone ([lat, lng]) or in Firestore, which has no
/// nested arrays ({lat, lng}).
ll.LatLng? routePoint(dynamic lat, [dynamic lng]) {
  if (lat is List && lat.length >= 2) return routePoint(lat[0], lat[1]);
  if (lat is Map) return routePoint(lat['lat'], lat['lng']);
  if (lat is! num || lng is! num) return null;
  final a = lat.toDouble(), b = lng.toDouble();
  if (!a.isFinite || !b.isFinite || a.abs() > 90 || b.abs() > 180) return null;
  return ll.LatLng(a, b);
}

ll.LatLng? personPoint(Map<String, dynamic> p) =>
    routePoint(p['lat'], p['lng']);

List<double> _pair(ll.LatLng p) => [
  double.parse(p.latitude.toStringAsFixed(6)),
  double.parse(p.longitude.toStringAsFixed(6)),
];

List<ll.LatLng> routePath(Map<String, dynamic> route) => [
  for (final p in (route['path'] as List?) ?? const []) ?routePoint(p),
];

List<Map<String, dynamic>> routeStops(Map<String, dynamic> route) =>
    ((route['stops'] as List?) ?? const []).map(asMap).toList();

List<Map<String, dynamic>> routeNotes(Map<String, dynamic> route) =>
    ((route['notes'] as List?) ?? const []).map(asMap).toList();

/// Every point worth showing: the path, homes and notes.
List<ll.LatLng> routeExtent(Map<String, dynamic> route) => [
  ...routePath(route),
  for (final s in routeStops(route)) ?personPoint(s),
  for (final n in routeNotes(route)) ?personPoint(n),
];

double routeDistanceMeters(List<ll.LatLng> path) {
  const distance = ll.Distance();
  var total = 0.0;
  for (var i = 1; i < path.length; i++) {
    total += distance.as(ll.LengthUnit.Meter, path[i - 1], path[i]);
  }
  return total;
}

String routeDistanceLabel(double meters) => meters >= 1000
    ? '${(meters / 1000).toStringAsFixed(1)} km'
    : '${meters.round()} m';

String routeTimeLeft(DateTime until, {DateTime? now}) {
  final left = until.difference(now ?? DateTime.now());
  if (left.inSeconds <= 0) return bi('Ended', 'முடிந்தது');
  final days = left.inDays, hours = left.inHours % 24;
  final minutes = left.inMinutes % 60;
  if (days > 0) {
    return bi('${days}d ${hours}h left', '$days நா $hours ம மீதம்');
  }
  if (left.inHours > 0) {
    return bi('${hours}h ${minutes}m left', '$hours ம $minutes நி மீதம்');
  }
  // Under a minute still reads as one minute, never "0m".
  final last = math.max(1, minutes);
  return bi('${last}m left', '$last நி மீதம்');
}

DateTime? _stamp(dynamic value) => value is Timestamp
    ? value.toDate()
    : value is String
    ? DateTime.tryParse(value)
    : null;

class VendorRoutes {
  const VendorRoutes._();
  static const boxName = 'vendor_routes';

  static Future<Box> open() async =>
      Hive.isBoxOpen(boxName) ? Hive.box(boxName) : await Hive.openBox(boxName);

  /// Own routes belong to the account and ranch workspace that made them.
  static String get scope =>
      '${settingText('firebaseUid', 'local')}:${ranchId()}';
  static String get receivedScope => 'recv:$signedInUid';

  static List<Map<String, dynamic>> _all(Box box) => [
    for (final e in box.toMap().entries)
      if (e.value is Map) {...asMap(e.value), '_key': e.key},
  ];

  static List<Map<String, dynamic>> own(Box box) =>
      _all(
          box,
        ).where((r) => r['kind'] != 'received' && r['scope'] == scope).toList()
        ..sort((a, b) => txt(b, 'updatedAt').compareTo(txt(a, 'updatedAt')));

  static List<Map<String, dynamic>> received(Box box) =>
      _all(box)
          .where(
            (r) =>
                r['kind'] == 'received' &&
                signedInUid.isNotEmpty &&
                r['scope'] == receivedScope,
          )
          .toList()
        ..sort((a, b) => txt(b, 'receivedAt').compareTo(txt(a, 'receivedAt')));

  static Map<String, dynamic>? byId(String id) {
    if (!Hive.isBoxOpen(boxName)) return null;
    final value = Hive.box(boxName).get(id);
    return value is Map ? asMap(value) : null;
  }

  static Future<void> save(Map<String, dynamic> route) async {
    final box = await open();
    final data = {...route}..remove('_key');
    await box.put(txt(data, 'id'), data);
    await box.flush();
  }

  static Future<void> delete(String id) async {
    final box = await open();
    await box.delete(id);
    await box.flush();
  }
}

/// Location permission and a single fix, with plain explanations.
class VendorLocation {
  const VendorLocation._();

  static Future<bool> ready(BuildContext context) async {
    try {
      if (!await geo.Geolocator.isLocationServiceEnabled()) {
        if (context.mounted) {
          snack(
            context,
            bi(
              'Turn on location to use the map.',
              'வரைபடத்திற்கு location-ஐ இயக்கவும்.',
            ),
          );
        }
        return false;
      }
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        if (context.mounted) {
          snack(
            context,
            bi(
              'Location permission is needed for the map.',
              'வரைபடத்திற்கு location அனுமதி தேவை.',
            ),
          );
        }
        return false;
      }
      return true;
    } catch (_) {
      if (context.mounted) {
        snack(
          context,
          bi(
            'Location is not available here.',
            'இங்கு location கிடைக்கவில்லை.',
          ),
        );
      }
      return false;
    }
  }

  static Future<ll.LatLng?> current(BuildContext context) async {
    if (!await ready(context)) return null;
    try {
      final p = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return ll.LatLng(p.latitude, p.longitude);
    } catch (_) {
      if (context.mounted) {
        snack(
          context,
          bi(
            'Could not find your location. Try again outside.',
            'உங்கள் இடத்தைக் கண்டறிய முடியவில்லை. வெளியே சென்று மீண்டும் முயற்சிக்கவும்.',
          ),
        );
      }
      return null;
    }
  }
}

// -----------------------------------------------------------------------------
//  Map building blocks
// -----------------------------------------------------------------------------

class VimoMap extends StatelessWidget {
  final fm.MapController? controller;
  final ll.LatLng? center;
  final double zoom;
  final List<ll.LatLng> fit;
  final List<Widget> layers;
  final bool interactive;
  final void Function(ll.LatLng point)? onTap, onLongPress;
  final fm.PositionCallback? onMove;
  final VoidCallback? onReady;
  const VimoMap({
    super.key,
    this.controller,
    this.center,
    this.zoom = 16,
    this.fit = const [],
    this.layers = const [],
    this.interactive = true,
    this.onTap,
    this.onLongPress,
    this.onMove,
    this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    final points = fit;
    final fitCamera = center == null && points.length >= 2
        ? fm.CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.all(48),
            maxZoom: 18,
          )
        : null;
    return fm.FlutterMap(
      mapController: controller,
      options: fm.MapOptions(
        initialCenter:
            center ?? (points.isNotEmpty ? points.first : vimoDefaultCenter),
        initialZoom: center != null
            ? zoom
            : points.isEmpty
            ? 7
            : 17,
        initialCameraFit: fitCamera,
        minZoom: 3,
        maxZoom: 19,
        backgroundColor: const Color(0xFFE8ECF4),
        interactionOptions: fm.InteractionOptions(
          flags: interactive
              ? fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate
              : fm.InteractiveFlag.none,
        ),
        onTap: onTap == null ? null : (_, p) => onTap!(p),
        onLongPress: onLongPress == null ? null : (_, p) => onLongPress!(p),
        onPositionChanged: onMove,
        onMapReady: onReady,
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.ranch_management',
          maxNativeZoom: 19,
        ),
        ...layers,
        const _MapCredit(),
      ],
    );
  }
}

class _MapCredit extends StatelessWidget {
  const _MapCredit();
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomRight,
    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '© OpenStreetMap',
        style: TextStyle(fontSize: 9.5, color: Ink.muted),
      ),
    ),
  );
}

enum StopState { pending, current, done, skipped }

/// Path, notes, homes and "me" as map layers.
List<Widget> routeLayers(
  Map<String, dynamic> route, {
  Map<String, StopState> states = const {},
  ll.LatLng? me,
  void Function(Map<String, dynamic> stop)? onStop,
  void Function(Map<String, dynamic> note)? onNote,
}) {
  final path = routePath(route);
  final stops = routeStops(route);
  final notes = routeNotes(route);
  return [
    if (path.length >= 2)
      fm.PolylineLayer(
        polylines: [
          fm.Polyline(
            points: path,
            strokeWidth: 5.5,
            color: Ink.violet,
            borderStrokeWidth: 2.5,
            borderColor: Colors.white.withValues(alpha: .92),
          ),
        ],
      ),
    fm.MarkerLayer(
      markers: [
        for (final n in notes)
          if (personPoint(n) case final point?)
            fm.Marker(
              point: point,
              width: 34,
              height: 34,
              child: _NotePin(
                note: n,
                onTap: onNote == null ? null : () => onNote(n),
              ),
            ),
        for (final (i, s) in stops.indexed)
          if (personPoint(s) case final point?)
            fm.Marker(
              point: point,
              width: 52,
              height: 52,
              child: _HomePin(
                number: i + 1,
                label: txt(s, 'name'),
                state: states[txt(s, 'id')] ?? StopState.pending,
                onTap: onStop == null ? null : () => onStop(s),
              ),
            ),
        if (me != null)
          fm.Marker(point: me, width: 30, height: 30, child: const _MePin()),
      ],
    ),
  ];
}

class _HomePin extends StatelessWidget {
  final int number;
  final String label;
  final StopState state;
  final VoidCallback? onTap;
  const _HomePin({
    required this.number,
    required this.label,
    required this.state,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final current = state == StopState.current;
    final colors = switch (state) {
      StopState.done => const [Color(0xFF52C483), Ink.green],
      StopState.skipped => const [Color(0xFFFF8793), Ink.red],
      StopState.current => const [Ink.violet, Ink.violetDeep],
      StopState.pending => const [Color(0xFF9D86F0), Color(0xFF7A62D8)],
    };
    final size = current ? 44.0 : 34.0;
    return Semantics(
      button: onTap != null,
      label: '$number $label',
      child: GestureDetector(
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Gold.base,
            curve: Gold.ease,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: colors.last.withValues(alpha: current ? .5 : .32),
                  blurRadius: current ? 16 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: state == StopState.done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : state == StopState.skipped
                ? const Icon(
                    CupertinoIcons.forward_fill,
                    color: Colors.white,
                    size: 14,
                  )
                : Text(
                    '$number',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: current ? 17 : 14,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _NotePin extends StatelessWidget {
  final Map<String, dynamic> note;
  final VoidCallback? onTap;
  const _NotePin({required this.note, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Ink.amber, width: 2),
        boxShadow: [
          BoxShadow(
            color: Ink.amber.withValues(alpha: .35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(routeNoteIcon(note), size: 16, color: Ink.amberText),
    ),
  );
}

IconData routeNoteIcon(Map<String, dynamic> note) =>
    txt(note, 'voice').isNotEmpty
    ? CupertinoIcons.mic_fill
    : txt(note, 'photo').isNotEmpty
    ? CupertinoIcons.photo_fill
    : CupertinoIcons.text_bubble_fill;

class _MePin extends StatelessWidget {
  const _MePin();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Ink.blue,
        border: Border.all(color: Colors.white, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: Ink.blue.withValues(alpha: .35),
            blurRadius: 14,
            spreadRadius: 4,
          ),
        ],
      ),
    ),
  );
}

/// A glass circle for floating map controls.
class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = Ink.violetDeep,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox.square(
      dimension: 48,
      child: Glass(
        radius: 24,
        opacity: .82,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Center(
          child: Icon(icon, color: onTap == null ? Ink.faint : color, size: 22),
        ),
      ),
    ),
  );
}

/// Rebuilds every 30 seconds so "time left" labels stay current.
class _Tick extends StatefulWidget {
  final WidgetBuilder builder;
  const _Tick({required this.builder});
  @override
  State<_Tick> createState() => _TickState();
}

class _TickState extends State<_Tick> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

// -----------------------------------------------------------------------------
//  Person location
// -----------------------------------------------------------------------------

/// Location row for the person form: a small map with the home pinned.
class VendorLocationField extends StatelessWidget {
  final ll.LatLng? value;
  final String name;
  final ValueChanged<ll.LatLng?> onChanged;
  const VendorLocationField({
    super.key,
    required this.value,
    required this.name,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await push<ll.LatLng>(
      context,
      LocationPickerScreen(initial: value, title: name),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final point = value;
    return Glass(
      radius: 24,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (point != null)
            ClipPath(
              clipper: const SquircleClipper(18),
              child: SizedBox(
                height: 144,
                child: IgnorePointer(
                  child: VimoMap(
                    key: ValueKey('${point.latitude},${point.longitude}'),
                    center: point,
                    zoom: 16.5,
                    interactive: false,
                    layers: [
                      fm.MarkerLayer(
                        markers: [
                          fm.Marker(
                            point: point,
                            width: 44,
                            height: 44,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              CupertinoIcons.house_fill,
                              color: Ink.violetDeep,
                              size: 34,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.map_pin_ellipse,
                  color: Ink.violetDeep,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    point == null
                        ? bi(
                            'Home location · optional',
                            'வீட்டு இடம் · விருப்பம்',
                          )
                        : bi(
                            'Home location saved',
                            'வீட்டு இடம் சேமிக்கப்பட்டது',
                          ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Ink.navy,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Actions sit on their own line so long labels and large text
          // never squeeze the title.
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              if (point != null)
                TextButton.icon(
                  onPressed: () => onChanged(null),
                  icon: const Icon(CupertinoIcons.trash, size: 17),
                  label: Text(bi('Remove', 'நீக்கு')),
                  style: TextButton.styleFrom(foregroundColor: Ink.redText),
                ),
              TextButton.icon(
                onPressed: () => _pick(context),
                icon: const Icon(CupertinoIcons.map, size: 17),
                label: Text(
                  point == null
                      ? bi('Set on map', 'வரைபடத்தில் அமை')
                      : bi('Change', 'மாற்று'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Move the map under the pin, or use the phone's location.
class LocationPickerScreen extends StatefulWidget {
  final ll.LatLng? initial;
  final String title;
  const LocationPickerScreen({super.key, this.initial, this.title = ''});
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = fm.MapController();
  late ll.LatLng _center = widget.initial ?? vimoDefaultCenter;
  bool _locating = false, _moving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    final here = await VendorLocation.current(context);
    if (!mounted) return;
    setState(() => _locating = false);
    if (here != null) {
      _map.move(here, 18);
      setState(() => _center = here);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      title: Text(
        widget.title.isEmpty
            ? bi('Home location', 'வீட்டு இடம்')
            : widget.title,
      ),
    ),
    body: Stack(
      children: [
        Positioned.fill(
          child: VimoMap(
            controller: _map,
            center: _center,
            zoom: widget.initial == null ? 7 : 18,
            onTap: (p) => _map.move(p, _map.camera.zoom),
            onMove: (camera, gesture) {
              _center = camera.center;
              if (gesture != _moving) setState(() => _moving = gesture);
            },
          ),
        ),
        // The pin lifts while the map moves, like Apple Maps.
        IgnorePointer(
          child: Center(
            child: AnimatedSlide(
              duration: Gold.fast,
              curve: Gold.ease,
              offset: Offset(0, _moving ? -.72 : -.5),
              child: const Icon(
                CupertinoIcons.house_alt_fill,
                size: 44,
                color: Ink.violetDeep,
                shadows: [Shadow(color: Color(0x55000000), blurRadius: 12)],
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 132,
          child: SafeArea(
            child: _MapButton(
              icon: _locating
                  ? CupertinoIcons.hourglass
                  : CupertinoIcons.location_fill,
              tooltip: bi('My location', 'என் இடம்'),
              onTap: _locating ? null : _locate,
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: Glass(
              radius: 28,
              opacity: .86,
              padding: const EdgeInsets.all(13),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bi(
                      'Move the map so the house sits on the home.',
                      'வீட்டின் மேல் குறி வரும்படி வரைபடத்தை நகர்த்தவும்.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Ink.muted),
                  ),
                  const SizedBox(height: 10),
                  LiquidButton(
                    label: bi('Save location', 'இடத்தைச் சேமி'),
                    icon: CupertinoIcons.checkmark_alt,
                    height: 52,
                    radius: 26,
                    onPressed: () => Navigator.pop(context, _center),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// -----------------------------------------------------------------------------
//  Route maps home
// -----------------------------------------------------------------------------

class RouteMapsScreen extends StatefulWidget {
  const RouteMapsScreen({super.key});
  @override
  State<RouteMapsScreen> createState() => _RouteMapsScreenState();
}

class _RouteMapsScreenState extends State<RouteMapsScreen> {
  late final Future<Box> _box = VendorRoutes.open();
  bool get _cloud => firebaseReady && signedInUid.isNotEmpty;

  Future<void> _record([Map<String, dynamic>? route]) =>
      push(context, RouteRecorderScreen(route: route));

  void _start(Map<String, dynamic> route) {
    if (routeStops(route).isEmpty) {
      snack(
        context,
        bi('Mark a home first.', 'முதலில் ஒரு வீட்டைக் குறிக்கவும்.'),
      );
      return;
    }
    vendorRouteRequest.value = txt(route, 'id');
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _delete(Map<String, dynamic> route) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bi('Delete route?', 'பாதையை நீக்கவா?')),
        content: Text(
          bi(
            '"${txt(route, 'name')}" and its notes will be removed from this phone.',
            '"${txt(route, 'name')}" மற்றும் அதன் குறிப்புகள் இந்த phone-லிருந்து நீக்கப்படும்.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: AppText('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Ink.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(bi('Delete', 'நீக்கு')),
          ),
        ],
      ),
    );
    if (ok == true) await VendorRoutes.delete(txt(route, 'id'));
  }

  Future<void> _share(Map<String, dynamic> route) async {
    if (!_cloud) {
      snack(context, ui('Please sign in again'));
      return;
    }
    if (routeStops(route).isEmpty) {
      snack(
        context,
        bi('Mark a home first.', 'முதலில் ஒரு வீட்டைக் குறிக்கவும்.'),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ink.canvasTop,
      builder: (_) => _RouteShareSheet(route: route),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(title: Text(bi('Route maps', 'பாதை வரைபடங்கள்'))),
    body: Shell(
      child: FutureBuilder<Box>(
        future: _box,
        builder: (context, snap) {
          final box = snap.data;
          if (box == null) {
            return const Center(child: CupertinoActivityIndicator());
          }
          return ValueListenableBuilder(
            valueListenable: box.listenable(),
            builder: (context, _, _) {
              final own = VendorRoutes.own(box);
              final received = VendorRoutes.received(box);
              return ListView(
                padding: const EdgeInsets.fromLTRB(21, 8, 21, 48),
                children: [
                  Reveal(child: _RecordHero(onRecord: () => _record())),
                  const SizedBox(height: 27),
                  _SectionTitle(bi('Your routes', 'உங்கள் பாதைகள்')),
                  if (own.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 21),
                      child: Text(
                        bi(
                          'Record your milk round once. Every home and note stays on the map.',
                          'உங்கள் பால் சுற்றை ஒருமுறை பதிவு செய்யுங்கள். ஒவ்வொரு வீடும் குறிப்பும் வரைபடத்தில் இருக்கும்.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Ink.muted),
                      ),
                    ),
                  for (final (i, route) in own.indexed)
                    Reveal(
                      index: math.min(i + 1, 8),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _RouteCard(
                          route: route,
                          onOpen: () =>
                              push(context, RouteViewScreen(route: route)),
                          menu: _RouteMenu(
                            onStart: () => _start(route),
                            onEdit: () => _record(route),
                            onShare: () => _share(route),
                            onDelete: () => _delete(route),
                          ),
                        ),
                      ),
                    ),
                  if (_cloud) ...[
                    const _OwnerShares(),
                    _ReceivedRoutes(saved: received),
                  ],
                ],
              );
            },
          );
        },
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: Ink.navy,
              letterSpacing: -.2,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RecordHero extends StatelessWidget {
  final VoidCallback onRecord;
  const _RecordHero({required this.onRecord});
  @override
  Widget build(BuildContext context) => Glass(
    radius: 34,
    padding: const EdgeInsets.all(21),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: .86),
        Ink.lavender.withValues(alpha: .62),
        Colors.white.withValues(alpha: .7),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Ink.violet, Ink.violetDeep],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Ink.violetDeep.withValues(alpha: .3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                CupertinoIcons.map_fill,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bi('Record a route', 'பாதையைப் பதிவு செய்'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: Ink.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bi(
                      'Walk your round. Mark each home and pin notes on the way.',
                      'சுற்றில் நடந்து செல்லுங்கள். ஒவ்வொரு வீட்டையும் குறித்து, வழியில் குறிப்புகள் சேர்க்கவும்.',
                    ),
                    style: const TextStyle(color: Ink.muted, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LiquidButton(
          label: bi('Record path', 'பாதையைப் பதிவு செய்'),
          icon: CupertinoIcons.largecircle_fill_circle,
          height: 52,
          radius: 26,
          onPressed: onRecord,
        ),
      ],
    ),
  );
}

class _RouteMenu extends StatelessWidget {
  final VoidCallback onStart, onEdit, onShare, onDelete;
  const _RouteMenu({
    required this.onStart,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });
  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: bi('More', 'மேலும்'),
    icon: const Icon(CupertinoIcons.ellipsis_vertical, color: Ink.navy),
    shape: const SquircleBorder(radius: 21),
    color: Colors.white.withValues(alpha: .96),
    onSelected: (v) => switch (v) {
      0 => onStart(),
      1 => onEdit(),
      2 => onShare(),
      _ => onDelete(),
    },
    itemBuilder: (_) => [
      _menuItem(
        0,
        CupertinoIcons.play_fill,
        bi('Start route', 'பாதையைத் தொடங்கு'),
        Ink.violetDeep,
      ),
      _menuItem(
        1,
        CupertinoIcons.pencil,
        bi('Edit route', 'பாதையைத் திருத்து'),
        Ink.navy,
      ),
      _menuItem(
        2,
        CupertinoIcons.paperplane_fill,
        bi('Share in VIMO chat', 'VIMO chat-ல் பகிர்'),
        Ink.blue,
      ),
      _menuItem(3, CupertinoIcons.trash, bi('Delete', 'நீக்கு'), Ink.redText),
    ],
  );

  PopupMenuItem<int> _menuItem(int v, IconData icon, String label, Color c) =>
      PopupMenuItem(
        value: v,
        child: Row(
          children: [
            Icon(icon, size: 19, color: c),
            const SizedBox(width: 13),
            Text(
              label,
              style: TextStyle(color: c, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

class _RouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final VoidCallback onOpen;
  final Widget? menu;
  final Widget? footer;
  const _RouteCard({
    required this.route,
    required this.onOpen,
    this.menu,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final stops = routeStops(route), notes = routeNotes(route);
    final extent = routeExtent(route);
    final distance = routeDistanceMeters(routePath(route));
    return Glass(
      radius: 30,
      padding: const EdgeInsets.all(8),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipPath(
            clipper: const SquircleClipper(23),
            child: SizedBox(
              height: 154,
              child: extent.isEmpty
                  ? DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFF1EBFF), Color(0xFFE4ECFF)],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          CupertinoIcons.map,
                          size: 42,
                          color: Ink.violetDeep.withValues(alpha: .4),
                        ),
                      ),
                    )
                  : IgnorePointer(
                      child: VimoMap(
                        fit: extent,
                        center: extent.length == 1 ? extent.first : null,
                        interactive: false,
                        layers: routeLayers(route),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 0, 5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        txt(route, 'name', bi('Route', 'பாதை')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Ink.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AppText(
                        [
                          bi(
                            '${stops.length} homes',
                            '${stops.length} வீடுகள்',
                          ),
                          if (notes.isNotEmpty)
                            bi(
                              '${notes.length} notes',
                              '${notes.length} குறிப்புகள்',
                            ),
                          if (distance > 0) routeDistanceLabel(distance),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Ink.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                ?menu,
              ],
            ),
          ),
          ?footer,
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Recording
// -----------------------------------------------------------------------------

class RouteRecorderScreen extends StatefulWidget {
  final Map<String, dynamic>? route;
  const RouteRecorderScreen({super.key, this.route});
  @override
  State<RouteRecorderScreen> createState() => _RouteRecorderScreenState();
}

class _RouteRecorderScreenState extends State<RouteRecorderScreen> {
  final _map = fm.MapController();
  late final Map<String, dynamic> _route = {
    'id':
        widget.route?['id'] ??
        'route_${settingText('deviceId', 'device')}_${DateTime.now().microsecondsSinceEpoch}',
    'kind': 'own',
    'scope': widget.route?['scope'] ?? VendorRoutes.scope,
    'name': txt(widget.route ?? {}, 'name'),
    'createdAt': widget.route?['createdAt'] ?? DateTime.now().toIso8601String(),
    'path': [...((widget.route?['path'] as List?) ?? const [])],
    'stops': routeStops(widget.route ?? {}),
    'notes': routeNotes(widget.route ?? {}),
  };
  StreamSubscription<geo.Position>? _gps;
  Timer? _clock;
  ll.LatLng? _me;
  bool _recording = false, _follow = true, _saving = false, _ready = false;
  Duration _elapsed = Duration.zero;
  bool _dirty = false;

  List<dynamic> get _path => _route['path'] as List;
  List<Map<String, dynamic>> get _stops =>
      (_route['stops'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _notes =>
      (_route['notes'] as List).cast<Map<String, dynamic>>();

  @override
  void dispose() {
    _gps?.cancel();
    _clock?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      await _gps?.cancel();
      _gps = null;
      _clock?.cancel();
      setState(() => _recording = false);
      return;
    }
    if (!await VendorLocation.ready(context) || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _follow = true;
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
    _gps =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.best,
            distanceFilter: 4,
          ),
        ).listen(
          (p) {
            if (!mounted) return;
            final here = ll.LatLng(p.latitude, p.longitude);
            setState(() {
              _me = here;
              // Poor fixes (large accuracy circles) would draw zigzags.
              if (_recording && p.accuracy <= 45) _addPoint(here);
            });
            if (_follow && _ready) {
              _map.move(here, math.max(_map.camera.zoom, 17));
            }
          },
          onError: (Object _) {
            if (mounted) {
              snack(
                context,
                bi('Location signal lost.', 'Location சிக்னல் கிடைக்கவில்லை.'),
              );
            }
          },
        );
  }

  void _addPoint(ll.LatLng point) {
    final last = _path.isEmpty ? null : routePoint(_path.last);
    if (last != null &&
        const ll.Distance().as(ll.LengthUnit.Meter, last, point) < 3) {
      return;
    }
    _path.add(_pair(point));
    _dirty = true;
  }

  ll.LatLng get _here =>
      _me ?? (_ready ? _map.camera.center : vimoDefaultCenter);

  Future<void> _markHome([ll.LatLng? at]) async {
    final used = {for (final s in _stops) txt(s, 'id')};
    final person = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ink.canvasTop,
      builder: (_) => _PickCustomerSheet(exclude: used),
    );
    if (person == null || !mounted) return;
    final point = at ?? _here;
    setState(() {
      _stops.add({
        'id': txt(person, 'id'),
        'name': txt(person, 'name'),
        'place': txt(person, 'place'),
        'lat': point.latitude,
        'lng': point.longitude,
      });
      _addPoint(point);
      _dirty = true;
    });
    HapticFeedback.selectionClick();
    // A home marked on the route also becomes the person's saved location.
    if (personPoint(person) == null && canRecordEntries) {
      final key = person['_key'] ?? person['id'];
      final current = asMap(Hive.box('vendor_people').get(key));
      if (current.isNotEmpty) {
        await Hive.box('vendor_people').put(key, {
          ...current,
          'lat': point.latitude,
          'lng': point.longitude,
          'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
        });
        AutoSyncService.markDirty(reason: 'vendor person location');
      }
    }
  }

  Future<void> _addNote({String stopId = '', ll.LatLng? at}) async {
    final note = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ink.canvasTop,
      builder: (_) => _RouteNoteComposer(
        stopName: stopId.isEmpty
            ? ''
            : txt(
                _stops.where((s) => s['id'] == stopId).firstOrNull ?? {},
                'name',
              ),
      ),
    );
    if (note == null || !mounted) return;
    final stop = _stops.where((s) => s['id'] == stopId).firstOrNull;
    final point = at ?? (stop == null ? _here : personPoint(stop) ?? _here);
    setState(() {
      _notes.add({
        ...note,
        'id': 'note_${DateTime.now().microsecondsSinceEpoch}',
        'stopId': stopId,
        'lat': point.latitude,
        'lng': point.longitude,
        'createdAt': DateTime.now().toIso8601String(),
      });
      _dirty = true;
    });
  }

  Future<void> _stopActions(Map<String, dynamic> stop) async {
    final id = txt(stop, 'id');
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Ink.canvasTop,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                txt(stop, 'name'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                ),
              ),
              subtitle: Text(txt(stop, 'place')),
            ),
            for (final n in _notes.where((n) => n['stopId'] == id))
              ListTile(
                leading: Icon(routeNoteIcon(n), color: Ink.amberText),
                title: Text(
                  txt(n, 'text', bi('Note', 'குறிப்பு')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(ctx, 'note:${txt(n, 'id')}'),
              ),
            ListTile(
              leading: const Icon(
                CupertinoIcons.text_badge_plus,
                color: Ink.violetDeep,
              ),
              title: Text(
                bi('Add note to this home', 'இந்த வீட்டுக்குக் குறிப்பு'),
              ),
              onTap: () => Navigator.pop(ctx, 'note'),
            ),
            if (_me != null)
              ListTile(
                leading: const Icon(
                  CupertinoIcons.location_fill,
                  color: Ink.blue,
                ),
                title: Text(
                  bi(
                    'Move to where I am',
                    'நான் இருக்கும் இடத்திற்கு நகர்த்து',
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'move'),
              ),
            ListTile(
              leading: const Icon(CupertinoIcons.trash, color: Ink.redText),
              title: Text(
                bi('Remove from route', 'பாதையிலிருந்து நீக்கு'),
                style: const TextStyle(color: Ink.redText),
              ),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'note') return _addNote(stopId: id);
    if (action.startsWith('note:')) {
      final note = _notes.where((n) => 'note:${n['id']}' == action).firstOrNull;
      if (note != null) await _openNote(note);
      return;
    }
    setState(() {
      if (action == 'move' && _me != null) {
        stop['lat'] = _me!.latitude;
        stop['lng'] = _me!.longitude;
      } else if (action == 'remove') {
        _stops.removeWhere((s) => s['id'] == id);
        _notes.removeWhere((n) => n['stopId'] == id);
      }
      _dirty = true;
    });
  }

  Future<void> _openNote(Map<String, dynamic> note) async {
    final remove = await showRouteNote(context, note, removable: true);
    if (remove == true && mounted) {
      setState(() {
        _notes.removeWhere((n) => n['id'] == note['id']);
        _dirty = true;
      });
    }
  }

  Future<void> _finish() async {
    if (_stops.isEmpty) {
      snack(
        context,
        bi('Mark at least one home.', 'குறைந்தது ஒரு வீட்டைக் குறிக்கவும்.'),
      );
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ink.canvasTop,
      builder: (_) =>
          _RouteFinishSheet(name: txt(_route, 'name'), stops: [..._stops]),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _gps?.cancel();
      _gps = null;
      _clock?.cancel();
      _route['name'] = result['name'];
      _route['stops'] = result['stops'];
      _route['updatedAt'] = DateTime.now().toIso8601String();
      await VendorRoutes.save(_route);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      snack(context, bi('Route saved', 'பாதை சேமிக்கப்பட்டது'));
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        snack(context, ui('Unable to save. Try again.'));
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bi('Discard this recording?', 'இந்தப் பதிவை விடவா?')),
        content: Text(
          bi(
            'The path, homes and notes recorded now will be lost.',
            'இப்போது பதிவு செய்த பாதை, வீடுகள், குறிப்புகள் இழக்கப்படும்.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(bi('Keep recording', 'தொடர்')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Ink.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(bi('Discard', 'விடு')),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final path = routePath(_route);
    final extent = routeExtent(_route);
    final distance = routeDistanceMeters(path);
    final top = MediaQuery.paddingOf(context).top;
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) {
          _dirty = false;
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: VimoMap(
                controller: _map,
                fit: extent,
                center: extent.length == 1 ? extent.first : null,
                zoom: 17,
                onReady: () => _ready = true,
                onMove: (_, gesture) {
                  if (gesture && _follow) setState(() => _follow = false);
                },
                onLongPress: (p) => _markHome(p),
                layers: routeLayers(
                  _route,
                  me: _me,
                  onStop: _stopActions,
                  onNote: _openNote,
                ),
              ),
            ),
            // Status capsule
            Positioned(
              top: top + 10,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _MapButton(
                    icon: CupertinoIcons.chevron_back,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    color: Ink.navy,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Glass(
                      radius: 24,
                      opacity: .84,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _RecordingDot(active: _recording),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppText(
                              _recording
                                  ? bi('Recording', 'பதிவாகிறது')
                                  : path.isEmpty
                                  ? bi('Ready to record', 'பதிவுக்குத் தயார்')
                                  : bi('Paused', 'நிறுத்தப்பட்டது'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Ink.navy,
                              ),
                            ),
                          ),
                          AppText(
                            '${voiceDurationLabel(_elapsed.inSeconds)} · ${routeDistanceLabel(distance)} · ${_stops.length}🏠',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Ink.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 196,
              child: SafeArea(
                child: _MapButton(
                  icon: _follow
                      ? CupertinoIcons.location_fill
                      : CupertinoIcons.location,
                  tooltip: bi('Follow me', 'என்னைப் பின்தொடர்'),
                  color: Ink.blue,
                  onTap: _me == null
                      ? null
                      : () {
                          setState(() => _follow = true);
                          _map.move(_me!, math.max(_map.camera.zoom, 17));
                        },
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Glass(
                  radius: 34,
                  opacity: .86,
                  padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _BigAction(
                              icon: CupertinoIcons.house_fill,
                              label: bi('Mark home', 'வீட்டைக் குறி'),
                              color: Ink.violetDeep,
                              onTap: _saving ? null : () => _markHome(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BigAction(
                              icon: CupertinoIcons.text_badge_plus,
                              label: bi('Add note', 'குறிப்பு'),
                              color: Ink.amberText,
                              onTap: _saving ? null : () => _addNote(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BigAction(
                              icon: _recording
                                  ? CupertinoIcons.pause_fill
                                  : CupertinoIcons.largecircle_fill_circle,
                              label: _recording
                                  ? bi('Pause', 'நிறுத்து')
                                  : path.isEmpty
                                  ? bi('Record', 'பதிவு')
                                  : bi('Resume', 'தொடர்'),
                              color: Ink.redText,
                              onTap: _saving ? null : _toggle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LiquidButton(
                        label: bi('Finish & save', 'முடித்து சேமி'),
                        icon: CupertinoIcons.checkmark_alt,
                        height: 50,
                        radius: 25,
                        busy: _saving,
                        onPressed: _saving ? null : _finish,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        bi(
                          'Tip: long-press the map to mark a home there.',
                          'குறிப்பு: வரைபடத்தை அழுத்திப் பிடித்தால் அங்கு வீட்டைக் குறிக்கலாம்.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Ink.muted, fontSize: 12),
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
}

class _RecordingDot extends StatefulWidget {
  final bool active;
  const _RecordingDot({required this.active});
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_RecordingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: .35, end: 1.0).animate(_c),
    child: Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.active ? Ink.red : Ink.faint,
        boxShadow: widget.active
            ? [BoxShadow(color: Ink.red.withValues(alpha: .5), blurRadius: 8)]
            : null,
      ),
    ),
  );
}

class _BigAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _BigAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Pressable(
      radius: 21,
      onTap: onTap,
      child: AnimatedOpacity(
        duration: Gold.fast,
        opacity: onTap == null ? .45 : 1,
        child: Container(
          height: 72,
          decoration: ShapeDecoration(
            shape: const SquircleBorder(radius: 21),
            color: color.withValues(alpha: .08),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PickCustomerSheet extends StatefulWidget {
  final Set<String> exclude;
  const _PickCustomerSheet({required this.exclude});
  @override
  State<_PickCustomerSheet> createState() => _PickCustomerSheetState();
}

class _PickCustomerSheetState extends State<_PickCustomerSheet> {
  String _query = '';
  final _name = TextEditingController();
  final _place = TextEditingController();
  bool _adding = false, _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final person = await vendorQuickPerson(
        name: _name.text.trim(),
        place: _place.text.trim(),
      );
      if (mounted) Navigator.pop(context, person);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, '$e'.replaceFirst('Bad state: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final people =
        vendorRows('vendor_people')
            .where(
              (p) =>
                  p['kind'] == 'customer' &&
                  !widget.exclude.contains(txt(p, 'id')) &&
                  (q.isEmpty ||
                      '${p['name']} ${p['place']}'.toLowerCase().contains(q)),
            )
            .toList()
          ..sort((a, b) => txt(a, 'name').compareTo(txt(b, 'name')));
    final groups = vendorPlaceGroups(people);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(21, 0, 21, 10),
                child: Text(
                  bi('Whose home is this?', 'இது யாருடைய வீடு?'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 21),
                child: _adding
                    ? Column(
                        children: [
                          TextField(
                            controller: _name,
                            autofocus: true,
                            textCapitalization: TextCapitalization.words,
                            decoration: fieldStyle(
                              ui('Name'),
                              icon: CupertinoIcons.person,
                            ),
                          ),
                          const SizedBox(height: 12),
                          VendorPlaceField(
                            controller: _place,
                            label: bi('Place', 'இடம்'),
                          ),
                          const SizedBox(height: 12),
                          LiquidButton(
                            label: bi('Add customer', 'வாடிக்கையாளரைச் சேர்'),
                            icon: CupertinoIcons.person_add_solid,
                            busy: _busy,
                            onPressed: _create,
                          ),
                        ],
                      )
                    : TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(CupertinoIcons.search),
                          hintText: bi(
                            'Search name or place',
                            'பெயர் அல்லது இடம் தேடு',
                          ),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
              ),
              if (!canRecordEntries)
                const SizedBox.shrink()
              else
                TextButton.icon(
                  onPressed: () => setState(() => _adding = !_adding),
                  icon: Icon(
                    _adding
                        ? CupertinoIcons.list_bullet
                        : CupertinoIcons.person_add,
                  ),
                  label: Text(
                    _adding
                        ? bi('Choose from list', 'பட்டியலில் தேர்வு செய்')
                        : bi('New customer', 'புதிய வாடிக்கையாளர்'),
                  ),
                ),
              if (!_adding)
                Expanded(
                  child: people.isEmpty
                      ? Center(
                          child: Text(
                            bi(
                              'Every customer is on this route.',
                              'அனைத்து வாடிக்கையாளர்களும் இந்தப் பாதையில் உள்ளனர்.',
                            ),
                            style: const TextStyle(color: Ink.muted),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(13, 0, 13, 21),
                          children: [
                            for (final g in groups) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                                child: Text(
                                  g.label,
                                  style: const TextStyle(
                                    color: Ink.muted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              for (final p in g.people)
                                _PickRow(
                                  person: p,
                                  selected: false,
                                  onTap: () => Navigator.pop(context, p),
                                ),
                            ],
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

class _RouteFinishSheet extends StatefulWidget {
  final String name;
  final List<Map<String, dynamic>> stops;
  const _RouteFinishSheet({required this.name, required this.stops});
  @override
  State<_RouteFinishSheet> createState() => _RouteFinishSheetState();
}

class _RouteFinishSheetState extends State<_RouteFinishSheet> {
  late final _name = TextEditingController(
    text: widget.name.isNotEmpty
        ? widget.name
        : vendorSessionNow() == 'Morning'
        ? bi('Morning round', 'காலைச் சுற்று')
        : bi('Evening round', 'மாலைச் சுற்று'),
  );
  late final List<Map<String, dynamic>> _stops = widget.stops;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 0, 21, 13),
              child: TextField(
                controller: _name,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: fieldStyle(
                  bi('Route name', 'பாதையின் பெயர்'),
                  icon: CupertinoIcons.map,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 21),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      bi('Delivery order', 'விநியோக வரிசை'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: Ink.navy,
                      ),
                    ),
                  ),
                  Text(
                    bi('Hold and drag', 'பிடித்து இழுக்கவும்'),
                    style: const TextStyle(color: Ink.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(21, 8, 21, 8),
                buildDefaultDragHandles: false,
                itemCount: _stops.length,
                onReorderItem: (old, next) => setState(() {
                  _stops.insert(next, _stops.removeAt(old));
                }),
                itemBuilder: (context, i) =>
                    ReorderableDelayedDragStartListener(
                      key: ValueKey(_stops[i]['id']),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Glass(
                          radius: 21,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              _HomePin(
                                number: i + 1,
                                label: txt(_stops[i], 'name'),
                                state: StopState.pending,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      txt(_stops[i], 'name'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      txt(_stops[i], 'place'),
                                      style: const TextStyle(
                                        color: Ink.muted,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                CupertinoIcons.line_horizontal_3,
                                color: Ink.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 8, 21, 16),
              child: LiquidButton(
                label: bi('Save route', 'பாதையைச் சேமி'),
                icon: CupertinoIcons.checkmark_alt,
                height: 54,
                radius: 27,
                onPressed: () {
                  final name = _name.text.trim();
                  if (name.isEmpty) {
                    snack(context, bi('Enter a name', 'பெயரை உள்ளிடவும்'));
                    return;
                  }
                  Navigator.pop(context, {'name': name, 'stops': _stops});
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
//  Notes: text, voice or photo
// -----------------------------------------------------------------------------

class _RouteNoteComposer extends StatefulWidget {
  final String stopName;
  const _RouteNoteComposer({this.stopName = ''});
  @override
  State<_RouteNoteComposer> createState() => _RouteNoteComposerState();
}

class _RouteNoteComposerState extends State<_RouteNoteComposer> {
  static const _rate = 8000, _maxSeconds = 30;
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  String _photo = '', _voice = '';
  int _voiceSeconds = 0, _seconds = 0;
  bool _recording = false, _picking = false;
  BytesBuilder _audio = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _stream;
  Completer<void>? _done;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_stream?.cancel());
    unawaited(_recorder.cancel().catchError((Object _) {}));
    unawaited(_recorder.dispose().catchError((Object _) {}));
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await pickImageDataUrl();
      if (picked == null) return;
      final bytes = await compute(
        _thumbnailEncode,
        base64Decode(picked.split(',').last),
      );
      if (bytes == null) throw StateError('photo');
      if (mounted) {
        setState(
          () => _photo = 'data:image/jpeg;base64,${base64Encode(bytes)}',
        );
      }
    } catch (_) {
      if (mounted) {
        snack(
          context,
          bi(
            'Could not use this photo.',
            'இந்தப் புகைப்படத்தைப் பயன்படுத்த முடியவில்லை.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _record() async {
    if (_recording) return _stop();
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) snack(context, ui('Microphone permission is needed'));
        return;
      }
      _audio = BytesBuilder(copy: false);
      final done = Completer<void>();
      _done = done;
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _rate,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _stream = stream.listen(
        _audio.add,
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _recording = true;
        _seconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= _maxSeconds) unawaited(_stop());
      });
    } catch (_) {
      if (mounted) snack(context, ui('Unable to record. Try again.'));
    }
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _timer?.cancel();
    setState(() => _recording = false);
    try {
      await _recorder.stop();
      await _done?.future.timeout(const Duration(seconds: 3));
      await _stream?.cancel();
      final pcm = _audio.takeBytes();
      if (pcm.isEmpty) throw StateError('empty');
      final wave = pcm16ToWave(pcm, sampleRate: _rate);
      if (mounted) {
        setState(() {
          _voice = base64Encode(wave);
          _voiceSeconds = math.max(1, _seconds);
        });
      }
    } catch (_) {
      if (mounted) snack(context, ui('Unable to record. Try again.'));
    } finally {
      _stream = null;
      _done = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        !_recording &&
        (_text.text.trim().isNotEmpty ||
            _photo.isNotEmpty ||
            _voice.isNotEmpty);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.stopName.isEmpty
                    ? bi('Note on the path', 'பாதையில் குறிப்பு')
                    : bi(
                        'Note for ${widget.stopName}',
                        '${widget.stopName} வீட்டுக்குக் குறிப்பு',
                      ),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Ink.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                bi(
                  'Help the next person find the way: a gate, a dog, a landmark.',
                  'அடுத்தவருக்கு வழி சொல்லுங்கள்: கேட், நாய், அடையாளம்.',
                ),
                style: const TextStyle(color: Ink.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                minLines: 2,
                maxLines: 5,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: fieldStyle(
                  bi('Write a note', 'குறிப்பு எழுது'),
                  icon: CupertinoIcons.text_bubble,
                ),
                onChanged: (_) => setState(() {}),
              ),
              Row(
                children: [
                  Expanded(
                    child: _BigAction(
                      icon: _recording
                          ? CupertinoIcons.stop_fill
                          : CupertinoIcons.mic_fill,
                      label: _recording
                          ? '${bi('Stop', 'நிறுத்து')} ${voiceDurationLabel(_seconds)}'
                          : _voice.isNotEmpty
                          ? bi('Record again', 'மீண்டும் பதிவு')
                          : bi('Voice note', 'குரல் குறிப்பு'),
                      color: Ink.redText,
                      onTap: _record,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BigAction(
                      icon: CupertinoIcons.camera_fill,
                      label: _photo.isEmpty
                          ? bi('Photo', 'புகைப்படம்')
                          : bi('Change photo', 'புகைப்படம் மாற்று'),
                      color: Ink.blue,
                      onTap: _picking || _recording ? null : _pickPhoto,
                    ),
                  ),
                ],
              ),
              if (_voice.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _VoiceMessageBubble(
                        key: ValueKey(_voice.length),
                        url: '',
                        encodedAudio: _voice,
                        durationSeconds: _voiceSeconds,
                        color: Ink.redText,
                      ),
                    ),
                    IconButton(
                      tooltip: bi('Remove voice', 'குரலை நீக்கு'),
                      icon: const Icon(CupertinoIcons.trash, size: 19),
                      color: Ink.muted,
                      onPressed: () => setState(() => _voice = ''),
                    ),
                  ],
                ),
              ],
              if (_photo.isNotEmpty) ...[
                const SizedBox(height: 12),
                Stack(
                  children: [
                    ClipPath(
                      clipper: const SquircleClipper(21),
                      child: Image.memory(
                        base64Decode(_photo.split(',').last),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _MapButton(
                        icon: CupertinoIcons.trash,
                        tooltip: bi('Remove photo', 'புகைப்படத்தை நீக்கு'),
                        color: Ink.redText,
                        onTap: () => setState(() => _photo = ''),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              LiquidButton(
                label: bi('Pin note', 'குறிப்பைச் சேர்'),
                icon: CupertinoIcons.pin_fill,
                height: 54,
                radius: 27,
                onPressed: canSave
                    ? () => Navigator.pop(context, {
                        'text': _text.text.trim(),
                        'photo': _photo,
                        'voice': _voice,
                        'voiceSeconds': _voiceSeconds,
                      })
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a note. Returns true when the person chose to remove it.
Future<bool?> showRouteNote(
  BuildContext context,
  Map<String, dynamic> note, {
  bool removable = false,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Ink.canvasTop,
  builder: (ctx) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
      child: _RouteNoteBody(note: note, removable: removable),
    ),
  ),
);

class _RouteNoteBody extends StatelessWidget {
  final Map<String, dynamic> note;
  final bool removable;
  const _RouteNoteBody({required this.note, this.removable = false});
  @override
  Widget build(BuildContext context) {
    final photo = txt(note, 'photo');
    final voice = txt(note, 'voice');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(routeNoteIcon(note), color: Ink.amberText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                bi('Note', 'குறிப்பு'),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Ink.navy,
                ),
              ),
            ),
            if (removable)
              TextButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(CupertinoIcons.trash, size: 18),
                label: Text(bi('Remove', 'நீக்கு')),
                style: TextButton.styleFrom(foregroundColor: Ink.redText),
              ),
          ],
        ),
        if (txt(note, 'text').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            txt(note, 'text'),
            style: const TextStyle(fontSize: 17, height: 1.4, color: Ink.body),
          ),
        ],
        if (voice.isNotEmpty) ...[
          const SizedBox(height: 13),
          _VoiceMessageBubble(
            url: '',
            encodedAudio: voice,
            durationSeconds: toInt(note['voiceSeconds']),
            color: Ink.redText,
          ),
        ],
        if (photo.startsWith('data:image')) ...[
          const SizedBox(height: 13),
          ClipPath(
            clipper: const SquircleClipper(21),
            child: Image.memory(
              base64Decode(photo.split(',').last),
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Viewing a route
// -----------------------------------------------------------------------------

class RouteViewScreen extends StatefulWidget {
  final Map<String, dynamic> route;
  final Map<String, StopState> states;
  const RouteViewScreen({
    super.key,
    required this.route,
    this.states = const {},
  });
  @override
  State<RouteViewScreen> createState() => _RouteViewScreenState();
}

class _RouteViewScreenState extends State<RouteViewScreen> {
  final _map = fm.MapController();
  ll.LatLng? _me;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final here = await VendorLocation.current(context);
    if (here == null || !mounted) return;
    setState(() => _me = here);
    _map.move(here, math.max(_map.camera.zoom, 17));
  }

  void _focus(Map<String, dynamic> stop) {
    final point = personPoint(stop);
    if (point != null) _map.move(point, 18);
  }

  Future<void> _stop(Map<String, dynamic> stop) async {
    final notes = routeNotes(
      widget.route,
    ).where((n) => n['stopId'] == stop['id']).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ink.canvasTop,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                txt(stop, 'name'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Ink.navy,
                ),
              ),
              Text(
                txt(stop, 'place'),
                style: const TextStyle(color: Ink.muted),
              ),
              if (notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    bi(
                      'No notes for this home.',
                      'இந்த வீட்டுக்குக் குறிப்புகள் இல்லை.',
                    ),
                    style: const TextStyle(color: Ink.muted),
                  ),
                ),
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Glass(radius: 21, child: _RouteNoteBody(note: n)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final stops = routeStops(route);
    final extent = routeExtent(route);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(txt(route, 'name')),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: VimoMap(
              controller: _map,
              fit: extent,
              center: extent.length == 1 ? extent.first : null,
              layers: routeLayers(
                route,
                states: widget.states,
                me: _me,
                onStop: _stop,
                onNote: (n) => showRouteNote(context, n),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 196,
            child: SafeArea(
              child: _MapButton(
                icon: CupertinoIcons.location_fill,
                tooltip: bi('My location', 'என் இடம்'),
                color: Ink.blue,
                onTap: _locate,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 118,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: stops.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final s = stops[i];
                    final notes = routeNotes(
                      route,
                    ).where((n) => n['stopId'] == s['id']).length;
                    return SizedBox(
                      width: 196,
                      child: Glass(
                        radius: 24,
                        opacity: .86,
                        padding: const EdgeInsets.all(13),
                        onTap: () {
                          _focus(s);
                          _stop(s);
                        },
                        child: Row(
                          children: [
                            _HomePin(
                              number: i + 1,
                              label: txt(s, 'name'),
                              state:
                                  widget.states[txt(s, 'id')] ??
                                  StopState.pending,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    txt(s, 'name'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Ink.navy,
                                    ),
                                  ),
                                  Text(
                                    txt(s, 'place'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Ink.muted,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  if (notes > 0)
                                    Text(
                                      bi('$notes notes', '$notes குறிப்புகள்'),
                                      style: const TextStyle(
                                        color: Ink.amberText,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Map during a vendor ride
// -----------------------------------------------------------------------------

/// The route map on the ride screen: the next home centred, its notes below.
class VendorRouteGuide extends StatefulWidget {
  final Map<String, dynamic> route;
  final String? currentId;
  final Map<String, StopState> states;
  const VendorRouteGuide({
    super.key,
    required this.route,
    required this.currentId,
    required this.states,
  });
  @override
  State<VendorRouteGuide> createState() => _VendorRouteGuideState();
}

class _VendorRouteGuideState extends State<VendorRouteGuide> {
  final _map = fm.MapController();
  bool _ready = false;

  ll.LatLng? get _target {
    final stop = routeStops(
      widget.route,
    ).where((s) => s['id'] == widget.currentId).firstOrNull;
    return stop == null ? null : personPoint(stop);
  }

  @override
  void didUpdateWidget(VendorRouteGuide old) {
    super.didUpdateWidget(old);
    final target = _target;
    if (old.currentId != widget.currentId && _ready && target != null) {
      _map.move(target, 17.5);
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final extent = routeExtent(widget.route);
    final notes = routeNotes(
      widget.route,
    ).where((n) => n['stopId'] == widget.currentId).toList();
    return Glass(
      radius: 30,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipPath(
            clipper: const SquircleClipper(23),
            child: SizedBox(
              height: 200,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: VimoMap(
                        controller: _map,
                        center:
                            target ??
                            (extent.length == 1 ? extent.first : null),
                        zoom: 17.5,
                        fit: extent,
                        interactive: false,
                        onReady: () => _ready = true,
                        layers: routeLayers(
                          widget.route,
                          states: widget.states,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: _MapButton(
                      icon: CupertinoIcons.arrow_up_left_arrow_down_right,
                      tooltip: bi('Full map', 'முழு வரைபடம்'),
                      onTap: () => push(
                        context,
                        RouteViewScreen(
                          route: widget.route,
                          states: widget.states,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in notes)
                    ActionChip(
                      avatar: Icon(
                        routeNoteIcon(n),
                        size: 16,
                        color: Ink.amberText,
                      ),
                      label: Text(
                        txt(n, 'text', bi('Open note', 'குறிப்பைத் திற')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => showRouteNote(context, n),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.map_fill,
                  size: 15,
                  color: Ink.violetDeep,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    txt(widget.route, 'name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Ink.violetDeep,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                // Paths between homes carry notes too.
                if (routeNotes(
                  widget.route,
                ).any((n) => txt(n, 'stopId').isEmpty))
                  Text(
                    bi(
                      '${routeNotes(widget.route).where((n) => txt(n, 'stopId').isEmpty).length} path notes',
                      '${routeNotes(widget.route).where((n) => txt(n, 'stopId').isEmpty).length} பாதைக் குறிப்புகள்',
                    ),
                    style: const TextStyle(
                      color: Ink.amberText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Lending a route through VIMO chat
// -----------------------------------------------------------------------------

class RouteShareService {
  const RouteShareService._();
  static CollectionReference<Map<String, dynamic>> get _shares =>
      FirebaseFirestore.instance.collection('route_shares');

  /// The lent copy: name, place, litres and optionally balance. No contact,
  /// photo or history. Media is dropped when the document would be too large.
  static ({Map<String, dynamic> route, bool trimmed}) payload(
    Map<String, dynamic> route, {
    required bool collectLater,
    String? session,
  }) {
    final people = {
      for (final p in vendorRows('vendor_people')) txt(p, 'id'): p,
    };
    final rows = vendorRows('vendor_entries');
    final when = session ?? vendorSessionNow();
    final stops = [
      for (final s in routeStops(route))
        {
          'id': txt(s, 'id'),
          'name': txt(people[txt(s, 'id')] ?? s, 'name'),
          'place': txt(people[txt(s, 'id')] ?? s, 'place'),
          if (personPoint(s) case final p?) ...{
            'lat': p.latitude,
            'lng': p.longitude,
          },
          'litres': double.parse(
            (people[txt(s, 'id')] == null
                    ? 1.0
                    : vendorUsualQuantity(people[txt(s, 'id')]!, when, rows))
                .toStringAsFixed(2),
          ),
          if (!collectLater && people[txt(s, 'id')] != null) ...{
            'price': numv(people[txt(s, 'id')]!, 'price', defaultMilkPrice()),
            'due': double.parse(
              math
                  .max(0.0, vendorPersonDue(txt(s, 'id'), rows))
                  .toStringAsFixed(2),
            ),
          },
        },
    ];
    var notes = [
      for (final n in routeNotes(route))
        {
          'id': txt(n, 'id'),
          'stopId': txt(n, 'stopId'),
          if (personPoint(n) case final p?) ...{
            'lat': p.latitude,
            'lng': p.longitude,
          },
          'text': txt(n, 'text'),
          'photo': txt(n, 'photo'),
          'voice': txt(n, 'voice'),
          'voiceSeconds': toInt(n['voiceSeconds']),
        },
    ];
    final path = [
      for (final p in routePath(route))
        {'lat': _pair(p).first, 'lng': _pair(p).last},
    ];
    int size() =>
        jsonEncode({'path': path, 'stops': stops, 'notes': notes}).length;
    var trimmed = false;
    // Firestore documents stop at 1 MiB; voice goes first, then photos.
    for (final field in const ['voice', 'photo']) {
      if (size() <= 880000) break;
      notes = [
        for (final n in notes)
          {...n, field: '', if (field == 'voice') 'voiceSeconds': 0},
      ];
      trimmed = true;
    }
    return (
      route: {'path': path, 'stops': stops, 'notes': notes},
      trimmed: trimmed,
    );
  }

  static Future<({String id, bool trimmed})> share({
    required Map<String, dynamic> route,
    required String recipientUid,
    required Duration duration,
    required bool collectLater,
  }) async {
    final me = signedInUid;
    if (me.isEmpty) throw StateError(ui('Please sign in again'));
    final built = payload(route, collectLater: collectLater);
    final ref = _shares.doc();
    final name = txt(route, 'name', bi('Route', 'பாதை'));
    final owner = currentUserName();
    await ref
        .set({
          'ownerUid': me,
          'ownerName': owner.length > 80 ? owner.substring(0, 80) : owner,
          'recipientUid': recipientUid,
          'routeName': name.length > 80 ? name.substring(0, 80) : name,
          'route': built.route,
          'collectLater': collectLater,
          'status': 'active',
          'response': 'pending',
          'progress': <String, dynamic>{},
          'expiresAt': Timestamp.fromDate(DateTime.now().add(duration)),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(CloudSyncService.networkTimeout);
    await _sendToPerson(
      recipientUid,
      ShareCard.route(
        shareId: ref.id,
        name: name,
        owner: owner,
        homes: routeStops(route).length,
      ).encode(),
    );
    return (id: ref.id, trimmed: built.trimmed);
  }

  static Future<void> extend(String id, DateTime current, Duration by) {
    final now = DateTime.now();
    var until = (current.isAfter(now) ? current : now).add(by);
    final cap = now.add(const Duration(days: 14));
    if (until.isAfter(cap)) until = cap;
    return _shares
        .doc(id)
        .update({
          'status': 'active',
          'expiresAt': Timestamp.fromDate(until),
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(CloudSyncService.networkTimeout);
  }

  static Future<void> stop(String id) => _shares
      .doc(id)
      .update({'status': 'stopped', 'updatedAt': FieldValue.serverTimestamp()})
      .timeout(CloudSyncService.networkTimeout);

  static Future<void> remove(String id) =>
      _shares.doc(id).delete().timeout(CloudSyncService.networkTimeout);

  static Future<void> respond(String id, bool accept) => _shares
      .doc(id)
      .update({
        'response': accept ? 'accepted' : 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      })
      .timeout(CloudSyncService.networkTimeout);

  static Future<void> progress(String id, Map<String, dynamic> progress) =>
      _shares
          .doc(id)
          .update({
            'progress': progress,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(CloudSyncService.networkTimeout);

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String id) =>
      _shares.doc(id).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> owned() =>
      _shares.where('ownerUid', isEqualTo: signedInUid).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> incoming() =>
      _shares.where('recipientUid', isEqualTo: signedInUid).snapshots();

  /// Keep the recipient's saved copy of a lent route.
  static Future<void> saveCopy(String id, Map<String, dynamic> data) =>
      VendorRoutes.save({
        ...asMap(data['route']),
        'id': 'recv_$id',
        'kind': 'received',
        'scope': VendorRoutes.receivedScope,
        'shareId': id,
        'name': txt(data, 'routeName'),
        'ownerName': txt(data, 'ownerName'),
        'collectLater': data['collectLater'] == true,
        'expiresAt': _stamp(data['expiresAt'])?.toIso8601String() ?? '',
        'receivedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

  static bool live(Map<String, dynamic> data) {
    final until = _stamp(data['expiresAt']);
    return data['status'] == 'active' &&
        until != null &&
        until.isAfter(DateTime.now());
  }
}

class _RouteShareSheet extends StatefulWidget {
  final Map<String, dynamic> route;
  const _RouteShareSheet({required this.route});
  @override
  State<_RouteShareSheet> createState() => _RouteShareSheetState();
}

class _RouteShareSheetState extends State<_RouteShareSheet> {
  static const _durations = [
    Duration(days: 1),
    Duration(days: 2),
    Duration(days: 3),
    Duration(days: 7),
  ];
  late final Future<List<String>> _people = loadShareablePeople(
    includeRanchMembers: true,
  );
  int _duration = 0;
  bool _collectLater = false, _sending = false;
  String? _peer;

  String _durationLabel(int i) => switch (i) {
    0 => bi('1 day', '1 நாள்'),
    1 => bi('2 days', '2 நாட்கள்'),
    2 => bi('3 days', '3 நாட்கள்'),
    _ => bi('1 week', '1 வாரம்'),
  };

  Future<void> _send() async {
    final peer = _peer;
    if (_sending || peer == null) return;
    setState(() => _sending = true);
    try {
      final result = await RouteShareService.share(
        route: widget.route,
        recipientUid: peer,
        duration: _durations[_duration],
        collectLater: _collectLater,
      );
      if (!mounted) return;
      Navigator.pop(context);
      snack(
        context,
        result.trimmed
            ? bi(
                'Shared. Some voice notes or photos were too large to send.',
                'பகிரப்பட்டது. சில குரல்/புகைப்படங்கள் அனுப்ப முடியாத அளவு பெரியவை.',
              )
            : bi('Route shared in chat', 'பாதை chat-ல் பகிரப்பட்டது'),
      );
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .84,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(21, 0, 21, 13),
              children: [
                Text(
                  bi('Lend this route', 'இந்தப் பாதையைக் கொடு'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  bi(
                    'They see only name, place, litres${_collectLater ? '' : ' and balance'}. No history, contact number or photo.',
                    'அவர்கள் பெயர், இடம், லிட்டர்${_collectLater ? '' : ', நிலுவை'} மட்டும் பார்ப்பார்கள். வரலாறு, தொலைபேசி எண், புகைப்படம் இல்லை.',
                  ),
                  style: const TextStyle(color: Ink.muted, fontSize: 13.5),
                ),
                const SizedBox(height: 21),
                Text(
                  bi('How long?', 'எத்தனை நாள்?'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < _durations.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: _VendorPill(
                          label: _durationLabel(i),
                          selected: _duration == i,
                          onTap: () => setState(() => _duration = i),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Glass(
                  radius: 24,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _collectLater,
                    activeTrackColor: Ink.violetDeep,
                    title: Text(
                      bi(
                        'I\'ll collect money after I return',
                        'நான் வந்த பிறகு பணம் வாங்கிக்கொள்கிறேன்',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      bi(
                        'Amounts stay hidden. Only litres are shown.',
                        'தொகை மறைக்கப்படும். லிட்டர் மட்டும் காட்டப்படும்.',
                      ),
                    ),
                    onChanged: (v) => setState(() => _collectLater = v),
                  ),
                ),
                const SizedBox(height: 21),
                Text(
                  bi('Send to', 'யாருக்கு'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
                const SizedBox(height: 6),
                FutureBuilder<List<String>>(
                  future: _people,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CupertinoActivityIndicator()),
                      );
                    }
                    final people = snap.data ?? const <String>[];
                    if (people.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(21),
                        child: Text(
                          bi(
                            'Add the person in Chat first.',
                            'முதலில் Chat-ல் அந்த நபரைச் சேர்க்கவும்.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Ink.muted),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final uid in people)
                          _ProfileChoice(
                            uid: uid,
                            selected: _peer == uid,
                            onTap: () => setState(() => _peer = uid),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(21, 4, 21, 13),
            child: LiquidButton(
              label: _peer == null
                  ? bi('Choose a person', 'ஒருவரைத் தேர்வு செய்யவும்')
                  : bi(
                      'Share · ${_durationLabel(_duration)}',
                      'பகிர் · ${_durationLabel(_duration)}',
                    ),
              icon: CupertinoIcons.paperplane_fill,
              busy: _sending,
              height: 54,
              radius: 27,
              onPressed: _peer == null ? null : _send,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfileChoice extends StatelessWidget {
  final String uid;
  final bool selected;
  final VoidCallback onTap;
  const _ProfileChoice({
    required this.uid,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance.collection('profiles').doc(uid).get(),
    builder: (context, snap) {
      final d = snap.data?.data() ?? const <String, dynamic>{};
      final name = txt(
        d,
        'displayName',
        txt(d, 'username', bi('VIMO member', 'VIMO உறுப்பினர்')),
      );
      return InkWell(
        borderRadius: BorderRadius.circular(21),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              profileAvatar(txt(d, 'photo'), radius: 23, label: name),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Ink.navy,
                      ),
                    ),
                    if (txt(d, 'username').isNotEmpty)
                      Text(
                        '@${txt(d, 'username')}',
                        style: const TextStyle(color: Ink.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: Gold.fast,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Ink.violetDeep : Colors.transparent,
                  border: Border.all(
                    color: selected ? Ink.violetDeep : Ink.faint,
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _profileName(Map<String, dynamic> d) => txt(
  d,
  'displayName',
  txt(d, 'username', bi('VIMO member', 'VIMO உறுப்பினர்')),
);

/// Owner view of lent routes: who has it, time left, extend or stop.
class _OwnerShares extends StatelessWidget {
  const _OwnerShares();
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: RouteShareService.owned(),
        builder: (context, snap) {
          final docs = [...?snap.data?.docs]
            ..sort(
              (a, b) => (_stamp(b.data()['createdAt']) ?? DateTime(0))
                  .compareTo(_stamp(a.data()['createdAt']) ?? DateTime(0)),
            );
          if (docs.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 13),
              _SectionTitle(bi('Shared by you', 'நீங்கள் பகிர்ந்தவை')),
              for (final d in docs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 13),
                  child: RouteShareOwnerCard(id: d.id, data: d.data()),
                ),
            ],
          );
        },
      );
}

class RouteShareOwnerCard extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  const RouteShareOwnerCard({super.key, required this.id, required this.data});
  @override
  State<RouteShareOwnerCard> createState() => _RouteShareOwnerCardState();
}

class _RouteShareOwnerCardState extends State<RouteShareOwnerCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) snack(context, done);
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extend() async {
    final pick = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      backgroundColor: Ink.canvasTop,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                bi('Extend by', 'நீட்டிப்பு'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final (d, label) in [
              (const Duration(days: 1), bi('1 day', '1 நாள்')),
              (const Duration(days: 2), bi('2 days', '2 நாட்கள்')),
              (const Duration(days: 3), bi('3 days', '3 நாட்கள்')),
              (const Duration(days: 7), bi('1 week', '1 வாரம்')),
            ])
              ListTile(
                leading: const Icon(
                  CupertinoIcons.clock_fill,
                  color: Ink.violetDeep,
                ),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pick == null) return;
    await _run(
      () => RouteShareService.extend(
        widget.id,
        _stamp(widget.data['expiresAt']) ?? DateTime.now(),
        pick,
      ),
      bi('Time extended', 'நேரம் நீட்டிக்கப்பட்டது'),
    );
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bi('Stop sharing now?', 'இப்போதே பகிர்வை நிறுத்தவா?')),
        content: Text(
          bi(
            'Their map stops immediately and they are told you stopped it.',
            'அவர்களுடைய வரைபடம் உடனே நிற்கும்; நீங்கள் நிறுத்தியதாக அவர்களுக்குத் தெரிவிக்கப்படும்.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: AppText('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Ink.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(bi('Stop', 'நிறுத்து')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(
        () => RouteShareService.stop(widget.id),
        bi('Sharing stopped', 'பகிர்வு நிறுத்தப்பட்டது'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final live = RouteShareService.live(data);
    final until = _stamp(data['expiresAt']);
    final response = txt(data, 'response', 'pending');
    final stops = routeStops(asMap(data['route']));
    final progress = asMap(data['progress']);
    final done = progress.values.where((v) => asMap(v)['s'] == 'done').length;
    final (badge, color) = !live
        ? (
            data['status'] == 'stopped'
                ? bi('Stopped', 'நிறுத்தப்பட்டது')
                : bi('Ended', 'முடிந்தது'),
            Ink.muted,
          )
        : response == 'accepted'
        ? (bi('Using now', 'பயன்படுத்துகிறார்'), Ink.greenText)
        : response == 'rejected'
        ? (bi('Declined', 'மறுத்தார்'), Ink.redText)
        : (bi('Waiting', 'காத்திருக்கிறது'), Ink.amberText);
    return Glass(
      radius: 27,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('profiles')
                    .doc(txt(data, 'recipientUid'))
                    .snapshots(),
                builder: (context, snap) {
                  final d = snap.data?.data() ?? const <String, dynamic>{};
                  return Expanded(
                    child: Row(
                      children: [
                        profileAvatar(
                          txt(d, 'photo'),
                          radius: 22,
                          label: _profileName(d),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _profileName(d),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Ink.navy,
                                ),
                              ),
                              Text(
                                txt(data, 'routeName'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Ink.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: color.withValues(alpha: .1),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _Tick(
            builder: (_) => Row(
              children: [
                const Icon(CupertinoIcons.clock, size: 16, color: Ink.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: AppText(
                    [
                      if (live && until != null) routeTimeLeft(until),
                      bi(
                        '$done/${stops.length} delivered',
                        '$done/${stops.length} கொடுத்தது',
                      ),
                      if (data['collectLater'] == true)
                        bi('Amounts hidden', 'தொகை மறைப்பு'),
                    ].join(' · '),
                    style: const TextStyle(
                      color: Ink.body,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              if (live) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _stop,
                    icon: const Icon(CupertinoIcons.stop_fill, size: 16),
                    label: Text(bi('Stop now', 'இப்போதே நிறுத்து')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Ink.redText,
                      side: BorderSide(color: Ink.red.withValues(alpha: .4)),
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ] else ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => RouteShareService.remove(widget.id),
                            bi('Removed', 'நீக்கப்பட்டது'),
                          ),
                    icon: const Icon(CupertinoIcons.trash, size: 16),
                    label: Text(bi('Remove', 'நீக்கு')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Ink.muted,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: LiquidButton(
                  label: live
                      ? bi('Extend', 'நீட்டி')
                      : bi('Share again', 'மீண்டும் பகிர்'),
                  icon: CupertinoIcons.clock_fill,
                  height: 46,
                  radius: 23,
                  busy: _busy,
                  onPressed: _busy ? null : _extend,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Routes others lent to this person: new invitations and saved copies.
class _ReceivedRoutes extends StatelessWidget {
  final List<Map<String, dynamic>> saved;
  const _ReceivedRoutes({required this.saved});

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: RouteShareService.incoming(),
    builder: (context, snap) {
      final live = {
        for (final d
            in snap.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
          d.id: d.data(),
      };
      final savedIds = {for (final r in saved) txt(r, 'shareId')};
      final invites = live.entries
          .where(
            (e) =>
                !savedIds.contains(e.key) &&
                e.value['response'] == 'pending' &&
                RouteShareService.live(e.value),
          )
          .toList();
      if (saved.isEmpty && invites.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 13),
          _SectionTitle(bi('Shared with you', 'உங்களுக்குப் பகிர்ந்தவை')),
          for (final e in invites)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Glass(
                radius: 27,
                tint: Ink.lavender,
                onTap: () => push(context, RouteInviteScreen(shareId: e.key)),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.envelope_badge_fill,
                      color: Ink.violetDeep,
                      size: 28,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            txt(e.value, 'routeName'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            bi(
                              'From ${txt(e.value, 'ownerName')} · tap to save or reject',
                              '${txt(e.value, 'ownerName')} அனுப்பியது · சேமிக்க அல்லது மறுக்கத் தொடவும்',
                            ),
                            style: const TextStyle(
                              color: Ink.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: Ink.faint,
                    ),
                  ],
                ),
              ),
            ),
          for (final r in saved)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ReceivedRouteCard(
                route: r,
                remote: live[txt(r, 'shareId')],
                loaded: snap.hasData,
              ),
            ),
        ],
      );
    },
  );
}

class _ReceivedRouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final Map<String, dynamic>? remote;
  final bool loaded;
  const _ReceivedRouteCard({
    required this.route,
    required this.remote,
    required this.loaded,
  });

  @override
  Widget build(BuildContext context) {
    final data = remote;
    // Offline, the saved expiry still ends the loan on time.
    final live = data != null
        ? RouteShareService.live(data)
        : !loaded &&
              (DateTime.tryParse(
                    txt(route, 'expiresAt'),
                  )?.isAfter(DateTime.now()) ??
                  false);
    final until = data == null
        ? DateTime.tryParse(txt(route, 'expiresAt'))
        : _stamp(data['expiresAt']);
    return _RouteCard(
      route: route,
      onOpen: () => push(context, RouteViewScreen(route: route)),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(13, 4, 13, 8),
        child: _Tick(
          builder: (_) => Row(
            children: [
              Expanded(
                child: AppText(
                  [
                    bi(
                      'From ${txt(route, 'ownerName')}',
                      '${txt(route, 'ownerName')} கொடுத்தது',
                    ),
                    if (live && until != null)
                      routeTimeLeft(until)
                    else if (data?['status'] == 'stopped')
                      bi('Stopped by owner', 'உரிமையாளர் நிறுத்தினார்')
                    else
                      bi('Ended', 'முடிந்தது'),
                  ].join(' · '),
                  maxLines: 2,
                  style: TextStyle(
                    color: live ? Ink.body : Ink.redText,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (live)
                SizedBox(
                  width: 112,
                  child: LiquidButton(
                    label: bi('Start', 'தொடங்கு'),
                    icon: CupertinoIcons.play_fill,
                    height: 44,
                    radius: 22,
                    onPressed: () => push(
                      context,
                      RouteRideScreen(shareId: txt(route, 'shareId')),
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: () => VendorRoutes.delete(txt(route, 'id')),
                  child: Text(bi('Remove', 'நீக்கு')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opened from the chat card: preview, then save or reject.
class RouteInviteScreen extends StatefulWidget {
  final String shareId;
  const RouteInviteScreen({super.key, required this.shareId});
  @override
  State<RouteInviteScreen> createState() => _RouteInviteScreenState();
}

class _RouteInviteScreenState extends State<RouteInviteScreen> {
  bool _busy = false;

  Future<void> _answer(Map<String, dynamic> data, bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await RouteShareService.respond(widget.shareId, accept);
      if (accept) await RouteShareService.saveCopy(widget.shareId, data);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      snack(
        context,
        accept
            ? bi(
                'Saved to your route maps',
                'உங்கள் பாதை வரைபடங்களில் சேமிக்கப்பட்டது',
              )
            : bi('Route rejected', 'பாதை மறுக்கப்பட்டது'),
      );
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(title: Text(bi('Shared route', 'பகிர்ந்த பாதை'))),
    body: Shell(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: RouteShareService.watch(widget.shareId),
        builder: (context, snap) {
          if (snap.hasError) {
            return _Centered(
              icon: CupertinoIcons.lock_fill,
              text: bi(
                'This route is not shared with you, or it was removed.',
                'இந்தப் பாதை உங்களுக்குப் பகிரப்படவில்லை, அல்லது நீக்கப்பட்டது.',
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CupertinoActivityIndicator());
          }
          final data = snap.data!.data();
          if (data == null) {
            return _Centered(
              icon: CupertinoIcons.map,
              text: bi('This route was removed.', 'இந்தப் பாதை நீக்கப்பட்டது.'),
            );
          }
          if (data['ownerUid'] == signedInUid) {
            return ListView(
              padding: const EdgeInsets.all(21),
              children: [RouteShareOwnerCard(id: widget.shareId, data: data)],
            );
          }
          final route = {
            ...asMap(data['route']),
            'name': txt(data, 'routeName'),
          };
          final live = RouteShareService.live(data);
          final until = _stamp(data['expiresAt']);
          final response = txt(data, 'response', 'pending');
          return ListView(
            padding: const EdgeInsets.fromLTRB(21, 8, 21, 40),
            children: [
              _RouteCard(
                route: route,
                onOpen: () => push(context, RouteViewScreen(route: route)),
              ),
              const SizedBox(height: 16),
              Glass(
                radius: 27,
                child: _Tick(
                  builder: (_) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bi(
                          '${txt(data, 'ownerName')} lent you this route',
                          '${txt(data, 'ownerName')} இந்தப் பாதையை உங்களுக்குக் கொடுத்துள்ளார்',
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: Ink.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppText(
                        [
                          if (live && until != null)
                            routeTimeLeft(until)
                          else if (data['status'] == 'stopped')
                            bi('Stopped by owner', 'உரிமையாளர் நிறுத்தினார்')
                          else
                            bi('Ended', 'முடிந்தது'),
                          bi(
                            '${routeStops(route).length} homes',
                            '${routeStops(route).length} வீடுகள்',
                          ),
                          if (data['collectLater'] == true)
                            bi(
                              'Owner collects money later',
                              'உரிமையாளர் பிறகு பணம் வாங்குவார்',
                            ),
                        ].join(' · '),
                        style: TextStyle(
                          color: live ? Ink.body : Ink.redText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 21),
              if (!live)
                const SizedBox.shrink()
              else if (response == 'pending')
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: bi('Reject', 'மறு'),
                        icon: CupertinoIcons.xmark,
                        color: Ink.redText,
                        onPressed: _busy ? null : () => _answer(data, false),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: LiquidButton(
                        label: bi('Save', 'சேமி'),
                        icon: CupertinoIcons.tray_arrow_down_fill,
                        busy: _busy,
                        onPressed: _busy ? null : () => _answer(data, true),
                      ),
                    ),
                  ],
                )
              else if (response == 'accepted')
                LiquidButton(
                  label: bi('Start route', 'பாதையைத் தொடங்கு'),
                  icon: CupertinoIcons.play_fill,
                  height: 56,
                  radius: 28,
                  onPressed: () async {
                    if (VendorRoutes.byId('recv_${widget.shareId}') == null) {
                      await RouteShareService.saveCopy(widget.shareId, data);
                    }
                    if (context.mounted) {
                      await push(
                        context,
                        RouteRideScreen(shareId: widget.shareId),
                      );
                    }
                  },
                )
              else
                Text(
                  bi(
                    'You rejected this route.',
                    'நீங்கள் இந்தப் பாதையை மறுத்தீர்கள்.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Ink.muted),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _Centered extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Centered({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Ink.faint),
          const SizedBox(height: 13),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Ink.muted, fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
//  Delivering a lent route
// -----------------------------------------------------------------------------

/// The lent-route delivery screen: map on top, one big home card below, and
/// every home as a chip so homes can be done in any order.
class RouteRideScreen extends StatefulWidget {
  final String shareId;
  const RouteRideScreen({super.key, required this.shareId});
  @override
  State<RouteRideScreen> createState() => _RouteRideScreenState();
}

class _RouteRideScreenState extends State<RouteRideScreen> {
  final _map = fm.MapController();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _watch;
  late final Map<String, dynamic> _route =
      VendorRoutes.byId('recv_${widget.shareId}') ?? {};
  late final Map<String, Map<String, dynamic>> _progress = {
    for (final e in asMap(_route['progress']).entries) e.key: asMap(e.value),
  };
  String? _selected;
  bool _ready = false, _ended = false, _stopped = false;
  ll.LatLng? _me;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    _checkExpiry();
    _expiry = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkExpiry(),
    );
    if (firebaseReady && signedInUid.isNotEmpty) {
      _watch = RouteShareService.watch(widget.shareId).listen((snap) {
        final data = snap.data();
        if (data == null) {
          _end(stopped: true);
          return;
        }
        if (!RouteShareService.live(data)) {
          _end(stopped: data['status'] == 'stopped');
          return;
        }
        final until = _stamp(data['expiresAt']);
        if (until != null && mounted) {
          setState(() => _route['expiresAt'] = until.toIso8601String());
          unawaited(VendorRoutes.save(_route));
        }
      }, onError: (Object _) => _end(stopped: true));
    }
  }

  void _checkExpiry() {
    final until = DateTime.tryParse(txt(_route, 'expiresAt'));
    if (until != null && !until.isAfter(DateTime.now())) _end();
  }

  void _end({bool stopped = false}) {
    if (_ended || !mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _ended = true;
      _stopped = stopped;
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    _expiry?.cancel();
    _map.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _stops => routeStops(_route);

  String? get _currentId {
    final chosen = _selected;
    if (chosen != null && !_progress.containsKey(chosen)) return chosen;
    return _stops
        .where((s) => !_progress.containsKey(txt(s, 'id')))
        .map((s) => txt(s, 'id'))
        .firstOrNull;
  }

  Map<String, StopState> get _states => {
    for (final s in _stops)
      txt(s, 'id'): switch (_progress[txt(s, 'id')]?['s']) {
        'done' => StopState.done,
        'skipped' => StopState.skipped,
        _ => txt(s, 'id') == _currentId ? StopState.current : StopState.pending,
      },
  };

  void _select(String id) {
    setState(() => _selected = id);
    final stop = _stops.where((s) => s['id'] == id).firstOrNull;
    final point = stop == null ? null : personPoint(stop);
    if (point != null && _ready) _map.move(point, 18);
  }

  double _litres(Map<String, dynamic> stop) =>
      numv(_progress[txt(stop, 'id')] ?? {}, 'q', numv(stop, 'litres', 1));

  Future<void> _mark(Map<String, dynamic> stop, String state) async {
    if (_ended) return;
    final id = txt(stop, 'id');
    HapticFeedback.mediumImpact();
    setState(() {
      _progress[id] = {
        's': state,
        'q': _pendingLitres[id] ?? numv(stop, 'litres', 1),
        't': DateTime.now().toIso8601String(),
      };
      _pendingLitres.remove(id);
      _selected = null;
    });
    _route['progress'] = _progress;
    await VendorRoutes.save(_route);
    final next = _currentId;
    final point = next == null
        ? null
        : personPoint(_stops.firstWhere((s) => s['id'] == next));
    if (point != null && _ready) _map.move(point, 17.5);
    try {
      await RouteShareService.progress(widget.shareId, _progress);
    } catch (_) {
      /* Progress is also kept on the phone; the next mark retries. */
    }
  }

  Future<void> _undo(String id) async {
    setState(() => _progress.remove(id));
    _route['progress'] = _progress;
    await VendorRoutes.save(_route);
    try {
      await RouteShareService.progress(widget.shareId, _progress);
    } catch (_) {}
  }

  final Map<String, double> _pendingLitres = {};

  Future<void> _locate() async {
    final here = await VendorLocation.current(context);
    if (here == null || !mounted) return;
    setState(() => _me = here);
    if (_ready) _map.move(here, math.max(_map.camera.zoom, 17));
  }

  @override
  Widget build(BuildContext context) {
    if (_route.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: _Centered(
          icon: CupertinoIcons.map,
          text: bi('Save the route first.', 'முதலில் பாதையைச் சேமிக்கவும்.'),
        ),
      );
    }
    final stops = _stops;
    final currentId = _currentId;
    final current = stops.where((s) => s['id'] == currentId).firstOrNull;
    final done = _progress.values.where((v) => v['s'] == 'done').length;
    final extent = routeExtent(_route);
    final size = MediaQuery.sizeOf(context);
    final hideMoney = _route['collectLater'] == true;
    final until = DateTime.tryParse(txt(_route, 'expiresAt'));
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      body: Stack(
        children: [
          Column(
            children: [
              // Golden split: the map takes the minor share of the height.
              SizedBox(
                height: size.height * Gold.minor + 24,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: VimoMap(
                        controller: _map,
                        center: current == null ? null : personPoint(current),
                        zoom: 17.5,
                        fit: extent,
                        onReady: () => _ready = true,
                        layers: routeLayers(
                          _route,
                          states: _states,
                          me: _me,
                          onStop: (s) => _select(txt(s, 'id')),
                          onNote: (n) => showRouteNote(context, n),
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 10,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          _MapButton(
                            icon: CupertinoIcons.xmark,
                            tooltip: ui('Close'),
                            color: Ink.navy,
                            onTap: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          if (until != null)
                            Glass(
                              radius: 20,
                              opacity: .86,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 9,
                              ),
                              child: _Tick(
                                builder: (_) => AppText(
                                  '${routeTimeLeft(until)} · $done/${stops.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Ink.navy,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          _MapButton(
                            icon: CupertinoIcons.location_fill,
                            tooltip: bi('My location', 'என் இடம்'),
                            color: Ink.blue,
                            onTap: _locate,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -24),
                  child: DecoratedBox(
                    decoration: const ShapeDecoration(
                      color: Ink.canvasTop,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(34),
                        ),
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 21, 16, 34),
                      children: [
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: stops.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final s = stops[i];
                              final state = _states[txt(s, 'id')]!;
                              return _StopChip(
                                number: i + 1,
                                name: txt(s, 'name'),
                                state: state,
                                onTap:
                                    state == StopState.pending ||
                                        state == StopState.current
                                    ? () => _select(txt(s, 'id'))
                                    : () => _undo(txt(s, 'id')),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : Gold.slow,
                          switchInCurve: Gold.ease,
                          switchOutCurve: Gold.easeIn,
                          transitionBuilder: (child, a) => FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(.08, 0),
                                end: Offset.zero,
                              ).animate(a),
                              child: child,
                            ),
                          ),
                          child: current == null
                              ? Glass(
                                  key: const ValueKey('all-done'),
                                  radius: 30,
                                  child: Column(
                                    children: [
                                      const Icon(
                                        CupertinoIcons.check_mark_circled_solid,
                                        color: Ink.green,
                                        size: 55,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        bi(
                                          'Every home is done',
                                          'அனைத்து வீடுகளும் முடிந்தது',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        bi(
                                          '$done of ${stops.length} delivered. The owner sees this too.',
                                          '${stops.length}-ல் $done கொடுக்கப்பட்டது. உரிமையாளருக்கும் தெரியும்.',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Ink.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _HomeCard(
                                  key: ValueKey(currentId),
                                  stop: current,
                                  number: stops.indexOf(current) + 1,
                                  litres:
                                      _pendingLitres[currentId] ??
                                      _litres(current),
                                  hideMoney: hideMoney,
                                  notes: routeNotes(_route)
                                      .where((n) => n['stopId'] == currentId)
                                      .toList(),
                                  onLitres: (v) => setState(
                                    () => _pendingLitres[currentId!] = v,
                                  ),
                                  onDone: () => _mark(current, 'done'),
                                  onSkip: () => _mark(current, 'skipped'),
                                ),
                        ),
                        const SizedBox(height: 16),
                        for (final n in routeNotes(
                          _route,
                        ).where((n) => txt(n, 'stopId').isEmpty))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Glass(
                              radius: 21,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              onTap: () {
                                final p = personPoint(n);
                                if (p != null && _ready) _map.move(p, 18);
                                showRouteNote(context, n);
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    routeNoteIcon(n),
                                    color: Ink.amberText,
                                    size: 19,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      txt(
                                        n,
                                        'text',
                                        bi('Path note', 'பாதைக் குறிப்பு'),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(
                                    CupertinoIcons.chevron_right,
                                    size: 14,
                                    color: Ink.faint,
                                  ),
                                ],
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
          if (_ended)
            Positioned.fill(
              child: ColoredBox(
                color: Ink.navy.withValues(alpha: .38),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(34),
                    child: Glass(
                      radius: 34,
                      opacity: .94,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _stopped
                                ? CupertinoIcons.hand_raised_fill
                                : CupertinoIcons.clock_fill,
                            color: Ink.redText,
                            size: 48,
                          ),
                          const SizedBox(height: 13),
                          Text(
                            _stopped
                                ? bi(
                                    '${txt(_route, 'ownerName')} stopped this map',
                                    '${txt(_route, 'ownerName')} இந்த வரைபடத்தை நிறுத்தினார்',
                                  )
                                : bi(
                                    'The shared time is over',
                                    'பகிர்வு நேரம் முடிந்தது',
                                  ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              color: Ink.navy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            bi(
                              'Deliveries you marked were sent to the owner.',
                              'நீங்கள் குறித்த விநியோகங்கள் உரிமையாளருக்கு அனுப்பப்பட்டன.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Ink.muted),
                          ),
                          const SizedBox(height: 21),
                          LiquidButton(
                            label: 'OK',
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StopChip extends StatelessWidget {
  final int number;
  final String name;
  final StopState state;
  final VoidCallback onTap;
  const _StopChip({
    required this.number,
    required this.name,
    required this.state,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final current = state == StopState.current;
    final color = switch (state) {
      StopState.done => Ink.greenText,
      StopState.skipped => Ink.redText,
      StopState.current => Colors.white,
      StopState.pending => Ink.navy,
    };
    return Pressable(
      radius: 22,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Gold.base,
        curve: Gold.ease,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: .9)),
          ),
          gradient: current
              ? const LinearGradient(colors: [Ink.violet, Ink.violetDeep])
              : null,
          color: current
              ? null
              : switch (state) {
                  StopState.done => Ink.green.withValues(alpha: .12),
                  StopState.skipped => Ink.red.withValues(alpha: .1),
                  _ => Colors.white.withValues(alpha: .7),
                },
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == StopState.done)
              Icon(Icons.check_rounded, size: 16, color: color)
            else if (state == StopState.skipped)
              Icon(CupertinoIcons.forward_fill, size: 13, color: color)
            else
              Text(
                '$number',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final Map<String, dynamic> stop;
  final int number;
  final double litres;
  final bool hideMoney;
  final List<Map<String, dynamic>> notes;
  final ValueChanged<double> onLitres;
  final VoidCallback onDone, onSkip;
  const _HomeCard({
    super.key,
    required this.stop,
    required this.number,
    required this.litres,
    required this.hideMoney,
    required this.notes,
    required this.onLitres,
    required this.onDone,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final price = numv(stop, 'price');
    final due = numv(stop, 'due');
    final today = litres * price;
    return Glass(
      radius: 34,
      padding: const EdgeInsets.all(21),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _HomePin(
                number: number,
                label: txt(stop, 'name'),
                state: StopState.current,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txt(stop, 'name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Ink.navy,
                        letterSpacing: -.4,
                      ),
                    ),
                    Text(
                      txt(stop, 'place'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Ink.muted, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 21),
          Row(
            children: [
              _StepButton(
                icon: CupertinoIcons.minus,
                onTap: litres <= .25
                    ? null
                    : () => onLitres(math.max(.25, litres - .25)),
              ),
              Expanded(
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: Gold.fast,
                      child: AppText(
                        '${vendorFieldNumber(litres)} L',
                        key: ValueKey(litres),
                        style: const TextStyle(
                          fontSize: 43,
                          fontWeight: FontWeight.w800,
                          color: Ink.violetDeep,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    Text(
                      bi('Milk to give', 'கொடுக்க வேண்டிய பால்'),
                      style: const TextStyle(color: Ink.muted),
                    ),
                  ],
                ),
              ),
              _StepButton(
                icon: CupertinoIcons.plus,
                onTap: litres >= 50 ? null : () => onLitres(litres + .25),
              ),
            ],
          ),
          if (!hideMoney && price > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: ShapeDecoration(
                shape: const SquircleBorder(radius: 21),
                color: Ink.green.withValues(alpha: .08),
              ),
              child: Column(
                children: [
                  _TotalLine(label: bi('Today', 'இன்று'), value: money(today)),
                  if (due > .001) ...[
                    const SizedBox(height: 4),
                    _TotalLine(
                      label: bi('Balance', 'நிலுவை'),
                      value: money(due),
                    ),
                  ],
                  const Divider(height: 16),
                  _TotalLine(
                    label: bi('Collect', 'வாங்க வேண்டியது'),
                    value: money(today + due),
                    strong: true,
                  ),
                ],
              ),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in notes)
                  ActionChip(
                    avatar: Icon(
                      routeNoteIcon(n),
                      size: 16,
                      color: Ink.amberText,
                    ),
                    label: Text(
                      txt(n, 'text', bi('Open note', 'குறிப்பைத் திற')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => showRouteNote(context, n),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 21),
          Row(
            children: [
              Expanded(
                flex: 382,
                child: GhostButton(
                  label: bi('Skip', 'தவிர்'),
                  icon: CupertinoIcons.forward_fill,
                  color: Ink.redText,
                  onPressed: onSkip,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 618,
                child: LiquidButton(
                  label: bi('Delivered', 'கொடுத்தாச்சு'),
                  icon: CupertinoIcons.checkmark_alt,
                  start: const Color(0xFF52C483),
                  end: Ink.green,
                  height: 56,
                  radius: 28,
                  onPressed: onDone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 55,
    child: Glass(
      radius: 27,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Icon(
        icon,
        color: onTap == null ? Ink.faint : Ink.violetDeep,
        size: 24,
      ),
    ),
  );
}
