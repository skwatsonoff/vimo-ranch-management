part of 'main.dart';

bool validProfileLink(String value) {
  if (value.isEmpty) return true;
  final uri = Uri.tryParse(value);
  return uri != null &&
      ['https', 'http'].contains(uri.scheme) &&
      uri.host.contains('.') &&
      uri.userInfo.isEmpty;
}

String accountError(Object error) {
  if (error is StateError) return error.message;
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return bi(
          'Cloud permission denied. Your entries are still saved. The app’s cloud rules need updating.',
          'கிளவுட் அனுமதி மறுக்கப்பட்டது. உங்கள் பதிவுகள் பாதுகாப்பாக உள்ளன. செயலியின் கிளவுட் அனுமதி விதிகளைப் புதுப்பிக்க வேண்டும்.',
        );
      case 'unauthenticated':
        return bi(
          'Your sign-in expired. Sign in again; local entries are kept.',
          'உள்நுழைவு காலாவதியானது. மீண்டும் உள்நுழையவும்; உள்ளூர் பதிவுகள் பாதுகாப்பாக உள்ளன.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return bi(
          'The cloud is not responding. Your changes are kept; retry when connected.',
          'கிளவுட் பதிலளிக்கவில்லை. மாற்றங்கள் பாதுகாக்கப்பட்டுள்ளன; இணையம் வந்ததும் மீண்டும் முயற்சிக்கவும்.',
        );
      default:
        return bi(
          'Cloud request failed (${error.code}). Please retry.',
          'கிளவுட் கோரிக்கை தோல்வி (${error.code}). மீண்டும் முயற்சிக்கவும்.',
        );
    }
  }
  if (error is TimeoutException) {
    return bi(
      'The cloud took too long to respond. Retry; your draft is kept.',
      'கிளவுட் பதில் தாமதமாகிறது. மீண்டும் முயற்சிக்கவும்; வரைவு பாதுகாக்கப்பட்டுள்ளது.',
    );
  }
  return bi(
    'Could not connect. Check your connection and try again.',
    'இணைக்க முடியவில்லை. இணையத்தைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',
  );
}

Widget profileAvatar(String photo, {double radius = 38}) => CircleAvatar(
  radius: radius,
  backgroundColor: Ink.violet.withValues(alpha: .12),
  child: photo.isEmpty
      ? Icon(CupertinoIcons.person_fill, size: radius, color: Ink.violet)
      : ClipOval(
          child: Image.memory(
            socialPhotoBytes(photo),
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(
              CupertinoIcons.person_fill,
              size: radius,
              color: Ink.violet,
            ),
          ),
        ),
);

class SocialProfileScreen extends StatefulWidget {
  final String? uid;
  const SocialProfileScreen({super.key, this.uid});
  @override
  State<SocialProfileScreen> createState() => _SocialProfileScreenState();
}

class _SocialProfileScreenState extends State<SocialProfileScreen> {
  String get uid => widget.uid ?? signedInUid;
  bool get own => uid == signedInUid;
  int _tab = 0;
  bool _busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      actions: [
        if (own)
          IconButton(
            tooltip: ui('Settings'),
            icon: const Icon(CupertinoIcons.gear),
            onPressed: () => push(context, const SettingsScreen()),
          ),
      ],
    ),
    body: Shell(
      child: uid.isEmpty
          ? Center(child: Text(ui('Please sign in again')))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('profiles')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? <String, dynamic>{};
                final name = txt(data, 'username', own ? accountUsername : '');
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                    SizedBox(
                      height: 190,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Opacity(
                            opacity: .22,
                            child: Image(
                              image: heroArtImage,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Vimo',
                                style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w300,
                                  fontStyle: FontStyle.italic,
                                  color: Ink.violet,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Glass(
                      radius: 34,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              profileAvatar(txt(data, 'photo'), radius: 48),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      txt(
                                        data,
                                        'displayName',
                                        own ? currentUserName() : name,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      name.isEmpty
                                          ? bi(
                                              'Choose a username',
                                              'பயனர்பெயரைத் தேர்ந்தெடு',
                                            )
                                          : '@$name',
                                      style: const TextStyle(color: Ink.muted),
                                    ),
                                    if (txt(data, 'place').isNotEmpty)
                                      Text(txt(data, 'place')),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _ProfileCount(uid: uid, kind: 'followers'),
                              _ProfileCount(uid: uid, kind: 'following'),
                            ],
                          ),
                          if (txt(data, 'bio').isNotEmpty)
                            Text(
                              txt(data, 'bio'),
                              style: const TextStyle(fontSize: 16),
                            ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              if (txt(data, 'whatsapp').isNotEmpty)
                                OutlinedButton.icon(
                                  icon: const Icon(CupertinoIcons.chat_bubble),
                                  label: const Text('WhatsApp'),
                                  onPressed: () => _link(
                                    'https://wa.me/${txt(data, 'whatsapp').replaceAll(RegExp(r'[^0-9]'), '')}',
                                  ),
                                ),
                              if (txt(data, 'link').isNotEmpty &&
                                  validProfileLink(txt(data, 'link')))
                                OutlinedButton.icon(
                                  icon: const Icon(CupertinoIcons.link),
                                  label: Text(bi('My link', 'என் இணைப்பு')),
                                  onPressed: () => _link(txt(data, 'link')),
                                ),
                              if (own)
                                IconButton(
                                  tooltip: bi(
                                    'Edit profile',
                                    'சுயவிவரத்தைத் திருத்து',
                                  ),
                                  icon: const Icon(CupertinoIcons.ellipsis),
                                  onPressed: () => push(
                                    context,
                                    EditSocialProfileScreen(data: data),
                                  ),
                                ),
                              if (!own)
                                OutlinedButton.icon(
                                  icon: const Icon(
                                    CupertinoIcons.chat_bubble_2,
                                  ),
                                  label: Text(bi('Message', 'செய்தி')),
                                  onPressed: () async {
                                    try {
                                      final chat = await DirectChatService.open(
                                        uid,
                                      );
                                      if (context.mounted) {
                                        await push(
                                          context,
                                          DirectChatScreen(
                                            chatId: chat,
                                            peer: uid,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        snack(context, accountError(e));
                                      }
                                    }
                                  },
                                ),
                            ],
                          ),
                          if (!own)
                            StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              stream: FirebaseFirestore.instance
                                  .collection('profiles')
                                  .doc(uid)
                                  .collection('followers')
                                  .doc(signedInUid)
                                  .snapshots(),
                              builder: (context, follow) => TextButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (accountUsername.isEmpty) {
                                          await push(
                                            context,
                                            const UsernameScreen(),
                                          );
                                          if (!mounted ||
                                              accountUsername.isEmpty) {
                                            return;
                                          }
                                        }
                                        setState(() => _busy = true);
                                        try {
                                          final db = FirebaseFirestore.instance;
                                          final batch = db.batch();
                                          final a = db
                                              .collection('profiles')
                                              .doc(uid)
                                              .collection('followers')
                                              .doc(signedInUid);
                                          final b = db
                                              .collection('profiles')
                                              .doc(signedInUid)
                                              .collection('following')
                                              .doc(uid);
                                          if (follow.data?.exists == true) {
                                            batch.delete(a);
                                            batch.delete(b);
                                          } else {
                                            batch.set(a, {
                                              'createdAt':
                                                  FieldValue.serverTimestamp(),
                                            });
                                            batch.set(b, {
                                              'createdAt':
                                                  FieldValue.serverTimestamp(),
                                            });
                                          }
                                          await batch.commit().timeout(
                                            CloudSyncService.networkTimeout,
                                          );
                                        } catch (e) {
                                          if (context.mounted) {
                                            snack(context, accountError(e));
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _busy = false);
                                          }
                                        }
                                      },
                                child: Text(
                                  follow.data?.exists == true
                                      ? bi('Unfollow', 'பின்தொடர்வதை நிறுத்து')
                                      : bi('Follow', 'பின்தொடர்'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (snap.hasError)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(accountError(snap.error!)),
                      ),
                    const SizedBox(height: 20),
                    Glass(
                      padding: const EdgeInsets.all(5),
                      child: Row(
                        children: [
                          for (final item in [
                            (
                              0,
                              bi('Post', 'பதிவுகள்'),
                              CupertinoIcons.doc_text,
                            ),
                            (1, bi('Ranch', 'பண்ணை'), CupertinoIcons.house),
                            (2, bi('Vendor', 'கடை'), CupertinoIcons.bag),
                          ])
                            Expanded(
                              child: TextButton(
                                onPressed: () => setState(() => _tab = item.$1),
                                style: TextButton.styleFrom(
                                  backgroundColor: _tab == item.$1
                                      ? Colors.white
                                      : Colors.transparent,
                                  foregroundColor: _tab == item.$1
                                      ? Ink.violet
                                      : Ink.muted,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (item.$1 == 1)
                                      const CowMark(size: 23)
                                    else
                                      Icon(item.$3, size: 21),
                                    const SizedBox(width: 6),
                                    Flexible(child: Text(item.$2)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_tab == 0) ProfilePostList(uid: uid, own: own),
                    if (_tab == 1) PublicRanchView(uid: uid, profile: data),
                    if (_tab == 2)
                      Glass(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['shareShop'] == true
                                  ? txt(data, 'shopName')
                                  : bi(
                                      'This shop is private.',
                                      'இந்தக் கடை தனிப்பட்டது.',
                                    ),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (data['shareShop'] == true) ...[
                              const SizedBox(height: 12),
                              Text(txt(data, 'shopDetails')),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
    ),
  );
  Future<void> _link(String value) async {
    try {
      await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    }
  }
}

class ProfilePostList extends StatefulWidget {
  final String uid;
  final bool own;
  const ProfilePostList({super.key, required this.uid, required this.own});
  @override
  State<ProfilePostList> createState() => _ProfilePostListState();
}

class _ProfilePostListState extends State<ProfilePostList> {
  Timer? _clock;
  late DateTime _now;
  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('social_posts')
        .where('authorUid', isEqualTo: widget.uid);
    if (!widget.own) {
      query = query.where(
        'createdAt',
        isLessThanOrEqualTo: Timestamp.fromDate(_now),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query
          .orderBy('createdAt', descending: true)
          .limit(60)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text(accountError(snap.error!));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(26),
            child: Text(bi('No posts yet.', 'இன்னும் பதிவுகள் இல்லை.')),
          );
        }
        return Column(
          children: [
            for (final post in snap.data!.docs)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if ((post.data()['createdAt'] as Timestamp?)
                            ?.toDate()
                            .isAfter(DateTime.now()) ==
                        true)
                      Text(
                        '${bi('Scheduled', 'திட்டமிடப்பட்டது')}: ${(post.data()['createdAt'] as Timestamp).toDate().toLocal()}',
                        style: const TextStyle(color: Ink.violet),
                      ),
                    _SocialPost(key: ValueKey(post.id), post: post),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProfileCount extends StatelessWidget {
  final String uid, kind;
  const _ProfileCount({required this.uid, required this.kind});
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('profiles')
        .doc(uid)
        .collection(kind)
        .snapshots(),
    builder: (context, snapshot) => TextButton(
      onPressed: () => push(context, ProfilePeopleScreen(uid: uid, kind: kind)),
      child: Text(
        '${snapshot.hasData ? snapshot.data!.docs.length : '–'} ${kind == 'followers' ? bi('Followers', 'பின்தொடர்பவர்கள்') : bi('Following', 'பின்தொடர்பவை')}',
      ),
    ),
  );
}

class ProfilePeopleScreen extends StatelessWidget {
  final String uid, kind;
  const ProfilePeopleScreen({super.key, required this.uid, required this.kind});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        kind == 'followers'
            ? bi('Followers', 'பின்தொடர்பவர்கள்')
            : bi('Following', 'பின்தொடர்பவை'),
      ),
    ),
    body: Shell(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('profiles')
            .doc(uid)
            .collection(kind)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(accountError(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(bi('No people yet', 'இன்னும் யாரும் இல்லை')),
            );
          }
          return ListView(
            children: [
              for (final person in snapshot.data!.docs)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('profiles')
                      .doc(person.id)
                      .snapshots(),
                  builder: (context, profile) => ListTile(
                    leading: profileAvatar(
                      txt(profile.data?.data() ?? {}, 'photo'),
                      radius: 22,
                    ),
                    title: Text(
                      '@${txt(profile.data?.data() ?? {}, 'username', '…')}',
                    ),
                    onTap: () =>
                        push(context, SocialProfileScreen(uid: person.id)),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class EditSocialProfileScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const EditSocialProfileScreen({super.key, required this.data});
  @override
  State<EditSocialProfileScreen> createState() =>
      _EditSocialProfileScreenState();
}

class _EditSocialProfileScreenState extends State<EditSocialProfileScreen> {
  late final _name = TextEditingController(
    text: txt(widget.data, 'displayName', currentUserName()),
  );
  late final _place = TextEditingController(text: txt(widget.data, 'place'));
  late final _whatsapp = TextEditingController(
    text: txt(widget.data, 'whatsapp'),
  );
  late final _shop = TextEditingController(text: txt(widget.data, 'shopName'));
  late final _shopDetails = TextEditingController(
    text: txt(widget.data, 'shopDetails'),
  );
  late bool _shareRanch = widget.data['shareRanch'] == true;
  late bool _shareShop = widget.data['shareShop'] == true;
  late final _bio = TextEditingController(text: txt(widget.data, 'bio'));
  late final _link = TextEditingController(text: txt(widget.data, 'link'));
  late String _photo = txt(widget.data, 'photo');
  bool _busy = false, _picking = false;
  @override
  void dispose() {
    _name.dispose();
    _place.dispose();
    _whatsapp.dispose();
    _shop.dispose();
    _shopDetails.dispose();
    _bio.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: bi('Edit profile', 'சுயவிவரத்தைத் திருத்து'),
    children: [
      Center(child: profileAvatar(_photo)),
      TextField(
        controller: _name,
        maxLength: 80,
        decoration: fieldStyle(bi('Name', 'பெயர்')),
      ),
      TextField(
        controller: _place,
        maxLength: 120,
        decoration: fieldStyle(bi('Location', 'இடம்')),
      ),
      TextButton(
        onPressed: _picking || _busy
            ? null
            : () async {
                setState(() => _picking = true);
                try {
                  final selected = await pickImageDataUrl();
                  if (selected == null) return;
                  final photo = await compressSocialPhoto(selected);
                  if (photo == null) {
                    throw StateError(
                      bi(
                        'Could not load this photo.',
                        'புகைப்படத்தை ஏற்ற முடியவில்லை.',
                      ),
                    );
                  }
                  if (mounted) setState(() => _photo = photo);
                } catch (e) {
                  if (context.mounted) snack(context, accountError(e));
                } finally {
                  if (mounted) setState(() => _picking = false);
                }
              },
        child: Text(bi('Change photo', 'புகைப்படத்தை மாற்று')),
      ),
      if (_photo.isNotEmpty)
        TextButton(
          onPressed: () => setState(() => _photo = ''),
          child: Text(bi('Remove photo', 'புகைப்படத்தை நீக்கு')),
        ),
      _ActionRow(
        icon: CupertinoIcons.at,
        label: accountUsername.isEmpty
            ? bi('Choose username', 'பயனர்பெயரைத் தேர்ந்தெடு')
            : '@$accountUsername',
        onTap: () async {
          await push(context, const UsernameScreen());
          if (mounted) setState(() {});
        },
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _bio,
        maxLength: 160,
        minLines: 3,
        maxLines: 5,
        decoration: fieldStyle(bi('Bio', 'சுய அறிமுகம்')),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _link,
        maxLength: 300,
        keyboardType: TextInputType.url,
        decoration: fieldStyle(bi('Link (optional)', 'இணைப்பு (விருப்பம்)')),
      ),
      TextField(
        controller: _whatsapp,
        maxLength: 16,
        keyboardType: TextInputType.phone,
        decoration: fieldStyle(
          bi(
            'WhatsApp with country code',
            'நாட்டுக் குறியீட்டுடன் வாட்ஸ்அப் எண்',
          ),
        ),
      ),
      SwitchListTile(
        value: _shareRanch,
        title: Text(bi('Show my ranch cows', 'என் பண்ணை மாடுகளைக் காட்டு')),
        subtitle: Text(
          bi(
            'Only cow photos, names and breeds are shared.',
            'மாட்டுப் படங்கள், பெயர்கள், இனங்கள் மட்டும் பகிரப்படும்.',
          ),
        ),
        onChanged: CloudSyncService.ready
            ? (v) => setState(() => _shareRanch = v)
            : null,
      ),
      SwitchListTile(
        value: _shareShop,
        title: Text(bi('Show my shop', 'என் கடையைக் காட்டு')),
        onChanged: (v) => setState(() => _shareShop = v),
      ),
      if (_shareShop) ...[
        TextField(
          controller: _shop,
          maxLength: 100,
          decoration: fieldStyle(bi('Shop name', 'கடைப் பெயர்')),
        ),
        TextField(
          controller: _shopDetails,
          maxLength: 500,
          maxLines: 4,
          decoration: fieldStyle(bi('Shop details', 'கடை விவரம்')),
        ),
      ],
      const SizedBox(height: 24),
      LiquidButton(
        label: 'Save',
        busy: _busy,
        onPressed: () async {
          if (_busy || _picking) return;
          if (_whatsapp.text.trim().isNotEmpty &&
              !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(_whatsapp.text.trim())) {
            snack(
              context,
              bi(
                'Enter 7–15 digits with country code.',
                'நாட்டுக் குறியீட்டுடன் 7–15 எண்களை உள்ளிடுங்கள்.',
              ),
            );
            return;
          }
          if (_name.text.trim().isEmpty) {
            snack(context, bi('Enter your name.', 'பெயரை உள்ளிடுங்கள்.'));
            return;
          }
          if (!validProfileLink(_link.text.trim())) {
            snack(
              context,
              bi(
                'Enter a valid https:// link.',
                'சரியான https:// இணைப்பை உள்ளிடுங்கள்.',
              ),
            );
            return;
          }
          if (accountUsername.isEmpty) {
            await push(context, const UsernameScreen());
            if (!mounted || accountUsername.isEmpty) return;
          }
          setState(() => _busy = true);
          try {
            final uid = FirebaseAuth.instance.currentUser!.uid;
            await FirebaseFirestore.instance
                .collection('profiles')
                .doc(uid)
                .set({
                  'username': accountUsername,
                  'displayName': _name.text.trim(),
                  'displayNameFold': _name.text.trim().toLowerCase(),
                  'place': _place.text.trim(),
                  'whatsapp': _whatsapp.text.trim(),
                  'shareRanch': _shareRanch,
                  'ranchId': _shareRanch ? ranchId() : '',
                  'ranchName': _shareRanch ? farmName() : '',
                  'shareShop': _shareShop,
                  'shopName': _shop.text.trim(),
                  'shopDetails': _shopDetails.text.trim(),
                  'photo': _photo,
                  'bio': _bio.text.trim(),
                  'link': _link.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true))
                .timeout(const Duration(seconds: 20));
            AutoSyncService.scheduleSync(reason: 'profile changed');
            if (context.mounted) Navigator.pop(context);
          } catch (e) {
            if (context.mounted) snack(context, accountError(e));
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
    ],
  );
}
