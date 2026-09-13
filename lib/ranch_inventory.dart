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
        .get(const GetOptions(source: Source.server));
    final known = {for (final d in links.docs) d.id: d.data()};
    for (final box in ['milk_records', 'sale_records']) {
      final sources = await ranch
          .collection(box)
          .get(const GetOptions(source: Source.server));
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
          await db.runTransaction((tx) async {
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
              'personName': 'Ranch milk',
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
          });
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
        padding: const EdgeInsets.fromLTRB(21, 12, 21, 0),
        child: LiquidSegmentBar(
          labels: [
            bi('Customers', 'வாடிக்கையாளர்கள்'),
            'Sales',
            'Stock',
            'Reports',
          ],
          index: _page,
          onChanged: (i) => setState(() => _page = i),
        ),
      ),
      Expanded(
        child: switch (_page) {
          0 => const VendorScreen(),
          1 => const SellScreen(embedded: true),
          2 => const _CombinedStock(),
          _ => const ReportsScreen(),
        },
      ),
    ],
  );
}

class _CombinedStock extends StatefulWidget {
  const _CombinedStock();
  @override
  State<_CombinedStock> createState() => _CombinedStockState();
}

class _CombinedStockState extends State<_CombinedStock> {
  int _page = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: LiquidSegmentBar(
          labels: ['Milk', 'Feed'],
          index: _page,
          onChanged: (i) => setState(() => _page = i),
        ),
      ),
      Expanded(
        child: _page == 0
            ? const VendorStockScreen()
            : const SellScreen(embedded: true, initialSection: 1),
      ),
    ],
  );
}
