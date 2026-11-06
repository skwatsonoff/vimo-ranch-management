part of 'main.dart';

// =============================================================================
//  Voice test & report (Settings, ranch owner).
//
//  Runs VIMO's voice checks on this phone and saves one report file the
//  owner gives to Claude: a self-test of the understanding, a live
//  microphone test the owner reads aloud, a permission and device check,
//  and the voice event log. Names of people are hidden by default.
// =============================================================================

/// Turns VIMO's voice log on: called once at start-up.
Future<void> startVoiceDiagnostics() async {
  try {
    await HiveDiagnosticsStore.open();
  } catch (_) {}
  MicPermission.log = VoiceDiagnostics.log;
  try {
    if (!Hive.isBoxOpen(languagePackBox)) await Hive.openBox(languagePackBox);
  } catch (_) {}
}

/// The sentences of the built-in corpus (assets/voice/voice_corpus.json).
Future<List<VoiceTestCase>> loadVoiceCorpus() async {
  try {
    final raw = await rootBundle.loadString('assets/voice/voice_corpus.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final item in (json['utterances'] as List).whereType<Map>())
        VoiceTestCase.fromJson(Map<String, dynamic>.from(item)),
    ];
  } catch (_) {
    return const [];
  }
}

/// The cows the corpus is written for; the self-test adds the ranch's own.
List<String> voiceCorpusCows(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return [for (final c in (json['cows'] as List? ?? const [])) '$c'];
  } catch (_) {
    return const [];
  }
}

/// Everyone named in this phone's records who is not a cow, so the report
/// can replace them with person_1, person_2…
Set<String> knownPeopleNames() {
  const fields = {
    'customer',
    'buyer',
    'person',
    'personName',
    'supplier',
    'vendor',
    'addedBy',
    'doctor',
    'username',
    'userName',
    'displayName',
  };
  final cows = {for (final a in animals(all: true)) txt(a, 'name')};
  final names = <String>{
    currentUserName(),
    ownerName(),
    for (final name in backupBoxNames)
      if (name != 'animals' && name != 'settings' && Hive.isBoxOpen(name))
        for (final row in Hive.box(name).values.whereType<Map>())
          for (final field in fields)
            if (row[field] is String) '${row[field]}'.trim(),
  };
  if (Hive.isBoxOpen(VendorRoutes.boxName)) {
    for (final row in Hive.box(VendorRoutes.boxName).values.whereType<Map>()) {
      for (final field in const ['name', 'customer', 'person']) {
        if (row[field] is String) names.add('${row[field]}'.trim());
      }
    }
  }
  return names.where((n) => n.length > 1 && !cows.contains(n)).toSet();
}

/// Sentences the owner reads in the live test, with the ranch's own cows.
List<VoiceTestCase> liveTestSentences(List<String> cows) {
  final a = cows.isNotEmpty ? cows.first : 'Lakshmi';
  final b = cows.length > 1 ? cows[1] : a;
  final ta = nameInLanguage(a, true);
  final tb = nameInLanguage(b, true);
  return [
    VoiceTestCase('$ta 5 லிட்டர்', 'milk_record', {
      'cow': a,
      'liters': 5,
    }, 'ta'),
    VoiceTestCase('${b.toLowerCase()} ku anju litre podu', 'milk_record', {
      'cow': b,
      'liters': 5,
    }, 'ta-Latn'),
    VoiceTestCase('add 3 litres for $a', 'milk_record', {
      'cow': a,
      'liters': 3,
    }, 'en'),
    VoiceTestCase('${tamilDative(tb)} ரெண்டரை லிட்டர்', 'milk_record', {
      'cow': b,
      'liters': 2.5,
    }, 'ta'),
    const VoiceTestCase('5 இல்லை 6 லிட்டர்', 'edit_last', {'liters': 6}, 'ta'),
    const VoiceTestCase('கடைசி பதிவை நீக்கு', 'delete_last', {}, 'ta'),
    const VoiceTestCase('செல்விக்கு 2 லிட்டர் பால் விற்றேன்', 'sell_milk', {
      'liters': 2,
    }, 'ta'),
    const VoiceTestCase('ஹே விமோ', 'wake', {}, 'ta'),
    VoiceTestCase('nethu maalai $a 4 litre', 'milk_record', {
      'cow': a,
      'liters': 4,
      'session': 'Evening',
      'date': 'yesterday',
    }, 'ta-Latn'),
    const VoiceTestCase('பால் கறந்து முடிச்சிட்டேன்', 'finish', {}, 'ta'),
  ];
}

class VoiceReportScreen extends StatefulWidget {
  const VoiceReportScreen({super.key});

  @override
  State<VoiceReportScreen> createState() => _VoiceReportScreenState();
}

class _LiveRow {
  final VoiceTestCase prompt;
  String heard = '';
  double? confidence;
  VoiceReading? understood;
  bool? ownerSaysRight;
  final correction = TextEditingController();
  _LiveRow(this.prompt);

  bool get matched =>
      understood != null &&
      understood!.intent == prompt.intent &&
      slotsMatch(prompt.slots, understood!.slots);
}

class _VoiceReportScreenState extends State<VoiceReportScreen> {
  final SpeechToText _stt = SpeechToText();
  List<VoiceTestResult>? _selfTest;
  bool _testing = false;
  bool _hideNames = true;
  bool _saving = false;
  Map<String, Object?> _device = {};
  late final List<_LiveRow> _live = [
    for (final s in liveTestSentences(cowNames())) _LiveRow(s),
  ];
  int? _listeningRow;

  @override
  void initState() {
    super.initState();
    _device = _baseDevice();
  }

  @override
  void dispose() {
    try {
      unawaited(_stt.cancel().catchError((_) {}));
    } catch (_) {}
    for (final r in _live) {
      r.correction.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _baseDevice() => {
    'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    if (kIsWeb) 'browser': _browserRuntime.userAgent,
    'appLanguage': appLanguage.mode,
    'voiceLocale': _defaultVoiceLocale(),
    'engine': settingValue('voiceOfflineBeta', false) == true
        ? 'offline (beta)'
        : 'system',
    'cows': cowNames().length,
  };

  VoiceReading _interpret(String text, List<String> cows) => understandVoice(
    text,
    cows: cows,
    aliases: cowNameAliases(),
    rewrite: voiceRewrite,
  );

  Future<void> _runSelfTest() async {
    setState(() => _testing = true);
    final raw = await rootBundle
        .loadString('assets/voice/voice_corpus.json')
        .catchError((_) => '{}');
    final cases = await loadVoiceCorpus();
    final cows = {...voiceCorpusCows(raw), ...cowNames()}.toList();
    final results = runVoiceSelfTest(cases, (t) => _interpret(t, cows));
    final failed = results.where((r) => !r.passed).length;
    VoiceDiagnostics.log('self_test', {
      'total': results.length,
      'failed': failed,
    });
    if (mounted) {
      setState(() {
        _selfTest = results;
        _testing = false;
      });
    }
  }

  Future<void> _checkDevice() async {
    final access = await ensureMicPermission(speech: true, ask: false);
    final info = {..._baseDevice(), 'micPermission': access.name};
    if (access.isGranted) {
      try {
        final ok = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
        info['speechAvailable'] = ok;
        if (ok) {
          final locales = await _stt.locales();
          final ids = locales.map((l) => l.localeId).toList();
          info['speechLocales'] = ids.length > 40 ? ids.take(40).toList() : ids;
          info['tamilSpeech'] = ids.any(
            (id) => id.toLowerCase().replaceAll('_', '-') == 'ta-in',
          );
        }
      } catch (error) {
        info['speechAvailable'] = false;
        info['speechError'] = '$error';
      }
    }
    info['languagePacks'] = installedLanguagePacksSummary();
    info['storage'] = kIsWeb ? 'browser storage' : 'not measured';
    VoiceDiagnostics.log('device_check', info);
    if (mounted) setState(() => _device = info);
  }

  Future<void> _listenFor(int index) async {
    if (_listeningRow != null) return;
    final access = await ensureMicPermission(speech: true);
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
    final row = _live[index];
    final started = DateTime.now();
    DateTime? firstWords;
    try {
      final ok = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
      if (!ok) throw StateError('speech not available');
      _stt.errorListener = (e) {
        VoiceDiagnostics.log('live_test_error', {'code': e.errorMsg});
        if (mounted) setState(() => _listeningRow = null);
      };
      _stt.statusListener = (status) {
        if (status == SpeechToText.doneStatus && mounted) {
          setState(() => _listeningRow = null);
        }
      };
      setState(() => _listeningRow = index);
      await _stt.listen(
        onResult: (r) {
          firstWords ??= DateTime.now();
          if (!mounted) return;
          setState(() {
            row.heard = r.recognizedWords;
            row.confidence = r.hasConfidenceRating ? r.confidence : null;
          });
          if (r.finalResult) _finishRow(index, started, firstWords);
        },
        listenOptions: SpeechListenOptions(
          localeId: _defaultVoiceLocale(),
          partialResults: true,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 15),
          contextualPhrases: ['Vimo', ...cowNames()],
        ),
      );
    } catch (error) {
      VoiceDiagnostics.log('live_test_error', {'error': '$error'});
      if (mounted) setState(() => _listeningRow = null);
    }
  }

  void _finishRow(int index, DateTime started, DateTime? firstWords) {
    final row = _live[index];
    final reading = _interpret(row.heard, cowNames());
    VoiceDiagnostics.log('live_test', {
      'prompt': row.prompt.text,
      'heard': row.heard,
      'confidence': row.confidence,
      'intent': reading.intent,
      'slots': reading.slots,
      'msToFirstWords': firstWords?.difference(started).inMilliseconds,
      'msTotal': DateTime.now().difference(started).inMilliseconds,
    });
    setState(() {
      row.understood = reading;
      _listeningRow = null;
    });
  }

  Map<String, Object?> _report() => buildVoiceReport(
    events: VoiceDiagnostics.events(),
    device: _device,
    selfTest: _selfTest ?? const [],
    live: [
      for (final r in _live)
        if (r.heard.isNotEmpty || r.ownerSaysRight != null)
          LiveTestResult(
            prompt: r.prompt.text,
            heard: r.heard,
            confidence: r.confidence,
            understood: r.understood ?? (intent: 'none', slots: const {}),
            matched: r.matched,
            ownerSaysRight: r.ownerSaysRight,
            correction: r.correction.text.trim(),
          ),
    ],
    hideNames: _hideNames,
    people: _hideNames ? knownPeopleNames() : const [],
    cows: cowNames(),
  );

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final report = _report();
      final stamp = reportStamp(DateTime.now());
      final json = const JsonEncoder.withIndent('  ').convert(report);
      final savedJson = await downloadJsonFile(
        'vimo_voice_report_$stamp.json',
        json,
      );
      final savedMd = await downloadTextFile(
        'vimo_voice_report_$stamp.md',
        voiceReportMarkdown(report),
        extension: 'md',
      );
      if (mounted) {
        snack(
          context,
          savedJson || savedMd
              ? bi('Report saved', 'அறிக்கை சேமிக்கப்பட்டது')
              : bi('Report not saved', 'அறிக்கை சேமிக்கப்படவில்லை'),
          tone: savedJson || savedMd ? SnackTone.success : SnackTone.info,
        );
      }
    } catch (_) {
      if (mounted) {
        snack(
          context,
          bi(
            'Could not save. Please try again.',
            'சேமிக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
          ),
          tone: SnackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy() async {
    final md = voiceReportMarkdown(_report());
    // The summary and failures are what matter on a clipboard.
    final cut = md.indexOf('## Event log');
    await Clipboard.setData(
      ClipboardData(text: cut > 0 ? md.substring(0, cut) : md),
    );
    if (mounted) {
      snack(
        context,
        bi('Report summary copied', 'அறிக்கை சுருக்கம் நகலெடுக்கப்பட்டது'),
        tone: SnackTone.success,
      );
    }
  }

  Future<void> _clear() async {
    final sure = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(bi('Clear the voice log?', 'குரல் பதிவேட்டை அழிக்கவா?')),
        content: Text(
          bi(
            'The report will start empty. Milk records are not touched.',
            'அறிக்கை காலியாகத் தொடங்கும். பால் பதிவுகள் மாறாது.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(bi('Cancel', 'ரத்து')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(bi('Clear', 'அழி')),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await VoiceDiagnostics.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final events = VoiceDiagnostics.events().length;
    final results = _selfTest;
    final failed = results?.where((r) => !r.passed).toList() ?? const [];
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      appBar: AppBar(
        title: AppText(bi('Voice test & report', 'குரல் சோதனை & அறிக்கை')),
        leading: const _BackButton(),
      ),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.s16,
            Space.s12,
            Space.s16,
            Space.s56,
          ),
          children: [
            _ReportSection(
              icon: CupertinoIcons.checkmark_seal,
              title: bi('Self-test', 'தானியங்கி சோதனை'),
              subtitle: bi(
                'Checks VIMO\'s understanding on the built-in sentences.',
                'உள்ளமைந்த வாக்கியங்களில் VIMO-வின் புரிதலைச் சோதிக்கும்.',
              ),
              children: [
                LiquidButton(
                  label: bi('Run self-test', 'சோதனையைத் தொடங்கு'),
                  icon: CupertinoIcons.play_fill,
                  busy: _testing,
                  onPressed: _runSelfTest,
                ),
                if (results != null) ...[
                  const SizedBox(height: Space.s12),
                  Text(
                    bi(
                      '${results.length - failed.length} of ${results.length} passed',
                      '${results.length}-இல் ${results.length - failed.length} வெற்றி',
                    ),
                    style: TextStyle(
                      fontSize: Gold.t16,
                      fontWeight: FontWeight.w700,
                      color: failed.isEmpty ? Ink.greenText : Ink.amberText,
                    ),
                  ),
                  for (final f in failed.take(30))
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s8),
                      child: Text(
                        '“${f.testCase.text}”\n'
                        '${bi('Expected', 'எதிர்பார்த்தது')}: ${f.testCase.intent} ${jsonEncode(f.testCase.slots)}\n'
                        '${bi('Got', 'கிடைத்தது')}: ${f.got.intent} ${jsonEncode(f.got.slots)}',
                        style: TextStyle(fontSize: 13, color: Ink.body),
                      ),
                    ),
                ],
              ],
            ),
            _ReportSection(
              icon: CupertinoIcons.mic,
              title: bi('Live mic test', 'நேரடி மைக் சோதனை'),
              subtitle: bi(
                'Tap a sentence, read it aloud, then mark whether VIMO got it right.',
                'ஒரு வாக்கியத்தைத் தட்டி உரக்கப் படியுங்கள்; VIMO சரியாகப் புரிந்ததா என்று குறியுங்கள்.',
              ),
              children: [for (int i = 0; i < _live.length; i++) _liveRow(i)],
            ),
            _ReportSection(
              icon: CupertinoIcons.device_phone_portrait,
              title: bi('Permission & device check', 'அனுமதி & கருவி சோதனை'),
              subtitle: bi(
                'Microphone, speech service, languages and voice packs on this phone.',
                'இந்த போனின் மைக், குரல் அறிதல், மொழிகள், குரல் packs.',
              ),
              children: [
                _SecondaryPill(
                  label: bi('Check now', 'இப்போது சோதி'),
                  icon: CupertinoIcons.search,
                  onTap: _checkDevice,
                ),
                const SizedBox(height: Space.s8),
                for (final e in _device.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s4),
                    child: Text(
                      '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}',
                      style: TextStyle(fontSize: 13, color: Ink.body),
                    ),
                  ),
              ],
            ),
            _ReportSection(
              icon: CupertinoIcons.doc_text,
              title: bi('Report', 'அறிக்கை'),
              subtitle: bi(
                '$events voice events logged on this phone. Give the saved file to Claude to fix problems.',
                'இந்த போனில் $events குரல் நிகழ்வுகள் பதிவாகியுள்ளன. சேமித்த கோப்பை Claude-இடம் கொடுத்தால் பிழைகளைச் சரிசெய்யலாம்.',
              ),
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _hideNames,
                    onChanged: (v) => setState(() => _hideNames = v),
                    title: AppText(bi('Hide names', 'பெயர்களை மறை')),
                    subtitle: AppText(
                      bi(
                        'People become person_1, person_2. Cow names stay. Phone numbers, emails, UPI ids and money are always removed.',
                        'மனிதர் பெயர்கள் person_1, person_2 ஆகும்; மாட்டுப் பெயர்கள் இருக்கும். தொலைபேசி எண், email, UPI, பணம் எப்போதும் நீக்கப்படும்.',
                      ),
                    ),
                  ),
                ),
                LiquidButton(
                  label: bi('Download report', 'அறிக்கையைப் பதிவிறக்கு'),
                  icon: CupertinoIcons.arrow_down_doc,
                  busy: _saving,
                  onPressed: _download,
                ),
                const SizedBox(height: Space.s8),
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryPill(
                        label: bi('Copy report', 'நகலெடு'),
                        icon: CupertinoIcons.doc_on_clipboard,
                        onTap: _copy,
                      ),
                    ),
                    const SizedBox(width: Space.s8),
                    Expanded(
                      child: _SecondaryPill(
                        label: bi('Clear log', 'பதிவேட்டை அழி'),
                        icon: CupertinoIcons.trash,
                        onTap: _clear,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveRow(int i) {
    final row = _live[i];
    final listening = _listeningRow == i;
    final understood = row.understood;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s8),
      child: Container(
        padding: const EdgeInsets.all(Space.s12),
        decoration: ShapeDecoration(
          shape: const SquircleBorder(radius: Gold.r13),
          color: Ink.surface.withValues(alpha: .7),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${i + 1}. ${row.prompt.text}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Ink.navy,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: bi('Read aloud', 'உரக்கப் படி'),
                  onPressed: listening ? null : () => _listenFor(i),
                  icon: Icon(
                    listening
                        ? CupertinoIcons.waveform
                        : CupertinoIcons.mic_fill,
                    color: listening ? Ink.orange : Ink.tint,
                  ),
                ),
              ],
            ),
            if (row.heard.isNotEmpty)
              Text(
                '${bi('Heard', 'கேட்டது')}: “${row.heard}”'
                '${row.confidence == null ? '' : ' (${(row.confidence! * 100).round()}%)'}',
                style: TextStyle(fontSize: 13, color: Ink.body),
              ),
            if (understood != null)
              Text(
                '${bi('Understood', 'புரிந்தது')}: ${understood.intent} ${jsonEncode(understood.slots)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: row.matched ? Ink.greenText : Ink.amberText,
                ),
              ),
            if (row.heard.isNotEmpty) ...[
              Row(
                children: [
                  ChoiceChip(
                    label: Text(bi('Right', 'சரி')),
                    selected: row.ownerSaysRight == true,
                    onSelected: (_) =>
                        setState(() => row.ownerSaysRight = true),
                  ),
                  const SizedBox(width: Space.s8),
                  ChoiceChip(
                    label: Text(bi('Wrong', 'தவறு')),
                    selected: row.ownerSaysRight == false,
                    onSelected: (_) =>
                        setState(() => row.ownerSaysRight = false),
                  ),
                ],
              ),
              if (row.ownerSaysRight == false)
                TextField(
                  controller: row.correction,
                  decoration: fieldStyle(
                    bi('What you said', 'நீங்கள் சொன்னது'),
                    icon: CupertinoIcons.pencil,
                  ),
                  onSubmitted: (text) {
                    VoiceDiagnostics.log('live_test_correction', {
                      'prompt': row.prompt.text,
                      'heard': row.heard,
                      'correct': text.trim(),
                    });
                    rememberVoiceCorrection(row.heard, text.trim());
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _ReportSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s16),
    child: Glass(
      radius: Gold.r21,
      padding: const EdgeInsets.all(Space.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: Ink.violetDeep, size: 20),
              const SizedBox(width: Space.s8),
              Expanded(
                child: AppText(
                  title,
                  style: TextStyle(
                    fontSize: Gold.t16 + 1,
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s4),
          AppText(subtitle, style: TextStyle(fontSize: 13, color: Ink.muted)),
          const SizedBox(height: Space.s12),
          ...children,
        ],
      ),
    ),
  );
}
