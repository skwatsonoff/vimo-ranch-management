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
  @override
  Widget build(BuildContext context) => const VendorRideScreen();
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

class VendorOnlyReports extends StatefulWidget {
  const VendorOnlyReports({super.key});
  @override
  State<VendorOnlyReports> createState() => _VendorOnlyReportsState();
}

class _VendorOnlyReportsState extends State<VendorOnlyReports> {
  String _period = 'This Month';

  Future<void> _export(List<Map<String, dynamic>> rows) async {
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
    await downloadCsvFile(
      'vendor_${safeFileName(_period)}_${todayDate()}.csv',
      output.toString(),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('vendor_entries').listenable(),
    builder: (context, _, _) {
      final rows =
          vendorRows('vendor_entries')
              .where(
                (r) =>
                    r['kind'] != 'ranch' &&
                    matchPeriod(txt(r, 'date'), _period),
              )
              .toList()
            ..sort(
              (a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')),
            );
      final milkIn =
          _vendorSum(rows, 'collection', 'quantity') +
          _vendorSum(rows, 'purchase', 'quantity');
      final delivered = _vendorSum(rows, 'sale', 'quantity');
      final sales = _vendorSum(rows, 'sale', 'amount');
      final cost =
          _vendorSum(rows, 'collection', 'amount') +
          _vendorSum(rows, 'purchase', 'amount');
      final dates = <String>[];
      for (final r in rows) {
        if (!dates.contains(txt(r, 'date'))) dates.add(txt(r, 'date'));
      }
      return Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(21, 8, 21, 120),
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
                    label: bi('Delivered', 'கொடுத்த பால்'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 27),
            Row(
              children: [
                Expanded(
                  child: Text(
                    bi('Entries', 'பதிவுகள்'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: Ink.navy,
                    ),
                  ),
                ),
                if (rows.isNotEmpty)
                  IconButton(
                    tooltip: bi(
                      'Export vendor report',
                      'விற்பனையாளர் அறிக்கையைப் பதிவிறக்கு',
                    ),
                    icon: const Icon(
                      Icons.file_download_outlined,
                      color: Ink.violetDeep,
                    ),
                    onPressed: () => _export(rows),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 34),
                child: Column(
                  children: [
                    const MilkVendorIcon(size: 55, color: Ink.faint),
                    const SizedBox(height: 13),
                    Text(
                      bi(
                        'No vendor entries in this period.',
                        'இந்தக் காலத்தில் விற்பனையாளர் பதிவுகள் இல்லை.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Ink.muted),
                    ),
                  ],
                ),
              ),
            for (final date in dates) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Text(
                  ui(chatDateLabel(date)),
                  style: const TextStyle(
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
                        in rows
                            .where((r) => txt(r, 'date') == date)
                            .indexed) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          thickness: .5,
                          indent: 66,
                          color: Color(0x1A202635),
                        ),
                      _VendorReportRow(row: r),
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
                      style: const TextStyle(
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
                          fontWeight: FontWeight.w800,
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
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Ink.muted, fontSize: 12),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
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
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Ink.navy,
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Ink.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _VendorReportRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _VendorReportRow({required this.row});
  @override
  Widget build(BuildContext context) {
    final kind = txt(row, 'kind');
    final payment = kind == 'payment';
    final intake = kind == 'collection' || kind == 'purchase';
    final color = payment
        ? Ink.greenText
        : intake
        ? Ink.amberText
        : Ink.violetDeep;
    final icon = payment
        ? CupertinoIcons.money_dollar
        : intake
        ? CupertinoIcons.arrow_down
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
                    txt(row, 'personName'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
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
                    style: const TextStyle(color: Ink.muted, fontSize: 12.5),
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
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (!payment)
                  Text(
                    money(numv(row, 'amount')),
                    style: const TextStyle(color: Ink.muted, fontSize: 12.5),
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
  _ => bi('Payment', 'பணம் செலுத்தியது'),
};
