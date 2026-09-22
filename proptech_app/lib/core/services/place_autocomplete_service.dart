import 'package:dio/dio.dart';

/// A single place/location suggestion returned by search.
class PlaceSuggestion {
  final String displayName;
  final double lat;
  final double lng;

  const PlaceSuggestion({required this.displayName, required this.lat, required this.lng});
}

/// Location search backed by OpenStreetMap's free Nominatim geocoding API
/// — no API key required. Same service already used by the map search
/// screen, exposed here as a shared singleton so any screen can look up
/// place suggestions as the user types.
class PlaceAutocompleteService {
  PlaceAutocompleteService._();
  static final PlaceAutocompleteService instance = PlaceAutocompleteService._();

  final Dio _dio = Dio();

  Future<List<PlaceSuggestion>> search(String query) async {
    if (query.trim().length < 3) return [];

    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'countrycodes': 'in',
          'limit': 5,
        },
        options: Options(headers: {'User-Agent': 'proptech_app'}),
      );

      return (response.data as List)
          .map((e) => PlaceSuggestion(
                displayName: e['display_name'] as String,
                lat: double.parse(e['lat'] as String),
                lng: double.parse(e['lon'] as String),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }
}