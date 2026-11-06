part of 'main.dart';

// =============================================================================
//  Offline voice packs (Settings).
//
//  After a language is chosen, VIMO can download what it needs to listen
//  without the internet: Tamil brings Tamil + English + Tanglish, any other
//  language brings itself + English. Until packs exist the app works as
//  before, with the phone's own online speech service.
// =============================================================================

const _packsWifiOnlyKey = 'packsWifiOnly';

/// "Use VIMO offline voice (beta)": off until the owner turns it on.
const voiceOfflineBetaKey = 'voiceOfflineBeta';

bool voiceOfflineBetaEnabled() =>
    settingValue(voiceOfflineBetaKey, false) == true;

/// The installed offline listening model for [locale] ("ta-IN" → asr-ta),
/// or null when none is installed on this phone.
String? offlineVoiceModelPath(String locale) {
  if (kIsWeb || !Hive.isBoxOpen(languagePackBox)) return null;
  final language = locale.split(RegExp('[-_]')).first;
  final row = asMap(Hive.box(languagePackBox).get('asr-$language'));
  final path = txt(row, 'path');
  return path.isEmpty ? null : path;
}

/// Installed offline voice packs, for the device check and the report.
String installedLanguagePacksSummary() {
  if (!Hive.isBoxOpen(languagePackBox)) return 'none installed';
  final rows = [
    for (final key in Hive.box(languagePackBox).keys)
      if (Hive.box(languagePackBox).get(key) is Map)
        '$key v${asMap(Hive.box(languagePackBox).get(key))['version']}',
  ];
  return rows.isEmpty ? 'none installed' : rows.join(', ');
}

String _megabytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  final mb = bytes / (1024 * 1024);
  return mb < 1 ? '${(bytes / 1024).ceil()} KB' : '${mb.toStringAsFixed(1)} MB';
}

/// Plain names for pack languages.
String packLanguageName(String code) => switch (code) {
  'ta' => bi('Tamil', 'தமிழ்'),
  'ta-Latn' => bi('Tanglish', 'தமிழ் (English எழுத்தில்)'),
  'en' => 'English',
  _ =>
    appLanguages
        .firstWhere((l) => l.code == code, orElse: () => appLanguages.first)
        .native,
};

String packKindName(PackKind kind) => switch (kind) {
  PackKind.asr => bi('Listening', 'கேட்டல்'),
  PackKind.nlu => bi('Understanding', 'புரிதல்'),
  PackKind.tts => bi('Speaking voice', 'பேசும் குரல்'),
  PackKind.strings => bi('App text', 'App உரை'),
  PackKind.lexicon => bi('Words', 'வார்த்தைகள்'),
};

class LanguagePacksScreen extends StatefulWidget {
  const LanguagePacksScreen({super.key, this.manager});

  /// Tests pass their own; the app opens this device's store.
  final LanguagePackManager? manager;

  @override
  State<LanguagePacksScreen> createState() => _LanguagePacksScreenState();
}

class _LanguagePacksScreenState extends State<LanguagePacksScreen> {
  LanguagePackManager? _manager;
  PackManifest? _manifest;
  List<LangPack> _missing = const [];
  String? _error;
  bool _loading = true;
  PackProgress? _progress;
  StreamSubscription<PackProgress>? _install;
  bool _wifiOnly = settingValue(_packsWifiOnlyKey, true) != false;

  String get _code => appLanguage.code;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _manager?.cancel();
    _install?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _manager ??=
          widget.manager ??
          LanguagePackManager(await openPackStore(), kinds: devicePackKinds);
      final m = await _manager!.manifest(refresh: true);
      final missing = await _manager!.missing(_code);
      if (!mounted) return;
      setState(() {
        _manifest = m;
        _missing = missing;
        _loading = false;
      });
    } on PackException catch (e) {
      VoiceDiagnostics.log('packs_error', {
        'step': 'manifest',
        'error': e.message,
      });
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<bool> _onWifi() async {
    try {
      final kinds = await Connectivity().checkConnectivity();
      return kinds.contains(ConnectivityResult.wifi) ||
          kinds.contains(ConnectivityResult.ethernet);
    } catch (_) {
      // When the phone cannot say, do not block the owner.
      return true;
    }
  }

  Future<void> _download() async {
    final manager = _manager;
    if (manager == null || _progress != null) return;
    if (_wifiOnly && !await _onWifi()) {
      if (mounted) {
        snack(
          context,
          bi(
            'Connect to Wi-Fi, or turn off "Wi-Fi only"',
            'Wi-Fi-இல் இணையுங்கள், அல்லது "Wi-Fi மட்டும்" அணையுங்கள்',
          ),
          tone: SnackTone.error,
        );
      }
      return;
    }
    VoiceDiagnostics.log('packs_install_start', {
      'language': _code,
      'packs': [for (final p in _missing) '${p.id}@${p.version}'],
    });
    setState(() {
      _error = null;
      _progress = const PackProgress(0, 1);
    });
    _install = manager
        .install(_code)
        .listen(
          (p) {
            if (mounted) setState(() => _progress = p);
          },
          onError: (Object e) {
            final message = e is PackException ? e.message : '$e';
            VoiceDiagnostics.log('packs_error', {
              'step': 'install',
              'error': message,
            });
            if (mounted) {
              setState(() {
                _progress = null;
                _error = message;
              });
            }
          },
          onDone: () async {
            VoiceDiagnostics.log('packs_installed', {
              'language': _code,
              'installed': installedLanguagePacksSummary(),
            });
            if (!mounted) return;
            setState(() => _progress = null);
            await _load();
          },
          cancelOnError: true,
        );
  }

  void _cancel() {
    _manager?.cancel();
    setState(() => _progress = null);
  }

  Future<void> _delete(String id) async {
    final manager = _manager;
    if (manager == null) return;
    await manager.store.remove(id);
    VoiceDiagnostics.log('packs_removed', {'id': id});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    final needed =
        manifest?.packsFor(_code, kinds: devicePackKinds) ?? const [];
    final total = _missing.fold<int>(0, (s, p) => s + p.sizeBytes);
    final ready = manifest != null && needed.isNotEmpty && _missing.isEmpty;
    final installed = _manager?.store.installed() ?? const <String, int>{};
    final progress = _progress;
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      appBar: AppBar(
        title: AppText(bi('Offline voice packs', 'Offline குரல் packs')),
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
              icon: CupertinoIcons.cloud_download,
              title: bi(
                'Download for offline voice',
                'Offline குரலுக்குப் பதிவிறக்கு',
              ),
              subtitle: manifest == null
                  ? bi(
                      'Voice works online as today until packs are downloaded.',
                      'Packs பதிவிறக்கும் வரை குரல் இன்றைப் போலவே இணையத்துடன் வேலை செய்யும்.',
                    )
                  : '${appLanguage.native}: ${manifest.languagesFor(_code).map(packLanguageName).join(' + ')}',
              children: [
                if (_loading)
                  const Center(child: CupertinoActivityIndicator())
                else if (manifest == null)
                  Text(
                    bi(
                      'No packs are published yet. After the first training run they appear here. ($_error)',
                      'இன்னும் packs வெளியிடப்படவில்லை. முதல் பயிற்சிக்குப் பிறகு இங்கே வரும். ($_error)',
                    ),
                    style: TextStyle(fontSize: 14, color: Ink.body),
                  )
                else if (needed.isEmpty)
                  Text(
                    kIsWeb
                        ? bi(
                            'Offline listening needs the VIMO phone app; a browser listens online.',
                            'Offline கேட்டலுக்கு VIMO phone app தேவை; browser இணையத்துடன் மட்டுமே கேட்கும்.',
                          )
                        : bi(
                            'No packs for this language yet.',
                            'இந்த மொழிக்கு இன்னும் packs இல்லை.',
                          ),
                    style: TextStyle(fontSize: 14, color: Ink.body),
                  )
                else if (ready)
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        color: Ink.greenText,
                      ),
                      const SizedBox(width: Space.s8),
                      Expanded(
                        child: AppText(
                          bi('Ready offline', 'Offline-க்குத் தயார்'),
                          style: TextStyle(
                            fontSize: Gold.t16,
                            fontWeight: FontWeight.w700,
                            color: Ink.greenText,
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  Text(
                    bi(
                      '${_missing.length} packs · ${_megabytes(total)}',
                      '${_missing.length} packs · ${_megabytes(total)}',
                    ),
                    style: TextStyle(
                      fontSize: Gold.t16,
                      fontWeight: FontWeight.w700,
                      color: Ink.navy,
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _wifiOnly,
                      title: AppText(bi('Wi-Fi only', 'Wi-Fi மட்டும்')),
                      onChanged: (v) {
                        setState(() => _wifiOnly = v);
                        unawaited(setSetting(_packsWifiOnlyKey, v));
                      },
                    ),
                  ),
                  if (progress != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Space.s4),
                      child: LinearProgressIndicator(
                        value: progress.fraction,
                        minHeight: Space.s8,
                        color: Ink.tint,
                        backgroundColor: Ink.lavender,
                      ),
                    ),
                    const SizedBox(height: Space.s8),
                    Text(
                      '${(progress.fraction * 100).floor()}% · ${_megabytes(progress.done)} / ${_megabytes(progress.total)}',
                      style: TextStyle(fontSize: 13, color: Ink.muted),
                    ),
                    const SizedBox(height: Space.s8),
                    _SecondaryPill(
                      label: bi('Cancel', 'ரத்து'),
                      icon: CupertinoIcons.xmark,
                      onTap: _cancel,
                    ),
                  ] else ...[
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.s8),
                        child: Text(
                          _error!,
                          style: TextStyle(fontSize: 13, color: Ink.redText),
                        ),
                      ),
                    LiquidButton(
                      label: _error == null
                          ? bi('Download', 'பதிவிறக்கு')
                          : bi('Retry', 'மீண்டும் முயற்சி'),
                      icon: CupertinoIcons.arrow_down_circle,
                      onPressed: _download,
                    ),
                    const SizedBox(height: Space.s8),
                    AppText(
                      bi(
                        'An interrupted download continues where it stopped. If the phone is full, free some space and retry.',
                        'நின்றுபோன பதிவிறக்கம் நின்ற இடத்திலிருந்து தொடரும். போனில் இடம் இல்லையெனில் இடம் விடுவித்து மீண்டும் முயற்சிக்கவும்.',
                      ),
                      style: TextStyle(fontSize: 12, color: Ink.muted),
                    ),
                  ],
                ],
              ],
            ),
            _ReportSection(
              icon: CupertinoIcons.waveform_path,
              title: bi(
                'Use VIMO offline voice (beta)',
                'VIMO offline குரல் (சோதனை)',
              ),
              subtitle: bi(
                'When on and the listening pack is installed, VIMO listens on the phone without the internet. If the offline voice cannot start, VIMO uses the phone\'s speech service as before.',
                'இயக்கி, கேட்டல் pack நிறுவப்பட்டிருந்தால், VIMO இணையம் இல்லாமல் போனிலேயே கேட்கும். Offline குரல் தொடங்காவிட்டால், முன்பு போல போனின் குரல் சேவையைப் பயன்படுத்தும்.',
              ),
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: voiceOfflineBetaEnabled(),
                    title: AppText(bi('Offline voice', 'Offline குரல்')),
                    subtitle: AppText(
                      offlineVoiceModelPath(appLanguage.code) == null
                          ? bi(
                              'Listening pack not installed yet',
                              'கேட்டல் pack இன்னும் நிறுவப்படவில்லை',
                            )
                          : bi(
                              'Listening pack installed',
                              'கேட்டல் pack நிறுவப்பட்டுள்ளது',
                            ),
                    ),
                    onChanged: (v) async {
                      await setSetting(voiceOfflineBetaKey, v);
                      VoiceDiagnostics.log('offline_voice_setting', {'on': v});
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ],
            ),
            _ReportSection(
              icon: CupertinoIcons.square_stack_3d_up,
              title: bi('Manage language packs', 'மொழி packs நிர்வகி'),
              subtitle: bi(
                'English always stays: every language uses it.',
                'English எப்போதும் இருக்கும்: எல்லா மொழிகளும் அதைப் பயன்படுத்தும்.',
              ),
              children: [
                if (installed.isEmpty)
                  AppText(
                    bi(
                      'Nothing installed yet.',
                      'இன்னும் எதுவும் நிறுவப்படவில்லை.',
                    ),
                    style: TextStyle(fontSize: 14, color: Ink.body),
                  ),
                for (final e in installed.entries)
                  _installedRow(e.key, e.value),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _installedRow(String id, int version) {
    final pack = _manifest?.packs
        .where((p) => p.id == id)
        .fold<LangPack?>(
          null,
          (best, p) => best == null || p.version > best.version ? p : best,
        );
    final update = pack != null && pack.version > version;
    final english = pack?.language == 'en' || id.endsWith('-en');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        pack == null
            ? id
            : '${packLanguageName(pack.language)} · ${packKindName(pack.kind)}',
      ),
      subtitle: Text(
        [
          'v$version',
          if (pack != null) _megabytes(pack.sizeBytes),
          if (update) bi('update available', 'புதிய பதிப்பு உள்ளது'),
        ].join(' · '),
      ),
      trailing: english
          ? null
          : IconButton(
              tooltip: bi('Delete', 'நீக்கு'),
              icon: Icon(CupertinoIcons.trash, color: Ink.redText),
              onPressed: () => _delete(id),
            ),
    );
  }
}
