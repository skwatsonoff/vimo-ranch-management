part of 'main.dart';

Future<String?> compressSocialPhoto(String source) async {
  final bytes = await compute(_socialPhotoEncode, socialPhotoBytes(source));
  return bytes == null ? null : 'data:image/jpeg;base64,${base64Encode(bytes)}';
}

Uint8List? _socialPhotoEncode(Uint8List bytes) {
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = image_lib.bakeOrientation(decoded);
  var resized = oriented.width >= oriented.height
      ? image_lib.copyResize(oriented, width: math.min(oriented.width, 1600))
      : image_lib.copyResize(oriented, height: math.min(oriented.height, 1600));
  for (final quality in const [92, 88, 84, 80]) {
    final encoded = Uint8List.fromList(
      image_lib.encodeJpg(resized, quality: quality),
    );
    if (encoded.length <= 440000) return encoded;
  }
  for (final dimension in [1280, 1080, 960]) {
    resized = oriented.width >= oriented.height
        ? image_lib.copyResize(
            oriented,
            width: math.min(oriented.width, dimension),
          )
        : image_lib.copyResize(
            oriented,
            height: math.min(oriented.height, dimension),
          );
    final encoded = Uint8List.fromList(
      image_lib.encodeJpg(resized, quality: 84),
    );
    if (encoded.length <= 440000) return encoded;
  }
  return null;
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
  Future<List<SocialPostRecord>>? _feed;
  @override
  void initState() {
    super.initState();
    _refreshFeed();
  }

  void _refreshFeed() {
    _feed = firebaseReady && FirebaseAuth.instance.currentUser != null
        ? SocialFeed.load()
        : null;
  }

  @override
  Widget build(BuildContext context) => Shell(
    child: Column(
      children: [
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
              : FutureBuilder(
                  future: _feed,
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
                    final docs = snapshot.data!;
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
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  BytesBuilder _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _audio;
  Completer<void>? _audioDone;
  Timer? _timer;
  bool _pickingPhoto = false;
  bool _recording = false, _busy = false, _stopping = false;
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
    _seconds = toInt(draft['seconds']);
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
                : accountUsername,
            style: const TextStyle(
              color: _blue,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          MentionInput(
            controller: _text,
            minLines: 5,
            maxLines: 10,
            maxLength: 2000,
            hint: bi(
              'What would you like to share?',
              'எதைப் பகிர விரும்புகிறீர்கள்?',
            ),
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
                          final picked = await pickImageDataUrl(social: true);
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
                              'mentions': mentionSelections[_text] ?? const [],
                              'photo': _photo,
                              'voice': _voice,
                              'voiceSeconds': _seconds,
                              'tile': false,
                              'createdAt': FieldValue.serverTimestamp(),
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
  final SocialPostRecord post;
  const _SocialPost({super.key, required this.post});
  @override
  State<_SocialPost> createState() => _SocialPostState();
}

class _SocialPostState extends State<_SocialPost> {
  bool _busy = false;
  bool _hidden = false;
  bool _commentsVisible = false;
  late final _likes = widget.post.reference.collection('likes').snapshots();
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _author =
      FirebaseFirestore.instance
          .collection('profiles')
          .doc(txt(widget.post.data(), 'authorUid'))
          .get();

  late final Future<int?> _commentCount = widget.post.reference
      .collection('comments')
      .count()
      .get()
      .then((result) => result.count)
      .catchError((_) => null);

  String _relative(Timestamp? stamp) {
    if (stamp == null) return bi('Sending', 'அனுப்புகிறது');
    final elapsed = DateTime.now().difference(stamp.toDate());
    if (elapsed.inMinutes < 1) return bi('Just now', 'இப்போது');
    if (elapsed.inHours < 1) {
      return bi(
        '${elapsed.inMinutes} min ago',
        '${elapsed.inMinutes} நிமிடம் முன்',
      );
    }
    if (elapsed.inDays < 1) {
      return bi('${elapsed.inHours} h ago', '${elapsed.inHours} மணி முன்');
    }
    if (elapsed.inDays == 1) return bi('Yesterday', 'நேற்று');
    if (elapsed.inDays < 7) {
      return bi('${elapsed.inDays} days ago', '${elapsed.inDays} நாள் முன்');
    }
    if (elapsed.inDays < 365) {
      final weeks = math.max(1, elapsed.inDays ~/ 7);
      return bi('$weeks w ago', '$weeks வாரம் முன்');
    }
    final years = math.max(1, elapsed.inDays ~/ 365);
    return bi('$years y ago', '$years ஆண்டு முன்');
  }

  Future<void> _deletePost() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const SquircleBorder(radius: Gold.r27),
        title: Text(bi('Delete this post?', 'இந்தப் பதிவை நீக்கவா?')),
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
    if (yes != true) return;
    await widget.post.reference.delete().timeout(
      CloudSyncService.networkTimeout,
    );
  }

  Future<void> _showLikes() async {
    final likes = await widget.post.reference.collection('likes').get();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Glass(
        radius: Gold.r34,
        opacity: .96,
        child: SafeArea(
          child: SizedBox(
            height: math.min(420, 100 + likes.docs.length * 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${likes.size} ${bi('likes', 'விருப்பங்கள்')}',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      for (final like in likes.docs)
                        FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          future: FirebaseFirestore.instance
                              .collection('profiles')
                              .doc(like.id)
                              .get(),
                          builder: (context, profile) {
                            final data =
                                profile.data?.data() ??
                                const <String, dynamic>{};
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: profileAvatar(
                                txt(data, 'photo'),
                                radius: 21,
                              ),
                              title: Text(
                                txt(
                                  data,
                                  'displayName',
                                  txt(
                                    data,
                                    'username',
                                    bi('VIMO member', 'VIMO உறுப்பினர்'),
                                  ),
                                ),
                              ),
                              subtitle: Text(
                                txt(data, 'username'),
                                style: const TextStyle(color: Ink.violetDeep),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                push(
                                  this.context,
                                  SocialProfileScreen(uid: like.id),
                                );
                              },
                            );
                          },
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

  Future<void> _reportPost() async {
    final uid = signedInUid;
    if (uid.isEmpty) return;
    await widget.post.reference.collection('reports').doc(uid).set({
      'reporterUid': uid,
      'reason': 'reported from post menu',
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted)
      snack(context, bi('Post reported', 'பதிவு புகாரளிக்கப்பட்டது'));
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
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
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: _author,
                    builder: (_, profile) => profileAvatar(
                      txt(profile.data?.data() ?? {}, 'photo'),
                      radius: 24,
                      label: txt(p, 'authorName'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => push(
                            context,
                            SocialProfileScreen(uid: txt(p, 'authorUid')),
                          ),
                          child:
                              FutureBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                future: _author,
                                builder: (_, profile) => Text(
                                  txt(
                                    profile.data?.data() ?? {},
                                    'displayName',
                                    txt(p, 'authorName'),
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                        ),
                        Text(
                          _relative(stamp),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Ink.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    color: const Color(0xF5FFFFFF),
                    shape: const SquircleBorder(radius: Gold.r21),
                    icon: const Icon(CupertinoIcons.ellipsis, size: 22),
                    onSelected: (value) async {
                      try {
                        if (value == 'delete') await _deletePost();
                        if (value == 'likes') await _showLikes();
                        if (value == 'hide') setState(() => _hidden = true);
                        if (value == 'report') await _reportPost();
                      } catch (error) {
                        if (mounted) snack(context, accountError(error));
                      }
                    },
                    itemBuilder: (_) => [
                      if (p['authorUid'] == signedInUid)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(bi('Delete', 'நீக்கு')),
                        ),
                      PopupMenuItem(
                        value: 'likes',
                        child: Text(bi('Who liked this', 'விரும்பியவர்கள்')),
                      ),
                      PopupMenuItem(
                        value: 'hide',
                        child: Text(
                          bi('I am not interested', 'எனக்கு விருப்பமில்லை'),
                        ),
                      ),
                      if (p['authorUid'] != signedInUid)
                        PopupMenuItem(
                          value: 'report',
                          child: Text(
                            bi('Report this post', 'இந்தப் பதிவைப் புகாரளி'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (photo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.memory(
                      socialPhotoBytes(photo),
                      width: double.infinity,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, _, _) => Text(
                        bi('Photo unavailable', 'புகைப்படம் கிடைக்கவில்லை'),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (txt(p, 'text').isNotEmpty)
                MentionText(
                  txt(p, 'text'),
                  mentions: p['mentions'] is List
                      ? List.from(p['mentions'])
                      : const [],
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
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
                      GestureDetector(
                        onLongPress: snapshot.hasData ? _showLikes : null,
                        child: TextButton.icon(
                          onPressed: _busy || !snapshot.hasData
                              ? null
                              : () async {
                                  _busy = true;
                                  try {
                                    final ref = widget.post.reference
                                        .collection('likes')
                                        .doc(
                                          FirebaseAuth
                                              .instance
                                              .currentUser!
                                              .uid,
                                        );
                                    if (liked) {
                                      await ref.delete();
                                    } else {
                                      await ref.set({
                                        'createdAt':
                                            FieldValue.serverTimestamp(),
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
                                    _busy = false;
                                  }
                                },
                          icon: Icon(
                            liked
                                ? CupertinoIcons.heart_fill
                                : CupertinoIcons.heart,
                            color: liked ? Colors.pink : _blue,
                          ),
                          label: Text(
                            '${snapshot.data?.size ?? 0}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Ink.body,
                            ),
                          ),
                        ),
                      ),
                      FutureBuilder<int?>(
                        future: _commentCount,
                        builder: (context, count) => TextButton.icon(
                          onPressed: () => setState(
                            () => _commentsVisible = !_commentsVisible,
                          ),
                          icon: const Icon(CupertinoIcons.chat_bubble),
                          label: Text(
                            count.data == null
                                ? bi('Comments', 'கருத்துகள்')
                                : '${count.data}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Ink.body,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (_commentsVisible)
                _SocialComments(post: widget.post.reference),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.only(top: 8),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0x167B61D1))),
    ),
    child: Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
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
                shrinkWrap: true,
                children: [
                  for (final doc in snapshot.data!.docs)
                    _SocialCommentCard(
                      comment: doc,
                      onReply: () {
                        final username = txt(
                          doc.data(),
                          'authorUsername',
                          txt(doc.data(), 'authorName'),
                        );
                        _text.text = '$username ';
                        _text.selection = TextSelection.collapsed(
                          offset: _text.text.length,
                        );
                        mentionSelections[_text] = [
                          {
                            'uid': txt(doc.data(), 'authorUid'),
                            'username': username,
                            'start': 0,
                            'end': username.length,
                          },
                        ];
                      },
                    ),
                ],
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: MentionInput(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    hint: bi('Write a comment', 'கருத்தை எழுதுங்கள்'),
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
                              'authorName': currentUserName(),
                              'authorUsername': accountUsername,
                              'ranchId': ranchId(),
                              'text': _text.text.trim(),
                              'mentions': mentionSelections[_text] ?? const [],
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            _text.clear();
                          } catch (_) {
                            if (context.mounted) {
                              snack(context, ui('Unable to save. Try again.'));
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
  );
}

class _SocialCommentCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> comment;
  final VoidCallback onReply;
  const _SocialCommentCard({required this.comment, required this.onReply});
  @override
  State<_SocialCommentCard> createState() => _SocialCommentCardState();
}

class _SocialCommentCardState extends State<_SocialCommentCard> {
  bool _likeBusy = false;
  late final _likes = widget.comment.reference.collection('likes').snapshots();
  late final _profile = FirebaseFirestore.instance
      .collection('profiles')
      .doc(txt(widget.comment.data(), 'authorUid'))
      .get();

  String _ago(Timestamp? stamp) {
    if (stamp == null) return bi('now', 'இப்போது');
    final elapsed = DateTime.now().difference(stamp.toDate());
    if (elapsed.inMinutes < 1) return bi('now', 'இப்போது');
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m';
    if (elapsed.inDays < 1) return '${elapsed.inHours}h';
    return '${elapsed.inDays}d';
  }

  Future<void> _longPress() async {
    final own = txt(widget.comment.data(), 'authorUid') == signedInUid;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Glass(
        radius: Gold.r34,
        opacity: .96,
        child: SafeArea(
          child: ListTile(
            leading: Icon(
              own
                  ? CupertinoIcons.trash
                  : CupertinoIcons.exclamationmark_triangle,
            ),
            title: Text(
              own
                  ? bi('Delete comment', 'கருத்தை நீக்கு')
                  : bi('Report comment', 'கருத்தைப் புகாரளி'),
            ),
            onTap: () => Navigator.pop(context, own ? 'delete' : 'report'),
          ),
        ),
      ),
    );
    if (action == 'delete') await widget.comment.reference.delete();
    if (action == 'report' && signedInUid.isNotEmpty) {
      await widget.comment.reference
          .collection('reports')
          .doc(signedInUid)
          .set({
            'reporterUid': signedInUid,
            'reason': 'reported from comment',
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (mounted)
        snack(context, bi('Comment reported', 'கருத்து புகாரளிக்கப்பட்டது'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.comment.data();
    return GestureDetector(
      onLongPress: _longPress,
      child: Glass(
        radius: Gold.r21,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: _profile,
              builder: (_, snapshot) => profileAvatar(
                txt(snapshot.data?.data() ?? {}, 'photo'),
                radius: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child:
                            FutureBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              future: _profile,
                              builder: (_, snapshot) => Text(
                                txt(
                                  snapshot.data?.data() ?? {},
                                  'displayName',
                                  txt(data, 'authorName'),
                                ),
                                style: const TextStyle(
                                  color: Ink.violetDeep,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                      ),
                      Text(
                        _ago(data['createdAt'] as Timestamp?),
                        style: const TextStyle(color: Ink.muted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  MentionText(
                    txt(data, 'text'),
                    mentions: data['mentions'] is List
                        ? List.from(data['mentions'])
                        : const [],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: widget.onReply,
                        icon: const Icon(CupertinoIcons.reply, size: 17),
                        label: Text(bi('Reply', 'பதில்')),
                      ),
                      const Spacer(),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _likes,
                        builder: (_, snapshot) {
                          final liked =
                              snapshot.data?.docs.any(
                                (doc) => doc.id == signedInUid,
                              ) ??
                              false;
                          return TextButton.icon(
                            onPressed: !snapshot.hasData || _likeBusy
                                ? null
                                : () async {
                                    _likeBusy = true;
                                    final ref = widget.comment.reference
                                        .collection('likes')
                                        .doc(signedInUid);
                                    try {
                                      if (liked) {
                                        await ref.delete();
                                      } else {
                                        await ref.set({
                                          'createdAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                      }
                                    } finally {
                                      _likeBusy = false;
                                    }
                                  },
                            icon: Icon(
                              liked
                                  ? CupertinoIcons.heart_fill
                                  : CupertinoIcons.heart,
                              size: 17,
                              color: liked ? Colors.pink : Ink.violetDeep,
                            ),
                            label: Text(
                              '${snapshot.data?.size ?? 0} ${bi('Like', 'விருப்பு')}',
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
