part of 'main.dart';

// ---------------------------------------------------------------------------
// Milk shop: the Vendor workspace as a counter. Preferences chooses between
// "Milk vendor" (home delivery rides) and "Milk shop" for each account.
// ---------------------------------------------------------------------------

/// 'vendor' (delivery rides) or 'shop' (counter sales), per account.
String get vendorMode =>
    purposeProfile['vendorMode'] == 'shop' ? 'shop' : 'vendor';
bool get milkShopMode => workspaceEnabled('Vendor') && vendorMode == 'shop';

Future<void> saveVendorMode(String mode) async {
  if (mode != 'vendor' && mode != 'shop') {
    throw ArgumentError('Invalid vendor mode');
  }
  await setSetting('purposeProfiles', {
    ...asMap(settingValue('purposeProfiles', {})),
    _profileKey: {...purposeProfile, 'vendorMode': mode},
  });
}

const shopBox = 'shop_entries';
const shopBuiltIns = ['milk', 'curd', 'ghee'];
const shopUnits = ['litre', 'kg', 'count'];
const _shopQuickSlots = 3;

String shopUnitShort(String unit) => switch (unit) {
  'kg' => bi('kg', 'கி'),
  'count' => bi('pcs', 'எண்'),
  _ => bi('L', 'லி'),
};

String shopUnitName(String unit) => switch (unit) {
  'kg' => bi('Kg', 'கிலோ'),
  'count' => bi('Count', 'எண்ணிக்கை'),
  _ => bi('Litre', 'லிட்டர்'),
};

/// "1 sale" / "5 sales" as whole messages, so every language can phrase them.
String shopSalesCount(int count) => count == 1
    ? bi('1 sale', '1 விற்பனை')
    : bi('$count sales', '$count விற்பனை');

String shopMoney(num amount) =>
    '${currencySymbol()}${vendorFieldNumber(amount)}';

String shopItemName(Map<String, dynamic> item) => switch (txt(item, 'id')) {
  'milk' => bi('Milk', 'பால்'),
  'curd' => bi('Curd', 'தயிர்'),
  'ghee' => bi('Ghee', 'நெய்'),
  _ => txt(item, 'name'),
};

IconData shopItemIcon(Map<String, dynamic> item) => switch (txt(item, 'id')) {
  'milk' => CupertinoIcons.drop_fill,
  'curd' => Icons.rice_bowl_rounded,
  'ghee' => Icons.opacity_rounded,
  _ => switch (txt(item, 'unit')) {
    'kg' => Icons.scale_rounded,
    'count' => CupertinoIcons.cube_box_fill,
    _ => CupertinoIcons.drop,
  },
};

/// The shop's items, always with Milk, Curd and Ghee first-class.
List<Map<String, dynamic>> shopItems() {
  final raw = asMap(settingValue('shopCatalog', {}))['items'];
  final saved = <String, Map<String, dynamic>>{
    if (raw is List)
      for (final m in raw.map(asMap))
        if (txt(m, 'id').isNotEmpty && shopUnits.contains(m['unit']))
          txt(m, 'id'): m,
  };
  return [
    for (final id in shopBuiltIns)
      {
        'id': id,
        'name': id[0].toUpperCase() + id.substring(1),
        'unit': 'litre',
        'price': 0.0,
        ...?saved[id],
      },
    for (final m in saved.values)
      if (!shopBuiltIns.contains(txt(m, 'id'))) m,
  ];
}

/// The three items shown as buttons beside Others, in order.
List<String> shopQuickIds([List<Map<String, dynamic>>? items]) {
  final ids = (items ?? shopItems()).map((m) => txt(m, 'id')).toList();
  final raw = asMap(settingValue('shopCatalog', {}))['quick'];
  final quick = <String>[];
  if (raw is List) {
    for (final id in raw.whereType<String>()) {
      if (ids.contains(id) && !quick.contains(id)) quick.add(id);
    }
  }
  for (final id in [...shopBuiltIns, ...ids]) {
    if (quick.length >= _shopQuickSlots) break;
    if (!quick.contains(id)) quick.add(id);
  }
  return quick.take(_shopQuickSlots).toList();
}

Future<void> saveShopCatalog(
  List<Map<String, dynamic>> items,
  List<String> quick,
) => setSetting('shopCatalog', {
  'items': [
    for (final m in items)
      {
        'id': txt(m, 'id'),
        'name': txt(m, 'name'),
        'unit': txt(m, 'unit', 'litre'),
        'price': numv(m, 'price'),
      },
  ],
  'quick': List<String>.of(quick),
});

/// Milk uses the default milk rate until the shop sets its own price.
double shopPrice(Map<String, dynamic> item) {
  final price = numv(item, 'price');
  if (price > 0) return price;
  return txt(item, 'id') == 'milk' ? defaultMilkPrice() : 0;
}

List<Map<String, dynamic>> shopRows() =>
    Hive.isBoxOpen(shopBox) ? vendorRows(shopBox) : <Map<String, dynamic>>[];

/// Stock added minus sold, ignoring cancelled sales.
double shopItemNet(String itemId, [Iterable<Map<String, dynamic>>? rows]) =>
    (rows ?? shopRows())
        .where((r) => r['itemId'] == itemId && r['voided'] != true)
        .fold(
          0.0,
          (total, r) =>
              total +
              (r['kind'] == 'stock'
                  ? numv(r, 'quantity')
                  : r['kind'] == 'sale'
                  ? -numv(r, 'quantity')
                  : 0),
        );

/// Milk in hand for the vendor and the shop: provider milk from the vendor
/// ledger plus shop stock, less what the counter has sold.
double vendorMilkOnHand([Iterable<Map<String, dynamic>>? vendorEntries]) =>
    vendorMilkBalance(vendorEntries ?? vendorRows('vendor_entries')) +
    shopItemNet('milk');

double shopAvailable(String itemId) =>
    itemId == 'milk' ? vendorMilkOnHand() : shopItemNet(itemId);

/// Thrown when a sale asks for more than the shop has.
class ShopStockShortage implements Exception {
  final Map<String, dynamic> item;
  final double available;
  const ShopStockShortage(this.item, this.available);
  @override
  String toString() => bi(
    'Only ${vendorFieldNumber(available)} ${shopUnitShort(txt(item, 'unit'))} of ${shopItemName(item)} in stock.',
    '${shopItemName(item)} இருப்பு ${vendorFieldNumber(available)} ${shopUnitShort(txt(item, 'unit'))} மட்டுமே.',
  );
}

class ShopLedger {
  static bool _busy = false;

  /// Saves a counter sale or a stock addition on this phone first; auto sync
  /// sends it on when ranch sharing is on.
  static Future<void> record({
    required String id,
    required String kind,
    required Map<String, dynamic> item,
    required double quantity,
    double price = 0,
  }) async {
    if (!canRecordEntries) throw StateError(ui('Permission denied'));
    final unit = txt(item, 'unit', 'litre');
    if (id.isEmpty ||
        !['sale', 'stock'].contains(kind) ||
        txt(item, 'id').isEmpty ||
        !shopUnits.contains(unit) ||
        !quantity.isFinite ||
        quantity <= 0 ||
        quantity > 100000 ||
        (unit == 'count' && quantity != quantity.roundToDouble()) ||
        !price.isFinite ||
        (kind == 'sale' ? price <= 0 || price > 1000000 : price != 0)) {
      throw StateError(
        bi(
          'Enter a valid quantity and price.',
          'சரியான அளவு மற்றும் விலையை உள்ளிடவும்.',
        ),
      );
    }
    if (_busy) {
      throw StateError(
        bi(
          'Another entry is saving. Try again.',
          'மற்றொரு பதிவு சேமிக்கப்படுகிறது. மீண்டும் முயற்சிக்கவும்.',
        ),
      );
    }
    _busy = true;
    try {
      final box = Hive.box(shopBox);
      // Stable IDs make a retry after an interrupted save a no-op.
      if (box.containsKey(id)) return;
      final itemId = txt(item, 'id');
      if (kind == 'sale') {
        final available = shopAvailable(itemId);
        if (quantity > available + .000001) {
          throw ShopStockShortage(item, math.max(0, available));
        }
      }
      final now = DateTime.now();
      await box.put(id, {
        'pendingUpload': true,
        'cloudId': id,
        'kind': kind,
        'itemId': itemId,
        'itemName': txt(item, 'name', shopItemName(item)),
        'unit': unit,
        'quantity': quantity,
        'price': price,
        'amount': double.parse((quantity * price).toStringAsFixed(2)),
        'voided': false,
        'notes': '',
        'date': todayDate(),
        'time': currentTime(),
        'createdAt': now.toIso8601String(),
        'createdByUid': firebaseReady
            ? FirebaseAuth.instance.currentUser?.uid ?? ''
            : '',
        'addedBy': currentUserName(),
        'updatedAtMillis': now.millisecondsSinceEpoch,
      });
      await box.flush();
      AutoSyncService.markDirty(reason: 'shop entry');
    } finally {
      _busy = false;
    }
  }

  /// Only the person who made a sale can cancel it, on the same day. The
  /// row stays in the history, marked cancelled, and the stock comes back.
  static bool canVoid(Map<String, dynamic> row) {
    if (row['kind'] != 'sale' || row['voided'] == true) return false;
    if (txt(row, 'date') != todayDate() || !canRecordEntries) return false;
    final creator = txt(row, 'createdByUid');
    final uid = firebaseReady
        ? FirebaseAuth.instance.currentUser?.uid ?? ''
        : '';
    return creator.isEmpty || creator == uid;
  }

  static Future<void> voidSale(Map<String, dynamic> row) async {
    if (!canVoid(row)) throw StateError(ui('Permission denied'));
    final box = Hive.box(shopBox);
    final key = row['_key'] ?? txt(row, 'cloudId');
    final current = asMap(box.get(key));
    if (current.isEmpty) return;
    final now = DateTime.now();
    await box.put(key, {
      ...current,
      'voided': true,
      'updatedAtMillis': math.max(
        now.millisecondsSinceEpoch,
        toInt(current['updatedAtMillis']) + 1,
      ),
      'updatedAtText': now.toIso8601String(),
      'pendingUpload': true,
    });
    await box.flush();
    AutoSyncService.markDirty(reason: 'shop sale cancelled');
  }
}

String _shopEntryId(String kind) =>
    'shop_${kind}_${DateTime.now().microsecondsSinceEpoch}_${settingText('deviceId', 'device')}';

/// The quantity typed on the keypad: whole units plus ½ and ¼.
class ShopQuantity {
  final int whole;
  final bool half, quarter;
  const ShopQuantity({this.whole = 0, this.half = false, this.quarter = false});

  double get value => whole + (half ? .5 : 0) + (quarter ? .25 : 0);
  bool get isEmpty => value <= 0;

  ShopQuantity digit(int d) {
    final next = whole * 10 + d;
    return next > 9999
        ? this
        : ShopQuantity(whole: next, half: half, quarter: quarter);
  }

  ShopQuantity toggleHalf() =>
      ShopQuantity(whole: whole, half: !half, quarter: quarter);
  ShopQuantity toggleQuarter() =>
      ShopQuantity(whole: whole, half: half, quarter: !quarter);

  ShopQuantity backspace() => quarter
      ? ShopQuantity(whole: whole, half: half)
      : half
      ? ShopQuantity(whole: whole)
      : ShopQuantity(whole: whole ~/ 10);

  /// Plain decimals: "1", "1.5", "1.25", "0.75".
  String get label => vendorFieldNumber(value);
}

// ---------------------------------------------------------------------------
// The shop counter
// ---------------------------------------------------------------------------

class MilkShopScreen extends StatefulWidget {
  const MilkShopScreen({super.key});
  @override
  State<MilkShopScreen> createState() => _MilkShopScreenState();
}

class _MilkShopScreenState extends State<MilkShopScreen> {
  String? _selected;
  bool _others = false, _busy = false;
  ShopQuantity _qty = const ShopQuantity();
  int _saleRevision = 0;
  final _buttons = GlobalKey(), _panel = GlobalKey();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open(Widget page) => push(context, page);

  /// On a phone the keypad opens below the fold. Once it has grown, glide
  /// up just enough that the slider clears the tab bar, never past the
  /// item buttons.
  void _reveal() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    Future<void>.delayed(
      reduce ? Duration.zero : Gold.base + const Duration(milliseconds: 34),
      () {
        final row = _buttons.currentContext?.findRenderObject();
        final panel = _panel.currentContext?.findRenderObject();
        if (!mounted ||
            !_scroll.hasClients ||
            row is! RenderBox ||
            panel is! RenderBox ||
            !row.attached ||
            !panel.attached) {
          return;
        }
        final viewport = Scrollable.of(
          _buttons.currentContext!,
        ).context.findRenderObject();
        if (viewport is! RenderBox) return;
        final top = viewport.localToGlobal(Offset.zero).dy;
        final bottom =
            MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).bottom -
            Gold.s13;
        final panelBottom = panel
            .localToGlobal(Offset(0, panel.size.height))
            .dy;
        final rowSlack = row.localToGlobal(Offset.zero).dy - top - Gold.s8;
        // A row scrolled out of view comes back to the top; otherwise
        // scroll only as far as the slider needs.
        final delta = rowSlack < 0
            ? rowSlack
            : math.max(0.0, math.min(panelBottom - bottom, rowSlack));
        if (delta.abs() <= 1) return;
        final position = _scroll.position;
        final target = (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (reduce) {
          position.jumpTo(target);
        } else {
          _scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 420),
            curve: Gold.ease,
          );
        }
      },
    );
  }

  void _choose(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _others = false;
      _qty = const ShopQuantity();
      _selected = _selected == id ? null : id;
    });
    if (_selected != null) _reveal();
  }

  void _toggleOthers() {
    HapticFeedback.selectionClick();
    setState(() {
      _others = !_others || _selected != null;
      _selected = null;
      _qty = const ShopQuantity();
    });
    if (_others) _reveal();
  }

  void _key(ShopQuantity next) {
    HapticFeedback.selectionClick();
    setState(() => _qty = next);
  }

  Future<void> _sell(Map<String, dynamic> item) async {
    if (_busy) return;
    final quantity = _qty.value, price = shopPrice(item);
    setState(() => _busy = true);
    try {
      await ShopLedger.record(
        id: _shopEntryId('sale'),
        kind: 'sale',
        item: item,
        quantity: quantity,
        price: price,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _qty = const ShopQuantity();
        _saleRevision++;
      });
      final sold =
          '${vendorFieldNumber(quantity)} ${shopUnitShort(txt(item, 'unit'))}';
      snack(
        context,
        bi(
          'Sold $sold ${shopItemName(item)} · ${shopMoney(quantity * price)}',
          '${shopItemName(item)} $sold விற்கப்பட்டது · ${shopMoney(quantity * price)}',
        ),
      );
    } on ShopStockShortage catch (shortage) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AppleAlert(
          title: Text(bi('Not enough stock', 'இருப்பு போதவில்லை')),
          content: Text(
            '$shortage ${bi('Add stock to sell more.', 'மேலும் விற்க இருப்பைச் சேர்க்கவும்.')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: AppText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(bi('Add stock', 'இருப்பு சேர்')),
            ),
          ],
        ),
      );
      if (add == true && mounted) await showShopAddStock(context, item);
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      Hive.box('vendor_people').listenable(),
      Hive.box('vendor_entries').listenable(),
      Hive.box(shopBox).listenable(),
      Hive.box(
        'settings',
      ).listenable(keys: const ['shopCatalog', 'defaultMilkPrice', 'currency']),
    ]),
    builder: (context, _) {
      final items = shopItems();
      final byId = {for (final m in items) txt(m, 'id'): m};
      final quick = shopQuickIds(items);
      final others = [
        for (final m in items)
          if (!quick.contains(txt(m, 'id'))) m,
      ];
      if (_selected != null && !byId.containsKey(_selected)) _selected = null;
      final selected = _selected == null ? null : byId[_selected];
      final session = vendorSessionNow();
      final suppliers = vendorRoutePeople(
        vendorRows('vendor_people'),
        vendorRows('vendor_entries'),
        DateTime.now(),
        session,
        suppliers: true,
      );
      final today = shopRows()
          .where(
            (r) =>
                r['kind'] == 'sale' &&
                r['voided'] != true &&
                r['date'] == todayDate(),
          )
          .toList();
      final reduce = MediaQuery.disableAnimationsOf(context);
      final selling = selected != null || _others;
      return Shell(
        edgeToEdge: true,
        child: SizedBox.expand(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              20,
              6,
              20,
              40 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // While selling, only what the sale needs stays on screen.
                AnimatedSize(
                  duration: reduce ? Duration.zero : Gold.base,
                  curve: Gold.ease,
                  alignment: Alignment.topCenter,
                  child: selling
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ShopStockCard(
                              items: [for (final id in quick) byId[id]!],
                              onTap: () => _open(const ShopStockScreen()),
                            ),
                            const SizedBox(height: 16),
                            VendorProvidersStrip(
                              suppliers: suppliers,
                              session: session,
                              enabled: !_busy,
                              onOpen: _open,
                            ),
                            const SizedBox(height: 13),
                            Row(
                              children: [
                                Expanded(
                                  child: Semantics(
                                    button: true,
                                    label: bi(
                                      'Today\'s sales',
                                      'இன்றைய விற்பனை',
                                    ),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () =>
                                          _open(const ShopSalesScreen()),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: AppText(
                                                '${bi('Today', 'இன்று')} · ${shopMoney(today.fold(0.0, (s, r) => s + numv(r, 'amount')))} · ${shopSalesCount(today.length)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Ink.muted,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              CupertinoIcons.chevron_right,
                                              size: 13,
                                              color: Ink.faint,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: canRecordEntries
                                      ? () => _open(const ShopCustomizeScreen())
                                      : null,
                                  icon: const Icon(
                                    CupertinoIcons.slider_horizontal_3,
                                  ),
                                  label: Text(bi('Customize', 'மாற்று')),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                ),
                Row(
                  key: _buttons,
                  children: [
                    for (final (i, id) in quick.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _ShopProductButton(
                          icon: shopItemIcon(byId[id]!),
                          label: shopItemName(byId[id]!),
                          selected: _selected == id,
                          onTap: () => _choose(id),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ShopProductButton(
                        icon: CupertinoIcons.square_grid_2x2_fill,
                        label: bi('Others', 'மற்றவை'),
                        selected:
                            _others ||
                            (selected != null && !quick.contains(_selected)),
                        onTap: _toggleOthers,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                AnimatedSize(
                  key: _panel,
                  duration: reduce ? Duration.zero : Gold.base,
                  curve: Gold.ease,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: reduce ? Duration.zero : Gold.base,
                    switchInCurve: Gold.ease,
                    switchOutCurve: Gold.easeIn,
                    child: selected != null
                        ? _ShopSellPanel(
                            key: ValueKey('sell-$_selected'),
                            item: selected,
                            quantity: _qty,
                            busy: _busy,
                            revision: _saleRevision,
                            fromOthers: !quick.contains(_selected),
                            onKey: _key,
                            onBackToOthers: () => setState(() {
                              _selected = null;
                              _others = true;
                              _qty = const ShopQuantity();
                            }),
                            onSell: () => _sell(selected),
                          )
                        : _others
                        ? _ShopOthersPanel(
                            key: const ValueKey('others'),
                            items: others,
                            onPick: (id) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selected = id;
                                _others = false;
                                _qty = const ShopQuantity();
                              });
                              _reveal();
                            },
                          )
                        : const SizedBox(
                            key: ValueKey('none'),
                            width: double.infinity,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Shop icon on the left, then how much of each main item is in stock.
class _ShopStockCard extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final VoidCallback onTap;
  const _ShopStockCard({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: bi('Shop stock', 'கடை இருப்பு'),
    child: Glass(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Ink.violet, Ink.violetDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: Ink.violetDeep.withValues(alpha: .26),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 13),
          for (final (i, item) in items.indexed) ...[
            if (i > 0)
              Container(
                width: .5,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                color: Ink.separator,
              ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shopItemName(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Ink.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AppText(
                      '${vendorFieldNumber(shopAvailable(txt(item, 'id')))} ${shopUnitShort(txt(item, 'unit'))}',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                        color: Ink.navy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ShopProductButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ShopProductButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        radius: Gold.r21,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : Gold.base,
          curve: Gold.ease,
          height: 76,
          decoration: ShapeDecoration(
            shape: SquircleBorder(
              radius: Gold.r21,
              side: BorderSide(
                color: selected ? Colors.transparent : Ink.separator,
                width: .5,
              ),
            ),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Ink.violet, Ink.violetDeep],
                  )
                : null,
            color: selected ? null : Ink.surface.withValues(alpha: .78),
            shadows: [
              BoxShadow(
                color: Ink.violetDeep.withValues(alpha: selected ? .30 : .06),
                blurRadius: selected ? 18 : 10,
                offset: Offset(0, selected ? 7 : 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 26,
                color: selected ? Colors.white : Ink.violetDeep,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Ink.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Only what a sale needs, large: the item, how much, the price, the
/// keypad (1–9, 0, .500, .250) and the slide to sell.
class _ShopSellPanel extends StatelessWidget {
  final Map<String, dynamic> item;
  final ShopQuantity quantity;
  final bool busy, fromOthers;
  final int revision;
  final ValueChanged<ShopQuantity> onKey;
  final VoidCallback onSell, onBackToOthers;
  const _ShopSellPanel({
    super.key,
    required this.item,
    required this.quantity,
    required this.busy,
    required this.revision,
    required this.fromOthers,
    required this.onKey,
    required this.onSell,
    required this.onBackToOthers,
  });

  @override
  Widget build(BuildContext context) {
    final unit = txt(item, 'unit', 'litre');
    final price = shopPrice(item);
    final amount = quantity.value * price;
    final fractions = unit != 'count';
    final keys = <(String, VoidCallback?, bool)>[
      for (var d = 1; d <= 9; d++)
        ('$d', () => onKey(quantity.digit(d)), false),
      ('0', () => onKey(quantity.digit(0)), false),
      (
        '.500',
        fractions ? () => onKey(quantity.toggleHalf()) : null,
        quantity.half,
      ),
      (
        '.250',
        fractions ? () => onKey(quantity.toggleQuarter()) : null,
        quantity.quarter,
      ),
    ];
    // Once litres are entered, .500 and .250 turn green with "+" to show
    // they add to it.
    final canAdd = fractions && quantity.whole > 0;
    final empty = quantity.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Glass(
          radius: Gold.r27,
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Items from Others name themselves; the main buttons above
              // already show which item is being sold.
              if (fromOthers)
                Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onBackToOthers,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.chevron_left,
                              size: 17,
                              color: Ink.violetDeep,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              shopItemName(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Ink.navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: quantity.label,
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                                color: empty ? Ink.faint : Ink.navy,
                              ),
                            ),
                            TextSpan(
                              text: ' ${shopUnitShort(unit)}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Ink.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (price > 0)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .38,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: AppText(
                          shopMoney(amount),
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            color: empty ? Ink.faint : Ink.violetDeep,
                          ),
                        ),
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: canRecordEntries
                          ? () => showShopItemSheet(context, item: item)
                          : null,
                      icon: const Icon(CupertinoIcons.tag_fill),
                      label: Text(bi('Set price', 'விலை அமை')),
                    ),
                  IconButton(
                    tooltip: bi('Delete', 'நீக்கு'),
                    onPressed: empty ? null : () => onKey(quantity.backspace()),
                    icon: Icon(
                      CupertinoIcons.delete_left,
                      size: 26,
                      color: empty ? Ink.faint : Ink.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final width = (constraints.maxWidth - gap * 2) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (label, onTap, active) in keys)
                  SizedBox(
                    width: width,
                    child: _ShopKey(
                      label: label,
                      added: active,
                      adds: canAdd && label.startsWith('.'),
                      onTap: busy ? null : onTap,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        SlideToSell(
          key: ValueKey('slide-$revision'),
          label: price > 0
              ? '${bi('Slide to sell', 'விற்க இழுக்கவும்')} · ${shopMoney(amount)}'
              : bi('Set a price to sell', 'விற்க விலையை அமைக்கவும்'),
          enabled: !busy && !empty && price > 0 && canRecordEntries,
          onSlide: onSell,
        ),
      ],
    );
  }
}

/// A keypad key. With litres entered, .500 and .250 show green with "+"
/// (they add to the amount); once added they stay filled green, and a
/// second press takes them off.
class _ShopKey extends StatelessWidget {
  final String label;
  final bool adds, added;
  final VoidCallback? onTap;
  const _ShopKey({
    required this.label,
    required this.onTap,
    this.adds = false,
    this.added = false,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final enabled = onTap != null;
    final green = adds || added;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: added,
      label: switch (label) {
        '.500' => bi('Add half', 'அரை சேர்'),
        '.250' => bi('Add quarter', 'கால் சேர்'),
        _ => label,
      },
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        radius: Gold.r21,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : Gold.base,
          curve: Gold.ease,
          height: 54,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: SquircleBorder(
              radius: Gold.r21,
              side: BorderSide(
                color: green ? Ink.green : Ink.separator,
                width: green ? 1.5 : .5,
              ),
            ),
            color: !enabled
                ? Ink.fill
                : added
                ? Ink.green
                : adds
                ? Ink.green.withValues(alpha: .12)
                : Ink.surface.withValues(alpha: .82),
            shadows: [
              if (enabled)
                BoxShadow(
                  color: (green ? Ink.green : Ink.violetDeep).withValues(
                    alpha: green ? .20 : .06,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Text(
            green ? '+$label' : label,
            style: TextStyle(
              fontSize: 26,
              fontWeight: green ? FontWeight.w700 : FontWeight.w600,
              color: !enabled
                  ? Ink.faint
                  : added
                  ? Colors.white
                  : adds
                  ? Ink.greenText
                  : Ink.navy,
            ),
          ),
        ),
      ),
    );
  }
}

/// A capsule with a knob: slide right to finish. VoiceOver users get a
/// plain button.
class SlideToSell extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback onSlide;
  const SlideToSell({
    super.key,
    required this.label,
    required this.enabled,
    required this.onSlide,
  });
  @override
  State<SlideToSell> createState() => _SlideToSellState();
}

class _SlideToSellState extends State<SlideToSell> {
  static const _height = 58.0, _inset = 4.0;
  double _x = 0;
  bool _dragging = false, _done = false;

  void _finish(double max) {
    HapticFeedback.mediumImpact();
    setState(() {
      _x = max;
      _done = true;
    });
    widget.onSlide();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.enabled && !_done;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: enabled ? () => _finish(0) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const knob = _height - _inset * 2;
          final max = math.max(0.0, constraints.maxWidth - knob - _inset * 2);
          final progress = max == 0 ? 0.0 : (_x / max).clamp(0.0, 1.0);
          return Container(
            height: _height,
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: enabled
                  ? Ink.violetDeep.withValues(alpha: .10 + .14 * progress)
                  : Ink.fill,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(left: knob, right: 13),
                    child: Center(
                      child: Opacity(
                        opacity: (1 - progress * 1.6).clamp(0.0, 1.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AppText(
                            widget.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: enabled ? Ink.violetDeep : Ink.faint,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: _dragging || reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 340),
                  curve: Curves.easeOutBack,
                  left: _inset + _x,
                  top: _inset,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: enabled
                        ? (_) => setState(() => _dragging = true)
                        : null,
                    onHorizontalDragUpdate: enabled
                        ? (d) => setState(
                            () => _x = (_x + d.delta.dx).clamp(0.0, max),
                          )
                        : null,
                    onHorizontalDragEnd: enabled
                        ? (d) {
                            final fling =
                                d.velocity.pixelsPerSecond.dx > 800 &&
                                _x > max * .4;
                            if (_x >= max * .82 || fling) {
                              setState(() => _dragging = false);
                              _finish(max);
                            } else {
                              setState(() {
                                _dragging = false;
                                _x = 0;
                              });
                            }
                          }
                        : null,
                    onHorizontalDragCancel: () => setState(() {
                      _dragging = false;
                      _x = 0;
                    }),
                    child: Container(
                      width: knob,
                      height: knob,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: enabled
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Ink.violet, Ink.violetDeep],
                              )
                            : null,
                        color: enabled ? null : Ink.surface,
                        boxShadow: [
                          BoxShadow(
                            color: Ink.violetDeep.withValues(
                              alpha: enabled ? .32 : .08,
                            ),
                            blurRadius: 13,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(
                        _done
                            ? CupertinoIcons.check_mark
                            : CupertinoIcons.chevron_right_2,
                        color: enabled || _done ? Colors.white : Ink.faint,
                        size: 23,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Every other item in the shop, and a tile to add a new one.
class _ShopOthersPanel extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final ValueChanged<String> onPick;
  const _ShopOthersPanel({
    super.key,
    required this.items,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      final width = (constraints.maxWidth - gap * 2) / 3;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                SizedBox(
                  width: width,
                  child: _ShopItemTile(
                    item: item,
                    onTap: () => onPick(txt(item, 'id')),
                  ),
                ),
              SizedBox(
                width: width,
                child: _ShopItemTile(
                  onTap: canRecordEntries
                      ? () => showShopItemSheet(context)
                      : null,
                ),
              ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 13, 4, 0),
              child: Text(
                bi(
                  'Add the other things your shop sells, like butter, paneer or biscuits.',
                  'வெண்ணெய், பனீர், பிஸ்கட் போன்ற கடையில் விற்கும் மற்ற பொருட்களைச் சேர்க்கவும்.',
                ),
                style: TextStyle(color: Ink.muted, fontSize: 13, height: 1.4),
              ),
            ),
        ],
      );
    },
  );
}

class _ShopItemTile extends StatelessWidget {
  final Map<String, dynamic>? item;
  final VoidCallback? onTap;
  const _ShopItemTile({this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = item;
    final price = m == null ? 0.0 : shopPrice(m);
    return Semantics(
      button: true,
      label: m == null ? bi('Add item', 'பொருள் சேர்') : shopItemName(m),
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        radius: Gold.r21,
        child: Container(
          height: 102,
          padding: const EdgeInsets.all(10),
          decoration: ShapeDecoration(
            shape: SquircleBorder(
              radius: Gold.r21,
              side: BorderSide(
                color: m == null
                    ? Ink.violetDeep.withValues(alpha: .35)
                    : Ink.separator,
                width: m == null ? 1 : .5,
              ),
            ),
            color: m == null
                ? Ink.violetDeep.withValues(alpha: .06)
                : Ink.surface.withValues(alpha: .78),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                m == null ? CupertinoIcons.add_circled_solid : shopItemIcon(m),
                color: Ink.violetDeep,
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                m == null ? bi('Add item', 'பொருள் சேர்') : shopItemName(m),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Ink.navy,
                ),
              ),
              if (m != null) ...[
                const SizedBox(height: 2),
                AppText(
                  price > 0
                      ? '${shopMoney(price)} / ${shopUnitShort(txt(m, 'unit'))}'
                      : bi('No price', 'விலை இல்லை'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Ink.muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add or edit an item
// ---------------------------------------------------------------------------

Future<void> showShopItemSheet(
  BuildContext context, {
  Map<String, dynamic>? item,
}) async {
  if (!canRecordEntries) {
    snack(context, ui('Permission denied'));
    return;
  }
  await showAppleSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Ink.canvasTop,
    builder: (_) => _ShopItemSheet(item: item),
  );
}

class _ShopItemSheet extends StatefulWidget {
  final Map<String, dynamic>? item;
  const _ShopItemSheet({this.item});
  @override
  State<_ShopItemSheet> createState() => _ShopItemSheetState();
}

class _ShopItemSheetState extends State<_ShopItemSheet> {
  late final Map<String, dynamic>? _item = widget.item;
  late final bool _builtIn = shopBuiltIns.contains(txt(_item ?? {}, 'id'));
  late final _name = TextEditingController(
    text: _item == null || _builtIn ? '' : txt(_item, 'name'),
  );
  late final _price = TextEditingController(
    text: _item == null || numv(_item, 'price') <= 0
        ? ''
        : vendorFieldNumber(numv(_item, 'price')),
  );
  late String? _unit = _item == null ? null : txt(_item, 'unit', 'litre');

  /// A unit is fixed once the item has stock or sales, so totals never mix
  /// litres with kilograms.
  late final bool _unitLocked =
      _item != null && shopRows().any((r) => r['itemId'] == txt(_item, 'id'));

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _builtIn ? txt(_item ?? {}, 'name') : _name.text.trim();
    final price = toDouble(_price.text);
    if (name.isEmpty || name.length > 60) {
      snack(context, ui('Enter a name'));
      return;
    }
    if (_unit == null) {
      snack(
        context,
        bi('Choose how it is measured', 'அளவிடும் முறையைத் தேர்வு செய்யவும்'),
      );
      return;
    }
    if (price <= 0 || price > 1000000) {
      snack(context, bi('Enter a valid price', 'சரியான விலையை உள்ளிடவும்'));
      return;
    }
    final items = shopItems();
    final quick = shopQuickIds(items);
    final duplicate = items.any(
      (m) =>
          txt(m, 'id') != txt(_item ?? {}, 'id') &&
          shopItemName(m).toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      snack(
        context,
        bi('An item with this name exists', 'இந்தப் பெயரில் பொருள் உள்ளது'),
      );
      return;
    }
    final id = _item == null
        ? 'item_${DateTime.now().microsecondsSinceEpoch}'
        : txt(_item, 'id');
    final next = {'id': id, 'name': name, 'unit': _unit!, 'price': price};
    final index = items.indexWhere((m) => txt(m, 'id') == id);
    if (index >= 0) {
      items[index] = next;
    } else {
      items.add(next);
    }
    try {
      await saveShopCatalog(items, quick);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.pop(context);
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    }
  }

  Future<void> _delete() async {
    final item = _item;
    if (item == null || _builtIn) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(
          bi('Remove ${shopItemName(item)}?', '${shopItemName(item)} நீக்கவா?'),
        ),
        content: Text(
          bi(
            'It leaves the shop list. Past sales stay in your reports.',
            'கடைப் பட்டியலிலிருந்து நீங்கும். பழைய விற்பனைகள் அறிக்கையில் இருக்கும்.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: AppText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Ink.red),
            child: Text(bi('Remove', 'நீக்கு')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final items = shopItems()
      ..removeWhere((m) => txt(m, 'id') == txt(item, 'id'));
    final quick = shopQuickIds()..remove(txt(item, 'id'));
    try {
      await saveShopCatalog(items, shopQuickIdsAfter(items, quick));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    }
  }

  Widget _unitChoice(String unit) {
    final selected = _unit == unit;
    final locked = _unitLocked && !selected;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        enabled: !locked,
        label: shopUnitName(unit),
        excludeSemantics: true,
        child: Pressable(
          onTap: locked || _unitLocked
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => _unit = unit);
                },
          radius: Gold.r21,
          child: AnimatedContainer(
            duration: reduce ? Duration.zero : Gold.base,
            height: 76,
            decoration: ShapeDecoration(
              shape: SquircleBorder(
                radius: Gold.r21,
                side: BorderSide(
                  color: selected ? Colors.transparent : Ink.separator,
                  width: .5,
                ),
              ),
              color: selected
                  ? Ink.tint
                  : Ink.sheetCell.withValues(alpha: locked ? .4 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  switch (unit) {
                    'kg' => Icons.scale_rounded,
                    'count' => CupertinoIcons.number,
                    _ => CupertinoIcons.drop_fill,
                  },
                  color: selected
                      ? Colors.white
                      : locked
                      ? Ink.faint
                      : Ink.violetDeep,
                ),
                const SizedBox(height: 5),
                Text(
                  shopUnitName(unit),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : locked
                        ? Ink.faint
                        : Ink.navy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final reduce = MediaQuery.disableAnimationsOf(context);
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
              Text(
                item == null
                    ? bi('New item', 'புதிய பொருள்')
                    : shopItemName(item),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Ink.navy,
                ),
              ),
              const SizedBox(height: 21),
              if (!_builtIn) ...[
                TextField(
                  controller: _name,
                  autofocus: item == null,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: fieldStyle(
                    bi('Name', 'பெயர்'),
                    icon: CupertinoIcons.tag,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                bi('Measured in', 'அளவிடும் முறை'),
                style: TextStyle(
                  color: Ink.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _unitChoice('litre'),
                  const SizedBox(width: 8),
                  _unitChoice('kg'),
                  const SizedBox(width: 8),
                  _unitChoice('count'),
                ],
              ),
              if (_unitLocked)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    bi(
                      'The measure stays fixed once an item has stock or sales.',
                      'இருப்பு அல்லது விற்பனை உள்ள பொருளின் அளவு முறை மாறாது.',
                    ),
                    style: TextStyle(color: Ink.muted, fontSize: 13),
                  ),
                ),
              AnimatedSize(
                duration: reduce ? Duration.zero : Gold.base,
                curve: Gold.ease,
                child: _unit == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: TextField(
                          controller: _price,
                          autofocus: item == null,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d{0,7}(\.\d{0,2})?'),
                            ),
                          ],
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: fieldStyle(
                            '${switch (_unit) {
                              'kg' => bi('Price per kg', 'ஒரு கிலோ விலை'),
                              'count' => bi('Price for one', 'ஒன்றின் விலை'),
                              _ => bi('Price per litre', 'ஒரு லிட்டர் விலை'),
                            }} (${currencySymbol()})',
                            icon: CupertinoIcons.tag_fill,
                          ),
                          onSubmitted: (_) => _save(),
                        ),
                      ),
              ),
              if (txt(item ?? {}, 'id') == 'milk')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    bi(
                      'Leave the default milk rate (${shopMoney(defaultMilkPrice())}) or set a shop price.',
                      'இயல்பு பால் விலை (${shopMoney(defaultMilkPrice())}) அல்லது கடை விலையை அமைக்கவும்.',
                    ),
                    style: TextStyle(color: Ink.muted, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 21),
              LiquidButton(
                label: bi('Save', 'சேமி'),
                icon: CupertinoIcons.check_mark,
                onPressed: _save,
              ),
              if (item != null && !_builtIn) ...[
                const SizedBox(height: 8),
                GhostButton(
                  label: bi('Remove from shop', 'கடையிலிருந்து நீக்கு'),
                  icon: CupertinoIcons.trash,
                  color: Ink.red,
                  onPressed: _delete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps three main buttons after an item leaves: an unused item fills the
/// empty place.
List<String> shopQuickIdsAfter(
  List<Map<String, dynamic>> items,
  List<String> quick,
) {
  final ids = items.map((m) => txt(m, 'id')).toList();
  final next = [
    for (final id in quick)
      if (ids.contains(id)) id,
  ];
  for (final id in ids) {
    if (next.length >= _shopQuickSlots) break;
    if (!next.contains(id)) next.add(id);
  }
  return next;
}

// ---------------------------------------------------------------------------
// Stock
// ---------------------------------------------------------------------------

Future<void> showShopAddStock(
  BuildContext context,
  Map<String, dynamic> item,
) async {
  if (!canRecordEntries) {
    snack(context, ui('Permission denied'));
    return;
  }
  await showAppleSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Ink.canvasTop,
    builder: (_) => _ShopAddStockSheet(item: item),
  );
}

class _ShopAddStockSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  const _ShopAddStockSheet({required this.item});
  @override
  State<_ShopAddStockSheet> createState() => _ShopAddStockSheetState();
}

class _ShopAddStockSheetState extends State<_ShopAddStockSheet> {
  final _qty = TextEditingController();
  final String _id = _shopEntryId('stock');
  bool _busy = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ShopLedger.record(
        id: _id,
        kind: 'stock',
        item: widget.item,
        quantity: toDouble(_qty.text),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final unit = txt(item, 'unit', 'litre');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
          children: [
            Row(
              children: [
                Icon(shopItemIcon(item), color: Ink.violetDeep, size: 27),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${bi('Add stock', 'இருப்பு சேர்')} · ${shopItemName(item)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Ink.navy,
                        ),
                      ),
                      AppText(
                        '${bi('In stock', 'இருப்பு')} ${vendorFieldNumber(shopAvailable(txt(item, 'id')))} ${shopUnitShort(unit)}',
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
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(
                decimal: unit != 'count',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  unit == 'count'
                      ? RegExp(r'^\d{0,5}')
                      : RegExp(r'^\d{0,5}(\.\d{0,2})?'),
                ),
              ],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: fieldStyle(
                '${bi('Quantity', 'அளவு')} (${shopUnitShort(unit)})',
                icon: CupertinoIcons.plus_circle_fill,
              ),
              onSubmitted: (_) => _save(),
            ),
            if (txt(item, 'id') == 'milk')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  bi(
                    'Milk from your providers is added by itself. Use this for milk from anywhere else.',
                    'வழங்குநர்களிடமிருந்து வரும் பால் தானாகச் சேரும். மற்ற இடங்களிலிருந்து வரும் பாலுக்கு இதைப் பயன்படுத்தவும்.',
                  ),
                  style: TextStyle(color: Ink.muted, fontSize: 13),
                ),
              ),
            const SizedBox(height: 21),
            LiquidButton(
              label: bi('Add', 'சேர்'),
              icon: CupertinoIcons.plus,
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class ShopStockScreen extends StatelessWidget {
  const ShopStockScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(bi('Shop stock', 'கடை இருப்பு'))),
    body: Shell(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          Hive.box(shopBox).listenable(),
          Hive.box('vendor_entries').listenable(),
          Hive.box('settings').listenable(keys: const ['shopCatalog']),
        ]),
        builder: (context, _) {
          final items = shopItems();
          final added =
              shopRows()
                  .where((r) => r['kind'] == 'stock' && r['voided'] != true)
                  .toList()
                ..sort(
                  (a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')),
                );
          return ListView(
            padding: const EdgeInsets.fromLTRB(21, 12, 21, 40),
            children: [
              Glass(
                radius: 24,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final (i, item) in items.indexed) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: .5,
                          indent: 60,
                          color: Ink.separator,
                        ),
                      ListTile(
                        leading: Icon(
                          shopItemIcon(item),
                          color: Ink.violetDeep,
                        ),
                        title: Text(
                          shopItemName(item),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: txt(item, 'id') == 'milk'
                            ? Text(
                                bi(
                                  'Includes milk from providers',
                                  'வழங்குநர் பாலும் சேர்த்து',
                                ),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppText(
                              '${vendorFieldNumber(shopAvailable(txt(item, 'id')))} ${shopUnitShort(txt(item, 'unit'))}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Ink.navy,
                              ),
                            ),
                            IconButton(
                              tooltip: bi('Add stock', 'இருப்பு சேர்'),
                              onPressed: canRecordEntries
                                  ? () => showShopAddStock(context, item)
                                  : null,
                              icon: Icon(
                                CupertinoIcons.plus_circle_fill,
                                color: Ink.violetDeep,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (added.isNotEmpty) ...[
                const SizedBox(height: 27),
                Text(
                  bi('Stock added', 'சேர்த்த இருப்பு'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Glass(
                  radius: 21,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final (i, r) in added.take(30).indexed) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: .5,
                            indent: 16,
                            color: Ink.separator,
                          ),
                        ListTile(
                          dense: true,
                          title: Text(_shopRowName(r)),
                          subtitle: AppText(
                            '${ui(chatDateLabel(txt(r, 'date')))} · ${txt(r, 'time')}',
                          ),
                          trailing: AppText(
                            '+${vendorFieldNumber(numv(r, 'quantity'))} ${shopUnitShort(txt(r, 'unit'))}',
                            style: TextStyle(
                              color: Ink.greenText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

String _shopRowName(Map<String, dynamic> r) {
  final id = txt(r, 'itemId');
  return shopBuiltIns.contains(id)
      ? shopItemName({'id': id})
      : txt(r, 'itemName', id);
}

// ---------------------------------------------------------------------------
// Today's sales
// ---------------------------------------------------------------------------

class ShopSalesScreen extends StatelessWidget {
  const ShopSalesScreen({super.key});

  Future<void> _cancel(BuildContext context, Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(bi('Cancel this sale?', 'இந்த விற்பனையை ரத்து செய்யவா?')),
        content: Text(
          bi(
            'It stays in the list marked cancelled, and the stock comes back.',
            'பட்டியலில் "ரத்து" எனக் குறிக்கப்பட்டு இருக்கும்; இருப்பு திரும்பும்.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(bi('Keep', 'வைத்திரு')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Ink.red),
            child: Text(bi('Cancel sale', 'ரத்து செய்')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ShopLedger.voidSale(row);
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (context.mounted) {
        snack(context, '$e'.replaceFirst('Bad state: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(bi('Today\'s sales', 'இன்றைய விற்பனை'))),
    body: Shell(
      child: ValueListenableBuilder(
        valueListenable: Hive.box(shopBox).listenable(),
        builder: (context, _, _) {
          final rows =
              shopRows()
                  .where((r) => r['kind'] == 'sale' && r['date'] == todayDate())
                  .toList()
                ..sort(
                  (a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')),
                );
          final live = rows.where((r) => r['voided'] != true);
          final total = live.fold(0.0, (s, r) => s + numv(r, 'amount'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(21, 12, 21, 40),
            children: [
              Glass(
                radius: 24,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bi('Total', 'மொத்தம்'),
                            style: TextStyle(
                              color: Ink.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          AppText(
                            shopMoney(total),
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.6,
                              color: Ink.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppText(
                      shopSalesCount(live.length),
                      style: TextStyle(
                        color: Ink.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 34),
                  child: Column(
                    children: [
                      Icon(
                        Icons.storefront_rounded,
                        size: 55,
                        color: Ink.faint,
                      ),
                      const SizedBox(height: 13),
                      Text(
                        bi(
                          'No sales yet today.',
                          'இன்று இன்னும் விற்பனை இல்லை.',
                        ),
                        style: TextStyle(color: Ink.muted),
                      ),
                    ],
                  ),
                )
              else
                Glass(
                  radius: 21,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final (i, r) in rows.indexed) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: .5,
                            indent: 16,
                            color: Ink.separator,
                          ),
                        _ShopSaleRow(
                          row: r,
                          onCancel: ShopLedger.canVoid(r)
                              ? () => _cancel(context, r)
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _ShopSaleRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback? onCancel;
  const _ShopSaleRow({required this.row, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final voided = row['voided'] == true;
    final strike = voided ? TextDecoration.lineThrough : null;
    return ListTile(
      title: Text(
        '${_shopRowName(row)} · ${vendorFieldNumber(numv(row, 'quantity'))} ${shopUnitShort(txt(row, 'unit'))}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: strike,
          color: voided ? Ink.muted : Ink.navy,
        ),
      ),
      subtitle: AppText(
        voided
            ? '${txt(row, 'time')} · ${bi('Cancelled', 'ரத்து')}'
            : '${txt(row, 'time')} · ${shopMoney(numv(row, 'price'))} / ${shopUnitShort(txt(row, 'unit'))}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText(
            shopMoney(numv(row, 'amount')),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              decoration: strike,
              color: voided ? Ink.muted : Ink.navy,
            ),
          ),
          if (onCancel != null)
            IconButton(
              tooltip: bi('Cancel sale', 'ரத்து செய்'),
              onPressed: onCancel,
              icon: Icon(CupertinoIcons.arrow_uturn_left, color: Ink.red),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Customize
// ---------------------------------------------------------------------------

class ShopCustomizeScreen extends StatefulWidget {
  const ShopCustomizeScreen({super.key});
  @override
  State<ShopCustomizeScreen> createState() => _ShopCustomizeScreenState();
}

class _ShopCustomizeScreenState extends State<ShopCustomizeScreen> {
  /// Changes save the moment they are made, as in iOS Settings.
  Future<void> _saveQuick(List<String> quick) async {
    try {
      await saveShopCatalog(shopItems(), quick);
      HapticFeedback.selectionClick();
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    }
  }

  Future<void> _promote(
    Map<String, dynamic> item,
    List<String> quick,
    Map<String, Map<String, dynamic>> byId,
  ) async {
    final slot = await showAppleSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 0, 21, 8),
              child: Text(
                bi(
                  'Put ${shopItemName(item)} in place of',
                  '${shopItemName(item)} எதற்குப் பதிலாக வைக்கலாம்?',
                ),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (var i = 0; i < quick.length; i++)
              ListTile(
                leading: Icon(shopItemIcon(byId[quick[i]]!), color: _blue),
                title: Text(shopItemName(byId[quick[i]]!)),
                trailing: AppText(
                  '${i + 1}',
                  style: TextStyle(color: Ink.muted),
                ),
                onTap: () => Navigator.pop(sheet, i),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (slot == null) return;
    await _saveQuick([...quick]..[slot] = txt(item, 'id'));
  }

  Widget _row(
    Map<String, dynamic> item, {
    required Widget trailing,
    int? index,
  }) {
    final price = shopPrice(item);
    final row = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        onTap: () => showShopItemSheet(context, item: item),
        child: Row(
          children: [
            Icon(shopItemIcon(item), color: Ink.violetDeep, size: 24),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopItemName(item),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Ink.navy,
                    ),
                  ),
                  AppText(
                    price > 0
                        ? '${shopMoney(price)} / ${shopUnitShort(txt(item, 'unit'))}'
                        : bi('No price yet', 'விலை இன்னும் இல்லை'),
                    style: TextStyle(color: Ink.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
    return index == null
        ? row
        : ReorderableDelayedDragStartListener(
            key: ValueKey(txt(item, 'id')),
            index: index,
            child: row,
          );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(bi('Customize', 'மாற்று'))),
    body: Shell(
      child: ValueListenableBuilder(
        valueListenable: Hive.box(
          'settings',
        ).listenable(keys: const ['shopCatalog', 'defaultMilkPrice']),
        builder: (context, _, _) {
          final items = shopItems();
          final byId = {for (final m in items) txt(m, 'id'): m};
          final quick = shopQuickIds(items);
          final others = [
            for (final m in items)
              if (!quick.contains(txt(m, 'id'))) m,
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(21, 12, 21, 40),
            children: [
              Text(
                bi('Main buttons', 'முதன்மை பொத்தான்கள்'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                bi(
                  'Hold and drag to change their places.',
                  'அழுத்திப் பிடித்து இழுத்து இடத்தை மாற்றவும்.',
                ),
                style: TextStyle(color: Ink.muted),
              ),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: quick.length,
                onReorderItem: (old, next) {
                  final order = [...quick];
                  order.insert(next, order.removeAt(old));
                  _saveQuick(order);
                },
                itemBuilder: (context, i) => _row(
                  byId[quick[i]]!,
                  index: i,
                  trailing: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      CupertinoIcons.line_horizontal_3,
                      color: Ink.muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 27),
              Text(
                bi('Others', 'மற்றவை'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                bi(
                  'Tap the arrow to bring an item to the main buttons.',
                  'ஒரு பொருளை முதன்மை பொத்தானாக்க அம்புக்குறியைத் தொடவும்.',
                ),
                style: TextStyle(color: Ink.muted),
              ),
              for (final item in others)
                _row(
                  item,
                  trailing: IconButton(
                    tooltip: bi('Move to main buttons', 'முதன்மைக்கு நகர்த்து'),
                    onPressed: () => _promote(item, quick, byId),
                    icon: Icon(
                      CupertinoIcons.arrow_up_circle_fill,
                      color: Ink.violetDeep,
                      size: 27,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              GhostButton(
                label: bi('Add item', 'பொருள் சேர்'),
                icon: CupertinoIcons.add,
                onPressed: () => showShopItemSheet(context),
              ),
            ],
          );
        },
      ),
    ),
  );
}
