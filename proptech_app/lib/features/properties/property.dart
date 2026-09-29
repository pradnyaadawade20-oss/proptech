/// Basic Property model. Fields mirror the future backend API response
/// so switching from dummy data to real API later is just a data-source swap.
library;
import 'package:flutter/foundation.dart';
import 'property_extras.dart';
class Property {
  final String id;
  final String title;
  final String imageUrl;
  final double price;
  final String priceUnit; // "/month" or "" for sale
  final String bhk;
  final String furnishing;
  final String location;
  final bool isVerified;
  final bool isFavorite;
  final double rating;
  final int reviewCount;
  final List<String> amenities;
  final String category; // 'Residential' or 'Commercial'

  // --- Advanced filter fields ---
  final double area; // in sqft
  final String possessionStatus; // 'Ready to Move' | 'Under Construction'
  final int ageOfPropertyYears; // 0 = new construction
  final int floorNumber;
  final int totalFloors;
  final String facing; // 'North' | 'South' | 'East' | 'West' | 'North-East' etc.

  // --- Map search fields ---
  final double latitude;
  final double longitude;

  // --- Listing quality fields ---
  /// Extra gallery photos beyond the cover `imageUrl`. Use `galleryImages`
  /// to get the full ordered list (cover + additional).
  final List<String> additionalImageUrls;
  /// Network video URL for a video walkthrough of the property, if the
  /// owner/dealer has uploaded one.
  final String? videoTourUrl;
  /// Image URL of an uploaded floor plan, if available.
  final String? floorPlanUrl;
  /// RERA registration number — presence of this (plus non-empty
  /// `verificationDocuments`) is what backs the "Verified" badge with an
  /// actual paper trail instead of just a boolean flag.
  final String? reraNumber;
  /// Labels of documents checked as part of verification (e.g. "Sale Deed",
  /// "Property Tax Receipt", "RERA Certificate"). Empty = not yet verified.
  final List<String> verificationDocuments;
  /// Expected/actual possession date. Null when not applicable or unknown.
  final DateTime? possessionDate;
  /// Whether the listed price is open to negotiation.
  final bool isPriceNegotiable;
  /// Historical price points for this listing, oldest first, used to draw
  /// the price-trend chart on the detail screen.
  final List<PricePoint> priceHistory;
  /// Nearby points of interest (schools, hospitals, metro, etc.).
  final List<NearbyLandmark> nearbyLandmarks;
  /// Actual scanned ownership-proof documents (Sale Deed, Tax Receipt,
  /// RERA Certificate, etc.) a buyer can open and inspect — this is what
  /// backs `verificationDocuments` with real, viewable images.
  final List<OwnershipDocument> ownershipDocuments;

  // --- Owner info (placeholder until Properties are backend-connected;
  // ownerId defaults to a dummy id so the Agreement flow has something to
  // send — swap for the real owner_id once GET /api/properties returns it) ---
  final String ownerId;
  final String ownerName;

  const Property({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.price,
    required this.priceUnit,
    required this.bhk,
    required this.furnishing,
    required this.location,
    this.isVerified = false,
    this.isFavorite = false,
    this.rating = 4.5,
    this.reviewCount = 0,
    this.amenities = const ['wifi', 'parking', 'lift', 'power_backup'],
    this.category = 'Residential',
    this.area = 1000,
    this.possessionStatus = 'Ready to Move',
    this.ageOfPropertyYears = 0,
    this.floorNumber = 1,
    this.totalFloors = 1,
    this.facing = 'North',
    this.latitude = 19.0760,
    this.longitude = 72.8777,
    this.additionalImageUrls = const [],
    this.videoTourUrl,
    this.floorPlanUrl,
    this.reraNumber,
    this.verificationDocuments = const [],
    this.possessionDate,
    this.isPriceNegotiable = false,
    this.priceHistory = const [],
    this.nearbyLandmarks = const [],
    this.ownershipDocuments = const [],
    this.ownerId = '11111111-1111-1111-1111-111111111101', // dummy Owner seed id, replace once Properties are backend-connected
    this.ownerName = 'Property Owner',
  });

  /// Full ordered gallery: cover image first, then any additional photos.
  List<String> get galleryImages => [imageUrl, ...additionalImageUrls];

  /// True once there's an actual paper trail (RERA number + at least one
  /// checked document) behind the verified badge — not just a flag.
  bool get isDocumentVerified => reraNumber != null && reraNumber!.isNotEmpty && verificationDocuments.isNotEmpty;

  /// Maps GET/POST /api/properties response fields. Backend fields not
  /// present yet (area, facing, gallery, etc.) fall back to defaults so
  /// this Property still renders fine in every existing screen.
  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      imageUrl: (json['image_url'] as String?)?.isNotEmpty == true
          ? json['image_url'] as String
          : 'https://images.unsplash.com/photo-1568605114967-8130f3a36994',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      priceUnit: json['price_unit'] as String? ?? '',
      bhk: json['bhk'] as String? ?? '',
      furnishing: json['furnishing'] as String? ?? '',
      location: json['location'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toDouble() ?? 4.5,
      reviewCount: json['review_count'] as int? ?? 0,
      amenities: (json['amenities'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const ['wifi', 'parking', 'lift', 'power_backup'],
      category: json['category'] as String? ?? 'Residential',
      ownerId: json['owner_id'] as String? ?? '',
    );
  }

  Property copyWith({bool? isFavorite, String? imageUrl}) {
    return Property(
      id: id,
      title: title,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price,
      priceUnit: priceUnit,
      bhk: bhk,
      furnishing: furnishing,
      location: location,
      isVerified: isVerified,
      isFavorite: isFavorite ?? this.isFavorite,
      rating: rating,
      reviewCount: reviewCount,
      amenities: amenities,
      category: category,
      area: area,
      possessionStatus: possessionStatus,
      ageOfPropertyYears: ageOfPropertyYears,
      floorNumber: floorNumber,
      totalFloors: totalFloors,
      facing: facing,
      latitude: latitude,
      longitude: longitude,
      additionalImageUrls: additionalImageUrls,
      videoTourUrl: videoTourUrl,
      floorPlanUrl: floorPlanUrl,
      reraNumber: reraNumber,
      verificationDocuments: verificationDocuments,
      possessionDate: possessionDate,
      isPriceNegotiable: isPriceNegotiable,
      priceHistory: priceHistory,
      nearbyLandmarks: nearbyLandmarks,
      ownershipDocuments: ownershipDocuments,
    );
  }
}

/// Shared in-memory property list every screen (home, search, favorites,
/// categories, map...) reads from. It starts empty and gets filled by
/// PropertyService.loadReal() — nothing here is hardcoded/mock anymore.
List<Property> dummyProperties = [];

/// Matches a property against the same "property type" categories used in
/// the search screen's quick-filter chips (Apartment/Villa/PG/House/Office).
/// Shared so search screen and saved-search alert checks stay in sync.
bool propertyMatchesType(Property p, String? type) {
  if (type == null) return true;
  switch (type) {
    case 'Apartment':
      return p.category == 'Residential' &&
          p.bhk != 'PG' &&
          p.bhk != '4 BHK' &&
          p.bhk != '5 BHK' &&
          !p.title.toLowerCase().contains('bungalow') &&
          !p.title.toLowerCase().contains('villa') &&
          !p.title.toLowerCase().contains('house');
    case 'Villa':
      return p.bhk == '4 BHK' ||
          p.bhk == '5 BHK' ||
          p.title.toLowerCase().contains('bungalow') ||
          p.title.toLowerCase().contains('villa');
    case 'PG':
      return p.bhk == 'PG';
    case 'House':
      return p.category == 'Residential' &&
          (p.title.toLowerCase().contains('house') || p.title.toLowerCase().contains('bungalow'));
    case 'Office':
      return p.category == 'Commercial';
    default:
      return true;
  }
}

/// Filters [input] by free-text query, property type chip, and a price
/// range. Shared by the search screen and saved-search alert checks so a
/// saved search's results always match what the search screen itself shows.
List<Property> filterProperties(
  List<Property> input, {
  String query = '',
  String? type,
  double? budgetStart,
  double? budgetEnd,
}) {
  return input.where((p) {
    final matchesQuery = query.isEmpty ||
        p.title.toLowerCase().contains(query.toLowerCase()) ||
        p.location.toLowerCase().contains(query.toLowerCase());
    final matchesBudget = (budgetStart == null || p.price >= budgetStart) &&
        (budgetEnd == null || p.price <= budgetEnd);
    return matchesQuery && matchesBudget && propertyMatchesType(p, type);
  }).toList();
}

/// Finds properties similar to [target] — same category/bhk/city and a
/// close-enough price — ranked by a simple weighted score (highest first).
/// Used for the "Similar Properties" section on the property detail screen.
List<Property> similarProperties(Property target, {int limit = 8}) {
  final targetCity = target.location.split(',').last.trim().toLowerCase();
  final candidates = dummyProperties.where((p) => p.id != target.id).toList();

  int score(Property p) {
    int s = 0;
    if (p.category == target.category) s += 3;
    if (p.bhk == target.bhk) s += 3;
    final pCity = p.location.split(',').last.trim().toLowerCase();
    if (pCity == targetCity) s += 2;
    if (p.priceUnit == target.priceUnit) s += 1;
    if (target.price > 0) {
      final priceDiff = (p.price - target.price).abs() / target.price;
      if (priceDiff <= 0.3) {
        s += 2;
      } else if (priceDiff <= 0.6) {
        s += 1;
      }
    }
    if (p.furnishing == target.furnishing) s += 1;
    return s;
  }

  candidates.sort((a, b) => score(b).compareTo(score(a)));
  // Drop zero-score matches — they're not actually similar, just filler.
  final ranked = candidates.where((p) => score(p) > 0).toList();
  return ranked.take(limit).toList();
}

/// Shared sort logic used across search & category screens so "Newest" and
/// other options behave consistently everywhere.
/// Sort keys: 'default' (recommended), 'price_low', 'price_high',
/// 'rating', 'newest', 'area_large'.
List<Property> sortProperties(List<Property> input, String sortOption) {
  final results = List<Property>.of(input);
  switch (sortOption) {
    case 'price_low':
      results.sort((a, b) => a.price.compareTo(b.price));
      break;
    case 'price_high':
      results.sort((a, b) => b.price.compareTo(a.price));
      break;
    case 'rating':
      results.sort((a, b) => b.rating.compareTo(a.rating));
      break;
    case 'newest':
      // dummyProperties order acts as a recency proxy (later index = posted
      // more recently) until a real `createdAt` field comes from the backend.
      results.sort((a, b) {
        final ia = dummyProperties.indexWhere((p) => p.id == a.id);
        final ib = dummyProperties.indexWhere((p) => p.id == b.id);
        return ib.compareTo(ia);
      });
      break;
    case 'area_large':
      results.sort((a, b) => b.area.compareTo(a.area));
      break;
    default:
      // 'default' / 'relevant' — keep the incoming (already relevance-filtered) order.
      break;
  }
  return results;
}

/// Notifies listening screens whenever dummyProperties changes (add/favorite toggle),
/// so they can refresh and show the latest data.
final ValueNotifier<int> propertiesVersion = ValueNotifier(0);

void notifyPropertiesChanged() {
  propertiesVersion.value++;
}

/// Gives each property a spread-out map position without needing to hand-edit
/// every dummy entry with real coordinates. If a property already has a
/// non-default lat/lng (e.g. once real data comes from the backend), that
/// value is used as-is.
extension PropertyMapLocation on Property {
  static const double _defaultLat = 19.0760;
  static const double _defaultLng = 72.8777;

  // Major Indian cities used as anchor points so properties spread out
  // realistically across the whole country instead of clustering in one spot.
  static const List<({double lat, double lng})> _cityAnchors = [
    (lat: 19.0760, lng: 72.8777), // Mumbai
    (lat: 18.5204, lng: 73.8567), // Pune
    (lat: 28.6139, lng: 77.2090), // Delhi
    (lat: 12.9716, lng: 77.5946), // Bengaluru
    (lat: 17.3850, lng: 78.4867), // Hyderabad
    (lat: 13.0827, lng: 80.2707), // Chennai
    (lat: 22.5726, lng: 88.3639), // Kolkata
    (lat: 23.0225, lng: 72.5714), // Ahmedabad
    (lat: 26.9124, lng: 75.7873), // Jaipur
    (lat: 21.1458, lng: 79.0882), // Nagpur
  ];

  ({double lat, double lng}) get mapPosition {
    if (latitude != _defaultLat || longitude != _defaultLng) {
      return (lat: latitude, lng: longitude);
    }
    // Deterministic pseudo-random position based on the property id:
    // pick a city anchor, then jitter a little around it so markers
    // spread across India instead of sitting in a single straight line.
    final hash = id.hashCode;
    final anchor = _cityAnchors[hash.abs() % _cityAnchors.length];
    final jitterLat = (((hash % 1000) / 1000) - 0.5) * 0.6;
    final jitterLng = ((((hash ~/ 1000) % 1000) / 1000) - 0.5) * 0.6;

    return (lat: anchor.lat + jitterLat, lng: anchor.lng + jitterLng);
  }
}