part of 'main.dart';

// -----------------------------------------------------------------------------
//  Vendor extras: place groups, milk clearance and customer monthly reports.
// -----------------------------------------------------------------------------

/// Places typed differently ("Chennai", " chennai.", "CHENNAI") share a key,
/// so every customer from one place lands in one group.
String vendorPlaceKey(String place) =>
    place.trim().toLowerCase().replaceAll(RegExp(r'[\s.,_/\\-]+'), ' ').trim();

class VendorPlaceGroup {
  final String key, label;
  final List<Map<String, dynamic>> people;
  const VendorPlaceGroup(this.key, this.label, this.people);
}

/// Groups people by place in first-seen order, keeping each person's order.
/// The label is the spelling most people use. People without a place come last.
List<VendorPlaceGroup> vendorPlaceGroups(
  Iterable<Map<String, dynamic>> people,
) {
  final order = <String>[];
  final members = <String, List<Map<String, dynamic>>>{};
  final spellings = <String, Map<String, int>>{};
  for (final p in people) {
    final spelling = txt(p, 'place').trim();
    final key = vendorPlaceKey(spelling);
    if (!members.containsKey(key)) order.add(key);
    members.putIfAbsent(key, () => []).add(p);
    if (spelling.isNotEmpty) {
      final counts = spellings.putIfAbsent(key, () => {});
      counts[spelling] = (counts[spelling] ?? 0) + 1;
    }
  }
  order.sort((a, b) => a.isEmpty == b.isEmpty ? 0 : (a.isEmpty ? 1 : -1));
  return [
    for (final key in order)
      VendorPlaceGroup(
        key,
        key.isEmpty
            ? bi('No place', 'இடம் இல்லை')
            : _mostUsed(spellings[key] ?? const {}),
        members[key]!,
      ),
  ];
}

String _mostUsed(Map<String, int> counts) {
  var best = '';
  var most = 0;
  for (final entry in counts.entries) {
    if (entry.value > most) {
      best = entry.key;
      most = entry.value;
    }
  }
  return best;
}

/// Every place already entered, most used first, for typing suggestions.
List<String> vendorKnownPlaces() {
  if (!Hive.isBoxOpen('vendor_people')) return const [];
  final groups = vendorPlaceGroups(vendorRows('vendor_people'))
    ..removeWhere((g) => g.key.isEmpty)
    ..sort((a, b) => b.people.length.compareTo(a.people.length));
  return [for (final g in groups) g.label];
}

/// Place field that suggests places already used. Choosing a suggestion keeps
/// one spelling, so customers from the same place always group together.
class VendorPlaceField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final IconData? icon;
  const VendorPlaceField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.icon = CupertinoIcons.location,
  });
  @override
  State<VendorPlaceField> createState() => _VendorPlaceFieldState();
}

class _VendorPlaceFieldState extends State<VendorPlaceField> {
  final _focus = FocusNode();
  late final List<String> _places = vendorKnownPlaces();
  late final Map<String, int> _counts = {
    for (final g in vendorPlaceGroups(
      Hive.isBoxOpen('vendor_people')
          ? vendorRows('vendor_people')
          : const <Map<String, dynamic>>[],
    ))
      g.key: g.people.length,
  };

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final places = _places;
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final typed = vendorPlaceKey(value.text);
        if (typed.isEmpty) return const Iterable<String>.empty();
        return places
            .where((p) {
              final key = vendorPlaceKey(p);
              return key.contains(typed) && key != typed;
            })
            .take(6);
      },
      fieldViewBuilder: (context, textController, focusNode, onSubmit) =>
          TextFormField(
            controller: textController,
            focusNode: focusNode,
            maxLength: 160,
            textCapitalization: TextCapitalization.words,
            decoration: fieldStyle(widget.label, icon: widget.icon),
            validator: widget.validator,
            onFieldSubmitted: (_) => onSubmit(),
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 260),
            child: Glass(
              radius: 21,
              opacity: .86,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Material(
                type: MaterialType.transparency,
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final option in options)
                      InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.location_solid,
                                size: 16,
                                color: Ink.violetDeep,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  option,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Ink.navy,
                                  ),
                                ),
                              ),
                              Text(
                                '${_counts[vendorPlaceKey(option)] ?? 0}',
                                style: TextStyle(
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
            ),
          ),
        ),
      ),
    );
  }
}

/// Place bubbles between the Customers title and the people. Selected places
/// rise to the top of the list; Start then delivers that place first.
class VendorPlaceBubbles extends StatelessWidget {
  final List<VendorPlaceGroup> groups;
  final String? selected;
  final ValueChanged<String?> onSelected;

  /// Finished stops per place during a ride, shown as "done/total".
  final Map<String, int>? done;
  const VendorPlaceBubbles({
    super.key,
    required this.groups,
    required this.selected,
    required this.onSelected,
    this.done,
  });

  @override
  Widget build(BuildContext context) {
    final total = groups.fold<int>(0, (s, g) => s + g.people.length);
    final finished = done?.values.fold<int>(0, (s, v) => s + v);
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: [
          _PlaceBubble(
            label: bi('All', 'அனைத்தும்'),
            count: finished == null ? '$total' : '$finished/$total',
            selected: selected == null,
            icon: CupertinoIcons.circle_grid_3x3_fill,
            onTap: () => onSelected(null),
          ),
          for (final g in groups)
            _PlaceBubble(
              label: g.label,
              count: done == null
                  ? '${g.people.length}'
                  : '${done![g.key] ?? 0}/${g.people.length}',
              selected: selected == g.key,
              icon: CupertinoIcons.location_solid,
              onTap: () => onSelected(selected == g.key ? null : g.key),
            ),
        ],
      ),
    );
  }
}

class _PlaceBubble extends StatelessWidget {
  final String label, count;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  const _PlaceBubble({
    required this.label,
    required this.count,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label $count',
        child: Pressable(
          radius: 23,
          onTap: onTap,
          child: AnimatedContainer(
            duration: reduce ? Duration.zero : Gold.base,
            curve: Gold.ease,
            padding: const EdgeInsets.fromLTRB(13, 0, 6, 0),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: selected ? Ink.tint : Ink.surface,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : Ink.violetDeep,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: selected ? Colors.white : Ink.navy,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 26),
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: selected
                        ? Colors.white.withValues(alpha: .24)
                        : Ink.violetDeep.withValues(alpha: .09),
                  ),
                  child: Text(
                    count,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : Ink.violetDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Milk clearance
// -----------------------------------------------------------------------------

const Map<String, dynamic> vendorFridge = {
  'id': '_fridge',
  'name': 'Fridge',
  'kind': 'fridge',
};

Future<void> showMilkClearance(BuildContext context) async {
  if (!canRecordEntries) {
    snack(context, ui('Permission denied'));
    return;
  }
  final balance = vendorMilkBalance(vendorRows('vendor_entries'));
  if (balance <= .0001) {
    snack(
      context,
      bi('No milk in hand to clear.', 'கிளியர் செய்ய பால் இருப்பு இல்லை.'),
    );
    return;
  }
  await showAppleSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Ink.canvasTop,
    builder: (_) => const _MilkClearanceSheet(),
  );
}

class _MilkClearanceSheet extends StatefulWidget {
  const _MilkClearanceSheet();
  @override
  State<_MilkClearanceSheet> createState() => _MilkClearanceSheetState();
}

class _MilkClearanceSheetState extends State<_MilkClearanceSheet> {
  late final double _balance = vendorMilkBalance(vendorRows('vendor_entries'));
  late final _qty = TextEditingController(text: vendorFieldNumber(_balance));
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _place = TextEditingController();
  final _note = TextEditingController();
  int _target = 0; // 0 person, 1 fridge, 2 new person
  String? _personId;
  String _entryId = '';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_qty, _search, _name, _place, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final quantity = toDouble(_qty.text);
    if (quantity <= 0 || quantity > _balance + .000001) {
      snack(
        context,
        bi(
          'Enter litres up to ${vendorFieldNumber(_balance)} L',
          '${vendorFieldNumber(_balance)} லி வரை அளவை உள்ளிடவும்',
        ),
      );
      return;
    }
    Map<String, dynamic>? person;
    if (_target == 0) {
      person = vendorRows(
        'vendor_people',
      ).where((p) => p['id'] == _personId).firstOrNull;
      if (person == null) {
        snack(context, bi('Choose a person', 'ஒருவரைத் தேர்வு செய்யவும்'));
        return;
      }
    } else if (_target == 1) {
      person = vendorFridge;
    } else if (_name.text.trim().isEmpty) {
      snack(context, ui('Enter a name'));
      return;
    }
    setState(() => _busy = true);
    try {
      person ??= await vendorQuickPerson(
        name: _name.text.trim(),
        place: _place.text.trim(),
      );
      _entryId = _entryId.isEmpty
          ? 'clear_${DateTime.now().microsecondsSinceEpoch}_${settingText('deviceId', 'device')}'
          : _entryId;
      await VendorLedger.record(
        id: _entryId,
        person: person,
        kind: 'clearance',
        quantity: quantity,
        session: vendorSessionNow(),
        notes: _note.text.trim(),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      snack(
        context,
        bi(
          '${vendorFieldNumber(quantity)} L cleared',
          '${vendorFieldNumber(quantity)} லி கிளியர் செய்யப்பட்டது',
        ),
      );
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _quick(String label, double value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(
      label: AppText(label),
      onPressed: () => setState(() => _qty.text = vendorFieldNumber(value)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final people =
        vendorRows('vendor_people')
            .where(
              (p) =>
                  query.isEmpty ||
                  '${p['name']} ${p['place']}'.toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) => txt(a, 'name').compareTo(txt(b, 'name')));
    final quantity = toDouble(_qty.text);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Ink.blue.withValues(alpha: .16),
                          Ink.violet.withValues(alpha: .14),
                        ],
                      ),
                    ),
                    child: Icon(
                      CupertinoIcons.tray_arrow_down_fill,
                      color: Ink.blue,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bi('Milk clearance', 'பால் கிளியரன்ஸ்'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Ink.navy,
                          ),
                        ),
                        AppText(
                          '${bi('In hand', 'கையிருப்பு')} ${vendorFieldNumber(_balance)} L',
                          style: TextStyle(color: Ink.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 21),
              TextField(
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                decoration: fieldStyle(
                  bi('Litres to clear', 'கிளியர் செய்யும் அளவு (லி)'),
                  icon: CupertinoIcons.drop_fill,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                children: [
                  _quick(
                    '${bi('All', 'முழுவதும்')} ${vendorFieldNumber(_balance)} L',
                    _balance,
                  ),
                  _quick(
                    '${bi('Half', 'பாதி')} ${vendorFieldNumber(_balance / 2)} L',
                    _balance / 2,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LiquidSegmentBar(
                labels: [
                  bi('Person', 'நபர்'),
                  bi('Fridge', 'ஃப்ரிட்ஜ்'),
                  bi('New person', 'புதிய நபர்'),
                ],
                icons: const [
                  CupertinoIcons.person_fill,
                  CupertinoIcons.snow,
                  CupertinoIcons.person_add_solid,
                ],
                index: _target,
                onChanged: (i) => setState(() => _target = i),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : Gold.base,
                switchInCurve: Gold.ease,
                switchOutCurve: Gold.easeIn,
                child: switch (_target) {
                  0 => Column(
                    key: const ValueKey('person'),
                    children: [
                      TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(CupertinoIcons.search),
                          hintText: bi(
                            'Search name or place',
                            'பெயர் அல்லது இடம் தேடு',
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: Glass(
                          radius: 21,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: people.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(21),
                                  child: Text(
                                    bi('No people found.', 'யாரும் இல்லை.'),
                                    style: TextStyle(color: Ink.muted),
                                  ),
                                )
                              : ListView(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  children: [
                                    for (final p in people)
                                      _PickRow(
                                        person: p,
                                        selected: _personId == p['id'],
                                        onTap: () => setState(
                                          () => _personId = txt(p, 'id'),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                  1 => Glass(
                    key: const ValueKey('fridge'),
                    radius: 21,
                    tint: Ink.blue.withValues(alpha: .05),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.snow, color: Ink.blue, size: 30),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Text(
                            bi(
                              'The milk goes into the fridge and leaves today\'s stock. No money changes.',
                              'பால் ஃப்ரிட்ஜுக்குச் செல்லும்; இன்றைய இருப்பிலிருந்து குறையும். பணக் கணக்கு மாறாது.',
                            ),
                            style: TextStyle(color: Ink.body),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ => Column(
                    key: const ValueKey('new'),
                    children: [
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: fieldStyle(
                          ui('Name'),
                          icon: CupertinoIcons.person,
                        ),
                      ),
                      const SizedBox(height: 12),
                      VendorPlaceField(
                        controller: _place,
                        label: bi('Place · optional', 'இடம் · விருப்பம்'),
                      ),
                    ],
                  ),
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                maxLength: 200,
                decoration: fieldStyle(
                  bi('Note · optional', 'குறிப்பு · விருப்பம்'),
                  icon: CupertinoIcons.text_bubble,
                ),
              ),
              const SizedBox(height: 8),
              LiquidButton(
                label: quantity > 0
                    ? bi(
                        'Clear ${vendorFieldNumber(quantity)} L',
                        '${vendorFieldNumber(quantity)} லி கிளியர் செய்',
                      )
                    : bi('Clear milk', 'பாலை கிளியர் செய்'),
                icon: CupertinoIcons.checkmark_alt,
                start: Ink.blue,
                end: Ink.blue,
                busy: _busy,
                height: 56,
                radius: 28,
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  final Map<String, dynamic> person;
  final bool selected;
  final VoidCallback onTap;
  const _PickRow({
    required this.person,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          GlassAvatar(
            image: personPhoto(person),
            label: txt(person, 'name'),
            radius: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txt(person, 'name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Ink.navy,
                  ),
                ),
                Text(
                  [
                    if (txt(person, 'place').isNotEmpty) txt(person, 'place'),
                    person['kind'] == 'supplier'
                        ? bi('Provider', 'வழங்குநர்')
                        : bi('Buyer', 'வாங்குபவர்'),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Ink.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: Gold.fast,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? Ink.tint : Colors.transparent,
              border: Border.all(
                color: selected ? Ink.tint : Ink.faint,
                width: 1.6,
              ),
            ),
            child: selected
                ? const Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 16,
                    color: Colors.white,
                  )
                : null,
          ),
        ],
      ),
    ),
  );
}

/// A customer created from a quick sheet uses the same defaults as the form.
Future<Map<String, dynamic>> vendorQuickPerson({
  required String name,
  required String place,
}) async {
  if (!canRecordEntries) throw StateError(ui('Permission denied'));
  final now = DateTime.now();
  final id =
      '${settingText('deviceId', 'device')}_${now.microsecondsSinceEpoch}';
  final data = <String, dynamic>{
    'id': id,
    'cloudId': id,
    'kind': 'customer',
    'name': name,
    'place': place,
    'contact': '',
    'imageData': '',
    'quantity': 1.0,
    'price': defaultMilkPrice(),
    'days': <int>[],
    'sessions': const ['Morning', 'Evening'],
    'paymentCycle': 'Daily',
    'paymentDays': const [0, 1, 2, 3, 4, 5, 6],
    'paymentMonthDay': 1,
    'createdAt': now.toIso8601String(),
    'updatedAtMillis': now.millisecondsSinceEpoch,
  };
  await Hive.box('vendor_people').put(id, data);
  AutoSyncService.markDirty(reason: 'vendor person');
  return data;
}

// -----------------------------------------------------------------------------
//  Customer profile reports
// -----------------------------------------------------------------------------

/// Every customer with this month's litres and balance; each opens a
/// month-by-month report.
class CustomerReportsScreen extends StatefulWidget {
  const CustomerReportsScreen({super.key});
  @override
  State<CustomerReportsScreen> createState() => _CustomerReportsScreenState();
}

class _CustomerReportsScreenState extends State<CustomerReportsScreen> {
  String _search = '';
  bool _suppliers = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      title: Text(bi('Customer reports', 'வாடிக்கையாளர் அறிக்கைகள்')),
    ),
    body: Shell(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          Hive.box('vendor_people').listenable(),
          Hive.box('vendor_entries').listenable(),
        ]),
        builder: (context, _) {
          final rows = vendorRows('vendor_entries');
          final month = thisMonth();
          final query = _search.trim().toLowerCase();
          final people =
              vendorRows('vendor_people')
                  .where(
                    (p) =>
                        p['kind'] == (_suppliers ? 'supplier' : 'customer') &&
                        (query.isEmpty ||
                            '${p['name']} ${p['place']}'.toLowerCase().contains(
                              query,
                            )),
                  )
                  .toList()
                ..sort((a, b) => txt(a, 'name').compareTo(txt(b, 'name')));
          return ListView(
            padding: const EdgeInsets.fromLTRB(21, 8, 21, 40),
            children: [
              LiquidSegmentBar(
                labels: [
                  bi('Buyers', 'வாங்குபவர்கள்'),
                  bi('Providers', 'வழங்குநர்கள்'),
                ],
                index: _suppliers ? 1 : 0,
                onChanged: (i) => setState(() => _suppliers = i == 1),
              ),
              const SizedBox(height: 13),
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(CupertinoIcons.search),
                  hintText: bi(
                    'Search name or place',
                    'பெயர் அல்லது இடம் தேடு',
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 16),
              if (people.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(34),
                  child: Text(
                    bi('No people yet.', 'யாரும் இல்லை.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Ink.muted),
                  ),
                ),
              for (final (i, p) in people.indexed)
                Reveal(
                  index: math.min(i, 8),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CustomerReportRow(
                      person: p,
                      rows: rows,
                      month: month,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _CustomerReportRow extends StatelessWidget {
  final Map<String, dynamic> person;
  final List<Map<String, dynamic>> rows;
  final String month;
  const _CustomerReportRow({
    required this.person,
    required this.rows,
    required this.month,
  });
  @override
  Widget build(BuildContext context) {
    final id = txt(person, 'id');
    final mine = rows.where((r) => r['personId'] == id).toList();
    final litres = mine
        .where(
          (r) =>
              txt(r, 'date').startsWith(month) &&
              ['sale', 'collection', 'purchase'].contains(r['kind']),
        )
        .fold(0.0, (s, r) => s + numv(r, 'quantity'));
    final due = vendorPersonDue(id, mine);
    return Glass(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => push(context, CustomerMonthlyReportScreen(person: person)),
      child: Row(
        children: [
          GlassAvatar(
            image: personPhoto(person),
            label: txt(person, 'name'),
            radius: 24,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txt(person, 'name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
                AppText(
                  [
                    if (txt(person, 'place').isNotEmpty) txt(person, 'place'),
                    '${bi('This month', 'இந்த மாதம்')} ${vendorFieldNumber(litres)} L',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Ink.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppText(
                due > .001 ? money(due) : bi('Settled', 'தீர்ந்தது'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: due > .001 ? Ink.redText : Ink.greenText,
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 14, color: Ink.faint),
            ],
          ),
        ],
      ),
    );
  }
}

/// One person's month: litres per day and session, amounts, payments and the
/// opening and closing balance. Any month can be chosen.
class CustomerMonthlyReportScreen extends StatefulWidget {
  final Map<String, dynamic> person;
  const CustomerMonthlyReportScreen({super.key, required this.person});
  @override
  State<CustomerMonthlyReportScreen> createState() =>
      _CustomerMonthlyReportScreenState();
}

class _CustomerMonthlyReportScreenState
    extends State<CustomerMonthlyReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  String get _key => '${_month.year}-${two(_month.month)}';

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  Future<void> _export(
    List<Map<String, dynamic>> rows,
    double opening,
    double closing,
  ) async {
    final out = StringBuffer(
      'Name,${csv(txt(widget.person, 'name'))}\n'
      'Place,${csv(txt(widget.person, 'place'))}\n'
      'Month,${csv(_key)}\n'
      'Opening balance,${opening.toStringAsFixed(2)}\n'
      'Date,Time,Session,Kind,Quantity (L),Price,Amount,Paid\n',
    );
    for (final r in rows) {
      out.writeln(
        [
          'date',
          'time',
          'session',
          'kind',
          'quantity',
          'price',
          'amount',
          'paid',
        ].map((k) => csv('${r[k] ?? ''}')).join(','),
      );
    }
    out.writeln('Closing balance,${closing.toStringAsFixed(2)}');
    final ok = await downloadCsvFile(
      '${safeFileName(txt(widget.person, 'name'))}_$_key.csv',
      out.toString(),
    );
    if (mounted && ok) {
      snack(context, bi('Report saved', 'அறிக்கை சேமிக்கப்பட்டது'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    body: AnimatedBuilder(
      animation: Hive.box('vendor_entries').listenable(),
      builder: (context, _) {
        final id = txt(widget.person, 'id');
        final supplier = widget.person['kind'] == 'supplier';
        final all =
            vendorRows('vendor_entries')
                .where((r) => r['personId'] == id && r['kind'] != 'clearance')
                .toList()
              ..sort((a, b) {
                final d = txt(a, 'date').compareTo(txt(b, 'date'));
                return d != 0 ? d : txt(a, 'time').compareTo(txt(b, 'time'));
              });
        final monthRows = all
            .where((r) => txt(r, 'date').startsWith(_key))
            .toList();
        final opening = vendorPersonDue(
          id,
          all.where((r) => txt(r, 'date').compareTo('$_key-01') < 0),
        );
        final closing = opening + vendorPersonDue(id, monthRows);
        final milk = monthRows.where((r) => r['kind'] != 'payment');
        final litres = milk.fold(0.0, (s, r) => s + numv(r, 'quantity'));
        final amount = milk.fold(0.0, (s, r) => s + numv(r, 'amount'));
        final received =
            milk.fold(0.0, (s, r) => s + numv(r, 'paid')) +
            monthRows
                .where((r) => r['kind'] == 'payment')
                .fold(0.0, (s, r) => s + numv(r, 'amount'));
        final days = <String, List<Map<String, dynamic>>>{};
        for (final r in monthRows) {
          days.putIfAbsent(txt(r, 'date'), () => []).add(r);
        }
        final now = DateTime.now();
        final latest = !_month.isBefore(DateTime(now.year, now.month));
        return Shell(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Ink.canvasTop.withValues(alpha: .92),
                surfaceTintColor: Colors.transparent,
                title: Text(
                  txt(widget.person, 'name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: bi('Export report', 'அறிக்கையைப் பதிவிறக்கு'),
                    icon: Icon(
                      CupertinoIcons.arrow_down_doc,
                      color: Ink.violetDeep,
                    ),
                    onPressed: monthRows.isEmpty
                        ? null
                        : () => _export(monthRows, opening, closing),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 8, 21, 40),
                sliver: SliverList.list(
                  children: [
                    Center(
                      child: GlassPortrait(
                        image: personPhoto(widget.person),
                        title: txt(widget.person, 'name'),
                        subtitle: txt(
                          widget.person,
                          'place',
                          supplier
                              ? bi('Milk provider', 'பால் வழங்குநர்')
                              : bi('Milk buyer', 'பால் வாங்குபவர்'),
                        ),
                        size: 110,
                      ),
                    ),
                    const SizedBox(height: 21),
                    Glass(
                      radius: 27,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: bi('Previous month', 'முந்தைய மாதம்'),
                            icon: const Icon(CupertinoIcons.chevron_left),
                            onPressed: () => _shift(-1),
                          ),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : Gold.base,
                              child: AppText(
                                monthLabel('$_key-01'),
                                key: ValueKey(_key),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Ink.navy,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: bi('Next month', 'அடுத்த மாதம்'),
                            icon: const Icon(CupertinoIcons.chevron_right),
                            onPressed: latest ? null : () => _shift(1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Expanded(
                          child: _ReportFigure(
                            icon: CupertinoIcons.drop_fill,
                            color: Ink.violetDeep,
                            value: '${vendorFieldNumber(litres)} L',
                            label: supplier
                                ? bi('Milk received', 'பெற்ற பால்')
                                : bi('Milk delivered', 'கொடுத்த பால்'),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: _ReportFigure(
                            icon: CupertinoIcons.money_dollar_circle_fill,
                            color: Ink.blue,
                            value: money(amount),
                            label: bi('Milk value', 'பால் மதிப்பு'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Expanded(
                          child: _ReportFigure(
                            icon: CupertinoIcons.checkmark_seal_fill,
                            color: Ink.greenText,
                            value: money(received),
                            label: supplier
                                ? bi('Paid', 'செலுத்தியது')
                                : bi('Received', 'பெற்றது'),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: _ReportFigure(
                            icon: CupertinoIcons.calendar,
                            color: Ink.amberText,
                            value:
                                '${days.values.where((d) => d.any((r) => r['kind'] != 'payment')).length}',
                            label: bi('Milk days', 'பால் நாட்கள்'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Glass(
                      radius: 24,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          _TotalLine(
                            label: bi('Opening balance', 'தொடக்க நிலுவை'),
                            value: money(opening),
                          ),
                          const SizedBox(height: 6),
                          _TotalLine(
                            label: bi('This month', 'இந்த மாதம்'),
                            value: money(amount),
                          ),
                          const SizedBox(height: 6),
                          _TotalLine(
                            label: supplier
                                ? bi('Paid', 'செலுத்தியது')
                                : bi('Received', 'பெற்றது'),
                            value: '− ${money(received)}',
                          ),
                          const Divider(height: 21),
                          _TotalLine(
                            label: supplier
                                ? bi('Balance to pay', 'கொடுக்க வேண்டியது')
                                : bi('Balance to collect', 'பெற வேண்டியது'),
                            value: money(closing),
                            strong: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 27),
                    Text(
                      bi('Day by day', 'நாள் வாரியாக'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Ink.navy,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (days.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 34),
                        child: Text(
                          bi(
                            'No entries in this month.',
                            'இந்த மாதத்தில் பதிவுகள் இல்லை.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Ink.muted),
                        ),
                      ),
                    if (days.isNotEmpty)
                      Glass(
                        radius: 24,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            for (final (i, day) in days.entries.indexed) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                  color: Ink.violetDeep.withValues(alpha: .08),
                                ),
                              _ReportDay(date: day.key, rows: day.value),
                            ],
                          ],
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
  );
}

class _ReportFigure extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, label;
  const _ReportFigure({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => Glass(
    radius: 24,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AppText(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Ink.navy,
              letterSpacing: -.3,
            ),
          ),
        ),
        AppText(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Ink.muted, fontSize: 13),
        ),
      ],
    ),
  );
}

class _ReportDay extends StatelessWidget {
  final String date;
  final List<Map<String, dynamic>> rows;
  const _ReportDay({required this.date, required this.rows});

  @override
  Widget build(BuildContext context) {
    final day = DateTime.tryParse(date);
    double litres(String session) => rows
        .where((r) => r['kind'] != 'payment' && r['session'] == session)
        .fold(0.0, (s, r) => s + numv(r, 'quantity'));
    final morning = litres('Morning'), evening = litres('Evening');
    final amount = rows
        .where((r) => r['kind'] != 'payment')
        .fold(0.0, (s, r) => s + numv(r, 'amount'));
    final paid =
        rows
            .where((r) => r['kind'] != 'payment')
            .fold(0.0, (s, r) => s + numv(r, 'paid')) +
        rows
            .where((r) => r['kind'] == 'payment')
            .fold(0.0, (s, r) => s + numv(r, 'amount'));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Column(
              children: [
                AppText(
                  day == null ? date : '${day.day}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Ink.navy,
                  ),
                ),
                if (day != null)
                  Text(
                    (tamilUi ? _dayTamil : _dayNames)[day.weekday % 7]
                        .characters
                        .take(3)
                        .toString(),
                    style: TextStyle(color: Ink.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (morning > 0)
                  _SessionPill(
                    icon: CupertinoIcons.sun_max_fill,
                    label: '${vendorFieldNumber(morning)} L',
                    color: Ink.amberText,
                  ),
                if (evening > 0)
                  _SessionPill(
                    icon: CupertinoIcons.moon_fill,
                    label: '${vendorFieldNumber(evening)} L',
                    color: Ink.violetDeep,
                  ),
                if (paid > 0)
                  _SessionPill(
                    icon: CupertinoIcons.money_dollar,
                    label: money(paid),
                    color: Ink.greenText,
                  ),
              ],
            ),
          ),
          if (amount > 0)
            AppText(
              money(amount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Ink.navy,
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SessionPill({
    required this.icon,
    required this.label,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: ShapeDecoration(
      shape: const StadiumBorder(),
      color: color.withValues(alpha: .09),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        AppText(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
