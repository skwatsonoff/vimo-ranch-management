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

/// A post being published in the background, so the composer can close at
/// once while a slim bar on the feed shows its progress.
class SocialUpload {
  final String id, draftOwner, photo, status, error;
  final Map<String, dynamic> payload;
  const SocialUpload({
    required this.id,
    required this.draftOwner,
    required this.payload,
    this.photo = '',
    this.status = 'posting',
    this.error = '',
  });
  SocialUpload withStatus(String status, [String error = '']) => SocialUpload(
    id: id,
    draftOwner: draftOwner,
    payload: payload,
    photo: photo,
    status: status,
    error: error,
  );
}

class SocialUploadService {
  const SocialUploadService._();
  static final current = ValueNotifier<SocialUpload?>(null);

  /// Bumped after each successful post so an open feed reloads.
  static final published = ValueNotifier<int>(0);

  static Future<void> publish(SocialUpload upload) async {
    current.value = upload.withStatus('posting');
    try {
      final db = FirebaseFirestore.instance;
      final ref = db.collection('social_posts').doc(upload.id);
      await db
          .runTransaction((tx) async {
            final existing = await tx.get(ref);
            if (existing.exists) return;
            tx.set(ref, {
              ...upload.payload,
              'createdAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 45));
      final drafts = asMap(settingValue('socialDrafts', {}));
      if (txt(asMap(drafts[upload.draftOwner] ?? {}), 'postId') == upload.id) {
        drafts.remove(upload.draftOwner);
        await setSetting('socialDrafts', drafts);
      }
      if (current.value?.id != upload.id) return;
      current.value = upload.withStatus('done');
      published.value++;
      Timer(const Duration(milliseconds: 2200), () {
        if (current.value?.id == upload.id && current.value?.status == 'done') {
          current.value = null;
        }
      });
    } catch (error) {
      // The draft stays saved, so Retry (or reopening the composer) resends
      // the same post id without creating a duplicate.
      if (current.value?.id == upload.id) {
        current.value = upload.withStatus('failed', accountError(error));
      }
    }
  }
}

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});
  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  final _scroll = ScrollController();
  List<SocialPostRecord>? _posts;
  Object? _error;
  Timer? _poll;
  Timer? _toastTimer;

  /// New posts noticed at the top that the list does not show yet.
  List<SocialPostRecord> _waiting = const [];

  /// Short confirmation after a pull to refresh ("3 new posts").
  String _toast = '';

  bool get _signedIn =>
      firebaseReady && FirebaseAuth.instance.currentUser != null;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _checkNew());
    SocialUploadService.published.addListener(_afterPublish);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _toastTimer?.cancel();
    SocialUploadService.published.removeListener(_afterPublish);
    _scroll.dispose();
    super.dispose();
  }

  void _afterPublish() {
    unawaited(_load());
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(0, duration: Gold.slow, curve: Curves.easeOutCubic),
      );
    }
  }

  Future<void> _load({bool announce = false}) async {
    if (!_signedIn) return;
    final before = _posts?.map((p) => p.id).toSet();
    try {
      final posts = await SocialFeed.load();
      if (!mounted) return;
      final fresh = before == null
          ? 0
          : posts.where((p) => !before.contains(p.id)).length;
      setState(() {
        _posts = posts;
        _error = null;
        _waiting = const [];
      });
      if (announce) {
        _showToast(
          fresh == 0
              ? bi('You’re up to date', 'புதிய பதிவுகள் இல்லை')
              : fresh == 1
              ? bi('1 new post', '1 புதிய பதிவு')
              : bi('$fresh new posts', '$fresh புதிய பதிவுகள்'),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _toast = '');
    });
  }

  Future<void> _checkNew() async {
    final posts = _posts;
    // Only while this tab is on screen, and only a tiny id-only query.
    if (!mounted ||
        posts == null ||
        !_signedIn ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    try {
      final latest = await SocialFeed.latest();
      if (!mounted) return;
      final known = posts.map((p) => p.id).toSet();
      final waiting = latest
          .where(
            (p) =>
                !known.contains(p.id) &&
                txt(p.data(), 'authorUid') != signedInUid,
          )
          .toList();
      if (waiting.length != _waiting.length) {
        setState(() => _waiting = waiting);
      }
    } catch (_) {}
  }

  Future<void> _showWaiting() async {
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        0,
        duration: Gold.slow,
        curve: Curves.easeOutCubic,
      );
    }
    await _load();
  }

  Widget _message(Widget child) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: Center(
          child: Padding(padding: const EdgeInsets.all(32), child: child),
        ),
      ),
    ),
  );

  Widget _feed() {
    if (_error != null && _posts == null) {
      return _message(
        Text(
          bi(
            'The community could not load. Pull down to try again.',
            'சமூகப் பதிவுகளை ஏற்ற முடியவில்லை. மீண்டும் முயல கீழே இழுக்கவும்.',
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    final posts = _posts;
    if (posts == null) {
      return const Center(child: CupertinoActivityIndicator(radius: 13));
    }
    if (posts.isEmpty) {
      return _message(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.person_3, size: 52, color: _blue),
            const SizedBox(height: 16),
            Text(
              bi('Start a conversation', 'உரையாடலைத் தொடங்குங்கள்'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
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
      );
    }
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(21, 8, 21, 120),
      itemCount: posts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (_, i) =>
          _SocialPost(key: ValueKey(posts[i].id), post: posts[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_signedIn) {
      return Shell(
        child: Center(
          child: Text(
            bi(
              'Sign in to connect with the community.',
              'சமூகத்துடன் இணைய உள்நுழையவும்.',
            ),
          ),
        ),
      );
    }
    final pill = _waiting.isNotEmpty
        ? (_waiting.length == 1
              ? bi('1 new post', '1 புதிய பதிவு')
              : bi(
                  '${_waiting.length} new posts',
                  '${_waiting.length} புதிய பதிவுகள்',
                ))
        : _toast;
    return Shell(
      child: Column(
        children: [
          const _SocialUploadBar(),
          Expanded(
            child: Stack(
              children: [
                RefreshIndicator.adaptive(
                  color: Ink.violetDeep,
                  onRefresh: () => _load(announce: _posts != null),
                  child: _feed(),
                ),
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: Gold.base,
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, -.6),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: pill.isEmpty
                          ? const SizedBox.shrink()
                          : _NewPostsPill(
                              key: ValueKey(pill),
                              label: pill,
                              arrow: _waiting.isNotEmpty,
                              onTap: _waiting.isNotEmpty ? _showWaiting : null,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewPostsPill extends StatelessWidget {
  final String label;
  final bool arrow;
  final VoidCallback? onTap;
  const _NewPostsPill({
    super.key,
    required this.label,
    required this.arrow,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          gradient: const LinearGradient(colors: [Ink.violet, Ink.violetDeep]),
          shadows: [
            BoxShadow(
              color: Ink.violetDeep.withValues(alpha: .32),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (arrow) ...[
              const Icon(
                CupertinoIcons.arrow_up,
                size: 15,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Slim bar at the top of the feed while a post uploads.
class _SocialUploadBar extends StatelessWidget {
  const _SocialUploadBar();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SocialUpload?>(
    valueListenable: SocialUploadService.current,
    builder: (context, upload, _) => AnimatedSize(
      duration: Gold.base,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: upload == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(21, 4, 21, 8),
              child: Glass(
                radius: 18,
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox.square(
                        dimension: 36,
                        child: upload.photo.isNotEmpty
                            ? Image.memory(
                                socialPhotoBytes(upload.photo),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                cacheWidth: 96,
                              )
                            : const ColoredBox(
                                color: Ink.lavender,
                                child: Icon(
                                  CupertinoIcons.text_bubble,
                                  size: 18,
                                  color: Ink.violetDeep,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            switch (upload.status) {
                              'done' => bi('Posted', 'பகிரப்பட்டது'),
                              'failed' => bi(
                                'Could not post',
                                'பகிர முடியவில்லை',
                              ),
                              _ => bi('Posting…', 'பகிர்கிறது…'),
                            },
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: upload.status == 'failed'
                                  ? Ink.redText
                                  : Ink.navy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: upload.status == 'posting'
                                ? LinearProgressIndicator(
                                    minHeight: 4,
                                    color: Ink.violetDeep,
                                    backgroundColor: Ink.violetDeep.withValues(
                                      alpha: .12,
                                    ),
                                  )
                                : LinearProgressIndicator(
                                    minHeight: 4,
                                    value: 1,
                                    color: upload.status == 'done'
                                        ? Ink.green
                                        : Ink.red,
                                    backgroundColor: Colors.transparent,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    if (upload.status == 'done')
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          CupertinoIcons.check_mark_circled_solid,
                          color: Ink.green,
                        ),
                      ),
                    if (upload.status == 'failed') ...[
                      TextButton(
                        onPressed: () =>
                            unawaited(SocialUploadService.publish(upload)),
                        child: Text(bi('Retry', 'மீண்டும்')),
                      ),
                      IconButton(
                        tooltip: ui('Close'),
                        icon: const Icon(CupertinoIcons.xmark, size: 18),
                        onPressed: () =>
                            SocialUploadService.current.value = null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
    ),
  );
}

/// Full-screen photo with pinch and double-tap zoom. Post photos can be saved
/// to the phone from the menu; profile pictures are view-only.
class SocialPhotoViewer extends StatefulWidget {
  final ImageProvider image;
  final Uint8List? saveBytes;
  final Object? heroTag;
  const SocialPhotoViewer({
    super.key,
    required this.image,
    this.saveBytes,
    this.heroTag,
  });
  @override
  State<SocialPhotoViewer> createState() => _SocialPhotoViewerState();
}

class _SocialPhotoViewerState extends State<SocialPhotoViewer> {
  final _zoom = TransformationController();
  TapDownDetails? _doubleTap;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_zoom.value.getMaxScaleOnAxis() > 1.01) {
      _zoom.value = Matrix4.identity();
      return;
    }
    final at = _doubleTap?.localPosition ?? Offset.zero;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-at.dx * 1.5, -at.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
  }

  // Runs straight from the menu tap (no awaits before the browser call) so
  // iPhone Safari may open its share sheet.
  void _save() {
    final bytes = widget.saveBytes;
    if (bytes == null || bytes.isEmpty) return;
    final name = 'vimo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    if (kIsWeb) {
      unawaited(
        _browserRuntime.saveImage(bytes, name).then((result) {
          if (!mounted) return;
          if (result == 'saved') {
            snack(context, bi('Photo saved', 'புகைப்படம் சேமிக்கப்பட்டது'));
          } else if (result == 'failed') {
            snack(
              context,
              bi(
                'Could not save the photo',
                'புகைப்படத்தைச் சேமிக்க முடியவில்லை',
              ),
            );
          }
        }),
      );
      return;
    }
    unawaited(
      FilePicker.platform
          .saveFile(
            dialogTitle: bi('Save photo', 'புகைப்படத்தைச் சேமி'),
            fileName: name,
            type: FileType.image,
            bytes: bytes,
          )
          .then((path) {
            if (mounted && path != null) {
              snack(context, bi('Photo saved', 'புகைப்படம் சேமிக்கப்பட்டது'));
            }
          })
          .catchError((Object _) {
            if (mounted) {
              snack(
                context,
                bi(
                  'Could not save the photo',
                  'புகைப்படத்தைச் சேமிக்க முடியவில்லை',
                ),
              );
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget photo = Image(
      image: widget.image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Center(
        child: Text(
          bi('Could not open the photo', 'புகைப்படத்தைத் திறக்க முடியவில்லை'),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
    if (widget.heroTag != null) {
      photo = Hero(tag: widget.heroTag!, child: photo);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: ui('Close'),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: .14),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(CupertinoIcons.xmark, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (widget.saveBytes != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PopupMenuButton<String>(
                tooltip: ui('More'),
                color: const Color(0xF5FFFFFF),
                shape: const SquircleBorder(radius: Gold.r21),
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'save',
                    onTap: _save,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          color: Ink.violetDeep,
                        ),
                        const SizedBox(width: 12),
                        Text(bi('Save photo', 'புகைப்படத்தைச் சேமி')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onDoubleTapDown: (details) => _doubleTap = details,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _zoom,
          minScale: 1,
          maxScale: 5,
          child: SizedBox.expand(child: photo),
        ),
      ),
    );
  }
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
                    } catch (error) {
                      if (context.mounted) snack(context, accountError(error));
                      if (mounted) setState(() => _busy = false);
                      return;
                    }
                    final ref = FirebaseFirestore.instance
                        .collection('social_posts')
                        .doc(_postId);
                    _postId = ref.id;
                    // The draft (with this post id) stays saved until the
                    // upload succeeds, so a failure can be retried safely.
                    _persistDraft();
                    _published = true;
                    unawaited(
                      SocialUploadService.publish(
                        SocialUpload(
                          id: ref.id,
                          draftOwner: _draftOwner,
                          photo: _photo,
                          payload: {
                            'authorUid': FirebaseAuth.instance.currentUser!.uid,
                            'ranchId': '',
                            'authorName': accountUsername,
                            'authorUsername': accountUsername,
                            'text': _text.text.trim(),
                            'mentions': mentionSelections[_text] ?? const [],
                            'photo': _photo,
                            'voice': _voice,
                            'voiceSeconds': _seconds,
                            'tile': false,
                          },
                        ),
                      ),
                    );
                    if (context.mounted) Navigator.pop(context);
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
                      if (p['authorUid'] != signedInUid)
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
                  child: GestureDetector(
                    onTap: () {
                      final bytes = socialPhotoBytes(photo);
                      if (bytes.isEmpty) return;
                      Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          opaque: false,
                          barrierColor: Colors.black,
                          transitionDuration: Gold.base,
                          reverseTransitionDuration: Gold.fast,
                          pageBuilder: (_, _, _) => SocialPhotoViewer(
                            image: MemoryImage(bytes),
                            saveBytes: bytes,
                            heroTag: 'post-photo-${widget.post.id}',
                          ),
                          transitionsBuilder: (_, animation, _, child) =>
                              FadeTransition(opacity: animation, child: child),
                        ),
                      );
                    },
                    child: Hero(
                      tag: 'post-photo-${widget.post.id}',
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

/// The comment a reply answers. Stored inside the reply's mentions list (an
/// entry with `replyTo`), which the existing comment rules already accept.
String commentParentId(Map<String, dynamic> comment) {
  final mentions = comment['mentions'];
  if (mentions is! List) return '';
  for (final entry in mentions.whereType<Map>()) {
    final parent = txt(asMap(entry), 'replyTo');
    if (parent.isNotEmpty) return parent;
  }
  return '';
}

/// Groups comments into threads: each top-level comment followed by every
/// reply beneath it (replies to replies stay in the same thread), in time
/// order.
List<
  (
    QueryDocumentSnapshot<Map<String, dynamic>>,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
  )
>
commentThreads(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final byId = {for (final d in docs) d.id: d};
  String rootOf(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    var current = doc;
    final seen = <String>{};
    while (seen.add(current.id)) {
      final parent = byId[commentParentId(current.data())];
      if (parent == null) break;
      current = parent;
    }
    return current.id;
  }

  final replies = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  final roots = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final doc in docs) {
    final root = rootOf(doc);
    if (root == doc.id) {
      roots.add(doc);
    } else {
      replies.putIfAbsent(root, () => []).add(doc);
    }
  }
  return [for (final root in roots) (root, replies[root.id] ?? const [])];
}

class _SocialComments extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> post;
  const _SocialComments({required this.post});
  @override
  State<_SocialComments> createState() => _SocialCommentsState();
}

class _SocialCommentsState extends State<_SocialComments> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  QueryDocumentSnapshot<Map<String, dynamic>>? _replyTo;
  final _expanded = <String>{};
  late final _stream = widget.post
      .collection('comments')
      .orderBy('createdAt')
      .limit(200)
      .snapshots();
  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _username(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      txt(doc.data(), 'authorUsername', txt(doc.data(), 'authorName'));

  void _reply(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final username = _username(doc);
    final own = txt(doc.data(), 'authorUid') == signedInUid;
    setState(() => _replyTo = doc);
    _text.text = own || username.isEmpty ? '' : '$username ';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    mentionSelections[_text] = [
      if (!own && username.isNotEmpty)
        {
          'uid': txt(doc.data(), 'authorUid'),
          'username': username,
          'start': 0,
          'end': username.length,
        },
    ];
    _focus.requestFocus();
  }

  Future<void> _send() async {
    if (_busy || _text.text.trim().isEmpty) return;
    if (accountUsername.isEmpty) {
      await push(context, const UsernameScreen());
      if (!mounted || accountUsername.isEmpty) return;
    }
    setState(() => _busy = true);
    final parent = _replyTo;
    try {
      await widget.post.collection('comments').add({
        'authorUid': FirebaseAuth.instance.currentUser!.uid,
        'authorName': currentUserName(),
        'authorUsername': accountUsername,
        'ranchId': ranchId(),
        'text': _text.text.trim(),
        'mentions': [
          ...?mentionSelections[_text],
          if (parent != null)
            {
              'uid': txt(parent.data(), 'authorUid'),
              'username': '',
              'replyTo': parent.id,
            },
        ].take(20).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _text.clear();
      mentionSelections[_text] = const [];
      if (mounted) {
        setState(() {
          if (parent != null) {
            _expanded.add(parent.id);
            final root = commentParentId(parent.data());
            if (root.isNotEmpty) _expanded.add(root);
          }
          _replyTo = null;
        });
      }
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _thread(
    QueryDocumentSnapshot<Map<String, dynamic>> root,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> replies,
  ) {
    final open = _expanded.contains(root.id) || replies.length <= 2;
    final shown = open ? replies : replies.take(1).toList();
    return [
      _SocialCommentCard(
        key: ValueKey(root.id),
        comment: root,
        onReply: () => _reply(root),
        threadBelow: replies.isNotEmpty,
      ),
      for (final (i, reply) in shown.indexed)
        _SocialCommentCard(
          key: ValueKey(reply.id),
          comment: reply,
          reply: true,
          onReply: () => _reply(reply),
          threadBelow: i < shown.length - 1 || shown.length < replies.length,
        ),
      if (shown.length < replies.length)
        Padding(
          padding: const EdgeInsets.only(left: 50, bottom: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Ink.muted,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              onPressed: () => setState(() => _expanded.add(root.id)),
              child: Text(
                bi(
                  'View ${replies.length - shown.length} more replies',
                  'மேலும் ${replies.length - shown.length} பதில்கள்',
                ),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      const SizedBox(height: 6),
    ];
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.only(top: 12),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0x167B61D1))),
    ),
    child: Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
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
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CupertinoActivityIndicator()),
                );
              }
              if (snapshot.data!.docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      bi(
                        'Be the first to comment.',
                        'முதல் கருத்தைப் பகிருங்கள்.',
                      ),
                      style: const TextStyle(color: Ink.muted),
                    ),
                  ),
                );
              }
              return ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final (root, replies) in commentThreads(
                    snapshot.data!.docs,
                  ))
                    ..._thread(root, replies),
                ],
              );
            },
          ),
        ),
        AnimatedSize(
          duration: Gold.fast,
          child: _replyTo == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.arrow_turn_down_right,
                        size: 15,
                        color: Ink.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          bi(
                            'Replying to ${_username(_replyTo!)}',
                            '${_username(_replyTo!)}-க்கு பதில்',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Ink.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: ui('Cancel'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(CupertinoIcons.xmark, size: 15),
                        onPressed: () {
                          setState(() => _replyTo = null);
                          _text.clear();
                          mentionSelections[_text] = const [];
                        },
                      ),
                    ],
                  ),
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
                  child: Focus(
                    focusNode: _focus,
                    child: MentionInput(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      hint: _replyTo == null
                          ? bi('Write a comment', 'கருத்தை எழுதுங்கள்')
                          : bi('Write a reply', 'பதிலை எழுதுங்கள்'),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: ui('Send'),
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : const Icon(CupertinoIcons.arrow_up),
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
  final bool reply;

  /// Draws the thread line down from this comment's avatar to the next reply.
  final bool threadBelow;
  const _SocialCommentCard({
    super.key,
    required this.comment,
    required this.onReply,
    this.reply = false,
    this.threadBelow = false,
  });
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
    try {
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
        if (mounted) {
          snack(context, bi('Comment reported', 'கருத்து புகாரளிக்கப்பட்டது'));
        }
      }
    } catch (error) {
      if (mounted) snack(context, accountError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.comment.data();
    final avatar = widget.reply ? 15.0 : 19.0;
    final line = Ink.violetDeep.withValues(alpha: .16);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _longPress,
      child: Padding(
        padding: EdgeInsets.only(left: widget.reply ? 44 : 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: avatar * 2,
                child: Column(
                  children: [
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () => push(
                        context,
                        SocialProfileScreen(uid: txt(data, 'authorUid')),
                      ),
                      child:
                          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            future: _profile,
                            builder: (_, snapshot) => profileAvatar(
                              txt(snapshot.data?.data() ?? {}, 'photo'),
                              radius: avatar,
                              label: txt(data, 'authorName'),
                            ),
                          ),
                    ),
                    // Threads-style connector down to the next reply.
                    if (widget.threadBelow)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: line,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Ink.navy,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _ago(data['createdAt'] as Timestamp?),
                            style: const TextStyle(
                              color: Ink.faint,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      MentionText(
                        txt(data, 'text'),
                        mentions: data['mentions'] is List
                            ? List.from(data['mentions'])
                            : const [],
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: Ink.body,
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Ink.muted,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                              ),
                              minimumSize: const Size(44, 34),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: widget.onReply,
                            child: Text(bi('Reply', 'பதில்')),
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
                              final count = snapshot.data?.size ?? 0;
                              return TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Ink.muted,
                                  minimumSize: const Size(44, 34),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                ),
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
                                        } catch (_) {
                                        } finally {
                                          _likeBusy = false;
                                        }
                                      },
                                icon: Icon(
                                  liked
                                      ? CupertinoIcons.heart_fill
                                      : CupertinoIcons.heart,
                                  size: 16,
                                  color: liked ? Colors.pink : Ink.muted,
                                ),
                                label: Text(
                                  count == 0 ? '' : '$count',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
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
