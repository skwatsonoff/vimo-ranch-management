part of 'main.dart';

// =============================================================================
//  Product page, checkout (Mercari's purchase confirmation) and orders.
// =============================================================================

/// Swipeable photos with page dots; loads the full photos after the cover.
class _ProductPhotos extends StatefulWidget {
  final String id;
  final Map<String, dynamic> product;
  const _ProductPhotos({required this.id, required this.product});

  @override
  State<_ProductPhotos> createState() => _ProductPhotosState();
}

class _ProductPhotosState extends State<_ProductPhotos> {
  late final Future<List<String>> _photos = ShopService.photos(
    widget.id,
    toInt(widget.product['photoCount']),
  );
  int _page = 0;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _photos,
    builder: (context, snap) {
      final photos = snap.data?.isNotEmpty == true
          ? snap.data!
          : [txt(widget.product, 'cover')];
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 1,
              child: PageView.builder(
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () {
                    final image = _shopImage(photos[i]);
                    if (image != null) {
                      push(
                        context,
                        SocialPhotoViewer(image: image, heroTag: 'p$i'),
                      );
                    }
                  },
                  child: Semantics(
                    image: true,
                    label: bi(
                      'Photo ${i + 1} of ${photos.length}',
                      'படம் ${i + 1} / ${photos.length}',
                    ),
                    child: _shopImage(photos[i]) == null
                        ? ColoredBox(color: Ink.lavender)
                        : Image(
                            image: _shopImage(photos[i])!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (photos.length > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < photos.length; i++)
                  AnimatedContainer(
                    duration: Motion.short,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: i == _page ? Ink.violetDeep : Ink.fillStrong,
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

Widget _detailRow(String label, String value) => value.trim().isEmpty
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: TextStyle(color: Ink.muted)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );

class ProductScreen extends StatelessWidget {
  final String id;
  final Map<String, dynamic>? initial;
  const ProductScreen({super.key, required this.id, this.initial});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ShopService.products.doc(id).snapshots(),
        builder: (context, snap) {
          final p = snap.hasData ? snap.data!.data() : initial;
          if (p == null) {
            return Scaffold(
              appBar: AppBar(leading: const _BackButton()),
              body: snap.hasData
                  ? StatePanel(
                      icon: CupertinoIcons.cube_box,
                      title: bi('Product removed', 'பொருள் நீக்கப்பட்டது'),
                      message: bi(
                        'The seller no longer lists this product.',
                        'விற்பவர் இதை இனி விற்கவில்லை.',
                      ),
                    )
                  : const SkeletonList(rows: 3),
            );
          }
          return _ProductBody(id: id, p: p);
        },
      );
}

class _ProductBody extends StatelessWidget {
  final String id;
  final Map<String, dynamic> p;
  const _ProductBody({required this.id, required this.p});

  @override
  Widget build(BuildContext context) {
    final own = txt(p, 'sellerUid') == signedInUid;
    final price = numv(p, 'price');
    final mrp = numv(p, 'mrp');
    final off = shopDiscount(price, mrp);
    final stock = toInt(p['stock']);
    final active = txt(p, 'status') == 'active';
    final delivery = asMap(p['delivery']);
    final methods = ((delivery['methods'] as List?) ?? const [])
        .map((e) => '$e')
        .toList();
    final features = ((p['features'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final unit = [
      shopLabel(productUnits, txt(p, 'unit', 'piece')),
      if (txt(p, 'unitSize').isNotEmpty) txt(p, 'unitSize'),
    ].join(' · ');
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      appBar: AppBar(
        leading: const _BackButton(),
        title: Text(
          txt(p, 'title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          LikeButton(productId: id, product: p),
          if (own)
            IconButton(
              tooltip: bi('Edit product', 'பொருளைத் திருத்து'),
              icon: const Icon(CupertinoIcons.pencil),
              onPressed: () async {
                final result = await push<String>(
                  context,
                  ProductEditorScreen(productId: id, product: p),
                );
                if (result == 'deleted' && context.mounted) {
                  Navigator.of(context).maybePop();
                }
              },
            ),
        ],
      ),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            _ProductPhotos(id: id, product: p),
            const SizedBox(height: 16),
            Text(
              txt(p, 'title'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(
                  money(price),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Ink.deepPurple,
                  ),
                ),
                if (off > 0) ...[
                  Text(
                    'MRP ${money(mrp)}',
                    style: TextStyle(
                      color: Ink.muted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  Text(
                    '$off% ${bi('off', 'தள்ளுபடி')}',
                    style: TextStyle(
                      color: Ink.greenText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            Text(
              [
                unit,
                if (toInt(p['gstPercent']) > 0)
                  bi(
                    'incl. GST ${toInt(p['gstPercent'])}%',
                    'GST ${toInt(p['gstPercent'])}% உட்பட',
                  ),
              ].join(' · '),
              style: TextStyle(color: Ink.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ProductPill(
                  icon: CupertinoIcons.sparkles,
                  text: shopLabel(shopConditions, txt(p, 'condition', 'new')),
                ),
                _ProductPill(
                  icon: CupertinoIcons.car_detailed,
                  text: shopDeliverySummary(p),
                ),
                _ProductPill(
                  icon: CupertinoIcons.cube_box,
                  text: stock <= 0
                      ? bi('Sold out', 'விற்றுத் தீர்ந்தது')
                      : stock <= 5
                      ? bi('Only $stock left', '$stock மட்டும் உள்ளது')
                      : bi('In stock', 'கையிருப்பில் உள்ளது'),
                  color: stock <= 0 ? Ink.redText : null,
                ),
              ],
            ),
            if (!own && active && stock > 0 && ShopService.available)
              OfferPanel(productId: id, product: p),
            if (own) SellerOffers(productId: id),
            if (features.isNotEmpty) ...[
              _shopSection(bi('Key features', 'முக்கிய அம்சங்கள்')),
              for (final f in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          size: 16,
                          color: Ink.greenText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f)),
                    ],
                  ),
                ),
            ],
            if (txt(p, 'description').isNotEmpty) ...[
              _shopSection(bi('Description', 'விவரம்')),
              Text(txt(p, 'description'), style: const TextStyle(height: 1.45)),
            ],
            _shopSection(bi('Delivery & returns', 'டெலிவரி & திருப்புதல்')),
            Glass(
              radius: 20,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _detailRow(
                    bi('How you get it', 'பெறும் முறை'),
                    methods
                        .map((m) => shopLabel(shopDeliveryMethods, m))
                        .join('\n'),
                  ),
                  _detailRow(
                    bi('Delivery fee', 'டெலிவரி கட்டணம்'),
                    shopDeliverySummary(p),
                  ),
                  if (!(methods.length == 1 && methods.first == 'pickup'))
                    _detailRow(
                      bi('Sends within', 'அனுப்பும் காலம்'),
                      shopLabel(shopShipDays, txt(delivery, 'days', '1-2')),
                    ),
                  _detailRow(bi('From', 'இருந்து'), txt(delivery, 'shipsFrom')),
                  _detailRow(
                    bi('Returns', 'திருப்புதல்'),
                    shopLabel(shopReturns, txt(p, 'returns', 'none')),
                  ),
                ],
              ),
            ),
            _shopSection(bi('Details', 'விவரங்கள்')),
            Glass(
              radius: 20,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _detailRow(
                    bi('Category', 'வகை'),
                    shopLabel(shopCategories, txt(p, 'category')),
                  ),
                  _detailRow(bi('Brand', 'பிராண்ட்'), txt(p, 'brand')),
                  _detailRow(bi('Sold per', 'அலகு'), unit),
                  _detailRow(
                    bi('Weight', 'எடை'),
                    toInt(p['weightGrams']) > 0
                        ? '${toInt(p['weightGrams'])} g'
                        : '',
                  ),
                  _detailRow(
                    bi('Country of origin', 'தயாரிப்பு நாடு'),
                    txt(p, 'origin'),
                  ),
                  _detailRow(
                    bi('Manufacturer / packer', 'தயாரிப்பாளர்'),
                    txt(p, 'manufacturer'),
                  ),
                  _detailRow('SKU', txt(p, 'sku')),
                  _detailRow('HSN', txt(p, 'hsn')),
                ],
              ),
            ),
            ProductQuestions(productId: id, product: p),
            _shopSection(bi('Seller', 'விற்பவர்')),
            _SellerCard(uid: txt(p, 'sellerUid'), name: txt(p, 'sellerName')),
            const SizedBox(height: 12),
            Text(
              bi(
                'VIMO does not hold money. You pay the seller directly, in cash or by UPI, as you choose at checkout.',
                'VIMO பணத்தை வைத்திருப்பதில்லை. செக்அவுட்டில் தேர்வு செய்தபடி விற்பவருக்கு நேரடியாக பணம் அல்லது UPI மூலம் செலுத்துவீர்கள்.',
              ),
              style: TextStyle(color: Ink.muted, fontSize: 13),
            ),
          ],
        ),
      ),
      bottomNavigationBar: own
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: LiquidButton(
                  label: !active
                      ? bi('Not available now', 'இப்போது கிடைக்காது')
                      : stock <= 0
                      ? bi('Sold out', 'விற்றுத் தீர்ந்தது')
                      : bi(
                          'Buy now · ${money(price)}',
                          'இப்போது வாங்கு · ${money(price)}',
                        ),
                  icon: CupertinoIcons.bag_fill,
                  onPressed: !active || stock <= 0 || !ShopService.available
                      ? null
                      : () => push(context, CheckoutScreen(id: id, product: p)),
                ),
              ),
            ),
    );
  }
}

class _ProductPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _ProductPill({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: ShapeDecoration(
      shape: const StadiumBorder(),
      color: Ink.surface,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color ?? Ink.violetDeep),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color ?? Ink.body,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

/// The seller (or buyer) as a row: photo, name, profile and message.
class _SellerCard extends StatelessWidget {
  final String uid;
  final String name;
  const _SellerCard({required this.uid, required this.name});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('profiles')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? const <String, dynamic>{};
          final shown = txt(data, 'displayName', name);
          return Glass(
            radius: 20,
            padding: const EdgeInsets.all(12),
            onTap: () => push(context, SocialProfileScreen(uid: uid)),
            child: Row(
              children: [
                profileAvatar(txt(data, 'photo'), radius: 24, label: shown),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shown,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      if (txt(data, 'username').isNotEmpty)
                        Text(
                          '@${txt(data, 'username')}',
                          style: TextStyle(color: Ink.muted, fontSize: 13),
                        ),
                      ReviewSummary(uid: uid, name: shown),
                    ],
                  ),
                ),
                if (uid != signedInUid)
                  IconButton(
                    tooltip: bi('Message', 'செய்தி'),
                    icon: Icon(
                      CupertinoIcons.chat_bubble_2_fill,
                      color: Ink.violetDeep,
                    ),
                    onPressed: () async {
                      try {
                        final chat = await DirectChatService.open(uid);
                        if (context.mounted) {
                          await push(
                            context,
                            DirectChatScreen(chatId: chat, peer: uid),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          snack(
                            context,
                            accountError(e),
                            tone: SnackTone.error,
                          );
                        }
                      }
                    },
                  ),
              ],
            ),
          );
        },
      );
}

// -----------------------------------------------------------------------------
//  Checkout: confirm item, quantity, delivery, address and payment
// -----------------------------------------------------------------------------

class CheckoutScreen extends StatefulWidget {
  final String id;
  final Map<String, dynamic> product;

  /// An accepted offer: one item at the offered price.
  final String offerId;
  const CheckoutScreen({
    super.key,
    required this.id,
    required this.product,
    this.offerId = '',
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late final Map<String, dynamic> _p = widget.product;
  late final List<String> _methods = [
    for (final m in (asMap(_p['delivery'])['methods'] as List?) ?? ['pickup'])
      '$m',
  ];
  late String _method = _methods.first;
  String _payment = 'cod';
  int _qty = 1;
  bool _busy = false;
  late final Map<String, dynamic> _saved = asMap(
    settingValue(accountSetting('shopAddress'), {}),
  );
  late final _name = TextEditingController(
    text: txt(_saved, 'name', accountFullName),
  );
  late final _phone = TextEditingController(
    text: txt(_saved, 'phone', accountPhone),
  );
  late final _line = TextEditingController(text: txt(_saved, 'line'));
  late final _city = TextEditingController(
    text: txt(_saved, 'city', txt(accountDetails, 'place')),
  );
  late final _pincode = TextEditingController(text: txt(_saved, 'pincode'));
  final _note = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _phone, _line, _city, _pincode, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _needsAddress => _method != 'pickup';

  Future<void> _place() async {
    if (_busy) return;
    String? problem;
    if (_needsAddress) {
      if (_name.text.trim().isEmpty) {
        problem = bi('Enter the receiver’s name', 'பெறுபவர் பெயரை உள்ளிடவும்');
      } else if (!RegExp(
        r'^\+?[0-9]{10,13}$',
      ).hasMatch(_phone.text.replaceAll(' ', ''))) {
        problem = bi(
          'Enter a 10-digit mobile number',
          '10 இலக்க மொபைல் எண்ணை உள்ளிடவும்',
        );
      } else if (_line.text.trim().length < 5) {
        problem = bi(
          'Enter the house and street',
          'வீடு, தெரு விவரத்தை உள்ளிடவும்',
        );
      } else if (_city.text.trim().isEmpty) {
        problem = bi('Enter the town or city', 'ஊரை உள்ளிடவும்');
      } else if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(_pincode.text.trim())) {
        problem = bi(
          'Enter a 6-digit PIN code',
          '6 இலக்க PIN குறியீட்டை உள்ளிடவும்',
        );
      }
    }
    if (problem != null) {
      snack(context, problem, tone: SnackTone.error);
      return;
    }
    // Market is local: buying needs location allowed.
    if (!await MarketLocation.require(context) || !mounted) return;
    if (!await VimoTeam.marketAllowed(context) || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = await ShopService.placeOrder(
        productId: widget.id,
        product: _p,
        quantity: _qty,
        deliveryMethod: _method,
        payment: _payment,
        address: {
          'name': _name.text.trim(),
          'phone': _phone.text.replaceAll(' ', ''),
          'line': _line.text.trim(),
          'city': _city.text.trim(),
          'pincode': _pincode.text.trim(),
        },
        note: _note.text,
        offerId: widget.offerId,
      );
      if (!mounted) return;
      UiSound.play(UiSoundKind.success);
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushReplacement(
        LiquidRoute<void>(
          builder: (_) => OrderScreen(id: id, justPlaced: true),
        ),
      );
    } catch (error) {
      if (mounted) {
        snack(
          context,
          error is FirebaseException && error.code == 'permission-denied'
              ? bi(
                  'The price or stock changed. Go back and check the product again.',
                  'விலை அல்லது கையிருப்பு மாறியுள்ளது. பொருளை மீண்டும் பார்க்கவும்.',
                )
              : accountError(error),
          tone: SnackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = numv(_p, 'price');
    final fee = shopDeliveryFee(_p, _method);
    // The most this buyer can take: the stock, within the seller's limit.
    final most = widget.offerId.isNotEmpty
        ? 1
        : _p['maxPerOrder'] == null
        ? 1
        : toInt(_p['maxPerOrder']);
    final stock = math.max(1, math.min(toInt(_p['stock']), math.max(1, most)));
    final total = price * _qty + fee;
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      appBar: AppBar(
        leading: const _BackButton(),
        title: Text(bi('Confirm purchase', 'வாங்குவதை உறுதிசெய்')),
      ),
      body: Shell(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Glass(
              radius: 20,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox.square(
                      dimension: 72,
                      child: _shopImage(txt(_p, 'cover')) == null
                          ? ColoredBox(color: Ink.lavender)
                          : Image(
                              image: _shopImage(txt(_p, 'cover'))!,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          txt(_p, 'title'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${money(price)} · ${shopLabel(shopConditions, txt(_p, 'condition', 'new'))}',
                          style: TextStyle(color: Ink.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (stock > 1) ...[
              _shopSection(bi('Quantity', 'எண்ணிக்கை')),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: bi('Fewer', 'குறைவு'),
                    onPressed: _qty <= 1
                        ? null
                        : () {
                            selectionFeedback();
                            setState(() => _qty--);
                          },
                    icon: const Icon(CupertinoIcons.minus),
                  ),
                  Expanded(
                    child: Text(
                      '$_qty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: bi('More', 'அதிகம்'),
                    onPressed: _qty >= stock
                        ? null
                        : () {
                            selectionFeedback();
                            setState(() => _qty++);
                          },
                    icon: const Icon(CupertinoIcons.plus),
                  ),
                ],
              ),
              Text(
                bi('$stock available', '$stock கிடைக்கும்'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Ink.muted, fontSize: 13),
              ),
            ],
            _shopSection(bi('How you get it', 'பெறும் முறை')),
            _ChoiceChips(
              choices: [
                for (final c in shopDeliveryMethods)
                  if (_methods.contains(c.$1)) c,
              ],
              selected: {_method},
              onTap: (v) => setState(() => _method = v),
            ),
            if (_needsAddress) ...[
              _shopSection(bi('Delivery address', 'டெலிவரி முகவரி')),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: fieldStyle(bi('Receiver’s name', 'பெறுபவர் பெயர்')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: fieldStyle(bi('Mobile number', 'மொபைல் எண்')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _line,
                minLines: 2,
                maxLines: 3,
                autofillHints: const [AutofillHints.fullStreetAddress],
                decoration: fieldStyle(
                  bi('House, street, landmark', 'வீடு, தெரு, அடையாளம்'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _city,
                      autofillHints: const [AutofillHints.addressCity],
                      decoration: fieldStyle(bi('Town / city', 'ஊர்')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _pincode,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.postalCode],
                      decoration: fieldStyle(bi('PIN code', 'PIN')),
                    ),
                  ),
                ],
              ),
            ],
            _shopSection(
              bi('Payment', 'பணம் செலுத்துதல்'),
              note: bi(
                'You pay the seller directly. VIMO does not handle money.',
                'விற்பவருக்கு நேரடியாகச் செலுத்துவீர்கள். VIMO பணத்தைக் கையாள்வதில்லை.',
              ),
            ),
            _ChoiceChips(
              choices: shopPayments,
              selected: {_payment},
              onTap: (v) => setState(() => _payment = v),
            ),
            if (_payment == 'upi')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  bi(
                    'The seller’s UPI ID appears in your order once they accept. Pay then.',
                    'விற்பவர் ஏற்றதும் அவரின் UPI ID ஆர்டரில் தெரியும். அப்போது செலுத்தவும்.',
                  ),
                  style: TextStyle(color: Ink.muted, fontSize: 13),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 300,
              maxLines: 2,
              decoration: fieldStyle(
                bi(
                  'Note to seller (optional)',
                  'விற்பவருக்குக் குறிப்பு (விருப்பம்)',
                ),
              ),
            ),
            _shopSection(bi('Summary', 'சுருக்கம்')),
            Glass(
              radius: 20,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _sumRow(
                    bi('Item total', 'பொருள் மொத்தம்'),
                    money(price * _qty),
                  ),
                  _sumRow(
                    bi('Delivery', 'டெலிவரி'),
                    fee > 0 ? money(fee) : bi('Free', 'இலவசம்'),
                  ),
                  const Divider(height: 20),
                  _sumRow(
                    bi('Total to pay', 'செலுத்த வேண்டியது'),
                    money(total),
                    strong: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            LiquidButton(
              label: bi(
                'Place order · ${money(total)}',
                'ஆர்டர் செய் · ${money(total)}',
              ),
              icon: CupertinoIcons.checkmark_seal_fill,
              busy: _busy,
              onPressed: _place,
            ),
            const SizedBox(height: 8),
            Text(
              bi(
                'The seller confirms the order. Before it is sent, you can ask them to cancel.',
                'விற்பவர் ஆர்டரை உறுதிசெய்வார். அனுப்பும் முன் ரத்து செய்ய அவரிடம் கேட்கலாம்.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: Ink.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _sumRow(String label, String value, {bool strong = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
            fontSize: strong ? 17 : 15,
          ),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          fontSize: strong ? 19 : 15,
        ),
      ),
    ],
  ),
);

// -----------------------------------------------------------------------------
//  Orders
// -----------------------------------------------------------------------------

class OrdersScreen extends StatefulWidget {
  final bool selling;
  const OrdersScreen({super.key, this.selling = false});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late int _tab = widget.selling ? 1 : 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ink.canvasTop,
    appBar: AppBar(
      leading: const _BackButton(),
      title: Text(bi('My orders', 'என் ஆர்டர்கள்')),
      actions: [
        IconButton(
          tooltip: bi('Help · VIMO Team', 'உதவி · VIMO Team'),
          icon: Icon(CupertinoIcons.question_circle, color: Ink.violetDeep),
          onPressed: () => push(context, const VimoHelpScreen()),
        ),
      ],
    ),
    body: Shell(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: LiquidSegmentBar(
              labels: [bi('Buying', 'வாங்குதல்'), bi('Selling', 'விற்பனை')],
              index: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              key: ValueKey(_tab),
              stream: _tab == 0 ? ShopService.buying() : ShopService.selling(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return StatePanel(
                    icon: CupertinoIcons.exclamationmark_triangle,
                    title: bi(
                      'Could not load orders',
                      'ஆர்டர்களை ஏற்ற முடியவில்லை',
                    ),
                    message: accountError(snap.error!),
                  );
                }
                if (!snap.hasData) return const SkeletonList(rows: 4);
                final docs = [...snap.data!.docs]
                  ..sort(
                    (a, b) =>
                        (_marketTime(b.data()['updatedAt']) ?? DateTime(2000))
                            .compareTo(
                              _marketTime(a.data()['updatedAt']) ??
                                  DateTime(2000),
                            ),
                  );
                if (docs.isEmpty) {
                  return StatePanel(
                    icon: CupertinoIcons.bag,
                    title: _tab == 0
                        ? bi('No purchases yet', 'இன்னும் வாங்கவில்லை')
                        : bi('No sales yet', 'இன்னும் விற்கவில்லை'),
                    message: _tab == 0
                        ? bi(
                            'Find products in Market.',
                            'சந்தையில் பொருட்களைத் தேடுங்கள்.',
                          )
                        : bi(
                            'List products from your profile shop.',
                            'உங்கள் ப்ரொஃபைல் கடையில் பொருட்களைச் சேர்க்கவும்.',
                          ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _OrderRow(
                    id: docs[i].id,
                    order: docs[i].data(),
                    selling: _tab == 1,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _OrderRow extends StatelessWidget {
  final String id;
  final Map<String, dynamic> order;
  final bool selling;
  const _OrderRow({
    required this.id,
    required this.order,
    required this.selling,
  });

  @override
  Widget build(BuildContext context) {
    final status = txt(order, 'status');
    return Glass(
      radius: 20,
      padding: const EdgeInsets.all(12),
      onTap: () => push(context, OrderScreen(id: id)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.square(
              dimension: 56,
              child: _shopImage(txt(order, 'cover')) == null
                  ? ColoredBox(color: Ink.lavender)
                  : Image(
                      image: _shopImage(txt(order, 'cover'))!,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txt(order, 'title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${selling ? txt(order, 'buyerName') : txt(order, 'sellerName')} · ${money(numv(order, 'total'))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Ink.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            shopOrderStatusLabel(status),
            style: TextStyle(
              color: shopOrderStatusColor(status),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// One order: where it stands, what to do next, and its messages.
class OrderScreen extends StatelessWidget {
  final String id;
  final bool justPlaced;
  const OrderScreen({super.key, required this.id, this.justPlaced = false});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ShopService.orders.doc(id).snapshots(),
        builder: (context, snap) {
          final order = snap.data?.data();
          return Scaffold(
            backgroundColor: Ink.canvasTop,
            appBar: AppBar(
              leading: const _BackButton(),
              title: Text(bi('Order', 'ஆர்டர்')),
            ),
            body: order == null
                ? (snap.hasError
                      ? StatePanel(
                          icon: CupertinoIcons.exclamationmark_triangle,
                          title: bi(
                            'Could not open the order',
                            'ஆர்டரைத் திறக்க முடியவில்லை',
                          ),
                          message: accountError(snap.error!),
                        )
                      : const SkeletonList(rows: 3))
                : _OrderBody(id: id, order: order, justPlaced: justPlaced),
          );
        },
      );
}

class _OrderBody extends StatefulWidget {
  final String id;
  final Map<String, dynamic> order;
  final bool justPlaced;
  const _OrderBody({
    required this.id,
    required this.order,
    required this.justPlaced,
  });

  @override
  State<_OrderBody> createState() => _OrderBodyState();
}

class _OrderBodyState extends State<_OrderBody> {
  final _message = TextEditingController();
  bool _busy = false;

  Map<String, dynamic> get o => widget.order;
  bool get _seller => txt(o, 'sellerUid') == signedInUid;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) snack(context, done, tone: SnackTone.success);
    } catch (error) {
      if (mounted) {
        snack(
          context,
          error is FirebaseException && error.code == 'permission-denied'
              ? bi(
                  'That step is not possible now. The order may have changed.',
                  'இப்போது அந்தப் படி இயலாது. ஆர்டர் மாறியிருக்கலாம்.',
                )
              : error is StateError
              ? error.message
              : accountError(error),
          tone: SnackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _ask(
    String title,
    String label, {
    String initial = '',
    String note = '',
  }) async {
    final c = TextEditingController(text: initial);
    final field = TextField(
      controller: c,
      autofocus: true,
      maxLength: 200,
      decoration: InputDecoration(labelText: label),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(title),
        content: note.isEmpty
            ? field
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(note, style: TextStyle(color: Ink.muted)),
                  const SizedBox(height: 8),
                  field,
                ],
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
    return result;
  }

  /// Rate the other side, Mercari style: five stars already filled in,
  /// lowered only if something went wrong, plus an optional comment.
  Future<(int, String)?> _rate(String who) async {
    var stars = 5;
    final text = TextEditingController();
    final ok = await showAppleSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                bi('How was $who?', '$who எப்படி?'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              StarPicker(value: stars, onChanged: (v) => set(() => stars = v)),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                maxLength: 300,
                maxLines: 3,
                decoration: fieldStyle(
                  bi(
                    'Write a few words (optional)',
                    'சில வார்த்தைகள் எழுதுங்கள் (விருப்பம்)',
                  ),
                ),
              ),
              Text(
                bi(
                  'Shown on $who’s profile. You can delete it later.',
                  '$who-இன் ப்ரொஃபைலில் காட்டப்படும். பின்னர் நீக்கலாம்.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: Ink.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              LiquidButton(
                label: bi('Send rating', 'மதிப்பீட்டை அனுப்பு'),
                onPressed: () => Navigator.pop(sheet, true),
              ),
            ],
          ),
        ),
      ),
    );
    final comment = text.text;
    text.dispose();
    return ok == true ? (stars, comment) : null;
  }

  List<Widget> _actions(String status) {
    if (_busy) {
      return [const Center(child: CupertinoActivityIndicator())];
    }
    final buyer = txt(o, 'buyerName', bi('the buyer', 'வாங்குபவர்'));
    final seller = txt(o, 'sellerName', bi('the seller', 'விற்பவர்'));
    // An open request to cancel is answered before anything else moves.
    final asked = asMap(o['cancelRequest']);
    if (asked.isNotEmpty && const {'ordered', 'accepted'}.contains(status)) {
      return [_cancelRequestCard(asked)];
    }
    if (_seller && ShopService.canRestock(o)) {
      final qty = toInt(o['quantity']);
      return [
        GhostButton(
          label: bi('Put $qty back on sale', '$qty-ஐ மீண்டும் விற்பனைக்கு வை'),
          icon: CupertinoIcons.arrow_counterclockwise,
          onPressed: () => _run(
            () => ShopService.restock(widget.id, o),
            bi('Back in stock', 'மீண்டும் இருப்பில் உள்ளது'),
          ),
        ),
      ];
    }
    if (_seller) {
      switch (status) {
        case 'ordered':
          return [
            LiquidButton(
              label: bi('Accept order', 'ஆர்டரை ஏற்று'),
              icon: CupertinoIcons.checkmark_alt,
              onPressed: () async {
                var upi = '';
                if (txt(o, 'payment') == 'upi') {
                  final entered = await _ask(
                    bi('Your UPI ID', 'உங்கள் UPI ID'),
                    'name@bank',
                    initial: '${settingValue(accountSetting('shopUpi'), '')}',
                  );
                  if (entered == null) return;
                  if (!RegExp(
                    r'^[\w.\-]{2,}@[A-Za-z]{2,}$',
                  ).hasMatch(entered)) {
                    if (mounted) {
                      snack(
                        context,
                        bi(
                          'Enter a UPI ID like name@bank',
                          'name@bank போன்ற UPI ID உள்ளிடவும்',
                        ),
                        tone: SnackTone.error,
                      );
                    }
                    return;
                  }
                  upi = entered;
                  await setSetting(accountSetting('shopUpi'), upi);
                }
                await _run(
                  () => ShopService.accept(widget.id, o, upi: upi),
                  bi(
                    'Accepted. Send it within the time you promised.',
                    'ஏற்கப்பட்டது. சொன்ன நேரத்திற்குள் அனுப்பவும்.',
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _askCancelButton(),
          ];
        case 'accepted':
          return [
            LiquidButton(
              label: txt(o, 'deliveryMethod') == 'pickup'
                  ? bi('Ready for pickup', 'எடுத்துச் செல்லத் தயார்')
                  : bi('Mark as sent', 'அனுப்பியதாகக் குறி'),
              icon: CupertinoIcons.cube_box_fill,
              onPressed: () async {
                var tracking = '';
                if (txt(o, 'deliveryMethod') == 'courier') {
                  final entered = await _ask(
                    bi(
                      'Courier and tracking number',
                      'கூரியர் & டிராக்கிங் எண்',
                    ),
                    bi(
                      'e.g. India Post EE123456789IN',
                      'எ.கா. India Post EE123…',
                    ),
                  );
                  if (entered == null) return;
                  tracking = entered;
                }
                await _run(
                  () => ShopService.ship(widget.id, tracking),
                  bi(
                    '$buyer has been told.',
                    '$buyer-க்குத் தெரிவிக்கப்பட்டது.',
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _askCancelButton(),
          ];
        case 'received':
          return [
            LiquidButton(
              label: bi('Rate $buyer and finish', '$buyer-ஐ மதிப்பிட்டு முடி'),
              icon: CupertinoIcons.star_fill,
              onPressed: () async {
                final rating = await _rate(buyer);
                if (rating == null) return;
                await _run(
                  () =>
                      ShopService.complete(widget.id, o, rating.$1, rating.$2),
                  bi('Order completed', 'ஆர்டர் முடிந்தது'),
                );
              },
            ),
          ];
      }
    } else {
      switch (status) {
        case 'ordered' || 'accepted':
          return [_askCancelButton()];
        case 'shipped':
          return [
            LiquidButton(
              label: bi(
                'I received it · rate $seller',
                'பெற்றேன் · $seller-ஐ மதிப்பிடு',
              ),
              icon: CupertinoIcons.checkmark_seal_fill,
              onPressed: () async {
                final rating = await _rate(seller);
                if (rating == null) return;
                await _run(
                  () =>
                      ShopService.received(widget.id, o, rating.$1, rating.$2),
                  bi(
                    'Thanks! $seller will rate you next.',
                    'நன்றி! அடுத்து $seller உங்களை மதிப்பிடுவார்.',
                  ),
                );
              },
            ),
          ];
      }
    }
    return const [];
  }

  String get _other => _seller
      ? txt(o, 'buyerName', bi('the buyer', 'வாங்குபவர்'))
      : txt(o, 'sellerName', bi('the seller', 'விற்பவர்'));

  /// Cancelling takes both people: this only asks.
  Widget _askCancelButton() => GhostButton(
    label: bi('Ask to cancel', 'ரத்து செய்யக் கேள்'),
    icon: CupertinoIcons.xmark_circle,
    color: Ink.redText,
    onPressed: () async {
      final reason = await _ask(
        bi('Ask $_other to cancel?', '$_other-இடம் ரத்து செய்யக் கேட்கவா?'),
        bi('Why? (both of you see this)', 'ஏன்? (இருவரும் பார்ப்பீர்கள்)'),
        note: bi(
          'An order is cancelled only when you both agree. $_other will be '
              'asked; talk it over in the messages.',
          'இருவரும் ஒப்புக்கொண்டால் மட்டுமே ஆர்டர் ரத்தாகும். $_other-இடம் '
              'கேட்கப்படும்; செய்திகளில் பேசிக்கொள்ளுங்கள்.',
        ),
      );
      if (reason == null) return;
      if (reason.isEmpty) {
        if (mounted) {
          snack(
            context,
            bi('Write a reason', 'காரணம் எழுதவும்'),
            tone: SnackTone.error,
          );
        }
        return;
      }
      await _run(
        () async {
          await ShopService.askCancel(
            widget.id,
            bySeller: _seller,
            reason: reason,
          );
          // The reason opens the conversation in the order messages.
          unawaited(
            ShopService.sendMessage(
              widget.id,
              bi(
                'I asked to cancel: $reason',
                'ரத்து செய்யக் கேட்டேன்: $reason',
              ),
            ).catchError((_) {}),
          );
        },
        bi(
          'Asked. Waiting for $_other.',
          'கேட்டாகிவிட்டது. $_other-க்காகக் காத்திருக்கிறது.',
        ),
      );
    },
  );

  Widget _cancelRequestCard(Map<String, dynamic> asked) {
    final mine = txt(asked, 'by') == (_seller ? 'seller' : 'buyer');
    final reason = txt(asked, 'reason');
    return Glass(
      radius: 20,
      tint: Ink.orange.withValues(alpha: .10),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.chat_bubble_2_fill, color: Ink.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  [
                    mine
                        ? bi(
                            'You asked to cancel. Waiting for $_other to agree.',
                            'நீங்கள் ரத்து கேட்டீர்கள். $_other ஒப்புக்கொள்ளக் காத்திருக்கிறது.',
                          )
                        : bi(
                            '$_other asks to cancel this order.',
                            '$_other இந்த ஆர்டரை ரத்து செய்யக் கேட்கிறார்.',
                          ),
                    if (reason.isNotEmpty) '“$reason”',
                  ].join('\n'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (mine)
            GhostButton(
              label: bi(
                'Take back my request',
                'என் கோரிக்கையைத் திரும்பப் பெறு',
              ),
              icon: CupertinoIcons.arrow_uturn_left,
              onPressed: () => _run(() async {
                await SocialActivityService.noteOwnOrderChange(
                  widget.id,
                  o,
                  selling: _seller,
                );
                await ShopService.dropCancel(widget.id);
              }, bi('The order goes on', 'ஆர்டர் தொடர்கிறது')),
            )
          else ...[
            LiquidButton(
              label: bi('Agree to cancel', 'ரத்து செய்ய ஒப்புக்கொள்'),
              icon: CupertinoIcons.checkmark_alt,
              onPressed: () async {
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AppleAlert(
                    title: Text(
                      bi('Cancel this order?', 'இந்த ஆர்டரை ரத்து செய்யவா?'),
                    ),
                    content: Text(
                      bi(
                        'Both of you agree, so it ends here. This cannot be undone.',
                        'இருவரும் ஒப்புக்கொண்டதால் இங்கே முடிகிறது. இதைத் திரும்பப் பெற முடியாது.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(bi('Not now', 'இப்போது வேண்டாம்')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          bi('Cancel order', 'ஆர்டரை ரத்து செய்'),
                          style: TextStyle(color: Ink.redText),
                        ),
                      ),
                    ],
                  ),
                );
                if (sure != true) return;
                await _run(
                  () =>
                      ShopService.agreeCancel(widget.id, o, bySeller: _seller),
                  bi('Order cancelled', 'ஆர்டர் ரத்து செய்யப்பட்டது'),
                );
              },
            ),
            const SizedBox(height: 8),
            GhostButton(
              label: bi('Keep the order', 'ஆர்டரைத் தொடர்'),
              icon: CupertinoIcons.arrow_right_circle,
              onPressed: () => _run(
                () => ShopService.dropCancel(widget.id),
                bi(
                  '$_other has been told.',
                  '$_other-க்குத் தெரிவிக்கப்பட்டது.',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = txt(o, 'status');
    final cancelled = status == 'cancelled';
    final step = shopOrderSteps.indexWhere((s) => s.$1 == status);
    final address = asMap(o['address']);
    final buyerRating = asMap(o['buyerRating']);
    final sellerRating = asMap(o['sellerRating']);
    return Shell(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          if (widget.justPlaced)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Glass(
                radius: 20,
                tint: Ink.green.withValues(alpha: .10),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      color: Ink.greenText,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        bi(
                          'Order placed. ${txt(o, 'sellerName')} will confirm it.',
                          'ஆர்டர் செய்யப்பட்டது. ${txt(o, 'sellerName')} உறுதிசெய்வார்.',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Where it stands: the five Mercari steps.
          Glass(
            radius: 20,
            padding: const EdgeInsets.all(16),
            child: cancelled
                ? Row(
                    children: [
                      Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: Ink.redText,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          [
                            switch (txt(o, 'cancelledBy')) {
                              'vimo' => bi(
                                'Ended by VIMO Team',
                                'VIMO Team முடித்தது',
                              ),
                              'seller' => bi(
                                'Cancelled · the seller asked, the buyer agreed',
                                'ரத்தானது · விற்பவர் கேட்டார், வாங்குபவர் ஒப்புக்கொண்டார்',
                              ),
                              _ => bi(
                                'Cancelled · the buyer asked, the seller agreed',
                                'ரத்தானது · வாங்குபவர் கேட்டார், விற்பவர் ஒப்புக்கொண்டார்',
                              ),
                            },
                            if (txt(o, 'cancelReason').isNotEmpty)
                              txt(o, 'cancelReason'),
                          ].join('\n'),
                          style: TextStyle(
                            color: Ink.redText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      for (var i = 0; i < shopOrderSteps.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                i <= step
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                size: 20,
                                color: i <= step ? Ink.greenText : Ink.faint,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  bi(
                                    shopOrderSteps[i].$2,
                                    shopOrderSteps[i].$3,
                                  ),
                                  style: TextStyle(
                                    fontWeight: i == step
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: i <= step ? Ink.navy : Ink.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          ..._actions(status),
          _shopSection(bi('Item', 'பொருள்')),
          Glass(
            radius: 20,
            padding: const EdgeInsets.all(12),
            onTap: () => push(context, ProductScreen(id: txt(o, 'productId'))),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox.square(
                    dimension: 56,
                    child: _shopImage(txt(o, 'cover')) == null
                        ? ColoredBox(color: Ink.lavender)
                        : Image(
                            image: _shopImage(txt(o, 'cover'))!,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${txt(o, 'title')}\n${money(numv(o, 'unitPrice'))} × ${toInt(o['quantity'])}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Glass(
            radius: 20,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _sumRow(
                  bi('Item total', 'பொருள் மொத்தம்'),
                  money(numv(o, 'unitPrice') * toInt(o['quantity'])),
                ),
                _sumRow(
                  bi('Delivery', 'டெலிவரி'),
                  numv(o, 'deliveryFee') > 0
                      ? money(numv(o, 'deliveryFee'))
                      : bi('Free', 'இலவசம்'),
                ),
                const Divider(height: 20),
                _sumRow(
                  bi('Total', 'மொத்தம்'),
                  money(numv(o, 'total')),
                  strong: true,
                ),
                const SizedBox(height: 8),
                _detailRow(
                  bi('Payment', 'பணம்'),
                  shopLabel(shopPayments, txt(o, 'payment')),
                ),
                if (txt(o, 'sellerUpi').isNotEmpty)
                  _detailRow(
                    bi('Seller’s UPI', 'விற்பவர் UPI'),
                    txt(o, 'sellerUpi'),
                  ),
                _detailRow(
                  bi('How you get it', 'பெறும் முறை'),
                  shopLabel(shopDeliveryMethods, txt(o, 'deliveryMethod')),
                ),
                if (address.isNotEmpty)
                  _detailRow(
                    bi('Address', 'முகவரி'),
                    [
                      txt(address, 'name'),
                      txt(address, 'phone'),
                      txt(address, 'line'),
                      '${txt(address, 'city')} ${txt(address, 'pincode')}',
                    ].where((e) => e.trim().isNotEmpty).join('\n'),
                  ),
                if (txt(o, 'tracking').isNotEmpty)
                  _detailRow(bi('Tracking', 'டிராக்கிங்'), txt(o, 'tracking')),
                if (txt(o, 'note').isNotEmpty)
                  _detailRow(bi('Note', 'குறிப்பு'), txt(o, 'note')),
              ],
            ),
          ),
          if (buyerRating.isNotEmpty || sellerRating.isNotEmpty) ...[
            _shopSection(bi('Ratings', 'மதிப்பீடுகள்')),
            if (buyerRating.isNotEmpty)
              _RatingLine(
                who: bi('Buyer about seller', 'விற்பவர் பற்றி வாங்குபவர்'),
                rating: buyerRating,
              ),
            if (sellerRating.isNotEmpty)
              _RatingLine(
                who: bi('Seller about buyer', 'வாங்குபவர் பற்றி விற்பவர்'),
                rating: sellerRating,
              ),
          ],
          _shopSection(
            _seller ? bi('Buyer', 'வாங்குபவர்') : bi('Seller', 'விற்பவர்'),
          ),
          _SellerCard(
            uid: _seller ? txt(o, 'buyerUid') : txt(o, 'sellerUid'),
            name: _seller ? txt(o, 'buyerName') : txt(o, 'sellerName'),
          ),
          _shopSection(
            bi('Messages', 'செய்திகள்'),
            note: bi(
              'Only the two of you see these.',
              'நீங்கள் இருவர் மட்டும் பார்க்கலாம்.',
            ),
          ),
          _OrderMessages(id: widget.id),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => openReport(
              context,
              againstUid: _seller ? txt(o, 'buyerUid') : txt(o, 'sellerUid'),
              againstName: _other,
              topic: 'order',
              orderId: widget.id,
            ),
            icon: Icon(CupertinoIcons.flag, size: 18, color: Ink.muted),
            label: Text(
              bi(
                'Problem with this order? Tell VIMO Team',
                'இந்த ஆர்டரில் பிரச்சனையா? VIMO Team-க்குச் சொல்லுங்கள்',
              ),
              style: TextStyle(color: Ink.muted),
            ),
          ),
          if (!cancelled && status != 'completed') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              maxLength: 500,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: fieldStyle(
                bi('Write a message', 'செய்தி எழுது'),
                suffix: IconButton(
                  tooltip: bi('Send', 'அனுப்பு'),
                  icon: Icon(
                    CupertinoIcons.arrow_up_circle_fill,
                    color: Ink.violetDeep,
                  ),
                  onPressed: () async {
                    final text = _message.text.trim();
                    if (text.isEmpty) return;
                    _message.clear();
                    try {
                      await ShopService.sendMessage(widget.id, text);
                    } catch (e) {
                      if (mounted) {
                        _message.text = text;
                        snack(
                          this.context,
                          accountError(e),
                          tone: SnackTone.error,
                        );
                      }
                    }
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RatingLine extends StatelessWidget {
  final String who;
  final Map<String, dynamic> rating;
  const _RatingLine({required this.who, required this.rating});

  @override
  Widget build(BuildContext context) {
    final stars = ratingStars(rating);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        radius: 18,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    who,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Semantics(
                  label: bi('$stars of 5 stars', '5-ல் $stars நட்சத்திரம்'),
                  child: StarRow(value: stars.toDouble()),
                ),
              ],
            ),
            if (txt(rating, 'text').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(txt(rating, 'text')),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderMessages extends StatelessWidget {
  final String id;
  const _OrderMessages({required this.id});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ShopService.messagesOf(
          id,
        ).orderBy('createdAt').limitToLast(100).snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Text(
              bi('No messages yet.', 'இன்னும் செய்திகள் இல்லை.'),
              style: TextStyle(color: Ink.muted),
            );
          }
          return Column(
            children: [
              for (final d in docs)
                AppleBubble(
                  mine: txt(d.data(), 'senderUid') == signedInUid,
                  child: Text(txt(d.data(), 'text')),
                ),
            ],
          );
        },
      );
}

// -----------------------------------------------------------------------------
//  Market: products
// -----------------------------------------------------------------------------

/// Products in Market: categories to browse, search results when searching,
/// and a way to the buyer's own orders.
class MarketProducts extends StatefulWidget {
  final String query;
  const MarketProducts({super.key, required this.query});

  @override
  State<MarketProducts> createState() => _MarketProductsState();
}

class _MarketProductsState extends State<MarketProducts> {
  String _category = '';
  String _sort = 'new';
  bool _available = false;
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _load =
      _fetch();

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetch() =>
      widget.query.trim().length >= 2
      ? ShopService.search(widget.query, category: _category)
      : ShopService.recent(category: _category);

  @override
  void didUpdateWidget(MarketProducts old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _load = _fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (!ShopService.available) return const SizedBox.shrink();
    final searching = widget.query.trim().length >= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                searching
                    ? bi('Products', 'பொருட்கள்')
                    : bi('New in Market', 'சந்தையில் புதியவை'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                ),
              ),
            ),
            IconButton(
              tooltip: bi('Liked', 'விரும்பியவை'),
              onPressed: () => push(context, const LikedScreen()),
              icon: Icon(CupertinoIcons.heart, color: Ink.violetDeep),
            ),
            PopupMenuButton<String>(
              tooltip: bi('Sort', 'வரிசை'),
              icon: Icon(
                CupertinoIcons.arrow_up_arrow_down,
                color: Ink.violetDeep,
              ),
              onSelected: (v) => setState(() {
                if (v == 'available') {
                  _available = !_available;
                } else {
                  _sort = v;
                }
              }),
              itemBuilder: (_) => [
                for (final s in shopSorts)
                  CheckedPopupMenuItem(
                    value: s.$1,
                    checked: _sort == s.$1,
                    child: Text(bi(s.$2, s.$3)),
                  ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                  value: 'available',
                  checked: _available,
                  child: Text(bi('On sale only', 'விற்பனையில் மட்டும்')),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => push(context, const OrdersScreen()),
              icon: const Icon(CupertinoIcons.bag),
              label: Text(bi('My orders', 'என் ஆர்டர்கள்')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in [('', 'All', 'அனைத்தும்'), ...shopCategories])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(bi(c.$2, c.$3)),
                    selected: _category == c.$1,
                    showCheckmark: false,
                    selectedColor: Ink.tint,
                    labelStyle: TextStyle(
                      color: _category == c.$1 ? Colors.white : Ink.navy,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) {
                      selectionFeedback();
                      setState(() {
                        _category = c.$1;
                        _load = _fetch();
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: _load,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonList(rows: 2, padding: EdgeInsets.zero);
            }
            if (snap.hasError) {
              return _MarketNote(
                bi(
                  'Could not load products. Pull down to try again.',
                  'பொருட்களை ஏற்ற முடியவில்லை. கீழே இழுத்து மீண்டும் முயற்சிக்கவும்.',
                ),
              );
            }
            final docs = sortShopProducts(
              snap.data ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
              (d) => d.data(),
              sort: _sort,
              available: _available,
            );
            if (docs.isEmpty) {
              return _MarketNote(
                searching
                    ? bi('No products match.', 'பொருந்தும் பொருட்கள் இல்லை.')
                    : bi('No products listed yet.', 'இன்னும் பொருட்கள் இல்லை.'),
              );
            }
            return ProductGrid(docs: docs);
          },
        ),
      ],
    );
  }
}
