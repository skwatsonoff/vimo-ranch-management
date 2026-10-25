part of 'main.dart';

/// Reviews, Mercari style. When a sale finishes both people rate each
/// other: five stars are already filled in (lower them only if something
/// went wrong) and a comment is optional. Reviews are public on the
/// profile; whoever wrote one can delete it, the person it is about
/// cannot.
class ShopReviews {
  const ShopReviews._();

  static CollectionReference<Map<String, dynamic>> get reviews =>
      FirebaseFirestore.instance.collection('shop_reviews');

  /// Everything said about [uid], newest first.
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> about(
    String uid,
  ) => reviews
      .where('aboutUid', isEqualTo: uid)
      .limit(300)
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

  /// Average stars and count.
  static (double, int) summary(Iterable<Map<String, dynamic>> rows) {
    var total = 0, count = 0;
    for (final r in rows) {
      final stars = toInt(r['stars']);
      if (stars < 1 || stars > 5) continue;
      total += stars;
      count++;
    }
    return (count == 0 ? 0 : total / count, count);
  }

  static Future<void> delete(String id) => reviews.doc(id).delete();
}

/// Stars of a rating, older good/not-good ratings read as 5 or 1.
int ratingStars(Map<String, dynamic> rating) {
  final stars = toInt(rating['stars']);
  if (stars >= 1 && stars <= 5) return stars;
  return switch (txt(rating, 'score')) {
    'good' => 5,
    'bad' => 1,
    _ => 0,
  };
}

/// Five stars, filled to [value] (halves shown for averages).
class StarRow extends StatelessWidget {
  final double value;
  final double size;
  const StarRow({super.key, required this.value, this.size = 16});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i
                ? CupertinoIcons.star_fill
                : value >= i - .5
                ? CupertinoIcons.star_lefthalf_fill
                : CupertinoIcons.star,
            size: size,
            color: Ink.orange,
          ),
      ],
    ),
  );
}

/// Tap a star to set the rating. Starts full; swipe or tap lower.
class StarPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const StarPicker({super.key, required this.value, required this.onChanged});

  static const _words = <(String, String)>[
    ('Poor', 'மோசம்'),
    ('Not good', 'சரியில்லை'),
    ('Okay', 'பரவாயில்லை'),
    ('Good', 'நல்லது'),
    ('Excellent', 'மிக நன்று'),
  ];

  @override
  Widget build(BuildContext context) => Semantics(
    label: bi('Rating', 'மதிப்பீடு'),
    value: bi('$value of 5 stars', '5-ல் $value நட்சத்திரம்'),
    increasedValue: value < 5 ? '${value + 1}' : null,
    decreasedValue: value > 1 ? '${value - 1}' : null,
    onIncrease: value < 5 ? () => onChanged(value + 1) : null,
    onDecrease: value > 1 ? () => onChanged(value - 1) : null,
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i == value) return;
                  selectionFeedback();
                  onChanged(i);
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AnimatedScale(
                    scale: i <= value ? 1 : .86,
                    duration: Motion.reduced(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      i <= value
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      size: 40,
                      color: Ink.orange,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          bi(_words[value - 1].$1, _words[value - 1].$2),
          style: TextStyle(color: Ink.muted, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// "★★★★★ 4.8 · 23 reviews" on a profile; opens every review.
class ReviewSummary extends StatelessWidget {
  final String uid;
  final String name;
  const ReviewSummary({super.key, required this.uid, required this.name});

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
    stream: ShopReviews.about(uid),
    builder: (context, snap) {
      final (average, count) = ShopReviews.summary(
        (snap.data ?? const []).map((d) => d.data()),
      );
      if (count == 0) return const SizedBox.shrink();
      return Semantics(
        button: true,
        label: bi(
          'Rated ${average.toStringAsFixed(1)} of 5 from $count reviews',
          '$count மதிப்பீடுகளில் 5-க்கு ${average.toStringAsFixed(1)}',
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => push(context, ReviewsScreen(uid: uid, name: name)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StarRow(value: average),
                  const SizedBox(width: 6),
                  Text(
                    '${average.toStringAsFixed(1)} · ${bi('$count reviews', '$count மதிப்பீடுகள்')}',
                    style: TextStyle(
                      color: Ink.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: Ink.faint,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ReviewsScreen extends StatefulWidget {
  final String uid;
  final String name;
  const ReviewsScreen({super.key, required this.uid, required this.name});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  /// 0 all, 1 as a seller (written by buyers), 2 as a buyer.
  int _filter = 0;

  Future<void> _delete(String id) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(bi('Delete your review?', 'உங்கள் மதிப்பீட்டை நீக்கவா?')),
        content: Text(
          bi(
            'It disappears from this profile. This cannot be undone.',
            'இந்த ப்ரொஃபைலில் இருந்து மறையும். திரும்பப் பெற முடியாது.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ui('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              bi('Delete', 'நீக்கு'),
              style: TextStyle(color: Ink.redText),
            ),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ShopReviews.delete(id);
      if (mounted) {
        snack(context, bi('Review deleted', 'மதிப்பீடு நீக்கப்பட்டது'));
      }
    } catch (e) {
      if (mounted) snack(context, accountError(e), tone: SnackTone.error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(bi('Reviews', 'மதிப்பீடுகள்')),
    ),
    body: Shell(
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: ShopReviews.about(widget.uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(accountError(snap.error!)));
          }
          final all = snap.data;
          if (all == null) return const SkeletonList(rows: 4);
          final (average, count) = ShopReviews.summary(
            all.map((d) => d.data()),
          );
          final shown = [
            for (final d in all)
              if (_filter == 0 ||
                  (_filter == 1 && txt(d.data(), 'role') == 'buyer') ||
                  (_filter == 2 && txt(d.data(), 'role') == 'seller'))
                d,
          ];
          final perStar = List.filled(6, 0);
          for (final d in all) {
            final s = toInt(d.data()['stars']);
            if (s >= 1 && s <= 5) perStar[s]++;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Glass(
                radius: 24,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Column(
                      children: [
                        Text(
                          count == 0 ? '–' : average.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                        StarRow(value: average, size: 14),
                        const SizedBox(height: 4),
                        Text(
                          bi('$count reviews', '$count மதிப்பீடுகள்'),
                          style: TextStyle(color: Ink.muted, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          for (var s = 5; s >= 1; s--)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    child: Text(
                                      '$s',
                                      style: TextStyle(
                                        color: Ink.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: count == 0
                                            ? 0
                                            : perStar[s] / count,
                                        minHeight: 6,
                                        color: Ink.orange,
                                        backgroundColor: Ink.lavender,
                                      ),
                                    ),
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
              const SizedBox(height: 16),
              LiquidSegmentBar(
                labels: [
                  bi('All', 'அனைத்தும்'),
                  bi('As seller', 'விற்பவராக'),
                  bi('As buyer', 'வாங்குபவராக'),
                ],
                index: _filter,
                onChanged: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    bi('No reviews yet.', 'இன்னும் மதிப்பீடுகள் இல்லை.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Ink.muted),
                  ),
                ),
              for (final d in shown) _tile(d),
            ],
          );
        },
      ),
    ),
  );

  Widget _tile(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final r = d.data();
    final mine = txt(r, 'byUid') == signedInUid;
    final stamp = r['createdAt'];
    final date = stamp is Timestamp
        ? () {
            final t = stamp.toDate().toLocal();
            return '${t.day}/${t.month}/${t.year}';
          }()
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StarRow(value: toInt(r['stars']).toDouble()),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    date,
                    style: TextStyle(color: Ink.muted, fontSize: 13),
                  ),
                ),
                if (mine)
                  IconButton(
                    tooltip: bi('Delete my review', 'என் மதிப்பீட்டை நீக்கு'),
                    onPressed: () => _delete(d.id),
                    icon: Icon(
                      CupertinoIcons.trash,
                      size: 20,
                      color: Ink.redText,
                    ),
                  ),
              ],
            ),
            if (txt(r, 'text').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(
                  txt(r, 'text'),
                  style: const TextStyle(fontSize: 16, height: 1.35),
                ),
              ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () =>
                  push(context, SocialProfileScreen(uid: txt(r, 'byUid'))),
              child: Text(
                '${txt(r, 'byName')} · ${txt(r, 'role') == 'buyer' ? bi('bought', 'வாங்கினார்') : bi('sold', 'விற்றார்')} ${txt(r, 'title')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Ink.violetDeep, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
