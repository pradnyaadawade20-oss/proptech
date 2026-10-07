import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import 'review.dart';

/// Talks to the reviews API:
///   GET  /api/properties/:id/reviews              (public)
///   GET  /api/properties/:id/reviews/eligibility  (login)
///   POST /api/properties/:id/reviews              (login, needs a completed visit)
class ReviewService {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _toException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(message);
  }

  Future<List<Review>> getReviews(String propertyId) async {
    try {
      final response = await _dio.get('/api/properties/$propertyId/reviews');
      final list = (response.data['reviews'] as List?) ?? const [];
      return list.map((e) => Review.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Returns null when not logged in / the check fails — the UI then simply
  /// hides the "Write a review" button.
  Future<ReviewEligibility?> getEligibility(String propertyId) async {
    try {
      final response = await _dio.get('/api/properties/$propertyId/reviews/eligibility');
      final data = response.data as Map;
      return ReviewEligibility(
        canReview: data['can_review'] == true,
        reason: (data['reason'] as String?) ?? '',
      );
    } on DioException catch (_) {
      return null;
    }
  }

  Future<Review> create(String propertyId, {required int rating, String comment = ''}) async {
    try {
      final response = await _dio.post('/api/properties/$propertyId/reviews', data: {
        'rating': rating,
        'comment': comment,
      });
      return Review.fromJson(Map<String, dynamic>.from(response.data['review'] as Map));
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}