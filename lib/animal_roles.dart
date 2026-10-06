part of 'main.dart';

// -----------------------------------------------------------------------------
//  Male animals: why a bull is raised decides what its profile tracks.
//  Milk and pregnancy never apply to a male. Work records are kept on the
//  animal itself in `workLog`, so they travel with backups and ranch sharing.
// -----------------------------------------------------------------------------

const maleUses = ['Breeding', 'Jallikattu', 'Cart'];

bool isMaleAnimal(Map<String, dynamic> a) =>
    txt(a, 'gender', 'Female') == 'Male';

String maleUseOf(Map<String, dynamic> a) =>
    maleUses.contains(txt(a, 'maleUse')) ? txt(a, 'maleUse') : '';

String maleUseLabel(String use) => switch (use) {
  'Breeding' => bi('Breeding', 'இனப்பெருக்கம்'),
  'Jallikattu' => bi('Jallikattu', 'ஜல்லிக்கட்டு'),
  'Cart' => bi('Cart & farm work', 'வண்டி & உழவு'),
  _ => bi('Not decided yet', 'இன்னும் முடிவு செய்யவில்லை'),
};

String maleUseDescription(String use) => switch (use) {
  'Breeding' => bi(
    'Services, conception results and fees',
    'கருவூட்டல், சினை முடிவு, கட்டணம்',
  ),
  'Jallikattu' => bi(
    'Training, events, prizes and fitness',
    'பயிற்சி, போட்டிகள், பரிசுகள், உடல் தகுதி',
  ),
  'Cart' => bi(
    'Work days, hours, earnings and rest',
    'வேலை நாட்கள், நேரம், வருமானம், ஓய்வு',
  ),
  _ => bi('Decide later from the profile', 'பின்னர் profile-ல் மாற்றலாம்'),
};

IconData maleUseIcon(String use) => switch (use) {
  'Breeding' => CupertinoIcons.heart_fill,
  'Jallikattu' => CupertinoIcons.rosette,
  'Cart' => Icons.agriculture_rounded,
  _ => CupertinoIcons.question_circle,
};

Color maleUseColor(String use) => switch (use) {
  'Breeding' => Ink.violet,
  'Jallikattu' => Ink.amber,
  'Cart' => Ink.green,
  _ => Ink.faint,
};

/// Rough ages (in months) at which a young bull usually starts each role.
int maleReadyMonths(String use) => switch (use) {
  'Breeding' => 30,
  'Jallikattu' => 36,
  'Cart' => 30,
  _ => 0,
};

int animalAgeMonths(Map<String, dynamic> a) {
  final dob = DateTime.tryParse(txt(a, 'dob'));
  if (dob != null) {
    final span = calendarSpan(dob, DateTime.now());
    return span.years * 12 + span.months;
  }
  return toInt(a['ageYears']) * 12 + toInt(a['ageMonths']);
}

List<Map<String, dynamic>> workLogOf(Map<String, dynamic> a) {
  final raw = a['workLog'];
  if (raw is! List) return <Map<String, dynamic>>[];
  final list = [
    for (final row in raw)
      if (row is Map) Map<String, dynamic>.from(row),
  ];
  list.sort((x, y) {
    final byDate = txt(y, 'date').compareTo(txt(x, 'date'));
    return byDate != 0 ? byDate : txt(y, 'id').compareTo(txt(x, 'id'));
  });
  return list;
}

Future<void> saveWorkLog(
  dynamic animalKey,
  List<Map<String, dynamic>> entries,
) => updateAnimalEntryFields(animalKey, {
  'workLog': [
    for (final e in entries) Map<String, dynamic>.from(e)..remove('_key'),
  ],
});

String workKindLabel(String kind) => switch (kind) {
  'service' => bi('Breeding service', 'கருவூட்டல்'),
  'training' => bi('Training', 'பயிற்சி'),
  'event' => bi('Event', 'போட்டி'),
  'work' => bi('Work', 'வேலை'),
  _ => kind,
};

const breedingResults = ['Pending', 'Confirmed', 'Repeat'];
String breedingResultLabel(String r) => switch (r) {
  'Confirmed' => bi('Pregnancy confirmed', 'சினை உறுதி'),
  'Repeat' => bi('Repeat (not conceived)', 'மீண்டும் (சினை பிடிக்கவில்லை)'),
  _ => bi('Waiting for result', 'முடிவுக்காகக் காத்திருக்கிறது'),
};
Color breedingResultColor(String r) => switch (r) {
  'Confirmed' => Ink.green,
  'Repeat' => Ink.red,
  _ => Ink.amber,
};

const trainingActivities = [
  'Running',
  'Swimming',
  'Mud horn practice',
  'Walking',
  'Vadivasal practice',
];
String trainingLabel(String a) => switch (a) {
  'Running' => bi('Running', 'ஓட்டம்'),
  'Swimming' => bi('Swimming', 'நீச்சல்'),
  'Mud horn practice' => bi('Mud horn practice', 'மண் குத்துதல்'),
  'Walking' => bi('Walking', 'நடைப் பயிற்சி'),
  'Vadivasal practice' => bi('Vadivasal practice', 'வாடிவாசல் பயிற்சி'),
  _ => a,
};

const eventResults = ['Won', 'Tamed', 'Participated'];
String eventResultLabel(String r) => switch (r) {
  'Won' => bi('Won · not tamed', 'வெற்றி · பிடிபடவில்லை'),
  'Tamed' => bi('Tamed', 'பிடிபட்டது'),
  _ => bi('Participated', 'பங்கேற்றது'),
};
Color eventResultColor(String r) => switch (r) {
  'Won' => Ink.green,
  'Tamed' => Ink.red,
  _ => Ink.blue,
};

const cartWorkTypes = ['Cart transport', 'Ploughing', 'Rekla race', 'Other'];
String cartWorkLabel(String w) => switch (w) {
  'Cart transport' => bi('Cart transport', 'வண்டி சவாரி / ஏற்றுமதி'),
  'Ploughing' => bi('Ploughing', 'உழவு'),
  'Rekla race' => bi('Rekla race', 'ரேக்ளா பந்தயம்'),
  _ => bi('Other work', 'மற்ற வேலை'),
};

bool _inThisMonth(Map<String, dynamic> e) =>
    txt(e, 'date').startsWith(thisMonth());

String _shortDate(String date) {
  final d = DateTime.tryParse(date);
  if (d == null) return bi('Not recorded', 'பதிவு இல்லை');
  final months = tamilUi
      ? const [
          'ஜன',
          'பிப்',
          'மார்',
          'ஏப்',
          'மே',
          'ஜூன்',
          'ஜூலை',
          'ஆக',
          'செப்',
          'அக்',
          'நவ',
          'டிச',
        ]
      : const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _daysAgo(String date) {
  final days = daysSince(date);
  if (DateTime.tryParse(date) == null) return bi('No record', 'பதிவு இல்லை');
  if (days <= 0) return bi('Today', 'இன்று');
  if (days == 1) return bi('Yesterday', 'நேற்று');
  return bi('$days days ago', '$days நாள் முன்');
}

/// One metric tile: (title, value, icon, colour).
typedef MaleMetric = (String, String, IconData, Color);

List<MaleMetric> maleMetrics(Map<String, dynamic> a) {
  final use = maleUseOf(a);
  final log = workLogOf(a);
  switch (use) {
    case 'Breeding':
      final services = log.where((e) => txt(e, 'kind') == 'service').toList();
      final confirmed = services
          .where((e) => txt(e, 'result') == 'Confirmed')
          .length;
      final decided = services
          .where((e) => txt(e, 'result') != 'Pending')
          .length;
      final income = services.fold<double>(0, (t, e) => t + numv(e, 'fee'));
      return [
        (
          bi('This month', 'இந்த மாதம்'),
          bi(
            '${services.where(_inThisMonth).length} services',
            '${services.where(_inThisMonth).length} முறை',
          ),
          CupertinoIcons.calendar,
          Ink.violet,
        ),
        (
          bi('Success rate', 'வெற்றி விகிதம்'),
          decided == 0 ? '—' : '${(confirmed * 100 / decided).round()}%',
          CupertinoIcons.checkmark_seal_fill,
          Ink.green,
        ),
        (
          bi('Pregnancies', 'சினை உறுதி'),
          '$confirmed / ${services.length}',
          CupertinoIcons.heart_fill,
          Ink.violetDeep,
        ),
        (
          bi('Service income', 'கட்டண வருமானம்'),
          money(income),
          CupertinoIcons.money_dollar_circle_fill,
          Ink.amber,
        ),
      ];
    case 'Jallikattu':
      final training = log.where((e) => txt(e, 'kind') == 'training');
      final events = log.where((e) => txt(e, 'kind') == 'event').toList();
      final minutes = training
          .where(_inThisMonth)
          .fold<double>(0, (t, e) => t + numv(e, 'minutes'));
      final wins = events.where((e) => txt(e, 'result') == 'Won').length;
      final prizes = events.fold<double>(0, (t, e) => t + numv(e, 'prize'));
      return [
        (
          bi('Training this month', 'இந்த மாதப் பயிற்சி'),
          bi(
            '${training.where(_inThisMonth).length} · ${minutes.toStringAsFixed(0)} min',
            '${training.where(_inThisMonth).length} · ${minutes.toStringAsFixed(0)} நிமி',
          ),
          Icons.directions_run_rounded,
          Ink.violet,
        ),
        (
          bi('Wins', 'வெற்றிகள்'),
          '$wins / ${events.length}',
          CupertinoIcons.rosette,
          Ink.amber,
        ),
        (
          bi('Prize value', 'பரிசு மதிப்பு'),
          money(prizes),
          CupertinoIcons.gift_fill,
          Ink.green,
        ),
        (
          bi('Fitness certificate', 'உடல் தகுதிச் சான்று'),
          _fitnessStatus(a),
          Icons.health_and_safety_rounded,
          _fitnessValid(a) ? Ink.green : Ink.red,
        ),
      ];
    case 'Cart':
      final work = log.where((e) => txt(e, 'kind') == 'work').toList();
      final month = work.where(_inThisMonth).toList();
      final days = month.map((e) => txt(e, 'date')).toSet().length;
      final hours = month.fold<double>(0, (t, e) => t + numv(e, 'hours'));
      final earned = month.fold<double>(0, (t, e) => t + numv(e, 'earnings'));
      final last = work.isEmpty ? '' : txt(work.first, 'date');
      return [
        (
          bi('Work days this month', 'இந்த மாத வேலை நாட்கள்'),
          bi('$days days', '$days நாள்'),
          CupertinoIcons.calendar,
          Ink.violet,
        ),
        (
          bi('Hours this month', 'இந்த மாத நேரம்'),
          bi(
            '${hours.toStringAsFixed(hours % 1 == 0 ? 0 : 1)} h',
            '${hours.toStringAsFixed(hours % 1 == 0 ? 0 : 1)} மணி',
          ),
          CupertinoIcons.clock,
          Ink.blue,
        ),
        (
          bi('Earned this month', 'இந்த மாத வருமானம்'),
          money(earned),
          CupertinoIcons.money_dollar_circle_fill,
          Ink.green,
        ),
        (
          bi('Resting', 'ஓய்வு'),
          last.isEmpty
              ? bi('No work yet', 'வேலை இல்லை')
              : bi('${daysSince(last)} days', '${daysSince(last)} நாள்'),
          CupertinoIcons.moon_fill,
          Ink.amber,
        ),
      ];
  }
  return const [];
}

bool _fitnessValid(Map<String, dynamic> a) {
  final until = DateTime.tryParse(txt(a, 'fitnessValidTill'));
  if (until == null) return false;
  final now = DateTime.now();
  return !until.isBefore(DateTime(now.year, now.month, now.day));
}

String _fitnessStatus(Map<String, dynamic> a) {
  final until = txt(a, 'fitnessValidTill');
  if (DateTime.tryParse(until) == null) return bi('Not added', 'சேர்க்கவில்லை');
  return _fitnessValid(a)
      ? bi('Valid · ${_shortDate(until)}', 'செல்லும் · ${_shortDate(until)}')
      : bi('Expired', 'காலாவதி');
}

/// Profile facts that sit under the metrics for each role.
List<(String, String, IconData, Color)> maleFacts(Map<String, dynamic> a) {
  final use = maleUseOf(a);
  final log = workLogOf(a);
  final facts = <(String, String, IconData, Color)>[];
  switch (use) {
    case 'Breeding':
      final services = log.where((e) => txt(e, 'kind') == 'service').toList();
      facts.add((
        bi('Last service', 'கடைசி கருவூட்டல்'),
        services.isEmpty
            ? bi('No service yet', 'இன்னும் இல்லை')
            : '${_shortDate(txt(services.first, 'date'))} · ${_daysAgo(txt(services.first, 'date'))}',
        CupertinoIcons.clock,
        Ink.violet,
      ));
      if (numv(a, 'serviceFee') > 0) {
        facts.add((
          bi('Service fee', 'கருவூட்டல் கட்டணம்'),
          money(numv(a, 'serviceFee')),
          CupertinoIcons.tag_fill,
          Ink.amber,
        ));
      }
      facts.add((
        bi('Outside cows', 'வெளி மாடுகள்'),
        a['outsideService'] == true
            ? bi('Available for service', 'கருவூட்டலுக்குக் கிடைக்கும்')
            : bi('Only for this ranch', 'இந்தத் தொழுவத்திற்கு மட்டும்'),
        CupertinoIcons.hand_raised_fill,
        Ink.blue,
      ));
    case 'Jallikattu':
      final events = log.where((e) => txt(e, 'kind') == 'event').toList();
      final training = log.where((e) => txt(e, 'kind') == 'training').toList();
      if (txt(a, 'trainerName').isNotEmpty) {
        facts.add((
          bi('Trainer', 'பயிற்சியாளர்'),
          txt(a, 'trainerName'),
          Icons.sports_rounded,
          Ink.violet,
        ));
      }
      facts.add((
        bi('Last training', 'கடைசிப் பயிற்சி'),
        training.isEmpty
            ? bi('No training yet', 'இன்னும் இல்லை')
            : '${trainingLabel(txt(training.first, 'activity'))} · ${_daysAgo(txt(training.first, 'date'))}',
        Icons.directions_run_rounded,
        Ink.blue,
      ));
      facts.add((
        bi('Last event', 'கடைசிப் போட்டி'),
        events.isEmpty
            ? bi('No event yet', 'இன்னும் இல்லை')
            : '${txt(events.first, 'place', workKindLabel('event'))} · ${eventResultLabel(txt(events.first, 'result'))}',
        Icons.stadium_rounded,
        Ink.amber,
      ));
    case 'Cart':
      if (txt(a, 'pairPartner').isNotEmpty) {
        facts.add((
          bi('Pair partner', 'ஜோடி மாடு'),
          localizedAnimalLabel(txt(a, 'pairPartner')),
          CupertinoIcons.link,
          Ink.violet,
        ));
      }
      if (numv(a, 'dailyRate') > 0) {
        facts.add((
          bi('Usual rate per day', 'ஒரு நாள் கூலி'),
          money(numv(a, 'dailyRate')),
          CupertinoIcons.tag_fill,
          Ink.amber,
        ));
      }
      final work = log.where((e) => txt(e, 'kind') == 'work').toList();
      facts.add((
        bi('Last work', 'கடைசி வேலை'),
        work.isEmpty
            ? bi('No work yet', 'இன்னும் இல்லை')
            : '${cartWorkLabel(txt(work.first, 'workType'))} · ${_daysAgo(txt(work.first, 'date'))}',
        Icons.agriculture_rounded,
        Ink.green,
      ));
  }
  return facts;
}

/// Young bulls show how far they are from starting their role.
String? maleReadiness(Map<String, dynamic> a) {
  if (txt(a, 'type') != 'calf') return null;
  final use = maleUseOf(a);
  final ready = maleReadyMonths(use);
  if (ready == 0) return null;
  final age = animalAgeMonths(a);
  if (age <= 0) return null;
  final left = ready - age;
  if (left <= 0) {
    return bi(
      'Old enough to start ${maleUseLabel(use).toLowerCase()}',
      '${maleUseLabel(use)} தொடங்கும் வயது வந்துவிட்டது',
    );
  }
  return bi(
    'About $left months until ${maleUseLabel(use).toLowerCase()} age',
    '${maleUseLabel(use)} வயதுக்கு இன்னும் சுமார் $left மாதம்',
  );
}

// --- entry description -------------------------------------------------------

String workEntryTitle(Map<String, dynamic> e) => switch (txt(e, 'kind')) {
  'service' =>
    txt(e, 'cow').isNotEmpty
        ? '${workKindLabel('service')} · ${localizedAnimalLabel(txt(e, 'cow'))}'
        : workKindLabel('service'),
  'training' => trainingLabel(txt(e, 'activity')),
  'event' => txt(e, 'place', workKindLabel('event')),
  'work' => cartWorkLabel(txt(e, 'workType')),
  _ => workKindLabel(txt(e, 'kind')),
};

String workEntryDetail(Map<String, dynamic> e) {
  final parts = <String>[_shortDate(txt(e, 'date'))];
  switch (txt(e, 'kind')) {
    case 'service':
      if (txt(e, 'owner').isNotEmpty) parts.add(txt(e, 'owner'));
      parts.add(breedingResultLabel(txt(e, 'result')));
      if (numv(e, 'fee') > 0) parts.add(money(numv(e, 'fee')));
    case 'training':
      if (numv(e, 'minutes') > 0) {
        parts.add(
          bi(
            '${numv(e, 'minutes').toStringAsFixed(0)} min',
            '${numv(e, 'minutes').toStringAsFixed(0)} நிமிடம்',
          ),
        );
      }
    case 'event':
      parts.add(eventResultLabel(txt(e, 'result')));
      if (txt(e, 'prizeName').isNotEmpty) parts.add(txt(e, 'prizeName'));
      if (numv(e, 'prize') > 0) parts.add(money(numv(e, 'prize')));
    case 'work':
      if (numv(e, 'hours') > 0) {
        parts.add(
          bi('${_trim(numv(e, 'hours'))} h', '${_trim(numv(e, 'hours'))} மணி'),
        );
      }
      if (numv(e, 'earnings') > 0) parts.add(money(numv(e, 'earnings')));
  }
  if (txt(e, 'notes').isNotEmpty) parts.add(txt(e, 'notes'));
  return parts.join(' · ');
}

String _trim(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

Color workEntryColor(Map<String, dynamic> e) => switch (txt(e, 'kind')) {
  'service' => breedingResultColor(txt(e, 'result')),
  'event' => eventResultColor(txt(e, 'result')),
  'training' => Ink.violet,
  _ => Ink.green,
};

IconData workEntryIcon(Map<String, dynamic> e) => switch (txt(e, 'kind')) {
  'service' => CupertinoIcons.heart_fill,
  'training' => Icons.directions_run_rounded,
  'event' => CupertinoIcons.rosette,
  _ => Icons.agriculture_rounded,
};

// --- widgets -----------------------------------------------------------------

/// Large choice cards used on the add form: why is this bull raised?
class MaleUsePicker extends StatelessWidget {
  final String value;
  final bool calf;
  final ValueChanged<String> onChanged;

  const MaleUsePicker({
    super.key,
    required this.value,
    required this.calf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [...maleUses, if (calf) ''];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Gold.s5, bottom: Gold.s8),
          child: AppText(
            calf
                ? bi(
                    'What are you raising this calf for?',
                    'இந்தக் காளைக் கன்றை எதற்காக வளர்க்கிறீர்கள்?',
                  )
                : bi(
                    'What do you use this bull for?',
                    'இந்தக் காளையை எதற்காகப் பயன்படுத்துகிறீர்கள்?',
                  ),
            style: TextStyle(
              color: Ink.navy,
              fontSize: Gold.t16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final use in options)
          Padding(
            padding: const EdgeInsets.only(bottom: Gold.s8),
            child: _UseTile(
              use: use,
              selected: value == use,
              onTap: () => onChanged(use),
            ),
          ),
      ],
    );
  }
}

class _UseTile extends StatelessWidget {
  final String use;
  final bool selected;
  final VoidCallback onTap;
  const _UseTile({
    required this.use,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Ink.navy;
    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        radius: Gold.r21,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Gold.base,
          curve: Gold.ease,
          padding: const EdgeInsets.symmetric(
            horizontal: Gold.s16,
            vertical: Gold.s13,
          ),
          decoration: ShapeDecoration(
            shape: SquircleBorder(
              radius: Gold.r21,
              side: BorderSide(color: selected ? Ink.tint : Colors.transparent),
            ),
            color: selected ? Ink.tint : Ink.surface.withValues(alpha: .52),
          ),
          child: Row(
            children: [
              Container(
                width: Gold.s34 + Gold.s5,
                height: Gold.s34 + Gold.s5,
                decoration: ShapeDecoration(
                  shape: const SquircleBorder(radius: Gold.r13),
                  color: selected
                      ? Colors.white.withValues(alpha: .18)
                      : maleUseColor(use).withValues(alpha: .14),
                ),
                child: Icon(
                  maleUseIcon(use),
                  size: Gold.t21,
                  color: selected ? Colors.white : maleUseColor(use),
                ),
              ),
              const SizedBox(width: Gold.s13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      maleUseLabel(use),
                      style: TextStyle(
                        color: fg,
                        fontSize: Gold.t16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Gold.s2),
                    Text(
                      maleUseDescription(use),
                      style: TextStyle(
                        color: selected
                            ? Colors.white.withValues(alpha: .82)
                            : Ink.muted,
                        fontSize: Gold.t11,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The role tab on a male profile: facts, history and the add action.
class MaleRolePanel extends StatelessWidget {
  final dynamic animalKey;
  final Map<String, dynamic> animal;
  const MaleRolePanel({
    super.key,
    required this.animalKey,
    required this.animal,
  });

  @override
  Widget build(BuildContext context) {
    final use = maleUseOf(animal);
    final log = workLogOf(animal);
    final readiness = maleReadiness(animal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoleBanner(use: use),
        if (readiness != null) ...[
          const SizedBox(height: Gold.s13),
          InfoRow(
            title: bi('Growth', 'வளர்ச்சி'),
            value: readiness,
            icon: CupertinoIcons.arrow_up_right,
            color: Ink.green,
          ),
        ],
        for (final fact in maleFacts(animal)) ...[
          const SizedBox(height: Gold.s13),
          InfoRow(
            title: fact.$1,
            value: fact.$2,
            icon: fact.$3,
            color: fact.$4,
          ),
        ],
        const SizedBox(height: Gold.s16),
        if (use.isNotEmpty && canRecordEntries) ...[
          LiquidButton(
            label: switch (use) {
              'Breeding' => bi('Record service', 'கருவூட்டலைப் பதிவு செய்'),
              'Jallikattu' => bi(
                'Record training or event',
                'பயிற்சி / போட்டியைப் பதிவு செய்',
              ),
              _ => bi('Record work', 'வேலையைப் பதிவு செய்'),
            },
            icon: CupertinoIcons.add,
            onPressed: () => push(
              context,
              MaleWorkEntryScreen(animalKey: animalKey, use: use),
            ),
          ),
          const SizedBox(height: Gold.s16),
        ],
        panel(
          bi('History', 'வரலாறு'),
          use.isEmpty
              ? bi(
                  'Choose what this bull is raised for from Edit details.',
                  '"விவரங்களைத் திருத்து"-ல் இந்தக் காளையின் பயன்பாட்டைத் தேர்வு செய்யவும்.',
                )
              : bi('No records yet.', 'இன்னும் பதிவுகள் இல்லை.'),
          [
            for (final e in log.take(40))
              _WorkLine(entry: e, animalKey: animalKey, animal: animal),
          ],
        ),
      ],
    );
  }
}

class _RoleBanner extends StatelessWidget {
  final String use;
  const _RoleBanner({required this.use});

  @override
  Widget build(BuildContext context) => Glass(
    radius: Gold.r27,
    padding: const EdgeInsets.all(Gold.s16),
    elevation: 0.8,
    child: Row(
      children: [
        Container(
          width: Gold.s55 - Gold.s8,
          height: Gold.s55 - Gold.s8,
          decoration: ShapeDecoration(
            shape: const SquircleBorder(radius: Gold.r21),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                maleUseColor(use),
                Color.lerp(maleUseColor(use), Ink.navy, .28)!,
              ],
            ),
          ),
          child: Icon(maleUseIcon(use), color: Colors.white, size: Gold.t27),
        ),
        const SizedBox(width: Gold.s13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                maleUseLabel(use),
                style: TextStyle(
                  color: Ink.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Gold.s2),
              Text(
                maleUseDescription(use),
                style: TextStyle(
                  color: Ink.muted,
                  fontSize: Gold.t13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WorkLine extends StatelessWidget {
  final Map<String, dynamic> entry;
  final dynamic animalKey;
  final Map<String, dynamic> animal;
  const _WorkLine({
    required this.entry,
    required this.animalKey,
    required this.animal,
  });

  Future<void> _actions(BuildContext context) async {
    final isService = txt(entry, 'kind') == 'service';
    final choice = await showAppleSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isService && canRecordEntries)
              for (final r in breedingResults)
                ListTile(
                  leading: Icon(
                    CupertinoIcons.circle_fill,
                    size: 14,
                    color: breedingResultColor(r),
                  ),
                  title: Text(breedingResultLabel(r)),
                  selected: txt(entry, 'result') == r,
                  selectedColor: Ink.violetDeep,
                  onTap: () => Navigator.pop(sheet, 'result:$r'),
                ),
            if (canEditAnimals)
              ListTile(
                leading: Icon(CupertinoIcons.trash, color: Ink.red),
                title: Text(
                  bi('Delete record', 'பதிவை நீக்கு'),
                  style: TextStyle(color: Ink.red),
                ),
                onTap: () => Navigator.pop(sheet, 'delete'),
              ),
            const SizedBox(height: Gold.s8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final log = workLogOf(animal);
    final id = txt(entry, 'id');
    try {
      if (choice == 'delete') {
        log.removeWhere((e) => txt(e, 'id') == id);
      } else if (choice.startsWith('result:')) {
        final result = choice.substring(7);
        for (final e in log) {
          if (txt(e, 'id') == id) e['result'] = result;
        }
      }
      await saveWorkLog(animalKey, log);
      AutoSyncService.scheduleSync(reason: 'bull record updated');
    } catch (_) {
      if (context.mounted) {
        snack(
          context,
          bi(
            'Could not update. Try again',
            'மாற்ற முடியவில்லை. மீண்டும் முயற்சிக்கவும்',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(Gold.r13),
    onTap: canRecordEntries ? () => _actions(context) : null,
    child: _RecordLine(
      icon: workEntryIcon(entry),
      color: workEntryColor(entry),
      title: workEntryTitle(entry),
      subtitle: workEntryDetail(entry),
    ),
  );
}

/// Adds one breeding service, training session, event or work day.
class MaleWorkEntryScreen extends StatefulWidget {
  final dynamic animalKey;
  final String use;
  const MaleWorkEntryScreen({
    super.key,
    required this.animalKey,
    required this.use,
  });

  @override
  State<MaleWorkEntryScreen> createState() => _MaleWorkEntryScreenState();
}

class _MaleWorkEntryScreenState extends State<MaleWorkEntryScreen> {
  final _date = TextEditingController(text: todayDate());
  final _owner = TextEditingController();
  final _fee = TextEditingController();
  final _minutes = TextEditingController();
  final _place = TextEditingController();
  final _prizeName = TextEditingController();
  final _prize = TextEditingController();
  final _hours = TextEditingController();
  final _earnings = TextEditingController();
  final _notes = TextEditingController();
  int _jalliMode = 0;
  bool _outsideCow = false;
  String _cow = '';
  String _result = 'Pending';
  String _eventResult = 'Participated';
  String _activity = trainingActivities.first;
  String _workType = cartWorkTypes.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw = Hive.box('animals').get(widget.animalKey);
    final a = raw == null ? <String, dynamic>{} : asMap(raw);
    if (numv(a, 'serviceFee') > 0) {
      _fee.text = numv(a, 'serviceFee').toStringAsFixed(0);
    }
    if (numv(a, 'dailyRate') > 0) {
      _earnings.text = numv(a, 'dailyRate').toStringAsFixed(0);
    }
    final cows = cowNames();
    _cow = cows.isEmpty ? '' : cows.first;
    _outsideCow = cows.isEmpty;
  }

  @override
  void dispose() {
    for (final c in [
      _date,
      _owner,
      _fee,
      _minutes,
      _place,
      _prizeName,
      _prize,
      _hours,
      _earnings,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!canRecordEntries) {
      snack(
        context,
        bi(
          'Your ranch role does not allow this entry',
          'உங்கள் பொறுப்புக்கு இந்தப் பதிவு அனுமதி இல்லை',
        ),
      );
      return;
    }
    final raw = Hive.box('animals').get(widget.animalKey);
    if (raw == null) {
      snack(context, 'Animal not found');
      return;
    }
    final entry = <String, dynamic>{
      'id': 'w${DateTime.now().microsecondsSinceEpoch}',
      'date': _date.text.trim().isEmpty ? todayDate() : _date.text.trim(),
      'notes': _notes.text.trim(),
      'addedBy': currentUserName(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    switch (widget.use) {
      case 'Breeding':
        if (_outsideCow && _owner.text.trim().isEmpty) {
          snack(
            context,
            bi(
              'Enter the cow owner name',
              'மாட்டின் உரிமையாளர் பெயரை எழுதவும்',
            ),
          );
          return;
        }
        entry.addAll({
          'kind': 'service',
          'cow': _outsideCow ? '' : _cow,
          'owner': _outsideCow ? _owner.text.trim() : '',
          'fee': toDouble(_fee.text),
          'result': _result,
        });
      case 'Jallikattu':
        if (_jalliMode == 0) {
          entry.addAll({
            'kind': 'training',
            'activity': _activity,
            'minutes': toDouble(_minutes.text),
          });
        } else {
          if (_place.text.trim().isEmpty) {
            snack(
              context,
              bi(
                'Enter the event name or place',
                'போட்டி நடந்த ஊர் / பெயரை எழுதவும்',
              ),
            );
            return;
          }
          entry.addAll({
            'kind': 'event',
            'place': _place.text.trim(),
            'result': _eventResult,
            'prizeName': _prizeName.text.trim(),
            'prize': toDouble(_prize.text),
          });
        }
      default:
        entry.addAll({
          'kind': 'work',
          'workType': _workType,
          'hours': toDouble(_hours.text),
          'earnings': toDouble(_earnings.text),
        });
    }
    setState(() => _saving = true);
    try {
      final log = workLogOf(asMap(raw))..insert(0, entry);
      await saveWorkLog(widget.animalKey, log);
      AutoSyncService.scheduleSync(reason: 'bull record saved');
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        snack(
          context,
          bi(
            'Could not save. Try again',
            'சேமிக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _gap() => const SizedBox(height: Gold.s13);

  Widget _money(TextEditingController c, String label) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: fieldStyle(label, icon: CupertinoIcons.money_dollar_circle),
  );

  Widget _choices(
    List<String> values,
    String selected,
    String Function(String) label,
    ValueChanged<String> onPick,
  ) => Wrap(
    spacing: Gold.s8,
    runSpacing: Gold.s8,
    children: [
      for (final v in values)
        ChoiceChip(
          showCheckmark: false,
          selected: v == selected,
          selectedColor: Ink.tint,
          label: Text(
            label(v),
            style: TextStyle(
              color: v == selected ? Colors.white : Ink.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          onSelected: (_) => setState(() => onPick(v)),
        ),
    ],
  );

  List<Widget> _breeding() {
    final cows = cowNames();
    return [
      Glass(
        radius: Gold.r21,
        blur: Gold.s13,
        padding: const EdgeInsets.all(Gold.s5),
        elevation: 0.62,
        child: LiquidSegmentBar(
          labels: [bi('Our cow', 'நம் மாடு'), bi('Outside cow', 'வெளி மாடு')],
          index: _outsideCow ? 1 : 0,
          onChanged: (i) => setState(() => _outsideCow = i == 1),
        ),
      ),
      _gap(),
      if (!_outsideCow)
        cows.isEmpty
            ? EmptyNote(
                icon: CupertinoIcons.info_circle,
                title: bi('No female cows', 'பசு மாடுகள் இல்லை'),
                message: bi(
                  'Choose Outside cow to record a service for another ranch.',
                  'வேறு தொழுவ மாட்டுக்கு "வெளி மாடு" தேர்வு செய்யவும்.',
                ),
              )
            : DropdownButtonFormField<String>(
                initialValue: cows.contains(_cow) ? _cow : cows.first,
                isExpanded: true,
                borderRadius: BorderRadius.circular(Gold.r21),
                decoration: fieldStyle(
                  bi('Cow', 'மாடு'),
                  icon: Icons.pets_rounded,
                ),
                items: [
                  for (final n in cows)
                    DropdownMenuItem(value: n, child: AppText(n)),
                ],
                onChanged: (v) => setState(() => _cow = v ?? _cow),
              )
      else
        TextField(
          controller: _owner,
          textCapitalization: TextCapitalization.words,
          decoration: fieldStyle(
            bi('Cow owner name', 'மாட்டின் உரிமையாளர் பெயர்'),
            icon: CupertinoIcons.person,
          ),
        ),
      _gap(),
      _money(_fee, bi('Service fee (optional)', 'கட்டணம் (விருப்பம்)')),
      _gap(),
      Padding(
        padding: const EdgeInsets.only(left: Gold.s5, bottom: Gold.s8),
        child: Text(
          bi('Result', 'முடிவு'),
          style: TextStyle(color: Ink.muted, fontWeight: FontWeight.w700),
        ),
      ),
      _choices(
        breedingResults,
        _result,
        breedingResultLabel,
        (v) => _result = v,
      ),
    ];
  }

  List<Widget> _jallikattu() => [
    Glass(
      radius: Gold.r21,
      blur: Gold.s13,
      padding: const EdgeInsets.all(Gold.s5),
      elevation: 0.62,
      child: LiquidSegmentBar(
        labels: [workKindLabel('training'), workKindLabel('event')],
        index: _jalliMode,
        onChanged: (i) => setState(() => _jalliMode = i),
      ),
    ),
    _gap(),
    if (_jalliMode == 0) ...[
      _choices(
        trainingActivities,
        _activity,
        trainingLabel,
        (v) => _activity = v,
      ),
      _gap(),
      TextField(
        controller: _minutes,
        keyboardType: TextInputType.number,
        decoration: fieldStyle(
          bi('Minutes', 'நிமிடங்கள்'),
          icon: CupertinoIcons.timer,
        ),
      ),
    ] else ...[
      TextField(
        controller: _place,
        textCapitalization: TextCapitalization.words,
        decoration: fieldStyle(
          bi('Event / place', 'போட்டி / ஊர்'),
          icon: Icons.stadium_outlined,
        ),
      ),
      _gap(),
      _choices(
        eventResults,
        _eventResult,
        eventResultLabel,
        (v) => _eventResult = v,
      ),
      _gap(),
      TextField(
        controller: _prizeName,
        textCapitalization: TextCapitalization.sentences,
        decoration: fieldStyle(
          bi('Prize (optional)', 'பரிசு (விருப்பம்)'),
          icon: CupertinoIcons.gift,
        ),
      ),
      _gap(),
      _money(
        _prize,
        bi('Prize value (optional)', 'பரிசின் மதிப்பு (விருப்பம்)'),
      ),
    ],
  ];

  List<Widget> _cart() => [
    _choices(cartWorkTypes, _workType, cartWorkLabel, (v) => _workType = v),
    _gap(),
    TextField(
      controller: _hours,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: fieldStyle(
        bi('Hours worked', 'வேலை செய்த நேரம் (மணி)'),
        icon: CupertinoIcons.clock,
      ),
    ),
    _gap(),
    _money(_earnings, bi('Earnings (optional)', 'வருமானம் (விருப்பம்)')),
  ];

  @override
  Widget build(BuildContext context) {
    final raw = Hive.box('animals').get(widget.animalKey);
    final a = raw == null ? <String, dynamic>{} : asMap(raw);
    return FormPage(
      title: switch (widget.use) {
        'Breeding' => bi('Breeding service', 'கருவூட்டல் பதிவு'),
        'Jallikattu' => bi('Jallikattu record', 'ஜல்லிக்கட்டுப் பதிவு'),
        _ => bi('Work record', 'வேலைப் பதிவு'),
      },
      children: [
        Glass(
          radius: Gold.r21,
          padding: const EdgeInsets.all(Gold.s16),
          elevation: 0.62,
          child: Row(
            children: [
              Icon(maleUseIcon(widget.use), color: maleUseColor(widget.use)),
              const SizedBox(width: Gold.s13),
              Expanded(
                child: AppText(
                  txt(a, 'name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                    fontSize: Gold.t16,
                  ),
                ),
              ),
              AppText(
                '#${txt(a, 'id')}',
                style: TextStyle(
                  color: Ink.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: Gold.t11,
                ),
              ),
            ],
          ),
        ),
        _gap(),
        DateField(
          controller: _date,
          label: bi('Date', 'தேதி'),
          onChanged: () => setState(() {}),
        ),
        _gap(),
        ...switch (widget.use) {
          'Breeding' => _breeding(),
          'Jallikattu' => _jallikattu(),
          _ => _cart(),
        },
        _gap(),
        TextField(
          controller: _notes,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldStyle(
            bi('Notes (optional)', 'குறிப்பு (விருப்பம்)'),
          ),
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: bi('Save', 'சேமி'),
          icon: CupertinoIcons.checkmark_alt,
          busy: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// A labelled field with an iOS-style "Unknown" switch beside its heading.
class UnknownToggleField extends StatelessWidget {
  final String label;
  final bool unknown;
  final ValueChanged<bool> onUnknownChanged;
  final Widget child;

  const UnknownToggleField({
    super.key,
    required this.label,
    required this.unknown,
    required this.onUnknownChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Gold.s5, 0, 0, Gold.s5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Ink.navy,
                  fontWeight: FontWeight.w700,
                  fontSize: Gold.t13,
                ),
              ),
            ),
            Text(
              bi('Unknown', 'தெரியாது'),
              style: TextStyle(
                color: unknown ? Ink.violetDeep : Ink.muted,
                fontWeight: FontWeight.w700,
                fontSize: Gold.t13,
              ),
            ),
            const SizedBox(width: Gold.s5),
            Transform.scale(
              scale: .82,
              child: CupertinoSwitch(
                value: unknown,
                activeTrackColor: Ink.tint,
                onChanged: onUnknownChanged,
              ),
            ),
          ],
        ),
      ),
      AnimatedSize(
        duration: Gold.base,
        curve: Gold.ease,
        alignment: Alignment.topCenter,
        child: unknown
            ? Glass(
                radius: Gold.r21,
                padding: const EdgeInsets.symmetric(
                  horizontal: Gold.s16,
                  vertical: Gold.s16,
                ),
                elevation: 0.4,
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.question_circle,
                      color: Ink.faint,
                      size: Gold.t21,
                    ),
                    const SizedBox(width: Gold.s13),
                    Expanded(
                      child: Text(
                        bi(
                          'Marked as unknown · you can add it later',
                          'தெரியாது எனக் குறிக்கப்பட்டது · பின்னர் சேர்க்கலாம்',
                        ),
                        style: TextStyle(
                          color: Ink.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: Gold.t13,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : child,
      ),
    ],
  );
}
