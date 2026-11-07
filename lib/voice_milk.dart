part of 'main.dart';

// =============================================================================
//  Voice milk mode.
//
//  The phone sits in a shirt pocket during milking. VIMO listens for its
//  wake word ("Vimo" / "Hey Vimo"), answers "ம்ம்?", and takes sentences like
//  "மைனா 5 லிட்டர்" or "Maina add 5 litre" in any mix of Tamil, English and
//  Hindi. A clear sentence is added at once and read back; anything unclear
//  (which cow, how many litres, a name that only sounds close) is asked like
//  a person would ask. "முடிஞ்சது" / "finish" ends the session with an
//  editable report, and nothing reaches the milk records until Save.
//
//  The understanding itself lives in voice_parser.dart and is unit tested.
// =============================================================================

/// One milk entry heard during a voice session (not yet saved).
class VoiceMilkEntry {
  final String id;
  String cow;
  double litres;
  DateTime at;
  final String heard;

  /// "Morning" or "Evening" when it was said; otherwise taken from [at].
  String? sessionOverride;

  VoiceMilkEntry({
    required this.id,
    required this.cow,
    required this.litres,
    required this.at,
    required this.heard,
    String? session,
  }) : sessionOverride = session;

  String get session => sessionOverride ?? milkSessionForTime(at);

  Map<String, dynamic> toMap() => {
    'id': id,
    'cow': cow,
    'litres': litres,
    'at': at.toIso8601String(),
    'heard': heard,
    if (sessionOverride != null) 'session': sessionOverride,
  };

  static VoiceMilkEntry? fromMap(dynamic raw) {
    final m = asMap(raw);
    final at = DateTime.tryParse(txt(m, 'at'));
    if (at == null || txt(m, 'cow').isEmpty) return null;
    return VoiceMilkEntry(
      id: txt(m, 'id', at.microsecondsSinceEpoch.toString()),
      cow: txt(m, 'cow'),
      litres: numv(m, 'litres'),
      at: at,
      heard: txt(m, 'heard'),
      session: txt(m, 'session').isEmpty ? null : txt(m, 'session'),
    );
  }
}

/// A recognition language VIMO can listen in.
class VoiceLocale {
  final String id, label, short;
  const VoiceLocale(this.id, this.label, this.short);
}

const voiceLocales = <VoiceLocale>[
  VoiceLocale('ta-IN', 'தமிழ் + English', 'தமிழ்'),
  VoiceLocale('en-IN', 'English (India)', 'EN'),
  VoiceLocale('hi-IN', 'हिन्दी', 'हि'),
  VoiceLocale('te-IN', 'తెలుగు', 'తె'),
  VoiceLocale('kn-IN', 'ಕನ್ನಡ', 'ಕ'),
  VoiceLocale('ml-IN', 'മലയാളം', 'മ'),
];

const _voiceDraftKey = 'voiceMilkDraft';
const _voiceLocaleKey = 'voiceMilkLocale';

String _defaultVoiceLocale() {
  final saved = settingText(_voiceLocaleKey, '');
  if (voiceLocales.any((l) => l.id == saved)) return saved;
  return switch (appLanguage.code) {
    'ta' => 'ta-IN',
    'hi' => 'hi-IN',
    'te' => 'te-IN',
    'kn' => 'kn-IN',
    'ml' => 'ml-IN',
    'en' => tamilUi ? 'ta-IN' : 'en-IN',
    _ => 'en-IN',
  };
}

List<VoiceMilkEntry> _loadVoiceDraft() {
  final raw = settingValue(_voiceDraftKey, const []);
  if (raw is! List) return [];
  return raw.map(VoiceMilkEntry.fromMap).whereType<VoiceMilkEntry>().toList();
}

Future<void> _storeVoiceDraft(List<VoiceMilkEntry> entries) async {
  try {
    if (entries.isEmpty) {
      if (Hive.isBoxOpen('settings')) {
        await Hive.box('settings').delete(_voiceDraftKey);
      }
    } else {
      await setSetting(_voiceDraftKey, entries.map((e) => e.toMap()).toList());
    }
  } catch (_) {}
}

/// Writes voice entries into the ranch's milk records, each with the time it
/// was spoken and the milking session that time belongs to.
Future<int> saveVoiceMilkEntries(List<VoiceMilkEntry> entries) async {
  final box = Hive.box('milk_records');
  int saved = 0;
  for (final e in entries) {
    if (e.cow.trim().isEmpty || e.litres <= 0) continue;
    final at = e.at;
    await box.add({
      'cow': e.cow,
      'date': _dayOf(at),
      'time': '${two(at.hour)}:${two(at.minute)}',
      'session': e.session,
      'quantity': e.litres,
      'notes': '',
      'source': 'voice',
      'voiceText': e.heard,
      'addedBy': currentUserName(),
      'createdAt': at.toIso8601String(),
    });
    saved++;
  }
  await _storeVoiceDraft(const []);
  return saved;
}

// --- old drafts ------------------------------------------------------------------

/// A voice draft is old when its newest entry is from another day or
/// milking, or more than three hours ago: the owner decides what to do
/// with it before anything else happens.
bool voiceDraftIsStale(List<VoiceMilkEntry> entries, DateTime now) {
  if (entries.isEmpty) return false;
  final last = entries.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
  return now.difference(last) > const Duration(hours: 3) ||
      _dayOf(last) != _dayOf(now) ||
      milkSessionForTime(last) != milkSessionForTime(now);
}

/// What to do with unsaved voice entries: "save", "discard" or "review".
/// The dialog cannot be dismissed: the owner must choose.
Future<String> askAboutVoiceDraft(
  BuildContext context,
  List<VoiceMilkEntry> entries, {
  bool review = true,
}) async {
  final total = entries.fold<double>(0, (s, e) => s + e.litres);
  final cows = entries.map((e) => e.cow).toSet().length;
  final first = entries
      .map((e) => e.at)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final day = _dayOf(first) == todayDate()
      ? bi('today', 'இன்று')
      : bi('on ${_dayOf(first)}', '${_dayOf(first)} அன்று');
  final choice = await showCupertinoDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => CupertinoAlertDialog(
      title: Text(bi('Unsaved voice entries', 'சேமிக்காத குரல் பதிவுகள்')),
      content: Text(
        bi(
          'From $day ${_clock(first)}: $cows cows · ${formatLitres(total)}. Save them with their own time, or delete them?',
          '$day ${_clock(first)} முதல்: $cows மாடு · ${formatLitres(total)}. அவற்றின் நேரத்துடன் சேமிக்கவா, நீக்கவா?',
        ),
      ),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop('save'),
          child: Text(bi('Save', 'சேமி')),
        ),
        if (review)
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop('review'),
            child: Text(bi('Check and edit', 'பார்த்து திருத்து')),
          ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop('discard'),
          child: Text(bi('Delete', 'நீக்கு')),
        ),
      ],
    ),
  );
  return choice ?? 'review';
}

/// Before typing milk by hand: unsaved voice entries are saved or deleted
/// first, so nothing is entered twice or left hanging.
Future<void> settleVoiceDraftBeforeManual(BuildContext context) async {
  final draft = _loadVoiceDraft();
  if (draft.isEmpty || !context.mounted) return;
  final choice = await askAboutVoiceDraft(context, draft, review: false);
  if (choice == 'save') {
    final count = await saveVoiceMilkEntries(draft);
    VoiceDiagnostics.log('draft_saved', {'entries': count, 'from': 'manual'});
    if (context.mounted) {
      snack(
        context,
        bi('Saved $count entries', '$count பதிவுகள் சேமிக்கப்பட்டன'),
        tone: SnackTone.success,
      );
    }
  } else {
    await _storeVoiceDraft(const []);
    VoiceDiagnostics.log('draft_discarded', {'entries': draft.length});
  }
}

// --- cow names -----------------------------------------------------------------

/// Other spellings of each cow's name (its saved Tamil and English names),
/// so "லட்சுமி" and "Lakshmi" both find the cow.
/// Other names of each cow: its Tamil and English names and, when
/// [learned], the spellings learned from the owner's recordings.
Map<String, List<String>> cowNameAliases({bool learned = true}) {
  final aliases = <String, List<String>>{};
  if (!Hive.isBoxOpen('animals')) return aliases;
  final cloud = learned ? cloudCowAliases() : const <String, List<String>>{};
  for (final animal in animals()) {
    final name = txt(animal, 'name').trim();
    if (name.isEmpty) continue;
    final extra = <String>{
      for (final n in [
        txt(animal, 'nameTamil'),
        txt(animal, 'nameEnglish'),
        ...?cloud[name],
      ])
        if (n.trim().isNotEmpty && n.trim() != name) n.trim(),
    };
    if (extra.isNotEmpty) aliases[name] = extra.toList();
  }
  return aliases;
}

/// The cow's name in Tamil letters for speaking: its saved Tamil name, else
/// a transliteration.
String tamilCowName(String cow) {
  if (Hive.isBoxOpen('animals')) {
    for (final animal in animals()) {
      if (txt(animal, 'name') != cow) continue;
      final tamil = txt(animal, 'nameTamil').trim();
      if (tamil.isNotEmpty) return tamil;
    }
  }
  return nameInLanguage(cow, true);
}

// --- Tamil phrasing ------------------------------------------------------------

/// "மைனா" → "மைனாவுக்கு", "பொன்னி" → "பொன்னிக்கு", "ராஜன்" → "ராஜனுக்கு".
String tamilDative(String name) {
  if (name.isEmpty) return name;
  if (!RegExp(r'[஀-௿]$').hasMatch(name)) return '$name-க்கு';
  if (name.endsWith('்')) {
    return '${name.substring(0, name.length - 1)}ுக்கு';
  }
  if (RegExp('[ிீைெே]\$').hasMatch(name)) return '$nameக்கு';
  return '$nameவுக்கு';
}

/// "மைனா" → "மைனாவா", "பொன்னி" → "பொன்னியா".
String tamilQuestion(String name) {
  if (name.isEmpty) return name;
  if (!RegExp(r'[஀-௿]$').hasMatch(name)) return '$name-ஆ';
  if (name.endsWith('்')) return '${name.substring(0, name.length - 1)}ா';
  if (RegExp('[ிீைெே]\$').hasMatch(name)) return '$nameயா';
  return '$nameவா';
}

String _litreWord(double v) {
  final rounded = (v * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toString();
}

/// What VIMO says: Tamil script, the same in Latin letters (for phones with
/// no Tamil voice), and English.
class _Say {
  final String ta, tanglish, en;
  const _Say(this.ta, this.tanglish, this.en);
}

enum _VoicePhase { sleeping, awake, askCow, askLitres, confirmAdd, confirmUndo }

class _Pending {
  String? cow;
  double? litres;
  bool cowSure = false;
  List<String> choices = const [];
  String? session;
  bool yesterday = false;
  final List<String> heard = [];
}

enum _LineKind { me, vimo, entry, note }

class _Line {
  final _LineKind kind;
  final String text;
  final String? entryId;
  final DateTime at;
  _Line(this.kind, this.text, {this.entryId}) : at = DateTime.now();
}

// --- the screen ----------------------------------------------------------------

/// Previews and browser checks: listen with VIMO's own ear everywhere.
@visibleForTesting
bool debugVoiceEar = false;

class VoiceMilkScreen extends StatefulWidget {
  const VoiceMilkScreen({super.key});

  @override
  State<VoiceMilkScreen> createState() => _VoiceMilkScreenState();
}

class _VoiceMilkScreenState extends State<VoiceMilkScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  /// The ear: the phone's speech service, or VIMO's offline model when the
  /// owner turned it on and its pack is installed.
  VoiceEngine? _engine;
  final List<StreamSubscription<Object?>> _engineSubs = [];

  /// Cancels listening without waiting (the engine may not exist yet).
  Future<void> _cancelEar() async => _engine?.cancel();
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scroll = ScrollController();
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// A beat each time new words arrive, so the orb answers the voice the
  /// way Siri does, even where the browser reports no sound level.
  late final AnimationController _hear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  String _locale = _defaultVoiceLocale();
  _VoicePhase _phase = _VoicePhase.sleeping;
  _Pending? _pending;
  final List<VoiceMilkEntry> _entries = [];

  /// Follow-up questions for everything other than milk.
  late final VoiceDialogue _dialogue = VoiceDialogue(
    cows: cowNames,
    tamilName: (n) => nameInLanguage(n, true),
  );

  /// Other entries saved by voice in this session (shown in the report).
  final List<VoiceSavedAction> _otherSaved = [];
  final List<_Line> _lines = [];

  bool _running = false;
  bool _initialised = false;
  bool _starting = false;
  bool _listeningNow = false;
  bool _speaking = false;
  bool _report = false;
  bool _askingDraft = false;
  DateTime? _retriedAt;
  bool _saving = false;
  bool _tamilVoice = false;
  bool _finishAfterSpeech = false;
  String? _micError;

  /// Why the microphone cannot be used, when it is a permission matter: the
  /// error card then offers "Allow microphone" or "Open Settings".
  _MicProblem? _micProblem;
  String _partial = '';
  double _level = 0;
  String _lastFinal = '';
  DateTime _lastFinalAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _errorStreak = 0;

  Timer? _restart;
  Timer? _sleep;

  /// Ends a sentence once the words stop changing. Browsers mark nothing as
  /// final until the microphone stops, so VIMO decides itself, as Siri does.
  Timer? _settle;
  DateTime? _listenStartedAt;
  bool _engineFactsLogged = false;
  bool _firstWordsLogged = false;
  double? _lastConfidence;
  List<String> _pendingAlternatives = const [];

  /// The sentence already acted on in this listening session.
  String _consumed = '';
  Future<void> _speech = Future.value();

  final Map<String, TextEditingController> _litreFields = {};

  /// VIMO's own ear waiting to be downloaded (the card offers it), and how
  /// far the download is.
  EarModel? _earOffer;
  double? _earProgress;

  /// The browser's speech service refused (no Tamil, or blocked): listen
  /// with VIMO's own ear instead.
  bool _earChosen = false;

  /// Where the browser's speech service cannot help: Tamil on an iPhone
  /// (Apple's service has no Tamil) and the Home Screen web app (Apple
  /// blocks the service there).
  bool get _wantEar =>
      kIsWeb &&
      earSupported &&
      (_earChosen ||
          debugVoiceEar ||
          // English too: Apple's English mishears the cows' names, and
          // Whistle is told them (17 MB, fast).
          (_browserRuntime.appleMobile &&
              (_browserRuntime.standaloneApp ||
                  _locale.startsWith('ta') ||
                  _locale.startsWith('en'))));

  void _listenTo(VoiceEngine engine) => _engineSubs.addAll([
    engine.results.listen(_onResult),
    engine.statuses.listen(_onStatus),
    engine.errors.listen(_onError),
    engine.soundLevels.listen((level) {
      if (mounted) setState(() => _level = level);
    }),
  ]);

  /// Lets go of the current ear so the next start picks the right one.
  Future<void> _dropEngine() async {
    for (final sub in _engineSubs) {
      unawaited(sub.cancel());
    }
    _engineSubs.clear();
    final old = _engine;
    _engine = null;
    _initialised = false;
    if (old != null) _quietly(old.dispose);
  }

  /// Downloads VIMO's own ear (the card's button), then listens with it.
  Future<void> _downloadEar() async {
    final model = _earOffer;
    if (model == null || _earProgress != null) return;
    setState(() => _earProgress = 0);
    try {
      await prepareEar(model, (p) {
        if (mounted) setState(() => _earProgress = p.clamp(0, 1).toDouble());
      });
      VoiceDiagnostics.log('ear_downloaded', {'model': model.id});
      if (!mounted) return;
      setState(() {
        _earOffer = null;
        _earProgress = null;
      });
      await _start();
    } catch (error) {
      VoiceDiagnostics.log('ear_download_error', {'error': '$error'});
      if (!mounted) return;
      setState(() => _earProgress = null);
      snack(
        context,
        bi(
          'The download stopped. Check the internet and try again.',
          'பதிவிறக்கம் நின்றுவிட்டது. இணையத்தைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',
        ),
        tone: SnackTone.error,
      );
    }
  }

  bool get _tamilReplies => _locale.startsWith('ta');

  @override
  void initState() {
    // What VIMO learned from the owner's recordings, for this session.
    unawaited(refreshVoiceLessons());
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entries.addAll(_loadVoiceDraft());
    if (_entries.isNotEmpty) {
      _lines.add(
        _Line(
          _LineKind.note,
          bi(
            '${_entries.length} unsaved entries restored',
            'சேமிக்காத ${_entries.length} பதிவுகள் மீட்கப்பட்டன',
          ),
        ),
      );
      for (final e in _entries) {
        _lines.add(_Line(_LineKind.entry, '', entryId: e.id));
      }
    }
    if (!(WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations)) {
      _breath.repeat(reverse: true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _settleOldDraft();
      if (mounted && !_report) await _start();
    });
  }

  /// An old draft (another day or milking, or hours ago) is not silently
  /// continued: the owner saves it, checks it, or deletes it first.
  Future<void> _settleOldDraft() async {
    if (_askingDraft || !voiceDraftIsStale(_entries, DateTime.now())) return;
    _askingDraft = true;
    _restart?.cancel();
    _quietly(_cancelEar);
    final choice = await askAboutVoiceDraft(context, _entries);
    _askingDraft = false;
    if (!mounted) return;
    VoiceDiagnostics.log('draft_choice', {
      'choice': choice,
      'entries': _entries.length,
    });
    switch (choice) {
      case 'save':
        final total = _entries.fold<double>(0, (s, e) => s + e.litres);
        final count = await saveVoiceMilkEntries(_entries);
        if (!mounted) return;
        setState(() {
          _entries.clear();
          _lines.clear();
        });
        snack(
          context,
          bi(
            'Saved $count entries · ${formatLitres(total)}',
            '$count பதிவுகள் சேமிக்கப்பட்டன · ${formatLitres(total)}',
          ),
          tone: SnackTone.success,
        );
      case 'discard':
        await _storeVoiceDraft(const []);
        if (!mounted) return;
        setState(() {
          _entries.clear();
          _lines.clear();
        });
      default:
        _openReport();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _running = false;
    _restart?.cancel();
    _sleep?.cancel();
    _settle?.cancel();
    for (final sub in _engineSubs) {
      unawaited(sub.cancel());
    }
    final engine = _engine;
    if (engine != null) _quietly(engine.dispose);
    _quietly(_tts.stop);
    _keepAwake(false);
    _breath.dispose();
    _hear.dispose();
    _scroll.dispose();
    for (final c in _litreFields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The phone may have taken the permission back while VIMO was away
      // ("Only this time"), or the owner may have just allowed it in
      // Settings: check again before listening.
      if (_report) return;
      if (voiceDraftIsStale(_entries, DateTime.now())) {
        unawaited(_settleOldDraft());
        return;
      }
      if (_running || _micProblem != null) unawaited(_resumeMic());
    } else if (state == AppLifecycleState.paused) {
      _restart?.cancel();
      _quietly(_cancelEar);
    }
  }

  // --- microphone permission ----------------------------------------------------

  /// Checks (and, with [ask], requests) the microphone. Shows the matching
  /// error card and returns false when listening cannot start.
  Future<bool> _checkMic({bool ask = true}) async {
    final access = await ensureMicPermission(speech: true, ask: ask);
    if (!mounted) return false;
    if (access.isGranted) {
      if (_micProblem != null) {
        setState(() {
          _micProblem = null;
          _micError = null;
        });
      }
      return true;
    }
    _showMicProblem(switch (access) {
      MicAccess.permanentlyDenied
          when MicPermission.backend.platform == 'web' =>
        _MicProblem.browserBlocked,
      MicAccess.permanentlyDenied ||
      MicAccess.restricted => _MicProblem.blocked,
      MicAccess.unsupported => _MicProblem.unsupported,
      _ => _MicProblem.denied,
    });
    return false;
  }

  void _showMicProblem(_MicProblem problem) {
    final retried = _retriedAt;
    if (retried != null &&
        DateTime.now().difference(retried) < const Duration(seconds: 12) &&
        mounted) {
      _retriedAt = null;
      snack(
        context,
        bi(
          'Still not working. Follow the steps on the card, or type the entry.',
          'இன்னும் வேலை செய்யவில்லை. card-இல் உள்ள படிகளைப் பின்பற்றுங்கள், அல்லது கையால் பதிவு செய்யுங்கள்.',
        ),
        tone: SnackTone.error,
      );
    }
    _running = false;
    _restart?.cancel();
    _quietly(_cancelEar);
    setState(() {
      _micProblem = problem;
      _micError = switch (problem) {
        _MicProblem.denied => bi(
          'VIMO needs the microphone to hear you. Tap Allow microphone.',
          'உங்களைக் கேட்க VIMO-க்கு மைக் அனுமதி தேவை. "அனுமதி கொடு" தட்டுங்கள்.',
        ),
        _MicProblem.blocked => bi(
          'The microphone is turned off for VIMO. Open Settings, tap Permissions, then Microphone, and choose Allow.',
          'VIMO-க்கு மைக் அணைக்கப்பட்டுள்ளது. Settings திறந்து Permissions → Microphone → Allow தேர்வு செய்யுங்கள்.',
        ),
        _MicProblem.browserBlocked => bi(
          'This browser blocked the microphone for VIMO. Tap the lock icon next to the address, open Site settings, set Microphone to Allow, then reload the page.',
          'இந்த browser VIMO-க்கு மைக்கைத் தடுத்துள்ளது. முகவரிக்கு அருகில் உள்ள பூட்டு ஐகானைத் தட்டி, Site settings → Microphone → Allow செய்து, பக்கத்தை reload செய்யுங்கள்.',
        ),
        _MicProblem.speechService => _speechServiceHelp(),
        _MicProblem.unsupported => bi(
          'This device cannot use the microphone here. On a computer use Google Chrome; on a phone use the VIMO app or Chrome.',
          'இந்தக் கருவியில் மைக் பயன்படுத்த முடியாது. கணினியில் Google Chrome; போனில் VIMO app அல்லது Chrome பயன்படுத்துங்கள்.',
        ),
      };
    });
  }

  /// Where to turn speech recognition on, for the device in hand.
  String _speechServiceHelp() {
    if (kIsWeb && _browserRuntime.appleMobile) {
      return _browserRuntime.standaloneApp
          ? bi(
              'On iPhone, voice does not work in VIMO opened from the Home Screen. Open my-ranch-sync.web.app in Safari, or turn on Dictation: Settings → General → Keyboard → Enable Dictation.',
              'iPhone-இல் Home Screen-இலிருந்து திறந்த VIMO-வில் குரல் வேலை செய்யாது. Safari-இல் my-ranch-sync.web.app திறங்கள், அல்லது Dictation-ஐ இயக்குங்கள்: Settings → General → Keyboard → Enable Dictation.',
            )
          : bi(
              'On iPhone, voice needs Dictation. Open the iPhone Settings app → General → Keyboard → turn on Enable Dictation, then tap Try again.',
              'iPhone-இல் குரலுக்கு Dictation தேவை. iPhone Settings app → General → Keyboard → Enable Dictation இயக்கி, "மீண்டும் முயற்சி" தட்டுங்கள்.',
            );
    }
    if (kIsWeb) {
      return bi(
        'This browser\'s speech service is off. Use Google Chrome, allow the microphone for this site, then tap Try again.',
        'இந்த browser-இன் குரல் சேவை இயங்கவில்லை. Google Chrome பயன்படுத்துங்கள், இந்தத் தளத்துக்கு மைக் அனுமதி கொடுத்து, "மீண்டும் முயற்சி" தட்டுங்கள்.',
      );
    }
    return bi(
      'VIMO has the microphone, but the phone\'s speech service does not. Open Settings, Apps, Google (or Speech Recognition & Synthesis), Permissions, and allow the microphone.',
      'VIMO-க்கு மைக் அனுமதி உள்ளது; ஆனால் போனின் குரல் அறிதல் சேவைக்கு இல்லை. Settings → Apps → Google (அல்லது Speech Recognition & Synthesis) → Permissions → Microphone அனுமதி கொடுங்கள்.',
    );
  }

  /// "Type instead": voice is not available, so go to the milk form, after
  /// the unsaved voice entries are saved or deleted.
  Future<void> _typeInstead() async {
    final navigator = Navigator.of(context);
    if (_entries.isNotEmpty) {
      await settleVoiceDraftBeforeManual(context);
      _entries.clear();
    }
    if (!mounted) return;
    navigator.pushReplacement(
      LiquidRoute<void>(builder: (_) => const AddEntryScreen()),
    );
  }

  /// "Allow microphone": ask again (shows the pop-up when the phone still
  /// allows it), then carry on listening.
  Future<void> _retryMic() async {
    _retriedAt = DateTime.now();
    if (!await _checkMic()) return;
    if (!mounted) return;
    if (!_initialised) {
      await _start();
      return;
    }
    setState(() => _micError = null);
    _running = true;
    _scheduleListen();
  }

  Future<void> _resumeMic() async {
    if (!await _checkMic()) return;
    if (!mounted || _report) return;
    if (!_initialised) {
      await _start();
      return;
    }
    _running = true;
    _scheduleListen(const Duration(milliseconds: 400));
  }

  /// The recogniser reported a permission error: find out whose permission
  /// is missing, VIMO's or the phone's speech service's.
  Future<void> _onPermissionError(String code) async {
    final access = await ensureMicPermission(speech: true, ask: false);
    if (!mounted) return;
    if (access.isGranted) {
      _showMicProblem(_MicProblem.speechService);
    } else {
      await _checkMic(ask: false);
    }
  }

  bool get _canSwitchToEar =>
      kIsWeb && earSupported && _engine is! BrowserEarEngine;

  Future<void> _switchToEar(String reason) async {
    VoiceDiagnostics.log('ear_switch', {'reason': reason, 'locale': _locale});
    _running = false;
    await _dropEngine();
    if (!mounted) return;
    setState(() {
      _earChosen = true;
      _micError = null;
      _micProblem = null;
    });
    await _start();
  }

  // --- start, listen, speak ----------------------------------------------------

  Future<void> _start() async {
    if (!canRecordEntries) {
      setState(
        () => _micError = bi(
          'Your ranch role does not allow adding entries',
          'உங்கள் பொறுப்பில் பதிவு சேர்க்க அனுமதி இல்லை',
        ),
      );
      return;
    }
    // Never trust the recogniser's remembered start: check the permission
    // itself, asking with the system pop-up when it is still possible.
    if (!await _checkMic()) return;
    await _setupVoice();
    bool ok = false;
    try {
      if (_engine == null && _wantEar) {
        final model = await earModelReadyFor(_locale);
        if (!await earDownloaded(model)) {
          // One download, offered on a card: nothing starts until then.
          if (mounted) setState(() => _earOffer = model);
          return;
        }
        final engine = BrowserEarEngine(model);
        _engine = engine;
        _listenTo(engine);
        ok = await engine.initialize();
      } else if (_engine == null) {
        final (engine, started) = await createVoiceEngine(
          offlineEnabled: voiceOfflineBetaEnabled(),
          offlineModelPath: offlineVoiceModelPath(_locale),
          log: VoiceDiagnostics.log,
        );
        _engine = engine;
        ok = started;
        _listenTo(engine);
      } else {
        ok = await _engine!.initialize();
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(
        () => _micError = bi(
          'Microphone or speech recognition is not available. Allow the microphone, and on a computer use Google Chrome.',
          'மைக் அல்லது குரல் அறிதல் கிடைக்கவில்லை. மைக் அனுமதி கொடுங்கள்; கணினியில் Google Chrome பயன்படுத்துங்கள்.',
        ),
      );
      return;
    }
    _initialised = true;
    _running = true;
    VoiceDiagnostics.log('voice_session_start', {
      'appVersion': vimoAppVersion,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'appLanguage': appLanguage.mode,
      'voiceLocale': _locale,
      'engine': _engine?.name ?? 'system',
      'tamilVoice': _tamilVoice,
      'cows': cowNames().length,
    });
    unawaited(_logLocales());
    _micError = null;
    _micProblem = null;
    _keepAwake(true);
    if (cowNames().isEmpty) {
      _line(
        _LineKind.note,
        bi(
          'Add a cow before recording milk.',
          'பால் பதிவுக்கு முதலில் மாடு சேர்க்கவும்.',
        ),
      );
    }
    _say(
      const _Say(
        'தயார். ஹே விமோ சொல்லுங்க.',
        'Ready. Hey Vimo sollunga.',
        'Ready. Say Hey Vimo.',
      ),
    );
  }

  Future<void> _setupVoice() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      final available = await _tts.isLanguageAvailable('ta-IN');
      _tamilVoice = available == true || available == 1;
    } catch (_) {
      _tamilVoice = false;
    }
  }

  void _keepAwake(bool on) =>
      _quietly(on ? WakelockPlus.enable : WakelockPlus.disable);

  /// Runs a plugin call whose failure must never reach the person.
  static void _quietly(Future<dynamic> Function() call) {
    try {
      unawaited(call().catchError((_) => null));
    } catch (_) {}
  }

  void _scheduleListen([Duration delay = const Duration(milliseconds: 300)]) {
    _restart?.cancel();
    if (!_running || _report) return;
    _restart = Timer(delay, _listen);
  }

  Future<void> _listen() async {
    if (!mounted || !_running || _report || _speaking || _starting) return;
    final engine = _engine;
    if (engine == null || _micError != null || engine.isListening) return;
    _starting = true;
    _listenStartedAt = DateTime.now();
    _firstWordsLogged = false;
    _consumed = '';
    try {
      await engine.start(
        locale: _locale,
        // Names and words to favour: the wake word, cows, customers and the
        // owner's learned words.
        hotwords: voiceHotwords(),
        // A long first wait so silence does not restart the microphone
        // every second; shortened as soon as words arrive.
        pauseFor: const Duration(seconds: 12),
        listenFor: const Duration(seconds: 55),
      );
      if (!_engineFactsLogged) {
        _engineFactsLogged = true;
        VoiceDiagnostics.log('engine_facts', engine.facts);
      }
    } catch (_) {
      _scheduleListen(const Duration(seconds: 1));
    } finally {
      _starting = false;
    }
  }

  Future<void> _logLocales() async {
    try {
      final ids =
          await (_engine?.supportedLocales() ?? Future.value(<String>[]));
      VoiceDiagnostics.log('speech_locales', {
        'count': ids.length,
        'tamil': ids.any((id) => id.toLowerCase().startsWith('ta')),
        'locales': ids.take(40).toList(),
      });
    } catch (error) {
      VoiceDiagnostics.log('speech_locales_error', {'error': '$error'});
    }
  }

  /// VIMO's own ear is writing down what was said (a few seconds).
  bool _thinking = false;

  void _onStatus(String status) {
    if (status == earThinking || status == earThought) {
      if (mounted) setState(() => _thinking = status == earThinking);
      return;
    }
    VoiceDiagnostics.log('speech_status', {
      'status': status,
      if (_listenStartedAt != null && status != VoiceStatus.listening)
        'msListening': DateTime.now()
            .difference(_listenStartedAt!)
            .inMilliseconds,
    });
    if (!mounted) return;
    final listening = status == VoiceStatus.listening;
    if (listening != _listeningNow) setState(() => _listeningNow = listening);
    if (!listening && !_speaking) {
      _scheduleListen(
        Duration(milliseconds: 250 + 250 * _errorStreak.clamp(0, 8)),
      );
    }
  }

  void _onError(VoiceEngineError error) {
    if (!mounted) return;
    final message = error.code;
    VoiceDiagnostics.log('speech_error', {
      'code': message,
      'permanent': error.permanent,
      'phase': _phase.name,
    });
    if (const {
      'error_permission',
      'not-allowed',
      'service-not-allowed',
      'error_insufficient_permissions',
    }.contains(message)) {
      if (message == 'service-not-allowed' && _canSwitchToEar) {
        // The browser's speech service is blocked: VIMO's own ear.
        unawaited(_switchToEar(message));
        return;
      }
      _running = false;
      unawaited(_onPermissionError(message));
      return;
    }
    if (message == 'audio-suspended') {
      // The iPhone wants a tap before the microphone can be heard.
      setState(
        () => _micError = bi(
          'Tap the microphone to start listening',
          'கேட்கத் தொடங்க மைக்கைத் தட்டுங்கள்',
        ),
      );
      return;
    }
    if (const {
          'error_language_not_supported',
          'language-not-supported',
          'error_language_unavailable',
        }.contains(message) &&
        _canSwitchToEar) {
      // This browser cannot listen in this language: VIMO's own ear can.
      unawaited(_switchToEar(message));
      return;
    }
    if (const {
      'error_language_not_supported',
      'language-not-supported',
      'error_language_unavailable',
    }.contains(message)) {
      setState(
        () => _micError = bi(
          'This phone cannot listen in this language. Choose another language above.',
          'இந்த மொழியில் கேட்க இந்த போனில் வசதி இல்லை. மேலே வேறு மொழியைத் தேர்வு செய்யுங்கள்.',
        ),
      );
      return;
    }
    if (const {'error_network', 'network', 'error_server'}.contains(message)) {
      _errorStreak++;
      if (_errorStreak == 3) {
        _line(
          _LineKind.note,
          bi(
            'Voice needs the internet on this phone. Retrying…',
            'குரல் அறிதலுக்கு இணையம் தேவை. மீண்டும் முயற்சிக்கிறது…',
          ),
        );
      }
    }
  }

  void _onResult(VoiceHeard result) {
    if (!mounted || _speaking) return;
    final words = result.text.trim();
    if (words.isEmpty || words == _consumed) return;
    final alternatives = [words, ...result.alternatives];
    _lastConfidence = result.confidence;
    if (!result.isFinal) {
      // Keep the microphone open past VIMO's own end-of-sentence pause.
      _engine?.changePauseFor(const Duration(milliseconds: 2600));
      if (words.length > _partial.length) {
        // The first words of a sentence: a light tap, like Siri noticing.
        if (_partial.isEmpty) HapticFeedback.selectionClick();
        if (!_firstWordsLogged && _listenStartedAt != null) {
          _firstWordsLogged = true;
          VoiceDiagnostics.log('first_words', {
            'ms': DateTime.now().difference(_listenStartedAt!).inMilliseconds,
          });
        }
        _hear.forward(from: 0);
      }
      setState(() => _partial = words);
      _pendingAlternatives = alternatives;
      _settle?.cancel();
      _settle = Timer(
        const Duration(milliseconds: 1250),
        () => _sentence(_pendingAlternatives),
      );
      return;
    }
    _sentence(alternatives);
  }

  /// One finished sentence: act on it once, then listen afresh.
  void _sentence(List<String> alternatives) {
    _settle?.cancel();
    if (!mounted || _speaking || alternatives.isEmpty) return;
    final words = alternatives.first.trim();
    if (words.isEmpty || words == _consumed) return;
    _consumed = words;
    setState(() => _partial = '');
    final now = DateTime.now();
    if (words == _lastFinal &&
        now.difference(_lastFinalAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastFinal = words;
    _lastFinalAt = now;
    _errorStreak = 0;
    // A fresh session for the next sentence: browsers would otherwise keep
    // adding new words to this one.
    _quietly(_cancelEar);
    _scheduleListen(const Duration(milliseconds: 200));
    VoiceDiagnostics.log('heard', {
      'text': words,
      'alternatives': alternatives.skip(1).take(4).toList(),
      'confidence': _lastConfidence,
      'phase': _phase.name,
    });
    _handle(alternatives);
  }

  /// Queues [say]: speaking stops the microphone (so VIMO never hears itself)
  /// and listening resumes when the voice ends.
  void _say(_Say say, {bool show = true}) {
    final text = _tamilReplies ? say.ta : say.en;
    VoiceDiagnostics.log('reply', {'text': say.en, 'phase': _phase.name});
    if (show) _line(_LineKind.vimo, text);
    final spoken = _tamilReplies
        ? (_tamilVoice ? say.ta : say.tanglish)
        : say.en;
    final language = _tamilReplies && _tamilVoice
        ? 'ta-IN'
        : (_locale.startsWith('hi') ? 'hi-IN' : 'en-IN');
    _speech = _speech.then((_) => _speakNow(spoken, language));
  }

  Future<void> _speakNow(String text, String language) async {
    if (!mounted) return;
    if (!_running) {
      // The microphone is off (a permission or speech service problem):
      // nothing is spoken, but Finish must still open the report.
      if (_finishAfterSpeech) {
        _finishAfterSpeech = false;
        _openReport();
      }
      return;
    }
    _restart?.cancel();
    _settle?.cancel();
    setState(() {
      _speaking = true;
      _partial = '';
    });
    try {
      await _cancelEar();
    } catch (_) {}
    try {
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(kIsWeb ? 1.0 : 0.5);
      final limit = Duration(
        milliseconds: (1200 + text.length * 90).clamp(1600, 9000),
      );
      // Some voices never report the end: the length of the text bounds it.
      final ended = Completer<void>();
      final timer = Timer(limit, () {
        if (!ended.isCompleted) ended.complete();
      });
      await Future.any([_tts.speak(text), ended.future]);
      timer.cancel();
    } catch (error) {
      VoiceDiagnostics.log('tts_error', {
        'language': language,
        'error': '$error',
      });
    }
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => _speaking = false);
    if (_finishAfterSpeech) {
      _finishAfterSpeech = false;
      _openReport();
      return;
    }
    _scheduleListen(const Duration(milliseconds: 60));
  }

  // --- conversation --------------------------------------------------------------

  void _line(_LineKind kind, String text, {String? entryId}) {
    if (!mounted) return;
    setState(() => _lines.add(_Line(kind, text, entryId: entryId)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: Motion.medium,
          curve: Motion.settle,
        );
      }
    });
  }

  String _name(String cow) => _tamilReplies ? tamilCowName(cow) : cow;

  void _armSleep([Duration after = const Duration(seconds: 14)]) {
    _sleep?.cancel();
    _sleep = Timer(after, _goToSleep);
  }

  void _goToSleep() {
    if (!mounted || _report) return;
    if (_speaking) {
      _armSleep(const Duration(seconds: 4));
      return;
    }
    final pending = _pending;
    if (pending != null && (pending.cow != null || pending.litres != null)) {
      _line(
        _LineKind.note,
        bi(
          'Not confirmed, so nothing was added',
          'உறுதி செய்யாததால் சேர்க்கவில்லை',
        ),
      );
    }
    _pending = null;
    if (_dialogue.active) {
      _dialogue.reset();
      _line(
        _LineKind.note,
        bi(
          'Not confirmed, so nothing was added',
          'உறுதி செய்யாததால் சேர்க்கவில்லை',
        ),
      );
    }
    if (_phase != _VoicePhase.sleeping) {
      UiSound.play(UiSoundKind.toggleOff);
      setState(() => _phase = _VoicePhase.sleeping);
    }
  }

  void _wake({bool silent = false}) {
    _sleep?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _VoicePhase.awake;
      _pending = null;
    });
    if (!silent) {
      UiSound.play(UiSoundKind.toggleOn);
      _say(const _Say('ம்ம்?', 'Hmm?', 'Hmm?'));
    }
    _armSleep();
  }

  void _handle(List<String> alternatives) {
    if (_report) return;
    final pending = _pending;
    // When VIMO asked "Maina or Meena?", only those cows are possible.
    final cows =
        _phase == _VoicePhase.askCow &&
            pending != null &&
            pending.choices.length > 1
        ? pending.choices
        : cowNames();
    // The owner's own corrections come first (on-device learning).
    final heard = [for (final a in alternatives) voiceRewrite(a)];
    final command = bestVoiceCommand(heard, cows, aliases: cowNameAliases());
    final reading = readingFromCommand(command);
    VoiceDiagnostics.log('understood', {
      'input': command.text,
      'rewritten': heard.first != alternatives.first,
      'intent': reading.intent,
      'slots': reading.slots,
      'cow': command.cow?.name,
      'cowScore': command.cow?.score,
      'cowKey': command.cow == null ? null : phoneticKey(command.cow!.name),
      'heardKey': phoneticKey(command.text),
      'closeCows': command.closeCows,
      'phase': _phase.name,
      'pending': _pending == null
          ? null
          : {'cow': _pending!.cow, 'liters': _pending!.litres},
    });
    if (command.isEmpty && !command.wake) return;

    // Ranch work beyond milk: expenses, feed, a new cow, the doctor,
    // questions. Milk follow-ups in progress keep priority.
    final spoken = command.rest.join(' ');
    final full = understandVoice(
      spoken.isEmpty ? command.text : spoken,
      cows: cowNames(),
      aliases: cowNameAliases(),
    );
    final milkBusy = _pending != null || _phase == _VoicePhase.confirmUndo;
    final otherWork =
        !milkBusy && !_dialogue.active && dialogueIntents.contains(full.intent);
    if (otherWork || _dialogue.active) {
      VoiceDiagnostics.log('understood_extra', {
        'intent': full.intent,
        'slots': full.slots,
        'dialogue': _dialogue.intent,
        'asking': _dialogue.asking,
      });
    }

    if (_phase == _VoicePhase.sleeping) {
      if (!command.wake) return; // Not for VIMO: ordinary talk nearby.
      _line(_LineKind.me, command.text);
      final hasMore =
          command.hasEntryData || command.finish || command.cancel || otherWork;
      _wake(silent: hasMore);
      if (otherWork) {
        _talk(_dialogue.start(full, command.text));
      } else if (hasMore) {
        _process(command);
      }
      return;
    }
    _line(_LineKind.me, command.text);
    _armSleep();
    if (_dialogue.active) {
      if (command.finish && !command.hasEntryData) {
        _dialogue.reset();
        _finish();
      } else if (command.cancel && !command.hasEntryData) {
        _dialogue.reset();
        _say(
          const _Say(
            'சரி, விட்டுட்டேன்.',
            'Sari, vittuten.',
            'Okay, dropped it.',
          ),
        );
      } else {
        _talk(_dialogue.answer(command.text, yes: command.yes, no: command.no));
      }
      return;
    }
    if (otherWork) {
      _talk(_dialogue.start(full, command.text));
      return;
    }
    _process(command);
  }

  /// Speaks a dialogue turn and carries out its action.
  void _talk(DialogueTurn turn) {
    setState(() => _phase = _VoicePhase.awake);
    final action = turn.action;
    final say = turn.say;
    if (action != null &&
        (action.kind == 'query' || action.kind == 'history')) {
      final answer = answerVoiceQuestion(action.data);
      VoiceDiagnostics.log('answered', {
        'slots': action.data,
        'answer': answer.en,
      });
      _say(_Say(answer.ta, answer.tanglish, answer.en));
      _armSleep();
      return;
    }
    if (say != null) _say(_Say(say.ta, say.tanglish, say.en));
    if (action != null) unawaited(_saveAction(action));
    _armSleep();
  }

  Future<void> _saveAction(VoiceAction action) async {
    try {
      final saved = await saveVoiceAction(action);
      VoiceDiagnostics.log('action_saved', {
        'kind': action.kind,
        'saved': saved != null,
        'data': action.data,
      });
      if (saved == null || !mounted) return;
      HapticFeedback.lightImpact();
      UiSound.play(UiSoundKind.success);
      setState(() => _otherSaved.add(saved));
      _line(_LineKind.note, '✓ ${saved.summary}');
    } catch (error) {
      VoiceDiagnostics.log('action_error', {
        'kind': action.kind,
        'error': '$error',
      });
      if (mounted) {
        _line(
          _LineKind.note,
          bi(
            'Could not save. Please try again.',
            'சேமிக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
          ),
        );
      }
    }
  }

  void _process(VoiceCommand c) {
    if (c.finish && !c.hasEntryData) {
      _finish();
      return;
    }
    if (c.sale && !c.cowIsSure) {
      _sayNotSale();
      return;
    }
    // A correction with nothing pending fixes the entry just saved.
    if (c.correction &&
        _pending == null &&
        (_phase == _VoicePhase.awake || _phase == _VoicePhase.sleeping) &&
        _correctLast(c)) {
      return;
    }
    switch (_phase) {
      case _VoicePhase.confirmAdd:
        if (c.hasEntryData) {
          _merge(c);
          _evaluate();
        } else if (c.yes) {
          _commit();
        } else if (c.no || c.cancel) {
          _pending = null;
          setState(() => _phase = _VoicePhase.awake);
          _say(
            const _Say(
              'சரி, சேர்க்கல. மறுபடியும் சொல்லுங்க.',
              'Sari, add pannala. Marubadiyum sollunga.',
              'Okay, not added. Please say it again.',
            ),
          );
        } else {
          _askConfirm();
        }
      case _VoicePhase.confirmUndo:
        if (c.yes) {
          _undo();
        } else if (c.hasEntryData) {
          setState(() => _phase = _VoicePhase.awake);
          _merge(c);
          _evaluate();
        } else {
          setState(() => _phase = _VoicePhase.awake);
          _say(
            const _Say(
              'சரி, அப்படியே இருக்கு.',
              'Sari, appadiye irukku.',
              'Okay, kept as it is.',
            ),
          );
        }
      case _VoicePhase.sleeping:
      case _VoicePhase.awake:
      case _VoicePhase.askCow:
      case _VoicePhase.askLitres:
        if (!c.hasEntryData) {
          if (c.cancel || (c.no && _pending == null)) {
            _askUndo();
          } else if (c.no && _pending != null) {
            _pending = null;
            setState(() => _phase = _VoicePhase.awake);
            _say(
              const _Say(
                'சரி, விட்டுட்டேன்.',
                'Sari, vittuten.',
                'Okay, dropped it.',
              ),
            );
          } else if (_phase == _VoicePhase.askCow) {
            _askCow();
          } else if (_phase == _VoicePhase.askLitres) {
            _askLitres();
          } else {
            _notUnderstood(c);
          }
          return;
        }
        _merge(c);
        _evaluate();
    }
    if (c.finish && c.hasEntryData) _finishAfterSpeech = true;
  }

  void _merge(VoiceCommand c) {
    final pending = _pending ??= _Pending();
    final cow = c.cow;
    if (cow != null) {
      pending.cow = cow.name;
      pending.cowSure =
          c.cowIsSure ||
          (_phase == _VoicePhase.askCow && pending.choices.contains(cow.name));
      pending.choices = c.cowIsClear ? const [] : c.closeCows;
    }
    if (c.litres != null) pending.litres = c.litres;
    if (c.session != null) pending.session = c.session;
    if (c.yesterday) pending.yesterday = true;
    pending.heard.add(c.text);
  }

  /// "நேற்று மாலை " when the sentence named the day or milking.
  _Say _when(_Pending p) {
    final ta = [
      if (p.yesterday) 'நேற்று',
      if (p.session == 'Morning') 'காலை',
      if (p.session == 'Evening') 'மாலை',
    ].join(' ');
    final en = [
      if (p.yesterday) 'yesterday',
      if (p.session == 'Morning') 'morning',
      if (p.session == 'Evening') 'evening',
    ].join(' ');
    final tg = [
      if (p.yesterday) 'nethu',
      if (p.session == 'Morning') 'kaalai',
      if (p.session == 'Evening') 'maalai',
    ].join(' ');
    return _Say(
      ta.isEmpty ? '' : '$ta ',
      tg.isEmpty ? '' : '$tg ',
      en.isEmpty ? '' : ' $en',
    );
  }

  /// Milk to a person is a sale: voice mode records milking only.
  void _sayNotSale() {
    _pending = null;
    setState(() => _phase = _VoicePhase.awake);
    _say(
      const _Say(
        'இது பால் விற்பனை போல இருக்கு. இங்கே கறந்த பால் மட்டும் பதிவாகும். மாடு பெயரும் லிட்டரும் சொல்லுங்க.',
        'Idhu paal virpanai pola irukku. Inga karandha paal mattum. Maadu perum litre-um sollunga.',
        'That sounds like a milk sale. Voice mode records milking only. Say the cow and the litres.',
      ),
    );
  }

  /// "5 இல்லை 9 லிட்டர்" after an entry: change that entry's litres.
  bool _correctLast(VoiceCommand c) {
    final litres = c.litres;
    if (litres == null || _entries.isEmpty) return false;
    final cow = c.cow?.name;
    final target = cow == null
        ? _entries.last
        : _entries.lastWhere((e) => e.cow == cow, orElse: () => _entries.last);
    if (cow != null && target.cow != cow) return false;
    setState(() {
      target.litres = litres;
      _litreFields[target.id]?.text = _litreWord(litres);
      _phase = _VoicePhase.awake;
    });
    unawaited(_storeVoiceDraft(_entries));
    VoiceDiagnostics.log('entry_corrected', {
      'cow': target.cow,
      'liters': litres,
    });
    HapticFeedback.lightImpact();
    final n = _litreWord(litres);
    _say(
      _Say(
        'சரி, ${tamilDative(_name(target.cow))} $n லிட்டர் என்று மாற்றினேன்.',
        'Sari, ${target.cow}-ku $n litre-nu maathiten.',
        'Changed ${target.cow} to $n litres.',
      ),
    );
    _armSleep();
    return true;
  }

  void _evaluate() {
    final pending = _pending;
    if (pending == null) return;
    if (pending.cow == null) {
      _askCow();
      return;
    }
    if (pending.choices.length > 1 && !pending.cowSure) {
      setState(() => _phase = _VoicePhase.askCow);
      final names = pending.choices.map(_name).toList();
      _say(
        _Say(
          '${names.map(tamilQuestion).join(' ')}?',
          '${pending.choices.join(' illa ')}?',
          '${pending.choices.join(' or ')}?',
        ),
      );
      return;
    }
    if (pending.litres == null) {
      _askLitres();
      return;
    }
    final already = _sessionTotal(pending.cow!);
    final big = pending.litres! > 30;
    if (!pending.cowSure || big || already > 0) {
      _askConfirm();
      return;
    }
    _commit();
  }

  double _sessionTotal(String cow) {
    double total = 0;
    for (final e in _entries) {
      if (e.cow == cow) total += e.litres;
    }
    return total;
  }

  void _askCow() {
    setState(() => _phase = _VoicePhase.askCow);
    final litres = _pending?.litres;
    if (litres == null) {
      _say(const _Say('எந்த மாடு?', 'Endha maadu?', 'Which cow?'));
    } else {
      final n = _litreWord(litres);
      _say(
        _Say(
          '$n லிட்டர். எந்த மாட்டுக்கு?',
          '$n litre. Endha maatukku?',
          '$n litres. Which cow?',
        ),
      );
    }
  }

  void _askLitres() {
    setState(() => _phase = _VoicePhase.askLitres);
    final cow = _pending?.cow ?? '';
    _say(
      _Say(
        '${tamilDative(_name(cow))} எத்தனை லிட்டர்?',
        '$cow-ku ethana litre?',
        'How many litres for $cow?',
      ),
    );
  }

  void _askConfirm() {
    final pending = _pending;
    if (pending == null || pending.cow == null || pending.litres == null) {
      _evaluate();
      return;
    }
    setState(() => _phase = _VoicePhase.confirmAdd);
    final cow = pending.cow!;
    final n = _litreWord(pending.litres!);
    final already = _sessionTotal(cow);
    final recorded = milkRecordedFor(
      cow,
      milkSessionForTime(DateTime.now()),
      todayDate(),
    );
    if (already > 0) {
      final m = _litreWord(already);
      _say(
        _Say(
          '${tamilDative(_name(cow))} ஏற்கனவே $m லிட்டர் இருக்கு. இன்னும் $n லிட்டர் சேர்க்கவா?',
          '$cow-ku already $m litre irukku. Innum $n litre add pannava?',
          '$cow already has $m litres. Add $n more?',
        ),
      );
    } else if (recorded > 0 && pending.cowSure && pending.litres! <= 30) {
      final m = _litreWord(recorded);
      _say(
        _Say(
          'இந்த நேரத்துக்கு ${tamilDative(_name(cow))} $m லிட்டர் ஏற்கனவே பதிவாகியிருக்கு. $n லிட்டர் சேர்க்கவா?',
          '$cow-ku indha neram already $m litre irukku. $n litre add pannava?',
          '$cow already has $m litres this session. Add $n litres?',
        ),
      );
    } else {
      _say(
        _Say(
          '${tamilDative(_name(cow))} $n லிட்டர். சேர்க்கவா?',
          '$cow-ku $n litre. Add pannava?',
          '$n litres for $cow. Shall I add it?',
        ),
      );
    }
  }

  void _commit() {
    final pending = _pending;
    if (pending == null || pending.cow == null || pending.litres == null) {
      return;
    }
    final now = DateTime.now();
    final entry = VoiceMilkEntry(
      id: now.microsecondsSinceEpoch.toString(),
      cow: pending.cow!,
      litres: pending.litres!,
      at: pending.yesterday ? now.subtract(const Duration(days: 1)) : now,
      heard: pending.heard.join(' · '),
      session: pending.session,
    );
    final when = _when(pending);
    _pending = null;
    setState(() {
      _entries.add(entry);
      _phase = _VoicePhase.awake;
    });
    unawaited(_storeVoiceDraft(_entries));
    HapticFeedback.lightImpact();
    UiSound.play(UiSoundKind.success);
    _line(_LineKind.entry, '', entryId: entry.id);
    VoiceDiagnostics.log('entry_added', {
      'cow': entry.cow,
      'liters': entry.litres,
      'session': entry.session,
      'heard': entry.heard,
    });
    final n = _litreWord(entry.litres);
    _say(
      _Say(
        '${when.ta}${tamilDative(_name(entry.cow))} $n லிட்டர் சேர்த்தேன்.',
        '${when.tanglish}${entry.cow}-ku $n litre add panniten.',
        'Added $n litres for ${entry.cow}${when.en}.',
      ),
      show: false,
    );
    _armSleep();
  }

  void _askUndo() {
    if (_entries.isEmpty) {
      _say(
        const _Say(
          'இன்னும் எதுவும் சேர்க்கல.',
          'Innum edhuvum add pannala.',
          'Nothing added yet.',
        ),
      );
      return;
    }
    final last = _entries.last;
    setState(() => _phase = _VoicePhase.confirmUndo);
    final n = _litreWord(last.litres);
    _say(
      _Say(
        'கடைசியா ${tamilDative(_name(last.cow))} $n லிட்டர். அதை நீக்கவா?',
        'Kadaisiya ${last.cow}-ku $n litre. Adha neekkava?',
        'Remove the last entry, $n litres for ${last.cow}?',
      ),
    );
  }

  void _undo() {
    if (_entries.isEmpty) return;
    final removed = _entries.removeLast();
    VoiceDiagnostics.log('entry_removed', {
      'cow': removed.cow,
      'liters': removed.litres,
    });
    setState(() {
      _lines.removeWhere((l) => l.entryId == removed.id);
      _phase = _VoicePhase.awake;
    });
    unawaited(_storeVoiceDraft(_entries));
    _say(const _Say('நீக்கிட்டேன்.', 'Neekkiten.', 'Removed.'));
  }

  void _notUnderstood(VoiceCommand c) {
    if (c.yes) {
      _say(
        const _Say(
          'மாடு பெயரும் லிட்டரும் சொல்லுங்க. உதாரணம்: மைனா 5 லிட்டர்.',
          'Maadu perum litre-um sollunga.',
          'Say the cow and the litres, like Maina 5 litres.',
        ),
      );
      return;
    }
    _say(
      const _Say(
        'புரியல. மாடு பெயரும் லிட்டரும் சொல்லுங்க.',
        'Puriyala. Maadu perum litre-um sollunga.',
        'Sorry, I did not get that. Say the cow and the litres.',
      ),
    );
  }

  void _finish() {
    if (_report || _finishAfterSpeech) return;
    _sleep?.cancel();
    _pending = null;
    if (!_running || _micProblem != null) {
      // No voice to speak with: show the report straight away.
      _openReport();
      return;
    }
    final total = _entries.fold<double>(0, (s, e) => s + e.litres);
    final cows = _entries.map((e) => e.cow).toSet().length;
    if (_entries.isEmpty) {
      _say(
        const _Say(
          'எதுவும் பதிவாகல.',
          'Edhuvum padhivaagala.',
          'Nothing was recorded.',
        ),
      );
      _finishAfterSpeech = true;
      return;
    }
    final t = _litreWord(total);
    _say(
      _Say(
        'முடிஞ்சது. மொத்தம் $cows மாட்டுக்கு $t லிட்டர். சரிபார்த்து சேமிங்க.',
        'Mudinjadhu. Mottham $cows maatukku $t litre. Check panni save pannunga.',
        'Done. $t litres from $cows cows. Check and save.',
      ),
    );
    _finishAfterSpeech = true;
  }

  void _openReport() {
    _restart?.cancel();
    _sleep?.cancel();
    _quietly(_cancelEar);
    UiSound.play(UiSoundKind.whoosh);
    setState(() {
      _report = true;
      _phase = _VoicePhase.sleeping;
      _partial = '';
    });
  }

  void _resumeListening() {
    setState(() => _report = false);
    if (!_initialised) {
      _start();
      return;
    }
    _running = true;
    _say(
      const _Say(
        'தொடர்கிறேன். ஹே விமோ சொல்லுங்க.',
        'Thodargiren. Hey Vimo sollunga.',
        'Listening again. Say Hey Vimo.',
      ),
    );
  }

  Future<void> _changeLocale() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s20,
                0,
                Space.s20,
                Space.s8,
              ),
              child: AppText(
                bi('Listen in', 'கேட்கும் மொழி'),
                style: TextStyle(
                  fontSize: Gold.t16,
                  fontWeight: FontWeight.w700,
                  color: Ink.navy,
                ),
              ),
            ),
            for (final l in voiceLocales)
              ListTile(
                title: Text(l.label),
                trailing: l.id == _locale
                    ? Icon(CupertinoIcons.check_mark, color: Ink.tint)
                    : null,
                onTap: () => Navigator.of(context).pop(l.id),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s20,
                Space.s4,
                Space.s20,
                Space.s16,
              ),
              child: AppText(
                bi(
                  'Tamil understands English words mixed in, like "Maina 5 litre add pannu".',
                  'தமிழில் English வார்த்தைகளும் புரியும்: "மைனா 5 litre add பண்ணு".',
                ),
                style: TextStyle(fontSize: 13, color: Ink.muted),
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == _locale || !mounted) return;
    await setSetting(_voiceLocaleKey, chosen);
    try {
      await _cancelEar();
    } catch (_) {}
    final before = _engine;
    final ear = before is BrowserEarEngine ? before.model : null;
    setState(() {
      _locale = chosen;
      _micError = null;
      _earOffer = null;
      _earChosen = false;
    });
    // A different ear for this language (Tamil model, other model, or the
    // browser's own service): start again with the right one.
    final wantsEar = _wantEar;
    if (ear != null ? (!wantsEar || earModelFor(chosen) != ear) : wantsEar) {
      _running = false;
      await _dropEngine();
      if (mounted) await _start();
      return;
    }
    if (!_running && _initialised) _running = true;
    _scheduleListen();
  }

  void _tapOrb() {
    if (_micProblem != null) {
      // A permission problem: ask again rather than only restarting.
      if (_micProblem == _MicProblem.speechService && !kIsWeb) {
        unawaited(openMicSettings());
      } else {
        unawaited(_retryMic());
      }
      return;
    }
    if (_micError != null) {
      setState(() => _micError = null);
      if (_initialised) {
        _running = true;
        _scheduleListen();
      } else {
        _start();
      }
      return;
    }
    if (_speaking) {
      _quietly(_tts.stop);
      return;
    }
    if (_phase == _VoicePhase.sleeping) {
      _wake();
    } else {
      _goToSleep();
    }
  }

  /// "Improve VIMO": the owner types what was really said; VIMO learns it
  /// on this phone at once (sentence and words, by sound).
  Future<void> _improve(String heard) async {
    final field = TextEditingController(text: heard);
    final meant = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          Space.s20,
          0,
          Space.s20,
          Space.s20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText(
              bi('Improve VIMO', 'VIMO-வை மேம்படுத்து'),
              style: TextStyle(
                fontSize: Gold.t16 + 1,
                fontWeight: FontWeight.w700,
                color: Ink.navy,
              ),
            ),
            const SizedBox(height: Space.s4),
            AppText(
              bi(
                'VIMO heard: "$heard". Type what you said; VIMO will understand it next time.',
                'VIMO கேட்டது: "$heard". நீங்கள் சொன்னதை எழுதுங்கள்; அடுத்த முறை VIMO புரிந்துகொள்ளும்.',
              ),
              style: TextStyle(fontSize: 13, color: Ink.muted),
            ),
            const SizedBox(height: Space.s12),
            TextField(
              controller: field,
              autofocus: true,
              decoration: fieldStyle(
                bi('What you said', 'நீங்கள் சொன்னது'),
                icon: CupertinoIcons.pencil,
              ),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
            const SizedBox(height: Space.s12),
            LiquidButton(
              label: bi('Teach VIMO', 'VIMO-க்குக் கற்றுக்கொடு'),
              icon: CupertinoIcons.lightbulb,
              onPressed: () => Navigator.of(context).pop(field.text),
            ),
          ],
        ),
      ),
    );
    field.dispose();
    final text = meant?.trim() ?? '';
    if (text.isEmpty || text == heard.trim()) return;
    await rememberVoiceCorrection(heard, text);
    if (mounted) {
      snack(
        context,
        bi('VIMO learned this', 'VIMO இதைக் கற்றுக்கொண்டது'),
        tone: SnackTone.success,
      );
    }
  }

  Future<bool> _confirmLeave() async {
    final leave = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(bi('Leave without saving?', 'சேமிக்காமல் வெளியேறவா?')),
        content: Text(
          bi(
            'Your entries stay as a draft and come back next time.',
            'பதிவுகள் வரைவாக இருக்கும்; அடுத்த முறை திரும்ப வரும்.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(bi('Stay', 'இருக்கட்டும்')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(bi('Leave', 'வெளியேறு')),
          ),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _save() async {
    if (_saving) return;
    for (final e in _entries) {
      final field = _litreFields[e.id];
      if (field != null) e.litres = toDouble(field.text);
    }
    final invalid = _entries.where((e) => e.cow.isEmpty || e.litres <= 0);
    if (invalid.isNotEmpty) {
      snack(
        context,
        bi(
          'Every row needs a cow and litres above 0',
          'ஒவ்வொரு வரிசைக்கும் மாடும் 0-க்கு மேல் லிட்டரும் தேவை',
        ),
        tone: SnackTone.error,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final total = _entries.fold<double>(0, (s, e) => s + e.litres);
      final count = await saveVoiceMilkEntries(_entries);
      VoiceDiagnostics.log('saved', {'entries': count, 'liters': total});
      _entries.clear();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      if (messenger != null) {
        snack(
          context,
          bi(
            'Saved $count entries · ${formatLitres(total)}',
            '$count பதிவுகள் சேமிக்கப்பட்டன · ${formatLitres(total)}',
          ),
          tone: SnackTone.success,
          messenger: messenger,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        snack(
          context,
          bi(
            'Could not save. Please try again.',
            'சேமிக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
          ),
          tone: SnackTone.error,
        );
      }
    }
  }

  // --- build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final locale = voiceLocales.firstWhere(
      (l) => l.id == _locale,
      orElse: () => voiceLocales.first,
    );
    return PopScope(
      canPop: _entries.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_report) {
          _finish();
          return;
        }
        final navigator = Navigator.of(context);
        // The draft stays saved, so leaving loses nothing.
        if (await _confirmLeave() && mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: Ink.canvasTop,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: AppText(
            _report
                ? bi('Voice milk report', 'குரல் பால் அறிக்கை')
                : bi('Voice milk', 'குரல் பால் பதிவு'),
          ),
          leading: const _BackButton(),
          actions: [
            if (!_report)
              Padding(
                padding: const EdgeInsets.only(right: Space.s12),
                child: Pressable(
                  radius: 22,
                  onTap: _changeLocale,
                  child: Container(
                    height: Space.s32 + Space.s4,
                    padding: const EdgeInsets.symmetric(horizontal: Space.s12),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: Ink.surface.withValues(alpha: .74),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.globe,
                          size: 16,
                          color: Ink.violetDeep,
                        ),
                        const SizedBox(width: Space.s4),
                        Text(
                          locale.short,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Ink.violetDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Shell(
          child: AnimatedSwitcher(
            duration: Motion.medium,
            switchInCurve: Motion.settle,
            child: _report ? _reportView() : _liveView(),
          ),
        ),
      ),
    );
  }

  // --- live view -----------------------------------------------------------------

  String get _statusText {
    if (_micError != null) return _micError!;
    if (!_initialised) {
      return bi('Starting the microphone…', 'மைக் தயாராகிறது…');
    }
    if (_speaking) return bi('VIMO is speaking…', 'VIMO பேசுகிறது…');
    if (_thinking) {
      return bi(
        'Understanding what you said…',
        'நீங்கள் சொன்னதைப் புரிந்துகொள்கிறேன்…',
      );
    }
    return switch (_phase) {
      _VoicePhase.sleeping => bi('Say "Hey Vimo"', '"ஹே விமோ" சொல்லுங்க'),
      _VoicePhase.awake => bi(
        'Listening… say cow and litres',
        'கேட்கிறேன்… மாடும் லிட்டரும் சொல்லுங்க',
      ),
      _VoicePhase.askCow => bi('Which cow?', 'எந்த மாடு?'),
      _VoicePhase.askLitres => bi('How many litres?', 'எத்தனை லிட்டர்?'),
      _VoicePhase.confirmAdd || _VoicePhase.confirmUndo => bi(
        'Say yes or no',
        '"ஆமா" அல்லது "வேண்டாம்" சொல்லுங்க',
      ),
    };
  }

  Widget _liveView() {
    final total = _entries.fold<double>(0, (s, e) => s + e.litres);
    final cows = _entries.map((e) => e.cow).toSet().length;
    return Column(
      key: const ValueKey('live'),
      children: [
        const SizedBox(height: Space.s56 + Space.s8),
        _VoiceOrb(
          animation: _breath,
          hearing: _hear,
          phase: _phase,
          speaking: _speaking,
          listening: _listeningNow,
          error: _micError != null,
          level: _level,
          onTap: _tapOrb,
        ),
        _ListeningBars(
          breath: _breath,
          hearing: _hear,
          active:
              _micError == null &&
              (_speaking ||
                  _phase != _VoicePhase.sleeping ||
                  _partial.isNotEmpty),
          speaking: _speaking,
          level: _level,
        ),
        const SizedBox(height: Space.s8),
        if (_earOffer != null)
          Flexible(
            flex: 3,
            child: SingleChildScrollView(
              child: _EarOfferCard(
                model: _earOffer!,
                tamil: _locale.startsWith('ta'),
                progress: _earProgress,
                onDownload: () => unawaited(_downloadEar()),
              ),
            ),
          )
        else if (_micProblem != null)
          // The help card scrolls on small phones instead of overflowing.
          Flexible(
            child: SingleChildScrollView(
              child: _MicProblemCard(
                message: _micError ?? '',
                problem: _micProblem!,
                // A web page cannot open the phone's settings.
                canOpenSettings: !kIsWeb,
                onAllow: () => unawaited(_retryMic()),
                onSettings: () => unawaited(openMicSettings()),
                onType: canRecordEntries
                    ? () => unawaited(_typeInstead())
                    : null,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s24),
            child: AnimatedSwitcher(
              duration: Motion.short,
              child: Text(
                _statusText,
                key: ValueKey(_statusText),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _micError != null ? 15 : Gold.t16 + 1,
                  fontWeight: FontWeight.w700,
                  color: _micError != null ? Ink.redText : Ink.navy,
                ),
              ),
            ),
          ),
        SizedBox(
          height: Space.s32 + Space.s8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s24,
              Space.s8,
              Space.s24,
              0,
            ),
            child: Text(
              _partial,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: Ink.muted,
              ),
            ),
          ),
        ),
        Expanded(
          child: _earOffer != null
              ? const SizedBox.shrink()
              : _lines.isEmpty
              ? _VoiceHelp(tamil: _tamilReplies)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                    Space.s16,
                    Space.s8,
                    Space.s16,
                    Space.s16,
                  ),
                  itemCount: _lines.length,
                  itemBuilder: (context, i) => _lineView(_lines[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.s16,
            0,
            Space.s16,
            Space.s16,
          ),
          child: Glass(
            radius: Gold.r27,
            padding: const EdgeInsets.fromLTRB(
              Space.s20,
              Space.s12,
              Space.s12,
              Space.s12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CountUpText(
                        value: total,
                        format: formatLitres,
                        style: TextStyle(
                          fontSize: Gold.t27,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.6,
                          color: Ink.deepPurple,
                        ),
                      ),
                      AppText(
                        bi(
                          '$cows cows · ${_entries.length} entries',
                          '$cows மாடு · ${_entries.length} பதிவு',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Ink.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  // 89 × φ: wide enough for the Tamil label, never less.
                  constraints: const BoxConstraints(minWidth: 144),
                  child: LiquidButton(
                    label: bi('Finish', 'முடிஞ்சது'),
                    icon: CupertinoIcons.checkmark_alt,
                    height: Space.target + Space.s4,
                    onPressed: _finish,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lineView(_Line line) {
    switch (line.kind) {
      case _LineKind.note:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s8),
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Ink.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case _LineKind.me:
        // Tap what VIMO heard to teach it what was really said.
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Semantics(
            button: true,
            hint: bi('Improve VIMO', 'VIMO-வை மேம்படுத்து'),
            child: GestureDetector(
              onTap: () => unawaited(_improve(line.text)),
              child: Container(
                margin: const EdgeInsets.only(top: Space.s8, left: Space.s48),
                padding: const EdgeInsets.fromLTRB(
                  Space.s16,
                  Space.s12,
                  Space.s12,
                  Space.s12,
                ),
                decoration: ShapeDecoration(
                  shape: const SquircleBorder(radius: Gold.r21),
                  color: Ink.tint,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        line.text,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.3,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.s8),
                    Icon(
                      CupertinoIcons.pencil,
                      size: 14,
                      color: Colors.white.withValues(alpha: .7),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      case _LineKind.vimo:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(top: Space.s8, right: Space.s48),
            child: Glass(
              radius: Gold.r21,
              elevation: .6,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s16,
                vertical: Space.s12,
              ),
              child: Text(
                line.text,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  color: Ink.navy,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      case _LineKind.entry:
        final entry = _entries.where((e) => e.id == line.entryId).firstOrNull;
        if (entry == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Space.s8, right: Space.s32),
          child: Glass(
            radius: Gold.r21,
            elevation: .6,
            padding: const EdgeInsets.all(Space.s12),
            child: Row(
              children: [
                Container(
                  width: Space.s40,
                  height: Space.s40,
                  decoration: ShapeDecoration(
                    shape: const SquircleBorder(radius: Gold.r13),
                    color: Ink.green.withValues(alpha: .14),
                  ),
                  child: Icon(
                    CupertinoIcons.checkmark_alt,
                    color: Ink.greenText,
                    size: 22,
                  ),
                ),
                const SizedBox(width: Space.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizedAnimalLabel(entry.cow),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Ink.navy,
                        ),
                      ),
                      Text(
                        '${bi('Added', 'சேர்க்கப்பட்டது')} · ${_clock(entry.at)}',
                        style: TextStyle(fontSize: 13, color: Ink.muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatLitres(entry.litres),
                  style: TextStyle(
                    fontSize: Gold.t21,
                    fontWeight: FontWeight.w700,
                    color: Ink.deepPurple,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  // --- report --------------------------------------------------------------------

  TextEditingController _litreField(VoiceMilkEntry e) =>
      _litreFields.putIfAbsent(
        e.id,
        () => TextEditingController(text: _litreWord(e.litres)),
      );

  Widget _reportView() {
    for (final e in _entries) {
      final field = _litreFields[e.id];
      if (field != null) e.litres = toDouble(field.text);
    }
    final total = _entries.fold<double>(0, (s, e) => s + e.litres);
    final cowCount = _entries.map((e) => e.cow).toSet().length;
    final first = _entries.isEmpty ? null : _entries.first.at;
    final last = _entries.isEmpty ? null : _entries.last.at;
    final counts = <String, int>{};
    for (final e in _entries) {
      counts[e.cow] = (counts[e.cow] ?? 0) + 1;
    }
    return Column(
      key: const ValueKey('report'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.s16,
              Space.s56 + Space.s8,
              Space.s16,
              Space.s16,
            ),
            children: [
              Reveal(
                index: 0,
                child: Glass(
                  radius: Gold.r27,
                  padding: const EdgeInsets.all(Space.s20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.waveform,
                            size: 16,
                            color: Ink.orange,
                          ),
                          const SizedBox(width: Space.s4),
                          Flexible(
                            child: AppText(
                              bi('Recorded by voice', 'குரல் மூலம் பதிவானது'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Ink.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.s4),
                      CountUpText(
                        value: total,
                        format: formatLitres,
                        style: TextStyle(
                          fontSize: 40,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.2,
                          color: Ink.deepPurple,
                        ),
                      ),
                      const SizedBox(height: Space.s8),
                      Wrap(
                        spacing: Space.s12,
                        runSpacing: Space.s4,
                        children: [
                          _ReportFact(
                            icon: CupertinoIcons.circle_grid_3x3_fill,
                            text: bi('$cowCount cows', '$cowCount மாடு'),
                          ),
                          _ReportFact(
                            icon: CupertinoIcons.list_bullet,
                            text: bi(
                              '${_entries.length} entries',
                              '${_entries.length} பதிவு',
                            ),
                          ),
                          if (first != null && last != null)
                            _ReportFact(
                              icon: CupertinoIcons.clock,
                              text: _clock(first) == _clock(last)
                                  ? _clock(first)
                                  : '${_clock(first)} – ${_clock(last)}',
                            ),
                          for (final session
                              in _entries.map((e) => e.session).toSet())
                            _ReportFact(
                              icon: session == 'Morning'
                                  ? CupertinoIcons.sun_max
                                  : CupertinoIcons.moon,
                              text: ui(session),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.s16),
              if (_entries.isEmpty)
                const EmptyNote(
                  icon: CupertinoIcons.mic,
                  title: 'Nothing recorded',
                  message:
                      'Say "Hey Vimo" and a cow with litres, or add a row.',
                ),
              for (int i = 0; i < _entries.length; i++)
                Reveal(
                  index: 1 + i,
                  child: _reportRow(
                    i,
                    _entries[i],
                    (counts[_entries[i].cow] ?? 0) > 1,
                  ),
                ),
              if (_otherSaved.isNotEmpty) ...[
                const SizedBox(height: Space.s8),
                AppText(
                  bi('Also saved by voice', 'குரல் மூலம் சேமித்த மற்றவை'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Ink.navy,
                  ),
                ),
                for (final a in _otherSaved)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s4),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          size: 16,
                          color: Ink.greenText,
                        ),
                        const SizedBox(width: Space.s8),
                        Expanded(
                          child: Text(
                            '${a.summary} · ${_clock(a.at)}',
                            style: TextStyle(fontSize: 14, color: Ink.body),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: Space.s8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: cowNames().isEmpty ? null : _addRow,
                  icon: Icon(CupertinoIcons.plus_circle_fill, color: Ink.tint),
                  label: AppText(
                    bi('Add a row', 'வரிசை சேர்'),
                    style: TextStyle(
                      color: Ink.tint,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.s16,
            0,
            Space.s16,
            Space.s16,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 382,
                child: _SecondaryPill(
                  label: bi('Resume', 'தொடர்'),
                  icon: CupertinoIcons.mic_fill,
                  onTap: _saving ? null : _resumeListening,
                ),
              ),
              const SizedBox(width: Space.s12),
              // Golden split: the main action takes the larger part.
              Expanded(
                flex: 618,
                child: LiquidButton(
                  label: bi('Save all', 'சேமி'),
                  icon: CupertinoIcons.checkmark_alt,
                  busy: _saving,
                  height: Space.target + Space.s8,
                  onPressed: _entries.isEmpty ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reportRow(int index, VoiceMilkEntry e, bool repeated) {
    final cows = cowNames();
    final field = _litreField(e);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s8),
      child: Glass(
        radius: Gold.r21,
        elevation: .7,
        padding: const EdgeInsets.fromLTRB(
          Space.s12,
          Space.s12,
          Space.s4,
          Space.s12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: Space.s32,
                  height: Space.s32,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    shape: const SquircleBorder(radius: Gold.r13),
                    color: Ink.violet.withValues(alpha: .12),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Ink.violetDeep,
                    ),
                  ),
                ),
                const SizedBox(width: Space.s8),
                Expanded(
                  child: PopupMenuButton<String>(
                    tooltip: bi('Change cow', 'மாட்டை மாற்று'),
                    initialValue: e.cow,
                    onSelected: (cow) => setState(() {
                      e.cow = cow;
                      unawaited(_storeVoiceDraft(_entries));
                    }),
                    itemBuilder: (context) => [
                      for (final c in cows)
                        PopupMenuItem(
                          value: c,
                          child: Text(localizedAnimalLabel(c)),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.s8),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              localizedAnimalLabel(e.cow),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Ink.navy,
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.s4),
                          Icon(
                            CupertinoIcons.chevron_down,
                            size: 14,
                            color: Ink.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 89,
                  child: TextField(
                    controller: field,
                    textAlign: TextAlign.end,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      e.litres = toDouble(field.text);
                      unawaited(_storeVoiceDraft(_entries));
                      setState(() {});
                    },
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Ink.deepPurple,
                    ),
                    decoration: fieldStyle('').copyWith(
                      suffixText: 'L',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Space.s12,
                        vertical: Space.s12,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: bi('Remove', 'நீக்கு'),
                  onPressed: () => setState(() {
                    _entries.remove(e);
                    _litreFields.remove(e.id)?.dispose();
                    _lines.removeWhere((l) => l.entryId == e.id);
                    unawaited(_storeVoiceDraft(_entries));
                  }),
                  icon: Icon(
                    CupertinoIcons.trash,
                    size: 20,
                    color: Ink.redText,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: Space.s40, right: Space.s8),
              child: Wrap(
                spacing: Space.s8,
                runSpacing: Space.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _chip(
                    icon: CupertinoIcons.clock,
                    label: [
                      if (_dayOf(e.at) != todayDate())
                        bi('Yesterday', 'நேற்று'),
                      _clock(e.at),
                    ].join(' · '),
                    onTap: () => _editTime(e),
                  ),
                  // Tap to switch the milking: morning ⇄ evening.
                  _chip(
                    icon: e.session == 'Morning'
                        ? CupertinoIcons.sun_max
                        : CupertinoIcons.moon,
                    label: ui(e.session),
                    onTap: () {
                      selectionFeedback();
                      setState(() {
                        e.sessionOverride = e.session == 'Morning'
                            ? 'Evening'
                            : 'Morning';
                      });
                      unawaited(_storeVoiceDraft(_entries));
                    },
                  ),
                  if (repeated)
                    Text(
                      bi('Same cow twice', 'ஒரே மாடு இரு முறை'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Ink.amberText,
                      ),
                    ),
                  if (e.heard.isNotEmpty)
                    Text(
                      '“${e.heard}”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Ink.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => ActionChip(
    avatar: Icon(icon, size: 15, color: Ink.violetDeep),
    label: Text(label),
    labelStyle: TextStyle(
      color: Ink.violetDeep,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    backgroundColor: Ink.lavender,
    side: BorderSide.none,
    shape: const StadiumBorder(),
    visualDensity: VisualDensity.compact,
    onPressed: onTap,
  );

  Future<void> _editTime(VoiceMilkEntry e) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(e.at),
    );
    if (picked == null || !mounted) return;
    setState(() {
      e.at = DateTime(
        e.at.year,
        e.at.month,
        e.at.day,
        picked.hour,
        picked.minute,
      );
    });
    unawaited(_storeVoiceDraft(_entries));
  }

  void _addRow() {
    final cows = cowNames();
    if (cows.isEmpty) return;
    final used = _entries.map((e) => e.cow).toSet();
    final now = DateTime.now();
    setState(() {
      _entries.add(
        VoiceMilkEntry(
          id: now.microsecondsSinceEpoch.toString(),
          cow: cows.firstWhere(
            (c) => !used.contains(c),
            orElse: () => cows.first,
          ),
          litres: 0,
          at: now,
          heard: '',
        ),
      );
    });
  }
}

String _dayOf(DateTime at) => '${at.year}-${two(at.month)}-${two(at.day)}';

String _clock(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '$hour:${two(at.minute)} ${at.hour < 12 ? 'AM' : 'PM'}';
}

class _ReportFact extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ReportFact({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: Ink.violet),
      const SizedBox(width: Space.s4),
      Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Ink.body,
        ),
      ),
    ],
  );
}

class _SecondaryPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _SecondaryPill({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Pressable(
      radius: 26,
      onTap: onTap,
      child: Container(
        height: Space.target + Space.s8,
        padding: const EdgeInsets.symmetric(horizontal: Space.s12),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: Ink.surface.withValues(alpha: .8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: Ink.tint),
            const SizedBox(width: Space.s4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Ink.tint,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// How to talk to VIMO, shown before the first sentence.
class _VoiceHelp extends StatelessWidget {
  final bool tamil;
  const _VoiceHelp({required this.tamil});

  @override
  Widget build(BuildContext context) {
    final steps = tamil
        ? const [
            ('1', '"ஹே விமோ"', 'VIMO "ம்ம்?" என்று கேட்கும்'),
            ('2', '"மைனா 5 லிட்டர்"', 'அல்லது "Maina add 5 litre"'),
            ('3', '"முடிஞ்சது"', 'அறிக்கை வரும்; திருத்தி சேமிக்கலாம்'),
          ]
        : const [
            ('1', '"Hey Vimo"', 'VIMO answers "Hmm?"'),
            ('2', '"Maina 5 litre"', 'or "add 5 litre for Maina"'),
            ('3', '"Finish"', 'see the report, edit, then save'),
          ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.s20,
        Space.s8,
        Space.s20,
        Space.s16,
      ),
      children: [
        Glass(
          radius: Gold.r27,
          padding: const EdgeInsets.all(Space.s16),
          child: Column(
            children: [
              for (final s in steps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s8),
                  child: Row(
                    children: [
                      Container(
                        width: Space.s32,
                        height: Space.s32,
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          shape: const CircleBorder(),
                          color: Ink.tint,
                        ),
                        child: Text(
                          s.$1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.$2,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Ink.navy,
                              ),
                            ),
                            Text(
                              s.$3,
                              style: TextStyle(fontSize: 13, color: Ink.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s12),
        Text(
          tamil
              ? 'போனை சட்டைப் பையில் வைக்கலாம்; திரை அணையாது. "வேண்டாம்" அல்லது "cancel" சொன்னால் கடைசி பதிவை நீக்கலாம்.'
              : 'Keep the phone in your pocket; the screen stays on. Say "cancel" to remove the last entry.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Ink.muted, height: 1.4),
        ),
      ],
    );
  }
}

/// The listening orb: breathes while waiting for "Hey Vimo", glows orange
/// when awake, swells with the voice level, and turns green while speaking.
class _VoiceOrb extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> hearing;
  final _VoicePhase phase;
  final bool speaking;
  final bool listening;
  final bool error;
  final double level;
  final VoidCallback onTap;

  const _VoiceOrb({
    required this.animation,
    required this.hearing,
    required this.phase,
    required this.speaking,
    required this.listening,
    required this.error,
    required this.level,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final awake = phase != _VoicePhase.sleeping;
    final colors = error
        ? [Ink.red, const Color(0xFF8E1B2B)]
        : speaking
        ? [const Color(0xFF34C759), const Color(0xFF1E7B3A)]
        : awake
        ? [Ink.orange, Ink.tint]
        : [Ink.violet, Ink.deepPurple];
    // Android reports roughly -2..10 dB; the web reports nothing.
    final voice = ((level + 2) / 12).clamp(0.0, 1.0);
    // 89 × φ normally; 89 when a help card needs the room.
    final size = error ? 89.0 : 144.0;
    return Semantics(
      button: true,
      label: awake
          ? bi('Listening. Tap to stop', 'கேட்கிறது. நிறுத்த தட்டவும்')
          : bi('Tap to talk to VIMO', 'VIMO-விடம் பேச தட்டவும்'),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([animation, hearing]),
          builder: (context, _) {
            final t = Curves.easeInOut.transform(animation.value);
            // Rises and settles with each burst of words.
            final beat = hearing.isAnimating
                ? math.sin(math.pi * hearing.value)
                : 0.0;
            final heard = math.max(voice, beat);
            final swell = awake || speaking
                ? .06 * t + .12 * heard
                : .03 * t + .08 * beat;
            final glow = (awake ? 34.0 : 21.0) + 21 * t + 34 * heard;
            return SizedBox.square(
              dimension: size + (error ? 21 : 55),
              child: Center(
                child: Transform.scale(
                  scale: 1 + swell,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-.35, -.45),
                        radius: 1.05,
                        colors: [
                          Color.lerp(colors[0], Colors.white, .28)!,
                          colors[0],
                          colors[1],
                        ],
                        stops: const [0, .45, 1],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors[0].withValues(
                            alpha: listening || speaking ? .45 : .25,
                          ),
                          blurRadius: glow,
                          spreadRadius: 2 + 8 * heard,
                        ),
                      ],
                    ),
                    child: Icon(
                      error
                          ? CupertinoIcons.mic_slash_fill
                          : speaking
                          ? CupertinoIcons.waveform
                          : CupertinoIcons.mic_fill,
                      size: error ? 34 : 55,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Five bars under the orb that dance while VIMO hears or speaks, and rest
/// as dots while it waits for "Hey Vimo".
class _ListeningBars extends StatelessWidget {
  final Animation<double> breath;
  final Animation<double> hearing;
  final bool active;
  final bool speaking;
  final double level;

  const _ListeningBars({
    required this.breath,
    required this.hearing,
    required this.active,
    required this.speaking,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final color = speaking ? const Color(0xFF34C759) : Ink.orange;
    return ExcludeSemantics(
      child: SizedBox(
        height: Space.s24,
        child: AnimatedBuilder(
          animation: Listenable.merge([breath, hearing]),
          builder: (context, _) {
            final voice = ((level + 2) / 12).clamp(0.0, 1.0);
            final beat = hearing.isAnimating
                ? math.sin(math.pi * hearing.value)
                : 0.0;
            final energy = speaking ? .55 : math.max(voice, beat);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < 5; i++) ...[
                  if (i > 0) const SizedBox(width: Space.s4),
                  AnimatedContainer(
                    duration: Motion.quick,
                    width: Space.s4,
                    height: active
                        ? Space.s4 +
                              Space.s20 *
                                  (.25 +
                                          .75 *
                                              energy *
                                              (.5 +
                                                  .5 *
                                                      math.sin(
                                                        breath.value *
                                                                math.pi *
                                                                6 +
                                                            i * Gold.goldenAngle,
                                                      )))
                                      .clamp(0.0, 1.0)
                        : Space.s4,
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: active ? color : Ink.faint.withValues(alpha: .5),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Why the microphone cannot be used.
enum _MicProblem {
  /// Not allowed yet; asking again shows the pop-up.
  denied,

  /// Refused for good on the phone: only Settings can allow it.
  blocked,

  /// Blocked by the browser for this site.
  browserBlocked,

  /// VIMO may use the microphone, the phone's speech service may not.
  speechService,

  /// No microphone access here at all.
  unsupported,
}

/// The red card under the orb with the fix for a permission problem.
class _MicProblemCard extends StatelessWidget {
  final String message;
  final _MicProblem problem;
  final VoidCallback onAllow;
  final VoidCallback onSettings;
  final VoidCallback? onType;
  final bool canOpenSettings;

  const _MicProblemCard({
    required this.message,
    required this.problem,
    required this.onAllow,
    required this.onSettings,
    this.onType,
    this.canOpenSettings = true,
  });

  @override
  Widget build(BuildContext context) {
    final settingsHelp =
        problem == _MicProblem.blocked || problem == _MicProblem.speechService;
    final canOpenSettings = this.canOpenSettings && settingsHelp;
    // Where Settings cannot be opened from here, "Try again" leads.
    final canAsk =
        problem == _MicProblem.denied ||
        problem == _MicProblem.browserBlocked ||
        (settingsHelp && !canOpenSettings);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s16),
      child: Glass(
        radius: Gold.r21,
        tint: Ink.red.withValues(alpha: .06),
        padding: const EdgeInsets.all(Space.s16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.mic_slash_fill,
                  size: 20,
                  color: Ink.redText,
                ),
                const SizedBox(width: Space.s8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: Ink.navy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s12),
            Row(
              children: [
                if (canAsk)
                  Expanded(
                    child: LiquidButton(
                      label: problem != _MicProblem.denied
                          ? bi('Try again', 'மீண்டும் முயற்சி')
                          : bi('Allow microphone', 'அனுமதி கொடு'),
                      icon: CupertinoIcons.mic_fill,
                      height: Space.target,
                      onPressed: onAllow,
                    ),
                  ),
                if (canAsk && canOpenSettings) const SizedBox(width: Space.s8),
                if (canOpenSettings)
                  Expanded(
                    child: LiquidButton(
                      label: bi('Open Settings', 'Settings திற'),
                      icon: CupertinoIcons.settings,
                      height: Space.target,
                      onPressed: onSettings,
                    ),
                  ),
                if (canOpenSettings) ...[
                  const SizedBox(width: Space.s8),
                  Expanded(
                    child: _SecondaryPill(
                      label: bi('Try again', 'மீண்டும் முயற்சி'),
                      icon: CupertinoIcons.arrow_clockwise,
                      onTap: onAllow,
                    ),
                  ),
                ],
              ],
            ),
            if (onType != null) ...[
              const SizedBox(height: Space.s8),
              _SecondaryPill(
                label: bi('Type instead', 'கையால் பதிவு செய்'),
                icon: CupertinoIcons.keyboard,
                onTap: onType,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Offers VIMO's own ear: one download, then listening on the phone itself.
class _EarOfferCard extends StatelessWidget {
  final EarModel model;
  final bool tamil;
  final double? progress;
  final VoidCallback onDownload;
  const _EarOfferCard({
    required this.model,
    required this.tamil,
    required this.progress,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final mb = model.megabytes;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s16),
      child: Glass(
        radius: Gold.r21,
        tint: Ink.violet.withValues(alpha: .06),
        padding: const EdgeInsets.all(Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(CupertinoIcons.ear, size: 22, color: Ink.violetDeep),
                const SizedBox(width: Space.s8),
                Expanded(
                  child: AppText(
                    tamil
                        ? bi(
                            "VIMO's own ear for Tamil",
                            'தமிழுக்கு VIMO-வின் சொந்தக் காது',
                          )
                        : bi("VIMO's own ear", 'VIMO-வின் சொந்தக் காது'),
                    style: TextStyle(
                      fontSize: Gold.t16 + 1,
                      fontWeight: FontWeight.w700,
                      color: Ink.navy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s8),
            AppText(
              bi(
                "This phone's speech service cannot listen here, so VIMO listens itself, on this phone. One download of about $mb MB (Wi-Fi is best); after that it works even without the internet.",
                'இந்த போனின் குரல் சேவை இங்கே கேட்காது; அதனால் VIMO தானே இந்த போனிலேயே கேட்கும். ஒரு முறை மட்டும் சுமார் $mb MB பதிவிறக்கம் (Wi-Fi நல்லது); அதன் பிறகு இணையம் இல்லாமலும் வேலை செய்யும்.',
              ),
              style: TextStyle(fontSize: 14, height: 1.4, color: Ink.body),
            ),
            const SizedBox(height: Space.s12),
            if (p == null)
              LiquidButton(
                label: bi('Download ($mb MB)', 'பதிவிறக்கு ($mb MB)'),
                icon: CupertinoIcons.arrow_down_circle_fill,
                height: Space.target,
                onPressed: onDownload,
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Space.s4),
                child: LinearProgressIndicator(
                  value: p <= 0 ? null : p,
                  minHeight: Space.s8,
                  color: Ink.tint,
                  backgroundColor: Ink.lavender,
                ),
              ),
              const SizedBox(height: Space.s8),
              AppText(
                bi(
                  'Downloading… ${(p * 100).round()}%. Keep this screen open.',
                  'பதிவிறக்குகிறது… ${(p * 100).round()}%. இந்தத் திரையைத் திறந்தே வையுங்கள்.',
                ),
                style: TextStyle(fontSize: 13, color: Ink.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
