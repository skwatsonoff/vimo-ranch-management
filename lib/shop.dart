part of 'main.dart';

// =============================================================================
//  Shop: products people list from their profile, and Mercari-style orders.
//
//  A product carries what Amazon and Meesho ask a seller for (photos, title,
//  category, condition, description, key features, price and MRP, unit and
//  pack size, stock, delivery and returns, brand, SKU, weight, origin,
//  manufacturer, GST and HSN) plus up to five private search tags.
//
//  An order follows Mercari's steps: the buyer confirms item, quantity,
//  delivery, address and payment; the seller accepts and ships; the buyer
//  confirms receipt and rates the seller; the seller rates the buyer and the
//  order completes. Either side can message inside the order. VIMO never
//  holds money: payment is cash or UPI straight to the seller, and the app
//  says so before anyone orders.
// =============================================================================

/// One choice in a fixed list: stored key, English and Tamil labels.
typedef ShopChoice = (String key, String en, String ta);

String shopLabel(List<ShopChoice> choices, String key) {
  for (final c in choices) {
    if (c.$1 == key) return bi(c.$2, c.$3);
  }
  return key;
}

const List<ShopChoice> shopCategories = [
  ('dairy', 'Milk & dairy', 'பால் & பால் பொருட்கள்'),
  ('ghee', 'Ghee, butter & paneer', 'நெய், வெண்ணெய் & பனீர்'),
  ('feed', 'Cattle feed & fodder', 'கால்நடைத் தீவனம்'),
  ('animals', 'Cows, calves & animals', 'மாடு, கன்று & விலங்குகள்'),
  ('equipment', 'Farm equipment', 'பண்ணைக் கருவிகள்'),
  ('produce', 'Vegetables & fruits', 'காய்கறி & பழங்கள்'),
  ('grains', 'Grains, pulses & oils', 'தானியம், பருப்பு & எண்ணெய்'),
  ('organic', 'Manure & organic', 'உரம் & இயற்கை'),
  ('home', 'Home & kitchen', 'வீடு & சமையலறை'),
  ('clothing', 'Clothing & accessories', 'உடை & அணிகலன்கள்'),
  ('electronics', 'Electronics & mobiles', 'மின்னணு & மொபைல்'),
  ('other', 'Other', 'மற்றவை'),
];

/// Mercari's condition scale.
const List<ShopChoice> shopConditions = [
  ('new', 'New, unused', 'புதியது'),
  ('like_new', 'Like new', 'புதியது போல'),
  ('good', 'Good', 'நல்லது'),
  ('fair', 'Fair', 'சுமார்'),
  ('poor', 'Poor', 'மோசம்'),
];

const List<ShopChoice> productUnits = [
  ('piece', 'Piece', 'எண்ணிக்கை'),
  ('litre', 'Litre', 'லிட்டர்'),
  ('kg', 'Kg', 'கிலோ'),
  ('pack', 'Pack', 'பேக்'),
  ('dozen', 'Dozen', 'டஜன்'),
];

const List<ShopChoice> shopDeliveryMethods = [
  ('pickup', 'Buyer picks up', 'வாங்குபவர் எடுத்துச் செல்வார்'),
  ('seller_delivery', 'Seller delivers', 'விற்பவர் கொண்டு வருவார்'),
  ('courier', 'Courier / post', 'கூரியர் / தபால்'),
];

const List<ShopChoice> shopShipDays = [
  ('1-2', '1–2 days', '1–2 நாள்'),
  ('2-3', '2–3 days', '2–3 நாள்'),
  ('4-7', '4–7 days', '4–7 நாள்'),
];

const List<ShopChoice> shopReturns = [
  ('none', 'No returns', 'திருப்பி அனுப்ப முடியாது'),
  ('7days', 'Returns within 7 days', '7 நாட்களுக்குள் திருப்பலாம்'),
];

const List<ShopChoice> shopPayments = [
  ('cod', 'Cash on delivery or pickup', 'பெறும்போது பணம்'),
  ('upi', 'UPI to the seller', 'விற்பவருக்கு UPI'),
];

const List<int> shopGstRates = [0, 5, 12, 18, 28];

const List<ShopChoice> shopOrderSteps = [
  ('ordered', 'Ordered', 'ஆர்டர் செய்யப்பட்டது'),
  ('accepted', 'Accepted', 'ஏற்கப்பட்டது'),
  ('shipped', 'On the way', 'வழியில்'),
  ('received', 'Received', 'பெறப்பட்டது'),
  ('completed', 'Completed', 'முடிந்தது'),
];

String shopOrderStatusLabel(String status) => status == 'cancelled'
    ? bi('Cancelled', 'ரத்து செய்யப்பட்டது')
    : shopLabel(shopOrderSteps, status);

Color shopOrderStatusColor(String status) => switch (status) {
  'ordered' => Ink.amberText,
  'accepted' || 'shipped' => Ink.violetDeep,
  'received' || 'completed' => Ink.greenText,
  _ => Ink.redText,
};

/// Lower-case words for array-contains search: title, tags, brand and the
/// category's names. Customers never see this list.
List<String> shopSearchTerms({
  required String title,
  required List<String> tags,
  required String brand,
  required String category,
}) {
  final words = <String>{};
  void add(String text) {
    for (final w in text.toLowerCase().split(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    )) {
      if (w.length >= 2 && w.length <= 30) words.add(w);
    }
  }

  add(title);
  add(brand);
  for (final t in tags) {
    add(t);
  }
  for (final c in shopCategories) {
    if (c.$1 == category) {
      add(c.$2);
      add(c.$3);
    }
  }
  return words.take(60).toList();
}

/// A private search tag: trimmed, lower case, at most 24 characters.
String shopTag(String raw) {
  final t = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return t.length > 24 ? t.substring(0, 24) : t;
}

/// Percentage off MRP, rounded, or 0 when there is no saving.
int shopDiscount(num price, num mrp) =>
    mrp > price && price > 0 ? ((mrp - price) * 100 / mrp).round() : 0;

/// The delivery fee a buyer pays for [method].
double shopDeliveryFee(Map<String, dynamic> product, String method) {
  final delivery = asMap(product['delivery']);
  if (method == 'pickup' || txt(delivery, 'payer') != 'buyer') return 0;
  return numv(delivery, 'fee');
}

/// "Free delivery", "₹40 delivery" or "Pickup only".
String shopDeliverySummary(Map<String, dynamic> product) {
  final delivery = asMap(product['delivery']);
  final methods = ((delivery['methods'] as List?) ?? const [])
      .map((e) => '$e')
      .toList();
  if (methods.length == 1 && methods.first == 'pickup') {
    return bi('Pickup only', 'நேரில் மட்டும்');
  }
  if (txt(delivery, 'payer') != 'buyer' || numv(delivery, 'fee') <= 0) {
    return bi('Free delivery', 'இலவச டெலிவரி');
  }
  return bi(
    '${money(numv(delivery, 'fee'))} delivery',
    'டெலிவரி ${money(numv(delivery, 'fee'))}',
  );
}

// -----------------------------------------------------------------------------
//  Photos
// -----------------------------------------------------------------------------

/// A product photo: longest side 1080 px, JPEG kept under about 280 KB so
/// each fits in its own small document.
Uint8List? _compressProductPhoto(Uint8List bytes) {
  var decoded = image_lib.decodeImage(bytes);
  if (decoded == null) return null;
  decoded = image_lib.bakeOrientation(decoded);
  const maxSide = 1080;
  if (decoded.width > maxSide || decoded.height > maxSide) {
    decoded = decoded.width >= decoded.height
        ? image_lib.copyResize(decoded, width: maxSide)
        : image_lib.copyResize(decoded, height: maxSide);
  }
  var quality = 80;
  var encoded = Uint8List.fromList(
    image_lib.encodeJpg(decoded, quality: quality),
  );
  while (encoded.lengthInBytes > 280 * 1024 && quality > 45) {
    quality -= 7;
    encoded = Uint8List.fromList(
      image_lib.encodeJpg(decoded, quality: quality),
    );
  }
  return encoded.lengthInBytes <= 300 * 1024 ? encoded : null;
}

/// The small square-ish cover used in grids and orders (about 360 px).
Uint8List? _productThumb(Uint8List bytes) {
  var decoded = image_lib.decodeImage(bytes);
  if (decoded == null) return null;
  decoded = image_lib.bakeOrientation(decoded);
  decoded = decoded.width >= decoded.height
      ? image_lib.copyResize(decoded, height: 360)
      : image_lib.copyResize(decoded, width: 360);
  var quality = 72;
  var encoded = Uint8List.fromList(
    image_lib.encodeJpg(decoded, quality: quality),
  );
  while (encoded.lengthInBytes > 40 * 1024 && quality > 40) {
    quality -= 8;
    encoded = Uint8List.fromList(
      image_lib.encodeJpg(decoded, quality: quality),
    );
  }
  return encoded;
}

Future<String?> _dataUrlVia(
  String source,
  Uint8List? Function(Uint8List) work,
) async {
  final comma = source.indexOf(',');
  if (comma < 0) return null;
  try {
    final out = await compute(work, base64Decode(source.substring(comma + 1)));
    if (out == null || out.isEmpty) return null;
    return 'data:image/jpeg;base64,${base64Encode(out)}';
  } catch (_) {
    return null;
  }
}

Future<String?> productPhotoFrom(String source) =>
    _dataUrlVia(source, _compressProductPhoto);
Future<String?> productThumbFrom(String source) =>
    _dataUrlVia(source, _productThumb);

// -----------------------------------------------------------------------------
//  Service
// -----------------------------------------------------------------------------

class ShopService {
  const ShopService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get products =>
      _db.collection('shop_products');
  static CollectionReference<Map<String, dynamic>> get orders =>
      _db.collection('shop_orders');
  static CollectionReference<Map<String, dynamic>> photosOf(String id) =>
      products.doc(id).collection('photos');

  static bool get available => firebaseReady && signedInUid.isNotEmpty;

  static Stream<QuerySnapshot<Map<String, dynamic>>> productsOf(String uid) =>
      products.where('sellerUid', isEqualTo: uid).snapshots();

  /// Saves a product and its photos together. [photos] are full-size data
  /// URLs (1 to 5); the first is the cover.
  static Future<String> save({
    String? id,
    required Map<String, dynamic> fields,
    required List<String> photos,
    required int previousPhotoCount,
  }) async {
    if (photos.isEmpty || photos.length > 5) {
      throw StateError(
        bi('Add 1 to 5 photos', '1 முதல் 5 படங்கள் சேர்க்கவும்'),
      );
    }
    final ref = id == null ? products.doc() : products.doc(id);
    final cover = await productThumbFrom(photos.first);
    if (cover == null) {
      throw StateError(
        bi('Could not read the photo', 'படத்தைப் படிக்க முடியவில்லை'),
      );
    }
    final batch = _db.batch();
    batch.set(ref, {
      ...fields,
      'sellerUid': signedInUid,
      'sellerName': await MarketService.myName(),
      'cover': cover,
      'photoCount': photos.length,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: id != null));
    for (var i = 0; i < photos.length; i++) {
      batch.set(ref.collection('photos').doc('$i'), {'data': photos[i]});
    }
    for (var i = photos.length; i < previousPhotoCount; i++) {
      batch.delete(ref.collection('photos').doc('$i'));
    }
    await batch.commit().timeout(const Duration(seconds: 40));
    return ref.id;
  }

  static Future<List<String>> photos(String id, int count) async {
    final snap = await photosOf(id).get();
    final byIndex = {for (final d in snap.docs) d.id: txt(d.data(), 'data')};
    return [
      for (var i = 0; i < count; i++)
        if ((byIndex['$i'] ?? '').isNotEmpty) byIndex['$i']!,
    ];
  }

  static Future<void> delete(String id, int photoCount) async {
    final batch = _db.batch();
    for (var i = 0; i < photoCount; i++) {
      batch.delete(photosOf(id).doc('$i'));
    }
    batch.delete(products.doc(id));
    await batch.commit();
  }

  static Future<void> setStatus(String id, String status) => products
      .doc(id)
      .update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});

  /// Products whose words start a search, active only.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> search(
    String query, {
    String category = '',
  }) async {
    final words = shopSearchTerms(
      title: query,
      tags: const [],
      brand: '',
      category: '',
    );
    Query<Map<String, dynamic>> q = products.where(
      'status',
      isEqualTo: 'active',
    );
    if (words.isNotEmpty) {
      q = q.where('searchTerms', arrayContains: words.first);
    }
    if (category.isNotEmpty) q = q.where('category', isEqualTo: category);
    final snap = await q.limit(40).get();
    final rest = words.skip(1).toList();
    return [
      for (final d in snap.docs)
        if (rest.every(
          (w) => ((d.data()['searchTerms'] as List?) ?? const []).any(
            (t) => '$t'.startsWith(w),
          ),
        ))
          d,
    ];
  }

  /// Recently listed active products, newest first (sorted here, so no
  /// composite index is needed).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> recent({
    String category = '',
  }) async {
    Query<Map<String, dynamic>> q = products.where(
      'status',
      isEqualTo: 'active',
    );
    if (category.isNotEmpty) q = q.where('category', isEqualTo: category);
    final snap = await q.limit(60).get();
    final docs =
        snap.docs.where((d) => d.data()['sellerUid'] != signedInUid).toList()
          ..sort(
            (a, b) => (_marketTime(b.data()['updatedAt']) ?? DateTime(2000))
                .compareTo(
                  _marketTime(a.data()['updatedAt']) ?? DateTime(2000),
                ),
          );
    return docs;
  }

  // --- Orders -----------------------------------------------------------------

  static Stream<QuerySnapshot<Map<String, dynamic>>> buying() =>
      orders.where('buyerUid', isEqualTo: signedInUid).snapshots();
  static Stream<QuerySnapshot<Map<String, dynamic>>> selling() =>
      orders.where('sellerUid', isEqualTo: signedInUid).snapshots();

  /// Places an order at the product's current price; the rules check the
  /// price, fee and total against the product itself.
  static Future<String> placeOrder({
    required String productId,
    required Map<String, dynamic> product,
    required int quantity,
    required String deliveryMethod,
    required String payment,
    required Map<String, dynamic> address,
    required String note,
  }) async {
    final unitPrice = numv(product, 'price');
    final fee = shopDeliveryFee(product, deliveryMethod);
    final ref = orders.doc();
    await ref.set({
      'productId': productId,
      'sellerUid': txt(product, 'sellerUid'),
      'buyerUid': signedInUid,
      'sellerName': txt(product, 'sellerName', 'VIMO'),
      'buyerName': await MarketService.myName(),
      'title': txt(product, 'title'),
      'cover': txt(product, 'cover'),
      'unitPrice': unitPrice,
      'quantity': quantity,
      'deliveryMethod': deliveryMethod,
      'deliveryFee': fee,
      'total': unitPrice * quantity + fee,
      'payment': payment,
      'address': deliveryMethod == 'pickup' ? <String, dynamic>{} : address,
      'note': note.trim(),
      'status': 'ordered',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await setSetting('shopAddress', address);
    return ref.id;
  }

  /// Seller accepts: stock goes down by the quantity in the same write.
  static Future<void> accept(
    String id,
    Map<String, dynamic> order, {
    String upi = '',
  }) async {
    final batch = _db.batch();
    batch.update(orders.doc(id), {
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'sellerUpi': upi.trim(),
    });
    batch.update(products.doc(txt(order, 'productId')), {
      'stock': FieldValue.increment(-toInt(order['quantity'])),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Future<void> ship(String id, String tracking) =>
      orders.doc(id).update({
        'status': 'shipped',
        'shippedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'tracking': tracking.trim(),
      });

  static Future<void> received(String id, String score, String text) =>
      orders.doc(id).update({
        'status': 'received',
        'receivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'buyerRating': {'score': score, 'text': text.trim()},
      });

  static Future<void> complete(String id, String score, String text) =>
      orders.doc(id).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'sellerRating': {'score': score, 'text': text.trim()},
      });

  /// Cancels; an accepted order gives its stock back.
  static Future<void> cancel(
    String id,
    Map<String, dynamic> order, {
    required bool bySeller,
    required String reason,
  }) async {
    final batch = _db.batch();
    batch.update(orders.doc(id), {
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': bySeller ? 'seller' : 'buyer',
      'cancelReason': reason.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (bySeller && txt(order, 'status') == 'accepted') {
      batch.update(products.doc(txt(order, 'productId')), {
        'stock': FieldValue.increment(toInt(order['quantity'])),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static CollectionReference<Map<String, dynamic>> messagesOf(String id) =>
      orders.doc(id).collection('messages');

  static Future<void> sendMessage(String id, String text) =>
      messagesOf(id).add({
        'senderUid': signedInUid,
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
}
