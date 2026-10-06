import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import 'visit.dart';

/// Talks to /api/visits.
class VisitService {
  VisitService._();
  static final VisitService instance = VisitService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _toException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(message);
  }

  /// [asOwner] = true → visits requested on properties I own;
  /// false → visits I booked as a visitor.
  Future<List<Visit>> getVisits({bool asOwner = false}) async {
    try {
      final response = await _dio.get(
        '/api/visits',
        queryParameters: asOwner ? {'as': 'owner'} : null,
      );
      final list = response.data['visits'] as List<dynamic>? ?? [];
      return list.map((e) => Visit.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Visit> create({required String propertyId, required DateTime scheduledAt}) async {
    try {
      final response = await _dio.post('/api/visits', data: {
        'property_id': propertyId,
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      });
      return Visit.fromJson(response.data['visit'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Visitor's feedback after a completed visit.
  /// [interest] = 'interested' | 'maybe' | 'not_interested'.
  Future<Visit> submitFeedback(String id, {required String interest, String note = ''}) async {
    try {
      final response = await _dio.post('/api/visits/$id/feedback', data: {
        'interest': interest,
        'note': note,
      });
      return Visit.fromJson(response.data['visit'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<void> updateStatus(String id, VisitStatus status) async {
    try {
      await _dio.patch('/api/visits/$id/status', data: {'status': status.name});
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}