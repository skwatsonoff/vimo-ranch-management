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
  int _page = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in [
              (0, bi('Collect milk', 'பால் சேகரிப்பு')),
              (1, bi('Buy milk', 'பால் கொள்முதல்')),
              (2, bi('Sell milk', 'பால் விற்பனை')),
              (3, bi('Milk stock', 'பால் இருப்பு')),
              (4, bi('Reports', 'அறிக்கைகள்')),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: _page == item.$1,
                onSelected: (_) => setState(() => _page = item.$1),
              ),
          ],
        ),
      ),
      Expanded(
        child: switch (_page) {
          0 || 1 || 2 => VendorScreen(
            key: ValueKey(_page),
            initialSection: _page,
            showTabs: false,
          ),
          3 => const VendorStockScreen(),
          _ => const VendorOnlyReports(),
        },
      ),
    ],
  );
}

class RanchWorkspace extends StatefulWidget {
  final void Function(String) onOpenCard;
  const RanchWorkspace({super.key, required this.onOpenCard});
  @override
  State<RanchWorkspace> createState() => _RanchWorkspaceState();
}

class _RanchWorkspaceState extends State<RanchWorkspace> {
  int _page = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in [
              (0, bi('Overview', 'முகப்பு')),
              (1, bi('Cows', 'மாடுகள்')),
              (2, bi('Calves', 'கன்றுகள்')),
              (3, bi('Sell', 'விற்பனை')),
              (4, bi('Stock', 'இருப்பு')),
              (5, bi('Reports', 'அறிக்கைகள்')),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: _page == item.$1,
                onSelected: (_) => setState(() => _page = item.$1),
              ),
          ],
        ),
      ),
      Expanded(
        child: switch (_page) {
          0 => DashboardScreen(onOpenCard: widget.onOpenCard),
          1 => const AnimalsScreen(key: ValueKey('ranch-cows'), initialTab: 0),
          2 => const AnimalsScreen(
            key: ValueKey('ranch-calves'),
            initialTab: 1,
          ),
          3 => const SellScreen(key: ValueKey('ranch-sell'), embedded: true),
          4 => const SellScreen(
            key: ValueKey('ranch-stock'),
            embedded: true,
            initialSection: 1,
          ),
          _ => const ReportsScreen(),
        },
      ),
    ],
  );
}

class VendorOnlyReports extends StatefulWidget {
  const VendorOnlyReports({super.key});
  @override
  State<VendorOnlyReports> createState() => _VendorOnlyReportsState();
}

class _VendorOnlyReportsState extends State<VendorOnlyReports> {
  String _period = 'This Month';
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
      return Shell(
        child: ListView(
          padding: const EdgeInsets.all(21),
          children: [
            Text(
              bi('Vendor reports', 'விற்பனையாளர் அறிக்கைகள்'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            LiquidSegmentBar(
              labels: const ['Today', 'Week', 'Month', 'Year'],
              index: periods.indexOf(_period).clamp(0, periods.length - 1),
              onChanged: (i) => setState(() => _period = periods[i]),
            ),
            const SizedBox(height: 18),
            VendorReportSummary(period: _period),
            TextButton.icon(
              icon: const Icon(Icons.file_download_outlined),
              label: Text(
                bi(
                  'Export vendor report',
                  'விற்பனையாளர் அறிக்கையைப் பதிவிறக்கு',
                ),
              ),
              onPressed: () async {
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
              },
            ),

            for (final row in rows)
              ListTile(
                title: Text(
                  '${vendorEntryLabel(txt(row, 'kind'))} · ${txt(row, 'personName')}',
                ),
                subtitle: Text(
                  '${txt(row, 'date')} · ${ui(txt(row, 'session'))} · ${numv(row, 'quantity').toStringAsFixed(2)} L',
                ),
                trailing: Text(money(numv(row, 'amount'))),
              ),
            if (rows.isEmpty)
              Text(
                bi(
                  'No vendor entries in this period.',
                  'இந்தக் காலத்தில் விற்பனையாளர் பதிவுகள் இல்லை.',
                ),
              ),
          ],
        ),
      );
    },
  );
}

String vendorEntryLabel(String kind) => switch (kind) {
  'collection' => bi('Collected', 'சேகரித்தது'),
  'purchase' => bi('Purchased', 'வாங்கியது'),
  'sale' => bi('Sold', 'விற்றது'),
  _ => bi('Payment', 'பணம் செலுத்தியது'),
};
