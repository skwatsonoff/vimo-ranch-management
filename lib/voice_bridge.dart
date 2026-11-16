part of 'main.dart';

// =============================================================================
//  VIMO's private Google Drive bridge (tools/voice_bridge/Code.gs, v2).
//
//  * No shared access code: every call carries the signed-in person's
//    Firebase ID token and ranch ID; the bridge verifies the token with
//    Google and checks ranch membership through Firestore rules.
//  * The bridge address is configuration, not a secret. It comes from the
//    build (--dart-define=VIMO_BRIDGE_URL) or is entered once by the owner.
//  * Nothing VIMO learns is kept on the phone: consent, aliases and the
//    provider status live in memory for the session and in Drive.
// =============================================================================

/// Legacy local scope (old Hive lesson keys only).
String _voiceScope() {
  final uid = signedInUid;
  final ranch = ranchId();
  if (uid.isEmpty || ranch.isEmpty) return '';
  return sha256.convert(utf8.encode('$uid/$ranch')).toString();
}

String _voicePrefix(String scope) => scope.isEmpty ? '' : '$scope/lesson/';
String _bridgeKey(String scope) => '$scope/drive-bridge';
const _bridgeUrlSetting = 'voiceBridgeUrl';
const vimoBridgeUrl = String.fromEnvironment('VIMO_BRIDGE_URL');

Uri? _bridgeUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'script.google.com' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !RegExp(r'^/macros/s/[A-Za-z0-9_-]+/exec$').hasMatch(uri.path)) {
    return null;
  }
  return uri;
}

Future<String?> _firebaseIdToken() async {
  try {
    return await FirebaseAuth.instance.currentUser?.getIdToken();
  } catch (_) {
    return null;
  }
}

/// What this session knows from Drive (memory only).
class VoiceDriveState {
  VoiceDriveState._();
  static bool connected = false;
  static bool textConsent = false;
  static bool voiceConsent = false;
  static bool geminiOptIn = false;
  static bool geminiSwitch = false;
  static int aliasVersion = 0;
  static int examplesSent = 0;
  static int examplesSkipped = 0;
  static DateTime? lastSync;
  static String? lastError;

  /// Learned spoken words per registered cow name (from Drive, this
  /// session only).
  static Map<String, List<String>> aliases = const {};

  /// Spoken words used for more than one cow: never resolved silently.
  static Set<String> conflicts = const {};

  static void reset() {
    connected = textConsent = voiceConsent = geminiOptIn = geminiSwitch = false;
    aliasVersion = examplesSent = examplesSkipped = 0;
    lastSync = null;
    lastError = null;
    aliases = const {};
    conflicts = const {};
  }
}

class _VoiceBridge {
  final Uri url;
  const _VoiceBridge(this.url);

  /// Legacy scope for old local rows (training screen).
  String get scope => _voiceScope();

  /// Gemini may be asked: the bridge's switch is on and this person opted in.
  bool get gemini => VoiceDriveState.geminiSwitch && VoiceDriveState.geminiOptIn;

  static _VoiceBridge? get current {
    if (signedInUid.isEmpty || ranchId().isEmpty) return null;
    final url = _bridgeUrl(
      vimoBridgeUrl.isNotEmpty ? vimoBridgeUrl : settingText(_bridgeUrlSetting, ''),
    );
    return url == null ? null : _VoiceBridge(url);
  }

  Future<Map<String, dynamic>> call(
    String op, [
    Map<String, Object?> fields = const {},
  ]) async {
    final ranch = ranchId();
    final uid = signedInUid;
    final token = await _firebaseIdToken();
    if (token == null || ranch.isEmpty) throw StateError('session');
    final result = await http
        .post(
          url,
          // Apps Script redirects ContentService responses. A simple request
          // lets the browser follow the redirect without a preflight request.
          headers: {'Content-Type': 'text/plain;charset=UTF-8'},
          body: jsonEncode({
            ...fields,
            'op': op,
            'idToken': token,
            'ranchId': ranch,
          }),
        )
        .timeout(const Duration(seconds: 18));
    if (result.statusCode != 200) throw StateError('unavailable');
    final payload = asMap(jsonDecode(utf8.decode(result.bodyBytes)));
    // A different person or ranch since the call started: drop the answer.
    if (signedInUid != uid || ranchId() != ranch) throw StateError('session');
    if (payload['error'] != null) throw StateError(txt(payload, 'error', 'error'));
    return payload;
  }

  /// Reads consent, the Gemini switch and the active aliases into memory.
  Future<void> refresh() async {
    final status = await call('status');
    final consent = asMap(status['consent']);
    VoiceDriveState.connected = status['drive'] == true;
    VoiceDriveState.textConsent = consent['text'] == true;
    VoiceDriveState.voiceConsent = consent['voice'] == true;
    VoiceDriveState.geminiOptIn = consent['gemini'] == true;
    VoiceDriveState.geminiSwitch = status['geminiSwitch'] == true;
    final lessons = await call('lessons');
    final byId = {
      for (final animal in animalsBy('cow'))
        if (txt(animal, 'id').isNotEmpty) txt(animal, 'id'): txt(animal, 'name'),
    };
    final aliases = <String, List<String>>{};
    final rows = lessons['aliases'];
    if (rows is List) {
      for (final raw in rows.take(2000)) {
        final row = asMap(raw);
        final name = byId[txt(row, 'cowId')];
        final spoken = txt(row, 'spoken').trim();
        if (name == null || spoken.isEmpty || spoken.length > 40) continue;
        (aliases[name] ??= []).add(spoken);
      }
    }
    final conflicts = <String>{
      for (final raw in (lessons['conflicts'] is List ? lessons['conflicts'] as List : const []))
        txt(asMap(raw), 'spoken').trim().toLowerCase(),
    };
    VoiceDriveState.aliases = aliases;
    VoiceDriveState.conflicts = conflicts;
    VoiceDriveState.aliasVersion = toInt(lessons['version']);
    VoiceDriveState.lastSync = DateTime.now();
    VoiceDriveState.lastError = null;
    _cloudAliases = null;
  }
}

Future<void>? _driveSync;

/// Loads this person's consent and the ranch's learned aliases from Drive
/// into memory. Failure leaves voice and milk saving working.
Future<void> refreshVoiceLessons() async {
  final bridge = _VoiceBridge.current;
  if (bridge == null || _driveSync != null) return;
  final request = bridge.refresh();
  _driveSync = request;
  try {
    await request;
  } catch (error) {
    VoiceDriveState.lastError = '$error'.replaceAll('Bad state: ', '');
    VoiceDiagnostics.log('drive_sync_unavailable', {'error': VoiceDriveState.lastError});
  } finally {
    _driveSync = null;
  }
}

/// Kept for callers of the old local-sync path: now reloads from Drive.
void _queueDriveSync() {}

/// Language tag of a sentence for the learning record.
String _exampleLanguage(String text) {
  final tamil = RegExp(r'[஀-௿]').hasMatch(text);
  final latin = RegExp(r'[A-Za-z]').hasMatch(text);
  return tamil && latin ? 'mixed' : (tamil ? 'ta' : 'en');
}

String _randomEventId() {
  final r = math.Random.secure();
  return [for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

/// After the existing milk write succeeded: one minimal, verified example
/// to Drive, sent from memory while this session is still current. On
/// failure it retries briefly, then is dropped (no device queue).
Future<bool> sendVerifiedMilkExample({
  required String heard,
  required String cowName,
  required String cowSpoken,
  required double litres,
  required String session,
  required bool corrected,
  required String provenance,
  bool Function()? stillCurrent,
}) async {
  final bridge = _VoiceBridge.current;
  if (bridge == null || !VoiceDriveState.textConsent) return false;
  final cow = milkCowByName(cowName);
  final cowId = cow == null ? '' : txt(cow, 'id');
  final text = heard.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cowId.isEmpty || text.isEmpty || text.length > 160 ||
      !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(cowId)) {
    return false;
  }
  // Only plain milk sentences: no contact details, money or long numbers.
  final (request, skip) = buildMilkGeminiRequest(text, const {});
  if (request == null && skip != MilkGeminiSkip.noMilkWords) return false;
  final example = {
    'schema': 'vimo.example.v1',
    'eventId': _randomEventId(),
    'lang': _exampleLanguage(text),
    'text': text,
    'cowId': cowId,
    'cowSpoken': cowSpoken.trim().length > 40 ? cowSpoken.trim().substring(0, 40) : cowSpoken.trim(),
    'litres': litres,
    'session': session,
    'intent': 'milk_record',
    'label': corrected ? 'corrected' : 'confirmed',
    'provenance': provenance,
    'datasetVersion': 1,
  };
  for (var attempt = 0; attempt < 3; attempt++) {
    if (stillCurrent != null && !stillCurrent()) break;
    if (!VoiceDriveState.textConsent) break;
    try {
      await bridge.call('example', {'example': example});
      VoiceDriveState.examplesSent++;
      return true;
    } catch (error) {
      if ('$error'.contains('consent') || '$error'.contains('access')) break;
      await Future<void>.delayed(Duration(seconds: 1 + attempt * 2));
    }
  }
  VoiceDriveState.examplesSkipped++;
  return false;
}

// --- screen ----------------------------------------------------------------------

/// "VIMO Voice": read-only learning status, consents, provider state and
/// the deliberate data actions. No Train button, no uploads to do.
class VoiceBridgeScreen extends StatefulWidget {
  const VoiceBridgeScreen({super.key});

  @override
  State<VoiceBridgeScreen> createState() => _VoiceBridgeScreenState();
}

class _VoiceBridgeScreenState extends State<VoiceBridgeScreen> {
  late final _url = TextEditingController(text: _VoiceBridge.current?.url.toString());
  bool _busy = false;
  List<String> _legacyCaches = const [];
  int _legacyRecordings = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    await refreshVoiceLessons();
    final caches = await legacyEarCaches();
    var recordings = 0;
    try {
      await _openTrainingBoxes();
      recordings = Hive.box(_trainingBox).length;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _legacyCaches = caches;
      _legacyRecordings = recordings;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _bridgeUrl(_url.text);
    if (url == null) {
      snack(context, bi('Enter the VIMO bridge web app URL (ends with /exec)', 'VIMO bridge web app முகவரியை உள்ளிடுங்கள் (/exec என முடியும்)'), tone: SnackTone.error);
      return;
    }
    setState(() => _busy = true);
    try {
      await _VoiceBridge(url).refresh();
      await setSetting(_bridgeUrlSetting, url.toString());
      // The old access code is no longer used: remove it from this phone.
      if (Hive.isBoxOpen(voiceLearningBox)) {
        await Hive.box(voiceLearningBox).delete(_bridgeKey(_voiceScope()));
      }
      if (!mounted) return;
      snack(context, bi('Google Drive connected', 'Google Drive இணைந்தது'), tone: SnackTone.success);
    } catch (error) {
      if (mounted) {
        snack(context, bi(
          'Could not connect. Check the bridge deployment (version 2).',
          'இணைக்க முடியவில்லை. Bridge வெளியீட்டைச் (பதிப்பு 2) சரிபாருங்கள்.',
        ), tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setConsent({bool? text, bool? voice, bool? gemini}) async {
    final bridge = _VoiceBridge.current;
    if (bridge == null) return;
    final nextText = text ?? VoiceDriveState.textConsent;
    setState(() => _busy = true);
    try {
      await bridge.call('consent', {
        'text': nextText,
        'voice': nextText && (voice ?? VoiceDriveState.voiceConsent),
        'gemini': gemini ?? VoiceDriveState.geminiOptIn,
      });
      await bridge.refresh();
    } catch (_) {
      if (mounted) {
        snack(context, bi('Could not save the choice. Try again.', 'தேர்வைச் சேமிக்க முடியவில்லை. மீண்டும் முயலுங்கள்.'), tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteMine() async {
    final bridge = _VoiceBridge.current;
    if (bridge == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(bi('Delete my VIMO learning data?', 'என் VIMO கற்றல் தரவை நீக்கவா?')),
        content: Text(bi(
          'Deletes the examples and voice samples you contributed from Drive, and turns learning off for you. Milk records are not touched.',
          'நீங்கள் கொடுத்த உதாரணங்களும் குரல் மாதிரிகளும் Drive-இலிருந்து நீக்கப்படும்; உங்களுக்குக் கற்றல் நிறுத்தப்படும். பால் பதிவுகள் மாறாது.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(bi('Cancel', 'ரத்து'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(bi('Delete', 'நீக்கு'))),
        ],
      ),
    );
    if (sure != true) return;
    setState(() => _busy = true);
    try {
      await bridge.call('deleteMine');
      await bridge.refresh();
      if (mounted) snack(context, bi('Deleted', 'நீக்கப்பட்டது'), tone: SnackTone.success);
    } catch (_) {
      if (mounted) snack(context, bi('Could not delete. Try again.', 'நீக்க முடியவில்லை. மீண்டும் முயலுங்கள்.'), tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeLegacyModels() async {
    final removed = await removeLegacyEarCaches();
    if (!mounted) return;
    setState(() => _legacyCaches = const []);
    snack(context, bi('Removed $removed old voice model downloads from this phone', 'இந்த போனிலிருந்து பழைய $removed குரல் மாடல் பதிவிறக்கங்கள் நீக்கப்பட்டன'), tone: SnackTone.success);
  }

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bridge = _VoiceBridge.current;
    final s = VoiceDriveState.lastSync;
    final asr = vimoAsrEndpoint() != null;
    return Scaffold(
      appBar: AppBar(
        leading: const _BackButton(),
        title: Text(bi('VIMO Voice', 'VIMO குரல்')),
      ),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(bi('Status', 'நிலை'), style: Theme.of(context).textTheme.titleMedium),
            _fact(bi('Speech recognition', 'குரல் அறிதல்'), asr
                ? bi('VIMO private service', 'VIMO தனிப்பட்ட சேவை')
                : bi('Not set up — use Manual Entry', 'அமைக்கப்படவில்லை — கையால் பதிவு செய்யுங்கள்')),
            _fact('Google Drive', bridge == null
                ? bi('Not connected', 'இணைக்கப்படவில்லை')
                : VoiceDriveState.connected
                    ? bi('Connected', 'இணைந்துள்ளது')
                    : (VoiceDriveState.lastError == null ? '…' : bi('Unavailable', 'கிடைக்கவில்லை'))),
            _fact('Gemini', !VoiceDriveState.geminiSwitch
                ? bi('Off', 'அணைக்கப்பட்டுள்ளது')
                : VoiceDriveState.geminiOptIn
                    ? bi('On for unclear milk sentences', 'தெளிவில்லாத பால் வாக்கியங்களுக்கு இயங்கும்')
                    : bi('Available, not chosen', 'கிடைக்கும், தேர்வு செய்யவில்லை')),
            _fact(bi('Learned cow words', 'கற்ற மாட்டுச் சொற்கள்'),
                '${VoiceDriveState.aliases.values.fold<int>(0, (n, l) => n + l.length)} · v${VoiceDriveState.aliasVersion}'),
            _fact(bi('Examples sent this session', 'இந்த அமர்வில் அனுப்பிய உதாரணங்கள்'),
                '${VoiceDriveState.examplesSent}${VoiceDriveState.examplesSkipped > 0 ? ' (${VoiceDriveState.examplesSkipped} ${bi('skipped', 'தவிர்க்கப்பட்டது')})' : ''}'),
            _fact(bi('Last update', 'கடைசிப் புதுப்பிப்பு'), s == null ? '—' : '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}'),
            _fact(bi('What learning updates', 'கற்றல் எதை மாற்றுகிறது'),
                bi('Cow-name aliases only. No speech model is trained yet.', 'மாட்டுப் பெயர் மாற்றுச் சொற்கள் மட்டும். குரல் மாடல் இன்னும் பயிற்றுவிக்கப்படவில்லை.')),
            const SizedBox(height: 16),
            if (bridge == null || vimoBridgeUrl.isEmpty) ...[
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: fieldStyle(bi('VIMO bridge web app URL', 'VIMO bridge web app முகவரி')),
                enabled: !_busy,
              ),
              const SizedBox(height: 8),
              LiquidButton(label: bi('Connect Google Drive', 'Google Drive இணை'), busy: _busy, onPressed: _connect),
              const SizedBox(height: 16),
            ],
            if (bridge != null) ...[
              SwitchListTile.adaptive(
                title: Text(bi('Learn from my corrections', 'என் திருத்தங்களிலிருந்து கற்றுக்கொள்')),
                subtitle: Text(bi(
                  'After a milk entry is saved, the short sentence, cow and litres go to your private Drive. Never audio, never calls.',
                  'பால் பதிவு சேமித்த பிறகு, சிறிய வாக்கியம், மாடு, லிட்டர் மட்டும் உங்கள் தனிப்பட்ட Drive-க்குச் செல்லும். ஒலி இல்லை, அழைப்புகள் இல்லை.',
                )),
                value: VoiceDriveState.textConsent,
                onChanged: _busy || !VoiceDriveState.connected ? null : (v) => _setConsent(text: v, voice: v ? null : false),
              ),
              SwitchListTile.adaptive(
                title: Text(bi('Also keep short samples of my voice', 'என் குரலின் சிறு மாதிரிகளையும் வைத்துக்கொள்')),
                subtitle: Text(bi(
                  'Off by default. Only your own voice, only sentences you confirmed, at most 15 seconds each. Each family member decides for their own voice.',
                  'இயல்பாக அணைந்திருக்கும். உங்கள் குரல் மட்டும், நீங்கள் உறுதிசெய்த வாக்கியங்கள் மட்டும், ஒவ்வொன்றும் 15 வினாடிக்குள். குடும்பத்தில் ஒவ்வொருவரும் தங்கள் குரலுக்குத் தாமே முடிவு செய்வார்கள்.',
                )),
                value: VoiceDriveState.voiceConsent,
                onChanged: _busy || !VoiceDriveState.textConsent ? null : (v) => _setConsent(voice: v),
              ),
              SwitchListTile.adaptive(
                title: Text(bi('Let Gemini help with unclear milk sentences', 'தெளிவில்லாத பால் வாக்கியங்களுக்கு Gemini உதவட்டும்')),
                subtitle: Text(bi(
                  'Free Tier only. Sends one sentence with cow names replaced by codes (C1, C2). Google may use Free Tier text to improve its products. You confirm every entry.',
                  'இலவச நிலை மட்டும். மாட்டுப் பெயர்கள் குறியீடுகளாக (C1, C2) மாற்றப்பட்ட ஒரு வாக்கியம் மட்டும் அனுப்பப்படும். இலவச உரையை Google தன் சேவைகளை மேம்படுத்தப் பயன்படுத்தலாம். ஒவ்வொரு பதிவையும் நீங்கள் உறுதிசெய்வீர்கள்.',
                )),
                value: VoiceDriveState.geminiOptIn,
                onChanged: _busy || !VoiceDriveState.geminiSwitch ? null : (v) => _setConsent(gemini: v),
              ),
              TextButton(
                onPressed: _busy ? null : _deleteMine,
                child: Text(bi('Delete my learning data', 'என் கற்றல் தரவை நீக்கு')),
              ),
            ],
            if (_legacyRecordings > 0)
              TextButton(
                onPressed: () => push(context, const TrainVimoScreen()),
                child: Text(bi(
                  'Review $_legacyRecordings old recordings on this phone (move to Drive or delete)',
                  'இந்த போனில் உள்ள பழைய $_legacyRecordings பதிவுகளைப் பாருங்கள் (Drive-க்கு நகர்த்து அல்லது நீக்கு)',
                )),
              ),
            if (_legacyCaches.isNotEmpty)
              TextButton(
                onPressed: _removeLegacyModels,
                child: Text(bi('Remove old voice model downloads from this phone', 'இந்த போனில் உள்ள பழைய குரல் மாடல் பதிவிறக்கங்களை நீக்கு')),
              ),
          ],
        ),
      ),
    );
  }
}
