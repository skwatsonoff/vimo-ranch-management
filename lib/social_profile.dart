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
  String get uid =>
      widget.uid ??
      (firebaseReady ? FirebaseAuth.instance.currentUser?.uid : null) ??
      '';
  bool get own =>
      widget.uid == null ||
      (firebaseReady && widget.uid == FirebaseAuth.instance.currentUser?.uid);
  bool _busy = false;
  late final _profile = uid.isEmpty
      ? null
      : FirebaseFirestore.instance.collection('profiles').doc(uid).snapshots();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(bi('Profile', 'சுயவிவரம்'))),
    body: Shell(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profile,
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final name = txt(data, 'username', own ? accountUsername : '');
          return ListView(
            padding: const EdgeInsets.all(21),
            children: [
              Glass(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    profileAvatar(txt(data, 'photo')),
                    const SizedBox(height: 16),
                    Text(
                      name.isEmpty
                          ? bi(
                              'Choose a username',
                              'பயனர்பெயரைத் தேர்ந்தெடுங்கள்',
                            )
                          : '@$name',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (txt(data, 'bio').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          txt(data, 'bio'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (txt(data, 'link').isNotEmpty &&
                        validProfileLink(txt(data, 'link')))
                      TextButton(
                        onPressed: () async {
                          try {
                            await launchUrl(
                              Uri.parse(txt(data, 'link')),
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            if (context.mounted) {
                              snack(context, accountError(e));
                            }
                          }
                        },
                        child: Text(
                          txt(data, 'link'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (uid.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _ProfileCount(uid: uid, kind: 'followers'),
                          _ProfileCount(uid: uid, kind: 'following'),
                        ],
                      ),
                    const SizedBox(height: 16),
                    if (own)
                      LiquidButton(
                        label: bi('Edit profile', 'சுயவிவரத்தைத் திருத்து'),
                        onPressed: () async {
                          await push(
                            context,
                            EditSocialProfileScreen(data: data),
                          );
                          if (mounted) setState(() {});
                        },
                      )
                    else if (firebaseReady &&
                        FirebaseAuth.instance.currentUser != null)
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('profiles')
                            .doc(uid)
                            .collection('followers')
                            .doc(FirebaseAuth.instance.currentUser!.uid)
                            .snapshots(),
                        builder: (context, follower) {
                          final following = follower.data?.exists == true;
                          return LiquidButton(
                            label: following
                                ? bi('Unfollow', 'பின்தொடர்வதை நிறுத்து')
                                : bi('Follow', 'பின்தொடர்'),
                            busy: _busy,
                            onPressed: () async {
                              if (_busy || !follower.hasData) return;
                              if (accountUsername.isEmpty) {
                                await push(context, const UsernameScreen());
                                if (!mounted || accountUsername.isEmpty) return;
                              }
                              setState(() => _busy = true);
                              try {
                                final db = FirebaseFirestore.instance;
                                final me =
                                    FirebaseAuth.instance.currentUser!.uid;
                                final batch = db.batch();
                                final target = db
                                    .collection('profiles')
                                    .doc(uid)
                                    .collection('followers')
                                    .doc(me);
                                final source = db
                                    .collection('profiles')
                                    .doc(me)
                                    .collection('following')
                                    .doc(uid);
                                if (following) {
                                  batch.delete(target);
                                  batch.delete(source);
                                } else {
                                  final payload = {
                                    'createdAt': FieldValue.serverTimestamp(),
                                  };
                                  batch.set(target, payload);
                                  batch.set(source, payload);
                                }
                                await batch.commit().timeout(
                                  const Duration(seconds: 20),
                                );
                              } catch (e) {
                                if (context.mounted) {
                                  snack(context, accountError(e));
                                }
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(accountError(snapshot.error!)),
                ),
              if (uid.isNotEmpty)
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('social_posts')
                      .where('authorUid', isEqualTo: uid)
                      .snapshots(),
                  builder: (context, posts) {
                    final docs = [...?posts.data?.docs]
                      ..sort(
                        (a, b) =>
                            ((b.data()['createdAt'] as Timestamp?)
                                        ?.millisecondsSinceEpoch ??
                                    0)
                                .compareTo(
                                  (a.data()['createdAt'] as Timestamp?)
                                          ?.millisecondsSinceEpoch ??
                                      0,
                                ),
                      );
                    return Column(
                      children: [
                        for (final post in docs)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _SocialPost(
                              key: ValueKey(post.id),
                              post: post,
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          );
        },
      ),
    ),
  );
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
  late final _bio = TextEditingController(text: txt(widget.data, 'bio'));
  late final _link = TextEditingController(text: txt(widget.data, 'link'));
  late String _photo = txt(widget.data, 'photo');
  bool _busy = false, _picking = false;
  @override
  void dispose() {
    _bio.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: bi('Edit profile', 'சுயவிவரத்தைத் திருத்து'),
    children: [
      Center(child: profileAvatar(_photo)),
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
      const SizedBox(height: 24),
      LiquidButton(
        label: 'Save',
        busy: _busy,
        onPressed: () async {
          if (_busy || _picking) return;
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
                  'photo': _photo,
                  'bio': _bio.text.trim(),
                  'link': _link.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true))
                .timeout(const Duration(seconds: 20));
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
