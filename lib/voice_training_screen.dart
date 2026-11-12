part of 'main.dart';

// =============================================================================
//  Train VIMO (Settings, ranch owner).
//
//  Trains command recognition on-device and lets the owner upload
//  recorded speech to their private Google Drive for speech training.
// =============================================================================

const _trainingBox = 'voice_training';
const _trainingAudioBox = 'voice_training_audio';
const _speakersKey = 'voiceTrainingSpeakers';

Future<void> _openTrainingBoxes() async {
  if (!Hive.isBoxOpen(_trainingBox)) await Hive.openBox(_trainingBox);
  if (!Hive.isBoxOpen(_trainingAudioBox)) {
    await Hive.openLazyBox(_trainingAudioBox);
  }
}

List<Map<String, dynamic>> _recordings() {
  if (!Hive.isBoxOpen(_trainingBox)) return const [];
  final box = Hive.box(_trainingBox);
  final rows = [
    for (final key in box.keys)
      if (box.get(key) is Map && (asMap(box.get(key))['scope'] == null ||
          asMap(box.get(key))['scope'] == _voiceScope()))
        {...asMap(box.get(key)), 'id': '$key'},
  ];
  rows.sort((a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')));
  return rows;
}

class TrainVimoScreen extends StatefulWidget {
  const TrainVimoScreen({super.key});

  @override
  State<TrainVimoScreen> createState() => _TrainVimoScreenState();
}

class _TrainVimoScreenState extends State<TrainVimoScreen> {
  int _tab = 0;
  bool _ready = false;

  // Record
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  late final List<TrainingPrompt> _prompts = trainingPrompts(
    cowNames(),
    tamilNames: {for (final c in cowNames()) c: tamilCowName(c)},
  );
  int _index = 0;
  bool _recording = false;
  Timer? _limit;
  BytesBuilder? _pcm;
  StreamSubscription<Uint8List>? _audio;
  VoiceFormat _format = VoiceFormat(16000);
  Uint8List? _take;
  int _takeMs = 0;
  String _speaker = 'Me';
  String _noise = 'quiet';
  bool _uploading = false;
  String? _custom;

  @override
  void initState() {
    super.initState();
    final speakers = settingValue(_speakersKey, const ['Me']);
    if (speakers is List && speakers.isNotEmpty) _speaker = '${speakers.first}';
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _openTrainingBoxes();
    } catch (_) {}
    if (!mounted) return;
    final done = _recordings().map((r) => txt(r, 'text')).toSet();
    final next = _prompts.indexWhere((p) => !done.contains(p.text));
    setState(() {
      _ready = true;
      _index = next < 0 ? 0 : next;
    });
  }

  @override
  void dispose() {
    _limit?.cancel();
    unawaited(_audio?.cancel());
    unawaited(_recorder.dispose().catchError((Object _) {}));
    unawaited(_player.dispose().catchError((Object _) {}));
    super.dispose();
  }

  List<String> get _speakers {
    final raw = settingValue(_speakersKey, const ['Me']);
    return raw is List && raw.isNotEmpty ? [for (final s in raw) '$s'] : ['Me'];
  }

  TrainingPrompt get _prompt => _custom != null
      ? TrainingPrompt(
          _custom!,
          RegExp(r'[஀-௿]').hasMatch(_custom!) ? 'ta' : 'ta-Latn',
        )
      : _prompts[_index % _prompts.length];

  // --- recording ------------------------------------------------------------------

  Future<void> _record() async {
    if (_recording) return _stop();
    final access = await ensureMicPermission();
    if (!mounted) return;
    if (!access.isGranted) {
      snack(
        context,
        ui('Microphone permission is needed'),
        tone: SnackTone.error,
        actionLabel: access.needsSettings && !kIsWeb
            ? bi('Open Settings', 'Settings திற')
            : null,
        onAction: access.needsSettings
            ? () => unawaited(openMicSettings())
            : null,
      );
      return;
    }
    try {
      _pcm = BytesBuilder(copy: false);
      _format = await watchVoiceFormat(_recorder, 16000);
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          noiseSuppress: false,
        ),
      );
      _audio = stream.listen((chunk) => _pcm?.add(chunk));
      // One recording fits one cloud record: stop at the limit.
      _limit?.cancel();
      _limit = Timer(const Duration(seconds: trainingMaxSeconds), () {
        if (_recording) unawaited(_stop());
      });
      setState(() {
        _recording = true;
        _take = null;
      });
      VoiceDiagnostics.log('training_record_start', {'lang': _prompt.language});
    } catch (error) {
      VoiceDiagnostics.log('training_record_error', {'error': '$error'});
      if (mounted) {
        snack(
          context,
          bi('Could not start recording', 'பதிவு தொடங்க முடியவில்லை'),
          tone: SnackTone.error,
        );
      }
    }
  }

  Future<void> _stop() async {
    _limit?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    await _audio?.cancel();
    _audio = null;
    final raw = _pcm?.takeBytes() ?? Uint8List(0);
    final pcm = pcm16ToVoiceRate(raw, _format, 16000);
    if (!mounted) return;
    setState(() {
      _recording = false;
      _take = pcm.isEmpty ? null : wavFromPcm16(pcm);
      _takeMs = pcmDurationMs(pcm.length);
    });
  }

  Future<void> _replay() async {
    final take = _take;
    if (take == null) return;
    try {
      await _player.play(BytesSource(take, mimeType: 'audio/wav'));
    } catch (_) {}
  }

  Future<void> _saveTake() async {
    final take = _take;
    if (take == null) return;
    if (_takeMs < 600) {
      snack(
        context,
        bi(
          'Too short. Please read the sentence again.',
          'மிகக் குறுகியது. மீண்டும் படியுங்கள்.',
        ),
        tone: SnackTone.error,
      );
      return;
    }
    final id = 'r${DateTime.now().microsecondsSinceEpoch}';
    final prompt = _prompt;
    await Hive.lazyBox(_trainingAudioBox).put(id, take);
    await Hive.box(_trainingBox).put(id, {
      'text': prompt.text,
      'lang': prompt.language,
      'speaker': _speaker,
      'noise': _noise,
      'durationMs': _takeMs,
      'device': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'createdAt': DateTime.now().toIso8601String(),
      'scope': _voiceScope(),
      'driveUploaded': false,
      'fromCorrection': _custom != null,
    });
    VoiceDiagnostics.log('training_saved', {
      'lang': prompt.language,
      'ms': _takeMs,
    });
    setState(() {
      _take = null;
      _custom = null;
      _index = (_index + 1) % _prompts.length;
    });
  }

  void _skip() => setState(() {
    _take = null;
    _custom = null;
    _index = (_index + 1) % _prompts.length;
  });

  // --- upload -------------------------------------------------------------------------

  Future<void> _uploadPending() async {
    if (_uploading || !Hive.isBoxOpen(_trainingBox)) return;
    final bridge = _VoiceBridge.current;
    if (bridge == null) {
      await push(context, const VoiceBridgeScreen());
      return;
    }
    final pending = _recordings().where((row) =>
      row['scope'] == bridge.scope && row['driveUploaded'] != true).toList();
    setState(() => _uploading = true);
    try {
      for (final row in pending) {
        final id = txt(row, 'id');
        final bytes = await Hive.lazyBox(_trainingAudioBox).get(id);
        if (bytes is! Uint8List || bytes.length >= 1000000) continue;
        final result = await bridge.call('recording', {
          'id': id,
          'wav': base64Encode(bytes),
          'sidecar': trainingSidecar(
            id: id, transcript: txt(row, 'text'), language: txt(row, 'lang', 'ta'),
            speaker: txt(row, 'speaker'), noise: txt(row, 'noise'),
            durationMs: toInt(row['durationMs']), device: txt(row, 'device'),
            recordedAt: DateTime.tryParse(txt(row, 'createdAt')) ?? DateTime.now(),
          ),
        });
        if (result['ok'] != true) throw StateError('recording');
        final box = Hive.box(_trainingBox);
        await box.put(id, {...asMap(box.get(id)), 'driveUploaded': true});
      }
      if (mounted) {
        snack(context, bi('Recordings synced to Google Drive', 'பதிவுகள் Google Drive-ல் ஒத்திசைந்தன'), tone: SnackTone.success);
      }
    } catch (_) {
      if (mounted) {
        snack(context, bi('Google Drive upload stopped. Try again to continue.', 'Google Drive பதிவேற்றம் நின்றது. தொடர மீண்டும் முயலுங்கள்.'), tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // --- data -------------------------------------------------------------------------------

  Future<void> _delete(String id, String lang) async {
    if (_uploading) return;
    final box = Hive.box(_trainingBox);
    final row = asMap(box.get(id));
    if (row['driveUploaded'] == true) {
      final bridge = _VoiceBridge.current;
      try {
        if (bridge == null || row['scope'] != bridge.scope) {
          throw StateError('session');
        }
        final reply = await bridge.call('deleteRecording', {'id': id});
        if (reply['ok'] != true) throw StateError('recording');
      } catch (_) {
        if (mounted) {
          snack(context, bi('Connect Google Drive to delete this recording.', 'இந்தப் பதிவை நீக்க Google Drive-ஐ இணைக்கவும்.'), tone: SnackTone.error);
        }
        return;
      }
    }
    await box.delete(id);
    await Hive.lazyBox(_trainingAudioBox).delete(id);
    if (mounted) setState(() {});
  }

  Future<bool> _ask(String title, String body) async =>
      await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(bi('Cancel', 'ரத்து')),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(bi('Delete', 'நீக்கு')),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _deleteAll() async {
    if (!await _ask(
      bi('Delete all training data?', 'எல்லா பயிற்சி தரவையும் நீக்கவா?'),
      bi(
        'Every recording on this phone and in the cloud.',
        'இந்த போனிலும் cloud-இலும் உள்ள எல்லா பதிவுகளும்.',
      ),
    )) {
      return;
    }
    if (!mounted) return;
    if (!await _ask(
      bi('Are you sure?', 'உறுதியாகவா?'),
      bi('This cannot be undone.', 'இதைத் திரும்பப் பெற முடியாது.'),
    )) {
      return;
    }
    for (final r in _recordings()) {
      await _delete(txt(r, 'id'), txt(r, 'lang', 'ta'));
    }
    VoiceDiagnostics.log('training_deleted_all', const {});
  }

  // --- training job ---------------------------------------------------------------------

  Future<void> _startTraining() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    await refreshVoiceLessons();
    final model = milkRecognitionModel();
    if (mounted) {
      setState(() => _uploading = false);
      snack(context, bi(
        'VIMO trained on ${model.examples} corrected milk commands.',
        'திருத்திய ${model.examples} பால் கட்டளைகளில் VIMO பயிற்சி பெற்றது.',
      ), tone: SnackTone.success);
    }
  }

  // --- build ---------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tabs = [
      bi('Record', 'பதிவு'),
      bi('Fix mistakes', 'திருத்தங்கள்'),
      bi('Train', 'பயிற்சி'),
      bi('Data', 'தரவு'),
    ];
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      appBar: AppBar(
        title: AppText(bi('Train VIMO', 'VIMO பயிற்சி')),
        leading: const _BackButton(),
      ),
      body: Shell(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s16,
                Space.s12,
                Space.s16,
                Space.s8,
              ),
              child: Glass(
                radius: Gold.r21,
                blur: Space.s12,
                padding: const EdgeInsets.all(Space.s4),
                elevation: .62,
                child: LiquidSegmentBar(
                  labels: tabs,
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
            ),
            Expanded(
              child: !_ready
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        Space.s16,
                        Space.s8,
                        Space.s16,
                        Space.s56,
                      ),
                      children: switch (_tab) {
                        0 => _recordTab(),
                        1 => _fixTab(),
                        2 => [_trainTab()],
                        _ => _dataTab(),
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _recordTab() {
    final minutes = minutesByLanguage(_recordings());
    final prompt = _prompt;
    return [
      _ReportSection(
        icon: CupertinoIcons.chart_pie,
        title: bi('Recorded so far', 'இதுவரை பதிவானது'),
        subtitle: bi(
          'Targets: Tamil 2 hours, Tanglish 1 hour, English 30 minutes.',
          'இலக்கு: தமிழ் 2 மணி, Tanglish 1 மணி, English 30 நிமிடம்.',
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final e in trainingTargetsMinutes.entries)
                Expanded(
                  child: _ProgressRing(
                    label: packLanguageName(e.key),
                    minutes: minutes[e.key] ?? 0,
                    target: e.value,
                  ),
                ),
            ],
          ),
        ],
      ),
      _ReportSection(
        icon: CupertinoIcons.text_quote,
        title: bi('Read this sentence', 'இந்த வாக்கியத்தைப் படியுங்கள்'),
        subtitle:
            '${packLanguageName(prompt.language)} · ${_index + 1}/${_prompts.length}',
        children: [
          Text(
            prompt.text,
            style: TextStyle(
              fontSize: Gold.t21,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: Ink.navy,
            ),
          ),
          const SizedBox(height: Space.s12),
          Wrap(
            spacing: Space.s8,
            runSpacing: Space.s8,
            children: [
              for (final s in _speakers)
                ChoiceChip(
                  label: Text(s),
                  selected: _speaker == s,
                  onSelected: (_) => setState(() => _speaker = s),
                ),
              ActionChip(
                avatar: const Icon(CupertinoIcons.person_add, size: 16),
                label: Text(bi('Speaker', 'பேசுபவர்')),
                onPressed: _addSpeaker,
              ),
            ],
          ),
          const SizedBox(height: Space.s8),
          Wrap(
            spacing: Space.s8,
            children: [
              ChoiceChip(
                label: Text(bi('Quiet', 'அமைதி')),
                selected: _noise == 'quiet',
                onSelected: (_) => setState(() => _noise = 'quiet'),
              ),
              ChoiceChip(
                label: Text(bi('Ranch noise', 'தொழுவ சத்தம்')),
                selected: _noise == 'ranch',
                onSelected: (_) => setState(() => _noise = 'ranch'),
              ),
            ],
          ),
          const SizedBox(height: Space.s12),
          LiquidButton(
            label: _recording
                ? bi('Stop', 'நிறுத்து')
                : bi('Record', 'பதிவு செய்'),
            icon: _recording
                ? CupertinoIcons.stop_fill
                : CupertinoIcons.mic_fill,
            start: _recording ? Ink.red : null,
            onPressed: _record,
          ),
          if (_take != null) ...[
            const SizedBox(height: Space.s8),
            Text(
              '${(_takeMs / 1000).toStringAsFixed(1)} s',
              style: TextStyle(color: Ink.muted),
            ),
            const SizedBox(height: Space.s8),
            Row(
              children: [
                Expanded(
                  child: _SecondaryPill(
                    label: bi('Replay', 'கேள்'),
                    icon: CupertinoIcons.play_fill,
                    onTap: _replay,
                  ),
                ),
                const SizedBox(width: Space.s8),
                Expanded(
                  child: _SecondaryPill(
                    label: bi('Redo', 'மீண்டும்'),
                    icon: CupertinoIcons.arrow_counterclockwise,
                    onTap: () => setState(() => _take = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s8),
            LiquidButton(
              label: bi('Save & next', 'சேமித்து அடுத்தது'),
              icon: CupertinoIcons.checkmark_alt,
              onPressed: _saveTake,
            ),
          ] else if (!_recording) ...[
            const SizedBox(height: Space.s8),
            _SecondaryPill(
              label: bi('Skip', 'தவிர்'),
              icon: CupertinoIcons.forward,
              onTap: _skip,
            ),
          ],
        ],
      ),
      AppText(
        bi(
          'Recordings stay on this phone first and upload on Wi-Fi when you are signed in.',
          'பதிவுகள் முதலில் இந்த போனில் இருக்கும்; sign in செய்து Wi-Fi இருக்கும்போது upload ஆகும்.',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Ink.muted),
      ),
    ];
  }

  Future<void> _addSpeaker() async {
    final field = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(bi('Speaker tag', 'பேசுபவர் குறிச்சொல்')),
        content: Padding(
          padding: const EdgeInsets.only(top: Space.s8),
          child: CupertinoTextField(
            controller: field,
            placeholder: 'Appa, Amma, worker 1',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(bi('Cancel', 'ரத்து')),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(field.text.trim()),
            child: Text(bi('Add', 'சேர்')),
          ),
        ],
      ),
    );
    field.dispose();
    if (name == null || name.isEmpty) return;
    await setSetting(_speakersKey, {..._speakers, name}.toList());
    if (mounted) setState(() => _speaker = name);
  }

  List<Widget> _fixTab() {
    final lessons = learnedVoiceRows()
        .where((r) => txt(r, 'kind') == 'text')
        .toList();
    final wrong = VoiceDiagnostics.events()
        .where((e) => e.type == 'live_test_correction')
        .toList()
        .reversed
        .toList();
    final items = <(String heard, String meant)>[
      for (final l in lessons) (txt(l, 'heard'), txt(l, 'meant')),
      for (final e in wrong)
        ('${e.details['heard'] ?? ''}', '${e.details['correct'] ?? ''}'),
    ];
    return [
      _ReportSection(
        icon: CupertinoIcons.wrench,
        title: bi('Where VIMO was wrong', 'VIMO தவறிய இடங்கள்'),
        subtitle: bi(
          'Record the right sentence so it becomes training data too.',
          'சரியான வாக்கியத்தைப் பதிவு செய்தால் அதுவும் பயிற்சிக்குப் பயன்படும்.',
        ),
        children: [
          if (items.isEmpty)
            AppText(
              bi(
                'No mistakes marked yet.',
                'இன்னும் தவறுகள் குறிக்கப்படவில்லை.',
              ),
              style: TextStyle(fontSize: 14, color: Ink.body),
            ),
          for (final (heard, meant) in items.take(40))
            if (meant.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(meant),
                subtitle: Text('${bi('VIMO heard', 'VIMO கேட்டது')}: $heard'),
                trailing: IconButton(
                  tooltip: bi('Record this', 'இதைப் பதிவு செய்'),
                  icon: Icon(CupertinoIcons.mic_fill, color: Ink.tint),
                  onPressed: () => setState(() {
                    _custom = meant;
                    _tab = 0;
                  }),
                ),
              ),
        ],
      ),
    ];
  }

  Widget _trainTab() {
    final examples = milkRecognitionModel().examples;
    return _ReportSection(
      icon: CupertinoIcons.bolt,
      title: bi('VIMO milk recognition', 'VIMO பால் கட்டளை அறிதல்'),
      subtitle: bi(
        'Learns from corrected milk commands and suggests a cow for you to confirm. Works offline with the examples on this device.',
        'திருத்திய பால் கட்டளைகளிலிருந்து கற்று, உறுதிசெய்ய மாட்டுப் பெயரைப் பரிந்துரைக்கும். சாதனத்தில் உள்ள உதாரணங்களுடன் இணையமின்றியும் இயங்கும்.',
      ),
      children: [
        Text(bi('$examples examples on this device', 'இந்தச் சாதனத்தில் $examples உதாரணங்கள்')),
        const SizedBox(height: Space.s12),
        LiquidButton(
          label: bi('Train VIMO', 'VIMO-க்குப் பயிற்சி'),
          icon: CupertinoIcons.bolt_fill,
          busy: _uploading,
          onPressed: _startTraining,
        ),
        TextButton(
          onPressed: _uploading ? null : () => push(context, const VoiceBridgeScreen()),
          child: Text(bi('Google Drive & Gemini', 'Google Drive & Gemini')),
        ),
      ],
    );
  }

  List<Widget> _dataTab() {
    final rows = _recordings();
    final uploaded = rows.where((r) => r['driveUploaded'] == true).length;
    return [
      _ReportSection(
        icon: CupertinoIcons.lock_shield,
        title: bi('Your training data', 'உங்கள் பயிற்சி தரவு'),
        subtitle: bi(
          'Recordings are saved on this device. Use Upload to Drive to copy recordings made under this account to your private folder.',
          'குரல் பதிவுகள் இந்தச் சாதனத்தில் சேமிக்கப்படும். இந்தக் கணக்கில் செய்த பதிவுகளைத் தனிப்பட்ட கோப்புறைக்கு நகலெடுக்க Drive-க்கு பதிவேற்றுங்கள்.',
        ),
        children: [
          Text(
            bi(
              '${rows.length} recordings, $uploaded uploaded',
              '${rows.length} பதிவுகள், $uploaded upload ஆனவை',
            ),
            style: TextStyle(
              fontSize: Gold.t16,
              fontWeight: FontWeight.w700,
              color: Ink.navy,
            ),
          ),
          const SizedBox(height: Space.s8),
          Row(
            children: [
              Expanded(
                child: _SecondaryPill(
                  label: _uploading
                      ? bi('Uploading…', 'Upload ஆகிறது…')
                      : bi('Upload to Drive', 'Drive-க்கு பதிவேற்று'),
                  icon: CupertinoIcons.cloud_upload,
                  onTap: _uploading
                      ? null
                      : () => unawaited(_uploadPending()),
                ),
              ),
              const SizedBox(width: Space.s8),
              Expanded(
                child: _SecondaryPill(
                  label: bi('Delete all', 'எல்லாம் நீக்கு'),
                  icon: CupertinoIcons.trash,
                  onTap: rows.isEmpty ? null : () => unawaited(_deleteAll()),
                ),
              ),
            ],
          ),
          for (final r in rows.take(80))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                txt(r, 'text'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${packLanguageName(txt(r, 'lang'))} · ${txt(r, 'speaker')} · ${(toInt(r['durationMs']) / 1000).toStringAsFixed(1)} s'
                '${r['driveUploaded'] == true ? ' · ☁︎' : ''}',
              ),
              trailing: IconButton(
                tooltip: bi('Delete', 'நீக்கு'),
                icon: Icon(CupertinoIcons.trash, size: 20, color: Ink.redText),
                onPressed: () =>
                    unawaited(_delete(txt(r, 'id'), txt(r, 'lang', 'ta'))),
              ),
            ),
        ],
      ),
    ];
  }
}

class _ProgressRing extends StatelessWidget {
  final String label;
  final double minutes;
  final double target;
  const _ProgressRing({
    required this.label,
    required this.minutes,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (minutes / target).clamp(0.0, 1.0);
    return Column(
      children: [
        SizedBox.square(
          dimension: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 7,
                  color: fraction >= 1 ? Ink.green : Ink.tint,
                  backgroundColor: Ink.lavender,
                ),
              ),
              Text(
                '${(fraction * 100).round()}%',
                style: TextStyle(fontWeight: FontWeight.w700, color: Ink.navy),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.s4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Ink.body,
          ),
        ),
        Text(
          '${minutes.toStringAsFixed(0)}/${target.toStringAsFixed(0)} min',
          style: TextStyle(fontSize: 11, color: Ink.muted),
        ),
      ],
    );
  }
}
