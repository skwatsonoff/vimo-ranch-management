part of 'main.dart';

String get signedInUid =>
    firebaseReady ? FirebaseAuth.instance.currentUser?.uid ?? '' : '';

class CurrentProfileAvatar extends StatelessWidget {
  final double radius;
  const CurrentProfileAvatar({super.key, this.radius = 22});
  @override
  Widget build(BuildContext context) => signedInUid.isEmpty
      ? profileAvatar('', radius: radius)
      : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('profiles')
              .doc(signedInUid)
              .snapshots(),
          builder: (_, snap) => profileAvatar(
            txt(snap.data?.data() ?? {}, 'photo'),
            radius: radius,
          ),
        );
}

/// Only explicitly selected, non-financial cow fields leave the ranch.
Map<String, dynamic> publicCow(Map<String, dynamic> cow) => {
  'name': txt(cow, 'name'),
  'cowId': txt(cow, 'cowId', txt(cow, 'id')),
  'photo': txt(cow, 'imageData'),
  'breed': txt(cow, 'breed'),
};

class PublicRanchService {
  static Future<void> refresh() async {
    final uid = signedInUid;
    if (uid.isEmpty || !CloudSyncService.ready) return;
    final ref = FirebaseFirestore.instance.collection('profiles').doc(uid);
    final registry = FirebaseFirestore.instance
        .collection('ranch_ids')
        .doc(ranchId());
    final directory =
        (await registry
                .get(const GetOptions(source: Source.server))
                .timeout(CloudSyncService.networkTimeout))
            .data();
    if (directory != null &&
        directory['ownerUid'] == uid &&
        (directory['farmNameFold'] != farmName().toLowerCase() ||
            directory['farmName'] != farmName())) {
      await registry
          .update({
            'farmName': farmName(),
            'farmNameFold': farmName().toLowerCase(),
          })
          .timeout(CloudSyncService.networkTimeout);
    }
    final profile =
        (await ref
                .get(const GetOptions(source: Source.server))
                .timeout(CloudSyncService.networkTimeout))
            .data();
    if (profile == null ||
        profile['shareRanch'] != true ||
        profile['ranchId'] != ranchId()) {
      return;
    }
    final existing = await ref
        .collection('cows')
        .get(const GetOptions(source: Source.server))
        .timeout(CloudSyncService.networkTimeout);
    final cows = animalsBy('cow');
    final current = <String>{};
    // Per-record writes avoid Firestore's batch size and payload limits.
    for (final cow in cows) {
      final id = txt(cow, 'cloudId');
      if (id.isEmpty) continue;
      current.add(id);
      final data = publicCow(cow);
      final matches = existing.docs.where((d) => d.id == id);
      final before = matches.isEmpty ? null : matches.first;
      if (before != null && sameSyncValue(before.data(), data)) continue;
      await ref
          .collection('cows')
          .doc(id)
          .set(data)
          .timeout(CloudSyncService.networkTimeout);
    }
    for (final old in existing.docs.where((d) => !current.contains(d.id))) {
      await old.reference.delete().timeout(CloudSyncService.networkTimeout);
    }
  }
}

class PublicRanchView extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> profile;
  const PublicRanchView({super.key, required this.uid, required this.profile});
  @override
  Widget build(BuildContext context) {
    if (profile['shareRanch'] != true) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Text(bi('This ranch is private.', 'இந்தப் பண்ணை தனிப்பட்டது.')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const CowMark(size: 32),
          title: Text(txt(profile, 'ranchName')),
          subtitle: Text(txt(profile, 'ranchId')),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('profiles')
              .doc(uid)
              .collection('cows')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(accountError(snapshot.error!));
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  bi('No cows shared yet.', 'இன்னும் மாடுகள் பகிரப்படவில்லை.'),
                ),
              );
            }
            return Column(
              children: [
                for (final cow in snapshot.data!.docs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Glass(
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: txt(cow.data(), 'photo').isEmpty
                                ? const SizedBox(
                                    width: 90,
                                    height: 90,
                                    child: CowMark(size: 50),
                                  )
                                : Image.memory(
                                    socialPhotoBytes(txt(cow.data(), 'photo')),
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const CowMark(size: 50),
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  txt(cow.data(), 'name'),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(txt(cow.data(), 'cowId')),
                                Text(txt(cow.data(), 'breed')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class CommunitySearchScreen extends StatefulWidget {
  final bool addPersonal;
  const CommunitySearchScreen({super.key, this.addPersonal = false});
  @override
  State<CommunitySearchScreen> createState() => _CommunitySearchScreenState();
}

class _CommunitySearchScreenState extends State<CommunitySearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _revision = 0;
  bool _busy = false;
  String? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _people = [];
  List<Map<String, dynamic>> _ranches = [];
  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    final rev = ++_revision;
    final q = text.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    setState(() {
      _error = null;
      _busy = q.isNotEmpty;
      _people = [];
      _ranches = [];
    });
    if (q.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final db = FirebaseFirestore.instance;
        Future<QuerySnapshot<Map<String, dynamic>>> find(
          String col,
          String key,
        ) => db
            .collection(col)
            .orderBy(key)
            .startAt([q])
            .endAt(['$q\uf8ff'])
            .limit(25)
            .get(const GetOptions(source: Source.server))
            .timeout(CloudSyncService.networkTimeout);
        final results = await Future.wait([
          find('profiles', 'username'),
          find('profiles', 'displayNameFold'),
          find('ranch_ids', 'farmNameFold'),
        ]);
        final exact = q.contains('/')
            ? null
            : await db
                  .collection('ranch_ids')
                  .doc(q)
                  .get()
                  .timeout(CloudSyncService.networkTimeout);
        if (!mounted || rev != _revision) return;
        setState(() {
          _people = {
            for (final d in [...results[0].docs, ...results[1].docs]) d.id: d,
          }.values.toList();
          _ranches = {
            for (final d in results[2].docs) d.id: {...d.data(), 'id': d.id},
            if (exact?.exists == true)
              exact!.id: {...exact.data()!, 'id': exact.id},
          }.values.toList();
          _busy = false;
        });
      } catch (e) {
        if (mounted && rev == _revision) {
          setState(() {
            _busy = false;
            _error = accountError(e);
          });
        }
      }
    });
  }

  Future<void> _join(Map<String, dynamic> ranch) async {
    final id = txt(ranch, 'id');
    try {
      final uid = signedInUid;
      if (uid.isEmpty) throw StateError(ui('Please sign in again'));
      // A discovery request must never clear or switch the active local ranch.
      final ref = RanchAccessService.requestRef(id, uid);
      await ref
          .set({
            'uid': uid,
            'name': currentUserName(),
            'email': FirebaseAuth.instance.currentUser?.email ?? '',
            'status': 'pending',
            'requestedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(CloudSyncService.networkTimeout);
      if (mounted) {
        snack(
          context,
          bi(
            'Join request sent. The ranch admin can approve it.',
            'சேரும் கோரிக்கை அனுப்பப்பட்டது. பண்ணை நிர்வாகி ஒப்புதல் அளிக்கலாம்.',
          ),
        );
      }
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(bi('Search', 'தேடல்'))),
    body: Shell(
      child: ListView(
        padding: const EdgeInsets.all(21),
        children: [
          TextField(
            controller: _query,
            onChanged: _search,
            decoration: fieldStyle(
              bi('Username, name or ranch', 'பயனர்பெயர், பெயர் அல்லது பண்ணை'),
              icon: CupertinoIcons.search,
            ),
          ),
          const SizedBox(height: 20),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_error != null) Text(_error!),
          for (final person in _people)
            ListTile(
              leading: profileAvatar(txt(person.data(), 'photo'), radius: 24),
              title: Text(
                txt(
                  person.data(),
                  'displayName',
                  txt(person.data(), 'username'),
                ),
              ),
              subtitle: Text('@${txt(person.data(), 'username')}'),
              trailing: widget.addPersonal && person.id != signedInUid
                  ? IconButton(
                      icon: const Icon(CupertinoIcons.person_add),
                      onPressed: () async {
                        try {
                          await DirectChatService.addPersonal(person.id);
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (context.mounted) snack(context, accountError(e));
                        }
                      },
                    )
                  : null,
              onTap: () => push(context, SocialProfileScreen(uid: person.id)),
            ),
          if (!widget.addPersonal) ...[
            for (final ranch in _ranches)
              ListTile(
                leading: const CowMark(size: 32),
                title: Text(txt(ranch, 'farmName', txt(ranch, 'id'))),
                subtitle: Text(txt(ranch, 'id')),
                trailing: txt(ranch, 'id') == ranchId()
                    ? Text(bi('Joined', 'இணைந்துள்ளீர்கள்'))
                    : TextButton(
                        onPressed: () => _join(ranch),
                        child: Text(bi('Request to join', 'சேரக் கோரிக்கை')),
                      ),
              ),
          ],
          if (!_busy &&
              _error == null &&
              _query.text.isNotEmpty &&
              _people.isEmpty &&
              _ranches.isEmpty)
            Text(bi('No matches found.', 'பொருத்தமான முடிவுகள் இல்லை.')),
        ],
      ),
    ),
  );
}

class DirectChatService {
  static Future<void>? _sending;
  static Future<void> flush() =>
      _sending ??= _flush().whenComplete(() => _sending = null);
  static Future<void> _flush() async {
    if (!Hive.isBoxOpen('community_outbox')) return;
    final uid = signedInUid;
    if (uid.isEmpty) return;
    final box = Hive.box('community_outbox');
    await runSyncSteps({
      for (final key in box.keys.toList())
        '$key': () async {
          final value = asMap(box.get(key));
          if (value['senderUid'] != uid || signedInUid != uid) return;
          final ref = FirebaseFirestore.instance
              .collection('direct_chats')
              .doc(txt(value, 'chatId'))
              .collection('messages')
              .doc('$key');
          await FirebaseFirestore.instance.runTransaction(
            (tx) async {
              final old = await tx.get(ref);
              if (!old.exists) {
                tx.set(ref, {
                  'senderUid': uid,
                  'text': txt(value, 'text'),
                  'createdAt': FieldValue.serverTimestamp(),
                });
              }
            },
            timeout: CloudSyncService.networkTimeout,
            maxAttempts: 3,
          );
          if (sameSyncValue(box.get(key), value)) await box.delete(key);
        },
    });
  }

  static String idFor(String a, String b) => ([a, b]..sort()).join('_');
  static Future<void> addPersonal(String peer) async {
    if (signedInUid.isEmpty || peer == signedInUid) {
      throw StateError('Choose another person');
    }
    await FirebaseFirestore.instance
        .collection('profiles')
        .doc(signedInUid)
        .collection('contacts')
        .doc(peer)
        .set({
          'category': 'personal',
          'createdAt': FieldValue.serverTimestamp(),
        })
        .timeout(CloudSyncService.networkTimeout);
  }

  static Future<String> open(String peer) async {
    final me = signedInUid;
    if (me.isEmpty || peer == me) throw StateError('Choose another person');
    final ref = FirebaseFirestore.instance
        .collection('direct_chats')
        .doc(idFor(me, peer));
    // Read-free idempotent creation, with immutable participants on the server.
    await ref
        .set({
          'participants': [me, peer]..sort(),
        }, SetOptions(merge: true))
        .timeout(CloudSyncService.networkTimeout);
    return ref.id;
  }
}

class CommunityChatsScreen extends StatefulWidget {
  const CommunityChatsScreen({super.key});
  @override
  State<CommunityChatsScreen> createState() => _CommunityChatsScreenState();
}

class _CommunityChatsScreenState extends State<CommunityChatsScreen> {
  int _tab = 0;
  Future<void> _open(String peer) async {
    try {
      final id = await DirectChatService.open(peer);
      if (mounted) {
        await push(context, DirectChatScreen(chatId: id, peer: peer));
      }
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    }
  }

  Widget _person(String uid) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('profiles')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) => ListTile(
          leading: profileAvatar(
            txt(snap.data?.data() ?? {}, 'photo'),
            radius: 23,
          ),
          title: Text(
            txt(
              snap.data?.data() ?? {},
              'displayName',
              txt(snap.data?.data() ?? {}, 'username', 'Ranch member'),
            ),
          ),
          trailing: const Icon(CupertinoIcons.chat_bubble),
          onTap: () => _open(uid),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final me = signedInUid;
    if (me.isEmpty) return Center(child: Text(ui('Please sign in again')));
    final db = FirebaseFirestore.instance;
    return Shell(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: LiquidSegmentBar(
                    labels: [
                      bi('Personal chat', 'தனிப்பட்ட அரட்டை'),
                      bi('Business chat', 'வணிக அரட்டை'),
                    ],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ),
                if (_tab == 0)
                  IconButton(
                    tooltip: ui('Add'),
                    icon: const Icon(CupertinoIcons.person_add),
                    onPressed: () => push(
                      context,
                      const CommunitySearchScreen(addPersonal: true),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('profiles')
                  .doc(me)
                  .collection('contacts')
                  .snapshots(),
              builder: (context, contacts) =>
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: CloudSyncService.ready
                        ? CloudSyncService.ranch
                              .collection('members')
                              .snapshots()
                        : null,
                    builder: (context, members) {
                      final personal = <String>{
                        for (final d
                            in contacts.data?.docs ??
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                          d.id,
                        for (final d
                            in members.data?.docs ??
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                          if (d.data()['active'] != false &&
                              txt(d.data(), 'status', 'active') == 'active')
                            d.id,
                      }..remove(me);
                      if (contacts.hasError || members.hasError) {
                        return Center(
                          child: Text(
                            accountError(contacts.error ?? members.error!),
                          ),
                        );
                      }
                      if (_tab == 0) {
                        return ListView(
                          children: [
                            if (CloudSyncService.ready)
                              ListTile(
                                leading: const Icon(CupertinoIcons.person_3),
                                title: Text(farmName()),
                                subtitle: Text(
                                  bi('Ranch group', 'பண்ணைக் குழு'),
                                ),
                                onTap: () => push(
                                  context,
                                  Scaffold(
                                    appBar: AppBar(title: Text(farmName())),
                                    body: const RanchChatScreen(),
                                  ),
                                ),
                              ),
                            for (final uid in personal) _person(uid),
                            if (personal.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  bi(
                                    'Add a person using search.',
                                    'தேடல் மூலம் ஒருவரைச் சேர்க்கலாம்.',
                                  ),
                                ),
                              ),
                          ],
                        );
                      }
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: db
                            .collection('direct_chats')
                            .where('participants', arrayContains: me)
                            .snapshots(),
                        builder: (context, chats) {
                          if (chats.hasError) {
                            return Center(
                              child: Text(accountError(chats.error!)),
                            );
                          }
                          if (!chats.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final peers = <String>{
                            for (final d in chats.data!.docs)
                              for (final p
                                  in (d.data()['participants'] as List))
                                if (p != me && !personal.contains(p)) '$p',
                          };
                          if (peers.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  bi(
                                    'Community conversations appear here.',
                                    'சமூகத்திலிருந்து வரும் உரையாடல்கள் இங்கே தோன்றும்.',
                                  ),
                                ),
                              ),
                            );
                          }
                          return ListView(
                            children: [for (final peer in peers) _person(peer)],
                          );
                        },
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class DirectChatScreen extends StatefulWidget {
  final String chatId, peer;
  const DirectChatScreen({super.key, required this.chatId, required this.peer});
  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final _text = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final id = FirebaseFirestore.instance
          .collection('direct_chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc()
          .id;
      await Hive.box('community_outbox').put(id, {
        'senderUid': signedInUid,
        'chatId': widget.chatId,
        'text': _text.text.trim(),
        'savedAt': DateTime.now().toIso8601String(),
      });
      _text.clear();
      AutoSyncService.markDirty(reason: 'private message');
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(bi('Chat', 'அரட்டை')),
      actions: [
        IconButton(
          tooltip: bi('Add to personal', 'தனிப்பட்ட அரட்டையில் சேர்'),
          icon: const Icon(CupertinoIcons.person_add),
          onPressed: () async {
            try {
              await DirectChatService.addPersonal(widget.peer);
              if (context.mounted) {
                snack(
                  context,
                  bi(
                    'Added to personal chat',
                    'தனிப்பட்ட அரட்டையில் சேர்க்கப்பட்டது',
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) snack(context, accountError(e));
            }
          },
        ),
      ],
    ),
    body: Shell(
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('direct_chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text(accountError(snap.error!)));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  reverse: true,
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final d in snap.data!.docs)
                      Align(
                        alignment: d.data()['senderUid'] == signedInUid
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Glass(child: Text(txt(d.data(), 'text'))),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          ValueListenableBuilder(
            valueListenable: Hive.box('community_outbox').listenable(),
            builder: (context, box, _) {
              final pending = box.values
                  .whereType<Map>()
                  .where(
                    (m) =>
                        m['senderUid'] == signedInUid &&
                        m['chatId'] == widget.chatId,
                  )
                  .toList();
              if (pending.isEmpty) return const SizedBox.shrink();
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final message in pending)
                      ListTile(
                        title: Text(txt(asMap(message), 'text')),
                        subtitle: Text(
                          bi(
                            'Saved · waiting to send',
                            'சேமிக்கப்பட்டது · அனுப்பக் காத்திருக்கிறது',
                          ),
                        ),
                        trailing: const Icon(CupertinoIcons.clock, size: 16),
                      ),
                  ],
                ),
              );
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_busy,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: fieldStyle(bi('Message', 'செய்தி')),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : _send,
                    icon: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(CupertinoIcons.arrow_up_circle_fill),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<DateTime?> choosePostTime(BuildContext context) async {
  final now = DateTime.now();
  final day = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
  );
  if (time == null || !context.mounted) return null;
  final result = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  if (!result.isAfter(DateTime.now())) {
    snack(
      context,
      bi('Choose a future time.', 'வருங்கால நேரத்தைத் தேர்ந்தெடுக்கவும்.'),
    );
    return null;
  }
  return result;
}

class MilkOriginScreen extends StatelessWidget {
  final Map<String, dynamic>? entry;
  const MilkOriginScreen({super.key, this.entry});
  @override
  Widget build(BuildContext context) {
    final rows = entry == null
        ? (vendorRows('vendor_entries')
              .where((r) => r['kind'] != 'payment' && r['kind'] != 'ranch')
              .toList()
            ..sort(
              (a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')),
            ))
        : [entry!];
    return Scaffold(
      appBar: AppBar(title: Text(bi('Milk sources', 'பால் வந்த விவரம்'))),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.all(21),
          children: [
            Text(
              bi(
                'Stock is pooled. These are the recorded inflows and outflows.',
                'பால் கலந்த இருப்பாக உள்ளது. இவை பதிவுசெய்யப்பட்ட வரவு–செலவு விவரங்கள்.',
              ),
              style: const TextStyle(color: Ink.muted),
            ),
            const SizedBox(height: 16),
            for (final row in rows)
              Builder(
                builder: (context) {
                  final sourceBox = txt(row, 'sourceBox');
                  final matches = Hive.isBoxOpen(sourceBox)
                      ? Hive.box(sourceBox).values.whereType<Map>().where(
                          (v) => v['cloudId'] == row['sourceId'],
                        )
                      : const <Map>[];
                  final source = matches.isEmpty
                      ? <String, dynamic>{}
                      : asMap(matches.first);
                  final purchase =
                      row['kind'] == 'purchase' || row['kind'] == 'collection';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Glass(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            purchase
                                ? (row['kind'] == 'collection'
                                      ? bi(
                                          'Collected from household',
                                          'வீட்டிலிருந்து சேகரித்த பால்',
                                        )
                                      : bi('Purchased milk', 'வாங்கிய பால்'))
                                : row['kind'] == 'ranch' &&
                                      sourceBox == 'milk_records'
                                ? bi('From ranch cows', 'பண்ணை மாடுகளிலிருந்து')
                                : bi(
                                    'Milk used / sold / adjusted',
                                    'பயன்படுத்திய / விற்ற / திருத்திய பால்',
                                  ),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text('${numv(row, 'quantity').toStringAsFixed(2)} L'),
                          Text('${txt(row, 'date')} · ${txt(row, 'time')}'),
                          if (purchase)
                            Text(
                              '${bi('Supplier', 'வழங்குநர்')}: ${txt(row, 'personName')}',
                            ),
                          if (!purchase)
                            Text(
                              '${bi('Cow / source', 'மாடு / மூலம்')}: ${txt(source, 'cow', txt(row, 'sourceCow', txt(row, 'personName')))}',
                            ),
                          if (!purchase)
                            Text(
                              '${txt(source, 'date', txt(row, 'sourceDate'))} ${txt(source, 'session', txt(row, 'sourceSession'))}',
                            ),
                          if (purchase)
                            Text(
                              '${bi('Price per litre', 'லிட்டர் விலை')}: ${money(numv(row, 'price'))}',
                            ),
                          if (purchase)
                            Text(
                              '${bi('Total', 'மொத்தம்')}: ${money(numv(row, 'amount'))} · ${bi('Paid', 'செலுத்தியது')}: ${money(numv(row, 'paid'))}',
                            ),
                          if (txt(row, 'notes').isNotEmpty)
                            Text(txt(row, 'notes')),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
