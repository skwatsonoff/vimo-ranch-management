part of 'main.dart';

const _rideVolume = MethodChannel('vimo/vendor_volume');

/// Clean text for editable numbers: 1.0 -> "1", 90.44999999 -> "90.45".
String vendorFieldNumber(num value) {
  if (!value.isFinite) return '0';
  final fixed = value.toStringAsFixed(2);
  return fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : fixed;
}

Set<int> vendorWeekdays(dynamic value) => value is List
    ? value
          .whereType<num>()
          .where(
            (day) => day.isFinite && day >= 0 && day < 7 && day == day.toInt(),
          )
          .map((day) => day.toInt())
          .toSet()
    : <int>{};

String vendorSessionNow([DateTime? at]) =>
    (at ?? DateTime.now()).hour < 12 ? 'Morning' : 'Evening';

bool vendorScheduled(Map<String, dynamic> p, DateTime date, String session) {
  final days = vendorWeekdays(p['days']);
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
  final days = vendorWeekdays(
    p['paymentDays'] ?? (cycle == 'Weekly' ? [0] : []),
  );
  if (days.isEmpty) return day;
  for (var i = 0; i < 7; i++) {
    final candidate = day.add(Duration(days: i));
    if (days.contains(candidate.weekday % 7)) return candidate;
  }
  return day;
}

const _dayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _dayShortTamil = ['ஞா', 'தி', 'செ', 'பு', 'வி', 'வெ', 'ச'];

/// Short, readable schedule: "Every day", "Weekly · Sun", "Mon, Thu".
String vendorScheduleDays(Set<int> days) {
  if (days.length >= 7) return bi('Every day', 'தினமும்');
  final sorted = days.toList()..sort();
  return sorted
      .map((d) => tamilUi ? _dayShortTamil[d] : _dayShort[d])
      .join(', ');
}

String vendorPaymentScheduleLabel(Map<String, dynamic> person) {
  final cycle = txt(person, 'paymentCycle', 'Daily');
  final prefix = bi('Payment', 'பணம்');
  if (cycle == 'Daily') return '$prefix · ${bi('Daily', 'தினமும்')}';
  if (cycle == 'Monthly') {
    return '$prefix · ${bi('Monthly on', 'மாதந்தோறும்')} ${numv(person, 'paymentMonthDay', 1).toInt()}';
  }
  final days = vendorWeekdays(person['paymentDays']);
  if (days.length >= 7) return '$prefix · ${bi('Every day', 'தினமும்')}';
  final cycleLabel = cycle == 'Weekly'
      ? bi('Weekly', 'வாரந்தோறும்')
      : bi('Selected days', 'தேர்ந்த நாட்கள்');
  return days.isEmpty
      ? '$prefix · $cycleLabel'
      : '$prefix · $cycleLabel · ${vendorScheduleDays(days)}';
}

({String label, Color color}) vendorPaymentTiming(
  Map<String, dynamic> person,
  Iterable<Map<String, dynamic>> rows,
  DateTime date,
) {
  final today = DateTime(date.year, date.month, date.day);
  final receipts =
      rows
          .where(
            (r) =>
                r['personId'] == person['id'] &&
                (r['kind'] == 'payment' || numv(r, 'paid') > 0),
          )
          .toList()
        ..sort(
          (a, b) => txt(
            b,
            'createdAt',
            txt(b, 'date'),
          ).compareTo(txt(a, 'createdAt', txt(a, 'date'))),
        );
  if (receipts.isNotEmpty && vendorPersonDue(txt(person, 'id'), rows) <= .001) {
    final paidDate = DateTime.tryParse(txt(receipts.first, 'date'));
    if (paidDate != null) {
      final age = today
          .difference(DateTime(paidDate.year, paidDate.month, paidDate.day))
          .inDays;
      if (age >= 0 && age <= 7)
        return (
          label: age == 0
              ? bi('Received today', 'இன்று பெற்றது')
              : age == 1
              ? bi('Received yesterday', 'நேற்று பெற்றது')
              : '${bi('Received', 'பெற்றது')} ${paidDate.day}/${paidDate.month}',
          color: Ink.greenText,
        );
    }
  }
  final due = vendorPaymentDate(person, today);
  final days = due.difference(today).inDays;
  return days <= 0
      ? (label: bi('Receive now', 'இப்போது பெறவும்'), color: Ink.amberText)
      : (
          label: days == 1
              ? bi('Due tomorrow', 'நாளை பெறவும்')
              : '${bi('Due', 'பெறுவது')} ${due.day}/${due.month}',
          color: Ink.redText,
        );
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
  final bool showAll;
  const VendorWeekRow({
    super.key,
    required this.days,
    required this.onChanged,
    this.daily = false,
    this.showAll = true,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (showAll)
        Expanded(
          flex: 2,
          child: _VendorPill(
            label: daily
                ? bi('Daily', 'தினமும்')
                : bi('All days', 'எல்லா நாட்களும்'),
            selected: days.length == 7,
            onTap: () =>
                onChanged(days.length == 7 ? {} : {0, 1, 2, 3, 4, 5, 6}),
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
        color: selected ? Ink.tint : Ink.fill,
        shape: const StadiumBorder(),
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
    text: vendorFieldNumber(numv(widget.person ?? {}, 'quantity', 1)),
  );
  late final _price = TextEditingController(
    text: vendorFieldNumber(
      numv(widget.person ?? {}, 'price', defaultMilkPrice()),
    ),
  );
  late String _kind = widget.person?['kind'] ?? widget.kind;
  late String _cycle = widget.person?['paymentCycle'] ?? 'Daily';
  late String _photo = txt(widget.person ?? {}, 'imageData');
  late Set<int> _days = vendorWeekdays(widget.person?['days']);
  late Set<int> _paymentDays = vendorWeekdays(
    widget.person?['paymentDays'] ?? [0, 1, 2, 3, 4, 5, 6],
  );
  late final Set<String> _sessions =
      ((widget.person?['sessions'] as List?) ?? ['Morning', 'Evening'])
          .cast<String>()
          .toSet();
  late int _monthDay = numv(widget.person ?? {}, 'paymentMonthDay', 1).toInt();
  late ll.LatLng? _point = personPoint(widget.person ?? {});
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
      final point = _point;
      if (point == null) {
        // Null (not a missing key) so a merged cloud copy clears it too.
        if (data.containsKey('lat') || data.containsKey('lng')) {
          data['lat'] = null;
          data['lng'] = null;
        }
      } else {
        data['lat'] = point.latitude;
        data['lng'] = point.longitude;
      }
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
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GlassAvatar(
                          image: cachedPhoto(_photo),
                          label: _name.text,
                          radius: 44,
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Ink.violetDeep,
                              border: Border.all(color: Ink.surface, width: 2),
                            ),
                            child: const Icon(
                              CupertinoIcons.camera_fill,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
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
            // Places already used are suggested, so one place is always
            // spelled one way and its customers group together.
            VendorPlaceField(
              controller: _place,
              label: bi('Place', 'இடம்'),
              icon: null,
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
                    label: AppText(
                      s,
                      style: TextStyle(
                        color: _sessions.contains(s) ? Colors.white : Ink.body,
                      ),
                    ),
                    selectedColor: Ink.violetDeep,
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
              bi('Payment frequency', 'பணம் பெறும் இடைவெளி'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cycle in ['Daily', 'Weekly', 'Monthly', 'Flexible'])
                  _VendorPill(
                    label: switch (cycle) {
                      'Daily' => bi('Daily', 'தினமும்'),
                      'Weekly' => bi('Weekly once', 'வாரம் ஒருமுறை'),
                      'Monthly' => bi('Monthly once', 'மாதம் ஒருமுறை'),
                      _ => bi('Choose days', 'நாட்களைத் தேர்வு செய்'),
                    },
                    selected: _cycle == cycle,
                    onTap: () => setState(() {
                      _cycle = cycle;
                      if (cycle == 'Weekly' && _paymentDays.length != 1) {
                        _paymentDays = {DateTime.now().weekday % 7};
                      }
                      if (cycle == 'Daily') {
                        _paymentDays = {0, 1, 2, 3, 4, 5, 6};
                      }
                      if (cycle == 'Flexible' && _paymentDays.isEmpty) {
                        _paymentDays = {DateTime.now().weekday % 7};
                      }
                    }),
                  ),
              ],
            ),
            if (_cycle == 'Weekly' || _cycle == 'Flexible') ...[
              const SizedBox(height: 12),
              Text(
                _cycle == 'Weekly'
                    ? bi('Which day?', 'எந்த நாள்?')
                    : bi('Receive payment on', 'பணம் பெறும் நாட்கள்'),
                style: TextStyle(color: Ink.muted),
              ),
              const SizedBox(height: 8),
              VendorWeekRow(
                showAll: _cycle == 'Flexible',
                days: _paymentDays,
                onChanged: (d) => setState(() {
                  final added = d.difference(_paymentDays);
                  _paymentDays = _cycle == 'Weekly'
                      ? (added.isEmpty ? _paymentDays : {added.first})
                      : (d.isEmpty ? _paymentDays : d);
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
                    DropdownMenuItem(value: d, child: AppText('$d')),
                ],
                onChanged: (d) => setState(() => _monthDay = d!),
              ),
            ],
            const SizedBox(height: 24),
            VendorLocationField(
              value: _point,
              name: _name.text.trim(),
              onChanged: (p) => setState(() => _point = p),
            ),
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
  String _session = vendorSessionNow();
  String _rideId = '';
  String _rideDate = '';
  List<String> _supplyIds = [];
  List<Map<String, dynamic>> _stops = [];
  Set<String> _done = {}, _skipped = {};
  String? _editing, _savingId;
  bool _busy = false, _hint = false, _volume = false, _payNow = true;

  /// Customers grouped by place (a Customize option) and the chosen place.
  bool _groups = false;
  String? _place;

  /// The route map this ride follows, if it was started from one.
  String _routeId = '';
  Timer? _hintTimer, _clock;
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
      _routeId = txt(saved, 'route');
    }
    _groups =
        Hive.box(
          'settings',
        ).get('${_storageKey}_groups', defaultValue: false) ==
        true;
    vendorRouteRequest.addListener(_routeRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _routeRequested());
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
    // Morning/evening follows the clock; no manual selector is needed.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && !_active && vendorSessionNow() != _session) {
        setState(() => _session = vendorSessionNow());
      }
    });
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
    vendorRouteRequest.removeListener(_routeRequested);
    vendorWorkspaceRevision.removeListener(_workspaceChanged);
    _hintTimer?.cancel();
    _clock?.cancel();
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
    'route': _routeId,
  });

  /// Starts a ride in a route map's home order.
  void _routeRequested() {
    final id = vendorRouteRequest.value;
    if (id == null || !mounted) return;
    vendorRouteRequest.value = null;
    if (_active) {
      snack(
        context,
        bi(
          'End the current ride before starting a route.',
          'பாதையைத் தொடங்கும் முன் இப்போதைய பயணத்தை முடிக்கவும்.',
        ),
      );
      return;
    }
    final route = VendorRoutes.byId(id);
    if (route == null) return;
    final people = {
      for (final p in vendorRows('vendor_people'))
        if (p['kind'] == 'customer') txt(p, 'id'): p,
    };
    final ordered = [
      for (final stop in routeStops(route)) ?people[txt(stop, 'id')],
    ];
    unawaited(_start(ordered, vendorRows('vendor_entries'), routeId: id));
  }

  /// Ride order: by place when grouping is on, the chosen place first (or
  /// only that place when one is selected).
  List<Map<String, dynamic>> _rideOrder(List<Map<String, dynamic>> buyers) {
    if (!_groups) return buyers;
    final groups = vendorPlaceGroups(buyers);
    if (_place != null && groups.any((g) => g.key == _place)) {
      return groups.firstWhere((g) => g.key == _place).people;
    }
    return [for (final g in groups) ...g.people];
  }

  DateTime get _date => DateTime.tryParse(_rideDate) ?? DateTime.now();
  Future<void> _start(
    List<Map<String, dynamic>> people,
    List<Map<String, dynamic>> rows, {
    String routeId = '',
  }) async {
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
      _routeId = routeId;
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
    final wasNext = _current?['id'] == p['id'];
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
    setState(() {
      _busy = true;
      _savingId = txt(p, 'id');
    });
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
        if (_editing == txt(p, 'id')) _editing = null;
        _hint = false;
      });
      await _persist();
      if (wasNext) _revealCurrent();
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _savingId = null;
        });
      }
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
    final wasNext = _current?['id'] == p['id'];
    HapticFeedback.lightImpact();
    setState(() {
      _skipped.add(txt(p, 'id'));
      if (_editing == txt(p, 'id')) _editing = null;
      _hint = false;
    });
    await _persist();
    if (wasNext) _revealCurrent();
  }

  void _edit(Map<String, dynamic> p) {
    if (_busy) return;
    if (_volume) {
      unawaited(_skip(p));
      return;
    }
    final due = vendorPersonDue(txt(p, 'id'), vendorRows('vendor_entries'));
    _qty.text = vendorFieldNumber(numv(p, 'quantity'));
    _price.text = vendorFieldNumber(numv(p, 'price'));
    _payNow = vendorPaymentDate(
      p,
      _date,
    ).isAtSameMomentAs(DateTime(_date.year, _date.month, _date.day));
    _paid.text = _payNow
        ? vendorFieldNumber(numv(p, 'quantity') * numv(p, 'price') + due)
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
        builder: (ctx) => AppleAlert(
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
      _routeId = '';
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
        if (!_active) _session = vendorSessionNow();
        final buyers = vendorRoutePeople(all, rows, DateTime.now(), _session);
        final suppliers = vendorRoutePeople(
          all,
          rows,
          DateTime.now(),
          _session,
          suppliers: true,
        );
        final others = _active
            ? const <Map<String, dynamic>>[]
            : all
                  .where(
                    (p) =>
                        p['kind'] == 'customer' &&
                        !buyers.any((b) => b['id'] == p['id']),
                  )
                  .toList();
        final groups = _groups
            ? vendorPlaceGroups(_active ? _stops : buyers)
            : const <VendorPlaceGroup>[];
        if (_place != null && !groups.any((g) => g.key == _place)) {
          _place = null;
        }
        final chosen = groups.where((g) => g.key == _place).firstOrNull;
        final route = _routeId.isEmpty ? null : VendorRoutes.byId(_routeId);
        return Shell(
          child: SizedBox.expand(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _providersRow(suppliers),
                  const SizedBox(height: 16),
                  _milkCard(rows),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: LiquidButton(
                          label: _active
                              ? bi('End', 'முடி')
                              : chosen != null
                              ? '${bi('Start', 'தொடங்கு')} · ${chosen.label}'
                              : bi('Start', 'தொடங்கு'),
                          icon: _active
                              ? CupertinoIcons.stop_fill
                              : CupertinoIcons.play_fill,
                          height: 56,
                          radius: 28,
                          start: _active ? Ink.red : Ink.tint,
                          end: _active ? Ink.red : Ink.tint,
                          onPressed: _busy || !canRecordEntries
                              ? null
                              : () => _active
                                    ? _end()
                                    : _start(_rideOrder(buyers), rows),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _CircleGlassButton(
                        tooltip: ui('Add person'),
                        icon: CupertinoIcons.person_badge_plus,
                        onTap: _busy || !canRecordEntries
                            ? null
                            : () => _open(const VendorPersonForm()),
                      ),
                    ],
                  ),
                  if (_active && route != null) ...[
                    const SizedBox(height: 16),
                    VendorRouteGuide(
                      route: route,
                      currentId: txt(_current ?? {}, 'id'),
                      states: {
                        for (final p in _stops)
                          txt(p, 'id'): _done.contains(txt(p, 'id'))
                              ? StopState.done
                              : _skipped.contains(txt(p, 'id'))
                              ? StopState.skipped
                              : txt(p, 'id') == txt(_current ?? {}, 'id')
                              ? StopState.current
                              : StopState.pending,
                      },
                    ),
                  ],
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bi('Customers', 'வாடிக்கையாளர்கள்'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.3,
                          ),
                        ),
                      ),
                      if (_active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: ShapeDecoration(
                            color: Ink.violetDeep.withValues(alpha: .10),
                            shape: const StadiumBorder(),
                          ),
                          child: AppText(
                            '${_done.length + _skipped.length}/${_stops.length}',
                            style: TextStyle(
                              color: Ink.violetDeep,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        TextButton.icon(
                          onPressed: _busy ? null : _customize,
                          icon: const Icon(
                            CupertinoIcons.slider_horizontal_3,
                            size: 19,
                          ),
                          label: Text(bi('Customize', 'மாற்று')),
                        ),
                    ],
                  ),
                  if (groups.length > 1 || (groups.isNotEmpty && _active)) ...[
                    const SizedBox(height: 13),
                    VendorPlaceBubbles(
                      groups: groups,
                      selected: _place,
                      done: _active
                          ? {
                              for (final g in groups)
                                g.key: g.people
                                    .where(
                                      (p) =>
                                          _done.contains(txt(p, 'id')) ||
                                          _skipped.contains(txt(p, 'id')),
                                    )
                                    .length,
                            }
                          : null,
                      onSelected: (key) {
                        HapticFeedback.selectionClick();
                        setState(() => _place = key);
                      },
                    ),
                  ],
                  if (_active && _volume)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        bi(
                          'Volume ↑ Complete · ↓ Skip · Editing off',
                          'Volume ↑ முடி · ↓ தவிர் · மாற்ற முடியாது',
                        ),
                        style: TextStyle(color: Ink.muted),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_active)
                    ..._rideList(rows)
                  else if (buyers.isEmpty)
                    Glass(
                      child: Text(
                        bi(
                          'Add a milk buyer to begin. No customers scheduled for this session.',
                          'பால் வாங்குபவரைச் சேர்க்கவும். இந்த நேரத்திற்கு வாடிக்கையாளர்கள் இல்லை.',
                        ),
                        style: TextStyle(color: Ink.muted),
                      ),
                    )
                  else if (_groups)
                    for (final g in _placeFirst(groups)) ...[
                      _GroupHeader(
                        label: g.label,
                        count: g.people.length,
                        highlighted: g.key == _place,
                      ),
                      for (final p in g.people)
                        Padding(
                          key: _keys.putIfAbsent(txt(p, 'id'), GlobalKey.new),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _stop(p, rows),
                        ),
                    ]
                  else
                    for (final p in buyers)
                      Padding(
                        key: _keys.putIfAbsent(txt(p, 'id'), GlobalKey.new),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _stop(p, rows),
                      ),
                  if (others.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      bi('Other customers', 'மற்ற வாடிக்கையாளர்கள்'),
                      style: TextStyle(
                        color: Ink.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final p in others)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Glass(
                          radius: 22,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          onTap: () => _open(VendorPersonScreen(person: p)),
                          child: Row(
                            children: [
                              _VendorAvatar(person: p, radius: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      txt(p, 'name'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      txt(p, 'place'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Ink.muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                CupertinoIcons.chevron_right,
                                size: 16,
                                color: Ink.faint,
                              ),
                            ],
                          ),
                        ),
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

  /// The chosen place rises to the top; the rest keep their order.
  List<VendorPlaceGroup> _placeFirst(List<VendorPlaceGroup> groups) => [
    ...groups.where((g) => g.key == _place),
    ...groups.where((g) => g.key != _place),
  ];

  Future<void> _customize() async {
    await _open(
      VendorCustomizeScreen(
        volume: _volume,
        groups: _groups,
        storageKey: _storageKey,
      ),
    );
    if (mounted) {
      final settings = Hive.box('settings');
      setState(() {
        _volume =
            settings.get('${_storageKey}_volume', defaultValue: false) == true;
        _groups =
            settings.get('${_storageKey}_groups', defaultValue: false) == true;
        if (!_groups) _place = null;
      });
    }
  }

  Widget _providersRow(List<Map<String, dynamic>> suppliers) => SizedBox(
    height: 108,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: suppliers.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy || !canRecordEntries
                        ? null
                        : () => _open(const VendorPersonForm(kind: 'supplier')),
                    icon: const Icon(CupertinoIcons.add_circled),
                    label: Text(
                      bi('Add milk provider', 'பால் வழங்குநரைச் சேர்'),
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  itemCount: suppliers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (_, i) {
                    final p = suppliers[i];
                    return _ProviderBubble(
                      person: p,
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
                    );
                  },
                ),
        ),
        const SizedBox(width: 8),
        _ProviderBubble(
          label: bi('All', 'அனைத்தும்'),
          icon: CupertinoIcons.person_3_fill,
          onTap: _busy
              ? null
              : () => _open(
                  VendorProvidersScreen(
                    entryPrefix: _active ? _rideId : '',
                    session: _session,
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _milkCard(List<Map<String, dynamic>> rows) {
    final today = todayDate();
    double sumToday(bool intake) => rows
        .where(
          (r) =>
              r['date'] == today &&
              r['stockScope'] == 'vendor_v2' &&
              (intake
                  ? ['collection', 'purchase'].contains(r['kind'])
                  : r['kind'] == 'sale' || r['kind'] == 'clearance'),
        )
        .fold(0.0, (s, r) => s + numv(r, 'quantity'));
    final inToday = sumToday(true), outToday = sumToday(false);
    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      onTap: _busy ? null : () => _open(const VendorStockScreen()),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Ink.surface, Ink.lavender],
              ),
              boxShadow: [
                BoxShadow(
                  color: Ink.violetDeep.withValues(alpha: .14),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const MilkVendorIcon(size: 42),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bi('Milk balance', 'பால் இருப்பு'),
                  style: TextStyle(
                    color: Ink.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AppText(
                    '${vendorFieldNumber(vendorMilkBalance(rows))} L',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MilkFlow(
                label: '+${vendorFieldNumber(inToday)} L',
                color: Ink.greenText,
              ),
              const SizedBox(height: 6),
              _MilkFlow(
                label: '−${vendorFieldNumber(outToday)} L',
                color: Ink.violetDeep,
              ),
              const SizedBox(height: 6),
              _ClearanceChip(
                onTap: _busy || !canRecordEntries
                    ? null
                    : () => showMilkClearance(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Every waiting customer can be swiped, in any order. Finished rows stay
  /// on top; with place groups on, the chosen place leads.
  List<Widget> _rideList(List<Map<String, dynamic>> rows) {
    final finished = _stops
        .where(
          (p) =>
              _done.contains(txt(p, 'id')) || _skipped.contains(txt(p, 'id')),
        )
        .toList();
    final waiting = _stops.where((p) => !finished.contains(p)).toList();
    final ordered = _groups
        ? [for (final g in _placeFirst(vendorPlaceGroups(waiting))) ...g.people]
        : waiting;
    return [
      for (final p in finished)
        _RideAppear(
          key: ValueKey('done-${txt(p, 'id')}'),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _finishedRow(p),
          ),
        ),
      if (waiting.isEmpty)
        _RideAppear(
          key: const ValueKey('ride-finished'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Glass(
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    color: Ink.green,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      bi(
                        'All customers done. Press End.',
                        'அனைவரும் முடிந்தது. முடி அழுத்தவும்.',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (finished.isEmpty && waiting.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(CupertinoIcons.hand_draw_fill, size: 15, color: Ink.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  bi(
                    'Swipe any customer, in any order',
                    'எந்த வாடிக்கையாளரையும், எந்த வரிசையிலும் நகர்த்தலாம்',
                  ),
                  style: TextStyle(color: Ink.muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      for (final p in ordered)
        _RideAppear(
          key: ValueKey('ride-${txt(p, 'id')}'),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: KeyedSubtree(
              key: _keys.putIfAbsent(txt(p, 'id'), GlobalKey.new),
              child: _stop(p, rows),
            ),
          ),
        ),
    ];
  }

  Widget _finishedRow(Map<String, dynamic> p) {
    final id = txt(p, 'id');
    final skipped = _skipped.contains(id);
    final paid = numv(p, 'ridePaid') > 0;
    final color = skipped ? Ink.redText : Ink.greenText;
    final qty = numv(p, 'quantity');
    return Glass(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      tint: (skipped ? Ink.red : Ink.green).withValues(alpha: .07),
      child: Row(
        children: [
          Icon(
            skipped
                ? CupertinoIcons.forward_fill
                : CupertinoIcons.check_mark_circled_solid,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          _VendorAvatar(person: p, radius: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              txt(p, 'name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (!skipped)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: AppText(
                '${vendorFieldNumber(qty)} L',
                style: TextStyle(color: Ink.muted),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              skipped
                  ? bi('Skipped today', 'இன்று தவிர்க்கப்பட்டது')
                  : paid
                  ? bi('Received', 'பெற்றது')
                  : bi('Delivered', 'வழங்கியது'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stop(
    Map<String, dynamic> p,
    List<Map<String, dynamic>> rows, {
    bool preview = false,
  }) {
    final id = txt(p, 'id');
    // Any customer still waiting can be completed, changed or skipped.
    final current =
        !preview && _active && !_done.contains(id) && !_skipped.contains(id);
    final edit = current && _editing == id;
    final qty = _active
            ? numv(p, 'quantity')
            : vendorUsualQuantity(p, _session, rows),
        price = numv(p, 'price', defaultMilkPrice());
    final amount = qty * price, due = vendorPersonDue(id, rows);
    final payDate = vendorPaymentDate(p, _active ? _date : DateTime.now());
    final today = DateTime.now();
    final now = payDate.isAtSameMomentAs(
      DateTime(today.year, today.month, today.day),
    );
    final timing = vendorPaymentTiming(p, rows, today);
    final card = Glass(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      radius: 26,
      tint: edit ? Ink.amber.withValues(alpha: .06) : null,
      onTap: _active ? null : () => _open(VendorPersonScreen(person: p)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _VendorAvatar(person: p, radius: 25),
              const SizedBox(width: 12),
              Container(
                constraints: const BoxConstraints(minWidth: 50),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: ShapeDecoration(
                  color: Ink.violetDeep.withValues(alpha: .08),
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      vendorFieldNumber(qty),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Ink.violetDeep,
                      ),
                    ),
                    AppText(
                      ' L',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Ink.violetDeep,
                      ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      txt(p, 'place'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Ink.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Bounded so long status labels (or Tamil text) never push
              // the row wider than the card.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 124),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        money(amount),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      timing.label,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: timing.color,
                      ),
                    ),
                    if (due > 0.001)
                      Text(
                        now
                            ? '${bi('Collect', 'பெறு')} ${money(due + amount)}'
                            : '${bi('Due', 'நிலுவை')} ${money(due)}',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: now ? Ink.greenText : Ink.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (edit) ..._editFields(p, due),
          if (current && _busy && _savingId == id)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
    if (preview || !_active) return card;
    return _VendorSwipeCard(
      enabled: current && !_busy,
      editing: edit,
      hint: current && _hint && _current?['id'] == id,
      onRight: () => edit ? _skip(p) : _complete(p),
      onLeft: () => edit || _volume ? _skip(p) : _edit(p),
      child: card,
    );
  }

  List<Widget> _editFields(Map<String, dynamic> p, double due) {
    void recompute() {
      if (_payNow) {
        _paid.text = vendorFieldNumber(
          toDouble(_qty.text) * toDouble(_price.text) + due,
        );
      }
    }

    final litres = toDouble(_qty.text), price = toDouble(_price.text);
    return [
      const SizedBox(height: 16),
      TextField(
        controller: _qty,
        autofocus: false,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: fieldStyle(bi('Litres', 'லிட்டர்')),
        onChanged: (_) => setState(recompute),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
        child: AppText(
          '${bi('Amount', 'தொகை')} ${money(litres * price)}'
          '${due > 0.001 ? '  ·  ${bi('Due', 'நிலுவை')} ${money(due)}' : ''}',
          style: TextStyle(color: Ink.body, fontWeight: FontWeight.w600),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: _VendorPill(
              label: bi('Received now', 'இப்போது பெற்றது'),
              selected: _payNow,
              onTap: () => setState(() {
                _payNow = true;
                recompute();
              }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _VendorPill(
              label: bi('Receive later', 'பிறகு பெறுவது'),
              selected: !_payNow,
              onTap: () => setState(() {
                _payNow = false;
                _paid.text = '0';
              }),
            ),
          ),
        ],
      ),
      if (_payNow) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                bi('Amount received', 'பெற்ற தொகை'),
                style: TextStyle(color: Ink.muted, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              width: 132,
              child: TextField(
                controller: _paid,
                textAlign: TextAlign.end,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: currencySymbol(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: GlassInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: GlassInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: GlassInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Ink.violetDeep, width: 1.4),
                  ),
                  filled: true,
                  fillColor: Ink.surface.withValues(alpha: .7),
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _busy ? null : () => setState(() => _editing = null),
              child: AppText('Cancel'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LiquidButton(
              label: ui('Save'),
              height: 48,
              radius: 24,
              onPressed: _busy ? null : () => _complete(p, edited: true),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        bi(
          'Swipe again to skip today',
          'மீண்டும் நகர்த்தினால் இன்று தவிர்க்கப்படும்',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Ink.amberText,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }
}

class _MilkFlow extends StatelessWidget {
  final String label;
  final Color color;
  const _MilkFlow({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: ShapeDecoration(
      color: color.withValues(alpha: .09),
      shape: const StadiumBorder(),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
    ),
  );
}

/// The small "Clearance" capsule on the milk balance card.
class _ClearanceChip extends StatelessWidget {
  final VoidCallback? onTap;
  const _ClearanceChip({required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: bi('Milk clearance', 'பால் கிளியரன்ஸ்'),
    child: Pressable(
      radius: 14,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(color: Ink.blue.withValues(alpha: .28)),
          ),
          color: Ink.surface.withValues(alpha: .7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.tray_arrow_down_fill,
              size: 12,
              color: onTap == null ? Ink.faint : Ink.blue,
            ),
            const SizedBox(width: 4),
            Text(
              bi('Clearance', 'கிளியரன்ஸ்'),
              style: TextStyle(
                color: onTap == null ? Ink.faint : Ink.blue,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Place heading inside the grouped customer list.
class _GroupHeader extends StatelessWidget {
  final String label;
  final int count;
  final bool highlighted;
  const _GroupHeader({
    required this.label,
    required this.count,
    this.highlighted = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
    child: Row(
      children: [
        Icon(
          CupertinoIcons.location_solid,
          size: 15,
          color: highlighted ? Ink.violetDeep : Ink.muted,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: highlighted ? Ink.violetDeep : Ink.muted,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('· $count', style: TextStyle(color: Ink.faint, fontSize: 13)),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: Ink.violetDeep.withValues(alpha: .1))),
      ],
    ),
  );
}

/// A soft rise-and-fade when a ride card first appears.
class _RideAppear extends StatelessWidget {
  final Widget child;
  const _RideAppear({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Gold.slow,
      curve: Gold.ease,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
    );
  }
}

class _CircleGlassButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  const _CircleGlassButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox.square(
      dimension: 56,
      child: Glass(
        radius: 28,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Center(
          child: Icon(
            icon,
            color: onTap == null ? Ink.faint : Ink.violetDeep,
            size: 25,
          ),
        ),
      ),
    ),
  );
}

class _ProviderBubble extends StatelessWidget {
  final Map<String, dynamic>? person;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const _ProviderBubble({
    this.person,
    this.label = '',
    this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = person;
    return SizedBox(
      width: 72,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            if (p != null)
              _VendorAvatar(person: p, radius: 30, halo: true)
            else
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Ink.violet, Ink.violetDeep],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Ink.violetDeep.withValues(alpha: .3),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
            const SizedBox(height: 6),
            Text(
              p == null ? label : txt(p, 'name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if (p != null)
              Text(
                txt(p, 'place'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Ink.muted, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

/// Every milk provider on one page.
class VendorProvidersScreen extends StatelessWidget {
  final String entryPrefix, session;
  const VendorProvidersScreen({
    super.key,
    this.entryPrefix = '',
    this.session = 'Morning',
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      title: Text(bi('Milk providers', 'பால் வழங்குநர்கள்')),
      actions: [
        if (canRecordEntries)
          IconButton(
            tooltip: ui('Add person'),
            icon: const Icon(CupertinoIcons.person_badge_plus),
            onPressed: () =>
                push(context, const VendorPersonForm(kind: 'supplier')),
          ),
      ],
    ),
    body: Shell(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          Hive.box('vendor_people').listenable(),
          Hive.box('vendor_entries').listenable(),
        ]),
        builder: (context, _) {
          final rows = vendorRows('vendor_entries');
          final providers = vendorRoutePeople(
            vendorRows('vendor_people'),
            rows,
            DateTime.now(),
            session,
            suppliers: true,
          );
          if (providers.isEmpty) {
            return Center(
              child: Text(
                bi('No milk providers yet.', 'பால் வழங்குநர்கள் இல்லை.'),
                style: TextStyle(color: Ink.muted),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            itemCount: providers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final p = providers[i];
              final due = vendorPersonDue(txt(p, 'id'), rows);
              return Glass(
                radius: 24,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: () => push(
                  context,
                  VendorPersonScreen(
                    person: p,
                    intakeKind: 'collection',
                    entryPrefix: entryPrefix,
                    initialSession: session,
                  ),
                ),
                child: Row(
                  children: [
                    _VendorAvatar(person: p, radius: 26, halo: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            txt(p, 'name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            txt(p, 'place'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Ink.muted),
                          ),
                        ],
                      ),
                    ),
                    if (due > 0.001)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            money(due),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            bi('To pay', 'கொடுக்க'),
                            style: TextStyle(
                              color: Ink.amberText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: Ink.faint,
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class _VendorAvatar extends StatelessWidget {
  final Map<String, dynamic> person;
  final double radius;
  final bool halo;
  const _VendorAvatar({
    required this.person,
    this.radius = 22,
    this.halo = false,
  });
  @override
  Widget build(BuildContext context) => GlassAvatar(
    image: personPhoto(person),
    label: txt(person, 'name'),
    radius: radius,
    halo: halo,
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
  final bool volume, groups;
  final String storageKey;
  const VendorCustomizeScreen({
    super.key,
    required this.volume,
    this.groups = false,
    required this.storageKey,
  });
  @override
  State<VendorCustomizeScreen> createState() => _VendorCustomizeScreenState();
}

class _VendorCustomizeScreenState extends State<VendorCustomizeScreen> {
  int _day = DateTime.now().weekday % 7;
  late bool _volume = widget.volume;
  late bool _groups = widget.groups;
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
      await Hive.box('settings').put('${widget.storageKey}_groups', _groups);
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
          Glass(
            radius: 27,
            padding: const EdgeInsets.all(16),
            onTap: () => push(context, const RouteMapsScreen()),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Ink.violet, Ink.violetDeep],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Ink.violetDeep.withValues(alpha: .28),
                        blurRadius: 13,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.map_fill,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bi('Route maps', 'பாதை வரைபடங்கள்'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Ink.navy,
                        ),
                      ),
                      Text(
                        bi(
                          'Record your round, pin notes, lend it for a day',
                          'சுற்றைப் பதிவு செய், குறிப்பு சேர், ஒரு நாள் கொடு',
                        ),
                        maxLines: 2,
                        style: TextStyle(color: Ink.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.chevron_right, size: 16, color: Ink.faint),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Glass(
            radius: 27,
            padding: const EdgeInsets.all(16),
            onTap: () => push(context, const CustomerReportsScreen()),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Ink.violetDeep.withValues(alpha: .1),
                  ),
                  child: Icon(
                    CupertinoIcons.person_crop_rectangle_fill,
                    color: Ink.violetDeep,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bi(
                          'Customer profile reports',
                          'வாடிக்கையாளர் அறிக்கைகள்',
                        ),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Ink.navy,
                        ),
                      ),
                      Text(
                        bi(
                          'Each customer, month by month',
                          'ஒவ்வொரு வாடிக்கையாளருக்கும் மாத வாரியாக',
                        ),
                        style: TextStyle(color: Ink.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.chevron_right, size: 16, color: Ink.faint),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Glass(
            radius: 27,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _groups,
              activeTrackColor: Ink.violetDeep,
              secondary: Icon(
                CupertinoIcons.location_solid,
                color: Ink.violetDeep,
              ),
              title: Text(
                bi('Group customers by place', 'ஊர் வாரியாகப் பிரி'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                bi(
                  'Place bubbles above the list. Start delivers one place at a time.',
                  'பட்டியலுக்கு மேல் ஊர் குமிழ்கள். தொடங்கு ஒவ்வொரு ஊராக விநியோகிக்கும்.',
                ),
              ),
              onChanged: (v) => setState(() => _groups = v),
            ),
          ),
          const SizedBox(height: 27),
          Text(
            bi('Customer order', 'வாடிக்கையாளர் வரிசை'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
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
            style: TextStyle(color: Ink.muted),
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
                              style: TextStyle(color: Ink.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(CupertinoIcons.line_horizontal_3, color: Ink.muted),
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
            child: SwitchListTile.adaptive(
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
                    builder: (ctx) => AppleAlert(
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
                          child: const AppText('OK'),
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
                    builder: (ctx) => AppleAlert(
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
                          child: const AppText('OK'),
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
    // Customers served on credit this ride, with the day they will pay.
    final today = DateTime.now();
    final later =
        <({Map<String, dynamic> person, double amount, DateTime on})>[];
    for (final sale in sales) {
      final owed = numv(sale, 'amount') - numv(sale, 'paid');
      if (owed <= .001) continue;
      final person = people
          .where((p) => p['id'] == sale['personId'])
          .firstOrNull;
      if (person == null) continue;
      final settled = rows.any(
        (r) =>
            r['kind'] == 'payment' &&
            r['personId'] == sale['personId'] &&
            numv(r, 'amount') >= owed - .001,
      );
      if (settled) continue;
      later.add((
        person: person,
        amount: owed,
        on: vendorPaymentDate(person, today.add(const Duration(days: 1))),
      ));
    }
    String payDay(DateTime on) {
      final start = DateTime(today.year, today.month, today.day);
      final days = on.difference(start).inDays;
      if (days <= 1) return bi('Pays tomorrow', 'நாளை செலுத்துவார்');
      return '${bi('Pays on', 'செலுத்தும் நாள்')} ${on.day}/${on.month}';
    }

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
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
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
                  trailing: Icon(CupertinoIcons.star_fill, color: Ink.amber),
                ),
              ),
            ],
            if (later.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                bi('Pays later', 'பிறகு செலுத்துபவர்கள்'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              for (final item in later)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Glass(
                    radius: 22,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        _VendorAvatar(person: item.person, radius: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                txt(item.person, 'name'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                payDay(item.on),
                                style: TextStyle(
                                  color: Ink.redText,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          money(item.amount),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
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
