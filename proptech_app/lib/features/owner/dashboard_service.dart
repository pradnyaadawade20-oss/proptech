import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';
import 'owner_stats.dart';

/// Talks to GET /api/properties/dashboard-stats. Used by both
/// OwnerDashboardScreen and BrokerDashboardScreen — a broker's "client
/// listings" are just properties where owner_id = the broker's own user
/// id, so the same endpoint and OwnerStats shape work for both.
class DashboardService {
  DashboardService._();
  static final DashboardService instance = DashboardService._();

  final Dio _dio = ApiClient.instance.dio;

  /// Throws on failure — callers should catch and show a retry state
  /// rather than silently falling back to dummy numbers.
  Future<OwnerStats> getDashboardStats() async {
    final userId = await TokenStore.instance.getUserId();
    if (userId == null) {
      throw Exception('Not logged in.');
    }

    try {
      final response = await _dio.get(
        '/api/properties/dashboard-stats',
        queryParameters: {'owner_id': userId},
      );
      final stats = response.data['stats'] as Map<String, dynamic>;
      return OwnerStats(
        totalProperties: stats['total_properties'] as int? ?? 0,
        available: stats['available'] as int? ?? 0,
        rented: stats['rented'] as int? ?? 0,
        sold: stats['sold'] as int? ?? 0,
        activeLeads: stats['active_leads'] as int? ?? 0,
        visitsThisWeek: stats['visits_this_week'] as int? ?? 0,
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = (data is Map && data['error'] != null)
          ? data['error'].toString()
          : (e.message ?? 'Could not load dashboard stats.');
      throw Exception(message);
    }
  }
}