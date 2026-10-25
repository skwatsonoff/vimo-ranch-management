part of 'main.dart';

double ranchSourceMilk(String box, Map<String, dynamic> data) {
  if (box == 'milk_records') return numv(data, 'quantity');
  return data['type'] == 'Milk' || data['category'] == 'Milk Sale'
      ? -numv(data, 'quantity')
      : 0;
}

/// Each source record owns one checkpoint. Transactions apply only the delta,
/// so retries, edits, deletions and concurrent devices cannot import it twice.
class RanchMilkBridge {
  static Future<void>? _running;
  static Future<void> sync() =>
      _running ??= _sync().whenComplete(() => _running = null);
  static Future<void> _sync() async {
    if (!CloudSyncService.ready || !canRecordEntries) return;
    final ranch = CloudSyncService.ranch;
    final db = FirebaseFirestore.instance;
    final links = await ranch
        .collection('vendor_ranch_links')
        .get(const GetOptions(source: Source.server))
        .timeout(CloudSyncService.networkTimeout);
    final known = {for (final d in links.docs) d.id: d.data()};
    for (final box in ['milk_records', 'sale_records']) {
      final sources = await ranch
          .collection(box)
          .get(const GetOptions(source: Source.server))
          .timeout(CloudSyncService.networkTimeout);
      final sourceMap = {for (final d in sources.docs) d.id: d.data()};
      final ids = {
        ...sourceMap.keys,
        ...known.values
            .where((v) => v['sourceBox'] == box)
            .map((v) => txt(v, 'sourceId')),
      };
      for (final sourceId in ids) {
        final linkId = '${box}_$sourceId';
        final target = ranchSourceMilk(box, sourceMap[sourceId] ?? {});
        if ((target - numv(known[linkId] ?? {}, 'quantity')).abs() < .000001) {
          continue;
        }
        final sourceRef = ranch.collection(box).doc(sourceId);
        final linkRef = ranch.collection('vendor_ranch_links').doc(linkId);
        final stockRef = ranch.collection('vendor_stock').doc('milk');
        final entryRef = ranch.collection('vendor_entries').doc();
        try {
          await db.runTransaction(
            (tx) async {
              final source = await tx.get(sourceRef);
              final link = await tx.get(linkRef);
              final stock = await tx.get(stockRef);
              final quantity = ranchSourceMilk(box, source.data() ?? {});
              final delta = quantity - numv(link.data() ?? {}, 'quantity');
              if (delta.abs() < .000001) return;
              final balance = numv(stock.data() ?? {}, 'quantity') + delta;
              final now = DateTime.now();
              tx.set(entryRef, {
                'cloudId': entryRef.id,
                'kind': 'ranch',
                'quantity': delta,
                'sourceBox': box,
                'sourceId': sourceId,
                'linkId': linkId,
                'personName': txt(source.data() ?? {}, 'cow', 'Ranch milk'),
                'sourceCow': txt(source.data() ?? {}, 'cow'),
                'sourceDate': txt(source.data() ?? {}, 'date'),
                'sourceSession': txt(source.data() ?? {}, 'session'),
                'personId': '',
                'amount': 0,
                'paid': 0,
                'date': todayDate(),
                'time': currentTime(),
                'notes': '',
                'createdAt': now.toIso8601String(),
                'updatedAtMillis': now.millisecondsSinceEpoch,
                'createdByUid': FirebaseAuth.instance.currentUser!.uid,
                'serverCreatedAt': FieldValue.serverTimestamp(),
                'pendingUpload': false,
              });
              tx.set(linkRef, {
                'sourceBox': box,
                'sourceId': sourceId,
                'quantity': quantity,
                'entryId': entryRef.id,
              });
              tx.set(stockRef, {'quantity': balance, 'entryId': entryRef.id});
            },
            timeout: CloudSyncService.networkTimeout,
            maxAttempts: 3,
          );
        } on FirebaseException catch (error) {
          if (error.code != 'permission-denied' && error.code != 'aborted') {
            rethrow;
          }
          // Another device may have committed the exact source checkpoint.
          // Confirm that on the server; unrelated denials remain errors.
          final currentSource = await sourceRef.get(
            const GetOptions(source: Source.server),
          );
          final currentLink = await linkRef.get(
            const GetOptions(source: Source.server),
          );
          if (!currentLink.exists ||
              (ranchSourceMilk(box, currentSource.data() ?? {}) -
                          numv(currentLink.data() ?? {}, 'quantity'))
                      .abs() >=
                  .000001) {
            rethrow;
          }
        }
      }
    }
    await CloudSyncService.downloadBox('vendor_entries');
  }
}

class VendorWorkspace extends StatefulWidget {
  const VendorWorkspace({super.key});
  @override
  State<VendorWorkspace> createState() => _VendorWorkspaceState();
}

class _VendorWorkspaceState extends State<VendorWorkspace> {
  // Preferences chooses Milk vendor (delivery rides) or Milk shop (counter).
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Box<dynamic>>(
    valueListenable: Hive.box(
      'settings',
    ).listenable(keys: const ['purposeProfiles']),
    builder: (context, _, _) =>
        milkShopMode ? const MilkShopScreen() : const VendorRideScreen(),
  );
}

class RanchWorkspace extends StatefulWidget {
  final void Function(String) onOpenCard;
  const RanchWorkspace({super.key, required this.onOpenCard});
  @override
  State<RanchWorkspace> createState() => _RanchWorkspaceState();
}

class _RanchWorkspaceState extends State<RanchWorkspace> {
  @override
  Widget build(BuildContext context) =>
      DashboardScreen(onOpenCard: widget.onOpenCard);
}

/// The Reports tab follows the workspaces that are switched on: Ranch
/// reports for Ranch, Vendor reports for Vendor, and with both a Ranch /
/// Vendor switch above the period (each keeps its own period and scroll).
class VendorOnlyReports extends StatefulWidget {
  const VendorOnlyReports({super.key});
  @override
  State<VendorOnlyReports> createState() => _VendorOnlyReportsState();
}

class _VendorOnlyReportsState extends State<VendorOnlyReports> {
  int _kind = 1;

  // Rebuild when workspaces are switched on or off in Preferences.
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Box<dynamic>>(
    valueListenable: Hive.box(
      'settings',
    ).listenable(keys: const ['purposeProfiles']),
    builder: (context, _, _) => _reports(),
  );

  Widget _reports() {
    final ranch = workspaceEnabled('Ranch');
    final vendor = workspaceEnabled('Vendor');
    if (ranch && !vendor) return const ReportsScreen();
    if (!ranch || !vendor) return const _VendorReports();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 8, 21, 4),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Gold.contentWidth + Space.s56 - 42,
              ),
              child: LiquidSegmentBar(
                labels: [
                  bi('Ranch', 'பண்ணை'),
                  milkShopMode
                      ? bi('Milk shop', 'பால் கடை')
                      : bi('Vendor', 'விற்பனையாளர்'),
                ],
                icons: const [CupertinoIcons.house_fill, null],
                index: _kind,
                onChanged: (i) => setState(() => _kind = i),
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _kind,
            children: const [ReportsScreen(), _VendorReports()],
          ),
        ),
      ],
    );
  }
}

class _VendorReports extends StatefulWidget {
  const _VendorReports();
  @override
  State<_VendorReports> createState() => _VendorReportsState();
}

class _VendorReportsState extends State<_VendorReports> {
  String _period = 'This Month';

  Future<void> _export(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> shop,
  ) async {
    final output = StringBuffer(
      'Date,Time,Session,Kind,Person,Quantity (L),Price,Amount,Paid\n',
    );
    for (final row in rows) {
      output.writeln(
        [
          'date',
          'time',
          'session',
          'kind',
          'personName',
          'quantity',
          'price',
          'amount',
          'paid',
        ].map((key) => csv('${row[key] ?? ''}')).join(','),
      );
    }
    // Shop sales: the item takes the person column, the unit the session.
    for (final row in shop) {
      output.writeln(
        [
          txt(row, 'date'),
          txt(row, 'time'),
          txt(row, 'unit'),
          'shop sale',
          _shopRowName(row),
          '${row['quantity'] ?? ''}',
          '${row['price'] ?? ''}',
          '${row['amount'] ?? ''}',
          '${row['amount'] ?? ''}',
        ].map(csv).join(','),
      );
    }
    await downloadCsvFile(
      'vendor_${safeFileName(_period)}_${todayDate()}.csv',
      output.toString(),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      Hive.box('vendor_entries').listenable(),
      if (Hive.isBoxOpen(shopBox)) Hive.box(shopBox).listenable(),
    ]),
    builder: (context, _) {
      // Each vendor mode reports only its own work. The shop's milk comes
      // from providers, so their deliveries are its cost; customer sales,
      // payments and clearances belong to delivery rides.
      final shopMode = milkShopMode;
      final shop = shopMode
          ? shopRows()
                .where(
                  (r) =>
                      r['voided'] != true &&
                      (r['kind'] == 'sale' ||
                          r['kind'] == 'stock' && r['itemId'] == 'milk') &&
                      matchPeriod(txt(r, 'date'), _period),
                )
                .toList()
          : <Map<String, dynamic>>[];
      final shopSales = shop.where((r) => r['kind'] == 'sale').toList();
      final rows =
          vendorRows('vendor_entries')
              .where(
                (r) =>
                    r['kind'] != 'ranch' &&
                    (!shopMode ||
                        r['kind'] == 'collection' ||
                        r['kind'] == 'purchase') &&
                    matchPeriod(txt(r, 'date'), _period),
              )
              .toList()
            ..sort(
              (a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')),
            );
      double shopSum(bool sale, String field) => shop
          .where((r) => sale ? r['kind'] == 'sale' : r['kind'] == 'stock')
          .where((r) => field == 'amount' || r['itemId'] == 'milk')
          .fold(0.0, (s, r) => s + numv(r, field));
      final milkIn =
          _vendorSum(rows, 'collection', 'quantity') +
          _vendorSum(rows, 'purchase', 'quantity') +
          shopSum(false, 'quantity');
      final delivered = shopMode
          ? shopSum(true, 'quantity')
          : _vendorSum(rows, 'sale', 'quantity');
      final sales = shopMode
          ? shopSum(true, 'amount')
          : _vendorSum(rows, 'sale', 'amount');
      final cost =
          _vendorSum(rows, 'collection', 'amount') +
          _vendorSum(rows, 'purchase', 'amount');
      final entries = [
        ...rows,
        for (final r in shop) {...r, '_shop': true},
      ]..sort((a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')));
      final dates = <String>[];
      for (final r in entries) {
        if (!dates.contains(txt(r, 'date'))) dates.add(txt(r, 'date'));
      }
      return Shell(
        edgeToEdge: true,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            21,
            8,
            21,
            floatingBarClearance(context),
          ),
          children: [
            LiquidSegmentBar(
              labels: const ['Today', 'Week', 'Month', 'Year'],
              index: periods.indexOf(_period).clamp(0, periods.length - 1),
              onChanged: (i) => setState(() => _period = periods[i]),
            ),
            const SizedBox(height: 18),
            _VendorProfitCard(sales: sales, cost: cost),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _VendorReportTile(
                    icon: CupertinoIcons.arrow_down_circle_fill,
                    color: Ink.greenText,
                    value: '${vendorFieldNumber(milkIn)} L',
                    label: bi('Milk in', 'வந்த பால்'),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: _VendorReportTile(
                    icon: CupertinoIcons.arrow_up_circle_fill,
                    color: Ink.violetDeep,
                    value: '${vendorFieldNumber(delivered)} L',
                    label: shopMode
                        ? bi('Milk sold', 'விற்ற பால்')
                        : bi('Delivered', 'கொடுத்த பால்'),
                  ),
                ),
              ],
            ),
            if (!shopMode) ...[
              const SizedBox(height: 13),
              Glass(
                radius: 24,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                onTap: () => push(context, const CustomerReportsScreen()),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Ink.violetDeep.withValues(alpha: .1),
                      ),
                      child: Icon(
                        CupertinoIcons.person_crop_rectangle_fill,
                        color: Ink.violetDeep,
                        size: 21,
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
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
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
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: Ink.faint,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 27),
            Row(
              children: [
                Expanded(
                  child: Text(
                    bi('Entries', 'பதிவுகள்'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Ink.navy,
                    ),
                  ),
                ),
                if (entries.isNotEmpty)
                  IconButton(
                    tooltip: bi(
                      'Export vendor report',
                      'விற்பனையாளர் அறிக்கையைப் பதிவிறக்கு',
                    ),
                    icon: Icon(
                      CupertinoIcons.arrow_down_doc,
                      color: Ink.violetDeep,
                    ),
                    onPressed: () => _export(rows, shopSales),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 34),
                child: Column(
                  children: [
                    shopMode
                        ? Icon(
                            Icons.storefront_rounded,
                            size: 55,
                            color: Ink.faint,
                          )
                        : MilkVendorIcon(size: 55, color: Ink.faint),
                    const SizedBox(height: 13),
                    Text(
                      shopMode
                          ? bi(
                              'No shop entries in this period.',
                              'இந்தக் காலத்தில் கடைப் பதிவுகள் இல்லை.',
                            )
                          : bi(
                              'No vendor entries in this period.',
                              'இந்தக் காலத்தில் விற்பனையாளர் பதிவுகள் இல்லை.',
                            ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Ink.muted),
                    ),
                  ],
                ),
              ),
            for (final date in dates) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Text(
                  ui(chatDateLabel(date)),
                  style: TextStyle(
                    color: Ink.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Glass(
                radius: 21,
                padding: const EdgeInsets.symmetric(vertical: 4),
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    for (final (i, r)
                        in entries
                            .where((r) => txt(r, 'date') == date)
                            .indexed) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          thickness: .5,
                          indent: 66,
                          color: Color(0x1A202635),
                        ),
                      r['_shop'] == true
                          ? _ShopReportRow(row: r)
                          : _VendorReportRow(row: r),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _VendorProfitCard extends StatelessWidget {
  final double sales, cost;
  const _VendorProfitCard({required this.sales, required this.cost});
  @override
  Widget build(BuildContext context) {
    final profit = sales - cost;
    final good = profit >= 0;
    return Glass(
      radius: 27,
      padding: const EdgeInsets.fromLTRB(21, 18, 21, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (good ? Ink.green : Ink.red).withValues(alpha: .12),
                ),
                child: Icon(
                  good
                      ? CupertinoIcons.arrow_up_right
                      : CupertinoIcons.arrow_down_right,
                  size: 21,
                  color: good ? Ink.greenText : Ink.redText,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      good ? bi('Profit', 'லாபம்') : bi('Loss', 'நஷ்டம்'),
                      style: TextStyle(
                        color: Ink.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        money(profit.abs()),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.6,
                          color: good ? Ink.greenText : Ink.redText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MoneyLine(
                  icon: CupertinoIcons.cart_fill,
                  label: bi('Sales', 'விற்பனை'),
                  value: money(sales),
                  color: Ink.violetDeep,
                ),
              ),
              Container(width: .5, height: 34, color: const Color(0x33202635)),
              Expanded(
                child: _MoneyLine(
                  icon: CupertinoIcons.bag_fill,
                  label: bi('Milk cost', 'பால் செலவு'),
                  value: money(cost),
                  color: Ink.amberText,
                  end: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final bool end;
  const _MoneyLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.end = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: end ? 16 : 0, end: end ? 0 : 16),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Ink.muted, fontSize: 12),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AppText(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _VendorReportTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, label;
  const _VendorReportTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => Glass(
    radius: 21,
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Icon(icon, size: 30, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AppText(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
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
        ),
      ],
    ),
  );
}

/// A counter sale or milk added at the shop, in the Milk shop report.
class _ShopReportRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ShopReportRow({required this.row});
  @override
  Widget build(BuildContext context) {
    final sale = row['kind'] == 'sale';
    final color = sale ? Ink.violetDeep : Ink.amberText;
    final unit = shopUnitShort(txt(row, 'unit'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 10, 16, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: .1),
            ),
            child: Icon(
              sale ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down,
              size: 19,
              color: color,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shopRowName(row),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
                AppText(
                  '${sale ? bi('Sold', 'விற்றது') : bi('Stock added', 'இருப்பு சேர்த்தது')} · ${txt(row, 'time')}',
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
                '${vendorFieldNumber(numv(row, 'quantity'))} $unit',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: color,
                ),
              ),
              if (sale)
                AppText(
                  shopMoney(numv(row, 'amount')),
                  style: TextStyle(color: Ink.muted, fontSize: 13),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VendorReportRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _VendorReportRow({required this.row});
  @override
  Widget build(BuildContext context) {
    final kind = txt(row, 'kind');
    final payment = kind == 'payment';
    final intake = kind == 'collection' || kind == 'purchase';
    final clearance = kind == 'clearance';
    final color = payment
        ? Ink.greenText
        : intake
        ? Ink.amberText
        : clearance
        ? Ink.blue
        : Ink.violetDeep;
    final icon = payment
        ? Icons.currency_rupee_rounded
        : intake
        ? CupertinoIcons.arrow_down
        : clearance
        ? CupertinoIcons.tray_arrow_down
        : CupertinoIcons.arrow_up;
    final person = vendorRows(
      'vendor_people',
    ).where((p) => p['id'] == row['personId']).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(21),
      onTap: person == null
          ? null
          : () => push(
              context,
              VendorPersonScreen(
                person: person,
                intakeKind: kind == 'purchase' ? 'purchase' : 'collection',
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 10, 16, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: .1),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vendorEntryPersonName(row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Ink.navy,
                    ),
                  ),
                  Text(
                    [
                      vendorEntryLabel(kind),
                      if (txt(row, 'session').isNotEmpty)
                        ui(txt(row, 'session')),
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
                Text(
                  payment
                      ? money(numv(row, 'amount'))
                      : '${vendorFieldNumber(numv(row, 'quantity'))} L',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (!payment &&
                    !clearance &&
                    !(kind == 'fridge_use' && row['use'] == 'curd'))
                  Text(
                    money(numv(row, 'amount')),
                    style: TextStyle(color: Ink.muted, fontSize: 13),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String vendorEntryLabel(String kind) => switch (kind) {
  'collection' => bi('Collected', 'சேகரித்தது'),
  'purchase' => bi('Purchased', 'வாங்கியது'),
  'sale' => bi('Sold', 'விற்றது'),
  'clearance' => bi('Milk clearance', 'பால் கிளியரன்ஸ்'),
  'fridge_use' => bi('Fridge milk used', 'ஃப்ரிட்ஜ் பால் பயன்பாடு'),
  _ => bi('Payment', 'பணம் செலுத்தியது'),
};

/// Clearance to the fridge has no person; show a localized name for it.
String vendorEntryPersonName(Map<String, dynamic> row) =>
    row['personKind'] == 'fridge'
    ? (row['kind'] == 'fridge_use'
          ? (row['use'] == 'curd'
                ? bi('Fridge → curd', 'ஃப்ரிட்ஜ் → தயிர்')
                : bi('Fridge → sold', 'ஃப்ரிட்ஜ் → விற்றது'))
          : bi('Fridge', 'ஃப்ரிட்ஜ்'))
    : row['personKind'] == 'walkin'
    ? bi('Walk-in customer', 'தெரியாத வாடிக்கையாளர்')
    : txt(row, 'personName');
