part of 'main.dart';

String get signedInUid =>
    firebaseReady ? FirebaseAuth.instance.currentUser?.uid ?? '' : '';

final Expando<List<Map<String, dynamic>>> mentionSelections =
    Expando<List<Map<String, dynamic>>>('vimoMentions');

class MentionInput extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool ranchOnly;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final bool bare;
  const MentionInput({
    super.key,
    required this.controller,
    required this.hint,
    this.bare = false,
    this.ranchOnly = false,
    this.minLines = 1,
    this.maxLines = 5,
    this.maxLength,
  });
  @override
  State<MentionInput> createState() => _MentionInputState();
}

class _MentionInputState extends State<MentionInput> {
  Timer? _timer;
  List<Map<String, dynamic>> _people = const [];
  int _start = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    _timer?.cancel();
    final selection = widget.controller.selection;
    final cursor = selection.isValid
        ? selection.baseOffset
        : widget.controller.text.length;
    final before = widget.controller.text.substring(
      0,
      cursor.clamp(0, widget.controller.text.length),
    );
    final match = RegExp(r'(?:^|\s)@([a-zA-Z0-9_]*)$').firstMatch(before);
    if (match == null) {
      if (_people.isNotEmpty) setState(() => _people = const []);
      return;
    }
    _start = match.start + (match.group(0)!.startsWith(' ') ? 1 : 0);
    final query = (match.group(1) ?? '').toLowerCase();
    _timer = Timer(const Duration(milliseconds: 220), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!firebaseReady || signedInUid.isEmpty) return;
    try {
      final db = FirebaseFirestore.instance;
      final ids = <String>{};
      if (widget.ranchOnly && CloudSyncService.ready) {
        final members = await CloudSyncService.ranch
            .collection('members')
            .limit(40)
            .get();
        ids.addAll(
          members.docs
              .where((d) => d.data()['active'] != false)
              .map((d) => d.id),
        );
      } else {
        final following = await db
            .collection('profiles')
            .doc(signedInUid)
            .collection('following')
            .limit(40)
            .get();
        final followers = await db
            .collection('profiles')
            .doc(signedInUid)
            .collection('followers')
            .limit(40)
            .get();
        ids.addAll([...following.docs, ...followers.docs].map((d) => d.id));
        final search = await db
            .collection('profiles')
            .orderBy('username')
            .startAt([query])
            .endAt(['$query\uf8ff'])
            .limit(12)
            .get();
        ids.addAll(search.docs.map((d) => d.id));
      }
      ids.remove(signedInUid);
      final docs = await Future.wait(
        ids.take(40).map((id) => db.collection('profiles').doc(id).get()),
      );
      final people = <Map<String, dynamic>>[
        for (final doc in docs)
          if (doc.exists &&
              (query.isEmpty ||
                  txt(doc.data()!, 'username').toLowerCase().contains(query)))
            {...doc.data()!, 'uid': doc.id},
      ]..sort((a, b) => txt(a, 'username').compareTo(txt(b, 'username')));
      if (mounted) setState(() => _people = people.take(5).toList());
    } catch (_) {
      if (mounted) setState(() => _people = const []);
    }
  }

  void _select(Map<String, dynamic> person) {
    final username = txt(person, 'username');
    if (username.isEmpty || _start < 0) return;
    final value = widget.controller.value;
    final cursor = value.selection.isValid
        ? value.selection.baseOffset
        : value.text.length;
    final text = value.text.replaceRange(_start, cursor, '$username ');
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: _start + username.length + 1),
    );
    final selected = [...?mentionSelections[widget.controller]];
    if (!selected.any((item) => txt(item, 'uid') == txt(person, 'uid'))) {
      selected.add({'uid': txt(person, 'uid'), 'username': username});
    }
    mentionSelections[widget.controller] = selected;
    setState(() => _people = const []);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: widget.controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                null,
        textCapitalization: TextCapitalization.sentences,
        decoration: widget.bare
            ? bareFieldStyle(widget.hint)
            : InputDecoration(hintText: widget.hint),
      ),
      if (_people.isNotEmpty)
        Glass(
          radius: Gold.r21,
          opacity: .96,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final person in _people)
                ListTile(
                  dense: true,
                  leading: profileAvatar(txt(person, 'photo'), radius: 18),
                  title: Text(
                    txt(person, 'displayName', txt(person, 'username')),
                  ),
                  subtitle: Text(
                    txt(person, 'username'),
                    style: const TextStyle(color: Ink.violetDeep),
                  ),
                  onTap: () => _select(person),
                ),
            ],
          ),
        ),
    ],
  );
}

class MentionText extends StatelessWidget {
  final String text;
  final List<dynamic> mentions;
  final TextStyle? style;
  final Color mentionColor;
  const MentionText(
    this.text, {
    super.key,
    this.mentions = const [],
    this.style,
    this.mentionColor = Ink.violetDeep,
  });
  @override
  Widget build(BuildContext context) {
    final byName = <String, String>{
      for (final raw in mentions.whereType<Map>())
        if (txt(asMap(raw), 'username').isNotEmpty)
          txt(asMap(raw), 'username'): txt(asMap(raw), 'uid'),
    };
    if (byName.isEmpty) return Text(text, style: style);
    final names = byName.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final pattern = RegExp('\\b(${names.map(RegExp.escape).join('|')})\\b');
    final spans = <TextSpan>[];
    var end = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > end)
        spans.add(TextSpan(text: text.substring(end, match.start)));
      final name = match.group(0)!;
      spans.add(
        TextSpan(
          text: name,
          style: TextStyle(
            color: mentionColor,
            fontWeight: FontWeight.w700,
            decoration: mentionColor == Colors.white
                ? TextDecoration.underline
                : null,
            decorationColor: mentionColor,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () =>
                push(context, SocialProfileScreen(uid: byName[name]!)),
        ),
      );
      end = match.end;
    }
    if (end < text.length) spans.add(TextSpan(text: text.substring(end)));
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.merge(style),
        children: spans,
      ),
    );
  }
}

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

/// Borderless field for use inside a capsule composer.
InputDecoration bareFieldStyle(String hint) => InputDecoration(
  hintText: hint,
  isDense: true,
  filled: false,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
);

/// "My ranch" belongs to the owner; visitors see a neutral ranch title.
String publicRanchTitle(String name, {required bool own}) {
  final clean = name.trim();
  final generic = clean.isEmpty || clean.toLowerCase() == 'my ranch';
  if (own) return generic ? bi('My ranch', 'என் பண்ணை') : clean;
  return generic ? bi('Ranch', 'பண்ணை') : clean;
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
    final grid = txt(profile, 'ranchLayout', 'grid') == 'grid';
    final own = uid == signedInUid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const CowMark(size: 32),
          title: Text(
            publicRanchTitle(txt(profile, 'ranchName'), own: own),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: own
              ? SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(CupertinoIcons.list_bullet),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(CupertinoIcons.square_grid_2x2),
                    ),
                  ],
                  selected: {grid},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) async {
                    try {
                      await FirebaseFirestore.instance
                          .collection('profiles')
                          .doc(uid)
                          .set({
                            'ranchLayout': value.first ? 'grid' : 'list',
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true))
                          .timeout(CloudSyncService.networkTimeout);
                    } catch (e) {
                      if (context.mounted) snack(context, accountError(e));
                    }
                  },
                )
              : null,
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
            Widget cowCard(QueryDocumentSnapshot<Map<String, dynamic>> cow) {
              final photo = txt(cow.data(), 'photo');
              final portrait = ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: photo.isEmpty
                    ? const ColoredBox(
                        color: Color(0x0D6C4ED4),
                        child: Center(child: CowMark(size: 50)),
                      )
                    : Image.memory(
                        socialPhotoBytes(photo),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) =>
                            const Center(child: CowMark(size: 50)),
                      ),
              );
              if (grid) {
                return Glass(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: portrait,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        txt(cow.data(), 'name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        txt(cow.data(), 'breed'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Ink.muted, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }
              return Glass(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(width: 76, height: 76, child: portrait),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            txt(cow.data(), 'name'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            txt(cow.data(), 'breed'),
                            style: const TextStyle(color: Ink.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            if (grid) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: .78,
                ),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (_, index) => cowCard(snapshot.data!.docs[index]),
              );
            }
            return Column(
              children: [
                for (final cow in snapshot.data!.docs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: cowCard(cow),
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
              subtitle: Text(
                txt(person.data(), 'username'),
                style: const TextStyle(color: Ink.violetDeep),
              ),
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

  Widget _person(String uid, {bool ranchMember = false}) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('profiles')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? const <String, dynamic>{};
          final displayName = txt(
            data,
            'displayName',
            txt(data, 'username', bi('VIMO member', 'VIMO உறுப்பினர்')),
          );
          return _ChatRow(
            avatar: profileAvatar(
              txt(data, 'photo'),
              radius: 26,
              label: displayName,
            ),
            title: displayName,
            subtitle: ranchMember
                ? bi('Ranch member', 'பண்ணை உறுப்பினர்')
                : txt(data, 'username'),
            onTap: () => _open(uid),
          );
        },
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
                      bi('Personal chat', 'தனிப்பட்ட சாட்'),
                      bi('Business chat', 'வணிக சாட்'),
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
                      final memberIds = <String>{
                        for (final d
                            in members.data?.docs ??
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                          if (d.data()['active'] != false &&
                              txt(d.data(), 'status', 'active') == 'active')
                            d.id,
                      };
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
                              _ChatRow(
                                avatar: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Ink.violet, Ink.violetDeep],
                                    ),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.person_3_fill,
                                    color: Colors.white,
                                  ),
                                ),
                                title: farmName(),
                                subtitle: bi('Ranch group', 'பண்ணைக் குழு'),
                                onTap: () => push(
                                  context,
                                  Scaffold(
                                    appBar: AppBar(
                                      title: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            bi('Chat', 'சாட்'),
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            farmName(),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Ink.violetDeep,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    body: const RanchChatScreen(),
                                  ),
                                ),
                              ),
                            for (final uid in personal)
                              _person(
                                uid,
                                ranchMember: memberIds.contains(uid),
                              ),
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

/// Messages-style list row: avatar, name, detail and a quiet chevron.
class _ChatRow extends StatelessWidget {
  final Widget avatar;
  final String title, subtitle;
  final VoidCallback onTap;
  const _ChatRow({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(bottom: 12, top: 2),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Ink.faint.withValues(alpha: .22),
                    width: .6,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Ink.navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AppText(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Ink.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    CupertinoIcons.chevron_right,
                    size: 15,
                    color: Ink.faint,
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

  String _clock(dynamic stamp) {
    final time = stamp is Timestamp ? stamp.toDate() : null;
    if (time == null) return '';
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  void _openProfile() => push(context, SocialProfileScreen(uid: widget.peer));

  Widget _messageBody(String text, bool mine) {
    final shared = ShareCard.decode(text);
    if (shared != null) return ShareCardBubble(card: shared, mine: mine);
    return Text(
      text,
      style: TextStyle(
        fontSize: 18,
        height: 1.3,
        color: mine ? Colors.white : Ink.navy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      centerTitle: true,
      toolbarHeight: 96,
      backgroundColor: Colors.white.withValues(alpha: .96),
      title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('profiles')
            .doc(widget.peer)
            .snapshots(),
        builder: (context, profile) {
          final data = profile.data?.data() ?? const <String, dynamic>{};
          final name = txt(
            data,
            'displayName',
            txt(data, 'username', bi('Chat', 'சாட்')),
          );
          return Semantics(
            button: true,
            label: bi('Open profile', 'ப்ரொஃபைலைத் திற'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openProfile,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  profileAvatar(txt(data, 'photo'), radius: 27, label: name),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        CupertinoIcons.chevron_right,
                        size: 13,
                        color: Ink.faint,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
    body: Column(
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
                return const Center(child: CupertinoActivityIndicator());
              }
              return ValueListenableBuilder(
                valueListenable: Hive.box('community_outbox').listenable(),
                builder: (context, box, _) {
                  final pending = box.values
                      .whereType<Map>()
                      .where(
                        (m) =>
                            m['senderUid'] == signedInUid &&
                            m['chatId'] == widget.chatId,
                      )
                      .toList()
                      .reversed;
                  final docs = snap.data!.docs;
                  if (docs.isEmpty && pending.isEmpty) {
                    return Center(
                      child: Text(
                        bi('Say hello 👋', 'வணக்கம் சொல்லுங்கள் 👋'),
                        style: const TextStyle(color: Ink.muted),
                      ),
                    );
                  }
                  return ListView(
                    reverse: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    children: [
                      for (final message in pending)
                        AppleBubble(
                          mine: true,
                          pending: true,
                          child: _messageBody(
                            txt(asMap(message), 'text'),
                            true,
                          ),
                        ),
                      for (final d in docs)
                        Builder(
                          builder: (_) {
                            final mine = d.data()['senderUid'] == signedInUid;
                            return AppleBubble(
                              mine: mine,
                              time: _clock(d.data()['createdAt']),
                              child: _messageBody(txt(d.data(), 'text'), mine),
                            );
                          },
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: AppleComposer(
              field: TextField(
                controller: _text,
                enabled: !_busy,
                maxLength: 2000,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: bareFieldStyle(bi('Message', 'செய்தி')),
              ),
              trailing: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (_, value, _) => IconButton(
                  tooltip: ui('Send'),
                  onPressed: _busy || value.text.trim().isEmpty ? null : _send,
                  icon: _busy
                      ? const CupertinoActivityIndicator()
                      : Icon(
                          CupertinoIcons.arrow_up_circle_fill,
                          size: 32,
                          color: value.text.trim().isEmpty
                              ? Ink.faint
                              : Ink.violetDeep,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
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
                          AppText(
                            '${numv(row, 'quantity').toStringAsFixed(2)} L',
                          ),
                          AppText('${txt(row, 'date')} · ${txt(row, 'time')}'),
                          if (purchase)
                            AppText(
                              '${bi('Supplier', 'வழங்குநர்')}: ${txt(row, 'personName')}',
                            ),
                          if (!purchase)
                            AppText(
                              '${bi('Cow / source', 'மாடு / மூலம்')}: ${txt(source, 'cow', txt(row, 'sourceCow', txt(row, 'personName')))}',
                            ),
                          if (!purchase)
                            AppText(
                              '${txt(source, 'date', txt(row, 'sourceDate'))} ${txt(source, 'session', txt(row, 'sourceSession'))}',
                            ),
                          if (purchase)
                            AppText(
                              '${bi('Price per litre', 'லிட்டர் விலை')}: ${money(numv(row, 'price'))}',
                            ),
                          if (purchase)
                            AppText(
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
