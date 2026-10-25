part of 'main.dart';

/// The VIMO Team: people can report a problem with someone they bought
/// from, sold to or chatted with. A report opens that one conversation and
/// the orders between the two to the team (nothing else), the team talks to
/// both through a private support thread, and only the team acts: warn,
/// pause Market for an account, end an order, take a listing down, resolve.
/// Team members are added from the Firebase console (vimo_admins/{uid}).
const vimoReportReasons = <ShopChoice>[
  ('not_received', 'Item not received', 'பொருள் வரவில்லை'),
  ('not_as_described', 'Not as described', 'சொன்னபடி இல்லை'),
  ('payment', 'Payment problem', 'பணப் பிரச்சனை'),
  ('cancel', 'Cannot agree on cancelling', 'ரத்தில் ஒப்பந்தம் இல்லை'),
  ('abuse', 'Rude or abusive', 'தவறான பேச்சு'),
  ('fraud', 'Fraud or scam', 'மோசடி'),
  ('other', 'Something else', 'வேறு'),
];

const vimoReportStatuses = <ShopChoice>[
  ('open', 'Sent', 'அனுப்பப்பட்டது'),
  ('reviewing', 'Being looked at', 'பார்க்கப்படுகிறது'),
  ('resolved', 'Resolved', 'தீர்ந்தது'),
];

class VimoTeam {
  const VimoTeam._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get reports =>
      _db.collection('vimo_reports');
  static DocumentReference<Map<String, dynamic>> support(String uid) =>
      _db.collection('vimo_support').doc(uid);
  static DocumentReference<Map<String, dynamic>> sanction(String uid) =>
      _db.collection('vimo_sanctions').doc(uid);

  static String? _memberUid;
  static bool _member = false;

  /// Whether this account is on the VIMO Team (checked once per account).
  static Future<bool> isMember() async {
    final uid = signedInUid;
    if (uid.isEmpty) return false;
    if (_memberUid == uid) return _member;
    try {
      _member = (await _db.collection('vimo_admins').doc(uid).get()).exists;
    } catch (_) {
      _member = false;
    }
    _memberUid = uid;
    return _member;
  }

  /// Sends a report. It also opens the conversation and the orders between
  /// the two people to the team, in the same step.
  static Future<String> report({
    required String againstUid,
    required String againstName,
    required String topic,
    required String reason,
    required String text,
    String orderId = '',
  }) async {
    final me = signedInUid;
    final chatId = DirectChatService.idFor(me, againstUid);
    var chat = false;
    try {
      chat = (await _db.collection('direct_chats').doc(chatId).get()).exists;
    } catch (_) {}
    final orders = <String>{if (orderId.isNotEmpty) orderId};
    final shop = _db.collection('shop_orders');
    for (final q in [
      shop
          .where('buyerUid', isEqualTo: me)
          .where('sellerUid', isEqualTo: againstUid),
      shop
          .where('sellerUid', isEqualTo: me)
          .where('buyerUid', isEqualTo: againstUid),
    ]) {
      try {
        for (final d in (await q.limit(10).get()).docs) {
          orders.add(d.id);
        }
      } catch (_) {}
    }
    final ref = reports.doc();
    final batch = _db.batch();
    batch.set(ref, {
      'reporterUid': me,
      'reporterName': await MarketService.myName(),
      'againstUid': againstUid,
      'againstName': againstName.length > 80
          ? againstName.substring(0, 80)
          : againstName,
      'topic': topic,
      'reason': reason,
      'text': text.trim(),
      'orderId': orderId,
      'chatId': chat ? chatId : '',
      'orderIds': orders.take(20).toList(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final open = {'reportId': ref.id, 'at': FieldValue.serverTimestamp()};
    if (chat) {
      batch.set(_db.collection('vimo_reported_chats').doc(chatId), open);
    }
    for (final id in orders.take(20)) {
      batch.set(_db.collection('vimo_reported_orders').doc(id), open);
    }
    await batch.commit();
    return ref.id;
  }

  /// The person's own reports, newest first.
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  myReports() => reports
      .where('reporterUid', isEqualTo: signedInUid)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.toList()..sort(_newest));

  static int _newest(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final x = a.data()['createdAt'], y = b.data()['createdAt'];
    if (x is! Timestamp || y is! Timestamp) return x is Timestamp ? 1 : -1;
    return y.compareTo(x);
  }

  static Query<Map<String, dynamic>> messagesOf(String uid) =>
      support(uid).collection('messages').orderBy('createdAt').limitToLast(200);

  /// A message in someone's thread with the team, from them or the team.
  static Future<void> send(
    String uid,
    String text, {
    required String name,
    bool asTeam = false,
    String reportId = '',
  }) async {
    final clean = text.trim();
    final batch = _db.batch();
    batch.set(support(uid).collection('messages').doc(), {
      'from': asTeam ? 'team' : 'user',
      'senderUid': signedInUid,
      'text': clean,
      'reportId': reportId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(support(uid), {
      'name': name.length > 80 ? name.substring(0, 80) : name,
      'lastText': clean,
      'lastFrom': asTeam ? 'team' : 'user',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Market is paused for this account by the team: the reason, else null.
  static Future<String?> marketPaused() async {
    if (signedInUid.isEmpty) return null;
    try {
      final d = (await sanction(signedInUid).get()).data() ?? const {};
      return txt(d, 'market') == 'blocked' ? txt(d, 'reason') : null;
    } catch (_) {
      return null;
    }
  }

  /// Before buying or selling: false (with a note) when the team paused it.
  static Future<bool> marketAllowed(BuildContext context) async {
    final reason = await marketPaused();
    if (reason == null) return true;
    if (context.mounted) {
      snack(
        context,
        bi(
          'VIMO Team has paused Market for your account. Open Settings → Help to talk to them.',
          'VIMO Team உங்கள் கணக்கிற்கு சந்தையை நிறுத்தியுள்ளது. பேச Settings → உதவி திறக்கவும்.',
        ),
        tone: SnackTone.error,
      );
    }
    return false;
  }

  // ---- Team only ----

  static Future<void> setStatus(String id, String status, {String? outcome}) =>
      reports.doc(id).update({
        'status': status,
        'outcome': ?outcome,
        'handledBy': signedInUid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> setSanction(
    String uid, {
    required bool blocked,
    required int warnings,
    required String reason,
  }) => sanction(uid).set({
    'market': blocked ? 'blocked' : 'ok',
    'warnings': warnings,
    'reason': reason.trim(),
    'by': signedInUid,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  static Future<void> endOrder(String id, String reason) =>
      _db.collection('shop_orders').doc(id).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': 'vimo',
        'cancelReason': reason.trim(),
        'cancelRequest': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> takeDown(String productId) => _db
      .collection('shop_products')
      .doc(productId)
      .update({'status': 'paused', 'updatedAt': FieldValue.serverTimestamp()});
}

String _vimoWhen(dynamic stamp) {
  if (stamp is! Timestamp) return '';
  final t = stamp.toDate().toLocal();
  return '${t.day}/${t.month}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

Widget _statusChip(String status) {
  final color = switch (status) {
    'resolved' => Ink.greenText,
    'reviewing' => Ink.orange,
    _ => Ink.violetDeep,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      shopLabel(vimoReportStatuses, status),
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );
}

/// A button that opens [ReportProblemScreen], used on orders, chats and
/// profiles.
Future<void> openReport(
  BuildContext context, {
  required String againstUid,
  required String againstName,
  required String topic,
  String orderId = '',
}) => push(
  context,
  ReportProblemScreen(
    againstUid: againstUid,
    againstName: againstName,
    topic: topic,
    orderId: orderId,
  ),
);

class ReportProblemScreen extends StatefulWidget {
  final String againstUid, againstName, topic, orderId;
  const ReportProblemScreen({
    super.key,
    required this.againstUid,
    required this.againstName,
    required this.topic,
    this.orderId = '',
  });

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final _text = TextEditingController();
  String _reason = '';
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    String? problem;
    if (_reason.isEmpty) {
      problem = bi(
        'Choose what happened',
        'என்ன நடந்தது என்று தேர்வுசெய்யவும்',
      );
    } else if (_text.text.trim().length < 10) {
      problem = bi(
        'Tell the team a little more (at least 10 letters)',
        'இன்னும் கொஞ்சம் சொல்லுங்கள் (குறைந்தது 10 எழுத்துகள்)',
      );
    }
    if (problem != null) {
      snack(context, problem, tone: SnackTone.error);
      return;
    }
    setState(() => _busy = true);
    try {
      await VimoTeam.report(
        againstUid: widget.againstUid,
        againstName: widget.againstName,
        topic: widget.topic,
        reason: _reason,
        text: _text.text,
        orderId: widget.orderId,
      );
      UiSound.play(UiSoundKind.success);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) snack(context, accountError(e), tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(bi('Report a problem', 'பிரச்சனையைத் தெரிவி')),
    ),
    body: Shell(
      child: _sent
          ? StatePanel(
              icon: CupertinoIcons.checkmark_shield_fill,
              accent: Ink.greenText,
              title: bi('Sent to VIMO Team', 'VIMO Team-க்கு அனுப்பப்பட்டது'),
              message: bi(
                'The team will look at what happened and message you in Settings → Help. Only the team takes action.',
                'நடந்ததைக் குழு பார்த்து Settings → உதவி-யில் உங்களுக்குச் செய்தி அனுப்பும். நடவடிக்கை குழு மட்டுமே எடுக்கும்.',
              ),
              actionLabel: bi('Open Help', 'உதவியைத் திற'),
              actionIcon: CupertinoIcons.chat_bubble_2_fill,
              onAction: () => Navigator.pushReplacement(
                context,
                LiquidRoute(builder: (_) => const VimoHelpScreen()),
              ),
            )
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(
                  bi(
                    'About ${widget.againstName}',
                    '${widget.againstName} பற்றி',
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _shopSection(bi('What happened?', 'என்ன நடந்தது?')),
                Glass(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        for (final r in vimoReportReasons)
                          Semantics(
                            selected: _reason == r.$1,
                            child: ListTile(
                              title: Text(bi(r.$2, r.$3)),
                              trailing: _reason == r.$1
                                  ? Icon(
                                      CupertinoIcons.checkmark_alt,
                                      color: Ink.violetDeep,
                                    )
                                  : null,
                              onTap: () {
                                selectionFeedback();
                                setState(() => _reason = r.$1);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _shopSection(bi('Tell us more', 'விவரமாகச் சொல்லுங்கள்')),
                TextField(
                  controller: _text,
                  maxLength: 1000,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: fieldStyle(
                    bi(
                      'When, what was agreed, what went wrong',
                      'எப்போது, என்ன பேசினீர்கள், என்ன தவறு',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Glass(
                  radius: 20,
                  tint: Ink.lavender.withValues(alpha: .5),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        CupertinoIcons.lock_shield_fill,
                        color: Ink.violetDeep,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          bi(
                            'Only the VIMO Team sees this report. To check it, the team can read your chat and your orders with ${widget.againstName} — nothing else. ${widget.againstName} is not told who reported.',
                            'இந்த அறிக்கையை VIMO Team மட்டுமே பார்க்கும். சரிபார்க்க, ${widget.againstName}-உடனான உங்கள் chat, ஆர்டர்களை மட்டும் குழு படிக்கலாம் — வேறு எதுவும் இல்லை. யார் தெரிவித்தார் என்று ${widget.againstName}-க்குச் சொல்லப்படாது.',
                          ),
                          style: TextStyle(color: Ink.body, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                LiquidButton(
                  label: bi('Send to VIMO Team', 'VIMO Team-க்கு அனுப்பு'),
                  icon: CupertinoIcons.paperplane_fill,
                  busy: _busy,
                  onPressed: _busy ? null : _send,
                ),
              ],
            ),
    ),
  );
}

/// Settings → Help: a thread with the VIMO Team and the person's reports.
class VimoHelpScreen extends StatelessWidget {
  const VimoHelpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(bi('Help · VIMO Team', 'உதவி · VIMO Team')),
    ),
    body: Shell(
      child: signedInUid.isEmpty
          ? SignInStatePanel(
              message: bi(
                'Sign in to talk to the VIMO Team.',
                'VIMO Team-உடன் பேச உள்நுழையவும்.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: VimoTeam.sanction(signedInUid).snapshots(),
                  builder: (context, snap) {
                    final d = snap.data?.data() ?? const {};
                    if (txt(d, 'market') != 'blocked') {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Glass(
                        radius: 20,
                        tint: Ink.red.withValues(alpha: .10),
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          [
                            bi(
                              'Market is paused for your account.',
                              'உங்கள் கணக்கிற்குச் சந்தை நிறுத்தப்பட்டுள்ளது.',
                            ),
                            if (txt(d, 'reason').isNotEmpty) txt(d, 'reason'),
                          ].join('\n'),
                          style: TextStyle(
                            color: Ink.redText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Glass(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  onTap: () async {
                    final name = await MarketService.myName();
                    if (!context.mounted) return;
                    await push(
                      context,
                      SupportThreadScreen(uid: signedInUid, name: name),
                    );
                  },
                  child: Row(
                    children: [
                      const BrandMark(size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child:
                            StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              stream: VimoTeam.support(signedInUid).snapshots(),
                              builder: (context, snap) {
                                final d = snap.data?.data() ?? const {};
                                return Text(
                                  [
                                    bi(
                                      'Message VIMO Team',
                                      'VIMO Team-க்குச் செய்தி',
                                    ),
                                    txt(d, 'lastText').isEmpty
                                        ? bi(
                                            'Questions, problems, ideas',
                                            'கேள்வி, பிரச்சனை, யோசனை',
                                          )
                                        : txt(d, 'lastText'),
                                  ].join('\n'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                            ),
                      ),
                      Icon(CupertinoIcons.chevron_right, color: Ink.faint),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // The account ID, for adding someone to the VIMO Team in
                // the Firebase console (vimo_admins/<this ID>).
                Glass(
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bi('Your account ID', 'உங்கள் கணக்கு ID'),
                              style: TextStyle(color: Ink.muted, fontSize: 13),
                            ),
                            SelectableText(
                              signedInUid,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: bi('Copy', 'நகலெடு'),
                        icon: Icon(
                          CupertinoIcons.doc_on_doc,
                          color: Ink.violetDeep,
                        ),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: signedInUid),
                          );
                          if (context.mounted) {
                            snack(
                              context,
                              bi(
                                'Account ID copied',
                                'கணக்கு ID நகலெடுக்கப்பட்டது',
                              ),
                              tone: SnackTone.success,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                _shopSection(
                  bi('My reports', 'என் அறிக்கைகள்'),
                  note: bi(
                    'Report a person from their profile, your chat or an order.',
                    'ஒருவரை அவர் ப்ரொஃபைல், chat அல்லது ஆர்டரில் இருந்து தெரிவிக்கலாம்.',
                  ),
                ),
                StreamBuilder<
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>
                >(
                  stream: VimoTeam.myReports(),
                  builder: (context, snap) {
                    final docs = snap.data;
                    if (docs == null) {
                      return snap.hasError
                          ? Text(accountError(snap.error!))
                          : const SkeletonList(
                              rows: 2,
                              padding: EdgeInsets.zero,
                            );
                    }
                    if (docs.isEmpty) {
                      return Text(
                        bi('No reports.', 'அறிக்கைகள் இல்லை.'),
                        style: TextStyle(color: Ink.muted),
                      );
                    }
                    return Column(
                      children: [
                        for (final doc in docs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Glass(
                              radius: 18,
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${shopLabel(vimoReportReasons, txt(doc.data(), 'reason'))} · ${txt(doc.data(), 'againstName')}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      _statusChip(txt(doc.data(), 'status')),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    txt(doc.data(), 'outcome').isNotEmpty
                                        ? txt(doc.data(), 'outcome')
                                        : _vimoWhen(doc.data()['createdAt']),
                                    style: TextStyle(color: Ink.muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
    ),
  );
}

/// A person's private thread with the VIMO Team. The team sees every
/// thread; the person sees only their own.
class SupportThreadScreen extends StatefulWidget {
  final String uid, name;
  final bool asTeam;
  final String reportId;
  const SupportThreadScreen({
    super.key,
    required this.uid,
    required this.name,
    this.asTeam = false,
    this.reportId = '',
  });

  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.asTeam) SocialActivityService.openChatId = 'vimo-support';
  }

  @override
  void dispose() {
    if (SocialActivityService.openChatId == 'vimo-support') {
      SocialActivityService.openChatId = '';
    }
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (_busy || text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await VimoTeam.send(
        widget.uid,
        text,
        name: widget.name,
        asTeam: widget.asTeam,
        reportId: widget.reportId,
      );
      _text.clear();
    } catch (e) {
      if (mounted) snack(context, accountError(e), tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.surface,
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(widget.asTeam ? widget.name : 'VIMO Team'),
    ),
    body: Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: VimoTeam.messagesOf(widget.uid).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text(accountError(snap.error!)));
              }
              if (!snap.hasData) return const SkeletonList();
              final docs = snap.data!.docs.reversed.toList();
              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      widget.asTeam
                          ? bi('No messages yet.', 'இன்னும் செய்திகள் இல்லை.')
                          : bi(
                              'Write to the VIMO Team. A real person answers.',
                              'VIMO Team-க்கு எழுதுங்கள். ஒருவர் பதில் சொல்வார்.',
                            ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Ink.muted),
                    ),
                  ),
                );
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final m = docs[i].data();
                  final fromTeam = txt(m, 'from') == 'team';
                  final mine = fromTeam == widget.asTeam;
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: mine ? Ink.violetDeep : Ink.lavender,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (fromTeam && !widget.asTeam)
                            Text(
                              'VIMO Team',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Ink.violetDeep,
                              ),
                            ),
                          Text(
                            txt(m, 'text'),
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.3,
                              color: mine ? Colors.white : Ink.navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _vimoWhen(m['createdAt']),
                            style: TextStyle(
                              fontSize: 11,
                              color: mine ? Colors.white70 : Ink.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _text,
              maxLength: 2000,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: fieldStyle(
                bi('Write a message', 'செய்தி எழுது'),
                suffix: IconButton(
                  tooltip: bi('Send', 'அனுப்பு'),
                  onPressed: _busy ? null : _send,
                  icon: Icon(
                    CupertinoIcons.arrow_up_circle_fill,
                    color: Ink.violetDeep,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The team's console: reports by state, and every support thread.
class VimoTeamConsole extends StatefulWidget {
  const VimoTeamConsole({super.key});

  @override
  State<VimoTeamConsole> createState() => _VimoTeamConsoleState();
}

class _VimoTeamConsoleState extends State<VimoTeamConsole> {
  int _view = 0;

  Widget _reports() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: VimoTeam.reports
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Text(accountError(snap.error!));
      if (!snap.hasData) {
        return const SkeletonList(rows: 4, padding: EdgeInsets.zero);
      }
      final want = vimoReportStatuses[_view].$1;
      final docs = snap.data!.docs
          .where((d) => txt(d.data(), 'status') == want)
          .toList();
      if (docs.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text(
            bi('Nothing here.', 'இங்கு எதுவும் இல்லை.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Ink.muted),
          ),
        );
      }
      return Column(
        children: [
          for (final d in docs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Glass(
                radius: 18,
                padding: const EdgeInsets.all(14),
                onTap: () => push(context, ReportCaseScreen(id: d.id)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          shopLabel(vimoReportReasons, txt(d.data(), 'reason')),
                          '${txt(d.data(), 'reporterName')} → ${txt(d.data(), 'againstName')}',
                          _vimoWhen(d.data()['createdAt']),
                        ].join('\n'),
                        style: const TextStyle(height: 1.35),
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_right, color: Ink.faint),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _threads() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('vimo_support')
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Text(accountError(snap.error!));
      if (!snap.hasData) {
        return const SkeletonList(rows: 4, padding: EdgeInsets.zero);
      }
      return Column(
        children: [
          for (final d in snap.data!.docs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Glass(
                radius: 18,
                padding: const EdgeInsets.all(14),
                onTap: () => push(
                  context,
                  SupportThreadScreen(
                    uid: d.id,
                    name: txt(d.data(), 'name', d.id),
                    asTeam: true,
                  ),
                ),
                child: Row(
                  children: [
                    if (txt(d.data(), 'lastFrom') == 'user')
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Icon(
                          CupertinoIcons.circle_fill,
                          size: 10,
                          color: Ink.violetDeep,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        '${txt(d.data(), 'name', d.id)}\n${txt(d.data(), 'lastText')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_right, color: Ink.faint),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      leading: const _BackButton(),
      title: const Text('VIMO Team'),
    ),
    body: Shell(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          LiquidSegmentBar(
            labels: [
              for (final s in vimoReportStatuses) bi(s.$2, s.$3),
              bi('Messages', 'செய்திகள்'),
            ],
            index: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          const SizedBox(height: 16),
          if (_view < vimoReportStatuses.length) _reports() else _threads(),
        ],
      ),
    ),
  );
}

/// One report, everything the team needs from A to Z: what was said, the
/// conversation, the orders and their messages, both people, and actions.
class ReportCaseScreen extends StatefulWidget {
  final String id;
  const ReportCaseScreen({super.key, required this.id});

  @override
  State<ReportCaseScreen> createState() => _ReportCaseScreenState();
}

class _ReportCaseScreenState extends State<ReportCaseScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) snack(context, done, tone: SnackTone.success);
    } catch (e) {
      if (mounted) snack(context, accountError(e), tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _write(String title, String label) async {
    final c = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 500,
          maxLines: 4,
          minLines: 2,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ui('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(bi('Done', 'சரி')),
          ),
        ],
      ),
    );
    c.dispose();
    return result == null || result.isEmpty ? null : result;
  }

  Widget _person(
    Map<String, dynamic> r, {
    required String uid,
    required String name,
    required String role,
  }) => Glass(
    radius: 20,
    padding: const EdgeInsets.all(14),
    child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: VimoTeam.sanction(uid).snapshots(),
      builder: (context, snap) {
        final s = snap.data?.data() ?? const <String, dynamic>{};
        final blocked = txt(s, 'market') == 'blocked';
        final warnings = toInt(s['warnings']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$name · $role${warnings > 0 ? ' · ${bi('$warnings warnings', '$warnings எச்சரிக்கைகள்')}' : ''}${blocked ? ' · ${bi('Market paused', 'சந்தை நிறுத்தம்')}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: bi('Open profile', 'ப்ரொஃபைலைத் திற'),
                  onPressed: () => push(context, SocialProfileScreen(uid: uid)),
                  icon: Icon(
                    CupertinoIcons.person_crop_circle,
                    color: Ink.violetDeep,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  style: liquidActionStyle(),
                  onPressed: () => push(
                    context,
                    SupportThreadScreen(
                      uid: uid,
                      name: name,
                      asTeam: true,
                      reportId: widget.id,
                    ),
                  ),
                  icon: const Icon(CupertinoIcons.chat_bubble_2, size: 18),
                  label: Text(bi('Message', 'செய்தி')),
                ),
                TextButton.icon(
                  style: liquidActionStyle(),
                  onPressed: _busy
                      ? null
                      : () async {
                          final why = await _write(
                            bi('Warn $name', '$name-ஐ எச்சரி'),
                            bi('What they must stop', 'அவர் நிறுத்த வேண்டியது'),
                          );
                          if (why == null) return;
                          await _run(() async {
                            await VimoTeam.setSanction(
                              uid,
                              blocked: blocked,
                              warnings: warnings + 1,
                              reason: why,
                            );
                            await VimoTeam.send(
                              uid,
                              bi(
                                'Warning from VIMO Team: $why',
                                'VIMO Team எச்சரிக்கை: $why',
                              ),
                              name: name,
                              asTeam: true,
                              reportId: widget.id,
                            );
                          }, bi('Warning sent', 'எச்சரிக்கை அனுப்பப்பட்டது'));
                        },
                  icon: const Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: 18,
                  ),
                  label: Text(bi('Warn', 'எச்சரி')),
                ),
                TextButton.icon(
                  style: liquidActionStyle(),
                  onPressed: _busy
                      ? null
                      : () async {
                          final why = blocked
                              ? ''
                              : await _write(
                                  bi(
                                    'Pause Market for $name?',
                                    '$name-க்குச் சந்தையை நிறுத்தவா?',
                                  ),
                                  bi(
                                    'Reason they will see',
                                    'அவர் பார்க்கும் காரணம்',
                                  ),
                                );
                          if (why == null) return;
                          await _run(
                            () async {
                              await VimoTeam.setSanction(
                                uid,
                                blocked: !blocked,
                                warnings: warnings,
                                reason: why,
                              );
                              await VimoTeam.send(
                                uid,
                                blocked
                                    ? bi(
                                        'VIMO Team opened Market for you again.',
                                        'VIMO Team உங்களுக்குச் சந்தையை மீண்டும் திறந்தது.',
                                      )
                                    : bi(
                                        'VIMO Team paused Market for your account: $why',
                                        'VIMO Team உங்கள் கணக்கிற்குச் சந்தையை நிறுத்தியது: $why',
                                      ),
                                name: name,
                                asTeam: true,
                                reportId: widget.id,
                              );
                            },
                            blocked
                                ? bi('Market opened', 'சந்தை திறக்கப்பட்டது')
                                : bi('Market paused', 'சந்தை நிறுத்தப்பட்டது'),
                          );
                        },
                  icon: Icon(
                    blocked ? CupertinoIcons.lock_open : CupertinoIcons.lock,
                    size: 18,
                    color: blocked ? null : Ink.redText,
                  ),
                  label: Text(
                    blocked
                        ? bi('Open Market', 'சந்தையைத் திற')
                        : bi('Pause Market', 'சந்தையை நிறுத்து'),
                    style: TextStyle(color: blocked ? null : Ink.redText),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

  Widget _chat(Map<String, dynamic> r) {
    final chatId = txt(r, 'chatId');
    if (chatId.isEmpty) {
      return Text(
        bi('They have not chatted.', 'அவர்கள் chat செய்யவில்லை.'),
        style: TextStyle(color: Ink.muted),
      );
    }
    final names = {
      txt(r, 'reporterUid'): txt(r, 'reporterName'),
      txt(r, 'againstUid'): txt(r, 'againstName'),
    };
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('direct_chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('createdAt')
          .limitToLast(300)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text(accountError(snap.error!));
        if (!snap.hasData) {
          return const SkeletonList(rows: 3, padding: EdgeInsets.zero);
        }
        return _transcript([
          for (final d in snap.data!.docs)
            (
              names[txt(d.data(), 'senderUid')] ?? '?',
              txt(d.data(), 'text'),
              d.data()['createdAt'],
            ),
        ]);
      },
    );
  }

  Widget _transcript(List<(String, String, dynamic)> lines) => Glass(
    radius: 18,
    padding: const EdgeInsets.all(14),
    child: lines.isEmpty
        ? Text(bi('No messages.', 'செய்திகள் இல்லை.'))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SelectableText.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${l.$1}  ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: _vimoWhen(l.$3),
                          style: TextStyle(color: Ink.muted, fontSize: 12),
                        ),
                        TextSpan(text: '\n${l.$2}'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );

  Widget _order(
    String id,
    Map<String, dynamic> r,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('shop_orders')
        .doc(id)
        .snapshots(),
    builder: (context, snap) {
      final o = snap.data?.data();
      if (o == null) {
        return snap.hasError
            ? Text(accountError(snap.error!))
            : const SkeletonList(rows: 1, padding: EdgeInsets.zero);
      }
      final status = txt(o, 'status');
      final done = const {'completed', 'cancelled'}.contains(status);
      final names = {
        txt(o, 'buyerUid'): txt(o, 'buyerName'),
        txt(o, 'sellerUid'): txt(o, 'sellerName'),
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Glass(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${txt(o, 'title')} × ${toInt(o['quantity'])} · ${money(numv(o, 'total'))}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  '${bi('Buyer', 'வாங்குபவர்')}: ${txt(o, 'buyerName')} · ${bi('Seller', 'விற்பவர்')}: ${txt(o, 'sellerName')}',
                  '${bi('Status', 'நிலை')}: ${shopOrderStatusLabel(status)}',
                  '${bi('Payment', 'பணம்')}: ${shopLabel(shopPayments, txt(o, 'payment'))}${txt(o, 'sellerUpi').isNotEmpty ? ' · ${txt(o, 'sellerUpi')}' : ''}',
                  for (final step in const [
                    ('createdAt', 'Ordered', 'ஆர்டர்'),
                    ('acceptedAt', 'Accepted', 'ஏற்பு'),
                    ('shippedAt', 'Sent', 'அனுப்பியது'),
                    ('receivedAt', 'Received', 'பெற்றது'),
                    ('completedAt', 'Completed', 'முடிந்தது'),
                    ('cancelledAt', 'Cancelled', 'ரத்து'),
                  ])
                    if (o[step.$1] is Timestamp)
                      '${bi(step.$2, step.$3)}: ${_vimoWhen(o[step.$1])}',
                  if (txt(o, 'tracking').isNotEmpty)
                    '${bi('Tracking', 'டிராக்கிங்')}: ${txt(o, 'tracking')}',
                  if (txt(o, 'cancelReason').isNotEmpty)
                    '${bi('Cancel reason', 'ரத்துக் காரணம்')}: ${txt(o, 'cancelReason')}',
                  if (asMap(o['cancelRequest']).isNotEmpty)
                    '${bi('Open cancel request', 'திறந்த ரத்துக் கோரிக்கை')}: ${txt(asMap(o['cancelRequest']), 'reason')}',
                ].join('\n'),
                style: TextStyle(color: Ink.body, height: 1.4),
              ),
              const SizedBox(height: 8),
              Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(bi('Order messages', 'ஆர்டர் செய்திகள்')),
                  children: [
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: ShopService.messagesOf(
                        id,
                      ).orderBy('createdAt').limitToLast(200).snapshots(),
                      builder: (context, m) => m.hasData
                          ? _transcript([
                              for (final d in m.data!.docs)
                                (
                                  names[txt(d.data(), 'senderUid')] ?? '?',
                                  txt(d.data(), 'text'),
                                  d.data()['createdAt'],
                                ),
                            ])
                          : const SkeletonList(
                              rows: 1,
                              padding: EdgeInsets.zero,
                            ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!done)
                    TextButton.icon(
                      style: liquidActionStyle(),
                      onPressed: _busy
                          ? null
                          : () async {
                              final why = await _write(
                                bi('End this order?', 'இந்த ஆர்டரை முடிக்கவா?'),
                                bi(
                                  'Reason both will see',
                                  'இருவரும் பார்க்கும் காரணம்',
                                ),
                              );
                              if (why == null) return;
                              await _run(
                                () => VimoTeam.endOrder(
                                  id,
                                  why.length > 200
                                      ? why.substring(0, 200)
                                      : why,
                                ),
                                bi('Order ended', 'ஆர்டர் முடிக்கப்பட்டது'),
                              );
                            },
                      icon: Icon(
                        CupertinoIcons.xmark_circle,
                        size: 18,
                        color: Ink.redText,
                      ),
                      label: Text(
                        bi('End order', 'ஆர்டரை முடி'),
                        style: TextStyle(color: Ink.redText),
                      ),
                    ),
                  TextButton.icon(
                    style: liquidActionStyle(),
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => VimoTeam.takeDown(txt(o, 'productId')),
                            bi('Listing taken down', 'பட்டியல் நீக்கப்பட்டது'),
                          ),
                    icon: const Icon(CupertinoIcons.eye_slash, size: 18),
                    label: Text(bi('Take listing down', 'பட்டியலை நீக்கு')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(bi('Report', 'அறிக்கை')),
    ),
    body: Shell(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: VimoTeam.reports.doc(widget.id).snapshots(),
        builder: (context, snap) {
          final r = snap.data?.data();
          if (r == null) {
            return snap.hasError
                ? Center(child: Text(accountError(snap.error!)))
                : const SkeletonList(rows: 4);
          }
          final status = txt(r, 'status');
          final orderIds = [
            for (final id in (r['orderIds'] as List? ?? const []))
              if (id is String) id,
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Glass(
                radius: 20,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            shopLabel(vimoReportReasons, txt(r, 'reason')),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _statusChip(status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${txt(r, 'reporterName')} → ${txt(r, 'againstName')} · ${_vimoWhen(r['createdAt'])}',
                      style: TextStyle(color: Ink.muted),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      txt(r, 'text'),
                      style: const TextStyle(fontSize: 16, height: 1.4),
                    ),
                    if (txt(r, 'outcome').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${bi('Outcome', 'முடிவு')}: ${txt(r, 'outcome')}',
                        style: TextStyle(
                          color: Ink.greenText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _shopSection(bi('People', 'நபர்கள்')),
              _person(
                r,
                uid: txt(r, 'reporterUid'),
                name: txt(r, 'reporterName'),
                role: bi('reported', 'தெரிவித்தவர்'),
              ),
              const SizedBox(height: 8),
              _person(
                r,
                uid: txt(r, 'againstUid'),
                name: txt(r, 'againstName'),
                role: bi('reported about', 'பற்றித் தெரிவிக்கப்பட்டவர்'),
              ),
              _shopSection(
                bi('Their chat', 'அவர்களின் chat'),
                note: bi(
                  'Opened to the team by this report.',
                  'இந்த அறிக்கையால் குழுவுக்குத் திறக்கப்பட்டது.',
                ),
              ),
              _chat(r),
              _shopSection(
                bi('Orders between them', 'அவர்களுக்கிடையேயான ஆர்டர்கள்'),
              ),
              if (orderIds.isEmpty)
                Text(
                  bi('No orders.', 'ஆர்டர்கள் இல்லை.'),
                  style: TextStyle(color: Ink.muted),
                )
              else
                for (final id in orderIds) _order(id, r),
              const SizedBox(height: 16),
              if (status == 'open')
                GhostButton(
                  label: bi('I am looking at this', 'இதை நான் பார்க்கிறேன்'),
                  icon: CupertinoIcons.eye,
                  onPressed: () => _run(
                    () => VimoTeam.setStatus(widget.id, 'reviewing'),
                    bi('Marked', 'குறிக்கப்பட்டது'),
                  ),
                ),
              if (status != 'resolved') ...[
                const SizedBox(height: 8),
                LiquidButton(
                  label: bi(
                    'Resolve and tell the reporter',
                    'தீர்த்து, தெரிவித்தவருக்குச் சொல்',
                  ),
                  icon: CupertinoIcons.checkmark_seal_fill,
                  busy: _busy,
                  onPressed: _busy
                      ? null
                      : () async {
                          final outcome = await _write(
                            bi('What the team did', 'குழு என்ன செய்தது'),
                            bi(
                              'The reporter will read this',
                              'தெரிவித்தவர் இதைப் படிப்பார்',
                            ),
                          );
                          if (outcome == null) return;
                          await _run(() async {
                            await VimoTeam.setStatus(
                              widget.id,
                              'resolved',
                              outcome: outcome,
                            );
                            await VimoTeam.send(
                              txt(r, 'reporterUid'),
                              bi(
                                'About your report: $outcome',
                                'உங்கள் அறிக்கை பற்றி: $outcome',
                              ),
                              name: txt(r, 'reporterName'),
                              asTeam: true,
                              reportId: widget.id,
                            );
                          }, bi('Resolved', 'தீர்க்கப்பட்டது'));
                        },
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}
