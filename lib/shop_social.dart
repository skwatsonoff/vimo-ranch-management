part of 'main.dart';

/// What Mercari does around an item, brought to VIMO's Market:
/// likes (and a note when a liked item gets cheaper), offers the seller can
/// accept for a 24-hour buy, and public questions the seller answers.

// ---------------------------------------------------------------- likes --

class ShopLikes {
  const ShopLikes._();

  static CollectionReference<Map<String, dynamic>> get likes =>
      FirebaseFirestore.instance.collection('shop_likes');

  static String idFor(String productId) => '${signedInUid}_$productId';

  static Stream<bool> liked(String productId) => likes
      .doc(idFor(productId))
      .snapshots()
      .map((d) => d.exists)
      .handleError((Object _) {});

  static Future<int> count(String productId) async {
    try {
      final agg = await likes
          .where('productId', isEqualTo: productId)
          .count()
          .get();
      return agg.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> set(
    String productId,
    Map<String, dynamic> product,
    bool like,
  ) => like
      ? likes.doc(idFor(productId)).set({
          'uid': signedInUid,
          'productId': productId,
          'title': txt(product, 'title'),
          'price': numv(product, 'price'),
          'createdAt': FieldValue.serverTimestamp(),
        })
      : likes.doc(idFor(productId)).delete();

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> mine() =>
      likes
          .where('uid', isEqualTo: signedInUid)
          .limit(100)
          .snapshots()
          .map((s) => s.docs);
}

/// A heart that likes or unlikes, with a little pop.
class LikeButton extends StatelessWidget {
  final String productId;
  final Map<String, dynamic> product;
  final bool small;
  const LikeButton({
    super.key,
    required this.productId,
    required this.product,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!ShopService.available || txt(product, 'sellerUid') == signedInUid) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<bool>(
      stream: ShopLikes.liked(productId),
      builder: (context, snap) {
        final on = snap.data ?? false;
        final icon = AnimatedSwitcher(
          duration: Motion.reduced(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          transitionBuilder: (child, a) => ScaleTransition(
            scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
            child: child,
          ),
          child: Icon(
            on ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            key: ValueKey(on),
            size: small ? 18 : 24,
            color: on ? Ink.red : (small ? Colors.white : Ink.navy),
          ),
        );
        Future<void> toggle() async {
          UiSound.play(on ? UiSoundKind.toggleOff : UiSoundKind.toggleOn);
          try {
            await ShopLikes.set(productId, product, !on);
          } catch (e) {
            if (context.mounted) {
              snack(context, accountError(e), tone: SnackTone.error);
            }
          }
        }

        final label = on
            ? bi('Remove from likes', 'விருப்பத்திலிருந்து நீக்கு')
            : bi('Like', 'விரும்பு');
        if (small) {
          return Semantics(
            button: true,
            label: label,
            child: GestureDetector(
              onTap: toggle,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .32),
                  shape: BoxShape.circle,
                ),
                child: icon,
              ),
            ),
          );
        }
        return IconButton(tooltip: label, onPressed: toggle, icon: icon);
      },
    );
  }
}

class LikedScreen extends StatelessWidget {
  const LikedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(bi('Liked', 'விரும்பியவை')),
    ),
    body: Shell(
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: ShopLikes.mine(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(accountError(snap.error!)));
          }
          final likes = snap.data;
          if (likes == null) return const SkeletonList(rows: 3);
          if (likes.isEmpty) {
            return StatePanel(
              icon: CupertinoIcons.heart,
              title: bi('Nothing liked yet', 'இன்னும் எதுவும் இல்லை'),
              message: bi(
                'Tap the heart on an item to keep it here. You will hear when its price drops.',
                'பொருளில் இதயத்தைத் தொட்டால் இங்கே சேரும். விலை குறைந்தால் தெரிவிக்கப்படும்.',
              ),
            );
          }
          final ids = [for (final l in likes) txt(l.data(), 'productId')];
          return FutureBuilder<
            List<QueryDocumentSnapshot<Map<String, dynamic>>>
          >(
            future: _products(ids),
            builder: (context, products) {
              final docs = products.data;
              if (docs == null) return const SkeletonList(rows: 3);
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [ProductGrid(docs: docs)],
              );
            },
          );
        },
      ),
    ),
  );

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _products(
    List<String> ids,
  ) async {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, math.min(ids.length, i + 30));
      try {
        out.addAll(
          (await ShopService.products
                  .where(FieldPath.documentId, whereIn: chunk)
                  .get())
              .docs,
        );
      } catch (_) {}
    }
    return out;
  }
}

// --------------------------------------------------------------- offers --

/// Offers can go down to half the price, Mercari style; an accepted one
/// is good for 24 hours and one item.
const shopOfferHours = 24;

double shopOfferFloor(double price) => (price / 2).ceilToDouble();

class ShopOffers {
  const ShopOffers._();

  static CollectionReference<Map<String, dynamic>> get offers =>
      FirebaseFirestore.instance.collection('shop_offers');

  static String idFor(String productId, [String? buyer]) =>
      '${productId}_${buyer ?? signedInUid}';

  /// Whether an accepted offer can still be used to buy.
  static bool usable(Map<String, dynamic> offer, [DateTime? now]) {
    if (txt(offer, 'status') != 'accepted') return false;
    final at = offer['acceptedAt'];
    if (at is! Timestamp) return false;
    return (now ?? DateTime.now()).isBefore(
      at.toDate().add(const Duration(hours: shopOfferHours)),
    );
  }

  static Future<void> make(
    String productId,
    Map<String, dynamic> product,
    double price,
  ) async => offers.doc(idFor(productId)).set({
    'productId': productId,
    'sellerUid': txt(product, 'sellerUid'),
    'buyerUid': signedInUid,
    'buyerName': await MarketService.myName(),
    'title': txt(product, 'title'),
    'listPrice': numv(product, 'price'),
    'price': price,
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  static Future<void> withdraw(String id) => offers.doc(id).update({
    'status': 'withdrawn',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  static Future<void> answer(String id, bool accept) => offers.doc(id).update({
    'status': accept ? 'accepted' : 'declined',
    if (accept) 'acceptedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> forProduct(
    String productId,
  ) => offers
      .where('sellerUid', isEqualTo: signedInUid)
      .where('productId', isEqualTo: productId)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            if (const {'pending', 'accepted'}.contains(txt(d.data(), 'status')))
              d,
        ],
      );
}

/// The buyer's side on a product page: make an offer, or see where it is.
class OfferPanel extends StatelessWidget {
  final String productId;
  final Map<String, dynamic> product;
  const OfferPanel({super.key, required this.productId, required this.product});

  Future<void> _make(BuildContext context) async {
    final price = numv(product, 'price');
    final floor = shopOfferFloor(price);
    final c = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(bi('Make an offer', 'விலை கேள்')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              bi(
                'Listed at ${money(price)}. Offer from ${money(floor)}. If the seller accepts, you have $shopOfferHours hours to buy one at your price.',
                'விலை ${money(price)}. ${money(floor)} முதல் கேட்கலாம். விற்பவர் ஏற்றால் $shopOfferHours மணி நேரத்தில் ஒன்றை உங்கள் விலைக்கு வாங்கலாம்.',
              ),
              style: TextStyle(color: Ink.muted),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: bi('Your price', 'உங்கள் விலை'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ui('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.trim())),
            child: Text(bi('Send offer', 'அனுப்பு')),
          ),
        ],
      ),
    );
    c.dispose();
    if (value == null || !context.mounted) return;
    if (value < floor || value >= price) {
      snack(
        context,
        bi(
          'Offer between ${money(floor)} and ${money(price - 1)}',
          '${money(floor)} முதல் ${money(price - 1)} வரை கேட்கவும்',
        ),
        tone: SnackTone.error,
      );
      return;
    }
    if (!await MarketLocation.require(context) || !context.mounted) return;
    if (!await VimoTeam.marketAllowed(context) || !context.mounted) return;
    try {
      await ShopOffers.make(productId, product, value);
      if (context.mounted) {
        snack(
          context,
          bi(
            'Offer sent. You will hear when ${txt(product, 'sellerName')} answers.',
            'அனுப்பப்பட்டது. ${txt(product, 'sellerName')} பதில் சொன்னதும் தெரிவிக்கப்படும்.',
          ),
          tone: SnackTone.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        snack(context, accountError(e), tone: SnackTone.error);
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: ShopOffers.offers.doc(ShopOffers.idFor(productId)).snapshots(),
    builder: (context, snap) {
      final offer = snap.data?.data() ?? const <String, dynamic>{};
      final status = txt(offer, 'status');
      if (status == 'pending') {
        return _line(
          context,
          CupertinoIcons.clock,
          bi(
            'Your offer ${money(numv(offer, 'price'))} is waiting for the seller.',
            'உங்கள் ${money(numv(offer, 'price'))} விற்பவரின் பதிலுக்குக் காத்திருக்கிறது.',
          ),
          action: bi('Withdraw', 'திரும்பப் பெறு'),
          onAction: () => ShopOffers.withdraw(ShopOffers.idFor(productId)),
        );
      }
      if (ShopOffers.usable(offer)) {
        return _line(
          context,
          CupertinoIcons.checkmark_seal_fill,
          bi(
            'Offer accepted: buy one at ${money(numv(offer, 'price'))} within $shopOfferHours hours.',
            'ஏற்கப்பட்டது: $shopOfferHours மணி நேரத்தில் ${money(numv(offer, 'price'))}-க்கு வாங்கலாம்.',
          ),
          color: Ink.greenText,
          action: bi('Buy', 'வாங்கு'),
          onAction: () => push(
            context,
            CheckoutScreen(
              id: productId,
              product: {...product, 'price': numv(offer, 'price')},
              offerId: ShopOffers.idFor(productId),
            ),
          ),
        );
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _make(context),
          icon: const Icon(CupertinoIcons.tag),
          label: Text(
            status == 'declined'
                ? bi(
                    'Offer declined · make another',
                    'ஏற்கவில்லை · மீண்டும் கேள்',
                  )
                : bi('Make an offer', 'விலை கேள்'),
          ),
        ),
      );
    },
  );

  Widget _line(
    BuildContext context,
    IconData icon,
    String text, {
    Color? color,
    required String action,
    required VoidCallback onAction,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Glass(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Icon(icon, color: color ?? Ink.violetDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color ?? Ink.body,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );
}

/// The seller's side: offers on this item, to accept or decline.
class SellerOffers extends StatelessWidget {
  final String productId;
  const SellerOffers({super.key, required this.productId});

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
    stream: ShopOffers.forProduct(productId),
    builder: (context, snap) {
      final docs = snap.data ?? const [];
      if (docs.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _shopSection(bi('Offers', 'விலைக் கோரிக்கைகள்')),
          for (final d in docs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Glass(
                radius: 18,
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${txt(d.data(), 'buyerName')} · ${money(numv(d.data(), 'price'))}${txt(d.data(), 'status') == 'accepted' ? ' · ${bi('accepted', 'ஏற்கப்பட்டது')}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (txt(d.data(), 'status') == 'pending') ...[
                      TextButton(
                        onPressed: () => ShopOffers.answer(d.id, false),
                        child: Text(
                          bi('Decline', 'மறு'),
                          style: TextStyle(color: Ink.redText),
                        ),
                      ),
                      TextButton(
                        style: liquidActionStyle(primary: true),
                        onPressed: () => ShopOffers.answer(d.id, true),
                        child: Text(bi('Accept', 'ஏற்று')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

// ------------------------------------------------------------ questions --

class ShopQuestions {
  const ShopQuestions._();

  static CollectionReference<Map<String, dynamic>> get questions =>
      FirebaseFirestore.instance.collection('shop_questions');

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> of(
    String productId,
  ) => questions
      .where('productId', isEqualTo: productId)
      .limit(100)
      .snapshots()
      .map((s) {
        final docs = s.docs.toList();
        int at(QueryDocumentSnapshot<Map<String, dynamic>> d) {
          final t = d.data()['createdAt'];
          return t is Timestamp ? t.millisecondsSinceEpoch : 1 << 62;
        }

        docs.sort((a, b) => at(a).compareTo(at(b)));
        return docs;
      });

  static Future<void> ask(
    String productId,
    Map<String, dynamic> product,
    String text,
  ) async => questions.add({
    'productId': productId,
    'sellerUid': txt(product, 'sellerUid'),
    'title': txt(product, 'title'),
    'uid': signedInUid,
    'name': await MarketService.myName(),
    'text': text.trim(),
    'answer': '',
    'createdAt': FieldValue.serverTimestamp(),
  });

  static Future<void> answer(String id, String text) =>
      questions.doc(id).update({
        'answer': text.trim(),
        'answeredAt': FieldValue.serverTimestamp(),
      });

  static Future<void> delete(String id) => questions.doc(id).delete();
}

/// Public questions on an item: anyone asks, the seller answers for all.
class ProductQuestions extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> product;
  const ProductQuestions({
    super.key,
    required this.productId,
    required this.product,
  });

  @override
  State<ProductQuestions> createState() => _ProductQuestionsState();
}

class _ProductQuestionsState extends State<ProductQuestions> {
  final _text = TextEditingController();
  bool _busy = false;

  bool get _seller => txt(widget.product, 'sellerUid') == signedInUid;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final text = _text.text.trim();
    if (_busy || text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ShopQuestions.ask(widget.productId, widget.product, text);
      _text.clear();
    } catch (e) {
      if (mounted) snack(context, accountError(e), tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answer(String id, String current) async {
    final c = TextEditingController(text: current);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(bi('Answer', 'பதில்')),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 500,
          maxLines: 4,
          minLines: 2,
          decoration: InputDecoration(
            labelText: bi('Everyone will see it', 'அனைவரும் பார்ப்பார்கள்'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ui('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(bi('Post', 'பதிவிடு')),
          ),
        ],
      ),
    );
    c.dispose();
    if (text == null || text.isEmpty) return;
    try {
      await ShopQuestions.answer(id, text);
    } catch (e) {
      if (mounted) snack(context, accountError(e), tone: SnackTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ShopService.available) return const SizedBox.shrink();
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: ShopQuestions.of(widget.productId),
      builder: (context, snap) {
        final docs = snap.data ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _shopSection(
              docs.isEmpty
                  ? bi('Questions', 'கேள்விகள்')
                  : bi(
                      'Questions (${docs.length})',
                      'கேள்விகள் (${docs.length})',
                    ),
              note: bi(
                'Public: everyone sees questions and answers.',
                'பொது: கேள்வி-பதில்களை அனைவரும் பார்ப்பார்கள்.',
              ),
            ),
            for (final d in docs) _tile(d),
            if (!_seller)
              TextField(
                controller: _text,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: fieldStyle(
                  bi('Ask the seller', 'விற்பவரிடம் கேள்'),
                  suffix: IconButton(
                    tooltip: bi('Ask', 'கேள்'),
                    onPressed: _busy ? null : _ask,
                    icon: Icon(
                      CupertinoIcons.arrow_up_circle_fill,
                      color: Ink.violetDeep,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _tile(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final q = d.data();
    final mine = txt(q, 'uid') == signedInUid;
    final answer = txt(q, 'answer');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txt(q, 'name'),
                    style: TextStyle(color: Ink.muted, fontSize: 13),
                  ),
                  Text(
                    txt(q, 'text'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (answer.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${bi('Seller', 'விற்பவர்')}: ',
                              style: TextStyle(
                                color: Ink.violetDeep,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: answer),
                          ],
                        ),
                      ),
                    )
                  else if (_seller)
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => _answer(d.id, ''),
                      child: Text(bi('Answer', 'பதில் சொல்')),
                    )
                  else
                    Text(
                      bi(
                        'Waiting for the seller',
                        'விற்பவரின் பதிலுக்குக் காத்திருக்கிறது',
                      ),
                      style: TextStyle(color: Ink.muted, fontSize: 13),
                    ),
                ],
              ),
            ),
            if (mine || _seller)
              IconButton(
                tooltip: bi('Delete', 'நீக்கு'),
                onPressed: () => ShopQuestions.delete(d.id),
                icon: Icon(CupertinoIcons.trash, size: 18, color: Ink.faint),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- sorting --

const shopSorts = <ShopChoice>[
  ('new', 'Newest', 'புதியவை'),
  ('low', 'Price: low to high', 'விலை: குறைவு முதல்'),
  ('high', 'Price: high to low', 'விலை: அதிகம் முதல்'),
];

/// Sorts loaded products; [available] keeps only those on sale now.
List<T> sortShopProducts<T>(
  List<T> docs,
  Map<String, dynamic> Function(T) data, {
  required String sort,
  bool available = false,
}) {
  final out = [
    for (final d in docs)
      if (!available ||
          (toInt(data(d)['stock']) > 0 && txt(data(d), 'status') == 'active'))
        d,
  ];
  int at(T d) {
    final t = data(d)['createdAt'];
    return t is Timestamp ? t.millisecondsSinceEpoch : 0;
  }

  switch (sort) {
    case 'low':
      out.sort(
        (a, b) => numv(data(a), 'price').compareTo(numv(data(b), 'price')),
      );
    case 'high':
      out.sort(
        (a, b) => numv(data(b), 'price').compareTo(numv(data(a), 'price')),
      );
    default:
      out.sort((a, b) => at(b).compareTo(at(a)));
  }
  return out;
}
