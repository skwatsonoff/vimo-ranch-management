part of 'main.dart';

List<Map<String, dynamic>> monthlyCowMilk(
  Iterable<Map<String, dynamic>> records,
  String cow,
) {
  final months = <String, double>{};
  for (final row in records) {
    if (txt(row, 'cow') != cow) continue;
    final date = DateTime.tryParse(txt(row, 'date'));
    if (date == null) continue;
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-01';
    months[key] = (months[key] ?? 0) + numv(row, 'quantity');
  }
  return months.entries
      .map((e) => <String, dynamic>{'date': e.key, 'quantity': e.value})
      .toList()
    ..sort((a, b) => txt(b, 'date').compareTo(txt(a, 'date')));
}

String monthLabel(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  const en = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const ta = [
    'ஜனவரி',
    'பிப்ரவரி',
    'மார்ச்',
    'ஏப்ரல்',
    'மே',
    'ஜூன்',
    'ஜூலை',
    'ஆகஸ்ட்',
    'செப்டம்பர்',
    'அக்டோபர்',
    'நவம்பர்',
    'டிசம்பர்',
  ];
  return '${(tamilUi ? ta : en)[date.month - 1]} ${date.year}';
}

Future<void> showWorkspaceAdd(BuildContext context, String workspace) async {
  if (workspace == 'Social') {
    if (accountUsername.isEmpty) {
      await push(context, const UsernameScreen());
      if (!context.mounted || accountUsername.isEmpty) return;
    }
    await push(context, const SocialComposer());
    return;
  }
  if (!canRecordEntries) return;
  if (workspace == 'Ranch') {
    await push(context, const AddEntryScreen());
    return;
  }
  await push(context, const VendorPersonForm());
}

String reportRecordName(Map<String, dynamic> row) {
  for (final key in [
    'customerName',
    'personName',
    'cow',
    'name',
    'item',
    '_type',
  ]) {
    final value = txt(row, key);
    if (value.isNotEmpty) {
      return isOwnUseCustomer(value) ? ownUseDisplayName : ui(value);
    }
  }
  return '';
}

String reportTitle(String kind) => ui(switch (kind) {
  'collected' => 'Milk Collected',
  'sold' => 'Milk Sold',
  'income' => 'Income',
  _ => 'Expense',
});

// The detail list uses the same sources and amount fields as the summary cards.
List<Map<String, dynamic>> reportDetailRows(String kind, String period) {
  final result = <Map<String, dynamic>>[];
  void add(
    Iterable<Map<String, dynamic>> source,
    String amountKey,
    String type,
  ) {
    for (final row in source) {
      if (matchPeriod(txt(row, 'date'), period)) {
        result.add({...row, '_value': numv(row, amountKey), '_type': type});
      }
    }
  }

  switch (kind) {
    case 'collected':
      add(milkRows(), 'quantity', 'Milk');
    case 'sold':
      add(
        saleRows().where(
          (r) =>
              (txt(r, 'type') == 'Milk' || txt(r, 'category') == 'Milk Sale') &&
              !isOwnUseMilk(r),
        ),
        'quantity',
        'Milk',
      );
    case 'income':
      add(saleRows(), 'amount', 'Sale');
    default:
      add(foodRows(), 'price', 'Feed');
      add(
        stockRows().where((r) => txt(r, 'movement') == 'Purchase'),
        'amount',
        'Feed',
      );
      add(expenseRows(), 'amount', 'Expense');
      add(doctorRows(), 'cost', 'Doctor');
      add(purchaseRows(), 'amount', 'Purchase');
      add(deathRows(), 'cost', 'Loss recorded');
  }
  result.sort(
    (a, b) => '${txt(b, 'date')} ${txt(b, 'time')}'.compareTo(
      '${txt(a, 'date')} ${txt(a, 'time')}',
    ),
  );
  return result;
}

class ReportDetailsScreen extends StatelessWidget {
  final String kind, period;
  const ReportDetailsScreen({
    super.key,
    required this.kind,
    required this.period,
  });
  @override
  Widget build(BuildContext context) {
    final records = reportDetailRows(kind, period);
    final milk = kind == 'collected' || kind == 'sold';
    return Scaffold(
      appBar: AppBar(title: Text(reportTitle(kind))),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.all(21),
          children: [
            Text(ui(period), style: const TextStyle(color: Ink.muted)),
            const SizedBox(height: 16),
            if (records.isEmpty)
              Text(
                bi(
                  'No entries in this period.',
                  'இந்தக் காலத்தில் பதிவுகள் இல்லை.',
                ),
              ),
            for (final row in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Glass(
                  padding: const EdgeInsets.all(18),
                  onTap: () => push(
                    context,
                    RecordFullDetailsScreen(
                      record: row,
                      title: '${reportTitle(kind)} details',
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              reportRecordName(row),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            milk
                                ? '${numv(row, '_value').toStringAsFixed(1)} L'
                                : money(numv(row, '_value')),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Ink.faint,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      AppText(
                        '${txt(row, 'date')} · ${txt(row, 'time')} ${ui(txt(row, 'session'))}',
                        style: const TextStyle(color: Ink.muted),
                      ),
                      if (txt(row, 'notes').isNotEmpty) Text(txt(row, 'notes')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Map<String, int> cowRankStreak(String cowName) {
  final totals = <String, Map<String, double>>{};
  for (final row in milkRows()) {
    final date = DateTime.tryParse(txt(row, 'date'));
    final cow = txt(row, 'cow');
    if (date == null || cow.isEmpty) continue;
    final month = '${date.year}-${date.month.toString().padLeft(2, '0')}-01';
    totals.putIfAbsent(month, () => <String, double>{});
    totals[month]![cow] = (totals[month]![cow] ?? 0) + numv(row, 'quantity');
  }
  final months = totals.keys.toList()..sort((a, b) => b.compareTo(a));
  int maintainedRank = 0;
  int streak = 0;
  for (final month in months) {
    final ranked = totals[month]!.entries.toList()
      ..sort((a, b) {
        final quantity = b.value.compareTo(a.value);
        return quantity != 0 ? quantity : a.key.compareTo(b.key);
      });
    final index = ranked.indexWhere((entry) => entry.key == cowName);
    final rank = index >= 0 && index < 3 ? index + 1 : 0;
    if (streak == 0) {
      if (rank == 0) continue;
      maintainedRank = rank;
      streak = 1;
    } else if (rank == maintainedRank) {
      streak++;
    } else {
      break;
    }
  }
  return {'rank': maintainedRank, 'months': streak};
}

/// Sync, device and account plumbing is never shown to people.
bool isInternalField(String key) {
  if (key.startsWith('_') || key == 'key') return true;
  const hidden = {
    'pendingUpload',
    'updatedAtMillis',
    'photo',
    'voice',
    'imageData',
    'imageUrl',
    'mentions',
    'bioMentions',
    'stockScope',
    'syncMode',
    'revision',
    'schemaVersion',
  };
  if (hidden.contains(key)) return true;
  final k = key.toLowerCase();
  const publicIds = {'id', 'cowid', 'calfid', 'animalid', 'tagid'};
  if (publicIds.contains(k)) return false;
  // CamelCase suffixes only, so fields like "paid" stay visible.
  return k == 'uid' ||
      key.endsWith('Uid') ||
      key.endsWith('Id') ||
      key.endsWith('ID') ||
      key.endsWith('Key') ||
      k.contains('device') ||
      k.contains('cloud') ||
      k.contains('millis') ||
      k.contains('sync') ||
      k.startsWith('createdat') ||
      k.startsWith('updatedat') ||
      k.endsWith('timestamp');
}

class RecordFullDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> record;
  final String title;
  const RecordFullDetailsScreen({
    super.key,
    required this.record,
    this.title = 'Entry details',
  });

  static const _hidden = {
    '_sort',
    '_value',
    '_type',
    'pendingUpload',
    'updatedAtMillis',
    'photo',
    'voice',
  };

  String _label(String key) => key
      .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
      .replaceAll('_', ' ')
      .trim()
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final entries = record.entries
        .where(
          (entry) =>
              !_hidden.contains(entry.key) &&
              !isInternalField(entry.key) &&
              entry.value is! Map &&
              entry.value is! List &&
              '${entry.value}'.trim().isNotEmpty,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: AppText(title), leading: const _BackButton()),
      body: Shell(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(21, 21, 21, 55),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            final entry = entries[index];
            return Glass(
              radius: Gold.r21,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: AppText(
                      _label(entry.key),
                      style: const TextStyle(
                        color: Ink.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: AppText(
                      '${entry.value}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Ink.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
