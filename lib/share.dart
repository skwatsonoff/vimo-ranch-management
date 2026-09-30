part of 'main.dart';

// -----------------------------------------------------------------------------
//  Sharing posts, profiles and animals into chats.
//
//  A share travels as ordinary message text: a readable first line followed by
//  a compact encoded card. Ranch chat and private chats therefore need no new
//  message fields. An animal card opens the full profile for people in the
//  same ranch; everyone else sees only its photo, name, breed and age.
// -----------------------------------------------------------------------------

const _shareMarker = '⁣vimo:';

class ShareCard {
  final Map<String, dynamic> data;
  const ShareCard(this.data);

  String get kind => txt(data, 'k');

  static ShareCard post(SocialPostRecord post) {
    final d = post.data();
    final text = txt(d, 'text').trim();
    return ShareCard({
      'k': 'post',
      'p': post.id,
      'n': txt(d, 'authorName', txt(d, 'authorUsername')),
      'h': txt(d, 'authorUsername'),
      'x': text.length > 140 ? '${text.substring(0, 140)}…' : text,
      'ph': txt(d, 'photo').isNotEmpty,
    });
  }

  static ShareCard profile(String uid, Map<String, dynamic> profile) =>
      ShareCard({
        'k': 'profile',
        'u': uid,
        'n': txt(profile, 'displayName', txt(profile, 'username')),
        'h': txt(profile, 'username'),
        'pl': txt(profile, 'place'),
      });

  static ShareCard animal(Map<String, dynamic> a, {String cardId = ''}) =>
      ShareCard({
        'k': 'animal',
        'r': ranchId(),
        'i': txt(a, 'id'),
        'n': txt(a, 'name'),
        'ne': txt(a, 'nameEnglish'),
        'nt': txt(a, 'nameTamil'),
        't': txt(a, 'type'),
        'b': txt(a, 'breed'),
        'g': txt(a, 'gender', 'Female'),
        'u': maleUseOf(a),
        'd': txt(a, 'dob'),
        'y': toInt(a['ageYears']),
        'm': toInt(a['ageMonths']),
        'dd': toInt(a['ageDays']),
        if (cardId.isNotEmpty) 'c': cardId,
      });

  /// A lent milk route. The route itself stays in route_shares; the card only
  /// names it, so chat text never carries customer details.
  static ShareCard route({
    required String shareId,
    required String name,
    required String owner,
    required int homes,
  }) => ShareCard({
    'k': 'route',
    's': shareId,
    'n': name,
    'o': owner,
    'c': homes,
  });

  /// The first line people see even without card support.
  String get headline => switch (kind) {
    'animal' => '🐄 $displayName · ${ui(txt(data, 'b', 'Unknown breed'))}',
    'route' => '🗺️ ${bi('Route map', 'பாதை வரைபடம்')} · ${txt(data, 'n')}',
    'post' => '📝 ${bi('Post by', 'பதிவு:')} ${txt(data, 'n')}',
    _ =>
      '👤 ${txt(data, 'n')}${txt(data, 'h').isEmpty ? '' : ' @${txt(data, 'h')}'}',
  };

  String get displayName {
    final explicit = txt(data, tamilUi ? 'nt' : 'ne');
    if (explicit.isNotEmpty) return explicit;
    return nameInLanguage(txt(data, 'n'), tamilUi);
  }

  String get ageLabel => ageTextLocal({
    'dob': txt(data, 'd'),
    'ageYears': data['y'],
    'ageMonths': data['m'],
    'ageDays': data['dd'],
  });

  String encode() =>
      '$headline\n$_shareMarker${base64Url.encode(utf8.encode(jsonEncode(data)))}';

  static ShareCard? decode(String text) {
    final at = text.indexOf(_shareMarker);
    if (at < 0) return null;
    try {
      final raw = text.substring(at + _shareMarker.length).trim();
      final json = jsonDecode(utf8.decode(base64Url.decode(raw)));
      if (json is! Map) return null;
      final card = ShareCard(Map<String, dynamic>.from(json));
      return const {'animal', 'post', 'profile', 'route'}.contains(card.kind)
          ? card
          : null;
    } catch (_) {
      return null;
    }
  }

  /// The local animal this card points to, when it belongs to our ranch.
  MapEntry<dynamic, Map<String, dynamic>>? localAnimal() {
    if (kind != 'animal') return null;
    final ranch = txt(data, 'r');
    if (ranch.isEmpty || ranch != ranchId() || !Hive.isBoxOpen('animals')) {
      return null;
    }
    final id = txt(data, 'i');
    final name = txt(data, 'n');
    final box = Hive.box('animals');
    for (final key in box.keys) {
      final a = asMap(box.get(key));
      if ((id.isNotEmpty &&
              txt(a, 'id') == id &&
              txt(a, 'type') == txt(data, 't')) ||
          (id.isEmpty && txt(a, 'name') == name)) {
        return MapEntry(key, a);
      }
    }
    return null;
  }
}

/// A small JPEG for the public animal card, so people outside the ranch see
/// the photo without receiving any private ranch record.
Future<String> _animalThumbnail(Map<String, dynamic> a) async {
  final data = txt(a, 'imageData');
  if (!data.startsWith('data:image')) return '';
  try {
    final bytes = await compute(
      _thumbnailEncode,
      base64Decode(data.split(',').last),
    );
    return bytes == null ? '' : 'data:image/jpeg;base64,${base64Encode(bytes)}';
  } catch (_) {
    return '';
  }
}

Uint8List? _thumbnailEncode(Uint8List bytes) {
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = image_lib.bakeOrientation(decoded);
  final longest = math.max(oriented.width, oriented.height);
  final resized = longest > 640
      ? image_lib.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 640 : null,
          height: oriented.height > oriented.width ? 640 : null,
          interpolation: image_lib.Interpolation.average,
        )
      : oriented;
  for (final quality in const [82, 70, 58]) {
    final out = Uint8List.fromList(
      image_lib.encodeJpg(resized, quality: quality),
    );
    if (out.lengthInBytes <= 200000) return out;
  }
  return null;
}

Future<ShareCard> buildAnimalShare(Map<String, dynamic> a) async {
  var cardId = '';
  try {
    final uid = signedInUid;
    if (uid.isNotEmpty) {
      final photo = await _animalThumbnail(a);
      final url = txt(a, 'imageUrl');
      final ref = FirebaseFirestore.instance.collection('shared_cards').doc();
      await ref
          .set({
            'ownerUid': uid,
            'kind': 'animal',
            'photo': photo,
            'photoUrl': photo.isEmpty && url.startsWith('https://') ? url : '',
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(CloudSyncService.networkTimeout);
      cardId = ref.id;
    }
  } catch (_) {
    // Offline or not yet permitted: the card is still shared without a photo.
  }
  return ShareCard.animal(a, cardId: cardId);
}

Future<void> _sendToRanchChat(String text) async {
  final messageId = 'message_${DateTime.now().microsecondsSinceEpoch}';
  await Hive.box('ranch_messages').add({
    'messageId': messageId,
    'text': text,
    'mentions': const [],
    'sender': currentUserName(),
    'date': todayDate(),
    'time': currentTime(),
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
  AutoSyncService.scheduleSync(reason: 'shared to ranch chat');
  await addRanchNotification(
    title: bi(
      '${currentUserName()} shared in ranch chat',
      '${currentUserName()} தொழுவ சாட்டில் பகிர்ந்தார்',
    ),
    message: text.split('\n').first,
    type: 'chat',
    sourceId: messageId,
  );
}

Future<void> _sendToPerson(String peer, String text) async {
  final chatId = await DirectChatService.open(peer);
  final id = FirebaseFirestore.instance
      .collection('direct_chats')
      .doc(chatId)
      .collection('messages')
      .doc()
      .id;
  await Hive.box('community_outbox').put(id, {
    'senderUid': signedInUid,
    'chatId': chatId,
    'text': text,
    'savedAt': DateTime.now().toIso8601String(),
  });
  AutoSyncService.markDirty(reason: 'private message');
}

/// People this account can message: contacts, chat partners and, when asked,
/// active ranch members. One unavailable source never hides the others.
Future<List<String>> loadShareablePeople({
  bool includeRanchMembers = true,
}) async {
  final me = signedInUid;

  final db = FirebaseFirestore.instance;
  final ids = <String>{};
  Future<void> collect(Future<Iterable<String>> Function() load) async {
    try {
      ids.addAll(await load().timeout(CloudSyncService.networkTimeout));
    } catch (_) {
      /* One unavailable source must not hide the others. */
    }
  }

  await Future.wait([
    collect(() async {
      final s = await db
          .collection('profiles')
          .doc(me)
          .collection('contacts')
          .get();
      return s.docs.map((d) => d.id);
    }),
    collect(() async {
      final s = await db
          .collection('direct_chats')
          .where('participants', arrayContains: me)
          .get();
      return [
        for (final d in s.docs)
          for (final p in (d.data()['participants'] as List? ?? const [])) '$p',
      ];
    }),
    if (includeRanchMembers && CloudSyncService.ready)
      collect(() async {
        final s = await CloudSyncService.ranch.collection('members').get();
        return [
          for (final d in s.docs)
            if (d.data()['active'] != false &&
                txt(d.data(), 'status', 'active') == 'active')
              d.id,
        ];
      }),
  ]);
  ids.remove(me);
  return ids.toList();
}

/// Pick where to share: the ranch group (members only) and people.
Future<void> showShareSheet(
  BuildContext context,
  Future<ShareCard> Function() build,
) async {
  if (signedInUid.isEmpty) {
    snack(context, ui('Please sign in again'));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShareSheet(build: build),
  );
}

class _ShareSheet extends StatefulWidget {
  final Future<ShareCard> Function() build;
  const _ShareSheet({required this.build});
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late final Future<List<String>> _people = _loadPeople();
  final Set<String> _selected = {};
  bool _ranch = false;
  bool _sending = false;

  static const _ranchTarget = '#ranch';

  Future<List<String>> _loadPeople() =>
      loadShareablePeople(includeRanchMembers: CloudSyncService.ready);

  Future<void> _send() async {
    if (_sending || (_selected.isEmpty && !_ranch)) return;
    setState(() => _sending = true);
    try {
      final card = await widget.build();
      final text = card.encode();
      if (_ranch) await _sendToRanchChat(text);
      for (final peer in _selected) {
        await _sendToPerson(peer, text);
      }
      if (!mounted) return;
      Navigator.pop(context);
      snack(context, bi('Shared', 'பகிரப்பட்டது'));
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _target({
    required String id,
    required Widget avatar,
    required String title,
    required String subtitle,
  }) {
    final selected = id == _ranchTarget ? _ranch : _selected.contains(id);
    return InkWell(
      onTap: () => setState(() {
        if (id == _ranchTarget) {
          _ranch = !_ranch;
        } else if (!_selected.remove(id)) {
          _selected.add(id);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Ink.navy,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Ink.muted, fontSize: 13),
                    ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: Gold.fast,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? Ink.violetDeep : Colors.transparent,
                border: Border.all(
                  color: selected ? Ink.violetDeep : Ink.faint,
                  width: 1.6,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length + (_ranch ? 1 : 0);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                bi('Share to', 'பகிர'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Ink.navy,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _people,
                builder: (context, snap) {
                  final people = snap.data ?? const <String>[];
                  return ListView(
                    children: [
                      if (CloudSyncService.ready)
                        _target(
                          id: _ranchTarget,
                          avatar: Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Ink.violet, Ink.violetDeep],
                              ),
                            ),
                            child: const Icon(
                              CupertinoIcons.person_3_fill,
                              color: Colors.white,
                            ),
                          ),
                          title: farmName(),
                          subtitle: bi('Ranch group', 'தொழுவக் குழு'),
                        ),
                      if (snap.connectionState != ConnectionState.done)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CupertinoActivityIndicator()),
                        ),
                      for (final uid in people)
                        FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          future: FirebaseFirestore.instance
                              .collection('profiles')
                              .doc(uid)
                              .get(),
                          builder: (context, profile) {
                            final d = profile.data?.data() ?? const {};
                            final name = txt(
                              d,
                              'displayName',
                              txt(
                                d,
                                'username',
                                bi('VIMO member', 'VIMO உறுப்பினர்'),
                              ),
                            );
                            return _target(
                              id: uid,
                              avatar: profileAvatar(
                                txt(d, 'photo'),
                                radius: 23,
                                label: name,
                              ),
                              title: name,
                              subtitle: txt(d, 'username').isEmpty
                                  ? ''
                                  : '@${txt(d, 'username')}',
                            );
                          },
                        ),
                      if (snap.connectionState == ConnectionState.done &&
                          people.isEmpty &&
                          !CloudSyncService.ready)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            bi(
                              'Add people from search to share with them.',
                              'பகிர, தேடல் மூலம் நபர்களைச் சேர்க்கவும்.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Ink.muted),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: LiquidButton(
                label: count == 0
                    ? bi(
                        'Choose where to share',
                        'பகிர வேண்டிய இடத்தைத் தேர்வு செய்யவும்',
                      )
                    : bi('Send · $count', 'அனுப்பு · $count'),
                icon: CupertinoIcons.paperplane_fill,
                busy: _sending,
                onPressed: count == 0 ? null : _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a shared card inside a chat bubble.
class ShareCardBubble extends StatelessWidget {
  final ShareCard card;
  final bool mine;
  const ShareCardBubble({super.key, required this.card, required this.mine});

  void _open(BuildContext context) {
    switch (card.kind) {
      case 'animal':
        final local = card.localAnimal();
        if (local != null) {
          push(context, AnimalProfileScreen(animalKey: local.key));
        } else {
          push(context, SharedAnimalScreen(card: card));
        }
      case 'post':
        push(context, SharedPostScreen(postId: txt(card.data, 'p')));
      case 'route':
        push(context, RouteInviteScreen(shareId: txt(card.data, 's')));
      default:
        push(context, SocialProfileScreen(uid: txt(card.data, 'u')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : Ink.navy;
    final sub = mine ? Colors.white.withValues(alpha: .80) : Ink.muted;
    final local = card.localAnimal();
    Widget leading;
    String title;
    String subtitle;
    String tag;
    switch (card.kind) {
      case 'animal':
        leading = local != null
            ? AnimalAvatar(animal: withKey(local.key, local.value), radius: 26)
            : Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mine
                      ? Colors.white.withValues(alpha: .18)
                      : Ink.lavender,
                ),
                child: const Center(child: CowMark(size: 34)),
              );
        title = card.displayName;
        subtitle = [
          ui(txt(card.data, 'b', 'Unknown breed')),
          card.ageLabel,
        ].join(' · ');
        tag = txt(card.data, 'g') == 'Male'
            ? (txt(card.data, 'u').isEmpty
                  ? bi('Bull', 'காளை')
                  : maleUseLabel(txt(card.data, 'u')))
            : (txt(card.data, 't') == 'calf'
                  ? bi('Calf profile', 'கன்று விவரம்')
                  : bi('Cow profile', 'மாடு விவரம்'));
      case 'post':
        leading = Icon(CupertinoIcons.doc_richtext, color: fg, size: 30);
        title = '${bi('Post by', 'பதிவு:')} ${txt(card.data, 'n')}';
        subtitle = txt(card.data, 'x').isEmpty
            ? (card.data['ph'] == true ? bi('Photo', 'புகைப்படம்') : '')
            : txt(card.data, 'x');
        tag = bi('Post', 'பதிவு');
      case 'route':
        leading = Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: mine ? Colors.white.withValues(alpha: .18) : Ink.lavender,
          ),
          child: Icon(
            CupertinoIcons.map_fill,
            color: mine ? Colors.white : Ink.violetDeep,
            size: 26,
          ),
        );
        title = txt(card.data, 'n');
        subtitle = [
          bi(
            '${toInt(card.data['c'])} homes',
            '${toInt(card.data['c'])} வீடுகள்',
          ),
          if (txt(card.data, 'o').isNotEmpty)
            bi(
              'from ${txt(card.data, 'o')}',
              '${txt(card.data, 'o')} அனுப்பியது',
            ),
        ].join(' · ');
        tag = bi(
          'Route map · Save or reject',
          'பாதை வரைபடம் · சேமி அல்லது மறு',
        );
      default:
        leading = Icon(CupertinoIcons.person_crop_circle, color: fg, size: 32);
        title = txt(card.data, 'n');
        subtitle = [
          if (txt(card.data, 'h').isNotEmpty) '@${txt(card.data, 'h')}',
          if (txt(card.data, 'pl').isNotEmpty) txt(card.data, 'pl'),
        ].join(' · ');
        tag = bi('Profile', 'ப்ரொஃபைல்');
    }
    return GestureDetector(
      onTap: () => _open(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: sub,
                            fontSize: 13.5,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  tag,
                  style: TextStyle(
                    color: sub,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  bi('Open', 'திற'),
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(CupertinoIcons.chevron_right, size: 13, color: fg),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What people outside the ranch see: photo, name, breed and age only.
class SharedAnimalScreen extends StatelessWidget {
  final ShareCard card;
  const SharedAnimalScreen({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final cardId = txt(card.data, 'c');
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      appBar: AppBar(
        leading: const _BackButton(),
        title: Text(
          txt(card.data, 'g') == 'Male'
              ? bi('Bull', 'காளை')
              : txt(card.data, 't') == 'calf'
              ? bi('Calf', 'கன்று')
              : bi('Cow', 'மாடு'),
        ),
      ),
      body: Shell(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Gold.contentWidth + 34),
            child: ListView(
              padding: const EdgeInsets.all(Gold.s21),
              children: [
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: cardId.isEmpty
                      ? null
                      : FirebaseFirestore.instance
                            .collection('shared_cards')
                            .doc(cardId)
                            .get(),
                  builder: (context, snap) {
                    final d = snap.data?.data() ?? const <String, dynamic>{};
                    final photo = txt(d, 'photo');
                    final url = txt(d, 'photoUrl');
                    ImageProvider? image;
                    if (photo.startsWith('data:image')) {
                      try {
                        image = MemoryImage(
                          base64Decode(photo.split(',').last),
                        );
                      } catch (_) {}
                    } else if (url.startsWith('https://')) {
                      image = NetworkImage(url);
                    }
                    return AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: const ShapeDecoration(
                          shape: SquircleBorder(radius: Gold.r34),
                          color: Ink.lavender,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: image == null
                            ? Center(
                                child:
                                    snap.connectionState ==
                                            ConnectionState.waiting &&
                                        cardId.isNotEmpty
                                    ? const CupertinoActivityIndicator()
                                    : const CowMark(size: 144),
                              )
                            : Image(
                                image: image,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                              ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: Gold.s21),
                Glass(
                  radius: Gold.r27,
                  padding: const EdgeInsets.all(Gold.s21),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.displayName,
                        style: const TextStyle(
                          color: Ink.navy,
                          fontSize: Gold.t27,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: Gold.s13),
                      _SharedFact(
                        icon: Icons.category_outlined,
                        label: bi('Breed', 'இனம்'),
                        value: ui(txt(card.data, 'b', 'Unknown breed')),
                      ),
                      const SizedBox(height: Gold.s8),
                      _SharedFact(
                        icon: Icons.cake_outlined,
                        label: bi('Age', 'வயது'),
                        value: card.ageLabel,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SharedFact extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _SharedFact({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Ink.violet, size: 20),
      const SizedBox(width: 10),
      Text(
        label,
        style: const TextStyle(color: Ink.muted, fontWeight: FontWeight.w600),
      ),
      const Spacer(),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(
            color: Ink.navy,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    ],
  );
}

/// Opens one shared post.
class SharedPostScreen extends StatelessWidget {
  final String postId;
  const SharedPostScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(bi('Post', 'பதிவு')),
    ),
    body: Shell(
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('social_posts')
            .doc(postId)
            .get(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CupertinoActivityIndicator());
          }
          final data = snap.data?.data();
          if (snap.hasError || data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gold.s21),
                child: EmptyNote(
                  icon: Icons.search_off_rounded,
                  title: bi('Post not available', 'பதிவு கிடைக்கவில்லை'),
                  message: bi(
                    'It may have been deleted.',
                    'அது நீக்கப்பட்டிருக்கலாம்.',
                  ),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
            children: [_SocialPost(post: SocialPostRecord(postId, data))],
          );
        },
      ),
    ),
  );
}
