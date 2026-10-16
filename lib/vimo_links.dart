part of 'main.dart';

// -----------------------------------------------------------------------------
//  VIMO ID links
//
//  A vendor can link a customer or supplier to that person's VIMO ID (their
//  username, or a Ranch ID). The person who was added sees a short message at
//  the top of VIMO and answers once: accept or reject. Only names travel in
//  the request (link_requests/{vendorUid}__{personId}); no records or money.
//  Messages between linked people appear in Business chat.
// -----------------------------------------------------------------------------

/// A VIMO ID found while typing: a person (username) or a ranch.
class VimoIdMatch {
  final String id, uid, kind, name, photo;
  const VimoIdMatch({
    required this.id,
    required this.uid,
    required this.kind,
    this.name = '',
    this.photo = '',
  });
  bool get ranch => kind == 'ranch';
}

class VimoLinks {
  const VimoLinks._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _links =>
      _db.collection('link_requests');

  /// Linking needs a signed-in account with cloud access.
  static bool get available => firebaseReady && signedInUid.isNotEmpty;

  static String normalize(String input) =>
      input.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();

  static String docId(String personId) => '${signedInUid}__$personId';

  static DocumentReference<Map<String, dynamic>> ref(String personId) =>
      _links.doc(docId(personId));

  /// IDs that start with what was typed: people first, then ranches.
  static Future<List<VimoIdMatch>> suggest(String input) async {
    final q = normalize(input);
    if (q.length < 2 || !available) return const [];
    Future<QuerySnapshot<Map<String, dynamic>>> prefix(
      Query<Map<String, dynamic>> query,
    ) => query
        .startAt([q])
        .endAt(['$q'])
        .limit(6)
        .get()
        .timeout(CloudSyncService.networkTimeout);
    try {
      final found = await Future.wait([
        prefix(_db.collection('profiles').orderBy('username')),
        prefix(_db.collection('ranch_ids').orderBy(FieldPath.documentId)),
      ]);
      return [
        for (final d in found[0].docs)
          if (d.id != signedInUid && txt(d.data(), 'username').isNotEmpty)
            VimoIdMatch(
              id: txt(d.data(), 'username'),
              uid: d.id,
              kind: 'person',
              name: txt(d.data(), 'displayName'),
              photo: txt(d.data(), 'photo'),
            ),
        for (final d in found[1].docs)
          if (txt(d.data(), 'ownerUid').isNotEmpty &&
              txt(d.data(), 'ownerUid') != signedInUid)
            VimoIdMatch(
              id: d.id,
              uid: txt(d.data(), 'ownerUid'),
              kind: 'ranch',
              name: txt(d.data(), 'farmName'),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The person or ranch behind an exact VIMO ID, or null if there is none.
  static Future<VimoIdMatch?> resolve(String input) async {
    final id = normalize(input);
    if (id.isEmpty || !available) return null;
    final person = await _db
        .collection('usernames')
        .doc(id)
        .get()
        .timeout(CloudSyncService.networkTimeout);
    final uid = txt(person.data() ?? {}, 'uid');
    if (person.exists && uid.isNotEmpty) {
      return VimoIdMatch(id: id, uid: uid, kind: 'person');
    }
    final ranch = await _db
        .collection('ranch_ids')
        .doc(id)
        .get()
        .timeout(CloudSyncService.networkTimeout);
    final owner = txt(ranch.data() ?? {}, 'ownerUid');
    if (ranch.exists && owner.isNotEmpty) {
      return VimoIdMatch(
        id: id,
        uid: owner,
        kind: 'ranch',
        name: txt(ranch.data()!, 'farmName'),
      );
    }
    return null;
  }

  static String get _myName {
    final name = accountFullName.isNotEmpty
        ? accountFullName
        : currentUserName();
    final handle = accountUsername.isEmpty ? '' : ' · @$accountUsername';
    final full = '${name.trim().isEmpty ? 'VIMO' : name.trim()}$handle';
    return full.length > 80 ? full.substring(0, 80) : full;
  }

  /// Sends (or sends again) the request to [match] for a vendor person.
  /// Firestore keeps the write on the phone until it reaches the server, so
  /// with weak signal it is sent later rather than lost.
  static Future<void> request(
    Map<String, dynamic> person,
    VimoIdMatch match,
  ) async {
    final name = txt(person, 'name', 'Customer');
    await ref(txt(person, 'id')).set({
      'fromUid': signedInUid,
      'fromName': _myName,
      'toUid': match.uid,
      'toId': match.id,
      'toKind': match.kind,
      'personName': name.length > 80 ? name.substring(0, 80) : name,
      'role': txt(person, 'kind') == 'supplier' ? 'supplier' : 'customer',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> remove(String personId) => ref(personId).delete();

  /// Requests waiting for this account's answer.
  static Stream<QuerySnapshot<Map<String, dynamic>>> incoming() => _links
      .where('toUid', isEqualTo: signedInUid)
      .where('status', isEqualTo: 'pending')
      .snapshots();

  /// Like [request], the answer is kept on the phone until it is delivered.
  static Future<void> answer(String linkId, {required bool accept}) =>
      _links.doc(linkId).update({
        'status': accept ? 'accepted' : 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });
}

/// Shows a message once a background write has failed (the screen that
/// started it may be gone by then).
void _linkProblem(Object error) {
  final context = rootMessengerKey.currentContext;
  if (context != null && context.mounted) snack(context, accountError(error));
}

/// The VIMO ID field on a vendor person. Matching IDs are listed inside the
/// form, right under the field (never floating over other fields), and an
/// exact match stays listed with a checkmark so the person can be confirmed.
/// The link's state shows underneath once saved (waiting, linked, or
/// rejected with a hint that another person may have been chosen).
class VimoIdField extends StatefulWidget {
  final TextEditingController controller;
  final Map<String, dynamic>? person;
  final ValueChanged<VimoIdMatch?> onMatch;
  const VimoIdField({
    super.key,
    required this.controller,
    required this.person,
    required this.onMatch,
  });

  @override
  State<VimoIdField> createState() => _VimoIdFieldState();
}

class _VimoIdFieldState extends State<VimoIdField> {
  Timer? _debounce;
  int _query = 0;
  bool _searching = false;
  String _searched = '';
  List<VimoIdMatch> _found = const [];
  VimoIdMatch? _chosen;

  @override
  void initState() {
    super.initState();
    final saved = txt(widget.person ?? {}, 'vimoId');
    if (saved.isNotEmpty) {
      _chosen = VimoIdMatch(
        id: saved,
        uid: txt(widget.person!, 'vimoUid'),
        kind: txt(widget.person!, 'vimoKind', 'person'),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String value) {
    final typed = VimoLinks.normalize(value);
    if (_chosen != null && _chosen!.id != typed) {
      _chosen = null;
      widget.onMatch(null);
    }
    _debounce?.cancel();
    final asked = ++_query;
    if (typed.length < 2) {
      setState(() {
        _searching = false;
        _searched = '';
        _found = const [];
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final found = await VimoLinks.suggest(typed);
      if (!mounted || asked != _query) return;
      setState(() {
        _searching = false;
        _searched = typed;
        _found = found;
        // Typing the whole ID picks that person without another tap.
        final exact = found.where((m) => m.id == typed).firstOrNull;
        if (exact != null && _chosen?.id != exact.id) {
          _chosen = exact;
          widget.onMatch(exact);
        }
      });
    });
  }

  void _pick(VimoIdMatch match) {
    HapticFeedback.selectionClick();
    widget.controller.value = TextEditingValue(
      text: match.id,
      selection: TextSelection.collapsed(offset: match.id.length),
    );
    setState(() {
      _chosen = match;
      _found = [match];
      _searched = match.id;
    });
    widget.onMatch(match);
  }

  @override
  Widget build(BuildContext context) {
    final personId = txt(widget.person ?? {}, 'id');
    final savedId = txt(widget.person ?? {}, 'vimoId');
    final typed = VimoLinks.normalize(widget.controller.text);
    final showNone =
        !_searching &&
        _found.isEmpty &&
        typed.length >= 3 &&
        _searched == typed &&
        _chosen?.id != typed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          maxLength: 40,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          decoration: fieldStyle(
            bi('VIMO ID · optional', 'VIMO ID · விருப்பம்'),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Text(
                '@',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Ink.violetDeep,
                ),
              ),
            ),
            suffix: _searching
                ? const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: CupertinoActivityIndicator(radius: 9),
                  )
                : null,
          ),
          onChanged: _changed,
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _found.isEmpty && !showNone
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Glass(
                    radius: 21,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: showNone
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Text(
                              bi(
                                'No VIMO ID starts with "@$typed".',
                                '"@$typed" என்று தொடங்கும் VIMO ID இல்லை.',
                              ),
                              style: TextStyle(color: Ink.muted),
                            ),
                          )
                        : Column(
                            children: [
                              for (final (i, m) in _found.indexed) ...[
                                if (i > 0)
                                  Divider(
                                    height: .5,
                                    thickness: .5,
                                    indent: 72,
                                    color: Ink.separator,
                                  ),
                                _VimoIdRow(
                                  match: m,
                                  chosen: _chosen?.id == m.id,
                                  onTap: () => _pick(m),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
        ),
        if (personId.isNotEmpty && savedId.isNotEmpty && VimoLinks.available)
          _VimoLinkStatus(personId: personId, vimoId: savedId),
      ],
    );
  }
}

class _VimoIdRow extends StatelessWidget {
  final VimoIdMatch match;
  final bool chosen;
  final VoidCallback onTap;
  const _VimoIdRow({
    required this.match,
    required this.chosen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chosen,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: [
            match.ranch
                ? CircleAvatar(
                    radius: 22,
                    backgroundColor: Ink.lavender,
                    child: Icon(
                      CupertinoIcons.house_fill,
                      size: 19,
                      color: Ink.violetDeep,
                    ),
                  )
                : profileAvatar(
                    match.photo,
                    radius: 22,
                    label: match.name.isEmpty ? match.id : match.name,
                  ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${match.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Ink.navy,
                    ),
                  ),
                  Text(
                    [
                      if (match.name.isNotEmpty) match.name,
                      match.ranch ? bi('Ranch', 'பண்ணை') : bi('Person', 'நபர்'),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: Ink.muted),
                  ),
                ],
              ),
            ),
            if (chosen)
              Icon(
                CupertinoIcons.checkmark_alt_circle_fill,
                color: Ink.violetDeep,
                size: 24,
              ),
          ],
        ),
      ),
    ),
  );
}

class _VimoLinkStatus extends StatelessWidget {
  final String personId, vimoId;
  const _VimoLinkStatus({required this.personId, required this.vimoId});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: VimoLinks.ref(personId).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data();
          if (data == null) return const SizedBox.shrink();
          final status = txt(data, 'status');
          final (IconData icon, Color color, String text) = switch (status) {
            'accepted' => (
              CupertinoIcons.checkmark_seal_fill,
              Ink.greenText,
              bi('Linked with @$vimoId', '@$vimoId உடன் இணைக்கப்பட்டது'),
            ),
            'rejected' => (
              CupertinoIcons.xmark_circle_fill,
              Ink.redText,
              bi(
                '@$vimoId said no. Maybe you chose a different person: '
                    'check the ID and save again.',
                '@$vimoId மறுத்தார். வேறு நபரைத் தேர்ந்திருக்கலாம்: ID-ஐச் '
                    'சரிபார்த்து மீண்டும் சேமிக்கவும்.',
              ),
            ),
            _ => (
              CupertinoIcons.clock_fill,
              Ink.amberText,
              bi(
                'Waiting for @$vimoId to approve',
                '@$vimoId ஒப்புதலுக்காகக் காத்திருக்கிறது',
              ),
            ),
          };
          return Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                if (status == 'accepted')
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(44, 30),
                    onPressed: () async {
                      try {
                        final peer = txt(data, 'toUid');
                        final chat = await DirectChatService.open(peer);
                        if (context.mounted) {
                          await push(
                            context,
                            DirectChatScreen(chatId: chat, peer: peer),
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          snack(context, accountError(error));
                        }
                      }
                    },
                    child: Text(
                      bi('Message', 'செய்தி'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Ink.violetDeep,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

/// A short message at the top of VIMO when someone added this account as
/// their milk customer or supplier: accept or reject, once.
class LinkRequestBanner extends StatefulWidget {
  const LinkRequestBanner({super.key});

  @override
  State<LinkRequestBanner> createState() => _LinkRequestBannerState();
}

class _LinkRequestBannerState extends State<LinkRequestBanner> {
  final Set<String> _answering = {};

  /// The banner goes as soon as the answer is given: the listener sees the
  /// change on the phone at once, and the server copy follows.
  void _answer(String id, String from, bool accept) {
    setState(() => _answering.add(id));
    HapticFeedback.selectionClick();
    VimoLinks.answer(id, accept: accept).catchError((Object error) {
      if (mounted) setState(() => _answering.remove(id));
      _linkProblem(error);
    });
    if (accept) {
      snack(context, bi('Linked with $from', '$from உடன் இணைக்கப்பட்டது'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!VimoLinks.available) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: VimoLinks.incoming(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final reduce = MediaQuery.disableAnimationsOf(context);
        final doc = docs.isEmpty ? null : docs.first;
        return AnimatedSwitcher(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -.3),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: doc == null
              ? const SizedBox.shrink(key: ValueKey('none'))
              : _request(doc.id, doc.data(), docs.length),
        );
      },
    );
  }

  Widget _request(String id, Map<String, dynamic> data, int count) {
    final from = txt(data, 'fromName', 'VIMO');
    final supplier = data['role'] == 'supplier';
    final busy = _answering.contains(id);
    return Padding(
      key: ValueKey(id),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: LiquidGlass(
            radius: 26,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    MilkVendorIcon(size: 28, color: Ink.violetDeep),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppText(
                        supplier
                            ? bi(
                                '$from added you as their milk supplier.',
                                '$from உங்களைத் தங்கள் பால் வழங்குநராகச் சேர்த்துள்ளார்.',
                              )
                            : bi(
                                '$from added you as their milk customer.',
                                '$from உங்களைத் தங்கள் பால் வாடிக்கையாளராகச் சேர்த்துள்ளார்.',
                              ),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Ink.navy,
                        ),
                      ),
                    ),
                    if (count > 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '1/$count',
                          style: TextStyle(color: Ink.muted, fontSize: 13),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 38),
                  child: AppText(
                    supplier
                        ? bi(
                            'Do you supply milk to them?',
                            'நீங்கள் அவருக்குப் பால் தருகிறீர்களா?',
                          )
                        : bi(
                            'Do you buy milk from them?',
                            'நீங்கள் அவரிடம் பால் வாங்குகிறீர்களா?',
                          ),
                    style: TextStyle(fontSize: 13, color: Ink.muted),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: bi('Reject', 'இல்லை'),
                        color: Ink.redText,
                        onPressed: busy ? null : () => _answer(id, from, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LiquidButton(
                        label: bi('Accept', 'ஆம்'),
                        height: 50,
                        busy: busy,
                        onPressed: () => _answer(id, from, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
