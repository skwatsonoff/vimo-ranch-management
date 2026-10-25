import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:ranch_management/main.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_market_');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('A place is shared only as a ~220 m square', () {
    // Chennai Central
    final gridLat = marketGrid(13.0827), gridLng = marketGrid(80.2707);
    expect((gridLat, gridLng), (6541, 40135));
    expect(marketCell(gridLat, gridLng), '261:1605');
    final center = marketAreaCenter({'gridLat': gridLat, 'gridLng': gridLng});
    // The shown point is never more than half a square from the real one.
    expect(
      marketDistance(center, const ll.LatLng(13.0827, 80.2707)),
      lessThan(160),
    );
    // South and west of zero round down too, matching the security rules.
    expect(marketCell(-6541, -40135), '-262:-1606');
  });

  test('A search covers 10 km: the buyer cell and two rings around it', () {
    final cells = marketNearbyCells(const ll.LatLng(13.0827, 80.2707));
    expect(cells.length, 25);
    expect(cells.toSet().length, 25);
    expect(
      cells,
      containsAll(['261:1605', '260:1604', '262:1606', '259:1603', '263:1607']),
    );
    // One ring is the old 3 x 3 search.
    expect(
      marketNearbyCells(const ll.LatLng(13.0827, 80.2707), ring: 1).length,
      9,
    );
  });

  test('Search widens 2 km, then 5 km, then 10 km at most', () {
    expect(marketSearchStep([1500, 7000]), 0);
    expect(marketSearchStep([2600, 9000]), 1);
    expect(marketSearchStep([8000]), 2);
    expect(marketSearchStep([]), 2);
    expect(marketSearchSteps.last, 10000);
  });

  test('Distances are rounded because places are approximate', () async {
    await Hive.box('settings').put('languageMode', 'English');
    expect(marketDistanceLabel(40), '~100 m');
    expect(marketDistanceLabel(460), '~500 m');
    expect(marketDistanceLabel(1240), '~1.2 km');
    expect(marketDistanceLabel(12600), '~13 km');
  });

  group('Open status like a map', () {
    final listing = {
      'active': true,
      'holiday': false,
      'onRide': false,
      'morning': {'start': '05:30', 'end': '08:00'},
      'evening': {'start': '17:00', 'end': '19:30'},
    };
    DateTime at(int h, int m) => DateTime(2026, 10, 17, h, m);

    test('opens soon, open, ends soon, closed', () {
      expect(marketStatus(listing, at(4, 40)), MarketOpen.opensSoon);
      expect(marketStatus(listing, at(4, 20)), MarketOpen.closed);
      expect(marketStatus(listing, at(6, 0)), MarketOpen.open);
      expect(marketStatus(listing, at(7, 40)), MarketOpen.endsSoon);
      expect(marketStatus(listing, at(8, 0)), MarketOpen.closed);
      expect(marketStatus(listing, at(16, 30)), MarketOpen.opensSoon);
      expect(marketStatus(listing, at(21, 0)), MarketOpen.closed);
    });

    test('a running ride shows; an old one does not', () {
      final ride = {
        ...listing,
        'onRide': true,
        'rideAt': Timestamp.fromDate(at(5, 0)),
      };
      expect(marketStatus(ride, at(6, 0)), MarketOpen.onRide);
      expect(marketStatus(ride, at(10, 0)), MarketOpen.closed);
    });

    test('holiday or hidden is closed', () {
      expect(
        marketStatus({...listing, 'holiday': true}, at(6, 0)),
        MarketOpen.closed,
      );
      expect(
        marketStatus({...listing, 'active': false}, at(6, 0)),
        MarketOpen.closed,
      );
    });

    test('the next change is named', () async {
      await Hive.box('settings').put('languageMode', 'English');
      expect(marketStatusDetail(listing, at(6, 0)), 'Ends 8:00 AM');
      expect(marketStatusDetail(listing, at(12, 0)), 'Opens 5:00 PM');
      expect(marketStatusDetail(listing, at(21, 0)), 'Opens tomorrow 5:30 AM');
      await Hive.box('settings').put('languageMode', 'Tamil');
      expect(marketStatusDetail(listing, at(6, 0)), 'காலை 8:00-க்கு முடியும்');
      await Hive.box('settings').put('languageMode', 'English');
    });

    test('hours that end before they start are ignored', () {
      expect(
        marketWindows({
          'morning': {'start': '08:00', 'end': '05:00'},
          'evening': <String, dynamic>{},
        }),
        isEmpty,
      );
    });
  });

  test('Nearest first, or rated first with distance breaking ties', () {
    MarketVendor v(String id, double km, double stars, int reviews) =>
        MarketVendor(
          uid: id,
          data: const {},
          distance: km * 1000,
          rating: stars,
          reviews: reviews,
        );
    final list = [
      v('far-best', 4, 4.9, 12),
      v('near-new', .5, 0, 0),
      v('mid-good', 2, 4.2, 5),
      v('near-good', 1, 4.2, 3),
    ];
    expect(sortMarketVendors(list, byRating: false).map((e) => e.uid), [
      'near-new',
      'near-good',
      'mid-good',
      'far-best',
    ]);
    expect(sortMarketVendors(list, byRating: true).map((e) => e.uid), [
      'far-best',
      'near-good',
      'mid-good',
      'near-new',
    ]);
  });

  test('A request reads as one clear line', () async {
    await Hive.box('settings').put('languageMode', 'English');
    expect(
      marketRequestSummary({
        'kind': 'today',
        'litres': 1.5,
        'session': 'Morning',
        'time': '06:30',
      }),
      'Today only · 1.5 L · Morning · 6:30 AM',
    );
    expect(
      marketRequestSummary({
        'kind': 'regular',
        'litres': 1,
        'session': 'Evening',
        'time': '',
        'days': ['Mon', 'Wed', 'Fri'],
        'payment': 'monthly',
      }),
      'Regular · 1 L · Evening · Mon Wed Fri · Pay monthly',
    );
  });

  test('The exact place and seen answers stay on this phone', () {
    expect(CloudSyncService.isLocalSetting('marketPoint'), isTrue);
    expect(CloudSyncService.isLocalSetting('marketSeen'), isTrue);
  });
}
