part of 'main.dart';

String bi(String en, String ta) => tamilUi ? ta : en;
const businessTabs = [
  'Ranch',
  'Vendor',
  'Reports',
  'Social',
  'Chat',
  'Profile',
];
String get _profileKey =>
    firebaseReady ? FirebaseAuth.instance.currentUser?.uid ?? 'local' : 'local';
Map<String, dynamic> get purposeProfile =>
    asMap(asMap(settingValue('purposeProfiles', {}))[_profileKey] ?? {});
bool get purposeChosen =>
    ['Ranch', 'Vendor', 'Market'].contains(purposeProfile['purpose']);
String get appPurpose => txt(purposeProfile, 'purpose', 'Ranch');
bool get secondaryWorkspaceEnabled =>
    purposeProfile['secondaryEnabled'] == true;
List<String> defaultNavigation(
  String purpose, {
  bool secondaryEnabled = false,
}) => switch (purpose) {
  'Vendor' || 'Market' =>
    secondaryEnabled
        ? ['Vendor', 'Ranch', 'Reports', 'Social']
        : ['Vendor', 'Reports', 'Social', 'Chat'],
  _ =>
    secondaryEnabled
        ? ['Ranch', 'Vendor', 'Social', 'Chat']
        : ['Ranch', 'Social', 'Chat', 'Profile'],
};
List<String> navigationOrder() {
  final allowed = defaultNavigation(
    appPurpose,
    secondaryEnabled: secondaryWorkspaceEnabled,
  );
  final raw = purposeProfile['order'];
  final saved = raw is List
      ? raw.where((id) => businessTabs.contains(id)).toList()
      : null;
  if (saved is List &&
      saved.length == allowed.length &&
      saved.toSet().containsAll(allowed)) {
    return saved.cast<String>();
  }
  return allowed;
}

Future<void> savePurpose(
  String purpose,
  List<String> order, {
  bool secondaryEnabled = false,
}) async {
  final allowed = defaultNavigation(
    purpose,
    secondaryEnabled: secondaryEnabled,
  );
  if (!['Ranch', 'Vendor', 'Market'].contains(purpose) ||
      order.length != allowed.length ||
      !order.toSet().containsAll(allowed)) {
    throw ArgumentError('Invalid preferences');
  }
  await setSetting('purposeProfiles', {
    ...asMap(settingValue('purposeProfiles', {})),
    _profileKey: {
      'purpose': purpose,
      'order': order,
      'secondaryEnabled': secondaryEnabled,
    },
  });
}

class PreferencesScreen extends StatefulWidget {
  final bool onboarding;
  const PreferencesScreen({super.key, this.onboarding = false});
  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late String _purpose = appPurpose;
  late List<String> _order = navigationOrder();
  late bool _secondary = secondaryWorkspaceEnabled;
  bool _saving = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      title: AppText(widget.onboarding ? 'Welcome to VIMO' : 'Preferences'),
      automaticallyImplyLeading: !widget.onboarding,
    ),
    body: Shell(
      child: ListView(
        padding: const EdgeInsets.all(21),
        children: [
          Text(
            bi('Made for your everyday.', 'உங்கள் அன்றாட வேலைகளுக்காக.'),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            bi(
              'What will you use VIMO for?',
              'VIMO செயலியை எதற்காகப் பயன்படுத்தப் போகிறீர்கள்?',
            ),
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 20),
          _InsetGroup(
            children: [
              for (final item in <(String, String, IconData)>[
                (
                  'Ranch',
                  bi(
                    'Care for animals and manage your ranch',
                    'மாட்டுத் தொழுவம் மற்றும் கால்நடை பராமரிப்பு',
                  ),
                  CupertinoIcons.house,
                ),
                (
                  'Vendor',
                  bi(
                    'Buy milk and deliver to homes and shops',
                    'பால் வாங்கி வீடுகள், கடைகளுக்கு விற்பனை',
                  ),
                  CupertinoIcons.drop,
                ),
                (
                  'Market',
                  bi(
                    'Sales, stock and business reports',
                    'விற்பனை, இருப்பு மற்றும் வணிக அறிக்கைகள்',
                  ),
                  CupertinoIcons.bag,
                ),
              ])
                ListTile(
                  leading: item.$1 == 'Vendor'
                      ? MilkVendorIcon(
                          size: 34,
                          color: _purpose == item.$1 ? Colors.white : _blue,
                        )
                      : Icon(
                          item.$3,
                          color: _purpose == item.$1 ? Colors.white : _blue,
                        ),
                  title: AppText(item.$1),
                  subtitle: Text(item.$2),
                  selected: _purpose == item.$1,
                  selectedTileColor: Ink.violetDeep,
                  selectedColor: Colors.white,
                  onTap: () => setState(() {
                    _purpose = item.$1;
                    _secondary = false;
                    _order = defaultNavigation(_purpose);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            bi(
              'You can enable the other workspace later in Settings → Preferences.',
              'மற்ற பணிப்பகுதியை பின்னர் அமைப்புகள் → விருப்பங்களில் இயக்கலாம்.',
            ),
            style: const TextStyle(color: Ink.muted),
          ),
          if (!widget.onboarding) ...[
            const SizedBox(height: 18),
            SwitchListTile.adaptive(
              title: Text(
                _purpose == 'Ranch'
                    ? bi(
                        'I also sell milk · Enable Vendor',
                        'பாலும் விற்கிறேன் · விற்பனையாளர் பகுதி',
                      )
                    : bi(
                        'I have cows too · Enable Ranch',
                        'மாடுகளும் உள்ளன · தொழுவம் பகுதி',
                      ),
              ),
              value: _secondary,
              onChanged: (value) => setState(() {
                _secondary = value;
                _order = defaultNavigation(_purpose, secondaryEnabled: value);
              }),
            ),
            SwitchListTile.adaptive(
              title: Text(
                bi(
                  'Sync with my ranch members',
                  'என் தொழுவ உறுப்பினர்களுடன் ஒத்திசைவு',
                ),
              ),
              subtitle: Text(
                bi(
                  'Entries stay on this device. Enable to share with the same ranch through Firebase.',
                  'பதிவுகள் இந்த சாதனத்தில் சேமிக்கப்படும். அதே தொழுவத்துடன் Firebase மூலம் பகிர இயக்கவும்.',
                ),
              ),
              value: CloudSyncService.sharedDataEnabled,
              onChanged: (value) async {
                await setSetting('workspaceSyncEnabled', value);
                await CollaborationRealtimeSyncService.stop();
                if (value) {
                  AutoSyncService.markDirty(reason: 'enable ranch sharing');
                }
                await CollaborationRealtimeSyncService.ensureStarted();
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 28),
            Text(
              bi('Tab order', 'பக்க வரிசை'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorderItem: (oldIndex, newIndex) => setState(() {
                _order.insert(newIndex, _order.removeAt(oldIndex));
              }),
              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                key: ValueKey(_order[i]),
                index: i,
                child: Glass(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: AppText(_order[i]),
                    leading: Text((i + 1).toString()),
                    trailing: const Icon(CupertinoIcons.line_horizontal_3),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await savePurpose(
                        _purpose,
                        _order,
                        secondaryEnabled: _secondary,
                      );
                      if (context.mounted && !widget.onboarding) {
                        Navigator.pop(context);
                      }
                    } catch (_) {
                      if (context.mounted) {
                        snack(context, ui('Unable to save. Try again.'));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: AppText(widget.onboarding ? 'Get started' : 'Save'),
            ),
          ),
        ],
      ),
    ),
  );
}

List<Map<String, dynamic>> vendorRows(String box) => Hive.box(box)
    .toMap()
    .entries
    .where((e) => e.value is Map)
    .map((e) => {...asMap(e.value), '_key': e.key})
    .toList();
double vendorMilkBalance(Iterable<Map<String, dynamic>> entries) =>
    vendorOpeningBalance(entries) +
    entries
        .where((r) => r['stockScope'] == 'vendor_v2')
        .fold(
          0.0,
          (total, r) =>
              total +
              (r['kind'] == 'purchase' || r['kind'] == 'collection'
                  ? numv(r, 'quantity')
                  : r['kind'] == 'sale'
                  ? -numv(r, 'quantity')
                  : 0),
        );
double vendorPersonDue(
  String personId,
  Iterable<Map<String, dynamic>> entries,
) => entries
    .where((r) => r['personId'] == personId)
    .fold(
      0.0,
      (total, r) =>
          total +
          (r['kind'] == 'payment'
              ? -numv(r, 'amount')
              : numv(r, 'amount') - numv(r, 'paid')),
    );
bool vendorDeliveryDue(
  Map<String, dynamic> person,
  DateTime date,
  String session,
) =>
    person['kind'] == 'customer' &&
    (person['days'] is List &&
        ((person['days'] as List).isEmpty ||
            (person['days'] as List).contains(date.weekday % 7))) &&
    (person['sessions'] is List &&
        (person['sessions'] as List).contains(session));

class VendorLedger {
  static bool _busy = false;
  static Future<void> record({
    required String id,
    required Map<String, dynamic> person,
    required String kind,
    double quantity = 0,
    double price = 0,
    double paid = 0,
    double payment = 0,
    String session = 'Morning',
    String notes = '',
  }) async {
    if (_busy) {
      throw StateError(
        bi(
          'Another entry is saving. Try again.',
          'மற்றொரு பதிவு சேமிக்கப்படுகிறது. மீண்டும் முயற்சிக்கவும்.',
        ),
      );
    }
    if (!canRecordEntries) throw StateError(ui('Permission denied'));
    if (id.isEmpty ||
        txt(person, 'id').isEmpty ||
        notes.length > 500 ||
        !['collection', 'purchase', 'sale', 'payment'].contains(kind) ||
        (['collection', 'purchase'].contains(kind) &&
            person['kind'] != 'supplier') ||
        (kind == 'sale' && person['kind'] != 'customer') ||
        ![quantity, price, paid, payment].every((n) => n.isFinite && n >= 0) ||
        (kind != 'payment' &&
            (quantity <= 0 || price <= 0 || paid > quantity * price)) ||
        (kind == 'payment' && payment <= 0)) {
      throw StateError(
        bi(
          'Enter valid quantities and amounts.',
          'சரியான அளவு மற்றும் தொகையை உள்ளிடவும்.',
        ),
      );
    }
    _busy = true;
    try {
      final now = DateTime.now();
      final personId = txt(person, 'id');
      final amount = kind == 'payment'
          ? payment
          : double.parse((quantity * price).toStringAsFixed(2));
      final entry = <String, dynamic>{
        'pendingUpload': true,
        'cloudId': id,
        'kind': kind,
        'stockScope': 'vendor_v2',
        'syncMode': 'local_v3',
        'personId': personId,
        'personName': txt(person, 'name'),
        'personKind': txt(person, 'kind'),
        'quantity': kind == 'payment' ? 0.0 : quantity,
        'price': kind == 'payment' ? 0.0 : price,
        'amount': amount,
        'paid': paid,
        'session': session,
        'notes': notes,
        'date': todayDate(),
        'time': currentTime(),
        'createdAt': now.toIso8601String(),
        'createdByUid': firebaseReady
            ? FirebaseAuth.instance.currentUser?.uid ?? ''
            : '',
        'addedBy': currentUserName(),
        'updatedAtMillis': now.millisecondsSinceEpoch,
      };
      final box = Hive.box('vendor_entries');
      // Stable IDs make a retry after an interrupted save a no-op.
      if (box.containsKey(id)) return;
      final rows = vendorRows('vendor_entries');
      if (kind == 'sale' && quantity > vendorMilkBalance(rows) + 0.000001) {
        throw StateError(
          bi(
            'Not enough milk. Add the milk collected from a provider first.',
            'பால் இருப்பு போதவில்லை. முதலில் வழங்குநரிடமிருந்து பெற்ற பாலைப் பதிவு செய்யவும்.',
          ),
        );
      }
      if (kind == 'payment' &&
          amount > vendorPersonDue(personId, rows) + 0.001) {
        throw StateError(
          bi(
            'Payment exceeds the outstanding balance.',
            'செலுத்தும் தொகை நிலுவையை விட அதிகமாக உள்ளது.',
          ),
        );
      }
      entry['pendingUpload'] = true;
      await box.put(id, entry);
      await box.flush();
      AutoSyncService.markDirty(reason: 'vendor entry');
    } finally {
      _busy = false;
    }
  }
}

class VendorScreen extends StatefulWidget {
  final int initialSection;
  final bool showTabs;
  const VendorScreen({
    super.key,
    this.initialSection = 0,
    this.showTabs = true,
  });
  @override
  State<VendorScreen> createState() => _VendorScreenState();
}

class _VendorScreenState extends State<VendorScreen> {
  late int _section = widget.initialSection;
  String _search = '';
  @override
  void initState() {
    super.initState();
    if (CloudSyncService.ready) {
      if (canManageRanch) {
        unawaited(
          SeparateVendorStock.ensureInitialized().catchError((Object error) {
            if (mounted) snack(context, accountError(error));
          }),
        );
      }
      unawaited(
        CloudSyncService.downloadBox(
          'vendor_entries',
        ).catchError((Object _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('vendor_people').listenable(),
    builder: (_, _, _) => ValueListenableBuilder(
      valueListenable: Hive.box('vendor_entries').listenable(),
      builder: (_, _, _) {
        final all = vendorRows('vendor_people');
        final rows = vendorRows('vendor_entries');
        final today = rows.where((r) => r['date'] == todayDate()).toList();
        final people =
            all
                .where(
                  (p) =>
                      p['kind'] == (_section < 2 ? 'supplier' : 'customer') &&
                      '${p['name']} ${p['place']}'.toLowerCase().contains(
                        _search.toLowerCase(),
                      ),
                )
                .toList()
              ..sort((a, b) => txt(a, 'name').compareTo(txt(b, 'name')));
        final session = DateTime.now().hour < 12 ? 'Morning' : 'Evening';
        final due = all
            .where(
              (p) =>
                  vendorDeliveryDue(p, DateTime.now(), session) &&
                  !today.any(
                    (r) =>
                        r['kind'] == 'sale' &&
                        r['personId'] == p['id'] &&
                        r['session'] == session,
                  ),
            )
            .toList();
        return Shell(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(21, 16, 21, 32),
            children: [
              if (widget.showTabs)
                LiquidSegmentBar(
                  labels: [
                    bi('Collect milk', 'பால் சேகரிப்பு'),
                    bi('Buy milk', 'பால் கொள்முதல்'),
                    bi('Sell milk', 'பால் விற்பது'),
                  ],
                  index: _section,
                  onChanged: (v) => setState(() {
                    _section = v;
                    _search = '';
                  }),
                ),
              const SizedBox(height: 24),
              Text(
                _section == 0
                    ? bi('Collect milk', 'பால் சேகரிப்பு')
                    : _section == 1
                    ? bi('Buy milk', 'பால் கொள்முதல்')
                    : bi('Sell milk', 'பால் விற்பனை'),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                bi(
                  'Every litre. Every delivery.',
                  'ஒவ்வொரு லிட்டரும். ஒவ்வொரு விநியோகமும்.',
                ),
                style: const TextStyle(color: Ink.muted),
              ),
              const SizedBox(height: 20),
              Glass(
                onTap: () => push(context, const MilkOriginScreen()),
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            bi(
                              'VENDOR MILK STORAGE',
                              'விற்பனையாளர் பால் இருப்பு',
                            ),
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .7,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const MilkVendorIcon(size: 60, detailed: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${vendorMilkBalance(rows).toStringAsFixed(2)} ${bi('L', 'லி')}',
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        _BusinessMetric(
                          label: bi('Collected today', 'இன்று சேகரித்தது'),
                          value:
                              '${_vendorSum(today, 'collection', 'quantity').toStringAsFixed(1)} L',
                        ),
                        _BusinessMetric(
                          label: bi('Bought today', 'இன்று வாங்கியது'),
                          value:
                              '${_vendorSum(today, 'purchase', 'quantity').toStringAsFixed(1)} L',
                        ),
                        _BusinessMetric(
                          label: bi('Sold today', 'இன்று விற்றது'),
                          value:
                              '${_vendorSum(today, 'sale', 'quantity').toStringAsFixed(1)} L',
                        ),
                        _BusinessMetric(
                          label: bi('Sales today', 'இன்றைய விற்பனை'),
                          value:
                              '${currencySymbol()}${_vendorSum(today, 'sale', 'amount').toStringAsFixed(0)}',
                        ),
                        _BusinessMetric(
                          label: bi('Receivable', 'வரவேண்டிய தொகை'),
                          value:
                              '${currencySymbol()}${all.where((p) => p['kind'] == 'customer').fold(0.0, (s, p) => s + vendorPersonDue(txt(p, 'id'), rows)).toStringAsFixed(0)}',
                        ),
                        _BusinessMetric(
                          label: bi('Payable', 'கொடுக்கவேண்டிய தொகை'),
                          value:
                              '${currencySymbol()}${all.where((p) => p['kind'] == 'supplier').fold(0.0, (s, p) => s + vendorPersonDue(txt(p, 'id'), rows)).toStringAsFixed(0)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (due.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  '${ui(session)} · ${bi('Deliveries remaining', 'மீதமுள்ள விநியோகங்கள்')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                _InsetGroup(
                  children: [
                    for (final p in due)
                      ListTile(
                        title: Text(txt(p, 'name')),
                        subtitle: Text(txt(p, 'place')),
                        trailing: const Icon(
                          CupertinoIcons.chevron_right,
                          size: 16,
                        ),
                        onTap: () => push(
                          context,
                          VendorPersonScreen(
                            person: p,
                            intakeKind: _section == 0
                                ? 'collection'
                                : 'purchase',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _section < 2
                          ? bi('Milk suppliers', 'பால் கொடுப்பவர்கள்')
                          : bi('Customers', 'வாடிக்கையாளர்கள்'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (canRecordEntries)
                    IconButton.filledTonal(
                      tooltip: ui('Add person'),
                      onPressed: () => push(
                        context,
                        VendorPersonForm(
                          kind: _section < 2 ? 'supplier' : 'customer',
                        ),
                      ),
                      icon: const Icon(CupertinoIcons.plus),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey(_section),
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
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    bi(
                      'No people yet. Tap + to add a person.',
                      'பட்டியல் காலியாக உள்ளது. நபரைச் சேர்க்க + அழுத்தவும்.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              _InsetGroup(
                children: [
                  for (final p in people)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _blue.withValues(alpha: .09),
                        child: Text(
                          txt(p, 'name').characters.first,
                          style: const TextStyle(color: _blue),
                        ),
                      ),
                      title: Text(txt(p, 'name')),
                      subtitle: Text(
                        '${txt(p, 'place')}\n${currencySymbol()}${vendorPersonDue(txt(p, 'id'), rows).toStringAsFixed(2)} ${bi('outstanding', 'நிலுவை')}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                      ),
                      onTap: () => push(
                        context,
                        VendorPersonScreen(
                          person: p,
                          intakeKind: _section == 0 ? 'collection' : 'purchase',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

double _vendorSum(
  Iterable<Map<String, dynamic>> rows,
  String kind,
  String field,
) => rows
    .where((r) => r['kind'] == kind)
    .fold(0.0, (s, r) => s + numv(r, field));

class VendorStockScreen extends StatelessWidget {
  const VendorStockScreen({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('vendor_entries').listenable(),
    builder: (_, _, _) {
      final rows = vendorRows('vendor_entries')
        ..sort((a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')));
      return Shell(
        child: ListView(
          padding: const EdgeInsets.all(21),
          children: [
            Text(
              bi('Vendor milk stock', 'வியாபாரி பால் இருப்பு'),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => push(context, const MilkOriginScreen()),
              child: Glass(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${vendorMilkBalance(rows).toStringAsFixed(2)} L',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 20),
            for (final r in rows.where(
              (r) => r['kind'] != 'payment' && r['kind'] != 'ranch',
            ))
              ListTile(
                onTap: () => push(context, MilkOriginScreen(entry: r)),
                title: AppText(txt(r, 'personName')),
                subtitle: Text('${txt(r, 'date')} · ${txt(r, 'time')}'),
                trailing: Text(
                  '${['collection', 'purchase'].contains(r['kind']) || (r['kind'] == 'ranch' && numv(r, 'quantity') >= 0) ? '+' : '−'}${numv(r, 'quantity').abs().toStringAsFixed(2)} L',
                  style: TextStyle(
                    color:
                        ['collection', 'purchase'].contains(r['kind']) ||
                            (r['kind'] == 'ranch' && numv(r, 'quantity') >= 0)
                        ? Ink.green
                        : Ink.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (rows.isEmpty)
              Text(
                bi(
                  'No milk movements yet.',
                  'பால் பரிவர்த்தனைகள் இன்னும் இல்லை.',
                ),
              ),
          ],
        ),
      );
    },
  );
}

class VendorReportSummary extends StatelessWidget {
  final String period;
  const VendorReportSummary({super.key, required this.period});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('vendor_entries').listenable(),
    builder: (_, _, _) {
      final rows = vendorRows(
        'vendor_entries',
      ).where((r) => matchPeriod(txt(r, 'date'), period)).toList();
      if (rows.isEmpty && appPurpose != 'Vendor') {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Glass(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bi('Vendor business', 'பால் வியாபாரக் கணக்கு'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 16,
                children: [
                  _BusinessMetric(
                    label: bi('Collected', 'சேகரித்த பால்'),
                    value:
                        '${_vendorSum(rows, 'collection', 'quantity').toStringAsFixed(2)} L',
                  ),
                  _BusinessMetric(
                    label: bi('Purchased', 'வாங்கிய பால்'),
                    value:
                        '${_vendorSum(rows, 'purchase', 'quantity').toStringAsFixed(2)} L',
                  ),
                  _BusinessMetric(
                    label: bi('Delivered', 'விற்ற பால்'),
                    value:
                        '${_vendorSum(rows, 'sale', 'quantity').toStringAsFixed(2)} L',
                  ),
                  _BusinessMetric(
                    label: bi('Purchase cost', 'வாங்கிய செலவு'),
                    value:
                        '${currencySymbol()}${(_vendorSum(rows, 'purchase', 'amount') + _vendorSum(rows, 'collection', 'amount')).toStringAsFixed(2)}',
                  ),
                  _BusinessMetric(
                    label: bi('Sales value', 'விற்பனைத் தொகை'),
                    value:
                        '${currencySymbol()}${_vendorSum(rows, 'sale', 'amount').toStringAsFixed(2)}',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _BusinessMetric extends StatelessWidget {
  final String label, value;
  const _BusinessMetric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      Text(label, style: const TextStyle(color: Ink.muted, fontSize: 12)),
    ],
  );
}

const _dayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const _dayTamil = [
  'ஞாயிறு',
  'திங்கள்',
  'செவ்வாய்',
  'புதன்',
  'வியாழன்',
  'வெள்ளி',
  'சனி',
];

class VendorPersonScreen extends StatefulWidget {
  final Map<String, dynamic> person;
  final String intakeKind;
  final String entryPrefix;
  final String? initialSession;
  const VendorPersonScreen({
    super.key,
    required this.person,
    this.intakeKind = 'purchase',
    this.entryPrefix = '',
    this.initialSession,
  });
  @override
  State<VendorPersonScreen> createState() => _VendorPersonScreenState();
}

class _VendorPersonScreenState extends State<VendorPersonScreen> {
  final _qty = TextEditingController(),
      _price = TextEditingController(),
      _paid = TextEditingController(text: '0');
  bool _busy = false;
  bool _payment = false;
  String _session = DateTime.now().hour < 12 ? 'Morning' : 'Evening';
  String _entryId = '';
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _session = widget.initialSession ?? _session;
    _qty.text =
        '${vendorUsualQuantity(widget.person, _session, vendorRows('vendor_entries'))}';
    _price.text = '${numv(widget.person, 'price', defaultMilkPrice())}';
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _qty.dispose();
    _price.dispose();
    _paid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('vendor_people').listenable(),
    builder: (_, _, _) {
      final p =
          vendorRows(
            'vendor_people',
          ).where((p) => p['id'] == widget.person['id']).firstOrNull ??
          widget.person;
      final supplier = p['kind'] == 'supplier';
      return Scaffold(
        backgroundColor: Ink.canvasTop,
        appBar: AppBar(
          title: Text(txt(p, 'name')),
          actions: [
            if (canRecordEntries)
              IconButton(
                tooltip: ui('Edit person'),
                icon: const Icon(CupertinoIcons.pencil),
                onPressed: () => push(
                  context,
                  VendorPersonForm(kind: txt(p, 'kind'), person: p),
                ),
              ),
          ],
        ),
        body: Shell(
          child: ValueListenableBuilder(
            valueListenable: Hive.box('vendor_entries').listenable(),
            builder: (_, _, _) {
              final all = vendorRows('vendor_entries');
              final rows = all.where((r) => r['personId'] == p['id']).toList()
                ..sort(
                  (a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')),
                );
              final due = vendorPersonDue(txt(p, 'id'), rows);
              return ListView(
                padding: const EdgeInsets.all(21),
                children: [
                  Text(
                    txt(p, 'place'),
                    style: const TextStyle(color: Ink.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    vendorPaymentScheduleLabel(p),
                    style: const TextStyle(color: Ink.muted),
                  ),
                  const SizedBox(height: 20),
                  Glass(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier
                              ? bi('Amount to pay', 'கொடுக்கவேண்டிய தொகை')
                              : bi('Amount to collect', 'வசூலிக்கவேண்டிய தொகை'),
                          style: const TextStyle(color: Ink.muted),
                        ),
                        Text(
                          '${currencySymbol()}${due.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${bi('Milk available', 'பால் இருப்பு')}: ${vendorMilkBalance(all).toStringAsFixed(2)} L',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (canRecordEntries) ...[
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(
                            supplier
                                ? widget.intakeKind == 'collection'
                                      ? bi('Collect milk', 'பால் சேகரிப்பு')
                                      : bi('Buy milk', 'பால் வாங்கு')
                                : bi('Deliver milk', 'பால் விற்பனை'),
                          ),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(bi('Payment', 'பணம்')),
                        ),
                      ],
                      selected: {_payment},
                      onSelectionChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _payment = v.first;
                              _entryId = '';
                            }),
                    ),
                    const SizedBox(height: 20),
                    if (!_payment) ...[
                      TextField(
                        controller: _qty,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: fieldStyle(
                          bi('Milk quantity (litres)', 'பால் அளவு (லிட்டர்)'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: fieldStyle(
                          bi('Price per litre', 'ஒரு லிட்டர் விலை'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _paid,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: fieldStyle(
                        _payment
                            ? supplier
                                  ? bi('Amount paid', 'செலுத்திய தொகை')
                                  : bi('Amount received', 'பெற்ற தொகை')
                            : bi(
                                supplier
                                    ? 'Amount paid now (0 for later)'
                                    : 'Amount received now (0 for later)',
                                supplier
                                    ? 'இப்போது செலுத்தியது (பிறகு என்றால் 0)'
                                    : 'இப்போது பெற்றது (பிறகு என்றால் 0)',
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              _entryId = _entryId.isEmpty
                                  ? '${widget.entryPrefix.isEmpty ? 'v' : widget.entryPrefix}_${DateTime.now().microsecondsSinceEpoch}_${settingText('deviceId', 'device')}'
                                  : _entryId;
                              try {
                                await VendorLedger.record(
                                  id: _entryId,
                                  person: p,
                                  kind: _payment
                                      ? 'payment'
                                      : supplier
                                      ? widget.intakeKind
                                      : 'sale',
                                  quantity: double.tryParse(_qty.text) ?? 0,
                                  price: double.tryParse(_price.text) ?? 0,
                                  paid: _payment
                                      ? 0
                                      : double.tryParse(_paid.text) ?? -1,
                                  payment: _payment
                                      ? double.tryParse(_paid.text) ?? 0
                                      : 0,
                                  session: DateTime.now().hour < 12
                                      ? 'Morning'
                                      : 'Evening',
                                );
                                _entryId = '';
                                _qty.clear();
                                _paid.text = '0';
                                if (context.mounted) {
                                  snack(
                                    context,
                                    bi('Saved', 'சேமிக்கப்பட்டது'),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  snack(
                                    context,
                                    e is FirebaseException
                                        ? bi(
                                            'Could not save. Check your connection and retry.',
                                            'சேமிக்க முடியவில்லை. இணைய இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',
                                          )
                                        : '$e'.replaceFirst('Bad state: ', ''),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _busy
                              ? bi('Saving…', 'சேமிக்கிறது…')
                              : bi('Save entry', 'பதிவைச் சேமி'),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    bi('History', 'பரிவர்த்தனைகள்'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    Text(bi('No transactions yet.', 'பரிவர்த்தனைகள் இல்லை.')),
                  for (final r in rows)
                    _InsetGroup(
                      children: [
                        ListTile(
                          title: Text(
                            '${vendorEntryLabel(txt(r, 'kind'))} · ${currencySymbol()}${numv(r, 'amount').toStringAsFixed(2)}',
                          ),
                          subtitle: Text(
                            '${txt(r, 'date')} · ${txt(r, 'time')}\n${r['kind'] == 'payment' ? '' : '${numv(r, 'quantity')} L × ${currencySymbol()}${numv(r, 'price')}\n'}${txt(r, 'notes')}',
                          ),
                          trailing:
                              withinEntryEditWindow(r, DateTime.now()) &&
                                  canRecordEntries &&
                                  (!firebaseReady ||
                                      r['createdByUid'] ==
                                          FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid)
                              ? IconButton(
                                  tooltip: bi(
                                    'Edit note',
                                    'குறிப்பைத் திருத்து',
                                  ),
                                  icon: const Icon(CupertinoIcons.pencil),
                                  onPressed: () => _editNote(r),
                                )
                              : null,
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
  Future<void> _editNote(Map<String, dynamic> row) async {
    final controller = TextEditingController(text: txt(row, 'notes'));
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bi('Add a note', 'குறிப்பைச் சேர்க்கவும்')),
        content: TextField(controller: controller, maxLength: 500, maxLines: 3),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const AppText('Save'),
          ),
        ],
      ),
    );
    if (note == null || !mounted) return;
    try {
      if (!withinEntryEditWindow(row, DateTime.now())) {
        throw StateError(
          bi(
            'The five-minute edit time has expired.',
            'ஐந்து நிமிட திருத்த நேரம் முடிந்துவிட்டது.',
          ),
        );
      }
      final update = {
        ...row,
        'notes': note,
        'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
      }..remove('_key');
      update['pendingUpload'] = true;
      await Hive.box('vendor_entries').put(row['_key'], update);
      await Hive.box('vendor_entries').flush();
      AutoSyncService.markDirty(reason: 'vendor note');
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Bad state: ', ''));
    }
  }
}
