part of 'main.dart';

// -----------------------------------------------------------------------------
//  Walk-in sale: someone not on the customer list buys ₹10 or ₹20 of milk.
// -----------------------------------------------------------------------------

/// Not a saved customer: they pay on the spot, so nothing is ever owed.
const Map<String, dynamic> vendorWalkIn = {
  'id': '_walkin',
  'name': 'Walk-in customer',
  'kind': 'walkin',
};

const walkInAmounts = [10, 20, 30, 50, 100];

/// The litre price for walk-ins: the one set last, else the last sale's.
double walkInPrice([Iterable<Map<String, dynamic>>? rows]) {
  final saved = settingValue('vendorWalkInPrice', 0);
  if (saved is num && saved > 0) return saved.toDouble();
  final sales =
      (rows ?? vendorRows('vendor_entries'))
          .where((r) => r['kind'] == 'sale' && numv(r, 'price') > 0)
          .toList()
        ..sort((a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')));
  return sales.isEmpty ? 60 : numv(sales.first, 'price');
}

/// Litres for a rupee amount at [price] per litre.
double walkInLitres(double amount, double price) =>
    price <= 0 ? 0 : amount / price;

String walkInMl(double litres) => litres < 1
    ? '${(litres * 1000).round()} ml'
    : '${vendorFieldNumber(litres)} L';

Future<void> showWalkInSale(BuildContext context) async {
  if (!canRecordEntries) {
    snack(context, ui('Permission denied'));
    return;
  }
  await showAppleSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Ink.canvasTop,
    builder: (_) => const _WalkInSheet(),
  );
}

class _WalkInSheet extends StatefulWidget {
  const _WalkInSheet();
  @override
  State<_WalkInSheet> createState() => _WalkInSheetState();
}

class _WalkInSheetState extends State<_WalkInSheet> {
  late double _price = walkInPrice();
  late final _amount = TextEditingController(text: '20');
  late final _litres = TextEditingController(text: '0.5');

  /// 0 by rupees, 1 by litres.
  int _by = 0;
  bool _busy = false;
  String _entryId = '';

  @override
  void dispose() {
    _amount.dispose();
    _litres.dispose();
    super.dispose();
  }

  double get _qty => _by == 0
      ? walkInLitres(toDouble(_amount.text), _price)
      : toDouble(_litres.text);
  double get _money => _by == 0
      ? toDouble(_amount.text)
      : double.parse((toDouble(_litres.text) * _price).toStringAsFixed(2));

  Future<void> _changePrice() async {
    final c = TextEditingController(text: vendorFieldNumber(_price));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(bi('Walk-in price', 'திடீர் வாடிக்கையாளர் விலை')),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '${currencySymbol()} ',
            suffixText: bi('per litre', 'லிட்டருக்கு'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ui('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, toDouble(c.text)),
            child: Text(bi('Save', 'சேமி')),
          ),
        ],
      ),
    );
    c.dispose();
    if (value == null || value <= 0 || !mounted) return;
    await setSetting('vendorWalkInPrice', value);
    setState(() => _price = value);
  }

  Future<void> _save() async {
    if (_busy) return;
    final qty = _qty, amount = _money;
    final inHand = vendorMilkOnHand();
    if (qty <= 0 || amount <= 0) {
      snack(context, bi('Enter an amount', 'தொகையை உள்ளிடவும்'));
      return;
    }
    if (qty > inHand + .000001) {
      snack(
        context,
        bi(
          'Only ${vendorFieldNumber(inHand)} L in hand',
          'கையிருப்பு ${vendorFieldNumber(inHand)} லி மட்டுமே',
        ),
        tone: SnackTone.error,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      _entryId = _entryId.isEmpty
          ? 'walkin_${DateTime.now().microsecondsSinceEpoch}_${settingText('deviceId', 'device')}'
          : _entryId;
      await VendorLedger.record(
        id: _entryId,
        person: vendorWalkIn,
        kind: 'sale',
        quantity: qty,
        price: _by == 0 ? amount / qty : _price,
        paid: amount,
        session: vendorSessionNow(),
      );
      if (!mounted) return;
      UiSound.play(UiSoundKind.success);
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      snack(
        context,
        bi(
          '${money(amount)} · ${walkInMl(qty)} sold',
          '${money(amount)} · ${walkInMl(qty)} விற்றது',
        ),
        tone: SnackTone.success,
      );
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8, bottom: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: on,
      showCheckmark: false,
      selectedColor: Ink.tint,
      labelStyle: TextStyle(
        color: on ? Colors.white : Ink.navy,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      onSelected: (_) {
        selectionFeedback();
        onTap();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final qty = _qty, amount = _money;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
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
                    color: Ink.violetDeep.withValues(alpha: .12),
                  ),
                  child: Icon(
                    CupertinoIcons.person_crop_circle_badge_plus,
                    color: Ink.violetDeep,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bi('Walk-in customer', 'தெரியாத வாடிக்கையாளர்'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Ink.navy,
                        ),
                      ),
                      GestureDetector(
                        onTap: _changePrice,
                        child: Text(
                          '${money(_price)} / L · ${bi('change', 'மாற்று')}',
                          style: TextStyle(
                            color: Ink.violetDeep,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LiquidSegmentBar(
              labels: [
                bi('By rupees', 'ரூபாயில்'),
                bi('By litres', 'லிட்டரில்'),
              ],
              index: _by,
              onChanged: (v) => setState(() => _by = v),
            ),
            const SizedBox(height: 14),
            Wrap(
              children: _by == 0
                  ? [
                      for (final a in walkInAmounts)
                        _chip(
                          money(a),
                          toDouble(_amount.text) == a,
                          () => setState(() => _amount.text = '$a'),
                        ),
                    ]
                  : [
                      for (final l in const [.25, .5, 1.0, 2.0])
                        _chip(
                          walkInMl(l),
                          toDouble(_litres.text) == l,
                          () => setState(
                            () => _litres.text = vendorFieldNumber(l),
                          ),
                        ),
                    ],
            ),
            TextField(
              controller: _by == 0 ? _amount : _litres,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: fieldStyle(
                _by == 0
                    ? bi('Other amount', 'வேறு தொகை')
                    : bi('Other litres', 'வேறு அளவு'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              amount > 0 && qty > 0
                  ? bi(
                      'Gives ${walkInMl(qty)} for ${money(amount)}, paid now',
                      '${money(amount)}-க்கு ${walkInMl(qty)}, இப்போதே பணம்',
                    )
                  : '',
              textAlign: TextAlign.center,
              style: TextStyle(color: Ink.muted, fontSize: 15),
            ),
            const SizedBox(height: 12),
            LiquidButton(
              label: amount > 0
                  ? bi('Sold · ${money(amount)}', 'விற்றது · ${money(amount)}')
                  : bi('Sold', 'விற்றது'),
              icon: CupertinoIcons.checkmark_alt,
              busy: _busy,
              onPressed: _busy || amount <= 0 ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Fridge: milk cleared to the fridge keeps two days. Before then it becomes
//  curd or is sold for money; after that it is counted as spoiled.
// -----------------------------------------------------------------------------

const fridgeKeepHours = 48;

class FridgeLot {
  final String id;
  final DateTime at;
  final double quantity;
  final double curd;
  final double sold;
  final double money;
  const FridgeLot({
    required this.id,
    required this.at,
    required this.quantity,
    this.curd = 0,
    this.sold = 0,
    this.money = 0,
  });

  double get left => math.max(0, quantity - curd - sold);
  DateTime get expires => at.add(const Duration(hours: fridgeKeepHours));
  bool expired([DateTime? now]) =>
      left > .000001 && !(now ?? DateTime.now()).isBefore(expires);
  Duration remaining([DateTime? now]) =>
      expires.difference(now ?? DateTime.now());
}

/// Every fridge lot, newest first, with what became of it.
List<FridgeLot> fridgeLots([Iterable<Map<String, dynamic>>? source]) {
  final rows = source ?? vendorRows('vendor_entries');
  final uses = <String, (double, double, double)>{};
  for (final r in rows.where((r) => r['kind'] == 'fridge_use')) {
    final lot = txt(r, 'lotId');
    final was = uses[lot] ?? (0.0, 0.0, 0.0);
    uses[lot] = r['use'] == 'curd'
        ? (was.$1 + numv(r, 'quantity'), was.$2, was.$3)
        : (was.$1, was.$2 + numv(r, 'quantity'), was.$3 + numv(r, 'amount'));
  }
  final lots = [
    for (final r in rows)
      if (r['kind'] == 'clearance' && r['personKind'] == 'fridge')
        FridgeLot(
          id: txt(r, 'cloudId', txt(r, 'id')),
          at: DateTime.tryParse(txt(r, 'createdAt')) ?? DateTime(2000),
          quantity: numv(r, 'quantity'),
          curd: uses[txt(r, 'cloudId', txt(r, 'id'))]?.$1 ?? 0,
          sold: uses[txt(r, 'cloudId', txt(r, 'id'))]?.$2 ?? 0,
          money: uses[txt(r, 'cloudId', txt(r, 'id'))]?.$3 ?? 0,
        ),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return lots;
}

/// Fridge milk still good to use.
double fridgeMilkGood([DateTime? now]) =>
    fridgeLots().where((l) => !l.expired(now)).fold(0.0, (s, l) => s + l.left);

/// Once per lot, a day before it spoils: a notice to use or sell it.
Future<void> remindFridgeMilk() async {
  if (!Hive.isBoxOpen('vendor_entries') || !Hive.isBoxOpen('notifications')) {
    return;
  }
  final now = DateTime.now();
  for (final lot in fridgeLots()) {
    if (lot.left <= .000001 || lot.expired(now)) continue;
    if (lot.remaining(now) > const Duration(hours: 24)) continue;
    await addRanchNotification(
      title:
          '${vendorFieldNumber(lot.left)} L fridge milk spoils tomorrow. Make curd or sell it.',
      titleTa:
          '${vendorFieldNumber(lot.left)} லி ஃப்ரிட்ஜ் பால் நாளை கெடும். தயிராக்குங்கள் அல்லது விற்கவும்.',
      message: 'Open Vendor → Stock → Fridge',
      messageTa: 'Vendor → இருப்பு → ஃப்ரிட்ஜ் திறக்கவும்',
      type: 'reminder',
      sourceId: 'fridge-expiry-${lot.id}',
      localOnly: true,
      extra: const {'fridge': true},
    );
  }
}

class FridgeScreen extends StatelessWidget {
  const FridgeScreen({super.key});

  String _left(Duration d) {
    if (d.inHours >= 1) {
      return bi('${d.inHours} h left', '${d.inHours} மணி நேரம் உள்ளது');
    }
    return bi(
      '${math.max(1, d.inMinutes)} min left',
      '${math.max(1, d.inMinutes)} நிமிடம் உள்ளது',
    );
  }

  Future<void> _use(BuildContext context, FridgeLot lot, String use) async {
    final qty = TextEditingController(text: vendorFieldNumber(lot.left));
    final price = TextEditingController(text: vendorFieldNumber(walkInPrice()));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(
          use == 'curd'
              ? bi('Make curd', 'தயிராக்கு')
              : bi('Sell for money', 'பணமாக மாற்று'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: bi('Litres', 'லிட்டர்'),
                helperText: bi(
                  'Up to ${vendorFieldNumber(lot.left)} L',
                  '${vendorFieldNumber(lot.left)} லி வரை',
                ),
              ),
            ),
            if (use == 'sold')
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: bi('Price per litre', 'லிட்டர் விலை'),
                  prefixText: '${currencySymbol()} ',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ui('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(bi('Save', 'சேமி')),
          ),
        ],
      ),
    );
    final q = toDouble(qty.text), p = toDouble(price.text);
    qty.dispose();
    price.dispose();
    if (ok != true || !context.mounted) return;
    if (q <= 0 || q > lot.left + .000001 || (use == 'sold' && p <= 0)) {
      snack(
        context,
        bi(
          'Enter valid quantities and amounts.',
          'சரியான அளவு மற்றும் தொகையை உள்ளிடவும்.',
        ),
        tone: SnackTone.error,
      );
      return;
    }
    try {
      await VendorLedger.record(
        id: 'fridge_${DateTime.now().microsecondsSinceEpoch}_${settingText('deviceId', 'device')}',
        person: vendorFridge,
        kind: 'fridge_use',
        quantity: q,
        price: use == 'sold' ? p : 0,
        paid: use == 'sold' ? double.parse((q * p).toStringAsFixed(2)) : 0,
        session: vendorSessionNow(),
        lotId: lot.id,
        use: use,
      );
      if (context.mounted) {
        UiSound.play(UiSoundKind.success);
        snack(
          context,
          use == 'curd'
              ? bi(
                  '${vendorFieldNumber(q)} L made into curd',
                  '${vendorFieldNumber(q)} லி தயிராக்கப்பட்டது',
                )
              : bi(
                  '${vendorFieldNumber(q)} L sold · ${money(q * p)}',
                  '${vendorFieldNumber(q)} லி விற்றது · ${money(q * p)}',
                ),
          tone: SnackTone.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        snack(
          context,
          '$e'.replaceFirst('Bad state: ', ''),
          tone: SnackTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(bi('Fridge', 'ஃப்ரிட்ஜ்')),
    ),
    body: ValueListenableBuilder(
      valueListenable: Hive.box('vendor_entries').listenable(),
      builder: (context, _, _) {
        final now = DateTime.now();
        final lots = fridgeLots();
        final good = lots.where((l) => l.left > .000001 && !l.expired(now));
        final done = lots.where((l) => l.left <= .000001 || l.expired(now));
        return Shell(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Glass(
                radius: 24,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vendorFieldNumber(good.fold(0.0, (s, l) => s + l.left))} L',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      bi(
                        'In the fridge. Milk keeps two days: make curd or sell it before then.',
                        'ஃப்ரிட்ஜில் உள்ளது. பால் இரண்டு நாள் மட்டுமே: அதற்குள் தயிராக்குங்கள் அல்லது விற்கவும்.',
                      ),
                      style: TextStyle(color: Ink.muted),
                    ),
                  ],
                ),
              ),
              if (good.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    bi(
                      'Nothing in the fridge. Use Clearance → Fridge to put milk here.',
                      'ஃப்ரிட்ஜில் எதுவும் இல்லை. கிளியரன்ஸ் → ஃப்ரிட்ஜ் மூலம் சேர்க்கவும்.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Ink.muted),
                  ),
                ),
              for (final lot in good) ...[
                const SizedBox(height: 12),
                Glass(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${vendorFieldNumber(lot.left)} L',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (lot.remaining(now).inHours < 24
                                          ? Ink.red
                                          : Ink.green)
                                      .withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              _left(lot.remaining(now)),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: lot.remaining(now).inHours < 24
                                    ? Ink.redText
                                    : Ink.greenText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${bi('Put in', 'வைத்தது')} ${lot.at.day}/${lot.at.month} ${lot.at.hour.toString().padLeft(2, '0')}:${lot.at.minute.toString().padLeft(2, '0')}'
                        '${lot.curd > 0 ? ' · ${bi('curd', 'தயிர்')} ${vendorFieldNumber(lot.curd)} L' : ''}'
                        '${lot.sold > 0 ? ' · ${bi('sold', 'விற்றது')} ${vendorFieldNumber(lot.sold)} L' : ''}',
                        style: TextStyle(color: Ink.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GhostButton(
                              label: bi('Make curd', 'தயிராக்கு'),
                              icon: CupertinoIcons.drop,
                              onPressed: canRecordEntries
                                  ? () => _use(context, lot, 'curd')
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LiquidButton(
                              label: bi('Sell', 'விற்'),
                              icon: Icons.currency_rupee_rounded,
                              onPressed: canRecordEntries
                                  ? () => _use(context, lot, 'sold')
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (done.isNotEmpty) ...[
                _shopSection(bi('Earlier', 'முன்பு')),
                for (final lot in done.take(20))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      [
                        '${lot.at.day}/${lot.at.month} · ${vendorFieldNumber(lot.quantity)} L',
                        if (lot.curd > 0)
                          '${bi('curd', 'தயிர்')} ${vendorFieldNumber(lot.curd)} L',
                        if (lot.sold > 0)
                          '${bi('sold', 'விற்றது')} ${vendorFieldNumber(lot.sold)} L · ${money(lot.money)}',
                        if (lot.expired(now))
                          '${bi('spoiled', 'கெட்டது')} ${vendorFieldNumber(lot.left)} L',
                      ].join(' · '),
                      style: TextStyle(
                        color: lot.expired(now) ? Ink.redText : Ink.body,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
