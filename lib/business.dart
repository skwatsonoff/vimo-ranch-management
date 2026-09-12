part of 'main.dart';

String bi(String en, String ta) => tamilUi ? ta : en;
const businessTabs = ['Ranch', 'Vendor', 'Sell', 'Social', 'Chat'];
String get _profileKey =>
    firebaseReady ? FirebaseAuth.instance.currentUser?.uid ?? 'local' : 'local';
Map<String, dynamic> get purposeProfile =>
    asMap(asMap(settingValue('purposeProfiles', {}))[_profileKey] ?? {});
bool get purposeChosen =>
    ['Ranch', 'Vendor', 'Market'].contains(purposeProfile['purpose']);
String get appPurpose => txt(purposeProfile, 'purpose', 'Ranch');
List<String> defaultNavigation(String purpose) => switch (purpose) {
  'Vendor' => ['Vendor', 'Ranch', 'Sell', 'Social', 'Chat'],
  'Market' => ['Sell', 'Vendor', 'Ranch', 'Social', 'Chat'],
  _ => [...businessTabs],
};
List<String> navigationOrder() {
  final saved = purposeProfile['order'];
  if (saved is List &&
      saved.length == 5 &&
      saved.toSet().containsAll(businessTabs)) {
    return saved.cast<String>();
  }
  return defaultNavigation(appPurpose);
}

Future<void> savePurpose(String purpose, List<String> order) async {
  if (!['Ranch', 'Vendor', 'Market'].contains(purpose) ||
      order.length != 5 ||
      !order.toSet().containsAll(businessTabs)) {
    throw ArgumentError('Invalid preferences');
  }
  await setSetting('purposeProfiles', {
    ...asMap(settingValue('purposeProfiles', {})),
    _profileKey: {'purpose': purpose, 'order': order},
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
                      ? const MilkVendorIcon(size: 34)
                      : Icon(item.$3, color: _blue),
                  title: AppText(item.$1),
                  subtitle: Text(item.$2),
                  trailing: Icon(
                    _purpose == item.$1
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    color: _blue,
                  ),
                  onTap: () => setState(() {
                    _purpose = item.$1;
                    _order = defaultNavigation(_purpose);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            bi('Your tab order', 'உங்கள் பக்கங்களின் வரிசை'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            bi(
              'Move a page up or down. The first page opens when you launch VIMO.',
              'மேல் அல்லது கீழ் நகர்த்தி வரிசையை மாற்றலாம். முதல் பக்கம் செயலியைத் திறக்கும்போது தெரியும்.',
            ),
            style: const TextStyle(color: Ink.muted),
          ),
          const SizedBox(height: 16),
          _InsetGroup(
            children: [
              for (var i = 0; i < _order.length; i++)
                ListTile(
                  leading: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  title: AppText(_order[i]),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: bi('Move up', 'மேலே நகர்த்து'),
                        onPressed: i == 0
                            ? null
                            : () => setState(() {
                                final item = _order.removeAt(i);
                                _order.insert(i - 1, item);
                              }),
                        icon: const Icon(CupertinoIcons.chevron_up),
                      ),
                      IconButton(
                        tooltip: bi('Move down', 'கீழே நகர்த்து'),
                        onPressed: i == 4
                            ? null
                            : () => setState(() {
                                final item = _order.removeAt(i);
                                _order.insert(i + 1, item);
                              }),
                        icon: const Icon(CupertinoIcons.chevron_down),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await savePurpose(_purpose, _order);
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
    entries.fold(
      0.0,
      (total, row) =>
          total +
          (row['kind'] == 'purchase'
              ? numv(row, 'quantity')
              : row['kind'] == 'sale'
              ? -numv(row, 'quantity')
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
        (person['days'] as List).contains(date.weekday % 7)) &&
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
    if (!['purchase', 'sale', 'payment'].contains(kind) ||
        (kind == 'purchase' && person['kind'] != 'supplier') ||
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
        'pendingUpload': false,
        'cloudId': id,
        'kind': kind,
        'personId': personId,
        'personName': txt(person, 'name'),
        'personKind': txt(person, 'kind'),
        'quantity': quantity,
        'price': price,
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
      if (CloudSyncService.ready) {
        await CloudSyncService.uploadBox('vendor_people');
        final db = FirebaseFirestore.instance;
        final stockRef = CloudSyncService.ranch
            .collection('vendor_stock')
            .doc('milk');
        final accountRef = CloudSyncService.ranch
            .collection('vendor_accounts')
            .doc(personId);
        final entryRef = CloudSyncService.ranch
            .collection('vendor_entries')
            .doc(id);
        await db.runTransaction((tx) async {
          final existing = await tx.get(entryRef);
          if (existing.exists) return;
          final stock = await tx.get(stockRef);
          final account = await tx.get(accountRef);
          final balance = numv(stock.data() ?? {}, 'quantity');
          final due = numv(account.data() ?? {}, 'due');
          if (kind == 'sale' && quantity > balance + 0.000001) {
            throw StateError(
              bi(
                'Not enough vendor milk in stock.',
                'விற்பனையாளரின் பால் இருப்பு போதவில்லை.',
              ),
            );
          }
          if (kind == 'payment' && amount > due + 0.001) {
            throw StateError(
              bi(
                'Payment exceeds the outstanding balance.',
                'செலுத்தும் தொகை நிலுவையை விட அதிகமாக உள்ளது.',
              ),
            );
          }
          tx.set(entryRef, {
            ...entry,
            'serverCreatedAt': FieldValue.serverTimestamp(),
          });
          tx.set(stockRef, {
            'quantity':
                balance +
                (kind == 'purchase'
                    ? quantity
                    : kind == 'sale'
                    ? -quantity
                    : 0),
            'entryId': id,
          });
          tx.set(accountRef, {
            'due': double.parse(
              (due + (kind == 'payment' ? -amount : amount - paid))
                  .toStringAsFixed(2),
            ),
            'entryId': id,
          });
        });
        // Server transaction is authoritative; refreshing also includes other devices.
        try {
          await CloudSyncService.downloadBox('vendor_entries');
        } catch (_) {
          AutoSyncService.beginRemoteWrite();
          try {
            await Hive.box('vendor_entries').put(id, entry);
          } finally {
            AutoSyncService.endRemoteWrite();
          }
        }
      } else {
        if (!vimoPreviewMode) {
          throw StateError(
            bi(
              'Connect to your account to save vendor entries.',
              'விற்பனையாளர் பதிவைச் சேமிக்க உங்கள் கணக்கில் இணையவும்.',
            ),
          );
        }
        final rows = vendorRows('vendor_entries');
        if (kind == 'sale' && quantity > vendorMilkBalance(rows)) {
          throw StateError('Not enough vendor milk in stock.');
        }
        if (kind == 'payment' && amount > vendorPersonDue(personId, rows)) {
          throw StateError('Payment exceeds the outstanding balance.');
        }
        if (!Hive.box('vendor_entries').containsKey(id)) {
          await Hive.box('vendor_entries').put(id, entry);
        }
      }
    } finally {
      _busy = false;
    }
  }
}

class VendorScreen extends StatefulWidget {
  final int initialSection;
  const VendorScreen({super.key, this.initialSection = 0});
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
                      p['kind'] == (_section == 0 ? 'supplier' : 'customer') &&
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
              LiquidSegmentBar(
                labels: [
                  bi('Buy milk', 'பால் வாங்குவது'),
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
                bi('Your milk business', 'உங்கள் பால் வணிகம்'),
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
                        onTap: () =>
                            push(context, VendorPersonScreen(person: p)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _section == 0
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
                          kind: _section == 0 ? 'supplier' : 'customer',
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
                      onTap: () => push(context, VendorPersonScreen(person: p)),
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
            Glass(
              padding: const EdgeInsets.all(24),
              child: Text(
                '${vendorMilkBalance(rows).toStringAsFixed(2)} L',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              bi(
                'Purchases add stock. Deliveries reduce stock.',
                'வாங்கும்போது இருப்பு கூடும். விற்கும்போது இருப்பு குறையும்.',
              ),
              style: const TextStyle(color: Ink.muted),
            ),
            const SizedBox(height: 20),
            for (final r in rows.where((r) => r['kind'] != 'payment'))
              ListTile(
                title: Text(txt(r, 'personName')),
                subtitle: Text('${txt(r, 'date')} · ${txt(r, 'time')}'),
                trailing: Text(
                  '${r['kind'] == 'purchase' ? '+' : '−'}${numv(r, 'quantity').toStringAsFixed(2)} L',
                  style: TextStyle(
                    color: r['kind'] == 'purchase' ? Ink.green : Ink.blue,
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
                        '${currencySymbol()}${_vendorSum(rows, 'purchase', 'amount').toStringAsFixed(2)}',
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

const _paymentCycles = [
  'Daily',
  'Every 2 days',
  'Weekly',
  'Monthly',
  'Flexible',
];
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

class VendorPersonForm extends StatefulWidget {
  final String kind;
  final Map<String, dynamic>? person;
  const VendorPersonForm({super.key, required this.kind, this.person});
  @override
  State<VendorPersonForm> createState() => _VendorPersonFormState();
}

class _VendorPersonFormState extends State<VendorPersonForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.person?['name']);
  late final _place = TextEditingController(text: widget.person?['place']);
  late final Set<int> _days =
      ((widget.person?['days'] as List?) ?? [0, 1, 2, 3, 4, 5, 6])
          .cast<int>()
          .toSet();
  late final Set<String> _sessions =
      ((widget.person?['sessions'] as List?) ?? ['Morning'])
          .cast<String>()
          .toSet();
  late String _cycle = widget.person?['paymentCycle'] ?? 'Daily';
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    _place.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      title: AppText(widget.person == null ? 'Add person' : 'Edit person'),
    ),
    body: Shell(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(21),
          children: [
            Text(
              widget.kind == 'supplier'
                  ? bi('Milk supplier', 'பால் கொடுப்பவர்')
                  : bi('Customer', 'வாடிக்கையாளர்'),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: fieldStyle(bi('Person name', 'நபரின் பெயர்')),
              validator: (v) => v == null || v.trim().isEmpty
                  ? bi('Enter a name', 'பெயரை உள்ளிடவும்')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _place,
              maxLength: 160,
              decoration: fieldStyle(bi('Place / address', 'இடம் / முகவரி')),
              validator: (v) =>
                  widget.kind == 'customer' && (v == null || v.trim().isEmpty)
                  ? bi('Enter a place', 'இடத்தை உள்ளிடவும்')
                  : null,
            ),
            if (widget.kind == 'customer') ...[
              const SizedBox(height: 24),
              Text(
                bi('Delivery days', 'பால் வாங்கும் நாட்கள்'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 7; i++)
                    Tooltip(
                      message: tamilUi ? _dayTamil[i] : _dayNames[i],
                      child: FilterChip(
                        label: Text(
                          tamilUi ? _dayTamil[i] : _dayNames[i].substring(0, 1),
                        ),
                        selected: _days.contains(i),
                        onSelected: (v) => setState(() {
                          v ? _days.add(i) : _days.remove(i);
                        }),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                bi('Delivery time', 'பால் வாங்கும் நேரம்'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  for (final s in ['Morning', 'Evening'])
                    FilterChip(
                      label: AppText(s),
                      selected: _sessions.contains(s),
                      onSelected: (v) => setState(() {
                        v ? _sessions.add(s) : _sessions.remove(s);
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _cycle,
              isExpanded: true,
              decoration: fieldStyle(
                bi('Payment frequency', 'பணம் செலுத்தும் இடைவெளி'),
              ),
              items: [
                for (final c in _paymentCycles)
                  DropdownMenuItem(value: c, child: AppText(c)),
              ],
              onChanged: (v) => setState(() => _cycle = v!),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!_form.currentState!.validate()) return;
                      if (widget.kind == 'customer' &&
                          (_days.isEmpty || _sessions.isEmpty)) {
                        snack(
                          context,
                          bi(
                            'Choose at least one day and delivery time.',
                            'குறைந்தது ஒரு நாள் மற்றும் நேரத்தைத் தேர்வு செய்யவும்.',
                          ),
                        );
                        return;
                      }
                      if (!canRecordEntries) return;
                      setState(() => _busy = true);
                      try {
                        final now = DateTime.now();
                        final id =
                            widget.person?['id'] ??
                            '${settingText('deviceId', 'device')}_${now.microsecondsSinceEpoch}';
                        final data = <String, dynamic>{
                          ...?widget.person,
                          'id': id,
                          'cloudId': widget.person?['cloudId'] ?? id,
                          'kind': widget.kind,
                          'name': _name.text.trim(),
                          'place': _place.text.trim(),
                          'days': _days.toList()..sort(),
                          'sessions': _sessions.toList(),
                          'paymentCycle': _cycle,
                          'createdAt':
                              widget.person?['createdAt'] ??
                              now.toIso8601String(),
                          'updatedAtMillis': now.millisecondsSinceEpoch,
                        };
                        data.remove('_key');
                        await Hive.box(
                          'vendor_people',
                        ).put(widget.person?['_key'] ?? id, data);
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) {
                          snack(context, ui('Unable to save. Try again.'));
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: AppText('Save'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class VendorPersonScreen extends StatefulWidget {
  final Map<String, dynamic> person;
  const VendorPersonScreen({super.key, required this.person});
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
                  if (!supplier)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        '${(p['days'] as List? ?? []).map((d) => tamilUi ? _dayTamil[d as int] : _dayNames[d as int].substring(0, 3)).join(' · ')}\n${(p['sessions'] as List? ?? []).map((s) => ui('$s')).join(' & ')}',
                      ),
                    ),
                  Text(
                    '${bi('Payment', 'பணம் செலுத்துவது')}: ${ui(txt(p, 'paymentCycle', 'Daily'))}',
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
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(
                            supplier
                                ? bi('Buy milk', 'பால் வாங்கு')
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
                      if (!supplier)
                        Wrap(
                          spacing: 12,
                          children: [
                            for (final s in ['Morning', 'Evening'])
                              ChoiceChip(
                                label: AppText(s),
                                selected: _session == s,
                                onSelected: (_) => setState(() => _session = s),
                              ),
                          ],
                        ),
                    ],
                    TextField(
                      controller: _paid,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: fieldStyle(
                        _payment
                            ? bi('Payment amount', 'செலுத்தும் தொகை')
                            : bi(
                                'Paid now (0 for credit)',
                                'இப்போது செலுத்தியது (கடனுக்கு 0)',
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      bi(
                        'Notes can be added for five minutes after saving. Vendor entries need an internet connection to keep shared stock accurate.',
                        'சேமித்த பிறகு ஐந்து நிமிடங்களுக்குள் குறிப்பைச் சேர்க்கலாம். பகிரப்பட்ட பால் இருப்பு சரியாக இருக்க இணைய இணைப்பு தேவை.',
                      ),
                      style: const TextStyle(color: Ink.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              _entryId = _entryId.isEmpty
                                  ? 'v_${DateTime.now().microsecondsSinceEpoch}_${settingText('deviceId', 'device')}'
                                  : _entryId;
                              try {
                                await VendorLedger.record(
                                  id: _entryId,
                                  person: p,
                                  kind: _payment
                                      ? 'payment'
                                      : supplier
                                      ? 'purchase'
                                      : 'sale',
                                  quantity: double.tryParse(_qty.text) ?? 0,
                                  price: double.tryParse(_price.text) ?? 0,
                                  paid: _payment
                                      ? 0
                                      : double.tryParse(_paid.text) ?? -1,
                                  payment: _payment
                                      ? double.tryParse(_paid.text) ?? 0
                                      : 0,
                                  session: _session,
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
                            '${ui(r['kind'] == 'purchase'
                                ? 'Purchased'
                                : r['kind'] == 'sale'
                                ? 'Sold'
                                : 'Payment')} · ${currencySymbol()}${numv(r, 'amount').toStringAsFixed(2)}',
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
      if (CloudSyncService.ready) {
        await CloudSyncService.ranch
            .collection('vendor_entries')
            .doc(txt(row, 'cloudId'))
            .update({
              'notes': note,
              'updatedAtMillis': update['updatedAtMillis'],
            });
      }
      AutoSyncService.beginRemoteWrite();
      try {
        await Hive.box('vendor_entries').put(row['_key'], update);
      } finally {
        AutoSyncService.endRemoteWrite();
      }
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Bad state: ', ''));
    }
  }
}
