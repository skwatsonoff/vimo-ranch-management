part of 'main.dart';

// =============================================================================
//  What VIMO does once a voice conversation is complete: answers questions
//  from the ranch's records, and saves the entries it confirmed (a new cow,
//  an expense, feed stock, the doctor, injections, pregnancy, sickness).
//  Every write uses the same fields as the app's own forms.
// =============================================================================

/// One entry saved by voice, for the chat and the report.
class VoiceSavedAction {
  final String kind;
  final String summary;
  final DateTime at;
  VoiceSavedAction(this.kind, this.summary) : at = DateTime.now();
}

String _periodFor(Object? range) => switch ('$range') {
  'this_week' => 'This Week',
  'this_month' => 'This Month',
  'this_year' => 'This Year',
  _ => 'Today',
};

String _rangeTa(Object? range) => switch ('$range') {
  'yesterday' => 'நேற்று',
  'this_week' => 'இந்த வாரம்',
  'this_month' => 'இந்த மாதம்',
  'this_year' => 'இந்த வருடம்',
  'all' => 'இதுவரை',
  _ => 'இன்று',
};

String _rangeEn(Object? range) => switch ('$range') {
  'yesterday' => 'yesterday',
  'this_week' => 'this week',
  'this_month' => 'this month',
  'this_year' => 'this year',
  'all' => 'so far',
  _ => 'today',
};

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

double _yesterdayMilk({String? cow}) {
  final y = DateTime.now().subtract(const Duration(days: 1));
  final day = '${y.year}-${two(y.month)}-${two(y.day)}';
  double total = 0;
  for (final r in milkRows()) {
    if (txt(r, 'date') != day) continue;
    if (cow != null && txt(r, 'cow') != cow) continue;
    total += numv(r, 'quantity');
  }
  return total;
}

/// The spoken answer to a question, from this phone's records.
VoiceLine answerVoiceQuestion(Map<String, Object?> slots) {
  final metric = '${slots['metric']}';
  final range = slots['range'];
  final period = _periodFor(range);
  final rTa = _rangeTa(range);
  final rEn = _rangeEn(range);
  switch (metric) {
    case 'milk':
      final cow = slots['cow'] as String?;
      final total = range == 'yesterday'
          ? _yesterdayMilk(cow: cow)
          : cow != null
          ? cowMilkForPeriod(cow, period)
          : milkTotal(period);
      final who = cow == null ? '' : '${tamilCowName(cow)} ';
      return VoiceLine(
        '$rTa $who${cow == null ? 'மொத்தம் ' : ''}${_num(total)} லிட்டர் பால்.',
        '$rEn ${cow ?? 'mottham'} ${_num(total)} litre paal.',
        '${cow ?? 'Total milk'} $rEn: ${_num(total)} litres.',
      );
    case 'milk_sold':
      final sold = milkSold(period);
      return VoiceLine(
        '$rTa ${_num(sold)} லிட்டர் பால் விற்பனை.',
        '$rEn ${_num(sold)} litre paal virpanai.',
        'Milk sold $rEn: ${_num(sold)} litres.',
      );
    case 'stock':
      final item = slots['item'] == 'vaikol' ? 'Vaikol' : 'Thavudu';
      final left = stockBalance(item);
      final itemTa = item == 'Vaikol' ? 'வைக்கோல்' : 'தவுடு';
      final unitTa = item == 'Vaikol' ? 'கட்டு' : 'கிலோ';
      final unitEn = item == 'Vaikol' ? 'bundles' : 'kg';
      return VoiceLine(
        '$itemTa ${_num(left)} $unitTa இருக்கு.',
        '${item.toLowerCase()} ${_num(left)} $unitEn irukku.',
        '${item == 'Vaikol' ? 'Hay' : 'Bran'} left: ${_num(left)} $unitEn.',
      );
    case 'cow_count':
      final n = animalsBy('cow').length;
      return VoiceLine(
        '$n மாடுகள் இருக்கு.',
        '$n maadu irukku.',
        'You have $n cows.',
      );
    case 'calf_count':
      final n = animalsBy('calf').length;
      return VoiceLine(
        '$n கன்றுகள் இருக்கு.',
        '$n kanru irukku.',
        'You have $n calves.',
      );
    case 'pregnant_count':
      final n = pregnantCowCount();
      return VoiceLine(
        '$n மாடுகள் சினையாக உள்ளன.',
        '$n maadu sinaiya irukku.',
        '$n cows are pregnant.',
      );
    case 'expense':
      final spent = totalExpense(period);
      return VoiceLine(
        '$rTa மொத்த செலவு ${_num(spent)} ரூபாய்.',
        '$rEn mottha selavu ${_num(spent)} rupaai.',
        'Total expenses $rEn: ${_num(spent)} rupees.',
      );
    case 'profit':
      final p = profit(period);
      return VoiceLine(
        '$rTa லாபம் ${_num(p)} ரூபாய்.',
        '$rEn laabam ${_num(p)} rupaai.',
        'Profit $rEn: ${_num(p)} rupees.',
      );
    case 'ranking':
      final top = topCowRankings(
        limit: 1,
        period: period == 'Today' ? 'This Month' : period,
      );
      if (top.isEmpty) {
        return const VoiceLine(
          'இன்னும் பால் பதிவு இல்லை.',
          'Innum paal padhivu illa.',
          'No milk recorded yet.',
        );
      }
      final name = txt(top.first, 'name');
      return VoiceLine(
        '${tamilCowName(name)} அதிக பால் கொடுத்தது, ${_num(numv(top.first, 'rankMilk'))} லிட்டர்.',
        '$name adhiga paal, ${_num(numv(top.first, 'rankMilk'))} litre.',
        '$name gave the most milk: ${_num(numv(top.first, 'rankMilk'))} litres.',
      );
  }
  return const VoiceLine(
    'இதற்கான பதிலை app-இன் அறிக்கைகளில் பாருங்கள்.',
    'Idharkaana badhilai app reports-la paarunga.',
    'Please see the app\'s reports for that.',
  );
}

dynamic _animalKeyByName(String name) {
  final box = Hive.box('animals');
  for (final key in box.keys) {
    final row = box.get(key);
    if (row is Map && '${row['name']}' == name) return key;
  }
  return null;
}

/// Saves a confirmed voice entry. Returns what was saved, or null when the
/// kind is not saved by voice.
Future<VoiceSavedAction?> saveVoiceAction(VoiceAction action) async {
  final saved = await _saveVoiceAction(action);
  if (saved != null) AutoSyncService.scheduleSync(reason: 'voice entry saved');
  return saved;
}

Future<VoiceSavedAction?> _saveVoiceAction(VoiceAction action) async {
  final d = action.data;
  final now = DateTime.now();
  final when = d['date'] == 'yesterday'
      ? now.subtract(const Duration(days: 1))
      : now;
  final date = '${when.year}-${two(when.month)}-${two(when.day)}';
  final common = {
    'date': date,
    'time': currentTime(),
    'addedBy': currentUserName(),
    'createdAt': now.toIso8601String(),
    'source': 'voice',
    'voiceText': '${d['heard'] ?? ''}',
  };
  final cow = '${d['cow'] ?? ''}'.trim();
  double amountOf(String key) =>
      d[key] is num ? (d[key] as num).toDouble() : 0.0;
  switch (action.kind) {
    case 'add_cow':
      final name = '${d['name'] ?? ''}'.trim();
      if (name.isEmpty) return null;
      final display = name[0].toUpperCase() + name.substring(1);
      final tamil = RegExp(r'[஀-௿]').hasMatch(display);
      final months = d['age_months'] is num
          ? (d['age_months'] as num).toInt()
          : -1;
      final breed = VoiceDialogue.breedName(d['breed'])?.$1 ?? 'Other';
      final amount = amountOf('amount');
      final purchased = d['source'] != 'added' || amount > 0;
      await Hive.box('animals').add({
        'type': 'cow',
        'name': display,
        'nameTamil': tamil ? display : '',
        'nameEnglish': tamil ? '' : display,
        'id': nextId('cow'),
        'breed': breed,
        'dob': '',
        'dobUnknown': true,
        'ageYears': months > 0 ? months ~/ 12 : 0,
        'ageMonths': months > 0 ? months % 12 : 0,
        'ageDays': 0,
        'ageUnknown': months <= 0,
        'status': 'Active',
        'mother': '',
        'arrivalDate': date,
        'arrivalUnknown': false,
        'source': purchased ? 'Purchased' : 'Existing',
        'purchaseAmount': amount,
        'gender': 'Female',
        'maleUse': '',
        'pregnancyStartDate': '',
        'pregnancyInjection': '',
        'milkingStopDate': '',
        'notes': d['photoWanted'] == true
            ? bi(
                'Added by voice; photo to add',
                'குரல் மூலம் சேர்க்கப்பட்டது; புகைப்படம் சேர்க்கவும்',
              )
            : bi('Added by voice', 'குரல் மூலம் சேர்க்கப்பட்டது'),
        'imageUrl': '',
        'imageData': '',
        'addedBy': currentUserName(),
      });
      if (purchased && amount > 0) {
        await Hive.box('purchase_records').add({
          'animal': display,
          'type': 'Cow Purchase',
          'amount': amount,
          'date': date,
          'notes': '',
          'addedBy': currentUserName(),
          'createdAt': now.toIso8601String(),
        });
      }
      return VoiceSavedAction(
        'add_cow',
        bi('New cow $display', 'புதிய மாடு $display'),
      );
    case 'expense':
      final amount = amountOf('amount');
      final name = '${d['name'] ?? ''}'.trim();
      if (amount <= 0 || name.isEmpty) return null;
      await Hive.box('expense_records').add({
        'category': 'Others',
        'name': name,
        'amount': amount,
        'notes': '',
        ...common,
      });
      return VoiceSavedAction('expense', '$name · ${money(amount)}');
    case 'stock_use':
    case 'stock_in':
      final item = d['item'] == 'vaikol' ? 'Vaikol' : 'Thavudu';
      final qty = amountOf('qty');
      if (qty <= 0) return null;
      final used = action.kind == 'stock_use';
      final spokenUnit = '${d['unit'] ?? ''}';
      await Hive.box('stock_records').add({
        'movement': used ? 'Usage' : 'Purchase',
        'item': item,
        if (used) 'target': 'Ranch',
        'quantityKg': qty,
        'unit': stockUnit(item),
        'amount': used ? 0.0 : amountOf('amount'),
        'notes': spokenUnit.isEmpty
            ? ''
            : bi('Said in $spokenUnit', '$spokenUnit என்று சொன்னது'),
        ...common,
      });
      return VoiceSavedAction(
        action.kind,
        '${ui(item)} ${_num(qty)} ${stockUnit(item)}',
      );
    case 'vet_visit':
    case 'vaccination':
    case 'symptom':
    case 'diagnosis':
    case 'calf_birth':
    case 'insemination':
    case 'pregnancy_confirmed':
      final problem = switch (action.kind) {
        'vet_visit' => bi('Doctor visit', 'டாக்டர் வருகை'),
        'vaccination' =>
          '${bi('Injection', 'ஊசி')}${d['vaccine'] == null ? '' : ' (${d['vaccine']})'}',
        'symptom' =>
          '${bi('Symptoms', 'அறிகுறிகள்')}: ${(d['symptoms'] as List?)?.join(', ') ?? ''}',
        'diagnosis' =>
          '${bi('Diagnosis', 'நோய் கண்டறிதல்')}: ${d['disease'] ?? ''}',
        'calf_birth' =>
          '${bi('Calf born', 'கன்று பிறந்தது')}${d['gender'] == null ? '' : ' (${d['gender']})'}',
        'insemination' => 'Pregnancy injection',
        _ => bi('Pregnancy confirmed', 'சினை உறுதி'),
      };
      await Hive.box('doctor_records').add({
        'cow': cow,
        'type': action.kind == 'insemination'
            ? 'Pregnancy Injection'
            : 'Problem / Treatment',
        'problem': problem,
        'injection': action.kind == 'vaccination'
            ? '${d['vaccine'] ?? ''}'
            : '',
        'cost': amountOf('fee'),
        'notes': bi('Recorded by voice', 'குரல் மூலம் பதிவு'),
        ...common,
      });
      final key = cow.isEmpty ? null : _animalKeyByName(cow);
      if (key != null &&
          (action.kind == 'insemination' ||
              action.kind == 'pregnancy_confirmed')) {
        final animal = asMap(Hive.box('animals').get(key));
        if (txt(animal, 'pregnancyStartDate').isEmpty) {
          await updateAnimalEntryFields(key, {
            'pregnancyStartDate': date,
            'milkingStopDate': '',
          });
        }
      }
      return VoiceSavedAction(
        action.kind,
        '${cow.isEmpty ? '' : '$cow · '}$problem',
      );
  }
  return null;
}
