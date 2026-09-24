import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import 'property.dart';

/// Talks to /api/properties/*. Add Property and Home listing use this to
/// create/list real properties (with real UUIDs + owner_id) instead of
/// the local dummyProperties list.
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

  /// Properties listed by a given owner (GET /api/properties/my?owner_id=).
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
  }) async {
    try {
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
      });
      return Property.fromJson(response.data['property'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}