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
  final date = DateTime.parse(value);
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
  await push(
    context,
    Scaffold(
      appBar: AppBar(title: Text(bi('Vendor', 'விற்பனையாளர்'))),
      body: const VendorWorkspace(),
    ),
  );
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
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
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
