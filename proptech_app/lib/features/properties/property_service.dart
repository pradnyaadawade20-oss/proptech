import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../../core/api/api_client.dart';
import 'property.dart';

/// Talks to /api/properties/*. Add Property and Home listing use this to
/// create/list real properties (with real UUIDs + owner_id).
class PropertyService {
  PropertyService._();
  static final PropertyService instance = PropertyService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _toException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(message);
  }

  Future<List<Property>> getAll() async {
    try {
      final response = await _dio.get('/api/properties');
      final list = response.data['properties'] as List<dynamic>? ?? [];
      return list.map((e) => Property.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Fetches real properties from the backend and replaces the shared
  /// property list every screen reads from (PropertyStore.instance.all).
  /// Call this once at app startup (main.dart) and again on pull-to-refresh /
  /// after creating a listing, so the whole app shows real data.
  Future<void> loadReal() async {
    final fetched = await getAll();
    dummyProperties
      ..clear()
      ..addAll(fetched);
    notifyPropertiesChanged();
  }

  Future<Property> getById(String id) async {
    try {
      final response = await _dio.get('/api/properties/$id');
      return Property.fromJson(response.data['property'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Properties listed by a specific owner (backs the "Listed" count on
  /// Owner Details, and the My Properties screen). Backend endpoint is
  /// /api/properties/my?owner_id=... (kept as "/my" for the logged-in
  /// owner's own dashboard; also usable to look up any owner by id).
  Future<List<Property>> getByOwner(String ownerId) async {
    try {
      final response = await _dio.get('/api/properties/my', queryParameters: {'owner_id': ownerId});
      final list = response.data['properties'] as List<dynamic>? ?? [];
      return list.map((e) => Property.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Property> create({
    required String ownerId,
    required String title,
    required String imageUrl,
    required double price,
    required String priceUnit,
    required String bhk,
    required String furnishing,
    required String location,
    required String category,
    required List<String> amenities,
    double area = 0,
    int bathrooms = 0,
    int balconies = 0,
    int floorNumber = 0,
    int totalFloors = 0,
    String city = '',
    String locality = '',
    String society = '',
    String pincode = '',
    double securityDeposit = 0,
    double maintenanceCharges = 0,
    List<String> preferredTenants = const [],
    DateTime? availableFrom,
    String description = '',
    int? propertyAgeYears,
    String facing = '',
    String ownershipType = '',
    bool isPriceNegotiable = false,
    String contactPreference = 'both',
  }) async {
    try {
      String? dateOnly(DateTime? d) => d == null
          ? null
          : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final response = await _dio.post('/api/properties', data: {
        'owner_id': ownerId,
        'title': title,
        'image_url': imageUrl,
        'price': price,
        'price_unit': priceUnit,
        'bhk': bhk,
        'furnishing': furnishing,
        'location': location,
        'category': category,
        'amenities': amenities,
        'area': area,
        'bathrooms': bathrooms,
        'balconies': balconies,
        'floor_number': floorNumber,
        'total_floors': totalFloors,
        'city': city,
        'locality': locality,
        'society': society,
        'pincode': pincode,
        'security_deposit': securityDeposit,
        'maintenance_charges': maintenanceCharges,
        'preferred_tenants': preferredTenants,
        'available_from': dateOnly(availableFrom),
        'description': description,
        'property_age_years': propertyAgeYears,
        'facing': facing,
        'ownership_type': ownershipType,
        'is_price_negotiable': isPriceNegotiable,
        'contact_preference': contactPreference,
      });
      return Property.fromJson(response.data['property'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Saves changes to an existing listing (PUT /api/properties/:id). The
  /// backend replaces every field, so the edit form passes the full set
  /// (pre-filled from the current property). Only the owner may do this.
  Future<Property> update({
    required String id,
    required String title,
    required String imageUrl,
    required double price,
    required String priceUnit,
    required String bhk,
    required String furnishing,
    required String location,
    required String category,
    required List<String> amenities,
    double area = 0,
    int bathrooms = 0,
    int balconies = 0,
    int floorNumber = 0,
    int totalFloors = 0,
    String city = '',
    String locality = '',
    String society = '',
    String pincode = '',
    double securityDeposit = 0,
    double maintenanceCharges = 0,
    List<String> preferredTenants = const [],
    DateTime? availableFrom,
    String description = '',
    int? propertyAgeYears,
    String facing = '',
    String ownershipType = '',
    bool isPriceNegotiable = false,
    String contactPreference = 'both',
  }) async {
    try {
      String? dateOnly(DateTime? d) => d == null
          ? null
          : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final response = await _dio.put('/api/properties/$id', data: {
        'title': title,
        'image_url': imageUrl,
        'price': price,
        'price_unit': priceUnit,
        'bhk': bhk,
        'furnishing': furnishing,
        'location': location,
        'category': category,
        'amenities': amenities,
        'area': area,
        'bathrooms': bathrooms,
        'balconies': balconies,
        'floor_number': floorNumber,
        'total_floors': totalFloors,
        'city': city,
        'locality': locality,
        'society': society,
        'pincode': pincode,
        'security_deposit': securityDeposit,
        'maintenance_charges': maintenanceCharges,
        'preferred_tenants': preferredTenants,
        'available_from': dateOnly(availableFrom),
        'description': description,
        'property_age_years': propertyAgeYears,
        'facing': facing,
        'ownership_type': ownershipType,
        'is_price_negotiable': isPriceNegotiable,
        'contact_preference': contactPreference,
      });
      return Property.fromJson(response.data['property'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Removes one gallery photo or the video tour, identified by its URL
  /// (.../api/properties/<id>/media/<mediaId>). Only the owner can.
  Future<void> deleteMedia(String propertyId, String mediaUrl) async {
    try {
      final mediaId = Uri.parse(mediaUrl).pathSegments.last;
      await _dio.delete('/api/properties/$propertyId/media/$mediaId');
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Permanently deletes a listing (only its owner can). The backend also
  /// removes its photos, visits, favorites and agreements.
  Future<void> delete(String id) async {
    try {
      await _dio.delete('/api/properties/$id');
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Uploads the actual picked photo's bytes for [propertyId] and returns
  /// the real image_url (serving those exact bytes back) so every screen
  /// — owner's own listing, buyer's browse/detail screens, home — shows
  /// the real photo instead of a placeholder.
  Future<String> uploadImage(String propertyId, XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: image.name),
      });
      final response = await _dio.post('/api/properties/$propertyId/image', data: formData);
      return response.data['image_url'] as String;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// "Verify Now" — uploads a photo taken with the in-app camera plus the
  /// GPS coordinates captured at that same moment. The backend stores
  /// both and marks the property verified. Returns the verification
  /// photo's URL on success.
  Future<String> verifyProperty(String propertyId, XFile photo, {required double lat, required double lng}) async {
    try {
      final bytes = await photo.readAsBytes();
      final formData = FormData.fromMap({
        'photo': MultipartFile.fromBytes(bytes, filename: photo.name),
        'lat': lat.toString(),
        'lng': lng.toString(),
      });
      final response = await _dio.post('/api/properties/$propertyId/verify', data: formData);
      return response.data['verification_photo_url'] as String;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Uploads the extra gallery photos and/or the walkthrough video for
  /// [propertyId] (the cover photo goes through [uploadImage]). Returns the
  /// property's full list of extra photo URLs and its video URL (or null).
  Future<({List<String> imageUrls, String? videoUrl})> uploadMedia(
    String propertyId, {
    List<XFile> images = const [],
    XFile? video,
  }) async {
    try {
      Future<MultipartFile> part(XFile f) async => kIsWeb
          ? MultipartFile.fromBytes(await f.readAsBytes(), filename: f.name)
          : await MultipartFile.fromFile(f.path, filename: f.name);

      final formData = FormData();
      for (final img in images) {
        formData.files.add(MapEntry('images', await part(img)));
      }
      if (video != null) {
        formData.files.add(MapEntry('video', await part(video)));
      }
      final response = await _dio.post(
        '/api/properties/$propertyId/media',
        data: formData,
        // Videos are big — allow far longer than the default 60s.
        options: Options(
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
      final data = response.data as Map<String, dynamic>;
      final urls = (data['additional_image_urls'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      return (imageUrls: urls, videoUrl: data['video_tour_url'] as String?);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}