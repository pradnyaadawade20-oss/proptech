/// Property model. Fields mirror the backend API response (/api/properties).
/// Real data is held in PropertyStore (see property_store.dart).
library;

import 'package:flutter/foundation.dart';
import 'property_extras.dart';
import 'property_store.dart';

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

  // --- Listing detail fields (Post Property form) ---
  final int bathrooms;
  final int balconies;
  final String city;
  final String locality;
  final String society; // society / building name
  final String pincode;
  /// Rent listings only (0 = not set).
  final double securityDeposit;
  final double maintenanceCharges;
  /// Who the owner prefers for rent: 'Family' | 'Bachelors' | 'Company'.
  final List<String> preferredTenants;
  /// Date from which the property is vacant / available.
  final DateTime? availableFrom;
  final String description;
  /// 'Freehold' | 'Leasehold' | 'Co-operative Society' | 'Power of Attorney' or ''.
  final String ownershipType;
  /// 'call' | 'chat' | 'both'
  final String contactPreference;
  /// 'owner' | 'broker' — who posted the listing (search filter).
  final String postedBy;

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

  // --- Owner info (owner_id comes from GET /api/properties) ---
  final String ownerId;
  final String ownerName;

  /// 'available' | 'rented' | 'sold'
  final String listingStatus;
  final DateTime? createdAt;

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
    this.rating = 0,
    this.reviewCount = 0,
    this.amenities = const [],
    this.category = 'Residential',
    this.area = 0,
    this.possessionStatus = '',
    this.ageOfPropertyYears = -1, // -1 = unknown
    this.floorNumber = 0,
    this.totalFloors = 0,
    this.facing = '',
    this.bathrooms = 0,
    this.balconies = 0,
    this.city = '',
    this.locality = '',
    this.society = '',
    this.pincode = '',
    this.securityDeposit = 0,
    this.maintenanceCharges = 0,
    this.preferredTenants = const [],
    this.availableFrom,
    this.description = '',
    this.ownershipType = '',
    this.contactPreference = 'both',
    this.postedBy = 'owner',
    this.latitude = 0,
    this.longitude = 0,
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
    this.ownerId = '',
    this.ownerName = '',
    this.listingStatus = 'available',
    this.createdAt,
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
    double num_(String k, [double d = 0]) => (json[k] as num?)?.toDouble() ?? d;
    int int_(String k, [int d = 0]) => (json[k] as num?)?.toInt() ?? d;
    final gallery = (json['additional_image_urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return Property(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      price: num_('price'),
      priceUnit: json['price_unit'] as String? ?? '',
      bhk: json['bhk'] as String? ?? '',
      furnishing: json['furnishing'] as String? ?? '',
      location: json['location'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      rating: num_('rating'),
      reviewCount: int_('review_count'),
      amenities: (json['amenities'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      category: json['category'] as String? ?? 'Residential',
      ownerId: json['owner_id'] as String? ?? '',
      ownerName: json['owner_name'] as String? ?? '',
      listingStatus: json['listing_status'] as String? ?? 'available',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
      // Optional fields — used automatically once the backend starts sending them.
      area: num_('area'),
      floorNumber: int_('floor_number'),
      totalFloors: int_('total_floors'),
      facing: json['facing'] as String? ?? '',
      ageOfPropertyYears: int_('property_age_years', -1),
      bathrooms: int_('bathrooms'),
      balconies: int_('balconies'),
      city: json['city'] as String? ?? '',
      locality: json['locality'] as String? ?? '',
      society: json['society'] as String? ?? '',
      pincode: json['pincode'] as String? ?? '',
      securityDeposit: num_('security_deposit'),
      maintenanceCharges: num_('maintenance_charges'),
      preferredTenants: (json['preferred_tenants'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      availableFrom: DateTime.tryParse(json['available_from'] as String? ?? ''),
      description: json['description'] as String? ?? '',
      ownershipType: json['ownership_type'] as String? ?? '',
      contactPreference: json['contact_preference'] as String? ?? 'both',
      postedBy: json['posted_by'] == 'broker' ? 'broker' : 'owner',
      latitude: num_('latitude'),
      longitude: num_('longitude'),
      additionalImageUrls: gallery,
      videoTourUrl: json['video_tour_url'] as String?,
      floorPlanUrl: json['floor_plan_url'] as String?,
      reraNumber: json['rera_number'] as String?,
      isPriceNegotiable: json['is_price_negotiable'] as bool? ?? false,
    );
  }

  Property copyWith({
    bool? isFavorite,
    String? imageUrl,
    List<String>? additionalImageUrls,
    String? videoTourUrl,
    bool? isVerified,
  }) {
    return Property(
      id: id,
      title: title,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price,
      priceUnit: priceUnit,
      bhk: bhk,
      furnishing: furnishing,
      location: location,
      isVerified: isVerified ?? this.isVerified,
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
      bathrooms: bathrooms,
      balconies: balconies,
      city: city,
      locality: locality,
      society: society,
      pincode: pincode,
      securityDeposit: securityDeposit,
      maintenanceCharges: maintenanceCharges,
      preferredTenants: preferredTenants,
      availableFrom: availableFrom,
      description: description,
      ownershipType: ownershipType,
      contactPreference: contactPreference,
      postedBy: postedBy,
      latitude: latitude,
      longitude: longitude,
      additionalImageUrls: additionalImageUrls ?? this.additionalImageUrls,
      videoTourUrl: videoTourUrl ?? this.videoTourUrl,
      floorPlanUrl: floorPlanUrl,
      reraNumber: reraNumber,
      verificationDocuments: verificationDocuments,
      possessionDate: possessionDate,
      isPriceNegotiable: isPriceNegotiable,
      priceHistory: priceHistory,
      nearbyLandmarks: nearbyLandmarks,
      ownershipDocuments: ownershipDocuments,
      ownerId: ownerId,
      ownerName: ownerName,
      listingStatus: listingStatus,
      createdAt: createdAt,
    );
  }
}

/// Legacy alias: older screens (favorites, search, category...) still read and
/// write `dummyProperties`. It is the very same list as
/// PropertyStore.instance.all, so there is only one source of truth.
List<Property> get dummyProperties => PropertyStore.instance.all;

/// Matches a property against the same "property type" categories used in
/// the search screen's quick-filter chips (Apartment/Villa/PG/House/Office).
/// Shared so search screen and saved-search alert checks stay in sync.
bool propertyMatchesType(Property p, String? type) {
  if (type == null) return true;
  final title = p.title.toLowerCase();
  switch (type) {
    case 'Apartment':
      return p.category == 'Residential' &&
          p.bhk != 'PG' &&
          p.bhk != '4 BHK' &&
          p.bhk != '5 BHK' &&
          !title.contains('bungalow') &&
          !title.contains('villa') &&
          !title.contains('house');
    case 'Villa':
      return p.bhk == '4 BHK' ||
          p.bhk == '5 BHK' ||
          title.contains('bungalow') ||
          title.contains('villa');
    case 'PG':
      return p.bhk == 'PG';
    case 'House':
      return p.category == 'Residential' && (title.contains('house') || title.contains('bungalow'));
    case 'Plot':
      return p.category == 'Plot/Land';
    // Commercial types are saved in `bhk` by the Post Property form.
    case 'Office Space':
    case 'Shop':
    case 'Warehouse':
    case 'Showroom':
      return p.category == 'Commercial' && p.bhk == type;
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
  final candidates = PropertyStore.instance.all.where((p) => p.id != target.id).toList();

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
      results.sort((a, b) {
        final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
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

/// Notifies listening screens whenever PropertyStore changes (load/add/favorite toggle),
/// so they can refresh and show the latest data.
final ValueNotifier<int> propertiesVersion = ValueNotifier(0);

void notifyPropertiesChanged() {
  propertiesVersion.value++;
}

/// Real map position. Properties without stored coordinates (0,0) have no
/// position and are skipped on the map.
extension PropertyMapLocation on Property {
  bool get hasMapPosition => latitude != 0 || longitude != 0;

  ({double lat, double lng}) get mapPosition => (lat: latitude, lng: longitude);
}