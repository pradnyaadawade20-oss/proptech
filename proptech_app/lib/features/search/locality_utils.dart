import 'package:flutter/material.dart';
import '../properties/property.dart';

/// Option lists used by the search screen's filter chips.
const List<String> searchBhkOptions = ['1 RK', '1 BHK', '2 BHK', '3 BHK', '4 BHK', '5 BHK'];

/// Same labels the Add Property form saves in `Property.furnishing`.
const List<String> searchFurnishingOptions = ['Unfurnished', 'Semi Furnished', 'Fully Furnished'];

/// key -> label. Keys are what SearchCriteria stores.
const Map<String, String> searchPostedByOptions = {
  'owner': 'Owner',
  'dealer': 'Dealer',
  'builder': 'Builder',
};

class SearchAmenity {
  final String key;
  final String label;
  final IconData icon;
  const SearchAmenity(this.key, this.label, this.icon);
}

/// Keys match the amenity keys saved by the Add Property form.
const List<SearchAmenity> searchAmenityOptions = [
  SearchAmenity('parking', 'Parking', Icons.local_parking_outlined),
  SearchAmenity('lift', 'Lift', Icons.elevator_outlined),
  SearchAmenity('power_backup', 'Power Backup', Icons.power_outlined),
  SearchAmenity('security', 'Security', Icons.security_outlined),
  SearchAmenity('gym', 'Gym', Icons.fitness_center_outlined),
  SearchAmenity('pool', 'Pool', Icons.pool_outlined),
  SearchAmenity('water_supply', '24x7 Water', Icons.water_drop_outlined),
  SearchAmenity('wifi', 'Wifi', Icons.wifi),
  SearchAmenity('gas_pipeline', 'Gas Pipeline', Icons.local_fire_department_outlined),
  SearchAmenity('cctv', 'CCTV', Icons.videocam_outlined),
  SearchAmenity('clubhouse', 'Clubhouse', Icons.deck_outlined),
  SearchAmenity('garden', 'Garden', Icons.park_outlined),
  SearchAmenity('play_area', 'Play Area', Icons.child_care_outlined),
];

String _cityOf(Property p) {
  final c = p.city.trim();
  if (c.isNotEmpty) return c;
  final parts = p.location.split(',');
  return parts.length > 1 ? parts.last.trim() : '';
}

String _localityOf(Property p) {
  final l = p.locality.trim();
  if (l.isNotEmpty) return l;
  final parts = p.location.split(',');
  return parts.length > 1 ? parts.first.trim() : '';
}

List<String> _rankByCount(Iterable<String> values) {
  final counts = <String, int>{};
  final display = <String, String>{};
  for (final v in values) {
    final t = v.trim();
    if (t.isEmpty) continue;
    final k = t.toLowerCase();
    counts[k] = (counts[k] ?? 0) + 1;
    display.putIfAbsent(k, () => t);
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : display[a]!.compareTo(display[b]!);
    });
  return [for (final k in keys) display[k]!];
}

/// Cities that have listings, most listings first.
List<String> citiesByListings(List<Property> input) => _rankByCount(input.map(_cityOf));

/// Localities with the most listings, optionally limited to [city].
List<String> popularLocalities(List<Property> input, {String? city, int limit = 10}) {
  final c = city?.trim().toLowerCase();
  final scoped = (c == null || c.isEmpty) ? input : input.where((p) => _cityOf(p).toLowerCase() == c);
  return _rankByCount(scoped.map(_localityOf)).take(limit).toList();
}