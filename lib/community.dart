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
                    style: TextStyle(color: Ink.violetDeep),
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
  final Color? _mentionColor;
  Color get mentionColor => _mentionColor ?? Ink.violetDeep;
  const MentionText(
    this.text, {
    super.key,
    this.mentions = const [],
    this.style,
    this._mentionColor,
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
            decoration: mentionColor == Ink.surface
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
              return const Center(child: CupertinoActivityIndicator());
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
                        style: TextStyle(color: Ink.muted, fontSize: 12),
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
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            txt(cow.data(), 'breed'),
                            style: TextStyle(color: Ink.muted),
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
          if (_busy) const Center(child: CupertinoActivityIndicator()),
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
                style: TextStyle(color: Ink.violetDeep),
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

  static CollectionReference<Map<String, dynamic>> get _hidden =>
      FirebaseFirestore.instance
          .collection('profiles')
          .doc(signedInUid)
          .collection('hidden_chats');

  /// Deletes a conversation from this person's own list only. The other
  /// person keeps theirs, and the chat comes back if a new message arrives.
  static Future<void> hide(String peer) => _hidden
      .doc(peer)
      .set({'hiddenAt': FieldValue.serverTimestamp()})
      .timeout(CloudSyncService.networkTimeout);

  static Future<void> unhide(String peer) =>
      _hidden.doc(peer).delete().timeout(CloudSyncService.networkTimeout);

  static Stream<QuerySnapshot<Map<String, dynamic>>> hiddenChats() =>
      _hidden.snapshots();

  /// Moves a personal contact back to business chats.
  static Future<void> removePersonal(String peer) => FirebaseFirestore.instance
      .collection('profiles')
      .doc(signedInUid)
      .collection('contacts')
      .doc(peer)
      .delete()
      .timeout(CloudSyncService.networkTimeout);

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

  /// Conversations this person deleted from their list, and when.
  final Map<String, DateTime> _hiddenAt = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _hiddenWatch;

  @override
  void initState() {
    super.initState();
    if (signedInUid.isEmpty) return;
    _hiddenWatch = DirectChatService.hiddenChats().listen((snap) {
      if (!mounted) return;
      setState(() {
        _hiddenAt
          ..clear()
          ..addAll({
            for (final d in snap.docs)
              d.id:
                  (d.data()['hiddenAt'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
          });
      });
    }, onError: (Object _) {});
  }

  /// A deleted chat stays out of the list until a newer message arrives.
  bool _hidden(String peer) {
    final at = _hiddenAt[peer];
    if (at == null) return false;
    final latest = _latest(peer);
    return latest == null || !latest.isAfter(at);
  }

  /// Long press on a person: delete the chat from this list, or move it
  /// between Business and Personal.
  Future<void> _actions(
    String peer,
    String name, {
    required bool personal,
    required bool ranchMember,
  }) async {
    selectionFeedback();
    final choice = await showAppleSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!personal)
                _SheetAction(
                  icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                  label: bi(
                    'Move to Personal chat',
                    'தனிப்பட்ட சாட்டுக்கு மாற்று',
                  ),
                  onTap: () => Navigator.of(sheet).pop('personal'),
                ),
              if (personal && !ranchMember)
                _SheetAction(
                  icon: CupertinoIcons.briefcase,
                  label: bi('Move to Business chat', 'வணிக சாட்டுக்கு மாற்று'),
                  onTap: () => Navigator.of(sheet).pop('business'),
                ),
              if (!ranchMember)
                _SheetAction(
                  icon: CupertinoIcons.trash,
                  label: bi('Delete chat', 'சாட்டை நீக்கு'),
                  destructive: true,
                  onTap: () => Navigator.of(sheet).pop('delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      switch (choice) {
        case 'personal':
          await DirectChatService.addPersonal(peer);
          if (mounted) {
            snack(
              context,
              bi(
                'Moved to Personal chat',
                'தனிப்பட்ட சாட்டுக்கு மாற்றப்பட்டது',
              ),
              tone: SnackTone.success,
            );
          }
        case 'business':
          await DirectChatService.removePersonal(peer);
          if (mounted) {
            snack(
              context,
              bi('Moved to Business chat', 'வணிக சாட்டுக்கு மாற்றப்பட்டது'),
              tone: SnackTone.success,
            );
          }
        case 'delete':
          await DirectChatService.hide(peer);
          if (mounted) {
            snack(
              context,
              bi('Chat deleted', 'சாட் நீக்கப்பட்டது'),
              tone: SnackTone.success,
              actionLabel: bi('Undo', 'திரும்பப் பெறு'),
              onAction: () => unawaited(
                DirectChatService.unhide(peer).catchError((Object _) {}),
              ),
            );
          }
      }
    } catch (e) {
      if (mounted) snack(context, accountError(e), tone: SnackTone.error);
    }
  }

  /// Newest message time per person, so the latest conversations sit at the
  /// top, as in Messages. One small listener per chat (its last message).
  final Map<String, DateTime> _lastAt = {};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _recency = {};

  @override
  void dispose() {
    _hiddenWatch?.cancel();
    for (final watch in _recency.values) {
      watch.cancel();
    }
    super.dispose();
  }

  void _watchRecency(Iterable<String> peers) {
    final me = signedInUid;
    if (me.isEmpty) return;
    for (final peer in peers) {
      if (_recency.containsKey(peer)) continue;
      _recency[peer] = FirebaseFirestore.instance
          .collection('direct_chats')
          .doc(DirectChatService.idFor(me, peer))
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots()
          .listen(
            (snap) {
              final at = snap.docs.firstOrNull?.data()['createdAt'];
              if (at is! Timestamp || !mounted) return;
              final time = at.toDate();
              if (_lastAt[peer] == time) return;
              setState(() => _lastAt[peer] = time);
            },
            // No conversation yet with this person.
            onError: (Object _) {},
          );
    }
  }

  /// Unsent messages waiting in the outbox count as the newest activity.
  DateTime? _latest(String peer) {
    final chat = DirectChatService.idFor(signedInUid, peer);
    var latest = _lastAt[peer];
    if (Hive.isBoxOpen('community_outbox')) {
      for (final value in Hive.box('community_outbox').values) {
        final row = asMap(value);
        if (row['chatId'] != chat) continue;
        final saved = DateTime.tryParse(txt(row, 'savedAt'));
        if (saved != null && (latest == null || saved.isAfter(latest))) {
          latest = saved;
        }
      }
    }
    return latest;
  }

  static DateTime? _ranchLatest() {
    if (!Hive.isBoxOpen('ranch_messages')) return null;
    DateTime? latest;
    for (final value in Hive.box('ranch_messages').values) {
      final at = DateTime.tryParse(txt(asMap(value), 'createdAt'));
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  /// Newest first; people without messages keep their order at the end.
  static List<T> _byRecent<T>(List<T> items, DateTime? Function(T) at) {
    final indexed = [
      for (final (i, item) in items.indexed) (i, item, at(item)),
    ];
    indexed.sort((a, b) {
      final x = a.$3, y = b.$3;
      if (x != null && y != null && x != y) return y.compareTo(x);
      if (x != null && y == null) return -1;
      if (x == null && y != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  static String _when(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final gap = today.difference(day).inDays;
    if (gap == 0) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    if (gap == 1) return bi('Yesterday', 'நேற்று');
    return '${local.day}/${local.month}';
  }

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

  Widget _person(
    String uid, {
    bool ranchMember = false,
    bool personal = false,
    String when = '',
  }) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
        when: when,
        onTap: () => _open(uid),
        onLongPress: () => _actions(
          uid,
          displayName,
          personal: personal,
          ranchMember: ranchMember,
        ),
      );
    },
  );
  @override
  Widget build(BuildContext context) {
    final me = signedInUid;
    if (me.isEmpty) {
      return SignInStatePanel(
        message: bi(
          'Sign in to see your chats.',
          'உங்கள் உரையாடல்களைப் பார்க்க உள்நுழையவும்.',
        ),
      );
    }
    final db = FirebaseFirestore.instance;
    // Opened from another page (not as the Chat tab): give it a title bar
    // with the back button.
    final pushed = !(ModalRoute.of(context)?.isFirst ?? true);
    final content = _chats(context, me, db);
    if (!pushed) return content;
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      appBar: AppBar(
        leading: const _BackButton(),
        title: Text(bi('Chat', 'சாட்')),
      ),
      body: content,
    );
  }

  Widget _chats(BuildContext context, String me, FirebaseFirestore db) {
    // Edge to edge: the chat lists pad themselves by the bottom inset.
    return Shell(
      edgeToEdge: true,
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
                        _watchRecency(personal);
                        final ranchAt = _ranchLatest();
                        const ranchKey = '\u0000ranch';
                        final ordered = _byRecent<String>([
                          if (CloudSyncService.ready) ranchKey,
                          ...personal.where(
                            (id) => memberIds.contains(id) || !_hidden(id),
                          ),
                        ], (id) => id == ranchKey ? ranchAt : _latest(id));
                        return ListView(
                          children: [
                            for (final id in ordered)
                              if (id == ranchKey)
                                _ChatRow(
                                  avatar: Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
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
                                  when: _when(ranchAt),
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
                                              style: TextStyle(
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
                                )
                              else
                                _person(
                                  id,
                                  ranchMember: memberIds.contains(id),
                                  personal: true,
                                  when: _when(_latest(id)),
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
                              child: CupertinoActivityIndicator(),
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
                          _watchRecency(peers);
                          final shown = peers.where((p) => !_hidden(p));
                          if (shown.isEmpty) {
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
                            children: [
                              for (final peer in _byRecent<String>(
                                shown.toList(),
                                _latest,
                              ))
                                _person(peer, when: _when(_latest(peer))),
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  bi(
                                    'Press and hold a person to delete the chat or move it to Personal.',
                                    'சாட்டை நீக்க அல்லது தனிப்பட்டதுக்கு மாற்ற, ஒருவரை அழுத்திப் பிடிக்கவும்.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Ink.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
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

  /// Time of the latest message ("14:05", "Yesterday", "12/10").
  final String when;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _ChatRow({
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.when = '',
    required this.onTap,
    this.onLongPress,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onLongPress: onLongPress,
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
                          style: TextStyle(
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
                          style: TextStyle(fontSize: 15, color: Ink.muted),
                        ),
                      ],
                    ),
                  ),
                  if (when.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    AppText(
                      when,
                      style: TextStyle(fontSize: 15, color: Ink.muted),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Icon(
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
        fontSize: 17,
        height: 1.3,
        color: mine ? Colors.white : Ink.navy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.surface,
    appBar: AppBar(
      centerTitle: true,
      toolbarHeight: 96,
      backgroundColor: Ink.surface.withValues(alpha: .96),
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
                      Icon(
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
              if (!snap.hasData) return const SkeletonList();
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
                        style: TextStyle(color: Ink.muted),
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

  void _explain(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialog) => AppleAlert(
      title: Text(bi('About milk stock', 'பால் இருப்பு பற்றி')),
      content: Text(
        bi(
          'All milk goes into one shared stock. This page lists every '
              'recorded movement into and out of it.',
          'எல்லா பாலும் ஒரே இருப்பில் சேரும். அதில் வந்த மற்றும் போன ஒவ்வொரு '
              'பதிவும் இங்கே உள்ளது.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: Text(bi('OK', 'சரி')),
        ),
      ],
    ),
  );

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
      appBar: AppBar(
        title: Text(bi('Milk sources', 'பால் வந்த விவரம்')),
        actions: [
          IconButton(
            tooltip: bi('About milk stock', 'பால் இருப்பு பற்றி'),
            icon: const Icon(CupertinoIcons.info_circle),
            onPressed: () => _explain(context),
          ),
        ],
      ),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.all(21),
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _MilkMovementCard(row: row),
              ),
          ],
        ),
      ),
    );
  }
}

/// One movement of milk into or out of the shared stock. The title says what
/// happened (bought, collected, sold, cleared, from ranch cows) and the detail
/// line names the other side in words that fit it: supplier, household,
/// customer, where the milk went, or the cow.
class _MilkMovementCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _MilkMovementCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final kind = txt(row, 'kind');
    final sourceBox = txt(row, 'sourceBox');
    final matches = Hive.isBoxOpen(sourceBox)
        ? Hive.box(sourceBox).values.whereType<Map>().where(
            (v) => v['cloudId'] == row['sourceId'],
          )
        : const <Map>[];
    final source = matches.isEmpty ? <String, dynamic>{} : asMap(matches.first);
    final purchase = kind == 'purchase' || kind == 'collection';
    final fromCows = kind == 'ranch' && sourceBox == 'milk_records';
    final name = vendorEntryPersonName(row);
    final cow = txt(source, 'cow', txt(row, 'sourceCow'));
    final (String title, String party) = switch (kind) {
      'collection' => (
        bi('Collected milk', 'சேகரித்த பால்'),
        '${bi('From', 'யாரிடமிருந்து')}: $name',
      ),
      'purchase' => (
        bi('Bought milk', 'வாங்கிய பால்'),
        '${bi('Supplier', 'வழங்குநர்')}: $name',
      ),
      'sale' => (
        bi('Sold milk', 'விற்ற பால்'),
        '${bi('Customer', 'வாடிக்கையாளர்')}: $name',
      ),
      'clearance' => (
        bi('Milk cleared', 'கிளியர் செய்த பால்'),
        '${bi('Moved to', 'எங்கே')}: $name',
      ),
      _ when fromCows => (
        bi('Milk from ranch cows', 'பண்ணை மாடுகளின் பால்'),
        '${bi('Cow', 'மாடு')}: ${cow.isEmpty ? name : cow}',
      ),
      'ranch' => (
        bi('Ranch milk adjusted', 'பண்ணை பால் திருத்தம்'),
        name.isEmpty ? '' : '${bi('Record', 'பதிவு')}: $name',
      ),
      _ => (bi('Stock adjusted', 'இருப்பு திருத்தம்'), name),
    };
    final sourceWhen =
        '${txt(source, 'date', txt(row, 'sourceDate'))} ${txt(source, 'session', txt(row, 'sourceSession'))}'
            .trim();
    final muted = TextStyle(color: Ink.muted, fontSize: 15);
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: AppText(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Ink.navy,
                  ),
                ),
              ),
              AppText(
                '${numv(row, 'quantity').toStringAsFixed(2)} L',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Ink.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (party.isNotEmpty)
            AppText(party, style: TextStyle(fontSize: 15, color: Ink.body)),
          AppText('${txt(row, 'date')} · ${txt(row, 'time')}', style: muted),
          if (fromCows && sourceWhen.isNotEmpty)
            AppText('${bi('Milked', 'கறந்தது')}: $sourceWhen', style: muted),
          if (purchase)
            AppText(
              '${bi('Price per litre', 'லிட்டர் விலை')}: ${money(numv(row, 'price'))}',
              style: muted,
            ),
          if (purchase)
            AppText(
              '${bi('Total', 'மொத்தம்')}: ${money(numv(row, 'amount'))} · ${bi('Paid', 'செலுத்தியது')}: ${money(numv(row, 'paid'))}',
              style: muted,
            ),
          if (txt(row, 'notes').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(txt(row, 'notes'), style: muted),
            ),
        ],
      ),
    );
  }
}

/// One row of a long-press action sheet: a symbol and a label, red when it
/// removes something.
class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Ink.redText : Ink.violetDeep;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        radius: Gold.r21,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Semantics(
          button: true,
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
