part of 'main.dart';

String _voiceScope() {
  final uid = signedInUid;
  final ranch = ranchId();
  if (uid.isEmpty || ranch.isEmpty) return '';
  return sha256.convert(utf8.encode('$uid/$ranch')).toString();
}

String _voicePrefix(String scope) => scope.isEmpty ? '' : '$scope/lesson/';
String _bridgeKey(String scope) => '$scope/drive-bridge';
final _bridgeCode = RegExp(r'^[a-f0-9]{64}$');

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

class _VoiceBridge {
  final String scope;
  final Uri url;
  final String code;
  final bool gemini;
  const _VoiceBridge(this.scope, this.url, this.code, this.gemini);

  static _VoiceBridge? get current {
    final scope = _voiceScope();
    if (scope.isEmpty || !Hive.isBoxOpen(voiceLearningBox)) return null;
    final config = asMap(Hive.box(voiceLearningBox).get(_bridgeKey(scope)));
    final url = _bridgeUrl(txt(config, 'url'));
    final code = txt(config, 'code');
    if (url == null || !_bridgeCode.hasMatch(code)) return null;
    return _VoiceBridge(scope, url, code, config['gemini'] == true);
  }

  Future<Map<String, dynamic>> call(
    String op, [
    Map<String, Object?> fields = const {},
  ]) async {
    if (scope != _voiceScope()) throw StateError('session');
    final result = await http.post(
      url,
      // Apps Script redirects ContentService responses. A simple request
      // lets the browser follow the redirect without a preflight request.
      headers: {'Content-Type': 'text/plain;charset=UTF-8'},
      body: jsonEncode({...fields, 'op': op, 'scope': scope, 'code': code}),
    ).timeout(const Duration(seconds: 18));
    if (result.statusCode != 200) throw StateError('unavailable');
    final payload = asMap(jsonDecode(utf8.decode(result.bodyBytes)));
    if (payload['error'] != null || scope != _voiceScope()) {
      throw StateError(txt(payload, 'error', 'session'));
    }
    return payload;
  }

  Future<void> sync() async {
    final box = Hive.box(voiceLearningBox);
    final prefix = _voicePrefix(scope);
    final outgoing = [
      for (final key in box.keys.whereType<String>())
        if (key.startsWith(prefix) && asMap(box.get(key))['share'] == true)
          {
            ...asMap(box.get(key)),
            'key': key.substring(prefix.length),
          },
    ];
    final result = await call('sync', {'rows': outgoing});
    final rows = result['rows'];
    if (result['schema'] != 1 || rows is! List || rows.length > 2000) {
      throw StateError('dataset');
    }
    final incoming = <String, Map<String, dynamic>>{};
    for (final raw in rows) {
      final row = asMap(raw);
      final key = txt(row, 'key');
      final kind = txt(row, 'kind');
      if (!const {'text', 'example'}.contains(kind) ||
          !key.startsWith('$kind:') ||
          key.length > 420 ||
          txt(row, 'heard').length > 400 ||
          txt(row, 'meant').length > 400 ||
          row['changed'] is! int ||
          row['deleted'] is! bool) {
        continue;
      }
      final id = '$prefix$key';
      final old = asMap(box.get(id));
      final revision = toInt(row['changed']);
      if (revision < toInt(old['changed']) ||
          (revision == old['changed'] && (old['deleted'] == true || row['deleted'] != true))) {
        continue;
      }
      incoming[id] = {
        ...row,
        'share': true,
        'updatedAt': DateTime.fromMillisecondsSinceEpoch(revision, isUtc: true).toIso8601String(),
      };
    }
    if (incoming.isEmpty) return;
    await box.putAll(incoming);
    _lexicon = null;
  }
}

Timer? _driveSyncTimer;
Future<void>? _driveSync;

Future<void> refreshVoiceLessons() async {
  final bridge = _VoiceBridge.current;
  if (bridge == null) return;
  if (_driveSync != null) return;
  final request = bridge.sync();
  _driveSync = request;
  try {
    await request;
  } catch (_) {
    VoiceDiagnostics.log('drive_sync_unavailable', const {});
  } finally {
    _driveSync = null;
  }
}

void _queueDriveSync() {
  if (_VoiceBridge.current == null) return;
  _driveSyncTimer?.cancel();
  _driveSyncTimer = Timer(const Duration(seconds: 2), () async {
    // A correction made during a sync needs another pass after it completes.
    await _driveSync?.catchError((Object _) {});
    await refreshVoiceLessons();
  });
}

class VoiceBridgeScreen extends StatefulWidget {
  const VoiceBridgeScreen({super.key});

  @override
  State<VoiceBridgeScreen> createState() => _VoiceBridgeScreenState();
}

class _VoiceBridgeScreenState extends State<VoiceBridgeScreen> {
  late final _scope = _voiceScope();
  late final _url = TextEditingController(text: _VoiceBridge.current?.url.toString());
  late final _code = TextEditingController(text: _VoiceBridge.current?.code);
  late bool _gemini = _VoiceBridge.current?.gemini ?? false;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _bridgeUrl(_url.text);
    final code = _code.text.trim();
    if (url == null || !_bridgeCode.hasMatch(code) ||
        _scope.isEmpty || _scope != _voiceScope()) {
      snack(context, bi('Enter your Apps Script URL and access code', 'Apps Script முகவரியையும் அணுகல் குறியீட்டையும் உள்ளிடுங்கள்'), tone: SnackTone.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final bridge = _VoiceBridge(_scope, url, code, _gemini);
      await bridge.sync();
      // Saving a Drive connection must work even if Gemini is unavailable.
      var enabled = false;
      if (_gemini) {
        try {
          enabled = (await bridge.call('checkGemini'))['ok'] == true;
        } catch (_) {}
      }
      if (_scope != _voiceScope()) return;
      await Hive.box(voiceLearningBox).put(_bridgeKey(_scope), {
        'url': url.toString(), 'code': code, 'gemini': enabled,
      });
      if (!mounted) return;
      final needsGeminiSetup = _gemini && !enabled;
      setState(() => _gemini = enabled);
      snack(
        context,
        needsGeminiSetup
            ? bi('Drive synced. Gemini Free Tier could not be verified.', 'Drive ஒத்திசைந்தது. இலவச Gemini-ஐ உறுதிசெய்ய முடியவில்லை.')
            : bi('Google Drive synced', 'Google Drive ஒத்திசைந்தது'),
        tone: needsGeminiSetup ? SnackTone.error : SnackTone.success,
      );
    } catch (_) {
      if (mounted) {
        snack(context, bi('Could not sync. Check the deployment and access code.', 'ஒத்திசைக்க முடியவில்லை. வெளியீட்டையும் அணுகல் குறியீட்டையும் சரிபாருங்கள்.'), tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(bi('Google Drive & Gemini', 'Google Drive & Gemini')),
    ),
    body: Shell(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(bi(
            'Syncs corrected milk commands and confirmed cow names to your private Google Drive.',
            'திருத்திய பால் கட்டளைகளும் உறுதிசெய்த மாட்டுப் பெயர்களும் உங்கள் தனிப்பட்ட Google Drive-க்கு ஒத்திசையும்.',
          )),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: fieldStyle(bi('Apps Script web app URL', 'Apps Script இணைய முகவரி')),
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: fieldStyle(bi('Access code', 'அணுகல் குறியீடு')),
            enabled: !_busy,
          ),
          SwitchListTile.adaptive(
            title: Text(bi('Gemini Free Tier fallback', 'இலவச Gemini உதவி')),
            subtitle: Text(bi(
              'Sends uncertain milk commands and cow names to Google. Google may use Free Tier submissions to improve its products.',
              'தெளிவில்லாத பால் கட்டளைகளும் மாட்டுப் பெயர்களும் Google-க்கு அனுப்பப்படும். இலவசக் கோரிக்கைகளை Google தனது சேவைகளை மேம்படுத்தப் பயன்படுத்தலாம்.',
            )),
            value: _gemini,
            onChanged: _busy ? null : (value) => setState(() => _gemini = value),
          ),
          LiquidButton(label: bi('Connect & sync', 'இணைத்து ஒத்திசை'), busy: _busy, onPressed: _connect),
          if (_VoiceBridge.current != null)
            TextButton(
              onPressed: _busy ? null : () async {
                await Hive.box(voiceLearningBox).delete(_bridgeKey(_scope));
                if (!mounted) return;
                setState(() { _url.clear(); _code.clear(); _gemini = false; });
              },
              child: Text(bi('Disconnect', 'இணைப்பைத் துண்டி')),
            ),
        ],
      ),
    ),
  );
}
