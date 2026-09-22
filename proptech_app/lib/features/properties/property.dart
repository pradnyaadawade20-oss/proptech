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

  Property copyWith({bool? isFavorite}) {
    return Property(
      id: id,
      title: title,
      imageUrl: imageUrl,
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

/// Dummy data — replace with real API call once backend is ready.
final List<Property> dummyProperties = [
  Property(
    id: '1',
    title: '1 BHK Apartment',
    imageUrl: 'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688',
    price: 25000,
    priceUnit: '/month',
    bhk: '1 BHK',
    furnishing: 'Semi Furnished',
    location: 'Andheri West, Mumbai',
    isVerified: true,
    rating: 4.3,
    reviewCount: 98,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267',
      'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2',
      'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/3112/3112-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
    reraNumber: 'P51800012345',
    verificationDocuments: ['Sale Deed', 'Property Tax Receipt', 'RERA Certificate'],
    ownershipDocuments: [
      const OwnershipDocument(
        name: 'Sale Deed',
        imageUrl: 'https://images.unsplash.com/photo-1554224155-6726b3ff858f',
        isVerified: true,
      ),
      const OwnershipDocument(
        name: 'Property Tax Receipt',
        imageUrl: 'https://images.unsplash.com/photo-1554224155-8d04cb21cd6c',
        isVerified: true,
      ),
      const OwnershipDocument(
        name: 'RERA Certificate',
        imageUrl: 'https://images.unsplash.com/photo-1450101499163-c8848c66ca85',
        isVerified: true,
      ),
    ],
    possessionDate: null,
    isPriceNegotiable: true,
    priceHistory: [
      PricePoint(date: DateTime(2025, 2, 1), price: 23000),
      PricePoint(date: DateTime(2025, 5, 1), price: 24000),
      PricePoint(date: DateTime(2025, 8, 1), price: 24500),
      PricePoint(date: DateTime(2025, 11, 1), price: 25000),
    ],
    nearbyLandmarks: [
      const NearbyLandmark(name: 'Andheri Metro Station', type: 'metro', distanceKm: 0.8),
      const NearbyLandmark(name: 'St. Xavier\'s High School', type: 'school', distanceKm: 1.2),
      const NearbyLandmark(name: 'Kokilaben Hospital', type: 'hospital', distanceKm: 2.5),
      const NearbyLandmark(name: 'Infiniti Mall', type: 'mall', distanceKm: 1.8),
    ],
  ),
  Property(
    id: '2',
    title: '2 BHK Apartment',
    imageUrl: 'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2',
    price: 42000,
    priceUnit: '/month',
    bhk: '2 BHK',
    furnishing: 'Fully Furnished',
    location: 'Powai, Mumbai',
    isVerified: true,
    isFavorite: true,
    rating: 4.5,
    reviewCount: 120,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1502672023488-70e25813eb80',
      'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
    ],
    reraNumber: 'P51800067890',
    verificationDocuments: ['Sale Deed', 'RERA Certificate'],
    ownershipDocuments: [
      const OwnershipDocument(
        name: 'Sale Deed',
        imageUrl: 'https://images.unsplash.com/photo-1554224155-6726b3ff858f',
        isVerified: true,
      ),
      const OwnershipDocument(
        name: 'RERA Certificate',
        imageUrl: 'https://images.unsplash.com/photo-1450101499163-c8848c66ca85',
        isVerified: true,
      ),
    ],
    isPriceNegotiable: false,
    priceHistory: [
      PricePoint(date: DateTime(2025, 3, 1), price: 40000),
      PricePoint(date: DateTime(2025, 7, 1), price: 41000),
      PricePoint(date: DateTime(2025, 11, 1), price: 42000),
    ],
    nearbyLandmarks: [
      const NearbyLandmark(name: 'Powai Lake', type: 'park', distanceKm: 0.5),
      const NearbyLandmark(name: 'Hiranandani Hospital', type: 'hospital', distanceKm: 1.0),
      const NearbyLandmark(name: 'IIT Bombay Metro', type: 'metro', distanceKm: 2.1),
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/4029/4029-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '3',
    title: 'PG for Boys',
    imageUrl: 'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267',
    price: 9000,
    priceUnit: '/month',
    bhk: 'PG',
    furnishing: 'Furnished',
    location: 'Bandra, Mumbai',
    isVerified: false,
    rating: 4.2,
    reviewCount: 45,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf',
      'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
      'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/12119/12119-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '4',
    title: 'Furnished Office Space',
    imageUrl: 'https://images.unsplash.com/photo-1497366216548-37526070297c',
    price: 85000,
    priceUnit: '/month',
    bhk: '1200',
    furnishing: 'Fully Furnished',
    location: 'BKC, Mumbai',
    isVerified: true,
    rating: 4.6,
    reviewCount: 32,
    category: 'Commercial',
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1497215728101-856f4ea42174',
      'https://images.unsplash.com/photo-1524758631624-e2822e304c36',
      'https://images.unsplash.com/photo-1524749292158-7540c2494485',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/918/918-720.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '5',
    title: 'Retail Shop on Main Road',
    imageUrl: 'https://images.unsplash.com/photo-1441986300917-64674bd600d8',
    price: 3500000,
    priceUnit: '',
    bhk: '450',
    furnishing: 'Unfurnished',
    location: 'Andheri East, Mumbai',
    isVerified: true,
    rating: 4.1,
    reviewCount: 12,
    category: 'Commercial',
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1441986300917-64674bd600d8',
      'https://images.unsplash.com/photo-1560518883-ce09059eeffa',
      'https://images.unsplash.com/photo-1567449303078-57ad995bd17f',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/283/283-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '6',
    title: 'Warehouse / Godown',
    imageUrl: 'https://images.unsplash.com/photo-1553413077-190dd305871c',
    price: 120000,
    priceUnit: '/month',
    bhk: '5000',
    furnishing: 'Unfurnished',
    location: 'Bhiwandi, Thane',
    isVerified: false,
    rating: 4.0,
    reviewCount: 8,
    category: 'Commercial',
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1553413077-190dd305871c',
      'https://images.unsplash.com/photo-1553413077-190dd305871c',
      'https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/4010/4010-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '7',
    title: 'Residential Plot',
    imageUrl: 'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
    price: 1800000,
    priceUnit: '',
    bhk: '1200',
    furnishing: 'Unfurnished',
    location: 'Karjat, Raigad',
    isVerified: true,
    rating: 4.3,
    reviewCount: 15,
    category: 'Plot/Land',
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/4010/4010-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '8',
    title: 'NA Plot near Highway',
    imageUrl: 'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
    price: 3200000,
    priceUnit: '',
    bhk: '2400',
    furnishing: 'Unfurnished',
    location: 'Panvel, Navi Mumbai',
    isVerified: false,
    rating: 4.0,
    reviewCount: 6,
    category: 'Plot/Land',
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/33952/33952-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '9',
    title: 'Agricultural Land',
    imageUrl: 'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
    price: 950000,
    priceUnit: '',
    bhk: '8000',
    furnishing: 'Unfurnished',
    location: 'Wada, Palghar',
    isVerified: false,
    rating: 3.9,
    reviewCount: 4,
    category: 'Plot/Land',
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/33952/33952-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '10',
    title: 'Corner Plot near School',
    imageUrl: 'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
    price: 2100000,
    priceUnit: '',
    bhk: '1500',
    furnishing: 'Unfurnished',
    location: 'Neral, Raigad',
    isVerified: true,
    rating: 4.2,
    reviewCount: 9,
    category: 'Plot/Land',
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/4010/4010-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),

  // ── Buy (resale) listings ──────────────────────────────────────────────
  const Property(
    id: '11',
    title: '2 BHK Resale Flat',
    imageUrl: 'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2',
    price: 8500000,
    priceUnit: '',
    bhk: '2 BHK',
    furnishing: 'Semi Furnished',
    location: 'Chembur, Mumbai',
    isVerified: true,
    rating: 4.4,
    reviewCount: 56,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1502672023488-70e25813eb80',
      'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
      'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/4029/4029-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  Property(
    id: '12',
    title: '3 BHK Sea View Apartment',
    imageUrl: 'https://images.unsplash.com/photo-1512917774080-9991f1c4c750',
    price: 21000000,
    priceUnit: '',
    bhk: '3 BHK',
    furnishing: 'Fully Furnished',
    location: 'Worli, Mumbai',
    isVerified: true,
    rating: 4.8,
    reviewCount: 74,
    possessionStatus: 'Under Construction',
    possessionDate: DateTime(2027, 6, 1),
    isPriceNegotiable: true,
    reraNumber: 'P51800099887',
    verificationDocuments: ['RERA Certificate', 'Approved Building Plan'],
    ownershipDocuments: [
      const OwnershipDocument(
        name: 'RERA Certificate',
        imageUrl: 'https://images.unsplash.com/photo-1450101499163-c8848c66ca85',
        isVerified: true,
      ),
    ],
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1600585154340-be6161a56a0c',
      'https://images.unsplash.com/photo-1570129477492-45c003edd2be',
    ],
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
    priceHistory: [
      PricePoint(date: DateTime(2025, 1, 1), price: 19500000),
      PricePoint(date: DateTime(2025, 6, 1), price: 20200000),
      PricePoint(date: DateTime(2025, 11, 1), price: 21000000),
    ],
    nearbyLandmarks: [
      const NearbyLandmark(name: 'Worli Sea Face', type: 'park', distanceKm: 0.3),
      const NearbyLandmark(name: 'Worli Metro Station', type: 'metro', distanceKm: 1.1),
      const NearbyLandmark(name: 'Breach Candy Hospital', type: 'hospital', distanceKm: 3.0),
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/25991/25991-360.mp4',
  ),
  const Property(
    id: '13',
    title: '1 BHK Compact Flat',
    imageUrl: 'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688',
    price: 4800000,
    priceUnit: '',
    bhk: '1 BHK',
    furnishing: 'Unfurnished',
    location: 'Thane West, Thane',
    isVerified: false,
    rating: 4.0,
    reviewCount: 22,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1502672023488-70e25813eb80',
      'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/3112/3112-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '14',
    title: 'Independent Bungalow',
    imageUrl: 'https://images.unsplash.com/photo-1568605114967-8130f3a36994',
    price: 32000000,
    priceUnit: '',
    bhk: '4 BHK',
    furnishing: 'Fully Furnished',
    location: 'Juhu, Mumbai',
    isVerified: true,
    rating: 4.9,
    reviewCount: 30,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1568605114967-8130f3a36994',
      'https://images.unsplash.com/photo-1613977257363-707ba9348227',
      'https://images.unsplash.com/photo-1570129477492-45c003edd2be',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/25991/25991-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '18',
    title: 'Luxury Villa with Garden',
    imageUrl: 'https://images.unsplash.com/photo-1613977257363-707ba9348227',
    price: 45000000,
    priceUnit: '',
    bhk: '5 BHK',
    furnishing: 'Fully Furnished',
    location: 'Alibaug, Raigad',
    isVerified: true,
    rating: 4.8,
    reviewCount: 18,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1613977257363-707ba9348227',
      'https://images.unsplash.com/photo-1568605114967-8130f3a36994',
      'https://images.unsplash.com/photo-1512917774080-9991f1c4c750',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/25991/25991-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '19',
    title: 'Beachside Villa',
    imageUrl: 'https://images.unsplash.com/photo-1512917774080-9991f1c4c750',
    price: 6200000,
    priceUnit: '/month',
    bhk: '4 BHK',
    furnishing: 'Fully Furnished',
    location: 'Lonavala, Pune',
    isVerified: true,
    rating: 4.7,
    reviewCount: 42,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1512917774080-9991f1c4c750',
      'https://images.unsplash.com/photo-1613977257363-707ba9348227',
      'https://images.unsplash.com/photo-1600585154340-be6161a56a0c',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/4029/4029-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '20',
    title: 'Independent House with Terrace',
    imageUrl: 'https://images.unsplash.com/photo-1570129477492-45c003edd2be',
    price: 9500000,
    priceUnit: '',
    bhk: '3 BHK',
    furnishing: 'Semi Furnished',
    location: 'Vasai, Palghar',
    isVerified: false,
    rating: 4.2,
    reviewCount: 11,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1570129477492-45c003edd2be',
      'https://images.unsplash.com/photo-1568605114967-8130f3a36994',
      'https://images.unsplash.com/photo-1600585154340-be6161a56a0c',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/25991/25991-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '21',
    title: 'Row House in Gated Society',
    imageUrl: 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c',
    price: 55000,
    priceUnit: '/month',
    bhk: '3 BHK',
    furnishing: 'Fully Furnished',
    location: 'Kharghar, Navi Mumbai',
    isVerified: true,
    rating: 4.5,
    reviewCount: 27,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1600585154340-be6161a56a0c',
      'https://images.unsplash.com/photo-1502672023488-70e25813eb80',
      'https://images.unsplash.com/photo-1570129477492-45c003edd2be',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/25991/25991-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),

  // ── PG listings ─────────────────────────────────────────────────────────
  const Property(
    id: '15',
    title: 'PG for Girls',
    imageUrl: 'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf',
    price: 11000,
    priceUnit: '/month',
    bhk: 'PG',
    furnishing: 'Furnished',
    location: 'Andheri East, Mumbai',
    isVerified: true,
    rating: 4.4,
    reviewCount: 60,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf',
      'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
      'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/12118/12118-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '16',
    title: 'Co-living PG for Working Professionals',
    imageUrl: 'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af',
    price: 13500,
    priceUnit: '/month',
    bhk: 'PG',
    furnishing: 'Fully Furnished',
    location: 'Powai, Mumbai',
    isVerified: true,
    rating: 4.6,
    reviewCount: 88,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af',
      'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf',
      'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/12119/12119-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),
  const Property(
    id: '17',
    title: 'Budget PG near Station',
    imageUrl: 'https://images.unsplash.com/photo-1560185127-6ed189bf02f4',
    price: 7000,
    priceUnit: '/month',
    bhk: 'PG',
    furnishing: 'Semi Furnished',
    location: 'Dadar, Mumbai',
    isVerified: false,
    rating: 3.8,
    reviewCount: 19,
    additionalImageUrls: [
      'https://images.unsplash.com/photo-1560185127-6ed189bf02f4',
      'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf',
      'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267',
    ],
    videoTourUrl: 'https://assets.mixkit.co/videos/12118/12118-360.mp4',
    floorPlanUrl: 'https://images.unsplash.com/photo-1503387762-592deb58ef4e',
  ),

  // ── Recently posted (home dashboard) ────────────────────────────────────
  const Property(
    id: 'rp1',
    title: '1 RK Studio Apartment',
    imageUrl: 'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267',
    price: 10000,
    priceUnit: '/month',
    bhk: '1 RK',
    furnishing: 'Semi Furnished',
    location: 'Priyadarshani CHS, Gaurish Nagar, Chembur',
    isVerified: false,
    rating: 4.1,
    reviewCount: 5,
  ),
  const Property(
    id: 'rp2',
    title: '1 RK Studio Apartment',
    imageUrl: 'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2',
    price: 10000,
    priceUnit: '/month',
    bhk: '1 RK',
    furnishing: 'Unfurnished',
    location: 'Priyadarshani CHS, Savitribai Rd, Chembur',
    isVerified: false,
    rating: 4.0,
    reviewCount: 3,
  ),
  const Property(
    id: 'rp3',
    title: '1 RK Studio Apartment',
    imageUrl: 'https://images.unsplash.com/photo-1502672023488-70e25813eb80',
    price: 6500,
    priceUnit: '/month',
    bhk: '1 RK',
    furnishing: 'Unfurnished',
    location: 'Apartment Complex, Chembur',
    isVerified: false,
    rating: 3.9,
    reviewCount: 2,
  ),
  const Property(
    id: 'rp4',
    title: '2 BHK Apartment',
    imageUrl: 'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
    price: 18000,
    priceUnit: '/month',
    bhk: '2 BHK',
    furnishing: 'Fully Furnished',
    location: 'Sunrise Towers, Andheri',
    isVerified: true,
    rating: 4.4,
    reviewCount: 14,
  ),

  // ── Recommended Projects (home dashboard) ───────────────────────────────
  const Property(
    id: 'proj1',
    title: 'Marathon Neopark',
    imageUrl: 'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab',
    price: 6500000,
    priceUnit: '',
    bhk: '1 BHK',
    furnishing: 'Unfurnished',
    location: 'Bhandup West, Mumbai',
    isVerified: true,
    rating: 4.3,
    reviewCount: 41,
  ),
  const Property(
    id: 'proj2',
    title: 'Sayba Swarnaz',
    imageUrl: 'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00',
    price: 9200000,
    priceUnit: '',
    bhk: '2 BHK',
    furnishing: 'Semi Furnished',
    location: 'Kandivali, Mumbai',
    isVerified: true,
    rating: 4.5,
    reviewCount: 67,
  ),
  const Property(
    id: 'proj3',
    title: 'Lodha Amara',
    imageUrl: 'https://images.unsplash.com/photo-1512917774080-9991f1c4c750',
    price: 11500000,
    priceUnit: '',
    bhk: '3 BHK',
    furnishing: 'Fully Furnished',
    location: 'Thane West, Mumbai',
    isVerified: true,
    rating: 4.6,
    reviewCount: 89,
  ),
];
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