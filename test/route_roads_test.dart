import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:ranch_management/main.dart';

Map<String, dynamic> _home(String id, double lat, double lng) => {
  'id': id,
  'name': id,
  'lat': lat,
  'lng': lng,
};

void main() {
  final a = _home('a', 10.790, 78.686);
  final b = _home('b', 10.795, 78.690);
  final c = _home('c', 10.800, 78.695);

  test('own route runs home 1 → 2 → 3, never back to a recorded point', () {
    final route = {
      'kind': 'own',
      // A stationary phone's GPS fix, recorded between marks.
      'path': [
        [10.700, 78.600],
        [10.795, 78.690],
        [10.700, 78.600],
        [10.800, 78.695],
      ],
      'stops': [a, b, c],
    };
    final segments = routeSegments(route);
    expect(segments, hasLength(2));
    expect(segments.every((s) => !s.road), isTrue);
    expect(segments[0].points, [
      const ll.LatLng(10.790, 78.686),
      const ll.LatLng(10.795, 78.690),
    ]);
    expect(segments[1].points.last, const ll.LatLng(10.800, 78.695));
    expect(
      routeLine(route).any((p) => p.latitude == 10.700),
      isFalse,
      reason: 'the raw GPS fix is no longer drawn',
    );
  });

  test('a saved road is used for its leg until a home moves', () {
    const road = RoadOption([
      ll.LatLng(10.790, 78.686),
      ll.LatLng(10.792, 78.689),
      ll.LatLng(10.795, 78.690),
    ], 640);
    final route = <String, dynamic>{
      'kind': 'own',
      'stops': [a, b, c],
      'legs': [roadLeg(a, b, road)],
    };
    final segments = routeSegments(route);
    expect(segments.first.road, isTrue);
    expect(segments.first.points, hasLength(3));
    expect(segments.last.road, isFalse);
    expect(routeLine(route), hasLength(4));

    final moved = {
      ...route,
      'stops': [_home('a', 10.7905, 78.686), b, c],
    };
    expect(routeSegments(moved).first.road, isFalse);
  });

  test('a lent route draws the road line it carries', () {
    final route = {
      'kind': 'received',
      'path': [
        {'lat': 10.790, 'lng': 78.686},
        {'lat': 10.792, 'lng': 78.689},
      ],
      'stops': [a, b],
    };
    final segments = routeSegments(route);
    expect(segments, hasLength(1));
    expect(segments.single.road, isTrue);
    expect(segments.single.points, hasLength(2));
  });
}
