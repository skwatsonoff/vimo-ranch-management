part of 'main.dart';

Future<String?> compressSocialPhoto(String source) async {
  final bytes = await compute(_socialPhotoEncode, socialPhotoBytes(source));
  return bytes == null ? null : 'data:image/jpeg;base64,${base64Encode(bytes)}';
}

Uint8List? _socialPhotoEncode(Uint8List bytes) {
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = image_lib.bakeOrientation(decoded);
  final image = oriented.width >= oriented.height
      ? image_lib.copyResize(oriented, width: math.min(oriented.width, 640))
      : image_lib.copyResize(oriented, height: math.min(oriented.height, 640));
  final encoded = Uint8List.fromList(image_lib.encodeJpg(image, quality: 72));
  return encoded.length <= 440000 ? encoded : null;
}

Uint8List socialPhotoBytes(String source) {
  try {
    return base64Decode(source.split(',').last);
  } on FormatException {
    return Uint8List(0);
  }
}

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});
  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  Timer? _feedClock;
  DateTime _feedTime = DateTime.now();
  @override
  void initState() {
    super.initState();
    _feedClock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _feedTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    _feedClock?.cancel();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? get _feed =>
      firebaseReady && FirebaseAuth.instance.currentUser != null
      ? FirebaseFirestore.instance
            .collection('social_posts')
            .where(
              'createdAt',
              isLessThanOrEqualTo: Timestamp.fromDate(_feedTime),
            )
            .orderBy('createdAt', descending: true)
            .limit(60)
            .snapshots()
      : null;
  @override
  Widget build(BuildContext context) => Shell(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 16, 21, 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bi('The VIMO community', 'VIMO சமூகம்'),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bi(
                        'Share a moment. Ask for help.',
                        'அனுபவங்களைப் பகிருங்கள். உதவி கேளுங்கள்.',
                      ),
                      style: const TextStyle(color: Ink.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _feed == null
              ? Center(
                  child: Text(
                    bi(
                      'Sign in to connect with the community.',
                      'சமூகத்துடன் இணைய உள்நுழையவும்.',
                    ),
                  ),
                )
              : StreamBuilder(
                  stream: _feed,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            bi(
                              'The community could not load. Check your connection and reopen Social.',
                              'சமூகப் பதிவுகளை ஏற்ற முடியவில்லை. இணையத்தைச் சரிபார்த்து மீண்டும் திறக்கவும்.',
                            ),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                CupertinoIcons.person_3,
                                size: 52,
                                color: _blue,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                bi(
                                  'Start a conversation',
                                  'உரையாடலைத் தொடங்குங்கள்',
                                ),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                bi(
                                  'Share a photo, a voice note or a question with other VIMO members.',
                                  'புகைப்படம், குரல் குறிப்பு அல்லது கேள்வியை மற்ற VIMO உறுப்பினர்களுடன் பகிருங்கள்.',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(21, 0, 21, 32),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (_, i) =>
                          _SocialPost(key: ValueKey(docs[i].id), post: docs[i]),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class SocialComposer extends StatefulWidget {
  const SocialComposer({super.key});
  @override
  State<SocialComposer> createState() => _SocialComposerState();
}

class _SocialComposerState extends State<SocialComposer> {
  String? _postId;
  DateTime? _publishAt;
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  BytesBuilder _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _audio;
  Completer<void>? _audioDone;
  Timer? _timer;
  bool _pickingPhoto = false;
  bool _recording = false, _busy = false, _tile = false, _stopping = false;
  String _photo = '', _voice = '';
  int _seconds = 0;
  bool _published = false;
  late final String _draftOwner;
  @override
  void initState() {
    super.initState();
    _draftOwner = signedInUid;
    final draft = asMap(
      asMap(settingValue('socialDrafts', {}))[_draftOwner] ?? {},
    );
    _text.text = txt(draft, 'text');
    _photo = txt(draft, 'photo');
    _voice = txt(draft, 'voice');
    _tile = draft['tile'] == true;
    _seconds = toInt(draft['seconds']);
    _publishAt = DateTime.tryParse(txt(draft, 'publishAt'));
    _postId = txt(draft, 'postId').isEmpty ? null : txt(draft, 'postId');
    _text.addListener(_persistDraft);
  }

  void _persistDraft() {
    if (_published) return;
    if (_text.text.isEmpty &&
        _photo.isEmpty &&
        _voice.isEmpty &&
        !asMap(settingValue('socialDrafts', {})).containsKey(_draftOwner)) {
      return;
    }
    unawaited(
      setSetting('socialDrafts', {
        ...asMap(settingValue('socialDrafts', {})),
        _draftOwner: {
          'text': _text.text,
          'photo': _photo,
          'voice': _voice,
          'seconds': _seconds,
          'tile': _tile,
          'publishAt': _publishAt?.toIso8601String() ?? '',
          'postId': _postId ?? '',
        },
      }),
    );
  }

  @override
  void dispose() {
    _persistDraft();
    _text.removeListener(_persistDraft);
    _text.dispose();
    _timer?.cancel();
    unawaited(_audio?.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _record() async {
    if (_busy || _stopping) return;
    try {
      if (_recording) {
        _timer?.cancel();
        setState(() => _stopping = true);
        await _recorder.stop();
        await _audioDone?.future.timeout(const Duration(seconds: 3));
        await _audio?.cancel();
        final data = _pcm.takeBytes();
        if (data.isEmpty) throw StateError('Empty recording');
        final wave = pcm16ToWave(data, sampleRate: 8000);
        if (mounted) {
          setState(() {
            _voice = base64Encode(wave);
            _recording = false;
            _stopping = false;
          });
        }
      } else {
        if (!await _recorder.hasPermission()) {
          if (mounted) snack(context, ui('Microphone permission is needed'));
          return;
        }
        _pcm = BytesBuilder(copy: false);
        _audioDone = Completer<void>();
        final stream = await _recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 8000,
            numChannels: 1,
          ),
        );
        _audio = stream.listen(
          _pcm.add,
          onDone: () {
            if (!_audioDone!.isCompleted) _audioDone!.complete();
          },
          onError: (Object e) {
            if (!_audioDone!.isCompleted) _audioDone!.complete();
          },
        );
        if (!mounted) {
          await _recorder.cancel();
          return;
        }
        setState(() {
          _seconds = 0;
          _voice = '';
          _recording = true;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _seconds++);
          if (_seconds >= 20) unawaited(_record());
        });
      }
    } catch (_) {
      _timer?.cancel();
      await _recorder.cancel();
      await _audio?.cancel();
      if (mounted) {
        setState(() {
          _recording = false;
          _stopping = false;
        });
        snack(context, ui('Unable to record. Try again.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(title: Text(bi('New post', 'புதிய பதிவு'))),
    body: Shell(
      child: ListView(
        padding: const EdgeInsets.all(21),
        children: [
          Text(
            accountUsername.isEmpty
                ? bi('Choose a username', 'பயனர்பெயரைத் தேர்ந்தெடுங்கள்')
                : '@$accountUsername',
            style: const TextStyle(
              color: _blue,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 10,
            maxLength: 2000,
            decoration: InputDecoration(
              hintText: bi(
                'What would you like to share?',
                'எதைப் பகிர விரும்புகிறீர்கள்?',
              ),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              bi('Colored text background', 'உரைக்கு வண்ணப் பின்னணி'),
            ),
            value: _tile,
            onChanged: (v) => setState(() => _tile = v),
          ),
          if (_photo.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.memory(
                base64Decode(_photo.split(',').last),
                height: 240,
                fit: BoxFit.cover,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _photo = ''),
              child: Text(bi('Remove photo', 'புகைப்படத்தை நீக்கு')),
            ),
          ],
          if (_voice.isNotEmpty) ...[
            _VoiceMessageBubble(
              key: ValueKey(_voice),
              url: '',
              encodedAudio: _voice,
              durationSeconds: _seconds,
              color: _blue,
            ),
            TextButton(
              onPressed: () => setState(() => _voice = ''),
              child: Text(bi('Remove voice', 'குரலை நீக்கு')),
            ),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy || _recording || _pickingPhoto
                    ? null
                    : () async {
                        try {
                          setState(() => _pickingPhoto = true);
                          final picked = await pickImageDataUrl();
                          final photo = picked == null
                              ? null
                              : await compressSocialPhoto(picked);
                          if (picked != null && photo == null) {
                            throw StateError('Invalid image');
                          }
                          if (mounted && photo != null) {
                            setState(() => _photo = photo);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            snack(
                              context,
                              bi(
                                'Could not load this photo.',
                                'புகைப்படத்தை ஏற்ற முடியவில்லை.',
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _pickingPhoto = false);
                        }
                      },
                icon: const Icon(CupertinoIcons.photo),
                label: Text(bi('Photo', 'புகைப்படம்')),
              ),
              OutlinedButton.icon(
                onPressed: _busy || _stopping ? null : _record,
                icon: Icon(
                  _recording ? CupertinoIcons.stop_circle : CupertinoIcons.mic,
                ),
                label: Text(
                  _recording
                      ? '${bi('Stop', 'நிறுத்து')} · $_seconds / 20 s'
                      : bi('Voice · 20 sec', 'குரல் · 20 நொடி'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(CupertinoIcons.clock),
            title: Text(
              _publishAt == null
                  ? bi('Publish now', 'இப்போதே வெளியிடு')
                  : '${bi('Scheduled', 'திட்டமிடப்பட்டது')}: ${_publishAt!.toLocal()}',
            ),
            trailing: _publishAt == null
                ? null
                : IconButton(
                    icon: const Icon(CupertinoIcons.xmark),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _publishAt = null),
                  ),
            onTap: _busy
                ? null
                : () async {
                    final time = await choosePostTime(context);
                    if (time != null && mounted) {
                      setState(() => _publishAt = time);
                    }
                  },
          ),
          FilledButton(
            onPressed: _busy || _recording || _stopping
                ? null
                : () async {
                    if (_text.text.trim().isEmpty &&
                        _photo.isEmpty &&
                        _voice.isEmpty) {
                      snack(
                        context,
                        bi(
                          'Add text, a photo or a voice note.',
                          'உரை, புகைப்படம் அல்லது குரலைச் சேர்க்கவும்.',
                        ),
                      );
                      return;
                    }
                    if (!firebaseReady ||
                        FirebaseAuth.instance.currentUser == null) {
                      snack(
                        context,
                        bi(
                          'Sign in to publish a post.',
                          'பதிவைப் பகிர உள்நுழையவும்.',
                        ),
                      );
                      return;
                    }
                    if (accountUsername.isEmpty) {
                      await push(context, const UsernameScreen());
                      if (!context.mounted || accountUsername.isEmpty) return;
                    }
                    if (_photo.length > 600000 ||
                        _voice.length > 450000 ||
                        _photo.length + _voice.length > 850000) {
                      snack(
                        context,
                        bi(
                          'This post is too large. Remove one attachment.',
                          'பதிவின் அளவு அதிகம். ஒரு இணைப்பை நீக்கவும்.',
                        ),
                      );
                      return;
                    }
                    if (_publishAt != null &&
                        !_publishAt!.isAfter(DateTime.now())) {
                      snack(
                        context,
                        bi(
                          'Choose a future time.',
                          'வருங்கால நேரத்தைத் தேர்ந்தெடுக்கவும்.',
                        ),
                      );
                      return;
                    }
                    setState(() => _busy = true);
                    try {
                      await UsernameService.refresh();
                      final db = FirebaseFirestore.instance;
                      final ref = db.collection('social_posts').doc(_postId);
                      _postId = ref.id;
                      _persistDraft();
                      await db
                          .runTransaction((tx) async {
                            final existing = await tx.get(ref);
                            if (existing.exists) return;
                            tx.set(ref, {
                              'authorUid':
                                  FirebaseAuth.instance.currentUser!.uid,
                              'ranchId': '',
                              'authorName': accountUsername,
                              'authorUsername': accountUsername,
                              'text': _text.text.trim(),
                              'photo': _photo,
                              'voice': _voice,
                              'voiceSeconds': _seconds,
                              'tile': _tile,
                              'createdAt': _publishAt == null
                                  ? FieldValue.serverTimestamp()
                                  : Timestamp.fromDate(_publishAt!),
                            });
                          })
                          .timeout(const Duration(seconds: 20));
                      _published = true;
                      final drafts = asMap(settingValue('socialDrafts', {}))
                        ..remove(_draftOwner);
                      await setSetting('socialDrafts', drafts);
                      if (context.mounted) Navigator.pop(context);
                    } catch (error) {
                      if (context.mounted) snack(context, accountError(error));
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _busy
                    ? bi('Publishing…', 'பகிர்கிறது…')
                    : bi('Publish post', 'பதிவைப் பகிர்'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SocialPost extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> post;
  const _SocialPost({super.key, required this.post});
  @override
  State<_SocialPost> createState() => _SocialPostState();
}

class _SocialPostState extends State<_SocialPost> {
  bool _busy = false;
  late final _likes = widget.post.reference.collection('likes').snapshots();
  @override
  Widget build(BuildContext context) {
    final p = widget.post.data();
    final stamp = p['createdAt'] as Timestamp?;
    final photo = txt(p, 'photo');
    return _InsetGroup(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('profiles')
                        .doc(txt(p, 'authorUid'))
                        .snapshots(),
                    builder: (_, profile) => profileAvatar(
                      txt(profile.data?.data() ?? {}, 'photo'),
                      radius: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton(
                          onPressed: () => push(
                            context,
                            SocialProfileScreen(uid: txt(p, 'authorUid')),
                          ),
                          child: Text(
                            txt(p, 'authorUsername', txt(p, 'authorName')),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '@${txt(p, 'authorUsername', txt(p, 'authorName'))} · ${stamp == null ? bi('Sending', 'அனுப்புகிறது') : '${stamp.toDate().day}/${stamp.toDate().month}'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Ink.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (p['authorUid'] == FirebaseAuth.instance.currentUser?.uid)
                    IconButton(
                      tooltip: bi('Schedule post', 'பதிவைத் திட்டமிடு'),
                      icon: const Icon(CupertinoIcons.clock, size: 18),
                      onPressed: () async {
                        final time = await choosePostTime(context);
                        if (time == null) return;
                        try {
                          await widget.post.reference
                              .update({'createdAt': Timestamp.fromDate(time)})
                              .timeout(CloudSyncService.networkTimeout);
                        } catch (e) {
                          if (context.mounted) snack(context, accountError(e));
                        }
                      },
                    ),
                  if (p['authorUid'] == FirebaseAuth.instance.currentUser?.uid)
                    IconButton(
                      tooltip: ui('Delete'),
                      icon: const Icon(CupertinoIcons.trash, size: 18),
                      onPressed: () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(
                              bi('Delete this post?', 'இந்தப் பதிவை நீக்கவா?'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const AppText('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const AppText('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true) {
                          try {
                            await widget.post.reference.delete().timeout(
                              CloudSyncService.networkTimeout,
                            );
                          } catch (_) {
                            if (context.mounted) {
                              snack(
                                context,
                                ui('Unable to delete. Try again.'),
                              );
                            }
                          }
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (photo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      socialPhotoBytes(photo),
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text(
                        bi('Photo unavailable', 'புகைப்படம் கிடைக்கவில்லை'),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (txt(p, 'text').isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: p['tile'] == true
                      ? const EdgeInsets.all(24)
                      : EdgeInsets.zero,
                  decoration: p['tile'] == true
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [Color(0xffdbeafe), Color(0xffede9fe)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        )
                      : null,
                  child: Text(
                    txt(p, 'text'),
                    style: TextStyle(
                      fontSize: p['tile'] == true ? 24 : 16,
                      height: 1.5,
                      fontWeight: p['tile'] == true
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              if (txt(p, 'voice').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _VoiceMessageBubble(
                    url: '',
                    encodedAudio: txt(p, 'voice'),
                    durationSeconds: toInt(p['voiceSeconds']),
                    color: _blue,
                  ),
                ),
              const SizedBox(height: 12),
              StreamBuilder(
                stream: _likes,
                builder: (context, snapshot) {
                  final liked =
                      snapshot.data?.docs.any(
                        (d) => d.id == FirebaseAuth.instance.currentUser?.uid,
                      ) ??
                      false;
                  return Wrap(
                    spacing: 16,
                    children: [
                      TextButton.icon(
                        onPressed: _busy || !snapshot.hasData
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                try {
                                  final ref = widget.post.reference
                                      .collection('likes')
                                      .doc(
                                        FirebaseAuth.instance.currentUser!.uid,
                                      );
                                  if (liked) {
                                    await ref.delete();
                                  } else {
                                    await ref.set({
                                      'createdAt': FieldValue.serverTimestamp(),
                                    });
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    snack(
                                      context,
                                      ui('Unable to save. Try again.'),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        icon: Icon(
                          liked
                              ? CupertinoIcons.heart_fill
                              : CupertinoIcons.heart,
                          color: liked ? Colors.pink : _blue,
                        ),
                        label: Text(
                          '${snapshot.data?.size ?? 0} ${bi('likes', 'விருப்பங்கள்')}',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => push(
                          context,
                          _SocialComments(post: widget.post.reference),
                        ),
                        icon: const Icon(CupertinoIcons.chat_bubble),
                        label: Text(bi('Comments', 'கருத்துகள்')),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SocialComments extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> post;
  const _SocialComments({required this.post});
  @override
  State<_SocialComments> createState() => _SocialCommentsState();
}

class _SocialCommentsState extends State<_SocialComments> {
  final _text = TextEditingController();
  bool _busy = false;
  late final _stream = widget.post
      .collection('comments')
      .orderBy('createdAt')
      .limit(100)
      .snapshots();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(title: Text(bi('Comments', 'கருத்துகள்'))),
    body: Shell(
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      bi(
                        'Could not load comments.',
                        'கருத்துகளை ஏற்ற முடியவில்லை.',
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      bi(
                        'Be the first to comment.',
                        'முதல் கருத்தைப் பகிருங்கள்.',
                      ),
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final doc in snapshot.data!.docs)
                      ListTile(
                        title: Text('@${txt(doc.data(), 'authorName')}'),
                        subtitle: Text(txt(doc.data(), 'text')),
                        trailing:
                            doc.data()['authorUid'] ==
                                FirebaseAuth.instance.currentUser?.uid
                            ? IconButton(
                                tooltip: ui('Delete'),
                                icon: const Icon(
                                  CupertinoIcons.trash,
                                  size: 18,
                                ),
                                onPressed: () async {
                                  try {
                                    await doc.reference.delete();
                                  } catch (_) {
                                    if (context.mounted) {
                                      snack(
                                        context,
                                        ui('Unable to delete. Try again.'),
                                      );
                                    }
                                  }
                                },
                              )
                            : null,
                      ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        hintText: bi('Write a comment', 'கருத்தை எழுதுங்கள்'),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: ui('Send'),
                    onPressed: _busy
                        ? null
                        : () async {
                            if (_text.text.trim().isEmpty) return;
                            if (accountUsername.isEmpty) {
                              await push(context, const UsernameScreen());
                              if (!mounted || accountUsername.isEmpty) return;
                            }
                            setState(() => _busy = true);
                            try {
                              await widget.post.collection('comments').add({
                                'authorUid':
                                    FirebaseAuth.instance.currentUser!.uid,
                                'authorName': accountUsername,
                                'ranchId': ranchId(),
                                'text': _text.text.trim(),
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                              _text.clear();
                            } catch (_) {
                              if (context.mounted) {
                                snack(
                                  context,
                                  ui('Unable to save. Try again.'),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    icon: const Icon(CupertinoIcons.arrow_up),
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
