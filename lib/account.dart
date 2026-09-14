part of 'main.dart';

String normalizeUsername(String name) => name.trim().toLowerCase();
bool validUsername(String name) =>
    RegExp(r'^[a-z][a-z0-9_]{2,19}$').hasMatch(name);
String get accountUsername =>
    txt(asMap(settingValue('usernameProfiles', {})), _profileKey);

class UsernameService {
  static Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError(ui('Please sign in again'));
    final data =
        (await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get(const GetOptions(source: Source.server))
                .timeout(CloudSyncService.networkTimeout))
            .data() ??
        {};
    final name = txt(data, 'username');
    if (!validUsername(name)) {
      throw StateError(
        bi(
          'Choose a username before posting.',
          'பதிவு போடுவதற்கு முன் பயனர்பெயரைத் தேர்ந்தெடுக்கவும்.',
        ),
      );
    }
    await setSetting('usernameProfiles', {
      ...asMap(settingValue('usernameProfiles', {})),
      user.uid: name,
    });
  }

  static Future<bool> available(String input) async {
    final name = normalizeUsername(input);
    if (!validUsername(name)) return false;
    if (!firebaseReady) {
      throw StateError(
        bi(
          'Cloud connection is not ready. Reopen the app.',
          'கிளவுட் இணைப்பு தயாராகவில்லை. செயலியை மீண்டும் திறக்கவும்.',
        ),
      );
    }
    final snap = await FirebaseFirestore.instance
        .collection('usernames')
        .doc(name)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));
    return !snap.exists ||
        snap.data()?['uid'] == FirebaseAuth.instance.currentUser?.uid;
  }

  static Future<void> save(String input) async {
    final name = normalizeUsername(input);
    if (!validUsername(name)) {
      throw StateError(
        bi(
          'Use 3–20 letters, numbers or underscores; start with a letter.',
          '3–20 ஆங்கில எழுத்துகள், எண்கள் அல்லது அடிக்கோடு; எழுத்தில் தொடங்கவும்.',
        ),
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError(ui('Please sign in again'));
    await user.getIdToken().timeout(const Duration(seconds: 12));
    final db = FirebaseFirestore.instance;
    final profile = db.collection('users').doc(user.uid);
    final handle = db.collection('usernames').doc(name);
    await db
        .runTransaction((tx) async {
          final p = (await tx.get(profile)).data() ?? {};
          final existing = await tx.get(handle);
          final old = txt(p, 'username');
          if (old == name) {
            if (!existing.exists || existing.data()?['uid'] != user.uid) {
              throw StateError(
                bi(
                  'This username needs account recovery. Your existing data is safe.',
                  'இந்தப் பயனர்பெயருக்கு கணக்கு மீட்பு தேவை. உங்கள் தரவு பாதுகாப்பாக உள்ளது.',
                ),
              );
            }
            tx.set(db.collection('profiles').doc(user.uid), {
              'username': name,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            return;
          }
          if (existing.exists && existing.data()?['uid'] != user.uid) {
            throw StateError(
              bi('Username unavailable', 'இந்தப் பயனர்பெயர் கிடைக்கவில்லை'),
            );
          }
          final changed = p['usernameChangedAt'];
          if (changed is Timestamp &&
              DateTime.now().difference(changed.toDate()).inDays < 30) {
            throw StateError(
              bi(
                'You can change your username once every 30 days.',
                'பயனர்பெயரை 30 நாட்களுக்கு ஒருமுறை மாற்றலாம்.',
              ),
            );
          }
          if (!existing.exists) {
            tx.set(handle, {
              'uid': user.uid,
              'claimedAt': FieldValue.serverTimestamp(),
            });
          }
          tx.set(profile, {
            'username': name,
            'usernameChangedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          tx.set(db.collection('profiles').doc(user.uid), {
            'username': name,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          if (old.isNotEmpty) tx.delete(db.collection('usernames').doc(old));
        })
        .timeout(const Duration(seconds: 20));
    await setSetting('usernameProfiles', {
      ...asMap(settingValue('usernameProfiles', {})),
      user.uid: name,
    });
  }
}

class UsernameField extends StatefulWidget {
  final TextEditingController controller;
  const UsernameField({super.key, required this.controller});
  @override
  State<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends State<UsernameField> {
  Timer? _timer;
  String? _status;
  bool? _available;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check(widget.controller.text);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _check(String input) {
    _timer?.cancel();
    final revision = ++_revision;
    final name = normalizeUsername(input);
    setState(() {
      _available = null;
      _status = null;
    });
    if (name.isEmpty) return;
    if (!validUsername(name)) {
      setState(
        () => _status = bi(
          '3–20 characters: a–z, 0–9, _. Start with a letter.',
          '3–20 குறிகள்: a–z, 0–9, _. எழுத்தில் தொடங்கவும்.',
        ),
      );
      return;
    }
    setState(() => _status = bi('Checking…', 'சரிபார்க்கிறது…'));
    _timer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final available = await UsernameService.available(name);
        if (!mounted || revision != _revision) return;
        setState(() {
          _available = available;
          _status = available
              ? bi('Username available', 'பயனர்பெயர் கிடைக்கிறது')
              : bi('Username unavailable', 'பயனர்பெயர் கிடைக்கவில்லை');
        });
      } catch (error) {
        if (mounted && revision == _revision) {
          setState(() => _status = accountError(error));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: widget.controller,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
        onChanged: _check,
        decoration: fieldStyle(
          bi('Username', 'பயனர்பெயர்'),
          icon: CupertinoIcons.at,
        ),
      ),
      if (_status != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _status!,
            style: TextStyle(
              color: _available == false ? Ink.red : Ink.muted,
              fontSize: 13,
            ),
          ),
        ),
    ],
  );
}

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});
  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _name = TextEditingController(text: accountUsername);
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: bi('Username', 'பயனர்பெயர்'),
    children: [
      UsernameField(controller: _name),
      const SizedBox(height: 24),
      LiquidButton(
        label: 'Save',
        busy: _busy,
        onPressed: () async {
          if (_busy) return;
          setState(() => _busy = true);
          try {
            await UsernameService.save(_name.text);
            if (context.mounted) Navigator.pop(context);
          } catch (e) {
            if (context.mounted) {
              snack(context, accountError(e));
            }
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
    ],
  );
}
