import 'dart:math';

/// A point on Earth, in degrees.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;
}

/// Straight-line ("as the crow flies") distance in kilometres, by the
/// haversine formula. Good to a fraction of a percent at city scale.
double distanceKm(GeoPoint a, GeoPoint b) {
  const earthRadiusKm = 6371.0088;
  double rad(double d) => d * pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h = pow(sin(dLat / 2), 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * pow(sin(dLng / 2), 2);
  return 2 * earthRadiusKm * asin(min(1.0, sqrt(h)));
}

/// "350 m", "2.3 km", "5 km", "12 km".
String formatDistance(double km) {
  if (km < 1) return '${max(10, (km * 1000 / 10).round() * 10)} m';
  if (km == km.roundToDouble()) return '${km.round()} km';
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}

/// The "Near…" filter (#94): activities within [km] of [point]. [label] says
/// where that is ("your location", "Orchard MRT").
class NearFilter {
  const NearFilter({required this.point, required this.label, required this.km});

  final GeoPoint point;
  final String label;
  final double km;

  static const distances = [1.0, 2.0, 5.0, 10.0, 20.0];

  NearFilter withKm(double value) => NearFilter(point: point, label: label, km: value);
}

/// Items split by the "Near…" filter: those within reach, nearest first with
/// their distance, and those that can't be measured (no Google place picked,
/// or Google couldn't place it).
class NearResult<T> {
  NearResult(this.within, this.unmeasured);

  final List<(T, double)> within;
  final List<T> unmeasured;
}

/// Applies [filter] to [items]. [placeOf] gives an item's Google place ID;
/// [coordinates] are the known places. Items farther than the filter's
/// distance are dropped.
NearResult<T> applyNear<T>(
  List<T> items,
  NearFilter filter,
  Map<String, GeoPoint> coordinates,
  String? Function(T) placeOf,
) {
  final within = <(T, double)>[];
  final unmeasured = <T>[];
  for (final item in items) {
    final place = placeOf(item);
    final at = place == null ? null : coordinates[place];
    if (at == null) {
      unmeasured.add(item);
      continue;
    }
    final d = distanceKm(filter.point, at);
    if (d <= filter.km) within.add((item, d));
  }
  within.sort((a, b) => a.$2.compareTo(b.$2));
  return NearResult(within, unmeasured);
}
