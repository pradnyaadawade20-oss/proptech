import 'dart:math';
import '../properties/property.dart';

/// Great-circle distance between two lat/lng points, in km.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = pow(sin(dLat / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLon / 2), 2);
  return 2 * earthRadiusKm * asin(sqrt(a));
}

/// Distance from the user to [p] in km, or null if [p] has no coordinates.
double? distanceKmTo(Property p, double lat, double lng) {
  if (!p.hasMapPosition) return null;
  return haversineKm(lat, lng, p.latitude, p.longitude);
}

/// Properties around the user, nearest first.
///
///  1. Properties WITH coordinates inside [radiusKm], sorted by distance.
///  2. Properties WITHOUT coordinates (older listings) whose locality / city
///     matches where the user is — appended after, so nothing nearby is lost.
List<Property> nearbyProperties(
  List<Property> input, {
  required double lat,
  required double lng,
  double radiusKm = 10,
  String city = '',
  String locality = '',
}) {
  final located = <(Property, double)>[];
  final byAddress = <Property>[];

  final c = city.trim().toLowerCase();
  final l = locality.trim().toLowerCase();

  bool sameArea(Property p) {
    final loc = '${p.location} ${p.city} ${p.locality}'.toLowerCase();
    if (l.isNotEmpty && loc.contains(l)) return true;
    return c.isNotEmpty && loc.contains(c);
  }

  for (final p in input) {
    final d = distanceKmTo(p, lat, lng);
    if (d != null) {
      if (d <= radiusKm) located.add((p, d));
    } else if (sameArea(p)) {
      byAddress.add(p);
    }
  }

  located.sort((a, b) => a.$2.compareTo(b.$2));
  return [...located.map((e) => e.$1), ...byAddress];
}

String formatDistance(double km) =>
    km < 1 ? '${(km * 1000).round()} m away' : '${km.toStringAsFixed(1)} km away';