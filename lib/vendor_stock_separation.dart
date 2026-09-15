part of 'main.dart';

double vendorOpeningBalance(Iterable<Map<String, dynamic>> rows) {
  final legacy = rows.where((r) => r['stockScope'] != 'vendor_v2');
  final delta = legacy.fold(
    0.0,
    (total, r) =>
        total +
        (r['kind'] == 'purchase' || r['kind'] == 'collection'
            ? numv(r, 'quantity')
            : r['kind'] == 'sale'
            ? -numv(r, 'quantity')
            : 0),
  );
  return math.max(0, delta);
}

/// Preserve the old implicit ranch consumption at the cutover. New vendor
/// sales must never consume ranch milk. Historical entries are not rewritten.
double legacyVendorRanchUse(String period) {
  if (!Hive.isBoxOpen('vendor_entries')) return 0;
  final rows = vendorRows('vendor_entries').where(
    (r) =>
        r['stockScope'] != 'vendor_v2' && matchPeriod(txt(r, 'date'), period),
  );
  return math.max(
    0,
    rows.fold(
      0.0,
      (total, r) =>
          total +
          (r['kind'] == 'sale'
              ? numv(r, 'quantity')
              : r['kind'] == 'purchase' || r['kind'] == 'collection'
              ? -numv(r, 'quantity')
              : 0),
    ),
  );
}

class SeparateVendorStock {
  static Future<void> ensureInitialized() async {
    final ranch = CloudSyncService.ranch;
    final db = FirebaseFirestore.instance;
    final stock = ranch.collection('vendor_stock').doc('vendor_milk');
    final old = ranch.collection('vendor_stock').doc('milk');
    if ((await stock
            .get(const GetOptions(source: Source.server))
            .timeout(CloudSyncService.networkTimeout))
        .exists) {
      return;
    }
    if (!canManageRanch) {
      throw StateError(
        bi(
          'An admin must open Vendor once to separate the existing stock.',
          'பழைய இருப்பைப் பிரிக்க நிர்வாகி ஒருமுறை விற்பனையாளர் பக்கத்தைத் திறக்க வேண்டும்.',
        ),
      );
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      final before = await old
          .get(const GetOptions(source: Source.server))
          .timeout(CloudSyncService.networkTimeout);
      final ledger = await ranch
          .collection('vendor_entries')
          .get(const GetOptions(source: Source.server))
          .timeout(CloudSyncService.networkTimeout);
      final quantity = vendorOpeningBalance(ledger.docs.map((d) => d.data()));
      final completed = await db.runTransaction<bool>((tx) async {
        final current = await tx.get(stock);
        final prior = await tx.get(old);
        if (current.exists) return true;
        if (!sameSyncValue(before.data(), prior.data())) return false;
        tx.set(stock, {'quantity': quantity, 'entryId': 'migration_v2'});
        return true;
      }, timeout: CloudSyncService.networkTimeout);
      if (completed) return;
    }
    throw StateError(
      bi(
        'Stock changed during setup. Retry shortly.',
        'அமைப்பின்போது இருப்பு மாறியது. மீண்டும் முயற்சிக்கவும்.',
      ),
    );
  }
}
