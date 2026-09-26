part of 'main.dart';

const _rideVolume = MethodChannel('vimo/vendor_volume');

bool vendorScheduled(Map<String, dynamic> p, DateTime date, String session) {
  final days = (p['days'] as List?) ?? [];
  final storedSessions = (p['sessions'] as List?) ?? [];
  final sessions = storedSessions.isEmpty
      ? ['Morning', 'Evening']
      : storedSessions;
  return (days.isEmpty || days.contains(date.weekday % 7)) &&
      sessions.contains(session);
}

DateTime vendorPaymentDate(Map<String, dynamic> p, DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final cycle = txt(p, 'paymentCycle', 'Daily');
  if (cycle == 'Monthly') {
    final target = numv(p, 'paymentMonthDay', 1).toInt().clamp(1, 31);
    DateTime inMonth(int year, int month) => DateTime(
      year,
      month,
      math.min(target, DateTime(year, month + 1, 0).day),
    );
    final current = inMonth(day.year, day.month);
    return current.isBefore(day) ? inMonth(day.year, day.month + 1) : current;
  }
  if (cycle == 'Every 2 days') {
    final anchor = DateTime.tryParse(txt(p, 'createdAt')) ?? day;
    return day.add(
      Duration(
        days:
            day
                .difference(DateTime(anchor.year, anchor.month, anchor.day))
                .inDays
                .abs() %
            2,
      ),
    );
  }
  if (cycle == 'Daily') return day;
  final days = (p['paymentDays'] as List?) ?? (cycle == 'Weekly' ? [0] : []);
  if (days.isEmpty) return day;
  for (var i = 0; i < 7; i++) {
    final candidate = day.add(Duration(days: i));
    if (days.contains(candidate.weekday % 7)) return candidate;
  }
  return day;
}

double vendorUsualQuantity(
  Map<String, dynamic> p,
  String session,
  Iterable<Map<String, dynamic>> rows,
) {
  if (p.containsKey('quantity')) return numv(p, 'quantity');
  final matches =
      rows
          .where(
            (r) =>
                r['personId'] == p['id'] &&
                r['session'] == session &&
                numv(r, 'quantity') > 0,
          )
          .toList()
        ..sort((a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')));
  return matches.isEmpty ? 1 : numv(matches.first, 'quantity');
}

List<Map<String, dynamic>> vendorRoutePeople(
  Iterable<Map<String, dynamic>> people,
  Iterable<Map<String, dynamic>> rows,
  DateTime date,
  String session, {
  bool suppliers = false,
}) {
  final list = people
      .where(
        (p) =>
            p['kind'] == (suppliers ? 'supplier' : 'customer') &&
            (suppliers || vendorScheduled(p, date, session)),
      )
      .toList();
  final key = '${date.weekday % 7}';
  double volume(Map<String, dynamic> p) => rows
      .where(
        (r) =>
            r['personId'] == p['id'] &&
            r['session'] == session &&
            ['collection', 'purchase'].contains(r['kind']),
      )
      .fold(0.0, (s, r) => s + numv(r, 'quantity'));
  int frequency(Map<String, dynamic> p) => rows
      .where(
        (r) =>
            r['personId'] == p['id'] &&
            r['session'] == session &&
            ['collection', 'purchase'].contains(r['kind']),
      )
      .length;
  list.sort((a, b) {
    if (suppliers) {
      final f = frequency(b).compareTo(frequency(a));
      if (f != 0) return f;
      final v = volume(b).compareTo(volume(a));
      if (v != 0) return v;
    } else {
      final ar = asMap(a['routeOrder'])[key] as num?;
      final br = asMap(b['routeOrder'])[key] as num?;
      final order = (ar ?? 100000).compareTo(br ?? 100000);
      if (order != 0) return order;
    }
    return txt(a, 'name').toLowerCase().compareTo(txt(b, 'name').toLowerCase());
  });
  return list;
}

class VendorWeekRow extends StatelessWidget {
  final Set<int> days;
  final ValueChanged<Set<int>> onChanged;
  final bool daily;
  const VendorWeekRow({
    super.key,
    required this.days,
    required this.onChanged,
    this.daily = false,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        flex: 2,
        child: _VendorPill(
          label: daily ? bi('Daily', 'தினமும்') : bi('All week', 'வாரம்'),
          selected: days.length == 7,
          onTap: () => onChanged(days.length == 7 ? {} : {0, 1, 2, 3, 4, 5, 6}),
        ),
      ),
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Tooltip(
              message: tamilUi ? _dayTamil[i] : _dayNames[i],
              child: _VendorPill(
                label: tamilUi
                    ? ['ஞா', 'தி', 'செ', 'பு', 'வி', 'வெ', 'ச'][i]
                    : _dayNames[i][0],
                selected: days.contains(i),
                onTap: () {
                  final next = {...days};
                  next.contains(i) ? next.remove(i) : next.add(i);
                  onChanged(next);
                },
              ),
            ),
          ),
        ),
    ],
  );
}

class _VendorPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _VendorPill({required this.label, required this.selected, this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: ShapeDecoration(
        color: selected ? Ink.violetDeep : Colors.white.withValues(alpha: .58),
        shape: const SquircleBorder(radius: 16),
      ),
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: selected ? Colors.white : Ink.body,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 5),
        ),
        onPressed: onTap,
        child: FittedBox(
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
  );
}

class VendorPersonForm extends StatefulWidget {
  final String kind;
  final Map<String, dynamic>? person;
  const VendorPersonForm({super.key, this.kind = 'customer', this.person});
  @override
  State<VendorPersonForm> createState() => _VendorPersonFormState();
}

class _VendorPersonFormState extends State<VendorPersonForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.person?['name']);
  late final _place = TextEditingController(text: widget.person?['place']);
  late final _contact = TextEditingController(text: widget.person?['contact']);
  late final _quantity = TextEditingController(
    text: '${widget.person?['quantity'] ?? 1}',
  );
  late final _price = TextEditingController(
    text: '${widget.person?['price'] ?? defaultMilkPrice()}',
  );
  late String _kind = widget.person?['kind'] ?? widget.kind;
  late String _cycle = widget.person?['paymentCycle'] ?? 'Daily';
  late String _photo = txt(widget.person ?? {}, 'imageData');
  late Set<int> _days = ((widget.person?['days'] as List?) ?? [])
      .cast<int>()
      .toSet();
  late Set<int> _paymentDays =
      ((widget.person?['paymentDays'] as List?) ?? [0, 1, 2, 3, 4, 5, 6])
          .cast<int>()
          .toSet();
  late final Set<String> _sessions =
      ((widget.person?['sessions'] as List?) ?? ['Morning', 'Evening'])
          .cast<String>()
          .toSet();
  late int _monthDay = numv(widget.person ?? {}, 'paymentMonthDay', 1).toInt();
  bool _saving = false, _picking = false;
  @override
  void dispose() {
    for (final c in [_name, _place, _contact, _quantity, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving || !canRecordEntries) return;
    if (_sessions.isEmpty) {
      snack(
        context,
        bi('Choose a delivery time', 'நேரத்தைத் தேர்ந்தெடுக்கவும்'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final id =
          widget.person?['id'] ??
          '${settingText('deviceId', 'device')}_${now.microsecondsSinceEpoch}';
      final data = <String, dynamic>{
        ...?widget.person,
        'id': id,
        'cloudId': widget.person?['cloudId'] ?? id,
        'kind': _kind,
        'name': _name.text.trim(),
        'place': _place.text.trim(),
        'contact': _contact.text.trim(),
        'imageData': _photo,
        'quantity': toDouble(_quantity.text),
        'price': toDouble(_price.text),
        'days': _days.toList()..sort(),
        'sessions': _sessions.toList(),
        'paymentCycle': _cycle,
        'paymentDays': _paymentDays.toList()..sort(),
        'paymentMonthDay': _monthDay,
        'createdAt': widget.person?['createdAt'] ?? now.toIso8601String(),
        'updatedAtMillis': now.millisecondsSinceEpoch,
      };
      data.remove('_key');
      await Hive.box('vendor_people').put(widget.person?['_key'] ?? id, data);
      AutoSyncService.markDirty(reason: 'vendor person');
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _number(TextEditingController c, String label) => TextFormField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: fieldStyle(label),
    validator: (v) =>
        double.tryParse(v ?? '') == null ||
            !toDouble(v!).isFinite ||
            toDouble(v) <= 0
        ? bi('Enter a positive number', 'சரியான எண்ணை உள்ளிடவும்')
        : null,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    appBar: AppBar(
      title: AppText(widget.person == null ? 'Add person' : 'Edit person'),
    ),
    body: Shell(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(21, 12, 21, 40),
          children: [
            Center(
              child: TextButton(
                onPressed: _picking
                    ? null
                    : () async {
                        setState(() => _picking = true);
                        try {
                          final photo = await pickImageDataUrl();
                          if (context.mounted && photo != null) {
                            setState(() => _photo = photo);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            snack(
                              context,
                              bi(
                                'Could not open photo',
                                'படத்தைத் திறக்க முடியவில்லை',
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _picking = false);
                        }
                      },
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundImage: animalImage({'imageData': _photo}),
                      child: _photo.isEmpty
                          ? const Icon(CupertinoIcons.camera_fill, size: 28)
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(bi('Photo · optional', 'புகைப்படம் · விருப்பம்')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: fieldStyle(bi('Name', 'பெயர்')),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? ui('Enter a name') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _place,
              maxLength: 160,
              decoration: fieldStyle(bi('Place', 'இடம்')),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? bi('Enter a place', 'இடத்தை உள்ளிடவும்')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contact,
              maxLength: 40,
              keyboardType: TextInputType.phone,
              decoration: fieldStyle(
                bi('Contact · optional', 'தொடர்பு · விருப்பம்'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final kind in ['supplier', 'customer'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: _VendorPill(
                        label: kind == 'supplier'
                            ? bi('Milk provider', 'பால் கொடுப்பவர்')
                            : bi('Milk buyer', 'பால் வாங்குபவர்'),
                        selected: _kind == kind,
                        onTap: widget.person != null
                            ? null
                            : () => setState(() => _kind = kind),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              bi('Milk days · optional', 'பால் நாட்கள் · விருப்பம்'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            VendorWeekRow(
              days: _days,
              onChanged: (d) => setState(() => _days = d),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                for (final s in ['Morning', 'Evening'])
                  FilterChip(
                    showCheckmark: false,
                    label: AppText(s),
                    selected: _sessions.contains(s),
                    onSelected: (v) => setState(() {
                      v ? _sessions.add(s) : _sessions.remove(s);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _number(_quantity, bi('Milk quantity (L)', 'பால் அளவு (லி)')),
            const SizedBox(height: 16),
            _number(_price, bi('Price per litre', 'லிட்டருக்கான விலை')),
            const SizedBox(height: 24),
            Text(
              bi('Payment days', 'பணம் செலுத்தும் நாட்கள்'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            VendorWeekRow(
              daily: true,
              days: _cycle == 'Daily' ? {0, 1, 2, 3, 4, 5, 6} : _paymentDays,
              onChanged: (d) => setState(() {
                _paymentDays = d;
                _cycle = d.length == 7 || d.isEmpty
                    ? 'Daily'
                    : d.length == 1
                    ? 'Weekly'
                    : 'Flexible';
              }),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final cycle in ['Weekly', 'Monthly'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: _VendorPill(
                        label: cycle == 'Weekly'
                            ? bi('Weekly once', 'வாரம் ஒருமுறை')
                            : bi('Monthly once', 'மாதம் ஒருமுறை'),
                        selected: _cycle == cycle,
                        onTap: () => setState(() {
                          _cycle = cycle;
                          if (cycle == 'Weekly' && _paymentDays.length != 1) {
                            _paymentDays = {DateTime.now().weekday % 7};
                          }
                        }),
                      ),
                    ),
                  ),
              ],
            ),
            if (_cycle == 'Weekly') ...[
              const SizedBox(height: 10),
              VendorWeekRow(
                days: _paymentDays,
                onChanged: (d) => setState(() {
                  final added = d.difference(_paymentDays);
                  _paymentDays = added.isEmpty ? {0} : {added.first};
                }),
              ),
            ],
            if (_cycle == 'Monthly') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _monthDay,
                decoration: fieldStyle(bi('Day of month', 'மாதத்தின் நாள்')),
                items: [
                  for (var d = 1; d <= 31; d++)
                    DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (d) => setState(() => _monthDay = d!),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _saving ? bi('Saving…', 'சேமிக்கிறது…') : ui('Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class VendorRideScreen extends StatefulWidget {
  const VendorRideScreen({super.key});
  @override
  State<VendorRideScreen> createState() => _VendorRideScreenState();
}

class _VendorRideScreenState extends State<VendorRideScreen>
    with WidgetsBindingObserver, RouteAware {
  String _session = DateTime.now().hour < 12 ? 'Morning' : 'Evening';
  String _rideId = '';
  String _rideDate = '';
  List<String> _supplyIds = [];
  List<Map<String, dynamic>> _stops = [];
  Set<String> _done = {}, _skipped = {};
  String? _editing;
  bool _busy = false, _hint = false, _volume = false;
  Timer? _hintTimer;
  final _qty = TextEditingController(),
      _price = TextEditingController(),
      _paid = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {};
  String get _storageKey =>
      'vendorRide_${settingText('ranchId', '')}_$_profileKey';
  bool get _active => _rideId.isNotEmpty;
  @override
  void initState() {
    super.initState();
    vendorWorkspaceRevision.addListener(_workspaceChanged);
    WidgetsBinding.instance.addObserver(this);
    final saved = asMap(Hive.box('settings').get(_storageKey));
    if (txt(saved, 'id').isNotEmpty && saved['date'] == todayDate()) {
      _supplyIds = ((saved['supplies'] as List?) ?? []).cast<String>().toList();
      _rideId = txt(saved, 'id');
      _rideDate = txt(saved, 'date');
      _session = txt(saved, 'session', _session);
      _stops = ((saved['stops'] as List?) ?? []).map(asMap).toList();
      _done = ((saved['done'] as List?) ?? []).cast<String>().toSet();
      _skipped = ((saved['skipped'] as List?) ?? []).cast<String>().toSet();
    }
    _volume =
        Hive.box(
          'settings',
        ).get('${_storageKey}_volume', defaultValue: false) ==
        true;
    _rideVolume.setMethodCallHandler((call) async {
      if (!_active ||
          !_volume ||
          _busy ||
          !(ModalRoute.of(context)?.isCurrent ?? false) ||
          !_visible) {
        return;
      }
      final p = _current;
      if (p == null) return;
      if (call.method == 'up') {
        await _complete(p);
      }
      if (call.method == 'down') {
        await _skip(p);
      }
    });
    HardwareKeyboard.instance.addHandler(_keyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVolume());
  }

  bool get _visible {
    final shell = context.findAncestorStateOfType<_MainShellState>();
    return shell == null || navigationOrder()[shell._tab] == 'Vendor';
  }

  bool _keyEvent(KeyEvent event) {
    if (!_active ||
        !_volume ||
        _busy ||
        !_visible ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    final p = _current;
    if (p == null || event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      unawaited(_complete(p));
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      unawaited(_skip(p));
      return true;
    }
    return false;
  }

  Future<void> _syncVolume({bool enabled = true}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _rideVolume.invokeMethod(
        'enabled',
        enabled &&
            _active &&
            _volume &&
            _visible &&
            (ModalRoute.of(context)?.isCurrent ?? false),
      );
    } on MissingPluginException {
      /* Older native clients keep touch controls. */
    }
  }

  void _workspaceChanged() => unawaited(_syncVolume());
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() => unawaited(_syncVolume(enabled: false));
  @override
  void didPopNext() => unawaited(_syncVolume());
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      unawaited(_syncVolume(enabled: state == AppLifecycleState.resumed));
  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    vendorWorkspaceRevision.removeListener(_workspaceChanged);
    _hintTimer?.cancel();
    _scroll.dispose();
    _qty.dispose();
    _price.dispose();
    _paid.dispose();
    HardwareKeyboard.instance.removeHandler(_keyEvent);
    WidgetsBinding.instance.removeObserver(this);
    _rideVolume.setMethodCallHandler(null);
    unawaited(_syncVolume(enabled: false));
    super.dispose();
  }

  Map<String, dynamic>? get _current => _stops
      .where(
        (p) =>
            !_done.contains(txt(p, 'id')) && !_skipped.contains(txt(p, 'id')),
      )
      .firstOrNull;
  Future<void> _persist() => Hive.box('settings').put(_storageKey, {
    'id': _rideId,
    'date': _rideDate,
    'session': _session,
    'supplies': _supplyIds,
    'stops': _stops.map((p) => {...p}..remove('_key')).toList(),
    'done': _done.toList(),
    'skipped': _skipped.toList(),
  });
  DateTime get _date => DateTime.tryParse(_rideDate) ?? DateTime.now();
  Future<void> _start(
    List<Map<String, dynamic>> people,
    List<Map<String, dynamic>> rows,
  ) async {
    if (!canRecordEntries || _busy) return;
    final date = todayDate();
    // A completed delivery in the selected session cannot be delivered twice by restarting a ride.
    final completed = rows
        .where(
          (r) =>
              r['kind'] == 'sale' &&
              r['date'] == date &&
              r['session'] == _session,
        )
        .map((r) => r['personId'])
        .toSet();
    final stops = people
        .where((p) => !completed.contains(p['id']))
        .map(
          (p) => <String, dynamic>{
            ...p,
            'quantity': vendorUsualQuantity(p, _session, rows),
            'price': numv(p, 'price', defaultMilkPrice()),
          },
        )
        .toList();
    if (stops.isEmpty) {
      snack(
        context,
        bi(
          'No customers due for this ride',
          'இந்த நேரத்திற்கு வாடிக்கையாளர்கள் இல்லை',
        ),
      );
      return;
    }
    setState(() {
      _rideId =
          'ride_${settingText('deviceId', 'device')}_${DateTime.now().microsecondsSinceEpoch}';
      _supplyIds = rows
          .where(
            (r) =>
                r['date'] == date &&
                r['session'] == _session &&
                ['collection', 'purchase'].contains(r['kind']),
          )
          .map((r) => txt(r, 'cloudId'))
          .where((id) => id.isNotEmpty)
          .toList();
      _rideDate = date;
      _stops = stops;
      _done = {};
      _skipped = {};
      _editing = null;
      _hint = !MediaQuery.disableAnimationsOf(context);
    });
    await _persist();
    await _syncVolume();
    _revealCurrent();
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  void _revealCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[txt(_current ?? {}, 'id')]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: .2,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _entryId(Map<String, dynamic> p) => '${_rideId}_${txt(p, 'id')}';
  Future<void> _complete(Map<String, dynamic> p, {bool edited = false}) async {
    if (_busy ||
        !_active ||
        _done.contains(txt(p, 'id')) ||
        _skipped.contains(txt(p, 'id'))) {
      return;
    }
    final rows = vendorRows('vendor_entries');
    final id = _entryId(p);
    final existing = rows.where((r) => r['cloudId'] == id).firstOrNull;
    final quantity = edited ? toDouble(_qty.text) : numv(p, 'quantity');
    final price = edited
        ? toDouble(_price.text)
        : numv(p, 'price', defaultMilkPrice());
    final due = vendorPersonDue(txt(p, 'id'), rows);
    final payable = vendorPaymentDate(
      p,
      _date,
    ).isAtSameMomentAs(DateTime(_date.year, _date.month, _date.day));
    final total = quantity * price;
    final paid = edited
        ? toDouble(_paid.text)
        : payable
        ? total + due
        : 0.0;
    if (!quantity.isFinite ||
        quantity <= 0 ||
        !price.isFinite ||
        price <= 0 ||
        !paid.isFinite ||
        paid < 0 ||
        paid > total + due + .001) {
      snack(
        context,
        bi(
          'Check litres, price and payment',
          'அளவு, விலை, பணத்தைச் சரிபார்க்கவும்',
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // Persist the exact draft before writing. Retries use identical IDs and terms.
      if (existing == null) {
        p['quantity'] = quantity;
        p['price'] = price;
        p['ridePaid'] = paid;
        await _persist();
      }
      final intentPaid = numv(p, 'ridePaid', paid);
      final saleAmount = existing == null
          ? numv(p, 'quantity') * numv(p, 'price')
          : numv(existing, 'amount');
      if (existing == null) {
        await VendorLedger.record(
          id: id,
          person: p,
          kind: 'sale',
          quantity: numv(p, 'quantity'),
          price: numv(p, 'price'),
          paid: math.min(saleAmount, intentPaid),
          session: _session,
        );
      }
      final settle = math.max(0.0, intentPaid - saleAmount);
      if (settle > .001 &&
          !vendorRows(
            'vendor_entries',
          ).any((r) => r['cloudId'] == '${id}_payment')) {
        await VendorLedger.record(
          id: '${id}_payment',
          person: p,
          kind: 'payment',
          payment: settle,
          session: _session,
        );
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _done.add(txt(p, 'id'));
        _editing = null;
        _hint = false;
      });
      await _persist();
      _revealCurrent();
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip(Map<String, dynamic> p) async {
    if (_busy || _done.contains(txt(p, 'id'))) return;
    if (vendorRows('vendor_entries').any((r) => r['cloudId'] == _entryId(p))) {
      snack(
        context,
        bi(
          'Sale saved. Swipe right to finish its payment.',
          'விற்பனை சேமிக்கப்பட்டது. பணத்தை முடிக்க வலமாக நகர்த்தவும்.',
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _skipped.add(txt(p, 'id'));
      _editing = null;
      _hint = false;
    });
    await _persist();
    _revealCurrent();
  }

  void _edit(Map<String, dynamic> p) {
    if (_busy) return;
    if (_volume) {
      unawaited(_skip(p));
      return;
    }
    final due = vendorPersonDue(txt(p, 'id'), vendorRows('vendor_entries'));
    _qty.text = '${numv(p, 'quantity')}';
    _price.text = '${numv(p, 'price')}';
    _paid.text =
        vendorPaymentDate(
          p,
          _date,
        ).isAtSameMomentAs(DateTime(_date.year, _date.month, _date.day))
        ? '${numv(p, 'quantity') * numv(p, 'price') + due}'
        : '0';
    setState(() {
      _editing = txt(p, 'id');
      _hint = false;
    });
  }

  Future<void> _end() async {
    if (_busy) return;
    final rideId = _rideId;
    final rows = vendorRows('vendor_entries')
        .where(
          (r) =>
              (txt(r, 'cloudId').startsWith('${rideId}_') ||
              _supplyIds.contains(txt(r, 'cloudId'))),
        )
        .toList();
    final done = _done.length,
        skipped = _skipped.length,
        remaining = _stops.length - done - skipped;
    if (_stops.any(
      (p) =>
          !_done.contains(txt(p, 'id')) &&
          rows.any((r) => r['cloudId'] == _entryId(p)),
    )) {
      snack(
        context,
        bi(
          'Finish the saved customer payment before ending.',
          'சேமித்த வாடிக்கையாளரின் பணத்தை முடித்தபின் பயணத்தை முடிக்கவும்.',
        ),
      );
      return;
    }
    if (remaining > 0 && done + skipped > 0) {
      final finish = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(bi('End ride?', 'பயணத்தை முடிக்கவா?')),
          content: Text(
            bi(
              '$remaining customers remaining. Saved deliveries stay recorded.',
              '$remaining வாடிக்கையாளர்கள் மீதம். சேமித்த பதிவுகள் இருக்கும்.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: AppText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(bi('End', 'முடி')),
            ),
          ],
        ),
      );
      if (finish != true) return;
    }
    setState(() {
      _rideId = '';
      _editing = null;
      _hint = false;
    });
    await Hive.box('settings').delete(_storageKey);
    await _syncVolume();
    if (!mounted ||
        done == 0 &&
            skipped == 0 &&
            !rows.any((r) => txt(r, 'cloudId').startsWith('${rideId}_'))) {
      return;
    }
    await push(
      context,
      VendorRideSummary(
        rows: rows,
        completed: remaining == 0,
        skipped: skipped,
        remaining: remaining,
      ),
    );
  }

  Future<void> _open(Widget page) async {
    await _syncVolume(enabled: false);
    if (!mounted) return;
    await push(context, page);
    if (mounted) await _syncVolume();
  }

  @override
  Widget build(BuildContext context) {
    unawaited(_syncVolume());
    return AnimatedBuilder(
      animation: Listenable.merge([
        Hive.box('vendor_people').listenable(),
        Hive.box('vendor_entries').listenable(),
      ]),
      builder: (context, _) {
        final all = vendorRows('vendor_people'),
            rows = vendorRows('vendor_entries');
        final buyers = vendorRoutePeople(all, rows, DateTime.now(), _session);
        final suppliers = vendorRoutePeople(
          all,
          rows,
          DateTime.now(),
          _session,
          suppliers: true,
        );
        final display = _active ? _stops : buyers;
        return Shell(
          child: SizedBox.expand(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(21, 12, 21, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          'Vendor',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _busy || _active
                            ? null
                            : () async {
                                await _open(
                                  VendorCustomizeScreen(
                                    volume: _volume,
                                    storageKey: _storageKey,
                                  ),
                                );
                                if (mounted) {
                                  setState(
                                    () => _volume =
                                        Hive.box('settings').get(
                                          '${_storageKey}_volume',
                                          defaultValue: false,
                                        ) ==
                                        true,
                                  );
                                }
                              },
                        icon: const Icon(
                          CupertinoIcons.slider_horizontal_3,
                          size: 19,
                        ),
                        label: Text(bi('Customize', 'மாற்று')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LiquidSegmentBar(
                    labels: const ['Morning', 'Evening'],
                    index: _session == 'Morning' ? 0 : 1,
                    onChanged: (i) {
                      if (!_active) {
                        setState(
                          () => _session = i == 0 ? 'Morning' : 'Evening',
                        );
                      }
                    },
                  ),
                  if (suppliers.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 104,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: suppliers.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 16),
                        itemBuilder: (_, i) {
                          final p = suppliers[i];
                          return SizedBox(
                            width: 74,
                            child: GestureDetector(
                              onTap: _busy
                                  ? null
                                  : () => _open(
                                      VendorPersonScreen(
                                        person: p,
                                        intakeKind: 'collection',
                                        entryPrefix: _active ? _rideId : '',
                                        initialSession: _session,
                                      ),
                                    ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [Ink.violet, Ink.blue],
                                      ),
                                    ),
                                    child: _VendorAvatar(person: p, radius: 28),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    txt(p, 'name'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    txt(p, 'place'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Ink.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Glass(
                    padding: const EdgeInsets.all(21),
                    child: Row(
                      children: [
                        const RanchIcon(type: 'milk', size: 44, weight: 2.7),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bi('Milk', 'பால்'),
                                style: const TextStyle(color: Ink.muted),
                              ),
                              FlowText(
                                '${vendorMilkBalance(rows).toStringAsFixed(2)} L',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy || !canRecordEntries
                              ? null
                              : () => _active ? _end() : _start(buyers, rows),
                          icon: Icon(
                            _active
                                ? CupertinoIcons.stop_fill
                                : CupertinoIcons.play_fill,
                            size: 18,
                          ),
                          label: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              _active
                                  ? bi('End', 'முடி')
                                  : bi('Start', 'தொடங்கு'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        tooltip: ui('Add person'),
                        onPressed: _busy || !canRecordEntries
                            ? null
                            : () => _open(const VendorPersonForm()),
                        icon: const Icon(CupertinoIcons.person_badge_plus),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bi('Customers', 'வாடிக்கையாளர்கள்'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_active)
                        Text(
                          '${_done.length + _skipped.length}/${_stops.length}',
                          style: const TextStyle(color: Ink.muted),
                        ),
                    ],
                  ),
                  if (_active && _volume)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        bi(
                          'Volume ↑ Complete · ↓ Skip · Editing off',
                          'Volume ↑ முடி · ↓ தவிர் · மாற்ற முடியாது',
                        ),
                        style: const TextStyle(color: Ink.muted),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (display.isEmpty)
                    Glass(
                      child: Text(
                        bi(
                          'Add a milk buyer to begin. No customers scheduled for this session.',
                          'பால் வாங்குபவரைச் சேர்க்கவும். இந்த நேரத்திற்கு வாடிக்கையாளர்கள் இல்லை.',
                        ),
                      ),
                    ),
                  for (final p in display)
                    Padding(
                      key: _keys.putIfAbsent(txt(p, 'id'), GlobalKey.new),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _stop(p, rows),
                    ),
                  if (!_active &&
                      all.any(
                        (p) => p['kind'] == 'customer' && !buyers.contains(p),
                      )) ...[
                    const SizedBox(height: 12),
                    Text(
                      bi('Other customers', 'மற்ற வாடிக்கையாளர்கள்'),
                      style: const TextStyle(color: Ink.muted),
                    ),
                    for (final p in all.where(
                      (p) => p['kind'] == 'customer' && !buyers.contains(p),
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _VendorAvatar(person: p),
                        title: Text(txt(p, 'name')),
                        subtitle: Text(txt(p, 'place')),
                        onTap: () => _open(VendorPersonScreen(person: p)),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stop(Map<String, dynamic> p, List<Map<String, dynamic>> rows) {
    final id = txt(p, 'id');
    final current = _active && _current?['id'] == id;
    final done = _active && _done.contains(id),
        skip = _active && _skipped.contains(id);
    final edit = _editing == id;
    final qty = vendorUsualQuantity(p, _session, rows),
        price = numv(p, 'price', defaultMilkPrice());
    final amount = qty * price, due = vendorPersonDue(id, rows);
    final payDate = vendorPaymentDate(p, _active ? _date : DateTime.now());
    final today = DateTime.now();
    final now = payDate.isAtSameMomentAs(
      DateTime(today.year, today.month, today.day),
    );
    final tone = skip
        ? Ink.red
        : done
        ? Ink.green
        : edit
        ? Ink.amber
        : Ink.violet;
    return _VendorSwipeCard(
      enabled: current && !_busy,
      editing: edit,
      hint: current && _hint,
      onRight: () => edit ? _skip(p) : _complete(p),
      onLeft: () => edit || _volume ? _skip(p) : _edit(p),
      child: Glass(
        padding: const EdgeInsets.all(16),
        tint: tone.withValues(alpha: done || skip || edit ? .16 : .04),
        onTap: _active ? null : () => _open(VendorPersonScreen(person: p)),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone.withValues(alpha: .12),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        child: Text(
                          '${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 1)} L',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: tone,
                          ),
                        ),
                      ),
                      if (done || skip)
                        Icon(
                          done
                              ? CupertinoIcons.check_mark
                              : CupertinoIcons.forward,
                          size: 14,
                          color: tone,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        txt(p, 'name'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        txt(p, 'place'),
                        style: const TextStyle(color: Ink.muted, fontSize: 13),
                      ),
                      if (current && !edit)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            bi(
                              'Swipe → complete · ← change',
                              '→ முடி · ← மாற்று',
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Ink.green,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        child: Text(
                          money(amount),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        skip
                            ? bi('Skipped today', 'இன்று தவிர்க்கப்பட்டது')
                            : done
                            ? bi('Completed', 'முடிந்தது')
                            : now
                            ? bi('Pay now', 'இப்போது பணம்')
                            : '${bi('Pay', 'பணம்')} ${payDate.day}/${payDate.month}',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 12, color: tone),
                      ),
                      if (!done && !skip && due > 0)
                        Text(
                          '${bi('Due', 'நிலுவை')} ${money(due)}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: Ink.muted,
                            fontSize: 11,
                          ),
                        ),
                      if (!done && !skip && now && due > 0)
                        Text(
                          '${bi('Collect', 'பெறு')} ${money(due + amount)}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: Ink.green,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (edit) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: fieldStyle(bi('Litres', 'லிட்டர்')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: fieldStyle(bi('Price / L', 'விலை / லி')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _VendorPill(
                      label: bi('Pay now', 'இப்போது'),
                      selected: toDouble(_paid.text) > 0,
                      onTap: () => setState(
                        () => _paid.text =
                            '${toDouble(_qty.text) * toDouble(_price.text) + due}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _VendorPill(
                      label: bi('Pay later', 'பிறகு'),
                      selected: toDouble(_paid.text) == 0,
                      onTap: () => setState(() => _paid.text = '0'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _paid,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: fieldStyle(bi('Payment now', 'இப்போது பணம்')),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _editing = null),
                      child: AppText('Cancel'),
                    ),
                  ),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _complete(p, edited: true),
                      child: AppText('Save'),
                    ),
                  ),
                ],
              ),
              Text(
                bi(
                  'Swipe again to skip today',
                  'மீண்டும் நகர்த்தினால் இன்று தவிர்க்கப்படும்',
                ),
                style: const TextStyle(fontSize: 12, color: Ink.amber),
              ),
            ],
            if (current && _busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _VendorAvatar extends StatelessWidget {
  final Map<String, dynamic> person;
  final double radius;
  const _VendorAvatar({required this.person, this.radius = 22});
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: Ink.lavender,
    backgroundImage: animalImage(person),
    child: animalImage(person) == null
        ? Text(
            txt(person, 'name', '?').characters.first,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Ink.violetDeep,
            ),
          )
        : null,
  );
}

class _VendorSwipeCard extends StatefulWidget {
  final Widget child;
  final bool enabled, editing, hint;
  final VoidCallback onRight, onLeft;
  const _VendorSwipeCard({
    required this.child,
    required this.enabled,
    required this.editing,
    required this.hint,
    required this.onRight,
    required this.onLeft,
  });
  @override
  State<_VendorSwipeCard> createState() => _VendorSwipeCardState();
}

class _VendorSwipeCardState extends State<_VendorSwipeCard> {
  double _drag = 0;
  bool _dragging = false;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final dx = _dragging
        ? _drag
        : widget.hint && !reduce
        ? 26.0
        : 0.0;
    final color = widget.editing
        ? Ink.red
        : dx >= 0
        ? Ink.green
        : Ink.amber;
    return ClipPath(
      clipper: const SquircleClipper(27),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: dx == 0
                        ? [Colors.transparent, Colors.transparent]
                        : [color.withValues(alpha: .72), color],
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: dx >= 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: dx.abs() > 6 ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.editing
                            ? CupertinoIcons.forward
                            : dx >= 0
                            ? CupertinoIcons.check_mark
                            : CupertinoIcons.pencil,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.editing
                            ? bi('Skip today', 'இன்று தவிர்')
                            : dx >= 0
                            ? bi('Complete', 'முடி')
                            : bi('Change', 'மாற்று'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: widget.enabled
                  ? (_) {
                      vendorSwipeInProgress = true;
                      setState(() => _dragging = true);
                    }
                  : null,
              onHorizontalDragUpdate: widget.enabled
                  ? (d) => setState(
                      () => _drag = (_drag + d.delta.dx).clamp(
                        -constraints.maxWidth * .55,
                        constraints.maxWidth * .55,
                      ),
                    )
                  : null,
              onHorizontalDragCancel: () => setState(() {
                vendorSwipeInProgress = false;
                _drag = 0;
                _dragging = false;
              }),
              onHorizontalDragEnd: widget.enabled
                  ? (d) {
                      scheduleMicrotask(() => vendorSwipeInProgress = false);
                      final dx = _drag;
                      setState(() {
                        _drag = 0;
                        _dragging = false;
                      });
                      if (dx.abs() >=
                              math.min(84, constraints.maxWidth * .25) ||
                          dx.abs() > 25 &&
                              d.velocity.pixelsPerSecond.dx.abs() > 650) {
                        if (dx > 0) {
                          widget.onRight();
                        } else {
                          widget.onLeft();
                        }
                      }
                    }
                  : null,
              child: AnimatedContainer(
                duration: _dragging || reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(dx, 0, 0),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VendorCustomizeScreen extends StatefulWidget {
  final bool volume;
  final String storageKey;
  const VendorCustomizeScreen({
    super.key,
    required this.volume,
    required this.storageKey,
  });
  @override
  State<VendorCustomizeScreen> createState() => _VendorCustomizeScreenState();
}

class _VendorCustomizeScreenState extends State<VendorCustomizeScreen> {
  int _day = DateTime.now().weekday % 7;
  late bool _volume = widget.volume;
  bool _saving = false;
  List<Map<String, dynamic>> _people = [];
  final Map<int, List<Map<String, dynamic>>> _orders = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _people = _orders.putIfAbsent(_day, () {
      final all = vendorRows('vendor_people')
          .where(
            (p) =>
                p['kind'] == 'customer' &&
                ((p['days'] as List?)?.isEmpty != false ||
                    (p['days'] as List).contains(_day)),
          )
          .toList();
      all.sort(
        (a, b) => ((asMap(a['routeOrder'])['$_day'] as num?) ?? 100000)
            .compareTo((asMap(b['routeOrder'])['$_day'] as num?) ?? 100000),
      );
      return all;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final day in _orders.entries) {
        for (var i = 0; i < day.value.length; i++) {
          final p = day.value[i];
          final current = asMap(Hive.box('vendor_people').get(p['_key']));
          if (current.isEmpty) continue;
          await Hive.box('vendor_people').put(p['_key'], {
            ...current,
            'routeOrder': {...asMap(current['routeOrder']), '${day.key}': i},
            'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }
      await Hive.box('settings').put('${widget.storageKey}_volume', _volume);
      AutoSyncService.markDirty(reason: 'vendor route order');
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(bi('Customize', 'மாற்று'))),
    body: Shell(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(21, 12, 21, 40),
        children: [
          Text(
            bi('Customer order', 'வாடிக்கையாளர் வரிசை'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Tooltip(
                      message: _dayNames[i],
                      child: _VendorPill(
                        label: _dayNames[i][0],
                        selected: _day == i,
                        onTap: () => setState(() {
                          _day = i;
                          _load();
                        }),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            bi(
              'Hold and drag to arrange',
              'அழுத்திப் பிடித்து வரிசையை மாற்றவும்',
            ),
            style: const TextStyle(color: Ink.muted),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _people.length,
            onReorderItem: (old, next) => setState(() {
              final p = _people.removeAt(old);
              _people.insert(next, p);
            }),
            itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
              key: ValueKey(_people[i]['id']),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Glass(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      _VendorAvatar(person: _people[i]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(txt(_people[i], 'name')),
                            Text(
                              txt(_people[i], 'place'),
                              style: const TextStyle(
                                color: Ink.muted,
                                fontSize: 12,
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
          const SizedBox(height: 24),
          Text(
            bi('Sale complete action', 'விற்பனையை முடிக்கும் முறை'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Glass(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _volume,
              title: Text(bi('Volume buttons', 'Volume பொத்தான்கள்')),
              subtitle: Text(
                bi('Up: complete · Down: skip', 'மேல்: முடி · கீழ்: தவிர்'),
              ),
              onChanged: (v) async {
                if (v &&
                    (kIsWeb ||
                        defaultTargetPlatform != TargetPlatform.android)) {
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(bi('Volume controls', 'Volume கட்டுப்பாடு')),
                      content: Text(
                        bi(
                          'Phone volume buttons work in the Android app. Browsers do not give this access. Use swipe controls here.',
                          'Phone volume பொத்தான்கள் Android app-ல் வேலை செய்யும். Browser-ல் இந்த அணுகல் இல்லை. இங்கு swipe பயன்படுத்தவும்.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                  return;
                }
                setState(() => _volume = v);
                if (v) {
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(bi('Volume mode', 'Volume முறை')),
                      content: Text(
                        bi(
                          'Editing is unavailable during volume mode. Volume up completes the next customer; volume down skips today.',
                          'Volume முறையில் மாற்ற முடியாது. Volume up அடுத்த வாடிக்கையாளரை முடிக்கும்; volume down இன்று தவிர்க்கும்.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: AppText('Save'),
            ),
          ),
        ],
      ),
    ),
  );
}

class VendorRideSummary extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool completed;
  final int skipped, remaining;
  const VendorRideSummary({
    super.key,
    required this.rows,
    required this.completed,
    required this.skipped,
    required this.remaining,
  });
  @override
  Widget build(BuildContext context) {
    final sales = rows.where((r) => r['kind'] == 'sale').toList();
    final bought =
        _vendorSum(rows, 'collection', 'quantity') +
        _vendorSum(rows, 'purchase', 'quantity');
    final sold = _vendorSum(rows, 'sale', 'quantity');
    final earned = _vendorSum(rows, 'sale', 'amount');
    final collected =
        sales.fold(0.0, (s, r) => s + numv(r, 'paid')) +
        _vendorSum(rows, 'payment', 'amount');
    final expenses =
        _vendorSum(rows, 'collection', 'amount') +
        _vendorSum(rows, 'purchase', 'amount');
    final people = vendorRows(
      'vendor_people',
    ).where((p) => p['kind'] == 'customer').toList();
    final allRows = vendorRows('vendor_entries');
    double score(Map<String, dynamic> p) {
      final entries = allRows
          .where((r) => r['personId'] == p['id'] && r['kind'] == 'sale')
          .toList();
      if (entries.isEmpty) return -1;
      double onTime = 0, total = 0;
      for (final sale in entries) {
        final date = DateTime.tryParse(txt(sale, 'date'));
        if (date == null) continue;
        total += numv(sale, 'quantity');
        final deadline = vendorPaymentDate(p, date);
        final dueAtDeadline = allRows
            .where(
              (r) =>
                  r['personId'] == p['id'] &&
                  (DateTime.tryParse(txt(r, 'date'))?.isAfter(deadline) ==
                      false),
            )
            .toList();
        if (numv(sale, 'paid') >= numv(sale, 'amount') ||
            vendorPersonDue(txt(p, 'id'), dueAtDeadline) <= .001) {
          onTime++;
        }
      }
      return onTime / entries.length * 1000000 + total;
    }

    people.sort((a, b) => score(b).compareTo(score(a)));
    final top = people.where((p) => score(p) >= 0).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(bi('Ride summary', 'பயணக் கணக்கு'))),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.all(21),
          children: [
            const SizedBox(height: 16),
            Icon(
              completed
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.flag_fill,
              color: Ink.green,
              size: 64,
            ),
            const SizedBox(height: 18),
            Text(
              completed
                  ? bi(
                      'Successfully completed ride',
                      'பயணம் வெற்றிகரமாக முடிந்தது',
                    )
                  : bi('Ride ended', 'பயணம் முடிந்தது'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            Glass(
              child: Column(
                children: [
                  _BalanceRow(
                    label: bi('Earnings', 'வருவாய்'),
                    value: money(earned),
                    color: Ink.green,
                  ),
                  _BalanceRow(
                    label: bi('Payments collected', 'பெற்ற பணம்'),
                    value: money(collected),
                    color: Ink.green,
                  ),
                  _BalanceRow(
                    label: bi('Milk bought', 'வாங்கிய பால்'),
                    value: '${bought.toStringAsFixed(2)} L',
                    color: Ink.blue,
                  ),
                  _BalanceRow(
                    label: bi('Milk sold', 'விற்ற பால்'),
                    value: '${sold.toStringAsFixed(2)} L',
                    color: Ink.violet,
                  ),
                  _BalanceRow(
                    label: bi('Milk cost', 'பால் செலவு'),
                    value: money(expenses),
                    color: Ink.amber,
                  ),
                  _BalanceRow(
                    label: bi('Profit', 'லாபம்'),
                    value: money(earned - expenses),
                    color: Ink.green,
                  ),
                  _BalanceRow(
                    label: bi('Customers served', 'வாடிக்கையாளர்கள்'),
                    value: '${sales.length}',
                    color: Ink.violet,
                  ),
                  _BalanceRow(
                    label: bi('Skipped', 'தவிர்த்தது'),
                    value: '$skipped',
                    color: Ink.red,
                  ),
                  if (remaining > 0)
                    _BalanceRow(
                      label: bi('Remaining', 'மீதம்'),
                      value: '$remaining',
                      color: Ink.muted,
                    ),
                ],
              ),
            ),
            if (top != null) ...[
              const SizedBox(height: 24),
              Text(
                bi('Top customer', 'சிறந்த வாடிக்கையாளர்'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Glass(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _VendorAvatar(person: top),
                  title: Text(txt(top, 'name')),
                  subtitle: Text(txt(top, 'place')),
                  trailing: const Icon(
                    CupertinoIcons.star_fill,
                    color: Ink.amber,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(bi('Done', 'முடிந்தது')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
