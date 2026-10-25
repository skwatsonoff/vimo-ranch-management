part of 'main.dart';

bool validProfileLink(String value) {
  if (value.isEmpty) return true;
  final uri = Uri.tryParse(value);
  return uri != null &&
      ['https', 'http'].contains(uri.scheme) &&
      uri.host.contains('.') &&
      uri.userInfo.isEmpty;
}

String accountError(Object error) {
  if (error is StateError) return error.message;
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return bi(
          'Cloud permission denied. Your entries are still saved. The app’s cloud rules need updating.',
          'கிளவுட் அனுமதி மறுக்கப்பட்டது. உங்கள் பதிவுகள் பாதுகாப்பாக உள்ளன. செயலியின் கிளவுட் அனுமதி விதிகளைப் புதுப்பிக்க வேண்டும்.',
        );
      case 'unauthenticated':
        return bi(
          'Your sign-in expired. Sign in again; local entries are kept.',
          'உள்நுழைவு காலாவதியானது. மீண்டும் உள்நுழையவும்; உள்ளூர் பதிவுகள் பாதுகாப்பாக உள்ளன.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return bi(
          'The cloud is not responding. Your changes are kept; retry when connected.',
          'கிளவுட் பதிலளிக்கவில்லை. மாற்றங்கள் பாதுகாக்கப்பட்டுள்ளன; இணையம் வந்ததும் மீண்டும் முயற்சிக்கவும்.',
        );
      default:
        return bi(
          'Cloud request failed (${error.code}). Please retry.',
          'கிளவுட் கோரிக்கை தோல்வி (${error.code}). மீண்டும் முயற்சிக்கவும்.',
        );
    }
  }
  if (error is TimeoutException) {
    return bi(
      'The cloud took too long to respond. Retry; your draft is kept.',
      'கிளவுட் பதில் தாமதமாகிறது. மீண்டும் முயற்சிக்கவும்; வரைவு பாதுகாக்கப்பட்டுள்ளது.',
    );
  }
  return bi(
    'Could not connect. Check your connection and try again.',
    'இணைக்க முடியவில்லை. இணையத்தைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',
  );
}

Widget profileAvatar(
  String photo, {
  double radius = 38,
  String label = '',
  bool halo = false,
}) => GlassAvatar(
  image: cachedPhoto(photo),
  label: label,
  radius: radius,
  halo: halo,
);

/// Tells a member when someone follows them, unfollows them or sends them a
/// message. There is no push server, so this watches the member's own
/// followers and chats while the app is open and, on the next launch,
/// reports what arrived while it was closed.
class SocialActivityService {
  const SocialActivityService._();
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followers;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _allFollowers;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chats;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _selling;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _buying;
  static final Map<
    String,
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  >
  _chatLatest = {};
  static String _uid = '';

  /// The direct chat on screen right now: its messages need no alert.
  static String openChatId = '';

  static Future<String> _nameOf(String uid) async {
    var name = bi('Someone', 'ஒருவர்');
    try {
      final profile = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(uid)
          .get()
          .timeout(CloudSyncService.networkTimeout);
      final data = profile.data() ?? const <String, dynamic>{};
      final username = txt(data, 'username');
      name = txt(data, 'displayName', username.isEmpty ? name : '@$username');
    } catch (_) {}
    return name;
  }

  /// Someone stopped following: compares the whole followers list with the
  /// one last seen on this device. The first run only records it.
  static Future<void> _checkUnfollows(
    String uid,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (uid != signedInUid || !Hive.isBoxOpen('notifications')) return;
    if (snapshot.metadata.isFromCache) return;
    final known = asMap(settingValue('followerIds', {}));
    final current = [for (final d in snapshot.docs) d.id];
    final before = known[uid];
    await setSetting('followerIds', {...known, uid: current});
    if (before is! List) return;
    final gone = before.map((e) => '$e').toSet().difference(current.toSet());
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final follower in gone) {
      final name = await _nameOf(follower);
      await addRanchNotification(
        title: '$name unfollowed you',
        titleTa: '$name உங்களைப் பின்தொடர்வதை நிறுத்தினார்',
        message: 'Tap to see their profile',
        messageTa: 'அவர் சுயவிவரத்தைப் பார்க்க',
        type: 'unfollow',
        sourceId: 'unfollow-$uid-$follower-$stamp',
        localOnly: true,
        extra: {'profileUid': follower},
      );
      _browserRuntime.showNotification(
        title: bi(
          '$name unfollowed you',
          '$name உங்களைப் பின்தொடர்வதை நிறுத்தினார்',
        ),
        body: bi('Open VIMO to see their profile', 'VIMO-வில் பார்க்கவும்'),
        tag: 'unfollow-$follower',
      );
    }
  }

  /// One small listener per conversation (its newest message).
  static void _watchChats(String uid, QuerySnapshot<Map<String, dynamic>> s) {
    for (final chat in s.docs) {
      if (_chatLatest.containsKey(chat.id)) continue;
      _chatLatest[chat.id] = chat.reference
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots()
          .listen(
            (m) => unawaited(_messageArrived(uid, chat.id, m)),
            onError: (_) {},
          );
    }
  }

  static Future<void> _messageArrived(
    String uid,
    String chatId,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (uid != signedInUid || !Hive.isBoxOpen('notifications')) return;
    final message = snapshot.docs.firstOrNull?.data();
    if (message == null) return;
    final at = message['createdAt'];
    if (at is! Timestamp) return;
    final millis = at.millisecondsSinceEpoch;
    final seenByChat = asMap(settingValue('messageNotices', {}));
    final seen = seenByChat[chatId];
    if (seen is num && millis <= seen) return;
    await setSetting('messageNotices', {...seenByChat, chatId: millis});
    // The first sight of a chat only records where "new" starts.
    if (seen is! num) return;
    final sender = txt(message, 'senderUid');
    if (sender.isEmpty || sender == uid || openChatId == chatId) return;
    final name = await _nameOf(sender);
    final text = txt(message, 'text').trim();
    final preview = text.isEmpty
        ? bi('Sent a voice or photo message', 'குரல் அல்லது படச் செய்தி')
        : (text.length > 80 ? '${text.substring(0, 80)}…' : text);
    await addRanchNotification(
      title: '$name sent you a message',
      titleTa: '$name உங்களுக்குச் செய்தி அனுப்பினார்',
      message: preview,
      type: 'message',
      sourceId: 'message-$chatId-$millis',
      localOnly: true,
      extra: {'chatPeer': sender},
    );
    _browserRuntime.showNotification(
      title: bi('$name sent you a message', '$name செய்தி அனுப்பினார்'),
      body: preview,
      tag: 'message-$chatId',
    );
  }

  /// What a notice compares for an order: its step, plus who has an open
  /// request to cancel ("ordered:buyer").
  static String orderNoticeState(Map<String, dynamic> o) {
    final asked = txt(asMap(o['cancelRequest']), 'by');
    return asked.isEmpty ? txt(o, 'status') : '${txt(o, 'status')}:$asked';
  }

  /// Taking back your own cancel request is not news to you: record the
  /// new state first so it raises no "said no" notice.
  static Future<void> noteOwnOrderChange(
    String id,
    Map<String, dynamic> order, {
    required bool selling,
  }) async {
    final key = selling ? 'orderNoticesSelling' : 'orderNoticesBuying';
    await setSetting(key, {
      ...asMap(settingValue(key, {})),
      id: txt(order, 'status'),
    });
  }

  /// Order steps the other person took: a new order or a received / cancel
  /// for the seller; accepted, sent, completed or cancelled for the buyer.
  /// Each order's last seen status is kept on this device, so the first
  /// sight of an order only records it.
  static Future<void> _ordersChanged(
    String uid,
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required bool selling,
  }) async {
    if (uid != signedInUid || !Hive.isBoxOpen('notifications')) return;
    final key = selling ? 'orderNoticesSelling' : 'orderNoticesBuying';
    final seen = asMap(settingValue(key, {}));
    final firstRun = !seen.containsKey('_primed');
    final next = {...seen, '_primed': true};
    final me = selling ? 'seller' : 'buyer';
    for (final doc in snapshot.docs) {
      final o = doc.data();
      final status = orderNoticeState(o);
      final before = txt(seen, doc.id);
      next[doc.id] = status;
      if (firstRun || before == status) continue;
      final title = txt(o, 'title');
      final who = selling ? txt(o, 'buyerName') : txt(o, 'sellerName');
      final asked = asMap(o['cancelRequest']);
      final (String en, String ta)? notice = switch ((selling, status)) {
        // Cancelling takes both: the other side asked, agreed or said no.
        (_, 'cancelled') when txt(o, 'cancelledBy') == me => (
          '$who agreed. The order for $title is cancelled.',
          '$who ஒப்புக்கொண்டார். $title ஆர்டர் ரத்தானது.',
        ),
        _ when asked.isNotEmpty && txt(asked, 'by') != me => (
          '$who asks to cancel $title. Talk it over and answer.',
          '$who $title ரத்து செய்யக் கேட்கிறார். பேசிப் பதில் சொல்லவும்.',
        ),
        _ when before.endsWith(':$me') && asked.isEmpty => (
          '$who said no to cancelling $title. The order goes on.',
          '$who $title ரத்தை ஏற்கவில்லை. ஆர்டர் தொடர்கிறது.',
        ),

        (true, 'ordered') => (
          '$who ordered $title',
          '$who $title ஆர்டர் செய்தார்',
        ),
        (true, 'received') => (
          '$who received $title. Rate them to finish.',
          '$who $title பெற்றார். முடிக்க மதிப்பிடவும்.',
        ),
        (false, 'accepted') => (
          '$who accepted your order for $title',
          '$who உங்கள் $title ஆர்டரை ஏற்றார்',
        ),
        (false, 'shipped') => ('$title is on the way', '$title வழியில் உள்ளது'),
        (false, 'completed') => (
          '$who rated you. Order complete.',
          '$who உங்களை மதிப்பிட்டார். ஆர்டர் முடிந்தது.',
        ),
        _ => null,
      };
      if (notice == null) continue;
      await addRanchNotification(
        title: notice.$1,
        titleTa: notice.$2,
        message: 'Tap to open the order',
        messageTa: 'ஆர்டரைத் திறக்கத் தொடவும்',
        type: 'message',
        sourceId:
            'order-${doc.id}-$status-${(o['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0}',
        localOnly: true,
        extra: {'orderId': doc.id},
      );
      _browserRuntime.showNotification(
        title: bi(notice.$1, notice.$2),
        body: bi(
          'Open VIMO to see the order',
          'VIMO-வில் ஆர்டரைப் பார்க்கவும்',
        ),
        tag: 'order-${doc.id}',
      );
    }
    await setSetting(key, next);
  }

  static void start() {
    final uid = signedInUid;
    if (uid.isEmpty || (uid == _uid && _followers != null)) return;
    unawaited(_followers?.cancel());
    unawaited(_allFollowers?.cancel());
    unawaited(_chats?.cancel());
    unawaited(_selling?.cancel());
    unawaited(_buying?.cancel());
    for (final watch in _chatLatest.values) {
      unawaited(watch.cancel());
    }
    _chatLatest.clear();
    _uid = uid;
    final profile = FirebaseFirestore.instance.collection('profiles').doc(uid);
    _allFollowers = profile
        .collection('followers')
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) => unawaited(_checkUnfollows(uid, snapshot)),
          onError: (_) {},
        );
    _selling = ShopService.selling().listen(
      (s) => unawaited(_ordersChanged(uid, s, selling: true)),
      onError: (_) {},
    );
    _buying = ShopService.buying().listen(
      (s) => unawaited(_ordersChanged(uid, s, selling: false)),
      onError: (_) {},
    );
    _chats = FirebaseFirestore.instance
        .collection('direct_chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snapshot) => _watchChats(uid, snapshot), onError: (_) {});
    _followers = FirebaseFirestore.instance
        .collection('profiles')
        .doc(uid)
        .collection('followers')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen(
          (snapshot) => unawaited(_arrived(uid, snapshot)),
          onError: (_) {},
        );
  }

  static Future<void> _arrived(
    String uid,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (uid != signedInUid || !Hive.isBoxOpen('notifications')) return;
    final seenByUser = asMap(settingValue('followNotices', {}));
    final seen = seenByUser[uid];
    var newest = seen is num ? seen.toInt() : -1;
    final fresh = <(String, int)>[];
    for (final doc in snapshot.docs) {
      final stamp = doc.data()['createdAt'];
      if (stamp is! Timestamp) continue;
      final millis = stamp.millisecondsSinceEpoch;
      if (seen is num && millis > seen) fresh.add((doc.id, millis));
      if (millis > newest) newest = millis;
    }
    // The first run only records where "new" starts; old follows are not
    // announced as if they had just happened.
    if (seen is! num || newest > seen) {
      await setSetting('followNotices', {
        ...seenByUser,
        uid: math.max(0, newest),
      });
    }
    for (final (follower, millis) in fresh.reversed) {
      var name = bi('Someone', 'ஒருவர்');
      try {
        final profile = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(follower)
            .get()
            .timeout(CloudSyncService.networkTimeout);
        final data = profile.data() ?? const <String, dynamic>{};
        final username = txt(data, 'username');
        name = txt(data, 'displayName', username.isEmpty ? name : '@$username');
      } catch (_) {}
      final title = bi(
        '$name started following you',
        '$name உங்களைப் பின்தொடர்கிறார்',
      );
      await addRanchNotification(
        title: '$name started following you',
        titleTa: '$name உங்களைப் பின்தொடர்கிறார்',
        message: 'Tap to see their profile',
        messageTa: 'அவர் சுயவிவரத்தைப் பார்க்க',
        type: 'follow',
        sourceId: 'follow-$uid-$follower-$millis',
        localOnly: true,
        extra: {'profileUid': follower},
      );
      _browserRuntime.showNotification(
        title: title,
        body: bi('Open VIMO to see their profile', 'VIMO-வில் பார்க்கவும்'),
        tag: 'follow-$follower',
      );
    }
  }

  static Future<void> stop() async {
    await _followers?.cancel();
    await _allFollowers?.cancel();
    await _chats?.cancel();
    await _selling?.cancel();
    await _buying?.cancel();
    _selling = null;
    _buying = null;
    for (final watch in _chatLatest.values) {
      await watch.cancel();
    }
    _chatLatest.clear();
    _followers = null;
    _allFollowers = null;
    _chats = null;
    _uid = '';
  }
}

class SocialProfileScreen extends StatefulWidget {
  final String? uid;
  const SocialProfileScreen({super.key, this.uid});
  @override
  State<SocialProfileScreen> createState() => _SocialProfileScreenState();
}

class _SocialProfileScreenState extends State<SocialProfileScreen> {
  String get uid => widget.uid ?? signedInUid;
  bool get own => uid == signedInUid;
  int _tab = 0;
  bool _busy = false;

  /// Unique to this page, so two open profiles never share a flying photo.
  final Object _photoHero = Object();
  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      actions: [
        if (uid.isNotEmpty)
          IconButton(
            tooltip: bi('Share profile', 'ப்ரொஃபைலைப் பகிர்'),
            icon: const Icon(CupertinoIcons.share),
            onPressed: () => showShareSheet(context, () async {
              final snap = await FirebaseFirestore.instance
                  .collection('profiles')
                  .doc(uid)
                  .get();
              return ShareCard.profile(uid, snap.data() ?? const {});
            }),
          ),
        // As the Profile tab, the app bar above already has Settings.
        if (own && !(ModalRoute.of(context)?.isFirst ?? false))
          IconButton(
            tooltip: ui('Settings'),
            icon: const Icon(CupertinoIcons.gear),
            onPressed: () => push(context, const SettingsScreen()),
          ),
      ],
    ),
    body: Shell(
      edgeToEdge: true,
      child: uid.isEmpty
          ? SignInStatePanel(
              message: bi(
                'Sign in to see your profile.',
                'உங்கள் சுயவிவரத்தைப் பார்க்க உள்நுழையவும்.',
              ),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('profiles')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? <String, dynamic>{};
                final name = txt(data, 'username', own ? accountUsername : '');
                final showRanch = own
                    ? workspaceEnabled('Ranch')
                    : data['shareRanch'] == true;
                final shop = data['shareShop'] == true;
                final showVendor = own
                    ? workspaceEnabled('Vendor') || shop
                    : shop;
                final sections = [
                  (0, bi('Post', 'பதிவுகள்'), CupertinoIcons.doc_text),
                  if (showRanch)
                    (1, bi('Ranch', 'பண்ணை'), CupertinoIcons.house),
                  if (showVendor)
                    (
                      2,
                      shop ? bi('Shop', 'கடை') : bi('Vendor', 'கடை'),
                      CupertinoIcons.bag,
                    ),
                ];
                // A hidden section falls back to the posts.
                final tab = sections.any((s) => s.$1 == _tab) ? _tab : 0;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    32 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    SizedBox(
                      height: 150,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Opacity(
                            opacity: .16,
                            child: Image(
                              image: heroArtImage,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const Align(
                            alignment: Alignment(.72, .1),
                            child: VimoScript(size: 58),
                          ),
                        ],
                      ),
                    ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Glass(
                          radius: 34,
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 118),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            txt(
                                              data,
                                              'displayName',
                                              own ? currentUserName() : name,
                                            ).toUpperCase(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: .2,
                                              color: Ink.navy,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                name.isEmpty
                                                    ? bi(
                                                        'Choose a username',
                                                        'பயனர்பெயரைத் தேர்ந்தெடு',
                                                      )
                                                    : '@$name',
                                                style: TextStyle(
                                                  color: Ink.muted,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (!own) _FollowsYou(uid: uid),
                                            ],
                                          ),
                                          if (txt(data, 'place').isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    CupertinoIcons
                                                        .location_solid,
                                                    size: 16,
                                                    color: Ink.violetDeep,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      txt(data, 'place'),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Ink.body,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (own)
                                      IconButton(
                                        tooltip: bi(
                                          'Edit profile',
                                          'சுயவிவரத்தைத் திருத்து',
                                        ),
                                        icon: const Icon(CupertinoIcons.pencil),
                                        onPressed: () => push(
                                          context,
                                          EditSocialProfileScreen(data: data),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _ProfileCount(
                                        uid: uid,
                                        kind: 'following',
                                      ),
                                    ),
                                    VerticalDivider(
                                      width: 1,
                                      thickness: 1,
                                      color: Ink.violetDeep.withValues(
                                        alpha: .14,
                                      ),
                                    ),
                                    Expanded(
                                      child: _ProfileCount(
                                        uid: uid,
                                        kind: 'followers',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (txt(data, 'bio').isNotEmpty) ...[
                                const SizedBox(height: 14),
                                MentionText(
                                  txt(data, 'bio'),
                                  mentions: data['bioMentions'] is List
                                      ? List.from(data['bioMentions'])
                                      : const [],
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.4,
                                    color: Ink.body,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  if (txt(data, 'whatsapp').isNotEmpty)
                                    Expanded(
                                      child: _ProfileAction(
                                        icon: CupertinoIcons.chat_bubble_fill,
                                        iconColor: const Color(0xFF25D366),
                                        label: 'WhatsApp',
                                        onTap: () => _link(
                                          'https://wa.me/${txt(data, 'whatsapp').replaceAll(RegExp(r'[^0-9]'), '')}',
                                        ),
                                      ),
                                    ),
                                  if (txt(data, 'whatsapp').isNotEmpty &&
                                      (validProfileLink(txt(data, 'link')) &&
                                              txt(data, 'link').isNotEmpty ||
                                          !own))
                                    const SizedBox(width: 10),
                                  if (txt(data, 'link').isNotEmpty &&
                                      validProfileLink(txt(data, 'link')))
                                    Expanded(
                                      child: _ProfileAction(
                                        icon: CupertinoIcons.link,
                                        label: bi('My link', 'என் இணைப்பு'),
                                        onTap: () => _link(txt(data, 'link')),
                                      ),
                                    ),
                                  if (!own) ...[
                                    if (txt(data, 'link').isNotEmpty &&
                                        validProfileLink(txt(data, 'link')))
                                      const SizedBox(width: 10),
                                    Expanded(
                                      child: _ProfileAction(
                                        icon: CupertinoIcons.chat_bubble_2_fill,
                                        label: bi('Message', 'செய்தி'),
                                        onTap: () async {
                                          try {
                                            final chat =
                                                await DirectChatService.open(
                                                  uid,
                                                );
                                            if (context.mounted) {
                                              await push(
                                                context,
                                                DirectChatScreen(
                                                  chatId: chat,
                                                  peer: uid,
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              snack(context, accountError(e));
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (!own)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child:
                                      StreamBuilder<
                                        DocumentSnapshot<Map<String, dynamic>>
                                      >(
                                        stream: FirebaseFirestore.instance
                                            .collection('profiles')
                                            .doc(uid)
                                            .collection('followers')
                                            .doc(signedInUid)
                                            .snapshots(),
                                        builder: (context, follow) {
                                          final following =
                                              follow.data?.exists == true;
                                          if (!following) {
                                            return LiquidButton(
                                              label: bi('Follow', 'பின்தொடர்'),
                                              icon: CupertinoIcons
                                                  .person_add_solid,
                                              height: 48,
                                              radius: 24,
                                              busy: _busy,
                                              onPressed:
                                                  _busy || !follow.hasData
                                                  ? null
                                                  : () => _toggleFollow(false),
                                            );
                                          }
                                          // Once followed, the same place offers
                                          // Unfollow as a quiet outlined button.
                                          return SizedBox(
                                            height: 48,
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                shape: const StadiumBorder(),
                                                backgroundColor: Ink.surface
                                                    .withValues(alpha: .7),
                                                foregroundColor: Ink.navy,
                                                side: BorderSide(
                                                  color: Ink.violetDeep
                                                      .withValues(alpha: .28),
                                                ),
                                                textStyle: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              onPressed: _busy
                                                  ? null
                                                  : () => _toggleFollow(true),
                                              icon: _busy
                                                  ? const SizedBox.square(
                                                      dimension: 18,
                                                      child:
                                                          CupertinoActivityIndicator(),
                                                    )
                                                  : const Icon(
                                                      CupertinoIcons
                                                          .person_badge_minus,
                                                      size: 20,
                                                    ),
                                              label: Text(
                                                bi(
                                                  'Unfollow',
                                                  'பின்தொடர்வதை நிறுத்து',
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 14,
                          top: -46,
                          child: GestureDetector(
                            onTap: () {
                              final image = cachedPhoto(txt(data, 'photo'));
                              if (image == null) return;
                              push(
                                context,
                                SocialPhotoViewer(
                                  image: image,
                                  heroTag: _photoHero,
                                ),
                              );
                            },
                            child: Hero(
                              tag: _photoHero,
                              child: profileAvatar(
                                txt(data, 'photo'),
                                radius: 56,
                                label: txt(data, 'displayName', name),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (snap.hasError)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(accountError(snap.error!)),
                      ),
                    const SizedBox(height: 20),
                    // Ranch and Vendor appear only for people who use them:
                    // your own switched-on workspaces, or what another
                    // person shares. Someone who uses VIMO only for the
                    // market sees just their posts.
                    if (sections.length > 1)
                      Glass(
                        radius: 28,
                        padding: const EdgeInsets.all(5),
                        child: Row(
                          children: [
                            for (final item in sections)
                              Expanded(
                                child: TextButton(
                                  onPressed: () =>
                                      setState(() => _tab = item.$1),
                                  style: TextButton.styleFrom(
                                    shape: const StadiumBorder(),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    backgroundColor: tab == item.$1
                                        ? Ink.tint
                                        : Colors.transparent,
                                    foregroundColor: tab == item.$1
                                        ? Colors.white
                                        : Ink.muted,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (item.$1 == 1)
                                        CowMark(
                                          size: 25,
                                          color: tab == 1
                                              ? Colors.white
                                              : Ink.violetDeep,
                                        )
                                      else
                                        Icon(item.$3, size: 21),
                                      const SizedBox(width: 6),
                                      Flexible(child: Text(item.$2)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (sections.length > 1) const SizedBox(height: 20),
                    if (tab == 0) ProfilePostList(uid: uid, own: own),
                    if (tab == 1) PublicRanchView(uid: uid, profile: data),
                    // The shop: products to buy, and for the owner a
                    // pencil to list more (once Show my shop is on).
                    if (tab == 2)
                      shop
                          ? ProfileShop(uid: uid, own: own, profile: data)
                          : Glass(
                              child: Text(
                                own
                                    ? bi(
                                        'Turn on Show my shop in Edit profile to list products.',
                                        'பொருட்களைப் பட்டியலிட, Edit profile-ல் என் கடையைக் காட்டு என்பதை இயக்கவும்.',
                                      )
                                    : bi(
                                        'This shop is private.',
                                        'இந்தக் கடை தனிப்பட்டது.',
                                      ),
                              ),
                            ),
                  ],
                );
              },
            ),
    ),
  );
  Future<void> _toggleFollow(bool following) async {
    if (accountUsername.isEmpty) {
      await push(context, const UsernameScreen());
      if (!mounted || accountUsername.isEmpty) return;
    }
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final a = db
          .collection('profiles')
          .doc(uid)
          .collection('followers')
          .doc(signedInUid);
      final b = db
          .collection('profiles')
          .doc(signedInUid)
          .collection('following')
          .doc(uid);
      if (following) {
        batch.delete(a);
        batch.delete(b);
      } else {
        batch.set(a, {'createdAt': FieldValue.serverTimestamp()});
        batch.set(b, {'createdAt': FieldValue.serverTimestamp()});
      }
      await batch.commit().timeout(CloudSyncService.networkTimeout);
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link(String value) async {
    try {
      await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    }
  }
}

// A simple silhouette stays recognisable at tab size, unlike the detailed art.

class ProfilePostList extends StatefulWidget {
  final String uid;
  final bool own;
  const ProfilePostList({super.key, required this.uid, required this.own});
  @override
  State<ProfilePostList> createState() => _ProfilePostListState();
}

class _ProfilePostListState extends State<ProfilePostList> {
  late Future<List<SocialPostRecord>> _posts;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SocialPostRecord>>(
      future: _posts,
      builder: (context, snap) {
        if (snap.hasError) return Text(accountError(snap.error!));
        if (!snap.hasData) {
          return const Center(child: CupertinoActivityIndicator());
        }
        if (snap.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(26),
            child: Text(bi('No posts yet.', 'இன்னும் பதிவுகள் இல்லை.')),
          );
        }
        return Column(
          children: [
            for (final post in snap.data!)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_SocialPost(key: ValueKey(post.id), post: post)],
                ),
              ),
          ],
        );
      },
    );
  }

  void _refresh() =>
      _posts = SocialFeed.load(authorUid: widget.uid, own: widget.own);
}

/// Twitter-style "Follows you" tag, shown when the viewed member follows the
/// signed-in member.
class _FollowsYou extends StatelessWidget {
  final String uid;
  const _FollowsYou({required this.uid});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('profiles')
            .doc(signedInUid)
            .collection('followers')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) => AnimatedSwitcher(
          duration: Gold.base,
          child: snap.data?.exists == true
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Ink.violetDeep.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    bi('Follows you', 'உங்களைப் பின்தொடர்கிறார்'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Ink.muted,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      );
}

class _ProfileCount extends StatelessWidget {
  final String uid, kind;
  const _ProfileCount({required this.uid, required this.kind});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('profiles')
            .doc(uid)
            .collection(kind)
            .snapshots(),
        builder: (context, snapshot) {
          final count = snapshot.data?.docs.length;
          String compact(int n) => n >= 1000000
              ? '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M'
              : n >= 1000
              ? '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K'
              : '$n';
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () =>
                push(context, ProfilePeopleScreen(uid: uid, kind: kind)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Text(
                    count == null ? '–' : compact(count),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Ink.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kind == 'followers'
                        ? bi('Followers', 'பின்தொடர்பவர்கள்')
                        : bi('Following', 'பின்தொடர்பவை'),
                    style: TextStyle(color: Ink.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _ProfileAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? _iconColor;
  Color get iconColor => _iconColor ?? Ink.violetDeep;
  final VoidCallback onTap;
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this._iconColor,
  });
  @override
  Widget build(BuildContext context) => Glass(
    radius: 22,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    onTap: onTap,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600, color: Ink.navy),
          ),
        ),
      ],
    ),
  );
}

class ProfilePeopleScreen extends StatelessWidget {
  final String uid, kind;
  const ProfilePeopleScreen({super.key, required this.uid, required this.kind});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        kind == 'followers'
            ? bi('Followers', 'பின்தொடர்பவர்கள்')
            : bi('Following', 'பின்தொடர்பவை'),
      ),
    ),
    body: Shell(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('profiles')
            .doc(uid)
            .collection(kind)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(accountError(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CupertinoActivityIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(bi('No people yet', 'இன்னும் யாரும் இல்லை')),
            );
          }
          return ListView(
            children: [
              for (final person in snapshot.data!.docs)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('profiles')
                      .doc(person.id)
                      .snapshots(),
                  builder: (context, profile) => ListTile(
                    leading: profileAvatar(
                      txt(profile.data?.data() ?? {}, 'photo'),
                      radius: 22,
                    ),
                    title: Text(
                      txt(profile.data?.data() ?? {}, 'username', '…'),
                    ),
                    onTap: () =>
                        push(context, SocialProfileScreen(uid: person.id)),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class EditSocialProfileScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const EditSocialProfileScreen({super.key, required this.data});
  @override
  State<EditSocialProfileScreen> createState() =>
      _EditSocialProfileScreenState();
}

class _EditSocialProfileScreenState extends State<EditSocialProfileScreen> {
  late final _username = TextEditingController(text: accountUsername);
  late final _name = TextEditingController(
    text: txt(widget.data, 'displayName', currentUserName()),
  );
  late final _place = TextEditingController(text: txt(widget.data, 'place'));
  late final _whatsapp = TextEditingController(
    text: txt(widget.data, 'whatsapp'),
  );
  late final _shop = TextEditingController(text: txt(widget.data, 'shopName'));
  late final _shopDetails = TextEditingController(
    text: txt(widget.data, 'shopDetails'),
  );
  late bool _shareRanch = widget.data['shareRanch'] == true;
  late bool _shareShop = widget.data['shareShop'] == true;
  late final _bio = TextEditingController(text: txt(widget.data, 'bio'));
  late final _link = TextEditingController(text: txt(widget.data, 'link'));
  late String _photo = txt(widget.data, 'photo');
  bool _busy = false, _picking = false;
  @override
  void initState() {
    super.initState();
    if (widget.data['bioMentions'] is List) {
      mentionSelections[_bio] = [
        for (final item in List.from(widget.data['bioMentions']))
          if (item is Map) asMap(item),
      ];
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _place.dispose();
    _whatsapp.dispose();
    _shop.dispose();
    _shopDetails.dispose();
    _bio.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_picking || _busy) return;
    setState(() => _picking = true);
    try {
      final selected = await pickImageDataUrl(social: true);
      if (selected == null) return;
      final photo = await compressSocialPhoto(selected);
      if (photo == null)
        throw StateError(
          bi('Could not load this photo.', 'புகைப்படத்தை ஏற்ற முடியவில்லை.'),
        );
      if (mounted) setState(() => _photo = photo);
    } catch (e) {
      if (mounted) snack(context, accountError(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _photoMenu() async {
    await showAppleSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Glass(
        radius: Gold.r34,
        opacity: .96,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(CupertinoIcons.photo),
                title: Text(bi('Change photo', 'புகைப்படத்தை மாற்று')),
                onTap: () {
                  Navigator.pop(context);
                  _pickPhoto();
                },
              ),
              if (_photo.isNotEmpty)
                ListTile(
                  leading: Icon(CupertinoIcons.trash, color: Ink.red),
                  title: Text(bi('Remove photo', 'புகைப்படத்தை நீக்கு')),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _photo = '');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: bi('Edit profile', 'சுயவிவரத்தைத் திருத்து'),
    children: [
      Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            profileAvatar(_photo, radius: 62),
            Positioned(
              right: -4,
              bottom: -4,
              child: Semantics(
                button: true,
                label: bi('Edit photo', 'புகைப்படத்தைத் திருத்து'),
                child: GestureDetector(
                  onTap: _picking || _busy ? null : _photoMenu,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Ink.surface.withValues(alpha: .96),
                          Ink.violet.withValues(alpha: .28),
                        ],
                      ),
                      border: Border.all(color: Ink.surface, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Ink.violetDeep.withValues(alpha: .28),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      CupertinoIcons.pencil,
                      size: 22,
                      color: Ink.violetDeep,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      TextField(
        controller: _name,
        maxLength: 80,
        decoration: fieldStyle(bi('Name', 'பெயர்')),
      ),
      TextField(
        controller: _place,
        maxLength: 120,
        decoration: fieldStyle(bi('Location', 'இடம்')),
      ),
      const SizedBox(height: 12),
      UsernameField(controller: _username),
      const SizedBox(height: 16),
      MentionInput(
        controller: _bio,
        maxLength: 160,
        minLines: 3,
        maxLines: 5,
        hint: bi('Bio', 'சுய அறிமுகம்'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _link,
        maxLength: 300,
        keyboardType: TextInputType.url,
        decoration: fieldStyle(bi('Link (optional)', 'இணைப்பு (விருப்பம்)')),
      ),
      TextField(
        controller: _whatsapp,
        maxLength: 16,
        keyboardType: TextInputType.phone,
        decoration: fieldStyle(
          bi(
            'WhatsApp with country code',
            'நாட்டுக் குறியீட்டுடன் வாட்ஸ்அப் எண்',
          ),
        ),
      ),
      // Sharing a ranch or a shop is offered only to people who use them;
      // a value already on stays editable so it can be switched off.
      if (workspaceEnabled('Ranch') || _shareRanch)
        SoundSwitchListTile(
          value: _shareRanch,
          title: Text(bi('Show my ranch cows', 'என் பண்ணை மாடுகளைக் காட்டு')),
          subtitle: Text(
            bi(
              'Only cow photos, names and breeds are shared.',
              'மாட்டுப் படங்கள், பெயர்கள், இனங்கள் மட்டும் பகிரப்படும்.',
            ),
          ),
          onChanged: CloudSyncService.ready
              ? (v) => setState(() => _shareRanch = v)
              : null,
        ),
      SoundSwitchListTile(
        value: _shareShop,
        title: Text(bi('Show my shop', 'என் கடையைக் காட்டு')),
        onChanged: (v) => setState(() => _shareShop = v),
      ),
      if (_shareShop) ...[
        TextField(
          controller: _shop,
          maxLength: 100,
          decoration: fieldStyle(bi('Shop name', 'கடைப் பெயர்')),
        ),
        TextField(
          controller: _shopDetails,
          maxLength: 500,
          maxLines: 4,
          decoration: fieldStyle(bi('Shop details', 'கடை விவரம்')),
        ),
      ],
      const SizedBox(height: 24),
      LiquidButton(
        label: 'Save',
        busy: _busy,
        onPressed: () async {
          if (_busy || _picking) return;
          if (_whatsapp.text.trim().isNotEmpty &&
              !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(_whatsapp.text.trim())) {
            snack(
              context,
              bi(
                'Enter 7–15 digits with country code.',
                'நாட்டுக் குறியீட்டுடன் 7–15 எண்களை உள்ளிடுங்கள்.',
              ),
            );
            return;
          }
          if (_name.text.trim().isEmpty) {
            snack(context, bi('Enter your name.', 'பெயரை உள்ளிடுங்கள்.'));
            return;
          }
          if (!validProfileLink(_link.text.trim())) {
            snack(
              context,
              bi(
                'Enter a valid https:// link.',
                'சரியான https:// இணைப்பை உள்ளிடுங்கள்.',
              ),
            );
            return;
          }
          final requestedUsername = normalizeUsername(_username.text);
          if (requestedUsername != accountUsername) {
            try {
              await UsernameService.save(requestedUsername);
            } catch (e) {
              if (mounted) snack(context, accountError(e));
              return;
            }
          }
          if (accountUsername.isEmpty) return;
          setState(() => _busy = true);
          try {
            final uid = FirebaseAuth.instance.currentUser!.uid;
            await FirebaseFirestore.instance
                .collection('profiles')
                .doc(uid)
                .set({
                  'username': accountUsername,
                  'displayName': _name.text.trim(),
                  'displayNameFold': _name.text.trim().toLowerCase(),
                  'place': _place.text.trim(),
                  'whatsapp': _whatsapp.text.trim(),
                  'shareRanch': _shareRanch,
                  'ranchId': _shareRanch ? ranchId() : '',
                  'ranchName': _shareRanch ? farmName() : '',
                  'shareShop': _shareShop,
                  'shopName': _shop.text.trim(),
                  'shopDetails': _shopDetails.text.trim(),
                  'photo': _photo,
                  'bio': _bio.text.trim(),
                  'bioMentions':
                      mentionSelections[_bio] ??
                      (widget.data['bioMentions'] is List
                          ? List.from(widget.data['bioMentions'])
                          : const []),
                  'link': _link.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true))
                .timeout(const Duration(seconds: 20));
            AutoSyncService.scheduleSync(reason: 'profile changed');
            if (context.mounted) Navigator.pop(context);
          } catch (e) {
            if (context.mounted) snack(context, accountError(e));
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
    ],
  );
}
