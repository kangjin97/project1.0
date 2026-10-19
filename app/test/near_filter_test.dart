import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/geo.dart';

const marinaBaySands = GeoPoint(1.2837575, 103.8591065);
const orchardMrt = GeoPoint(1.3043, 103.8320);
const changiAirport = GeoPoint(1.3644, 103.9915);

void main() {
  test('straight-line distance', () {
    expect(distanceKm(marinaBaySands, marinaBaySands), 0);
    // Marina Bay Sands → Orchard MRT is about 3.8 km; → Changi Airport about 17 km.
    expect(distanceKm(marinaBaySands, orchardMrt), closeTo(3.79, 0.05));
    expect(distanceKm(marinaBaySands, changiAirport), closeTo(17.2, 0.2));
    expect(distanceKm(orchardMrt, marinaBaySands), distanceKm(marinaBaySands, orchardMrt));
  });

  test('distances read naturally', () {
    expect(formatDistance(0.004), '10 m');
    expect(formatDistance(0.347), '350 m');
    expect(formatDistance(2.345), '2.3 km');
    expect(formatDistance(12.6), '13 km');
    expect(formatDistance(5), '5 km');
    expect(formatDistance(1), '1 km');
  });

  test('near: within reach nearest first, too far dropped, unmeasured kept apart', () {
    final places = {'mbs': marinaBaySands, 'changi': changiAirport, 'orchard': orchardMrt};
    final items = ['changi', 'no-place', 'mbs', 'orchard', 'unknown-place'];
    final result = applyNear(
      items,
      const NearFilter(point: orchardMrt, label: 'Orchard MRT', km: 5),
      places,
      (i) => i == 'no-place' ? null : i,
    );
    expect([for (final (i, _) in result.within) i], ['orchard', 'mbs']);
    expect(result.within.first.$2, closeTo(0, 0.001));
    expect(result.unmeasured, ['no-place', 'unknown-place']);
  });
}
