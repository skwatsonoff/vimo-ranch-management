part of 'main.dart';

// -----------------------------------------------------------------------------
//  Nearby milk: search, requests and reviews from real buyers
// -----------------------------------------------------------------------------

/// A listed place is shared only as a grid square of 1/500 degree (about
/// 220 m), so buyers see roughly where a vendor is, never the exact spot.
const marketGridScale = 500;

/// A search cell is 25 x 25 grid squares (about 5.5 km). A search reads the
/// buyer's cell and the eight around it.
const marketCellSize = 25;

/// The area drawn around a listed vendor, in metres.
const marketAreaRadius = 220.0;

int marketGrid(double degrees) => (degrees * marketGridScale).round();
int marketCellIndex(int grid) => (grid / marketCellSize).floor();
String marketCell(int gridLat, int gridLng) =>
    '${marketCellIndex(gridLat)}:${marketCellIndex(gridLng)}';

/// Search distances, nearest first: 2 km, then 5 km, then 10 km at most.
const marketSearchSteps = <double>[2000, 5000, 10000];

/// The cells around [point], [ring] cells out on each side. The default ring
/// of 2 (5 x 5 cells, 25 values within Firestore's limit of 30 for `in`)
/// reaches at least 11 km in every direction, covering the 10 km maximum.
List<String> marketNearbyCells(ll.LatLng point, {int ring = 2}) {
  final lat = marketCellIndex(marketGrid(point.latitude));
  final lng = marketCellIndex(marketGrid(point.longitude));
  return [
    for (var a = -ring; a <= ring; a++)
      for (var b = -ring; b <= ring; b++) '${lat + a}:${lng + b}',
  ];
}

/// The first search distance that finds anyone: 2 km, else 5 km, else
/// 10 km (index into [marketSearchSteps]).
int marketSearchStep(Iterable<double> distances) {
  for (var i = 0; i < marketSearchSteps.length; i++) {
    if (distances.any((d) => d <= marketSearchSteps[i])) return i;
  }
  return marketSearchSteps.length - 1;
}

String marketStepLabel(int step) {
  final km = (marketSearchSteps[step] / 1000).round();
  return bi('$km km', '$km கி.மீ');
}

/// The middle of a listing's grid square: where its area is drawn.
ll.LatLng marketAreaCenter(Map<String, dynamic> listing) => ll.LatLng(
  numv(listing, 'gridLat') / marketGridScale,
  numv(listing, 'gridLng') / marketGridScale,
);

double marketDistance(ll.LatLng a, ll.LatLng b) =>
    const ll.Distance().as(ll.LengthUnit.Meter, a, b);

/// Distances are rounded, since the vendor's place itself is approximate.
String marketDistanceLabel(double metres) {
  if (metres < 1000) {
    final rounded = math.max(100, (metres / 100).round() * 100);
    return bi('~$rounded m', '~$rounded மீ');
  }
  final km = metres < 10000
      ? (metres / 1000).toStringAsFixed(1)
      : (metres / 1000).round().toString();
  return bi('~$km km', '~$km கி.மீ');
}

int? marketMinutes(String clock) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(clock);
  if (match == null) return null;
  return int.parse(match[1]!) * 60 + int.parse(match[2]!);
}

String marketClock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// A time of day as people say it: 5:30 AM, or காலை 5:30 in Tamil.
String marketTimeLabel(int minutes) {
  final hour = minutes ~/ 60, minute = minutes % 60;
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  final clock = '$h12:${minute.toString().padLeft(2, '0')}';
  if (hour < 12) return bi('$clock AM', 'காலை $clock');
  if (hour < 16) return bi('$clock PM', 'மதியம் $clock');
  if (hour < 19) return bi('$clock PM', 'மாலை $clock');
  return bi('$clock PM', 'இரவு $clock');
}

/// Opening hours of a listing: morning and evening, each start to end.
List<(int, int)> marketWindows(Map<String, dynamic> listing) => [
  for (final key in const ['morning', 'evening'])
    if (asMap(listing[key]) case final hours
        when marketMinutes(txt(hours, 'start')) != null &&
            marketMinutes(txt(hours, 'end')) != null &&
            marketMinutes(txt(hours, 'end'))! >
                marketMinutes(txt(hours, 'start'))!)
      (marketMinutes(txt(hours, 'start'))!, marketMinutes(txt(hours, 'end'))!),
];

enum MarketOpen { open, opensSoon, onRide, endsSoon, closed }

DateTime? _marketTime(dynamic value) => switch (value) {
  Timestamp t => t.toDate(),
  DateTime d => d,
  _ => null,
};

/// Like a shop on a map: open, opens soon, on ride, ends soon or closed.
/// A ride counts for four hours at most, in case the app was closed mid-ride.
MarketOpen marketStatus(Map<String, dynamic> listing, DateTime now) {
  if (listing['active'] != true || listing['holiday'] == true) {
    return MarketOpen.closed;
  }
  final ride = _marketTime(listing['rideAt']);
  if (listing['onRide'] == true &&
      ride != null &&
      now.difference(ride) < const Duration(hours: 4)) {
    return MarketOpen.onRide;
  }
  final minute = now.hour * 60 + now.minute;
  for (final (start, end) in marketWindows(listing)) {
    if (minute >= start && minute < end) {
      return end - minute <= 30 ? MarketOpen.endsSoon : MarketOpen.open;
    }
  }
  for (final (start, _) in marketWindows(listing)) {
    if (start > minute && start - minute <= 60) return MarketOpen.opensSoon;
  }
  return MarketOpen.closed;
}

String marketStatusLabel(MarketOpen status) => switch (status) {
  // "Open" alone is translated as the command "open it" elsewhere.
  MarketOpen.open => bi('Open now', 'திறந்துள்ளது'),
  MarketOpen.opensSoon => bi('Opens soon', 'விரைவில் திறக்கும்'),
  MarketOpen.onRide => bi('On ride', 'விநியோகத்தில்'),
  MarketOpen.endsSoon => bi('Ends soon', 'விரைவில் முடியும்'),
  MarketOpen.closed => bi('Closed', 'மூடப்பட்டது'),
};

Color marketStatusColor(MarketOpen status) => switch (status) {
  MarketOpen.open => Ink.greenText,
  MarketOpen.opensSoon || MarketOpen.endsSoon => Ink.amberText,
  MarketOpen.onRide => Ink.violetDeep,
  MarketOpen.closed => Ink.redText,
};

/// The next change, as on a map: "Closes 8:00 AM" or "Opens 5:30 AM".
String marketStatusDetail(Map<String, dynamic> listing, DateTime now) {
  if (listing['holiday'] == true) return bi('Holiday', 'விடுமுறை');
  final windows = marketWindows(listing);
  if (windows.isEmpty) return '';
  final minute = now.hour * 60 + now.minute;
  for (final (start, end) in windows) {
    if (minute >= start && minute < end) {
      return bi(
        'Ends ${marketTimeLabel(end)}',
        '${marketTimeLabel(end)}-க்கு முடியும்',
      );
    }
  }
  final next = windows.where((w) => w.$1 > minute).toList();
  final start = next.isEmpty ? windows.first.$1 : next.first.$1;
  return next.isEmpty
      ? bi(
          'Opens tomorrow ${marketTimeLabel(start)}',
          'நாளை ${marketTimeLabel(start)}-க்குத் திறக்கும்',
        )
      : bi(
          'Opens ${marketTimeLabel(start)}',
          '${marketTimeLabel(start)}-க்குத் திறக்கும்',
        );
}

const marketWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String marketWeekdayLabel(String day) => switch (day) {
  'Mon' => bi('Mon', 'திங்'),
  'Tue' => bi('Tue', 'செவ்'),
  'Wed' => bi('Wed', 'புத'),
  'Thu' => bi('Thu', 'வியா'),
  'Fri' => bi('Fri', 'வெள்'),
  'Sat' => bi('Sat', 'சனி'),
  _ => bi('Sun', 'ஞாயி'),
};

String marketSessionLabel(String session) =>
    session == 'Evening' ? bi('Evening', 'மாலை') : bi('Morning', 'காலை');

String marketPaymentLabel(String payment) => switch (payment) {
  'daily' => bi('Pay daily', 'தினமும் பணம்'),
  'weekly' => bi('Pay weekly', 'வாரம் ஒருமுறை பணம்'),
  _ => bi('Pay monthly', 'மாதம் ஒருமுறை பணம்'),
};

/// One line about what was asked: "Today only · 1.5 L · Morning · 6:30 AM".
String marketRequestSummary(Map<String, dynamic> request) {
  final regular = request['kind'] == 'regular';
  final days = (request['days'] as List?)?.whereType<String>().toList() ?? [];
  final time = marketMinutes(txt(request, 'time'));
  return [
    regular ? bi('Regular', 'தினசரி') : bi('Today only', 'இன்று மட்டும்'),
    '${vendorFieldNumber(numv(request, 'litres'))} ${bi('L', 'லி')}',
    marketSessionLabel(txt(request, 'session')),
    if (time != null) marketTimeLabel(time),
    if (regular)
      days.length == 7
          ? bi('Every day', 'தினமும்')
          : days.map(marketWeekdayLabel).join(' '),
    if (regular) marketPaymentLabel(txt(request, 'payment')),
  ].join(' · ');
}

/// Where a request stands, in the words of the person reading it.
String marketRequestState(Map<String, dynamic> request, {required bool buyer}) {
  final vendor = txt(request, 'vendorName', 'VIMO');
  return switch (txt(request, 'status')) {
    'pending' =>
      buyer
          ? bi('Waiting for $vendor', '$vendor பதிலுக்குக் காத்திருக்கிறது')
          : bi('New request', 'புதிய கோரிக்கை'),
    'offered' => bi('New time or price offered', 'புதிய நேரம் அல்லது விலை'),
    'accepted' => bi('Accepted', 'ஏற்கப்பட்டது'),
    'declined' => bi('Declined', 'மறுக்கப்பட்டது'),
    _ => bi('Cancelled', 'ரத்து செய்யப்பட்டது'),
  };
}

Color marketRequestColor(String status) => switch (status) {
  'accepted' => Ink.greenText,
  'pending' || 'offered' => Ink.amberText,
  _ => Ink.redText,
};

/// A listed vendor as seen from where the buyer is.
class MarketVendor {
  final String uid;
  final Map<String, dynamic> data;
  final double distance;
  final double rating;
  final int reviews;
  const MarketVendor({
    required this.uid,
    required this.data,
    required this.distance,
    this.rating = 0,
    this.reviews = 0,
  });

  String get name => txt(data, 'name', 'VIMO');
  String get kind => txt(data, 'kind', 'vendor');
  bool get shop => kind == 'shop';
  bool get ranch => kind == 'ranch';
  double get price => numv(data, 'price');

  MarketVendor rated(double rating, int reviews) => MarketVendor(
    uid: uid,
    data: data,
    distance: distance,
    rating: rating,
    reviews: reviews,
  );
}

/// Nearest first, or best rated first. Vendors with no reviews yet come after
/// rated ones; ties fall back to distance.
List<MarketVendor> sortMarketVendors(
  List<MarketVendor> vendors, {
  required bool byRating,
}) {
  final list = List.of(vendors);
  list.sort((a, b) {
    if (byRating) {
      final rated = (b.reviews > 0 ? 1 : 0).compareTo(a.reviews > 0 ? 1 : 0);
      if (rated != 0) return rated;
      final score = b.rating.compareTo(a.rating);
      if (score != 0) return score;
    }
    return a.distance.compareTo(b.distance);
  });
  return list;
}

class MarketService {
  const MarketService._();

  static bool get available => firebaseReady && signedInUid.isNotEmpty;
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get listings =>
      _db.collection('vendor_listings');
  static CollectionReference<Map<String, dynamic>> get requests =>
      _db.collection('milk_requests');
  static DocumentReference<Map<String, dynamic>> get myListing =>
      listings.doc(signedInUid);
  static CollectionReference<Map<String, dynamic>> reviewsOf(String uid) =>
      listings.doc(uid).collection('reviews');

  static Map<String, dynamic> _hours(int? start, int? end) =>
      start == null || end == null || end <= start
      ? <String, dynamic>{}
      : {'start': marketClock(start), 'end': marketClock(end)};

  /// Saves the listing. The exact place stays on this phone (to share with
  /// buyers whose request is accepted); the cloud gets only the grid square.
  static Future<void> saveListing({
    required String name,
    String? kind,
    required ll.LatLng point,
    required double price,
    required (int?, int?) morning,
    required (int?, int?) evening,
    required bool active,
    required bool holiday,
  }) async {
    final gridLat = marketGrid(point.latitude);
    final gridLng = marketGrid(point.longitude);
    await setSetting('marketPoint', {
      'lat': point.latitude,
      'lng': point.longitude,
    });
    Map<String, dynamic> current = {};
    try {
      current = (await myListing.get()).data() ?? {};
    } catch (_) {}
    await myListing.set({
      'name': name.trim(),
      'nameFold': name.trim().toLowerCase(),
      'kind': kind ?? marketListingKind(),
      'gridLat': gridLat,
      'gridLng': gridLng,
      'cell': marketCell(gridLat, gridLng),
      'price': price,
      'morning': _hours(morning.$1, morning.$2),
      'evening': _hours(evening.$1, evening.$2),
      'active': active,
      'holiday': holiday,
      'onRide': current['onRide'] == true,
      if (current['rideAt'] is Timestamp) 'rideAt': current['rideAt'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeListing() => myListing.delete();

  /// Finds ranches, vendors and shops by the start of their name, anywhere.
  /// Listings saved before names were searchable appear in nearby results.
  static Future<List<MarketVendor>> searchByName(
    String query, {
    ll.LatLng? here,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final snap = await listings
        .where('nameFold', isGreaterThanOrEqualTo: q)
        .where('nameFold', isLessThan: '$q\uf8ff')
        .limit(30)
        .get();
    return [
      for (final doc in snap.docs)
        if (doc.id != signedInUid && doc.data()['active'] == true)
          MarketVendor(
            uid: doc.id,
            data: doc.data(),
            distance: here == null
                ? -1
                : marketDistance(here, marketAreaCenter(doc.data())),
          ),
    ];
  }

  /// People this buyer already gets milk from: accepted requests.
  static Future<List<MarketVendor>> previousSellers(
    Iterable<Map<String, dynamic>> myRequests, {
    ll.LatLng? here,
  }) async {
    final uids = <String>{
      for (final r in myRequests)
        if (txt(r, 'status') == 'accepted' && txt(r, 'vendorUid').isNotEmpty)
          txt(r, 'vendorUid'),
    };
    final found = <MarketVendor>[];
    for (final uid in uids.take(10)) {
      try {
        final doc = await listings.doc(uid).get();
        final data = doc.data();
        if (data == null) continue;
        found.add(
          MarketVendor(
            uid: uid,
            data: data,
            distance: here == null
                ? -1
                : marketDistance(here, marketAreaCenter(data)),
          ),
        );
      } catch (_) {}
    }
    return found;
  }

  /// One tap for a ranch to appear in Market: the place comes from the
  /// phone's location (asked for, with the reason, at that moment), the name
  /// from the ranch, the price from its milk price, with usual hours.
  static Future<bool> listMyRanch(BuildContext context) async {
    final point = await VendorLocation.current(context);
    if (point == null) return false;
    var name = farmName().trim();
    if (name.isEmpty) name = await myName();
    if (name.length > 80) name = name.substring(0, 80);
    await saveListing(
      name: name,
      kind: 'ranch',
      point: point,
      price: defaultMilkPrice(),
      morning: (6 * 60, 8 * 60),
      evening: (17 * 60, 19 * 60),
      active: true,
      holiday: false,
    );
    return true;
  }

  /// Buyers see "On ride" while a delivery ride is running. Only for vendors
  /// who are listed; a failure never disturbs the ride itself.
  static Future<void> setRide(bool onRide) async {
    if (!available) return;
    try {
      final snap = await myListing.get();
      // A start always refreshes the time, in case an earlier ride was never
      // ended (the app was closed): the old time would hide this ride.
      if (!snap.exists || (!onRide && snap.data()?['onRide'] != true)) return;
      await myListing.update({
        'onRide': onRide,
        'rideAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Future<List<MarketVendor>> nearby(ll.LatLng here) async {
    final snap = await listings
        .where('cell', whereIn: marketNearbyCells(here))
        .get();
    return [
      for (final doc in snap.docs)
        if (doc.id != signedInUid && doc.data()['active'] == true)
          MarketVendor(
            uid: doc.id,
            data: doc.data(),
            distance: marketDistance(here, marketAreaCenter(doc.data())),
          ),
    ].where((v) => v.distance <= marketSearchSteps.last).toList();
  }

  /// Average stars and number of reviews, counted by the server.
  static Future<(double, int)> rating(String uid) async {
    try {
      final result = await reviewsOf(
        uid,
      ).aggregate(count(), average('stars')).get();
      return (result.getAverage('stars') ?? 0.0, result.count ?? 0);
    } catch (_) {
      return (0.0, 0);
    }
  }

  /// The name buyers and vendors see: the public profile name, else the
  /// VIMO ID, else the name used in this app.
  static Future<String> myName() async {
    var name = '';
    try {
      final profile =
          (await _db.collection('profiles').doc(signedInUid).get()).data() ??
          {};
      name = txt(profile, 'displayName', txt(profile, 'username'));
    } catch (_) {}
    if (name.trim().isEmpty) name = currentUserName();
    if (name.trim().isEmpty) name = 'VIMO';
    name = name.trim();
    return name.length > 80 ? name.substring(0, 80) : name;
  }

  static Future<void> request({
    required MarketVendor vendor,
    required bool regular,
    required double litres,
    required String session,
    required String time,
    required List<String> days,
    required String payment,
    required ll.LatLng? home,
    required String note,
  }) async {
    final name = vendor.name;
    await requests.add({
      'buyerUid': signedInUid,
      'buyerName': await myName(),
      'vendorUid': vendor.uid,
      'vendorName': name.length > 80 ? name.substring(0, 80) : name,
      'kind': regular ? 'regular' : 'today',
      'litres': litres,
      'session': session,
      'time': time,
      'days': regular ? days : <String>[],
      'payment': regular ? payment : '',
      'home': home == null
          ? <String, dynamic>{}
          : {'lat': home.latitude, 'lng': home.longitude},
      'note': note.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> incoming() => requests
      .where('vendorUid', isEqualTo: signedInUid)
      .where('status', isEqualTo: 'pending')
      .snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> toMe() =>
      requests.where('vendorUid', isEqualTo: signedInUid).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> mine() =>
      requests.where('buyerUid', isEqualTo: signedInUid).snapshots();

  /// The vendor's exact place for a buyer whose request is accepted: the
  /// place saved on this phone, else the middle of the listed area.
  static Future<Map<String, double>?> _myPoint() async {
    final saved = asMap(settingValue('marketPoint', {}));
    if (saved['lat'] is num && saved['lng'] is num) {
      return {
        'lat': (saved['lat'] as num).toDouble(),
        'lng': (saved['lng'] as num).toDouble(),
      };
    }
    try {
      final listing = (await myListing.get()).data();
      if (listing == null) return null;
      final center = marketAreaCenter(listing);
      return {'lat': center.latitude, 'lng': center.longitude};
    } catch (_) {
      return null;
    }
  }

  static Future<void> accept(String id) async {
    final point = await _myPoint();
    if (point == null) throw StateError('listing');
    await requests.doc(id).update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
      'vendorPoint': point,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> offer(String id, {required int? time, double? price}) =>
      requests.doc(id).update({
        'status': 'offered',
        if (time != null) 'offerTime': marketClock(time),
        'offerPrice': ?price,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> decline(String id) => requests.doc(id).update({
    'status': 'declined',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// The buyer agrees to the vendor's new time or price.
  static Future<void> agree(String id) => requests.doc(id).update({
    'status': 'accepted',
    'acceptedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  static Future<void> cancel(String id) => requests.doc(id).update({
    'status': 'cancelled',
    'cancelledBy': signedInUid,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// After a buyer agrees to an offer, the vendor's phone adds its place.
  static Future<void> sharePoint(String id) async {
    final point = await _myPoint();
    if (point == null) return;
    await requests.doc(id).update({
      'vendorPoint': point,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// What proves this account really bought from the vendor: an accepted
  /// request, or an accepted VIMO ID link from that vendor.
  static Future<(String, String)?> reviewProof(String vendorUid) async {
    try {
      final asked = await requests
          .where('buyerUid', isEqualTo: signedInUid)
          .where('vendorUid', isEqualTo: vendorUid)
          .get();
      for (final doc in asked.docs) {
        if (doc.data().containsKey('acceptedAt')) return ('request', doc.id);
      }
      final links = await _db
          .collection('link_requests')
          .where('toUid', isEqualTo: signedInUid)
          .where('fromUid', isEqualTo: vendorUid)
          .where('status', isEqualTo: 'accepted')
          .get();
      if (links.docs.isNotEmpty) return ('link', links.docs.first.id);
    } catch (_) {}
    return null;
  }

  static Future<void> saveReview({
    required String vendorUid,
    required int stars,
    required String text,
    required (String, String) proof,
  }) async {
    final ref = reviewsOf(vendorUid).doc(signedInUid);
    final old = await ref.get();
    await ref.set({
      'stars': stars,
      'text': text.trim(),
      'buyerName': await myName(),
      'proof': proof.$2,
      'proofKind': proof.$1,
      'createdAt': old.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// A regular buyer joins the vendor's customers on this phone, with the
  /// litres, session, days and home pin they asked for.
  static Future<void> addCustomer(Map<String, dynamic> request) async {
    final same = vendorRows(
      'vendor_people',
    ).where((p) => txt(p, 'vimoUid') == txt(request, 'buyerUid'));
    // A customer the vendor deleted earlier comes back with their history.
    final removed = same.where(vendorPersonRemoved).firstOrNull;
    if (same.isNotEmpty && same.every(vendorPersonRemoved)) {
      await setVendorPersonRemoved(removed!, false);
      return;
    }
    if (same.isNotEmpty) return;
    final person = await vendorQuickPerson(
      name: txt(request, 'buyerName', 'VIMO'),
      place: '',
    );
    final days = (request['days'] as List?)?.whereType<String>() ?? [];
    final home = asMap(request['home']);
    final price = numv(request, 'offerPrice');
    final updated = {
      ...person,
      'quantity': numv(request, 'litres'),
      if (price > 0) 'price': price,
      'sessions': [txt(request, 'session', 'Morning')],
      // Customers count days from Sunday (0) to Saturday (6).
      'days': [
        for (final day in days)
          if (marketWeekdays.indexOf(day) case final i when i >= 0) (i + 1) % 7,
      ]..sort(),
      'paymentCycle': switch (txt(request, 'payment')) {
        'daily' => 'Daily',
        'weekly' => 'Weekly',
        _ => 'Monthly',
      },
      if (home['lat'] is num) 'lat': home['lat'],
      if (home['lng'] is num) 'lng': home['lng'],
      'vimoUid': txt(request, 'buyerUid'),
      'vimoKind': 'person',
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    };
    await Hive.box('vendor_people').put(person['id'], updated);
    vendorWorkspaceRevision.value++;
    AutoSyncService.markDirty(reason: 'vendor person');
  }
}

void _marketProblem(BuildContext context, Object error) {
  if (!context.mounted) return;
  snack(
    context,
    error is FirebaseException && error.code == 'unavailable'
        ? bi(
            'No internet. Try again when you are online.',
            'இணையம் இல்லை. இணையம் வந்ததும் மீண்டும் முயற்சிக்கவும்.',
          )
        : ui('Unable to save. Try again.'),
  );
}

// -----------------------------------------------------------------------------
//  Small pieces
// -----------------------------------------------------------------------------

class MarketStatusPill extends StatelessWidget {
  final MarketOpen status;
  const MarketStatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final color = marketStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s8,
        vertical: Space.s4,
      ),
      decoration: ShapeDecoration(
        shape: const SquircleBorder(radius: Gold.r8),
        color: color.withValues(alpha: 0.13),
      ),
      child: Text(
        marketStatusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class MarketStars extends StatelessWidget {
  final double rating;
  final int reviews;
  final double size;
  const MarketStars({
    super.key,
    required this.rating,
    required this.reviews,
    this.size = 14,
  });
  @override
  Widget build(BuildContext context) {
    if (reviews == 0) {
      return Text(
        bi('No reviews yet', 'இன்னும் மதிப்பீடு இல்லை'),
        style: TextStyle(color: Ink.muted, fontSize: size - 1),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w700,
            color: Ink.navy,
          ),
        ),
        const SizedBox(width: Space.s4),
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i - .25
                ? CupertinoIcons.star_fill
                : rating >= i - .75
                ? CupertinoIcons.star_lefthalf_fill
                : CupertinoIcons.star,
            size: size,
            color: Ink.goldDeep,
          ),
        const SizedBox(width: Space.s4),
        Text(
          '($reviews)',
          style: TextStyle(color: Ink.muted, fontSize: size - 1),
        ),
      ],
    );
  }
}

/// What kind of seller a listing is, in words.
String marketKindLabel(String kind) => switch (kind) {
  'shop' => bi('Milk shop', 'பால் கடை'),
  'ranch' => bi('Ranch', 'பண்ணை'),
  _ => bi('Milk vendor', 'பால் வியாபாரி'),
};

/// The listing kind this account appears as in Market: a milk shop, a
/// vendor, or a ranch for people who only run a ranch.
String marketListingKind() => milkShopMode
    ? 'shop'
    : workspaceEnabled('Vendor')
    ? 'vendor'
    : 'ranch';

Widget _marketIcon(String kind, {double size = 22}) => kind == 'ranch'
    ? CowMark(size: size + 2, color: Ink.violetDeep)
    : _marketMilkIcon(kind == 'shop', size: size);

Widget _marketMilkIcon(bool shop, {double size = 22}) => shop
    ? Icon(Icons.storefront_rounded, color: Ink.violetDeep, size: size)
    : MilkVendorIcon(size: size + 4, color: Ink.violetDeep);

Future<int?> _pickMarketTime(BuildContext context, int? initial) async {
  final start = initial ?? 6 * 60;
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
  );
  return picked == null ? null : picked.hour * 60 + picked.minute;
}

// -----------------------------------------------------------------------------
//  Buyer: the Nearby tab
// -----------------------------------------------------------------------------

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});
  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  ll.LatLng? _here;
  List<MarketVendor>? _vendors;
  bool _loading = false;
  bool _failed = false;
  int _sort = 0;

  /// Index into [marketSearchSteps]: starts at the nearest distance that
  /// finds someone; people can widen or narrow it.
  int _step = 0;

  /// 0 everyone, 1 milk sellers (vendors and shops), 2 ranches.
  int _kind = 0;

  /// The person picked a distance; otherwise the nearest that finds someone.
  bool _distanceChosen = false;

  /// 0 sellers near you, 1 products.
  int _tab = 0;

  /// The saved place was searched once this visit (no location asked).
  bool _autoSearched = false;

  /// Products: category chip, sort and "on sale only".
  String _category = '';
  String _productSort = 'new';
  bool _onSale = false;

  /// Bumped by pull to refresh so the product list loads again.
  int _productsKey = 0;

  int get _filtersOn => _tab == 1 || _search.text.trim().length >= 2
      ? (_productSort != 'new' ? 1 : 0) + (_onSale ? 1 : 0)
      : (_sort != 0 ? 1 : 0) + (_kind != 0 ? 1 : 0) + (_distanceChosen ? 1 : 0);

  String get _filterSummary => [
    bi('Within ${marketStepLabel(_step)}', '${marketStepLabel(_step)}-க்குள்'),
    _sort == 1 ? bi('Top rated', 'சிறந்த மதிப்பீடு') : bi('Nearest', 'அருகில்'),
    switch (_kind) {
      1 => bi('Milk sellers', 'பால் விற்பவர்'),
      2 => bi('Ranches', 'பண்ணைகள்'),
      _ => bi('All', 'அனைத்தும்'),
    },
  ].join(' · ');

  /// The filter button: what it holds follows what is on screen.
  Future<void> _filters() => _tab == 1 || _search.text.trim().length >= 2
      ? _productFilters()
      : _sellerFilters();

  /// Products: sort and "on sale only" (categories are the chips).
  Future<void> _productFilters() async {
    var sort = _productSort, onSale = _onSale;
    final apply = await showAppleSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ink.canvasTop,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        bi('Filters', 'வடிகட்டிகள்'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => set(() {
                        sort = 'new';
                        onSale = false;
                      }),
                      child: Text(bi('Reset', 'மீட்டமை')),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s12),
                _InsetGroup(
                  children: [
                    for (final s in shopSorts)
                      ListTile(
                        title: Text(bi(s.$2, s.$3)),
                        trailing: sort == s.$1
                            ? Icon(
                                CupertinoIcons.checkmark_alt,
                                color: Ink.violetDeep,
                              )
                            : null,
                        onTap: () {
                          selectionFeedback();
                          set(() => sort = s.$1);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: Space.s12),
                _InsetGroup(
                  children: [
                    SoundSwitchListTile(
                      value: onSale,
                      onChanged: (v) => set(() => onSale = v),
                      title: Text(bi('On sale only', 'விற்பனையில் மட்டும்')),
                      subtitle: Text(
                        bi('Hide sold-out items', 'விற்றுத் தீர்ந்தவற்றை மறை'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s24),
                LiquidButton(
                  label: bi('Show results', 'முடிவுகளைக் காட்டு'),
                  onPressed: () => Navigator.pop(sheet, true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (apply != true || !mounted) return;
    setState(() {
      _productSort = sort;
      _onSale = onSale;
    });
  }

  /// Sellers: sort, distance and kind, and searching from here now.
  Future<void> _sellerFilters() async {
    var sort = _sort, step = _step, kind = _kind, chosen = _distanceChosen;
    final apply = await showAppleSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ink.canvasTop,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) {
          Widget title(String text) => Padding(
            padding: const EdgeInsets.only(top: Space.s16, bottom: Space.s8),
            child: Text(
              text,
              style: TextStyle(
                color: Ink.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bi('Filters', 'வடிகட்டிகள்'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => set(() {
                          sort = 0;
                          kind = 0;
                          chosen = false;
                          step = marketSearchStep(
                            (_vendors ?? const <MarketVendor>[]).map(
                              (v) => v.distance,
                            ),
                          );
                        }),
                        child: Text(bi('Reset', 'மீட்டமை')),
                      ),
                    ],
                  ),
                  title(bi('Sort by', 'வரிசை')),
                  LiquidSegmentBar(
                    labels: [
                      bi('Nearest', 'அருகில்'),
                      bi('Top rated', 'சிறந்த மதிப்பீடு'),
                    ],
                    index: sort,
                    onChanged: (v) => set(() => sort = v),
                  ),
                  title(bi('Distance', 'தூரம்')),
                  Semantics(
                    label: bi('Search distance', 'தேடும் தூரம்'),
                    child: LiquidSegmentBar(
                      labels: [
                        for (var i = 0; i < marketSearchSteps.length; i++)
                          marketStepLabel(i),
                      ],
                      index: step,
                      onChanged: (v) => set(() {
                        step = v;
                        chosen = true;
                      }),
                    ),
                  ),
                  title(bi('Show', 'காட்டு')),
                  LiquidSegmentBar(
                    labels: [
                      bi('All', 'அனைத்தும்'),
                      bi('Milk sellers', 'பால் விற்பவர்'),
                      bi('Ranches', 'பண்ணைகள்'),
                    ],
                    index: kind,
                    onChanged: (v) => set(() => kind = v),
                  ),
                  const SizedBox(height: Space.s16),
                  Text(
                    bi(
                      'Places are shown as an area of about 200 m, never the exact spot.',
                      'இடங்கள் சுமார் 200 மீ பகுதியாக மட்டுமே காட்டப்படும்; சரியான இடம் அல்ல.',
                    ),
                    style: TextStyle(color: Ink.muted, fontSize: 13),
                  ),
                  const SizedBox(height: Space.s16),
                  GhostButton(
                    label: bi(
                      'Search from where I am now',
                      'இப்போது இருக்கும் இடத்திலிருந்து தேடு',
                    ),
                    icon: CupertinoIcons.location_fill,
                    onPressed: () => Navigator.pop(sheet, false),
                  ),
                  const SizedBox(height: Space.s8),
                  LiquidButton(
                    label: bi('Show results', 'முடிவுகளைக் காட்டு'),
                    onPressed: () => Navigator.pop(sheet, true),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (apply == null || !mounted) return;
    setState(() {
      _sort = sort;
      _step = step;
      _kind = kind;
      _distanceChosen = chosen;
    });
    // "Search from where I am now" closes the sheet with false.
    if (!apply) unawaited(_find());
  }

  final _search = TextEditingController();
  Timer? _debounce;
  List<MarketVendor>? _found;
  bool _searching = false;

  /// Whether this ranch is already in Market (null while checking).
  bool? _listed;

  @override
  void initState() {
    super.initState();
    // The last place searched from, kept on this phone: Market opens with
    // results at once and never asks for location by itself.
    // Kept for the phone, not the account, which may still be loading at
    // launch; the search itself starts once Market is available (build).
    var saved = asMap(settingValue('marketHere', {}));
    // A place saved per account by the previous version still counts.
    if (saved.isEmpty && Hive.isBoxOpen('settings')) {
      final box = Hive.box('settings');
      for (final k in box.keys) {
        if (k is String && k.startsWith('acct_') && k.endsWith('_marketHere')) {
          saved = asMap(box.get(k));
          if (saved.isNotEmpty) break;
        }
      }
    }
    if (saved['lat'] is num && saved['lng'] is num) {
      _here = ll.LatLng(
        (saved['lat'] as num).toDouble(),
        (saved['lng'] as num).toDouble(),
      );
    }
    if (MarketService.available && workspaceEnabled('Ranch')) {
      MarketService.myListing
          .get()
          .then((d) {
            if (mounted) setState(() => _listed = d.exists);
          })
          .catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _found = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final found = await MarketService.searchByName(text, here: _here);
        // Nearby listings saved before names were searchable still match.
        final q = text.trim().toLowerCase();
        final seen = {for (final v in found) v.uid};
        final local = [
          for (final v in _vendors ?? const <MarketVendor>[])
            if (!seen.contains(v.uid) && v.name.toLowerCase().contains(q)) v,
        ];
        if (mounted && _search.text == text) {
          setState(() {
            _found = [...found, ...local];
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _listRanch() async {
    try {
      final ok = await MarketService.listMyRanch(context);
      if (!ok || !mounted) return;
      setState(() => _listed = true);
      snack(
        context,
        bi(
          'Your ranch is in Market. Change details in Settings → App Settings → Market listing.',
          'உங்கள் பண்ணை சந்தையில் உள்ளது. விவரங்களை Settings → App Settings → சந்தைப் பட்டியல்-ல் மாற்றலாம்.',
        ),
        tone: SnackTone.success,
      );
    } catch (error) {
      if (mounted) _marketProblem(context, error);
    }
  }

  bool _kindMatches(MarketVendor v) => switch (_kind) {
    1 => !v.ranch,
    2 => v.ranch,
    _ => true,
  };

  /// Finds who is near. [fresh] asks the phone where it is now (only when
  /// the person taps for it); otherwise the last place is used.
  Future<void> _find({bool fresh = true}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final here = fresh ? await VendorLocation.current(context) : _here;
    if (!mounted) return;
    if (here == null) {
      setState(() => _loading = false);
      return;
    }
    if (fresh) {
      await MarketLocation.remember();
      await setSetting('marketHere', {
        'lat': here.latitude,
        'lng': here.longitude,
      });
    }
    try {
      final found = await MarketService.nearby(here);
      final rated = await Future.wait(
        found.map((v) async {
          final (rating, reviews) = await MarketService.rating(v.uid);
          return v.rated(rating, reviews);
        }),
      );
      if (!mounted) return;
      setState(() {
        _here = here;
        _vendors = rated;
        if (!_distanceChosen) {
          _step = marketSearchStep(rated.map((v) => v.distance));
        }
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!MarketService.available) {
      return Shell(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.s32),
            child: AppText(
              bi(
                'Sign in to find milk near you.',
                'அருகிலுள்ள பாலைக் கண்டறிய உள்நுழையவும்.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: Ink.muted, fontSize: 16),
            ),
          ),
        ),
      );
    }
    if (_here != null && _vendors == null && !_loading && !_autoSearched) {
      _autoSearched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_find(fresh: false));
      });
    }
    final vendors = _vendors == null
        ? null
        : sortMarketVendors(
            _vendors!
                .where(
                  (v) =>
                      v.distance <= marketSearchSteps[_step] && _kindMatches(v),
                )
                .toList(),
            byRating: _sort == 1,
          );
    final searching = _search.text.trim().length >= 2;
    final now = DateTime.now();
    final sellers = _tab == 0;
    return Shell(
      child: RefreshIndicator(
        onRefresh: () async {
          if (sellers && _here != null) await _find(fresh: false);
          if (mounted) setState(() => _productsKey++);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(21, 12, 21, 120),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            // One line to find anything: search, then filters for what is
            // shown below.
            Row(
              children: [
                Expanded(
                  child: CupertinoSearchTextField(
                    controller: _search,
                    placeholder: bi(
                      'Search ranches, sellers, products',
                      'பண்ணை, விற்பவர், பொருளைத் தேடு',
                    ),
                    onChanged: _onSearch,
                    style: TextStyle(color: Ink.navy),
                  ),
                ),
                const SizedBox(width: Space.s4),
                IconButton(
                  tooltip: bi('Filters', 'வடிகட்டிகள்'),
                  onPressed: _filters,
                  icon: Badge(
                    isLabelVisible: _filtersOn > 0,
                    label: Text('$_filtersOn'),
                    backgroundColor: Ink.violetDeep,
                    child: Icon(
                      CupertinoIcons.slider_horizontal_3,
                      color: Ink.violetDeep,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s12),
            if (searching) ...[
              if (_searching)
                const SkeletonList(rows: 3, padding: EdgeInsets.zero)
              else if ((_found ?? const []).isNotEmpty) ...[
                _InsetGroup(
                  children: [
                    for (final vendor in _found!)
                      _NearbyVendorRow(
                        vendor: vendor,
                        status: marketStatus(vendor.data, now),
                        onTap: () =>
                            push(context, MarketVendorScreen(vendor: vendor)),
                      ),
                  ],
                ),
                const SizedBox(height: Space.s16),
              ],
              MarketProducts(
                key: ValueKey('search-$_productsKey'),
                query: _search.text,
                category: _category,
                sort: _productSort,
                available: _onSale,
              ),
            ] else ...[
              // Sellers or products, then likes and orders: everything else
              // sits inside one of these.
              Row(
                children: [
                  Expanded(
                    child: LiquidSegmentBar(
                      // Text only: HIG segmented-controls.md, "Prefer using
                      // either text or images — not a mix of both".
                      labels: [
                        bi('Sellers', 'விற்பவர்கள்'),
                        bi('Products', 'பொருட்கள்'),
                      ],
                      index: _tab,
                      onChanged: (v) => setState(() => _tab = v),
                    ),
                  ),
                  IconButton(
                    tooltip: bi('Liked', 'விரும்பியவை'),
                    onPressed: () => push(context, const LikedScreen()),
                    icon: Icon(CupertinoIcons.heart, color: Ink.violetDeep),
                  ),
                  IconButton(
                    tooltip: bi('My orders', 'என் ஆர்டர்கள்'),
                    onPressed: () => push(context, const OrdersScreen()),
                    icon: Icon(CupertinoIcons.cube_box, color: Ink.violetDeep),
                  ),
                ],
              ),
              const SizedBox(height: Space.s4),
              // A short cross-fade between the two lists (none with Reduce
              // Motion), so the switch reads as one view changing.
              AnimatedSwitcher(
                duration: Motion.reduced(context)
                    ? Duration.zero
                    : Motion.short,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: Column(
                  key: ValueKey(_tab),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: sellers
                      ? _sellerList(vendors, now)
                      : _productList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One tappable line saying what the filters are set to. A full 44 pt
  /// tall row, so it is as easy to hit as any button.
  Widget _summary(String text) => Semantics(
    button: true,
    label: bi('Filters: $text', 'வடிகட்டிகள்: $text'),
    excludeSemantics: true,
    child: InkWell(
      onTap: _filters,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: Ink.violetDeep,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down, size: 14, color: Ink.violetDeep),
          ],
        ),
      ),
    ),
  );

  List<Widget> _sellerList(List<MarketVendor>? vendors, DateTime now) => [
    if (workspaceEnabled('Ranch') && _listed == false) ...[
      Glass(
        radius: Gold.r27,
        padding: const EdgeInsets.all(Space.s16),
        child: Row(
          children: [
            CowMark(size: 34, color: Ink.violetDeep),
            const SizedBox(width: Space.s12),
            Expanded(
              child: Text(
                bi(
                  'Let buyers near you find your ranch.',
                  'அருகிலுள்ளவர்கள் உங்கள் பண்ணையைக் கண்டறியட்டும்.',
                ),
                style: TextStyle(color: Ink.body, fontSize: 15),
              ),
            ),
            const SizedBox(width: Space.s8),
            TextButton(
              style: liquidActionStyle(primary: true),
              onPressed: _listRanch,
              child: Text(bi('Show', 'காட்டு')),
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.s16),
    ],
    _PreviousSellers(here: _here),
    const _MyMilkRequests(),
    if (_here == null)
      Glass(
        radius: Gold.r27,
        padding: const EdgeInsets.all(Space.s20),
        child: Column(
          children: [
            Icon(
              CupertinoIcons.location_circle_fill,
              size: 44,
              color: Ink.violetDeep,
            ),
            const SizedBox(height: Space.s12),
            Text(
              bi(
                'Your location is used only to find sellers near you, and kept on this phone only.',
                'அருகிலுள்ள விற்பவர்களைக் கண்டறிய மட்டுமே உங்கள் இடம் பயன்படும்; இந்த phone-ல் மட்டும் வைக்கப்படும்.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: Ink.body, fontSize: 15),
            ),
            const SizedBox(height: Space.s16),
            LiquidButton(
              label: bi('Find sellers near me', 'அருகில் விற்பவர்களைத் தேடு'),
              icon: CupertinoIcons.location_fill,
              busy: _loading,
              onPressed: _find,
            ),
          ],
        ),
      )
    else ...[
      _summary(_filterSummary),
      const SizedBox(height: Space.s4),
      if (_loading || vendors == null)
        const SkeletonList(rows: 2, padding: EdgeInsets.zero)
      else if (_failed)
        _MarketNote(
          bi(
            'Could not search. Check the internet and pull down to try again.',
            'தேட முடியவில்லை. இணையத்தைச் சரிபார்த்து, கீழே இழுத்து மீண்டும் முயற்சிக்கவும்.',
          ),
        )
      else if (vendors.isEmpty)
        _MarketNote(
          _step < marketSearchSteps.length - 1
              ? bi(
                  'No one within ${marketStepLabel(_step)}. Try ${marketStepLabel(_step + 1)} in Filters.',
                  '${marketStepLabel(_step)}-க்குள் யாரும் இல்லை. வடிகட்டியில் ${marketStepLabel(_step + 1)} முயற்சிக்கவும்.',
                )
              : bi(
                  'No sellers are listed within 10 km yet.',
                  '10 கி.மீ-க்குள் இன்னும் விற்பவர்கள் இல்லை.',
                ),
        )
      else
        _InsetGroup(
          children: [
            for (final vendor in vendors)
              _NearbyVendorRow(
                vendor: vendor,
                status: marketStatus(vendor.data, now),
                onTap: () => push(context, MarketVendorScreen(vendor: vendor)),
              ),
          ],
        ),
    ],
  ];

  List<Widget> _productList() => [
    // Categories are the one thing people browse by, so they stay in view.
    SizedBox(
      height: 40,
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
                  setState(() => _category = c.$1);
                },
              ),
            ),
        ],
      ),
    ),
    const SizedBox(height: Space.s8),
    _summary(
      [
        shopLabel(shopSorts, _productSort),
        if (_onSale) bi('On sale only', 'விற்பனையில் மட்டும்'),
      ].join(' · '),
    ),
    const SizedBox(height: Space.s4),
    MarketProducts(
      key: ValueKey('products-$_productsKey'),
      query: '',
      category: _category,
      sort: _productSort,
      available: _onSale,
    ),
  ];
}

/// "You buy from": the sellers whose milk requests this buyer has had
/// accepted, at the top of Market for a quick way back.
class _PreviousSellers extends StatefulWidget {
  final ll.LatLng? here;
  const _PreviousSellers({this.here});

  @override
  State<_PreviousSellers> createState() => _PreviousSellersState();
}

class _PreviousSellersState extends State<_PreviousSellers> {
  String _key = '';
  Future<List<MarketVendor>>? _future;

  /// Looked up again only when the sellers or the place change, not on
  /// every rebuild of Market.
  Future<List<MarketVendor>> _sellers(
    String key,
    List<Map<String, dynamic>> requests,
  ) {
    final full = '$key|${widget.here}';
    if (_future == null || full != _key) {
      _key = full;
      _future = MarketService.previousSellers(requests, here: widget.here);
    }
    return _future!;
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: MarketService.mine(),
        builder: (context, snap) {
          final requests = [
            for (final d
                in snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              d.data(),
          ];
          if (!requests.any((r) => txt(r, 'status') == 'accepted')) {
            return const SizedBox.shrink();
          }
          final key = requests
              .where((r) => txt(r, 'status') == 'accepted')
              .map((r) => txt(r, 'vendorUid'))
              .toSet()
              .join(',');
          return FutureBuilder<List<MarketVendor>>(
            future: _sellers(key, requests),
            builder: (context, sellers) {
              final list = sellers.data ?? const <MarketVendor>[];
              if (list.isEmpty) return const SizedBox.shrink();
              final now = DateTime.now();
              return Padding(
                padding: const EdgeInsets.only(bottom: Space.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // A quiet label, not a heading: Market is the one title.
                    Text(
                      bi('You buy from', 'நீங்கள் வாங்குபவர்கள்'),
                      style: TextStyle(
                        color: Ink.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Space.s8),
                    _InsetGroup(
                      children: [
                        for (final vendor in list)
                          _NearbyVendorRow(
                            vendor: vendor,
                            status: marketStatus(vendor.data, now),
                            onTap: () => push(
                              context,
                              MarketVendorScreen(vendor: vendor),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
}

class _MarketNote extends StatelessWidget {
  final String text;
  const _MarketNote(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s32),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: Ink.muted, fontSize: 15),
    ),
  );
}

class _NearbyVendorRow extends StatelessWidget {
  final MarketVendor vendor;
  final MarketOpen status;
  final VoidCallback onTap;
  const _NearbyVendorRow({
    required this.vendor,
    required this.status,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s16,
        Space.s12,
        Space.s12,
        Space.s12,
      ),
      child: Row(
        children: [
          SizedBox(width: 26, child: Center(child: _marketIcon(vendor.kind))),
          const SizedBox(width: Space.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        vendor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Ink.navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.s8),
                    MarketStatusPill(status),
                  ],
                ),
                const SizedBox(height: Space.s4),
                Text(
                  [
                    marketKindLabel(vendor.kind),
                    if (vendor.distance >= 0)
                      marketDistanceLabel(vendor.distance),
                    if (vendor.price > 0)
                      '${money(vendor.price)}/${bi('L', 'லி')}',
                  ].join(' · '),
                  style: TextStyle(color: Ink.body, fontSize: 14),
                ),
                const SizedBox(height: Space.s4),
                MarketStars(rating: vendor.rating, reviews: vendor.reviews),
              ],
            ),
          ),
          Icon(CupertinoIcons.chevron_forward, size: 15, color: Ink.faint),
        ],
      ),
    ),
  );
}

/// The buyer's own requests, newest first: what was asked and where it stands.
class _MyMilkRequests extends StatelessWidget {
  const _MyMilkRequests();
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: MarketService.mine(),
    builder: (context, snap) {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final docs =
          (snap.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              .where((d) {
                final status = txt(d.data(), 'status');
                final updated = _marketTime(d.data()['updatedAt']);
                // Finished requests drop off after a week.
                return status == 'pending' ||
                    status == 'offered' ||
                    status == 'accepted' ||
                    updated == null ||
                    updated.isAfter(weekAgo);
              })
              .toList()
            ..sort(
              (a, b) => (_marketTime(b.data()['createdAt']) ?? DateTime.now())
                  .compareTo(
                    _marketTime(a.data()['createdAt']) ?? DateTime.now(),
                  ),
            );
      if (docs.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Space.s4, bottom: Space.s8),
              child: Text(
                bi('MY REQUESTS', 'என் கோரிக்கைகள்'),
                style: TextStyle(
                  color: Ink.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .4,
                ),
              ),
            ),
            _InsetGroup(
              children: [
                for (final doc in docs.take(6))
                  _MarketRequestRow(id: doc.id, data: doc.data(), buyer: true),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _MarketRequestRow extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final bool buyer;
  const _MarketRequestRow({
    required this.id,
    required this.data,
    required this.buyer,
  });

  Future<void> _cancel(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AppleAlert(
        title: AppText(
          bi('Cancel this request?', 'இந்தக் கோரிக்கையை ரத்து செய்யவா?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: AppText(bi('Keep', 'வைத்திரு')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: AppText(bi('Cancel request', 'ரத்து செய்')),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    try {
      await MarketService.cancel(id);
    } catch (error) {
      if (context.mounted) _marketProblem(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = txt(data, 'status');
    final open = const {'pending', 'offered', 'accepted'}.contains(status);
    final offerTime = marketMinutes(txt(data, 'offerTime'));
    final offerPrice = numv(data, 'offerPrice');
    return ListTile(
      minTileHeight: 64,
      leading: Icon(
        status == 'accepted'
            ? CupertinoIcons.checkmark_seal_fill
            : CupertinoIcons.drop_fill,
        color: marketRequestColor(status),
      ),
      title: Text(
        buyer
            ? txt(data, 'vendorName', 'VIMO')
            : txt(data, 'buyerName', 'VIMO'),
        style: TextStyle(fontWeight: FontWeight.w600, color: Ink.navy),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(marketRequestSummary(data)),
          if (offerTime != null || offerPrice > 0)
            Text(
              [
                if (offerTime != null) marketTimeLabel(offerTime),
                if (offerPrice > 0) '${money(offerPrice)}/${bi('L', 'லி')}',
              ].join(' · '),
              style: TextStyle(
                color: Ink.violetDeep,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(
            marketRequestState(data, buyer: buyer),
            style: TextStyle(
              color: marketRequestColor(status),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      trailing: open
          ? IconButton(
              tooltip: bi('Cancel request', 'ரத்து செய்'),
              icon: Icon(CupertinoIcons.xmark_circle, color: Ink.faint),
              onPressed: () => _cancel(context),
            )
          : null,
    );
  }
}

// -----------------------------------------------------------------------------
//  Buyer: one vendor
// -----------------------------------------------------------------------------

class MarketVendorScreen extends StatefulWidget {
  final MarketVendor vendor;
  const MarketVendorScreen({super.key, required this.vendor});
  @override
  State<MarketVendorScreen> createState() => _MarketVendorScreenState();
}

class _MarketVendorScreenState extends State<MarketVendorScreen> {
  late final Future<(String, String)?> _proof = MarketService.reviewProof(
    widget.vendor.uid,
  );

  MarketVendor get v => widget.vendor;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = marketStatus(v.data, now);
    final detail = marketStatusDetail(v.data, now);
    return Scaffold(
      appBar: AppBar(title: Text(v.name)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: MarketService.mine(),
        builder: (context, snap) {
          final mine = [
            for (final d
                in snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              if (txt(d.data(), 'vendorUid') == v.uid) d,
          ];
          final open = mine.where(
            (d) => const {
              'pending',
              'offered',
              'accepted',
            }.contains(txt(d.data(), 'status')),
          );
          final exact = [
            for (final d in mine)
              if (txt(d.data(), 'status') == 'accepted' &&
                  asMap(d.data()['vendorPoint'])['lat'] is num)
                asMap(d.data()['vendorPoint']),
          ];
          final point = exact.isEmpty
              ? null
              : ll.LatLng(numv(exact.first, 'lat'), numv(exact.first, 'lng'));
          return Shell(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(21, 8, 21, 40),
              children: [
                Glass(
                  radius: Gold.r27,
                  padding: const EdgeInsets.all(Space.s16),
                  child: Row(
                    children: [
                      Container(
                        width: Space.s56,
                        height: Space.s56,
                        decoration: ShapeDecoration(
                          shape: const SquircleBorder(radius: Gold.r21),
                          color: Ink.violet.withValues(alpha: .13),
                        ),
                        child: Center(child: _marketIcon(v.kind, size: 28)),
                      ),
                      const SizedBox(width: Space.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              marketKindLabel(v.kind),
                              style: TextStyle(color: Ink.muted, fontSize: 13),
                            ),
                            const SizedBox(height: Space.s4),
                            Wrap(
                              spacing: Space.s8,
                              runSpacing: Space.s4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                MarketStatusPill(status),
                                if (detail.isNotEmpty)
                                  Text(
                                    detail,
                                    style: TextStyle(
                                      color: Ink.body,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: Space.s4),
                            MarketStars(rating: v.rating, reviews: v.reviews),
                          ],
                        ),
                      ),
                      if (v.price > 0)
                        Column(
                          children: [
                            Text(
                              money(v.price),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Ink.navy,
                              ),
                            ),
                            Text(
                              bi('per litre', 'லிட்டருக்கு'),
                              style: TextStyle(color: Ink.muted, fontSize: 12),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s12),
                // Talk to them or see who they are, before asking for milk.
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: bi('Message', 'செய்தி'),
                        icon: CupertinoIcons.chat_bubble_2_fill,
                        onPressed: () async {
                          try {
                            final id = await DirectChatService.open(v.uid);
                            if (context.mounted) {
                              await push(
                                context,
                                DirectChatScreen(chatId: id, peer: v.uid),
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
                    ),
                    const SizedBox(width: Space.s12),
                    Expanded(
                      child: GhostButton(
                        label: bi('Profile', 'ப்ரொஃபைல்'),
                        icon: CupertinoIcons.person_crop_circle,
                        onPressed: () =>
                            push(context, SocialProfileScreen(uid: v.uid)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s16),
                ClipPath(
                  clipper: SquircleClipper(Gold.r27),
                  child: SizedBox(
                    height: 180,
                    child: VimoMap(
                      center: point ?? marketAreaCenter(v.data),
                      zoom: point == null ? 15 : 16,
                      interactive: false,
                      layers: [
                        if (point == null)
                          fm.CircleLayer(
                            circles: [
                              fm.CircleMarker(
                                point: marketAreaCenter(v.data),
                                radius: marketAreaRadius,
                                useRadiusInMeter: true,
                                color: Ink.violet.withValues(alpha: .18),
                                borderColor: Ink.violet,
                                borderStrokeWidth: 1.5,
                              ),
                            ],
                          )
                        else
                          fm.MarkerLayer(
                            markers: [
                              fm.Marker(
                                point: point,
                                width: 44,
                                height: 44,
                                alignment: Alignment.topCenter,
                                child: Icon(
                                  CupertinoIcons.location_solid,
                                  color: Ink.violetDeep,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.s8),
                Text(
                  point == null
                      ? bi(
                          'Shown as an area of about 200 m. The exact place is shared once your request is accepted.',
                          'சுமார் 200 மீ பகுதியாகக் காட்டப்படுகிறது. உங்கள் கோரிக்கை ஏற்கப்பட்டதும் சரியான இடம் பகிரப்படும்.',
                        )
                      : bi(
                          'Your request was accepted, so the exact place is shared with you.',
                          'உங்கள் கோரிக்கை ஏற்கப்பட்டதால், சரியான இடம் உங்களுடன் பகிரப்பட்டுள்ளது.',
                        ),
                  style: TextStyle(color: Ink.muted, fontSize: 13),
                ),
                if (marketWindows(v.data).isNotEmpty) ...[
                  const SizedBox(height: Space.s20),
                  _InsetGroup(
                    children: [
                      for (final key in const ['morning', 'evening'])
                        if (marketMinutes(txt(asMap(v.data[key]), 'start'))
                            case final start?)
                          ListTile(
                            leading: Icon(
                              key == 'morning'
                                  ? CupertinoIcons.sunrise_fill
                                  : CupertinoIcons.sunset_fill,
                              color: Ink.amber,
                            ),
                            title: Text(
                              marketSessionLabel(
                                key == 'morning' ? 'Morning' : 'Evening',
                              ),
                            ),
                            trailing: Text(
                              '${marketTimeLabel(start)} – ${marketTimeLabel(marketMinutes(txt(asMap(v.data[key]), 'end')) ?? start)}',
                              style: TextStyle(color: Ink.body),
                            ),
                          ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.s20),
                if (open.isNotEmpty)
                  _InsetGroup(
                    children: [
                      for (final d in open)
                        _MarketRequestRow(
                          id: d.id,
                          data: d.data(),
                          buyer: true,
                        ),
                    ],
                  )
                else
                  LiquidButton(
                    label: bi('Request milk', 'பால் கேள்'),
                    icon: CupertinoIcons.drop_fill,
                    onPressed: () => showMarketRequestSheet(context, v),
                  ),
                const SizedBox(height: Space.s32),
                _MarketReviews(vendor: v, proof: _proof),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MarketReviews extends StatelessWidget {
  final MarketVendor vendor;
  final Future<(String, String)?> proof;
  const _MarketReviews({required this.vendor, required this.proof});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: MarketService.reviewsOf(
          vendor.uid,
        ).orderBy('updatedAt', descending: true).limit(30).snapshots(),
        builder: (context, snap) {
          final docs =
              snap.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final mineDoc = docs.where((d) => d.id == signedInUid).firstOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bi('Reviews', 'மதிப்பீடுகள்'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  FutureBuilder<(String, String)?>(
                    future: proof,
                    builder: (context, p) => p.data == null
                        ? const SizedBox.shrink()
                        : TextButton.icon(
                            onPressed: () => showMarketReviewSheet(
                              context,
                              vendor: vendor,
                              proof: p.data!,
                              current: mineDoc?.data(),
                            ),
                            icon: const Icon(CupertinoIcons.star, size: 18),
                            label: Text(
                              mineDoc == null
                                  ? bi('Write a review', 'மதிப்பிடு')
                                  : bi(
                                      'Edit my review',
                                      'என் மதிப்பீட்டைத் திருத்து',
                                    ),
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s4),
              Text(
                bi(
                  'Only people who really bought from this vendor can review.',
                  'இவரிடம் உண்மையில் வாங்கியவர்கள் மட்டுமே மதிப்பிட முடியும்.',
                ),
                style: TextStyle(color: Ink.muted, fontSize: 13),
              ),
              const SizedBox(height: Space.s12),
              if (docs.isEmpty)
                _MarketNote(bi('No reviews yet', 'இன்னும் மதிப்பீடு இல்லை'))
              else
                _InsetGroup(
                  children: [
                    for (final doc in docs)
                      ListTile(
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                txt(doc.data(), 'buyerName', 'VIMO'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Ink.navy,
                                ),
                              ),
                            ),
                            const SizedBox(width: Space.s8),
                            for (var i = 1; i <= 5; i++)
                              Icon(
                                i <= numv(doc.data(), 'stars')
                                    ? CupertinoIcons.star_fill
                                    : CupertinoIcons.star,
                                size: 13,
                                color: Ink.goldDeep,
                              ),
                          ],
                        ),
                        subtitle: txt(doc.data(), 'text').isEmpty
                            ? null
                            : Text(txt(doc.data(), 'text')),
                      ),
                  ],
                ),
            ],
          );
        },
      );
}

Future<void> showMarketRequestSheet(
  BuildContext context,
  MarketVendor vendor,
) => showAppleSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _MarketRequestSheet(vendor: vendor),
);

class _MarketRequestSheet extends StatefulWidget {
  final MarketVendor vendor;
  const _MarketRequestSheet({required this.vendor});
  @override
  State<_MarketRequestSheet> createState() => _MarketRequestSheetState();
}

class _MarketRequestSheetState extends State<_MarketRequestSheet> {
  bool _regular = false;
  double _litres = 1;
  String _session = vendorSessionNow();
  int? _time;
  final Set<String> _days = {...marketWeekdays};
  String _payment = 'monthly';
  bool _shareHome = true;
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _step(double by) {
    selectionFeedback();
    setState(() => _litres = (_litres + by).clamp(.25, 50).toDouble());
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_regular && _days.isEmpty) {
      snack(
        context,
        bi('Choose at least one day', 'குறைந்தது ஒரு நாளைத் தேர்ந்தெடுக்கவும்'),
      );
      return;
    }
    setState(() => _sending = true);
    ll.LatLng? home;
    if (_shareHome) {
      home = await VendorLocation.current(context);
      if (home == null) {
        if (mounted) setState(() => _sending = false);
        return;
      }
    }
    try {
      await MarketService.request(
        vendor: widget.vendor,
        regular: _regular,
        litres: _litres,
        session: _session,
        time: _time == null ? '' : marketClock(_time!),
        days: [
          for (final d in marketWeekdays)
            if (_days.contains(d)) d,
        ],
        payment: _payment,
        home: home,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      snack(
        context,
        bi(
          'Request sent to ${widget.vendor.name}',
          '${widget.vendor.name}-க்குக் கோரிக்கை அனுப்பப்பட்டது',
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        _marketProblem(context, error);
      }
    }
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(
      left: Space.s4,
      top: Space.s16,
      bottom: Space.s8,
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Ink.muted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: .4,
      ),
    ),
  );

  @override
  // The send button stays in view under the scrolling choices.
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(21, 0, 21, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    bi('Request milk', 'பால் கேள்'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  ),
                  Text(widget.vendor.name, style: TextStyle(color: Ink.muted)),
                  const SizedBox(height: Space.s16),
                  LiquidSegmentBar(
                    labels: [
                      bi('Today only', 'இன்று மட்டும்'),
                      bi('Regular', 'தினசரி'),
                    ],
                    index: _regular ? 1 : 0,
                    onChanged: (v) => setState(() => _regular = v == 1),
                  ),
                  _label(bi('LITRES', 'லிட்டர்')),
                  Glass(
                    radius: Gold.r21,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.s8,
                      vertical: Space.s4,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: bi('Less', 'குறை'),
                          onPressed: _litres > .25 ? () => _step(-.25) : null,
                          icon: const Icon(
                            CupertinoIcons.minus_circle_fill,
                            size: 32,
                          ),
                          color: Ink.violetDeep,
                        ),
                        Expanded(
                          child: Text(
                            '${vendorFieldNumber(_litres)} ${bi('L', 'லி')}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: Ink.navy,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: bi('More', 'கூட்டு'),
                          onPressed: _litres < 50 ? () => _step(.25) : null,
                          icon: const Icon(
                            CupertinoIcons.plus_circle_fill,
                            size: 32,
                          ),
                          color: Ink.violetDeep,
                        ),
                      ],
                    ),
                  ),
                  _label(bi('WHEN', 'எப்போது')),
                  LiquidSegmentBar(
                    labels: [
                      marketSessionLabel('Morning'),
                      marketSessionLabel('Evening'),
                    ],
                    index: _session == 'Evening' ? 1 : 0,
                    onChanged: (v) => setState(
                      () => _session = v == 1 ? 'Evening' : 'Morning',
                    ),
                  ),
                  const SizedBox(height: Space.s8),
                  _InsetGroup(
                    children: [
                      ListTile(
                        leading: Icon(
                          CupertinoIcons.clock_fill,
                          color: Ink.violetDeep,
                        ),
                        title: AppText(bi('Time', 'நேரம்')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _time == null
                                  ? bi('Any time', 'எந்த நேரமும்')
                                  : marketTimeLabel(_time!),
                              style: TextStyle(color: Ink.body),
                            ),
                            if (_time != null)
                              IconButton(
                                tooltip: bi('Any time', 'எந்த நேரமும்'),
                                icon: Icon(
                                  CupertinoIcons.xmark_circle_fill,
                                  color: Ink.faint,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _time = null),
                              ),
                          ],
                        ),
                        onTap: () async {
                          final picked = await _pickMarketTime(
                            context,
                            _time ?? (_session == 'Evening' ? 17 * 60 : 6 * 60),
                          );
                          if (picked != null && mounted) {
                            setState(() => _time = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  if (_regular) ...[
                    _label(bi('DAYS', 'நாட்கள்')),
                    Wrap(
                      spacing: Space.s8,
                      runSpacing: Space.s8,
                      children: [
                        for (final day in marketWeekdays)
                          FilterChip(
                            label: Text(marketWeekdayLabel(day)),
                            selected: _days.contains(day),
                            showCheckmark: false,
                            selectedColor: Ink.tint,
                            labelStyle: TextStyle(
                              color: _days.contains(day)
                                  ? Colors.white
                                  : Ink.violetDeep,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (on) => setState(
                              () => on ? _days.add(day) : _days.remove(day),
                            ),
                          ),
                      ],
                    ),
                    _label(bi('PAYMENT', 'பணம்')),
                    LiquidSegmentBar(
                      labels: [
                        bi('Daily', 'தினமும்'),
                        bi('Weekly', 'வாரம்'),
                        bi('Monthly', 'மாதம்'),
                      ],
                      index: const [
                        'daily',
                        'weekly',
                        'monthly',
                      ].indexOf(_payment),
                      onChanged: (v) => setState(
                        () =>
                            _payment = const ['daily', 'weekly', 'monthly'][v],
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.s16),
                  _InsetGroup(
                    children: [
                      SoundSwitchListTile(
                        value: _shareHome,
                        onChanged: (v) => setState(() => _shareHome = v),
                        title: AppText(
                          bi(
                            'Share my home location',
                            'என் வீட்டு இடத்தைப் பகிர்',
                          ),
                        ),
                        subtitle: AppText(
                          bi(
                            'Only this vendor sees it, to find your home.',
                            'உங்கள் வீட்டைக் கண்டறிய இந்த வியாபாரி மட்டுமே பார்ப்பார்.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s16),
                  TextField(
                    controller: _note,
                    maxLength: 200,
                    maxLines: 2,
                    minLines: 1,
                    decoration: fieldStyle(
                      bi('Note · optional', 'குறிப்பு · விருப்பம்'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(21, 8, 21, 21),
            child: LiquidButton(
              label: bi('Send request', 'கோரிக்கை அனுப்பு'),
              icon: CupertinoIcons.paperplane_fill,
              busy: _sending,
              onPressed: _send,
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showMarketReviewSheet(
  BuildContext context, {
  required MarketVendor vendor,
  required (String, String) proof,
  Map<String, dynamic>? current,
}) => showAppleSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      _MarketReviewSheet(vendor: vendor, proof: proof, current: current),
);

class _MarketReviewSheet extends StatefulWidget {
  final MarketVendor vendor;
  final (String, String) proof;
  final Map<String, dynamic>? current;
  const _MarketReviewSheet({
    required this.vendor,
    required this.proof,
    this.current,
  });
  @override
  State<_MarketReviewSheet> createState() => _MarketReviewSheetState();
}

class _MarketReviewSheetState extends State<_MarketReviewSheet> {
  late int _stars = numv(widget.current ?? {}, 'stars').toInt();
  late final _text = TextEditingController(
    text: txt(widget.current ?? {}, 'text'),
  );
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_stars < 1 || _saving) return;
    setState(() => _saving = true);
    try {
      await MarketService.saveReview(
        vendorUid: widget.vendor.uid,
        stars: _stars,
        text: _text.text,
        proof: widget.proof,
      );
      if (!mounted) return;
      Navigator.pop(context);
      snack(
        context,
        bi('Thanks for your review', 'உங்கள் மதிப்பீட்டிற்கு நன்றி'),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _marketProblem(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.vendor.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Space.s12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i',
                    iconSize: 40,
                    onPressed: () {
                      selectionFeedback();
                      setState(() => _stars = i);
                    },
                    icon: Icon(
                      i <= _stars
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      color: Ink.goldDeep,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.s12),
            TextField(
              controller: _text,
              maxLength: 300,
              maxLines: 4,
              minLines: 2,
              decoration: fieldStyle(
                bi('Your review · optional', 'உங்கள் கருத்து · விருப்பம்'),
              ),
            ),
            const SizedBox(height: Space.s8),
            LiquidButton(
              label: bi('Save review', 'மதிப்பீட்டைச் சேமி'),
              busy: _saving,
              onPressed: _stars < 1 ? null : _save,
            ),
          ],
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
//  Vendor: being listed
// -----------------------------------------------------------------------------

class MarketListingScreen extends StatefulWidget {
  const MarketListingScreen({super.key});
  @override
  State<MarketListingScreen> createState() => _MarketListingScreenState();
}

class _MarketListingScreenState extends State<MarketListingScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController(
    text: vendorFieldNumber(defaultMilkPrice()),
  );
  ll.LatLng? _point;
  bool _active = true, _holiday = false, _listed = false;
  bool _morningOn = true, _eveningOn = false;
  int _morningStart = 5 * 60 + 30, _morningEnd = 8 * 60;
  int _eveningStart = 17 * 60, _eveningEnd = 19 * 60 + 30;
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = asMap(settingValue('marketPoint', {}));
    if (saved['lat'] is num && saved['lng'] is num) {
      _point = ll.LatLng(numv(saved, 'lat'), numv(saved, 'lng'));
    }
    try {
      final listing = (await MarketService.myListing.get()).data();
      if (listing != null) {
        _listed = true;
        _name.text = txt(listing, 'name');
        _price.text = vendorFieldNumber(numv(listing, 'price'));
        _active = listing['active'] == true;
        _holiday = listing['holiday'] == true;
        _point ??= marketAreaCenter(listing);
        final morning = asMap(listing['morning']);
        final evening = asMap(listing['evening']);
        _morningOn = morning.isNotEmpty;
        _eveningOn = evening.isNotEmpty;
        _morningStart = marketMinutes(txt(morning, 'start')) ?? _morningStart;
        _morningEnd = marketMinutes(txt(morning, 'end')) ?? _morningEnd;
        _eveningStart = marketMinutes(txt(evening, 'start')) ?? _eveningStart;
        _eveningEnd = marketMinutes(txt(evening, 'end')) ?? _eveningEnd;
      } else {
        _name.text = marketListingKind() == 'ranch'
            ? farmName()
            : await MarketService.myName();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    // No place yet: take it from the phone's location (permission is asked
    // now, with the reason), instead of asking people to find it on a map.
    if (_point == null && mounted) {
      final here = await VendorLocation.current(context);
      if (here != null && mounted) setState(() => _point = here);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim());
    String? problem;
    if (name.isEmpty) {
      problem = bi('Enter a name', 'பெயரை உள்ளிடவும்');
    } else if (_point == null) {
      problem = bi(
        'Choose your place on the map',
        'வரைபடத்தில் உங்கள் இடத்தைத் தேர்ந்தெடுக்கவும்',
      );
    } else if (price == null || price < 0 || price > 1000) {
      problem = bi('Enter a valid price', 'சரியான விலையை உள்ளிடவும்');
    } else if (!_morningOn && !_eveningOn) {
      problem = bi(
        'Turn on morning or evening hours',
        'காலை அல்லது மாலை நேரத்தை இயக்கவும்',
      );
    } else if ((_morningOn && _morningEnd <= _morningStart) ||
        (_eveningOn && _eveningEnd <= _eveningStart)) {
      problem = bi(
        'End time must be after start time',
        'முடியும் நேரம் தொடங்கும் நேரத்திற்குப் பிறகு இருக்க வேண்டும்',
      );
    }
    if (problem != null) {
      snack(context, problem);
      return;
    }
    setState(() => _saving = true);
    try {
      await MarketService.saveListing(
        name: name,
        point: _point!,
        price: price!,
        morning: _morningOn ? (_morningStart, _morningEnd) : (null, null),
        evening: _eveningOn ? (_eveningStart, _eveningEnd) : (null, null),
        active: _active,
        holiday: _holiday,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _listed = true;
      });
      snack(context, bi('Saved', 'சேமிக்கப்பட்டது'));
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _marketProblem(context, error);
      }
    }
  }

  Future<void> _remove() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AppleAlert(
        title: AppText(bi('Remove from Market?', 'சந்தையிலிருந்து நீக்கவா?')),
        content: AppText(
          bi(
            'Buyers will no longer find you. Your reviews stay.',
            'வாங்குபவர்கள் இனி உங்களைக் கண்டறிய முடியாது. மதிப்பீடுகள் அப்படியே இருக்கும்.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: AppText(bi('Remove', 'நீக்கு')),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await MarketService.removeListing();
      if (mounted) setState(() => _listed = false);
    } catch (error) {
      if (mounted) _marketProblem(context, error);
    }
  }

  Widget _hoursRow({
    required String title,
    required IconData icon,
    required bool on,
    required ValueChanged<bool> onChanged,
    required int start,
    required int end,
    required ValueChanged<int> onStart,
    required ValueChanged<int> onEnd,
  }) => Column(
    children: [
      SoundSwitchListTile(
        secondary: Icon(icon, color: Ink.amber),
        value: on,
        onChanged: onChanged,
        title: AppText(title),
      ),
      if (on)
        Padding(
          padding: const EdgeInsets.fromLTRB(54, 0, Space.s16, Space.s12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await _pickMarketTime(context, start);
                    if (t != null) onStart(t);
                  },
                  child: Text(marketTimeLabel(start)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s8),
                child: Text('–', style: TextStyle(color: Ink.muted)),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await _pickMarketTime(context, end);
                    if (t != null) onEnd(t);
                  },
                  child: Text(marketTimeLabel(end)),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final shop = milkShopMode;
    final ranchListing = marketListingKind() == 'ranch';
    return Scaffold(
      appBar: AppBar(title: AppText(bi('Market listing', 'சந்தைப் பட்டியல்'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Shell(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(21, 8, 21, 40),
                children: [
                  Text(
                    bi(
                      'Let milk buyers near you find you, send requests and leave reviews. They see only an area of about 200 m, never your exact place, until you accept their request.',
                      'அருகிலுள்ள பால் வாங்குபவர்கள் உங்களைக் கண்டறிந்து, கோரிக்கை அனுப்பி, மதிப்பிடலாம். நீங்கள் கோரிக்கையை ஏற்கும் வரை சுமார் 200 மீ பகுதி மட்டுமே தெரியும், சரியான இடம் தெரியாது.',
                    ),
                    style: TextStyle(color: Ink.muted, fontSize: 14),
                  ),
                  const SizedBox(height: Space.s16),
                  _InsetGroup(
                    children: [
                      SoundSwitchListTile(
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                        title: AppText(
                          bi('Show me in Market', 'சந்தையில் என்னைக் காட்டு'),
                        ),
                      ),
                      SoundSwitchListTile(
                        value: _holiday,
                        onChanged: (v) => setState(() => _holiday = v),
                        title: AppText(bi('Holiday', 'விடுமுறை')),
                        subtitle: AppText(
                          bi(
                            'Buyers see you as closed until you turn this off.',
                            'இதை அணைக்கும் வரை மூடப்பட்டதாகக் காட்டும்.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s20),
                  TextField(
                    controller: _name,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: fieldStyle(
                      shop
                          ? bi('Shop name', 'கடையின் பெயர்')
                          : ranchListing
                          ? bi('Ranch name', 'பண்ணையின் பெயர்')
                          : bi('Name', 'பெயர்'),
                    ),
                  ),
                  const SizedBox(height: Space.s8),
                  TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: fieldStyle(
                      bi('Price per litre', 'லிட்டர் விலை'),
                      prefix: Text('${currencySymbol()} '),
                    ),
                  ),
                  const SizedBox(height: Space.s16),
                  VendorLocationField(
                    value: _point,
                    name: shop
                        ? bi('Shop place', 'கடை இருக்கும் இடம்')
                        : ranchListing
                        ? bi('Ranch place', 'பண்ணை இருக்கும் இடம்')
                        : bi('Where you start from', 'நீங்கள் புறப்படும் இடம்'),
                    title: shop
                        ? bi('Shop place', 'கடை இருக்கும் இடம்')
                        : ranchListing
                        ? bi('Ranch place', 'பண்ணை இருக்கும் இடம்')
                        : bi('Where you start from', 'நீங்கள் புறப்படும் இடம்'),
                    marker: shop
                        ? Icons.storefront_rounded
                        : CupertinoIcons.location_solid,
                    onChanged: (p) => setState(() => _point = p),
                  ),
                  const SizedBox(height: Space.s20),
                  _InsetGroup(
                    children: [
                      _hoursRow(
                        title: shop
                            ? bi('Morning hours', 'காலை நேரம்')
                            : bi('Morning delivery', 'காலை விநியோகம்'),
                        icon: CupertinoIcons.sunrise_fill,
                        on: _morningOn,
                        onChanged: (v) => setState(() => _morningOn = v),
                        start: _morningStart,
                        end: _morningEnd,
                        onStart: (t) => setState(() => _morningStart = t),
                        onEnd: (t) => setState(() => _morningEnd = t),
                      ),
                      _hoursRow(
                        title: shop
                            ? bi('Evening hours', 'மாலை நேரம்')
                            : bi('Evening delivery', 'மாலை விநியோகம்'),
                        icon: CupertinoIcons.sunset_fill,
                        on: _eveningOn,
                        onChanged: (v) => setState(() => _eveningOn = v),
                        start: _eveningStart,
                        end: _eveningEnd,
                        onStart: (t) => setState(() => _eveningStart = t),
                        onEnd: (t) => setState(() => _eveningEnd = t),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s20),
                  LiquidButton(
                    label: bi('Save', 'சேமி'),
                    busy: _saving,
                    onPressed: _save,
                  ),
                  if (_listed) ...[
                    const SizedBox(height: Space.s8),
                    GhostButton(
                      label: bi('Remove from Market', 'சந்தையிலிருந்து நீக்கு'),
                      color: Ink.redText,
                      onPressed: _remove,
                    ),
                    const SizedBox(height: Space.s32),
                    const _RequestsToMe(),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Every request this vendor received, newest first.
class _RequestsToMe extends StatelessWidget {
  const _RequestsToMe();
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: MarketService.toMe(),
    builder: (context, snap) {
      final docs = [...?snap.data?.docs]
        ..sort(
          (a, b) => (_marketTime(b.data()['createdAt']) ?? DateTime.now())
              .compareTo(_marketTime(a.data()['createdAt']) ?? DateTime.now()),
        );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            bi('Milk requests', 'பால் கோரிக்கைகள்'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: Space.s12),
          if (docs.isEmpty)
            _MarketNote(bi('No requests yet', 'இன்னும் கோரிக்கைகள் இல்லை'))
          else
            _InsetGroup(
              children: [
                for (final doc in docs.take(30))
                  _MarketRequestRow(id: doc.id, data: doc.data(), buyer: false),
              ],
            ),
        ],
      );
    },
  );
}

// -----------------------------------------------------------------------------
//  In-app popups: a vendor answers new requests; a buyer answers offers and
//  hears once when a request is accepted or declined.
// -----------------------------------------------------------------------------

class MarketRequestBanner extends StatefulWidget {
  const MarketRequestBanner({super.key});
  @override
  State<MarketRequestBanner> createState() => _MarketRequestBannerState();
}

class _MarketRequestBannerState extends State<MarketRequestBanner> {
  String _uid = '';
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _toMe, _mine;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _incoming = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _offers = const [];
  final Set<String> _answering = {};
  final Set<String> _sharing = {};

  /// The middle of this vendor's listed area, for distances when the exact
  /// place was saved on another phone.
  Map<String, dynamic>? _area;

  @override
  void dispose() {
    _toMe?.cancel();
    _mine?.cancel();
    super.dispose();
  }

  void _listen() {
    final uid = MarketService.available ? signedInUid : '';
    if (uid == _uid) return;
    _uid = uid;
    _toMe?.cancel();
    _mine?.cancel();
    _incoming = const [];
    _offers = const [];
    if (uid.isEmpty) return;
    MarketService.myListing.get().then((snap) {
      final data = snap.data();
      if (data == null || !mounted) return;
      final center = marketAreaCenter(data);
      setState(() => _area = {'lat': center.latitude, 'lng': center.longitude});
    }, onError: (Object _) {});
    _toMe = MarketService.toMe().listen((snap) {
      if (!mounted) return;
      for (final doc in snap.docs) {
        final data = doc.data();
        // A buyer agreed to this vendor's offer: share the exact place now.
        if (txt(data, 'status') == 'accepted' &&
            data['vendorPoint'] == null &&
            _sharing.add(doc.id)) {
          unawaited(MarketService.sharePoint(doc.id).catchError((Object _) {}));
          if (data['kind'] == 'regular' && canRecordEntries) {
            unawaited(
              MarketService.addCustomer(data).catchError((Object _) {}),
            );
          }
        }
      }
      setState(
        () => _incoming = [
          for (final d in snap.docs)
            if (txt(d.data(), 'status') == 'pending') d,
        ],
      );
    }, onError: (Object _) {});
    _mine = MarketService.mine().listen((snap) {
      if (!mounted) return;
      _tellChanges(snap);
      setState(
        () => _offers = [
          for (final d in snap.docs)
            if (txt(d.data(), 'status') == 'offered') d,
        ],
      );
    }, onError: (Object _) {});
  }

  /// Once per request and answer, so reopening the app does not repeat it.
  void _tellChanges(QuerySnapshot<Map<String, dynamic>> snap) {
    final seen = asMap(settingValue('marketSeen', {}));
    final next = <String, dynamic>{};
    String? message;
    for (final doc in snap.docs) {
      final status = txt(doc.data(), 'status');
      next[doc.id] = status;
      if (seen.containsKey(doc.id) && seen[doc.id] == status) continue;
      final vendor = txt(doc.data(), 'vendorName', 'VIMO');
      if (status == 'accepted') {
        message = bi(
          '$vendor accepted your milk request',
          '$vendor உங்கள் பால் கோரிக்கையை ஏற்றார்',
        );
      } else if (status == 'declined') {
        message = bi(
          '$vendor cannot take your request now',
          '$vendor இப்போது உங்கள் கோரிக்கையை ஏற்க முடியவில்லை',
        );
      }
    }
    if (snap.metadata.isFromCache && seen.isNotEmpty) return;
    unawaited(setSetting('marketSeen', next));
    if (message != null && seen.isNotEmpty && mounted) snack(context, message);
  }

  Future<void> _vendorAnswer(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String answer,
  ) async {
    final id = doc.id;
    if (answer == 'offer') {
      final offer = await _askOffer(doc.data());
      if (offer == null) return;
      setState(() => _answering.add(id));
      try {
        await MarketService.offer(id, time: offer.$1, price: offer.$2);
        if (mounted) {
          snack(context, bi('Offer sent', 'புதிய நேரம்/விலை அனுப்பப்பட்டது'));
        }
      } catch (error) {
        if (mounted) _marketProblem(context, error);
      }
    } else {
      setState(() => _answering.add(id));
      selectionFeedback();
      try {
        if (answer == 'accept') {
          await MarketService.accept(id);
          if (doc.data()['kind'] == 'regular' && canRecordEntries) {
            await MarketService.addCustomer(doc.data());
          }
          if (mounted) {
            snack(
              context,
              doc.data()['kind'] == 'regular'
                  ? bi(
                      'Accepted. ${txt(doc.data(), 'buyerName')} is added to your customers.',
                      'ஏற்கப்பட்டது. ${txt(doc.data(), 'buyerName')} உங்கள் வாடிக்கையாளர்களில் சேர்க்கப்பட்டார்.',
                    )
                  : bi('Accepted', 'ஏற்கப்பட்டது'),
            );
          }
        } else {
          await MarketService.decline(id);
        }
      } catch (error) {
        if (mounted) _marketProblem(context, error);
      }
    }
    if (mounted) setState(() => _answering.remove(id));
  }

  Future<(int?, double?)?> _askOffer(Map<String, dynamic> request) =>
      showAppleSheet<(int?, double?)>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _MarketOfferSheet(request: request),
      );

  Future<void> _buyerAnswer(String id, bool agree) async {
    setState(() => _answering.add(id));
    selectionFeedback();
    try {
      agree ? await MarketService.agree(id) : await MarketService.cancel(id);
    } catch (error) {
      if (mounted) _marketProblem(context, error);
    }
    if (mounted) setState(() => _answering.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final uid = MarketService.available ? signedInUid : '';
    if (uid != _uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_listen);
      });
    }
    final reduce = MediaQuery.disableAnimationsOf(context);
    final incoming = _incoming
        .where((d) => !_answering.contains(d.id))
        .toList();
    final offers = _offers.where((d) => !_answering.contains(d.id)).toList();
    Widget child = const SizedBox.shrink(key: ValueKey('none'));
    if (incoming.isNotEmpty) {
      child = _card(
        key: ValueKey(incoming.first.id),
        count: incoming.length,
        title: bi(
          '${txt(incoming.first.data(), 'buyerName', 'VIMO')} asks for milk',
          '${txt(incoming.first.data(), 'buyerName', 'VIMO')} பால் கேட்கிறார்',
        ),
        detail: _incomingDetail(incoming.first.data()),
        actions: [
          Expanded(
            child: GhostButton(
              label: bi('Decline', 'மறு'),
              color: Ink.redText,
              onPressed: () => _vendorAnswer(incoming.first, 'decline'),
            ),
          ),
          const SizedBox(width: Space.s8),
          Expanded(
            child: GhostButton(
              label: bi('Change', 'மாற்று'),
              onPressed: () => _vendorAnswer(incoming.first, 'offer'),
            ),
          ),
          const SizedBox(width: Space.s8),
          Expanded(
            child: LiquidButton(
              label: bi('Accept', 'ஏற்கவும்'),
              height: 50,
              onPressed: () => _vendorAnswer(incoming.first, 'accept'),
            ),
          ),
        ],
      );
    } else if (offers.isNotEmpty) {
      final data = offers.first.data();
      final time = marketMinutes(txt(data, 'offerTime'));
      final price = numv(data, 'offerPrice');
      child = _card(
        key: ValueKey(offers.first.id),
        count: offers.length,
        title: bi(
          '${txt(data, 'vendorName', 'VIMO')} suggests a change',
          '${txt(data, 'vendorName', 'VIMO')} ஒரு மாற்றத்தைப் பரிந்துரைக்கிறார்',
        ),
        detail: [
          marketRequestSummary(data),
          [
            if (time != null) marketTimeLabel(time),
            if (price > 0) '${money(price)}/${bi('L', 'லி')}',
          ].join(' · '),
        ].where((s) => s.isNotEmpty).join('\n'),
        actions: [
          Expanded(
            child: GhostButton(
              label: bi('Cancel request', 'ரத்து செய்'),
              color: Ink.redText,
              onPressed: () => _buyerAnswer(offers.first.id, false),
            ),
          ),
          const SizedBox(width: Space.s8),
          Expanded(
            child: LiquidButton(
              label: bi('Agree', 'சம்மதம்'),
              height: 50,
              onPressed: () => _buyerAnswer(offers.first.id, true),
            ),
          ),
        ],
      );
    }
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -.3),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }

  String _incomingDetail(Map<String, dynamic> request) {
    final home = asMap(request['home']);
    final saved = asMap(settingValue('marketPoint', {}));
    final mine = saved['lat'] is num ? saved : (_area ?? const {});
    final far = home['lat'] is num && mine['lat'] is num
        ? marketDistanceLabel(
            marketDistance(
              ll.LatLng(numv(mine, 'lat'), numv(mine, 'lng')),
              ll.LatLng(numv(home, 'lat'), numv(home, 'lng')),
            ),
          )
        : '';
    return [
      marketRequestSummary(request),
      if (far.isNotEmpty) bi('$far away', '$far தொலைவில்'),
      if (txt(request, 'note').isNotEmpty) '“${txt(request, 'note')}”',
    ].join('\n');
  }

  Widget _card({
    required Key key,
    required int count,
    required String title,
    required String detail,
    required List<Widget> actions,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: LiquidGlass(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.drop_fill,
                    color: Ink.violetDeep,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Ink.navy,
                      ),
                    ),
                  ),
                  if (count > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '1/$count',
                        style: TextStyle(color: Ink.muted, fontSize: 13),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Text(
                  detail,
                  style: TextStyle(fontSize: 13, color: Ink.muted),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: actions),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The vendor offers another time or price instead of accepting as asked.
class _MarketOfferSheet extends StatefulWidget {
  final Map<String, dynamic> request;
  const _MarketOfferSheet({required this.request});
  @override
  State<_MarketOfferSheet> createState() => _MarketOfferSheetState();
}

class _MarketOfferSheetState extends State<_MarketOfferSheet> {
  late int? _time = marketMinutes(txt(widget.request, 'time'));
  late final _price = TextEditingController(
    text: vendorFieldNumber(defaultMilkPrice()),
  );

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              bi('Suggest a change', 'மாற்றத்தைப் பரிந்துரை'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text(
              marketRequestSummary(widget.request),
              style: TextStyle(color: Ink.muted),
            ),
            const SizedBox(height: Space.s16),
            _InsetGroup(
              children: [
                ListTile(
                  leading: Icon(
                    CupertinoIcons.clock_fill,
                    color: Ink.violetDeep,
                  ),
                  title: AppText(bi('Time', 'நேரம்')),
                  trailing: Text(
                    _time == null
                        ? bi('Any time', 'எந்த நேரமும்')
                        : marketTimeLabel(_time!),
                    style: TextStyle(color: Ink.body),
                  ),
                  onTap: () async {
                    final picked = await _pickMarketTime(context, _time);
                    if (picked != null && mounted) {
                      setState(() => _time = picked);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: Space.s16),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: fieldStyle(
                bi('Price per litre', 'லிட்டர் விலை'),
                prefix: Text('${currencySymbol()} '),
              ),
            ),
            const SizedBox(height: Space.s16),
            LiquidButton(
              label: bi('Send to buyer', 'வாங்குபவருக்கு அனுப்பு'),
              icon: CupertinoIcons.paperplane_fill,
              onPressed: () {
                final price = double.tryParse(_price.text.trim());
                if (price == null || price < 0 || price > 1000) {
                  snack(
                    context,
                    bi('Enter a valid price', 'சரியான விலையை உள்ளிடவும்'),
                  );
                  return;
                }
                Navigator.pop(context, (_time, price));
              },
            ),
          ],
        ),
      ),
    ),
  );
}
