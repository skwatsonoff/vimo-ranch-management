part of 'main.dart';

String bi(String en, String ta) => tamilUi ? ta : en;
const businessTabs = [
  'Ranch',
  'Vendor',
  'Reports',
  'Social',
  'Chat',
  'Profile',
];
const workspaceKinds = ['Ranch', 'Vendor', 'Market'];

/// The bottom bar always has exactly four destinations.
const navigationSlots = 4;

String get _profileKey =>
    firebaseReady ? FirebaseAuth.instance.currentUser?.uid ?? 'local' : 'local';
Map<String, dynamic> get purposeProfile =>
    asMap(asMap(settingValue('purposeProfiles', {}))[_profileKey] ?? {});
bool get purposeChosen => workspaceKinds.contains(purposeProfile['purpose']);
String get appPurpose => txt(purposeProfile, 'purpose', 'Ranch');

/// The workspace that pairs with a purpose in the older two-mode settings.
String _legacySecondary(String purpose) =>
    purpose == 'Ranch' ? 'Vendor' : 'Ranch';

List<String> _cleanWorkspaces(String purpose, Iterable<dynamic> raw) {
  final set = {purpose, ...raw.whereType<String>()};
  return [
    for (final w in workspaceKinds)
      if (set.contains(w)) w,
  ];
}

/// Workspaces switched on for this account. The chosen purpose is always on.
List<String> get enabledWorkspaces {
  final raw = purposeProfile['workspaces'];
  if (raw is List) return _cleanWorkspaces(appPurpose, raw);
  return _cleanWorkspaces(appPurpose, [
    if (purposeProfile['secondaryEnabled'] == true)
      _legacySecondary(appPurpose),
  ]);
}

bool get secondaryWorkspaceEnabled => enabledWorkspaces.length > 1;
bool workspaceEnabled(String kind) => enabledWorkspaces.contains(kind);

/// True when this account uses the Ranch workspace, before or after sign-in.
bool get accountWantsRanch => purposeChosen
    ? workspaceEnabled('Ranch')
    : settingText('introPurpose', 'Ranch') == 'Ranch';

List<String> workspaceTabs(String kind) => switch (kind) {
  'Vendor' => const ['Vendor', 'Reports', 'Social', 'Chat'],
  'Market' => const ['Social', 'Reports', 'Chat', 'Profile'],
  _ => const ['Ranch', 'Social', 'Chat', 'Profile'],
};

/// Every destination the enabled workspaces offer, in a stable order.
List<String> availableTabs(List<String> workspaces) {
  final set = {for (final w in workspaces) ...workspaceTabs(w)};
  return [
    for (final t in businessTabs)
      if (set.contains(t)) t,
  ];
}

List<String> _workspacesFor(
  String purpose,
  bool secondaryEnabled,
  List<String>? workspaces,
) => workspaces != null
    ? _cleanWorkspaces(purpose, workspaces)
    : _cleanWorkspaces(purpose, [
        if (secondaryEnabled) _legacySecondary(purpose),
      ]);

List<String> defaultNavigation(
  String purpose, {
  bool secondaryEnabled = false,
  List<String>? workspaces,
}) {
  final list = _workspacesFor(purpose, secondaryEnabled, workspaces);
  if (list.length == 1) return List.of(workspaceTabs(purpose));
  // Home of the chosen purpose first, then the other workspaces' homes, then
  // the purpose's own remaining destinations.
  final order = <String>[];
  void add(String tab) {
    if (order.length < navigationSlots && !order.contains(tab)) order.add(tab);
  }

  add(workspaceTabs(purpose).first);
  for (final w in list) {
    if (w != 'Market') add(workspaceTabs(w).first);
  }
  for (final t in workspaceTabs(purpose)) {
    add(t);
  }
  for (final t in availableTabs(list)) {
    add(t);
  }
  return order;
}

bool _validOrder(List<dynamic> order, List<String> available) =>
    order.length == navigationSlots &&
    order.toSet().length == navigationSlots &&
    order.every(available.contains);

List<String> navigationOrder() {
  final workspaces = enabledWorkspaces;
  final available = availableTabs(workspaces);
  final raw = purposeProfile['order'];
  if (raw is List && _validOrder(raw, available)) {
    // Older single-workspace saves must not quietly surface another workspace.
    final legacy = purposeProfile['workspaces'] is! List;
    final foreign = raw.any((t) => !workspaceTabs(appPurpose).contains(t));
    if (!(legacy && !secondaryWorkspaceEnabled && foreign)) {
      return raw.cast<String>();
    }
  }
  return defaultNavigation(appPurpose, workspaces: workspaces);
}

Future<void> savePurpose(
  String purpose,
  List<String> order, {
  bool secondaryEnabled = false,
  List<String>? workspaces,
}) async {
  if (!workspaceKinds.contains(purpose)) {
    throw ArgumentError('Invalid preferences');
  }
  final list = _workspacesFor(purpose, secondaryEnabled, workspaces);
  if (!_validOrder(order, availableTabs(list))) {
    throw ArgumentError('Invalid preferences');
  }
  await setSetting('purposeProfiles', {
    ...asMap(settingValue('purposeProfiles', {})),
    _profileKey: {
      'purpose': purpose,
      'order': List<String>.of(order),
      'workspaces': list,
      'secondaryEnabled': list.length > 1,
    },
  });
}

String workspaceTitle(String kind) => switch (kind) {
  'Vendor' => bi('Vendor', 'பால் வியாபாரம்'),
  'Market' => bi('Market', 'சந்தை'),
  _ => bi('Ranch', 'தொழுவம்'),
};

String workspaceSubtitle(String kind) => switch (kind) {
  'Vendor' => bi(
    'Buy milk and deliver to homes and shops',
    'பால் வாங்கி வீடுகளுக்கும் கடைகளுக்கும் விற்பனை',
  ),
  'Market' => bi(
    'People, posts, chats and reports',
    'மக்கள், பதிவுகள், சாட், அறிக்கைகள்',
  ),
  _ => bi(
    'Care for your cows and manage the ranch',
    'மாடுகளைப் பராமரித்துத் தொழுவத்தை நிர்வகிக்கலாம்',
  ),
};

Widget workspaceIcon(String kind, {required Color color, double size = 26}) =>
    switch (kind) {
      'Vendor' => MilkVendorIcon(size: size + 6, color: color),
      'Market' => Icon(CupertinoIcons.bag_fill, color: color, size: size),
      _ => Icon(CupertinoIcons.house_fill, color: color, size: size),
    };

String navLabel(String tab) => switch (tab) {
  'Ranch' => bi('Ranch', 'தொழுவம்'),
  'Vendor' => bi('Vendor', 'வியாபாரம்'),
  'Reports' => bi('Reports', 'ரிப்போர்ட்'),
  'Social' => bi('Social', 'சமூகம்'),
  'Chat' => bi('Chat', 'சாட்'),
  'Profile' => bi('Profile', 'ப்ரொஃபைல்'),
  _ => tab,
};

IconData navIcon(String tab) => switch (tab) {
  'Ranch' => CupertinoIcons.house_fill,
  'Vendor' => CupertinoIcons.drop_fill,
  'Reports' => Icons.analytics_rounded,
  'Social' => CupertinoIcons.globe,
  'Chat' => CupertinoIcons.chat_bubble_2_fill,
  _ => CupertinoIcons.person_fill,
};

class PreferencesScreen extends StatefulWidget {
  final bool onboarding;
  const PreferencesScreen({super.key, this.onboarding = false});
  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late String _purpose = purposeChosen
      ? appPurpose
      : settingText('introPurpose', 'Ranch');
  late List<String> _workspaces = purposeChosen
      ? enabledWorkspaces
      : [_purpose];
  late List<String> _order = purposeChosen
      ? navigationOrder()
      : defaultNavigation(_purpose);
  bool _saving = false;

  List<String> get _extras => [
    for (final t in availableTabs(_workspaces))
      if (!_order.contains(t)) t,
  ];

  Future<void> _persist() async {
    try {
      await savePurpose(_purpose, _order, workspaces: _workspaces);
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    }
  }

  Future<void> _toggleWorkspace(String kind, bool on) async {
    if (!on && _workspaces.length == 1) {
      snack(
        context,
        bi(
          'Keep at least one workspace on',
          'குறைந்தது ஒரு பகுதியாவது இயக்கத்தில் இருக்க வேண்டும்',
        ),
      );
      return;
    }
    final next = [
      for (final w in workspaceKinds)
        if (w == kind ? on : _workspaces.contains(w)) w,
    ];
    final purpose = next.contains(_purpose) ? _purpose : next.first;
    final available = availableTabs(next);
    final fallback = defaultNavigation(purpose, workspaces: next);
    final order = <String>[
      for (final t in _order)
        if (available.contains(t)) t,
    ];
    for (final t in [...fallback, ...available]) {
      if (order.length >= navigationSlots) break;
      if (!order.contains(t)) order.add(t);
    }
    // A newly enabled workspace should appear on the bar straight away.
    if (on && kind != 'Market') {
      final home = workspaceTabs(kind).first;
      if (!order.contains(home)) {
        order.insert(math.min(1, order.length), home);
        while (order.length > navigationSlots) {
          order.removeLast();
        }
      }
    }
    setState(() {
      _workspaces = next;
      _purpose = purpose;
      _order = order;
    });
    await _persist();
    if (on && kind == 'Ranch' && ranchId().isEmpty && mounted) {
      await promptRanchSetup(context);
    }
  }

  void _dropOnSlot(int slot, String tab) {
    setState(() {
      final from = _order.indexOf(tab);
      if (from == slot) return;
      if (from >= 0) {
        _order[from] = _order[slot];
        _order[slot] = tab;
      } else {
        _order[slot] = tab;
      }
    });
    HapticFeedback.selectionClick();
    unawaited(_persist());
  }

  Future<void> _chooseSlotFor(String tab) async {
    final slot = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 0, 21, 8),
              child: Text(
                bi('Replace which tab?', 'எந்த tab-க்குப் பதிலாக வைக்கலாம்?'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (var i = 0; i < _order.length; i++)
              ListTile(
                leading: Icon(navIcon(_order[i]), color: _blue),
                title: Text(navLabel(_order[i])),
                trailing: AppText(
                  '${i + 1}',
                  style: const TextStyle(color: Ink.muted),
                ),
                onTap: () => Navigator.pop(sheet, i),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (slot != null) _dropOnSlot(slot, tab);
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Ink.muted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: .4,
      ),
    ),
  );

  Widget _footnote(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: AppText(
      text,
      style: const TextStyle(color: Ink.muted, fontSize: 13, height: 1.4),
    ),
  );

  Widget _workspaceRow(String kind) {
    final on = _workspaces.contains(kind);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: ShapeDecoration(
              shape: const SquircleBorder(radius: 11),
              color: on ? Ink.violetDeep : Ink.violet.withValues(alpha: .12),
            ),
            child: Center(
              child: workspaceIcon(
                kind,
                color: on ? Colors.white : _blue,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workspaceTitle(kind),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Ink.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  workspaceSubtitle(kind),
                  style: const TextStyle(color: Ink.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CupertinoSwitch(
            value: on,
            activeTrackColor: Ink.violetDeep,
            onChanged: (v) => _toggleWorkspace(kind, v),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String tab, {bool dragging = false, bool muted = false}) =>
      Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: ShapeDecoration(
            shape: SquircleBorder(
              radius: 16,
              side: BorderSide(
                color: muted ? const Color(0x33788298) : Colors.white,
              ),
            ),
            color: dragging
                ? Ink.violetDeep
                : Colors.white.withValues(alpha: muted ? .40 : .78),
            shadows: dragging
                ? [
                    BoxShadow(
                      color: Ink.violetDeep.withValues(alpha: .28),
                      blurRadius: 21,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              tab == 'Vendor'
                  ? MilkVendorIcon(
                      size: 24,
                      color: dragging ? Colors.white : _blue,
                    )
                  : Icon(
                      navIcon(tab),
                      size: 19,
                      color: dragging ? Colors.white : _blue,
                    ),
              const SizedBox(width: 8),
              Text(
                navLabel(tab),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: dragging ? Colors.white : Ink.navy,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _slot(int i) => DragTarget<String>(
    onWillAcceptWithDetails: (d) => d.data != _order[i],
    onAcceptWithDetails: (d) => _dropOnSlot(i, d.data),
    builder: (context, candidate, _) {
      final hovering = candidate.isNotEmpty;
      final tab = _order[i];
      return AnimatedContainer(
        duration: Gold.fast,
        curve: Gold.ease,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: ShapeDecoration(
          shape: SquircleBorder(
            radius: 18,
            side: BorderSide(
              color: hovering ? Ink.violetDeep : Colors.white,
              width: hovering ? 1.5 : 1,
            ),
          ),
          color: hovering
              ? Ink.violet.withValues(alpha: .10)
              : Colors.white.withValues(alpha: .62),
        ),
        child: LongPressDraggable<String>(
          data: tab,
          delay: const Duration(milliseconds: 180),
          hapticFeedbackOnStart: true,
          feedback: _tabChip(tab, dragging: true),
          childWhenDragging: Opacity(opacity: .35, child: _slotRow(i, tab)),
          child: _slotRow(i, tab),
        ),
      );
    },
  );

  Widget _slotRow(int i, String tab) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const ShapeDecoration(
            shape: SquircleBorder(radius: 8),
            color: Ink.lavender,
          ),
          child: AppText(
            '${i + 1}',
            style: const TextStyle(
              color: Ink.violetDeep,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        tab == 'Vendor'
            ? MilkVendorIcon(size: 26, color: _blue)
            : Icon(navIcon(tab), size: 21, color: _blue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            navLabel(tab),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Ink.navy,
            ),
          ),
        ),
        const Icon(CupertinoIcons.line_horizontal_3, color: Ink.faint),
      ],
    ),
  );

  Widget _purposeChoice() => Column(
    children: [
      for (final kind in workspaceKinds) ...[
        _ChoiceCard(
          selected: _purpose == kind,
          title: workspaceTitle(kind),
          subtitle: workspaceSubtitle(kind),
          leading: workspaceIcon(
            kind,
            color: _purpose == kind ? Colors.white : Ink.violetDeep,
            size: 22,
          ),
          onTap: () => setState(() {
            _purpose = kind;
            _workspaces = [kind];
            _order = defaultNavigation(kind);
          }),
        ),
        const SizedBox(height: 13),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final extras = _extras;
    final showSync = _workspaces.contains('Ranch') && ranchId().isNotEmpty;
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      appBar: AppBar(
        title: Text(
          widget.onboarding
              ? bi('Welcome to VIMO', 'VIMO-க்கு வரவேற்கிறோம்')
              : bi('Preferences', 'விருப்பங்கள்'),
        ),
        automaticallyImplyLeading: !widget.onboarding,
      ),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (widget.onboarding) ...[
              Text(
                bi(
                  'What will you use VIMO for?',
                  'VIMO-வை எதற்காகப் பயன்படுத்தப் போகிறீர்கள்?',
                ),
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                bi(
                  'You can switch on more later in Settings → Preferences.',
                  'மற்ற பகுதிகளைப் பின்னர் செட்டிங்ஸ் → விருப்பங்களில் இயக்கலாம்.',
                ),
                style: const TextStyle(color: Ink.muted, fontSize: 15),
              ),
              const SizedBox(height: 21),
              _purposeChoice(),
              const SizedBox(height: 28),
              LiquidButton(
                label: bi('Get started', 'தொடங்கலாம்'),
                busy: _saving,
                onPressed: () async {
                  setState(() => _saving = true);
                  await _persist();
                  if (mounted) setState(() => _saving = false);
                },
              ),
            ] else ...[
              _sectionTitle(bi('Workspaces', 'பணிப் பகுதிகள்')),
              _InsetGroup(
                children: [for (final k in workspaceKinds) _workspaceRow(k)],
              ),
              _footnote(
                bi(
                  'Switch on everything you use. Your records stay safe when a workspace is off.',
                  'நீங்கள் பயன்படுத்தும் அனைத்தையும் இயக்கலாம். ஒரு பகுதியை அணைத்தாலும் பதிவுகள் பாதுகாப்பாக இருக்கும்.',
                ),
              ),
              if (showSync) ...[
                const SizedBox(height: 28),
                _InsetGroup(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              bi(
                                'Sync with ranch people',
                                'தொழுவ உறுப்பினர்களுடன் ஒத்திசை',
                              ),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Ink.navy,
                              ),
                            ),
                          ),
                          CupertinoSwitch(
                            value: CloudSyncService.sharedDataEnabled,
                            activeTrackColor: Ink.violetDeep,
                            onChanged: (value) async {
                              await setSetting('workspaceSyncEnabled', value);
                              await CollaborationRealtimeSyncService.stop();
                              if (value) {
                                AutoSyncService.markDirty(
                                  reason: 'enable ranch sharing',
                                );
                              }
                              await CollaborationRealtimeSyncService.ensureStarted();
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              _sectionTitle(bi('Tab order', 'Tab வரிசை')),
              for (var i = 0; i < _order.length; i++) _slot(i),
              _footnote(
                bi(
                  'Hold and drag to rearrange your four tabs.',
                  'அழுத்திப் பிடித்து இழுத்து நான்கு tab-களின் வரிசையை மாற்றலாம்.',
                ),
              ),
              if (extras.isNotEmpty) ...[
                const SizedBox(height: 28),
                _sectionTitle(bi('More tabs', 'மேலும் tab-கள்')),
                DragTarget<String>(
                  onWillAcceptWithDetails: (_) => false,
                  builder: (context, _, _) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tab in extras)
                        Draggable<String>(
                          data: tab,
                          feedback: _tabChip(tab, dragging: true),
                          childWhenDragging: Opacity(
                            opacity: .35,
                            child: _tabChip(tab, muted: true),
                          ),
                          child: GestureDetector(
                            onTap: () => _chooseSlotFor(tab),
                            child: _tabChip(tab, muted: true),
                          ),
                        ),
                    ],
                  ),
                ),
                _footnote(
                  bi(
                    'Drag a tab onto the list above, or tap it to choose its place.',
                    'ஒரு tab-ஐ மேலே உள்ள பட்டியலுக்கு இழுக்கவும், அல்லது தொட்டு இடத்தைத் தேர்வு செய்யவும்.',
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> vendorRows(String box) => Hive.box(box)
    .toMap()
    .entries
    .where((e) => e.value is Map)
    .map((e) => {...asMap(e.value), '_key': e.key})
    .toList();
double vendorMilkBalance(Iterable<Map<String, dynamic>> entries) =>
    vendorOpeningBalance(entries) +
    entries
        .where((r) => r['stockScope'] == 'vendor_v2')
        .fold(
          0.0,
          (total, r) =>
              total +
              (r['kind'] == 'purchase' || r['kind'] == 'collection'
                  ? numv(r, 'quantity')
                  : r['kind'] == 'sale'
                  ? -numv(r, 'quantity')
                  : 0),
        );
double vendorPersonDue(
  String personId,
  Iterable<Map<String, dynamic>> entries,
) => entries
    .where((r) => r['personId'] == personId)
    .fold(
      0.0,
      (total, r) =>
          total +
          (r['kind'] == 'payment'
              ? -numv(r, 'amount')
              : numv(r, 'amount') - numv(r, 'paid')),
    );
bool vendorDeliveryDue(
  Map<String, dynamic> person,
  DateTime date,
  String session,
) =>
    person['kind'] == 'customer' &&
    (person['days'] is List &&
        ((person['days'] as List).isEmpty ||
            (person['days'] as List).contains(date.weekday % 7))) &&
    (person['sessions'] is List &&
        (person['sessions'] as List).contains(session));

class VendorLedger {
  static bool _busy = false;
  static Future<void> record({
    required String id,
    required Map<String, dynamic> person,
    required String kind,
    double quantity = 0,
    double price = 0,
    double paid = 0,
    double payment = 0,
    String session = 'Morning',
    String notes = '',
  }) async {
    if (_busy) {
      throw StateError(
        bi(
          'Another entry is saving. Try again.',
          'மற்றொரு பதிவு சேமிக்கப்படுகிறது. மீண்டும் முயற்சிக்கவும்.',
        ),
      );
    }
    if (!canRecordEntries) throw StateError(ui('Permission denied'));
    if (id.isEmpty ||
        txt(person, 'id').isEmpty ||
        notes.length > 500 ||
        !['collection', 'purchase', 'sale', 'payment'].contains(kind) ||
        (['collection', 'purchase'].contains(kind) &&
            person['kind'] != 'supplier') ||
        (kind == 'sale' && person['kind'] != 'customer') ||
        ![quantity, price, paid, payment].every((n) => n.isFinite && n >= 0) ||
        (kind != 'payment' &&
            (quantity <= 0 || price <= 0 || paid > quantity * price)) ||
        (kind == 'payment' && payment <= 0)) {
      throw StateError(
        bi(
          'Enter valid quantities and amounts.',
          'சரியான அளவு மற்றும் தொகையை உள்ளிடவும்.',
        ),
      );
    }
    _busy = true;
    try {
      final now = DateTime.now();
      final personId = txt(person, 'id');
      final amount = kind == 'payment'
          ? payment
          : double.parse((quantity * price).toStringAsFixed(2));
      final entry = <String, dynamic>{
        'pendingUpload': true,
        'cloudId': id,
        'kind': kind,
        'stockScope': 'vendor_v2',
        'syncMode': 'local_v3',
        'personId': personId,
        'personName': txt(person, 'name'),
        'personKind': txt(person, 'kind'),
        'quantity': kind == 'payment' ? 0.0 : quantity,
        'price': kind == 'payment' ? 0.0 : price,
        'amount': amount,
        'paid': paid,
        'session': session,
        'notes': notes,
        'date': todayDate(),
        'time': currentTime(),
        'createdAt': now.toIso8601String(),
        'createdByUid': firebaseReady
            ? FirebaseAuth.instance.currentUser?.uid ?? ''
            : '',
        'addedBy': currentUserName(),
        'updatedAtMillis': now.millisecondsSinceEpoch,
      };
      final box = Hive.box('vendor_entries');
      // Stable IDs make a retry after an interrupted save a no-op.
      if (box.containsKey(id)) return;
      final rows = vendorRows('vendor_entries');
      if (kind == 'sale' && quantity > vendorMilkBalance(rows) + 0.000001) {
        throw StateError(
          bi(
            'Not enough milk. Add the milk collected from a provider first.',
            'பால் இருப்பு போதவில்லை. முதலில் வழங்குநரிடமிருந்து பெற்ற பாலைப் பதிவு செய்யவும்.',
          ),
        );
      }
      if (kind == 'payment' &&
          amount > vendorPersonDue(personId, rows) + 0.001) {
        throw StateError(
          bi(
            'Payment exceeds the outstanding balance.',
            'செலுத்தும் தொகை நிலுவையை விட அதிகமாக உள்ளது.',
          ),
        );
      }
      entry['pendingUpload'] = true;
      await box.put(id, entry);
      await box.flush();
      AutoSyncService.markDirty(reason: 'vendor entry');
    } finally {
      _busy = false;
    }
  }
}

class VendorScreen extends StatefulWidget {
  final int initialSection;
  final bool showTabs;
  const VendorScreen({
    super.key,
    this.initialSection = 0,
    this.showTabs = true,
  });
  @override
  State<VendorScreen> createState() => _VendorScreenState();
}

class _VendorScreenState extends State<VendorScreen> {
  late int _section = widget.initialSection;
  String _search = '';
  @override
  void initState() {
    super.initState();
    if (CloudSyncService.ready) {
      if (canManageRanch) {
        unawaited(
          SeparateVendorStock.ensureInitialized().catchError((Object error) {
            if (mounted) snack(context, accountError(error));
          }),
        );
      }
      unawaited(
        CloudSyncService.downloadBox(
          'vendor_entries',
        ).catchError((Object _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('vendor_people').listenable(),
    builder: (_, _, _) => ValueListenableBuilder(
      valueListenable: Hive.box('vendor_entries').listenable(),
      builder: (_, _, _) {
        final all = vendorRows('vendor_people');
        final rows = vendorRows('vendor_entries');
        final today = rows.where((r) => r['date'] == todayDate()).toList();
        final people =
            all
                .where(
                  (p) =>
                      p['kind'] == (_section < 2 ? 'supplier' : 'customer') &&
                      '${p['name']} ${p['place']}'.toLowerCase().contains(
                        _search.toLowerCase(),
                      ),
                )
                .toList()
              ..sort((a, b) => txt(a, 'name').compareTo(txt(b, 'name')));
        final session = DateTime.now().hour < 12 ? 'Morning' : 'Evening';
        final due = all
            .where(
              (p) =>
                  vendorDeliveryDue(p, DateTime.now(), session) &&
                  !today.any(
                    (r) =>
                        r['kind'] == 'sale' &&
                        r['personId'] == p['id'] &&
                        r['session'] == session,
                  ),
            )
            .toList();
        return Shell(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(21, 16, 21, 32),
            children: [
              if (widget.showTabs)
                LiquidSegmentBar(
                  labels: [
                    bi('Collect milk', 'பால் சேகரிப்பு'),
                    bi('Buy milk', 'பால் கொள்முதல்'),
                    bi('Sell milk', 'பால் விற்பது'),
                  ],
                  index: _section,
                  onChanged: (v) => setState(() {
                    _section = v;
                    _search = '';
                  }),
                ),
              const SizedBox(height: 24),
              Text(
                _section == 0
                    ? bi('Collect milk', 'பால் சேகரிப்பு')
                    : _section == 1
                    ? bi('Buy milk', 'பால் கொள்முதல்')
                    : bi('Sell milk', 'பால் விற்பனை'),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                bi(
                  'Every litre. Every delivery.',
                  'ஒவ்வொரு லிட்டரும். ஒவ்வொரு விநியோகமும்.',
                ),
                style: const TextStyle(color: Ink.muted),
              ),
              const SizedBox(height: 20),
              Glass(
                onTap: () => push(context, const MilkOriginScreen()),
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            bi(
                              'VENDOR MILK STORAGE',
                              'விற்பனையாளர் பால் இருப்பு',
                            ),
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .7,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const MilkVendorIcon(size: 60, detailed: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AppText(
                      '${vendorMilkBalance(rows).toStringAsFixed(2)} ${bi('L', 'லி')}',
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        _BusinessMetric(
                          label: bi('Collected today', 'இன்று சேகரித்தது'),
                          value:
                              '${_vendorSum(today, 'collection', 'quantity').toStringAsFixed(1)} L',
                        ),
                        _BusinessMetric(
                          label: bi('Bought today', 'இன்று வாங்கியது'),
                          value:
                              '${_vendorSum(today, 'purchase', 'quantity').toStringAsFixed(1)} L',
                        ),
                        _BusinessMetric(
                          label: bi('Sold today', 'இன்று விற்றது'),
                          value:
                              '${_vendorSum(today, 'sale', 'quantity').toStringAsFixed(1)} L',
                        ),
                        _BusinessMetric(
                          label: bi('Sales today', 'இன்றைய விற்பனை'),
                          value:
                              '${currencySymbol()}${_vendorSum(today, 'sale', 'amount').toStringAsFixed(0)}',
                        ),
                        _BusinessMetric(
                          label: bi('Receivable', 'வரவேண்டிய தொகை'),
                          value:
                              '${currencySymbol()}${all.where((p) => p['kind'] == 'customer').fold(0.0, (s, p) => s + vendorPersonDue(txt(p, 'id'), rows)).toStringAsFixed(0)}',
                        ),
                        _BusinessMetric(
                          label: bi('Payable', 'கொடுக்கவேண்டிய தொகை'),
                          value:
                              '${currencySymbol()}${all.where((p) => p['kind'] == 'supplier').fold(0.0, (s, p) => s + vendorPersonDue(txt(p, 'id'), rows)).toStringAsFixed(0)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (due.isNotEmpty) ...[
                const SizedBox(height: 20),
                AppText(
                  '${ui(session)} · ${bi('Deliveries remaining', 'மீதமுள்ள விநியோகங்கள்')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                _InsetGroup(
                  children: [
                    for (final p in due)
                      ListTile(
                        title: Text(txt(p, 'name')),
                        subtitle: Text(txt(p, 'place')),
                        trailing: const Icon(
                          CupertinoIcons.chevron_right,
                          size: 16,
                        ),
                        onTap: () => push(
                          context,
                          VendorPersonScreen(
                            person: p,
                            intakeKind: _section == 0
                                ? 'collection'
                                : 'purchase',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _section < 2
                          ? bi('Milk suppliers', 'பால் கொடுப்பவர்கள்')
                          : bi('Customers', 'வாடிக்கையாளர்கள்'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (canRecordEntries)
                    IconButton.filledTonal(
                      tooltip: ui('Add person'),
                      onPressed: () => push(
                        context,
                        VendorPersonForm(
                          kind: _section < 2 ? 'supplier' : 'customer',
                        ),
                      ),
                      icon: const Icon(CupertinoIcons.plus),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey(_section),
                decoration: InputDecoration(
                  prefixIcon: const Icon(CupertinoIcons.search),
                  hintText: bi(
                    'Search name or place',
                    'பெயர் அல்லது இடம் தேடு',
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 16),
              if (people.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    bi(
                      'No people yet. Tap + to add a person.',
                      'பட்டியல் காலியாக உள்ளது. நபரைச் சேர்க்க + அழுத்தவும்.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              _InsetGroup(
                children: [
                  for (final p in people)
                    ListTile(
                      leading: GlassAvatar(
                        image: personPhoto(p),
                        label: txt(p, 'name'),
                        radius: 22,
                      ),
                      title: Text(txt(p, 'name')),
                      subtitle: AppText(
                        '${txt(p, 'place')}\n${currencySymbol()}${vendorPersonDue(txt(p, 'id'), rows).toStringAsFixed(2)} ${bi('outstanding', 'நிலுவை')}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                      ),
                      onTap: () => push(
                        context,
                        VendorPersonScreen(
                          person: p,
                          intakeKind: _section == 0 ? 'collection' : 'purchase',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

double _vendorSum(
  Iterable<Map<String, dynamic>> rows,
  String kind,
  String field,
) => rows
    .where((r) => r['kind'] == kind)
    .fold(0.0, (s, r) => s + numv(r, field));

class VendorStockScreen extends StatelessWidget {
  const VendorStockScreen({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('vendor_entries').listenable(),
    builder: (_, _, _) {
      final rows = vendorRows('vendor_entries')
        ..sort((a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')));
      return Shell(
        child: ListView(
          padding: const EdgeInsets.all(21),
          children: [
            Text(
              bi('Vendor milk stock', 'வியாபாரி பால் இருப்பு'),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => push(context, const MilkOriginScreen()),
              child: Glass(
                padding: const EdgeInsets.all(24),
                child: AppText(
                  '${vendorMilkBalance(rows).toStringAsFixed(2)} L',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 20),
            for (final r in rows.where(
              (r) => r['kind'] != 'payment' && r['kind'] != 'ranch',
            ))
              ListTile(
                onTap: () => push(context, MilkOriginScreen(entry: r)),
                title: AppText(txt(r, 'personName')),
                subtitle: AppText('${txt(r, 'date')} · ${txt(r, 'time')}'),
                trailing: AppText(
                  '${['collection', 'purchase'].contains(r['kind']) || (r['kind'] == 'ranch' && numv(r, 'quantity') >= 0) ? '+' : '−'}${numv(r, 'quantity').abs().toStringAsFixed(2)} L',
                  style: TextStyle(
                    color:
                        ['collection', 'purchase'].contains(r['kind']) ||
                            (r['kind'] == 'ranch' && numv(r, 'quantity') >= 0)
                        ? Ink.green
                        : Ink.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (rows.isEmpty)
              Text(
                bi(
                  'No milk movements yet.',
                  'பால் பரிவர்த்தனைகள் இன்னும் இல்லை.',
                ),
              ),
          ],
        ),
      );
    },
  );
}

class VendorReportSummary extends StatelessWidget {
  final String period;
  const VendorReportSummary({super.key, required this.period});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('vendor_entries').listenable(),
    builder: (_, _, _) {
      final rows = vendorRows(
        'vendor_entries',
      ).where((r) => matchPeriod(txt(r, 'date'), period)).toList();
      if (rows.isEmpty && appPurpose != 'Vendor') {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Glass(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bi('Vendor business', 'பால் வியாபாரக் கணக்கு'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 16,
                children: [
                  _BusinessMetric(
                    label: bi('Collected', 'சேகரித்த பால்'),
                    value:
                        '${_vendorSum(rows, 'collection', 'quantity').toStringAsFixed(2)} L',
                  ),
                  _BusinessMetric(
                    label: bi('Purchased', 'வாங்கிய பால்'),
                    value:
                        '${_vendorSum(rows, 'purchase', 'quantity').toStringAsFixed(2)} L',
                  ),
                  _BusinessMetric(
                    label: bi('Delivered', 'விற்ற பால்'),
                    value:
                        '${_vendorSum(rows, 'sale', 'quantity').toStringAsFixed(2)} L',
                  ),
                  _BusinessMetric(
                    label: bi('Purchase cost', 'வாங்கிய செலவு'),
                    value:
                        '${currencySymbol()}${(_vendorSum(rows, 'purchase', 'amount') + _vendorSum(rows, 'collection', 'amount')).toStringAsFixed(2)}',
                  ),
                  _BusinessMetric(
                    label: bi('Sales value', 'விற்பனைத் தொகை'),
                    value:
                        '${currencySymbol()}${_vendorSum(rows, 'sale', 'amount').toStringAsFixed(2)}',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _BusinessMetric extends StatelessWidget {
  final String label, value;
  const _BusinessMetric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      Text(label, style: const TextStyle(color: Ink.muted, fontSize: 12)),
    ],
  );
}

const _dayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const _dayTamil = [
  'ஞாயிறு',
  'திங்கள்',
  'செவ்வாய்',
  'புதன்',
  'வியாழன்',
  'வெள்ளி',
  'சனி',
];

class VendorPersonScreen extends StatefulWidget {
  final Map<String, dynamic> person;
  final String intakeKind;
  final String entryPrefix;
  final String? initialSession;
  const VendorPersonScreen({
    super.key,
    required this.person,
    this.intakeKind = 'purchase',
    this.entryPrefix = '',
    this.initialSession,
  });
  @override
  State<VendorPersonScreen> createState() => _VendorPersonScreenState();
}

class _VendorPersonScreenState extends State<VendorPersonScreen> {
  final _qty = TextEditingController(),
      _price = TextEditingController(),
      _paid = TextEditingController(text: '0');
  bool _busy = false;
  bool _payment = false;
  String _session = vendorSessionNow();
  String _entryId = '';
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _session = widget.initialSession ?? _session;
    _qty.text = vendorFieldNumber(
      vendorUsualQuantity(
        widget.person,
        _session,
        vendorRows('vendor_entries'),
      ),
    );
    _price.text = vendorFieldNumber(
      numv(widget.person, 'price', defaultMilkPrice()),
    );
    _qty.addListener(_refresh);
    _price.addListener(_refresh);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _qty.dispose();
    _price.dispose();
    _paid.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> p, bool supplier) async {
    if (_busy) return;
    setState(() => _busy = true);
    _entryId = _entryId.isEmpty
        ? '${widget.entryPrefix.isEmpty ? 'v' : widget.entryPrefix}_${DateTime.now().microsecondsSinceEpoch}_${settingText('deviceId', 'device')}'
        : _entryId;
    try {
      await VendorLedger.record(
        id: _entryId,
        person: p,
        kind: _payment
            ? 'payment'
            : supplier
            ? widget.intakeKind
            : 'sale',
        quantity: double.tryParse(_qty.text) ?? 0,
        price: double.tryParse(_price.text) ?? 0,
        paid: _payment ? 0 : double.tryParse(_paid.text) ?? -1,
        payment: _payment ? double.tryParse(_paid.text) ?? 0 : 0,
        session: vendorSessionNow(),
      );
      _entryId = '';
      if (!mounted) return;
      snack(context, bi('Saved', 'சேமிக்கப்பட்டது'));
      // A finished entry returns to the Vendor page.
      await Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        snack(
          context,
          e is FirebaseException
              ? bi(
                  'Could not save. Check your connection and retry.',
                  'சேமிக்க முடியவில்லை. இணைய இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',
                )
              : '$e'.replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contact(String uri) async {
    try {
      await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) snack(context, ui('Unable to open'));
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('vendor_people').listenable(),
    builder: (_, _, _) {
      final p =
          vendorRows(
            'vendor_people',
          ).where((p) => p['id'] == widget.person['id']).firstOrNull ??
          widget.person;
      final supplier = p['kind'] == 'supplier';
      final contact = txt(p, 'contact').replaceAll(RegExp(r'[^0-9+]'), '');
      return Scaffold(
        backgroundColor: Ink.canvasTop,
        body: SafeArea(
          bottom: false,
          child: Shell(
            child: ValueListenableBuilder(
              valueListenable: Hive.box('vendor_entries').listenable(),
              builder: (_, _, _) {
                final all = vendorRows('vendor_entries');
                final rows = all.where((r) => r['personId'] == p['id']).toList()
                  ..sort(
                    (a, b) =>
                        txt(b, 'createdAt').compareTo(txt(a, 'createdAt')),
                  );
                final due = vendorPersonDue(txt(p, 'id'), rows);
                final month = thisMonth();
                final monthLitres = rows
                    .where(
                      (r) =>
                          txt(r, 'date').startsWith(month) &&
                          r['kind'] != 'payment',
                    )
                    .fold(0.0, (s, r) => s + numv(r, 'quantity'));
                final qty = toDouble(_qty.text), price = toDouble(_price.text);
                final entryTotal = qty * price;
                final days = vendorWeekdays(p['days']);
                final sessions = ((p['sessions'] as List?) ?? const [])
                    .whereType<String>()
                    .toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(21, 8, 21, 40),
                  children: [
                    // Back and edit sit beside the portrait instead of in an
                    // empty app bar row above it.
                    Stack(
                      children: [
                        Center(
                          child: GlassPortrait(
                            image: personPhoto(p),
                            title: txt(p, 'name'),
                            subtitle: txt(
                              p,
                              'place',
                              supplier
                                  ? bi('Milk provider', 'பால் வழங்குநர்')
                                  : bi('Milk buyer', 'பால் வாங்குபவர்'),
                            ),
                            size: 150,
                          ),
                        ),
                        PositionedDirectional(
                          top: 0,
                          start: -8,
                          child: IconButton(
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).backButtonTooltip,
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                        if (canRecordEntries)
                          PositionedDirectional(
                            top: 0,
                            end: -8,
                            child: IconButton(
                              tooltip: ui('Edit person'),
                              icon: const Icon(CupertinoIcons.pencil),
                              onPressed: () => push(
                                context,
                                VendorPersonForm(
                                  kind: txt(p, 'kind'),
                                  person: p,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (due > .001)
                          _InfoChip(
                            icon: CupertinoIcons.money_dollar_circle_fill,
                            label:
                                '${supplier ? bi('To pay', 'கொடுக்க') : bi('To collect', 'பெற')} ${money(due)}',
                            color: supplier ? Ink.amberText : Ink.redText,
                          ),
                        _InfoChip(
                          icon: supplier
                              ? CupertinoIcons.arrow_down_circle
                              : CupertinoIcons.arrow_up_circle,
                          label: supplier
                              ? bi('Provider', 'வழங்குநர்')
                              : bi('Buyer', 'வாங்குபவர்'),
                        ),
                        _InfoChip(
                          icon: CupertinoIcons.calendar,
                          label: vendorPaymentScheduleLabel(p),
                        ),
                        if (days.isNotEmpty)
                          _InfoChip(
                            icon: CupertinoIcons.drop,
                            label: vendorScheduleDays(days),
                          ),
                        if (sessions.isNotEmpty && sessions.length < 2)
                          _InfoChip(
                            icon: sessions.first == 'Morning'
                                ? CupertinoIcons.sun_max
                                : CupertinoIcons.moon,
                            label: ui(sessions.first),
                          ),
                      ],
                    ),
                    if (contact.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _contact('tel:$contact'),
                            icon: const Icon(
                              CupertinoIcons.phone_fill,
                              size: 18,
                            ),
                            label: Text(bi('Call', 'அழை')),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () => _contact(
                              'https://wa.me/${contact.replaceAll('+', '')}',
                            ),
                            icon: const Icon(
                              CupertinoIcons.chat_bubble_fill,
                              size: 18,
                            ),
                            label: const AppText('WhatsApp'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (canRecordEntries) ...[
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(
                              supplier
                                  ? widget.intakeKind == 'collection'
                                        ? bi('Collect milk', 'பால் சேகரிப்பு')
                                        : bi('Buy milk', 'பால் வாங்கு')
                                  : bi('Deliver milk', 'பால் விற்பனை'),
                            ),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(bi('Payment', 'பணம்')),
                          ),
                        ],
                        selected: {_payment},
                        onSelectionChanged: _busy
                            ? null
                            : (v) => setState(() {
                                _payment = v.first;
                                _entryId = '';
                                _paid.text = _payment && due > .001
                                    ? vendorFieldNumber(due)
                                    : '0';
                              }),
                      ),
                      const SizedBox(height: 20),
                      if (!_payment) ...[
                        TextField(
                          controller: _qty,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: fieldStyle(
                            bi('Milk quantity (litres)', 'பால் அளவு (லிட்டர்)'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: fieldStyle(
                            bi('Price per litre', 'ஒரு லிட்டர் விலை'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _paid,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: fieldStyle(
                          _payment
                              ? supplier
                                    ? bi('Amount paid', 'செலுத்திய தொகை')
                                    : bi('Amount received', 'பெற்ற தொகை')
                              : bi(
                                  supplier
                                      ? 'Amount paid now (0 for later)'
                                      : 'Amount received now (0 for later)',
                                  supplier
                                      ? 'இப்போது செலுத்தியது (பிறகு என்றால் 0)'
                                      : 'இப்போது பெற்றது (பிறகு என்றால் 0)',
                                ),
                        ),
                      ),
                      if (!_payment && entryTotal > 0) ...[
                        const SizedBox(height: 12),
                        Glass(
                          radius: 22,
                          padding: const EdgeInsets.all(16),
                          tint: Ink.violetDeep.withValues(alpha: .05),
                          child: Column(
                            children: [
                              _TotalLine(
                                label: due > .001
                                    ? bi('This entry', 'இந்தப் பதிவு')
                                    : bi('Total', 'மொத்தம்'),
                                strong: due <= .001,
                                value: money(entryTotal),
                              ),
                              if (due > .001) ...[
                                const SizedBox(height: 6),
                                _TotalLine(
                                  label: bi(
                                    'Previous balance',
                                    'முந்தைய நிலுவை',
                                  ),
                                  value: money(due),
                                ),
                                const Divider(height: 18),
                                _TotalLine(
                                  label: supplier
                                      ? bi('Total to pay', 'மொத்தம் கொடுக்க')
                                      : bi('Total to collect', 'மொத்தம் பெற'),
                                  value: money(entryTotal + due),
                                  strong: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      LiquidButton(
                        label: bi('Save entry', 'பதிவைச் சேமி'),
                        busy: _busy,
                        height: 56,
                        radius: 28,
                        onPressed: _busy ? null : () => _save(p, supplier),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Glass(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _PersonStat(
                              label: due > .001
                                  ? supplier
                                        ? bi('To pay', 'கொடுக்கவேண்டியது')
                                        : bi('To collect', 'பெறவேண்டியது')
                                  : bi('Balance', 'நிலுவை'),
                              value: due > .001
                                  ? money(due)
                                  : bi('Settled', 'தீர்ந்தது'),
                              color: due > .001
                                  ? supplier
                                        ? Ink.amberText
                                        : Ink.redText
                                  : Ink.greenText,
                            ),
                          ),
                          const _StatDivider(),
                          Expanded(
                            child: _PersonStat(
                              label: bi('This month', 'இந்த மாதம்'),
                              value: '${vendorFieldNumber(monthLitres)} L',
                            ),
                          ),
                          const _StatDivider(),
                          Expanded(
                            child: _PersonStat(
                              label: bi('Price / L', 'விலை / லி'),
                              value: money(
                                numv(p, 'price', defaultMilkPrice()),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      bi('History', 'பரிவர்த்தனைகள்'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (rows.isEmpty)
                      Text(
                        bi('No transactions yet.', 'பரிவர்த்தனைகள் இல்லை.'),
                        style: const TextStyle(color: Ink.muted),
                      ),
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Glass(
                          radius: 22,
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      (r['kind'] == 'payment'
                                              ? Ink.green
                                              : Ink.violetDeep)
                                          .withValues(alpha: .1),
                                ),
                                child: Icon(
                                  r['kind'] == 'payment'
                                      ? CupertinoIcons.money_dollar
                                      : CupertinoIcons.drop_fill,
                                  size: 20,
                                  color: r['kind'] == 'payment'
                                      ? Ink.greenText
                                      : Ink.violetDeep,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      vendorEntryLabel(txt(r, 'kind')),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      [
                                        '${txt(r, 'date')} · ${txt(r, 'time')}',
                                        if (r['kind'] != 'payment')
                                          '${vendorFieldNumber(numv(r, 'quantity'))} L',
                                        if (txt(r, 'notes').isNotEmpty)
                                          txt(r, 'notes'),
                                      ].join('\n'),
                                      style: const TextStyle(
                                        color: Ink.muted,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                money(numv(r, 'amount')),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              if (withinEntryEditWindow(r, DateTime.now()) &&
                                  canRecordEntries &&
                                  (!firebaseReady ||
                                      r['createdByUid'] ==
                                          FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid))
                                IconButton(
                                  tooltip: bi(
                                    'Edit note',
                                    'குறிப்பைத் திருத்து',
                                  ),
                                  icon: const Icon(CupertinoIcons.pencil),
                                  onPressed: () => _editNote(r),
                                )
                              else
                                const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );
  Future<void> _editNote(Map<String, dynamic> row) async {
    final controller = TextEditingController(text: txt(row, 'notes'));
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bi('Add a note', 'குறிப்பைச் சேர்க்கவும்')),
        content: TextField(controller: controller, maxLength: 500, maxLines: 3),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const AppText('Save'),
          ),
        ],
      ),
    );
    if (note == null || !mounted) return;
    try {
      if (!withinEntryEditWindow(row, DateTime.now())) {
        throw StateError(
          bi(
            'The five-minute edit time has expired.',
            'ஐந்து நிமிட திருத்த நேரம் முடிந்துவிட்டது.',
          ),
        );
      }
      final update = {
        ...row,
        'notes': note,
        'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
      }..remove('_key');
      update['pendingUpload'] = true;
      await Hive.box('vendor_entries').put(row['_key'], update);
      await Hive.box('vendor_entries').flush();
      AutoSyncService.markDirty(reason: 'vendor note');
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Bad state: ', ''));
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({
    required this.icon,
    required this.label,
    this.color = Ink.body,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: ShapeDecoration(
      color: Colors.white.withValues(alpha: .72),
      shape: StadiumBorder(
        side: BorderSide(color: Ink.violetDeep.withValues(alpha: .10)),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color == Ink.body ? Ink.violetDeep : color),
        const SizedBox(width: 6),
        Flexible(
          child: AppText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PersonStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _PersonStat({
    required this.label,
    required this.value,
    this.color = Ink.navy,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: AppText(
          value,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
      const SizedBox(height: 3),
      AppText(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Ink.muted, fontSize: 12.5),
      ),
    ],
  );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 34,
    color: Ink.violetDeep.withValues(alpha: .12),
  );
}

class _TotalLine extends StatelessWidget {
  final String label, value;
  final bool strong;
  const _TotalLine({
    required this.label,
    required this.value,
    this.strong = false,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: AppText(
          label,
          style: TextStyle(
            color: strong ? Ink.navy : Ink.muted,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
      AppText(
        value,
        style: TextStyle(
          fontSize: strong ? 20 : 16,
          fontWeight: FontWeight.w800,
          color: Ink.navy,
        ),
      ),
    ],
  );
}
