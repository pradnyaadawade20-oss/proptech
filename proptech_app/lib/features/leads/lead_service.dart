import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import 'lead.dart';

/// Talks to /api/leads.
class LeadService {
  LeadService._();
  static final LeadService instance = LeadService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _toException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(message);
  }

  /// Buyer taps "Contact Owner" / Call / Chat. [source]: contact | call | chat.
  Future<LeadResult> create({
    required String propertyId,
    String name = '',
    String phone = '',
    String message = '',
    String source = 'contact',
  }) async {
    try {
      final response = await _dio.post('/api/leads', data: {
        'property_id': propertyId,
        'name': name,
        'phone': phone,
        'message': message,
        'source': source,
      });
      final data = response.data as Map<String, dynamic>;
      return LeadResult(
        lead: Lead.fromJson(data['lead'] as Map<String, dynamic>),
        isNew: data['is_new'] as bool? ?? false,
        ownerName: data['owner_name'] as String? ?? '',
        ownerPhone: data['owner_phone'] as String? ?? '',
      );
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Fire-and-forget lead for plain Call / Chat taps. Never throws, so it can't
  /// block the dialer or the chat from opening.
  Future<void> track(String propertyId, String source) async {
    try {
      await create(propertyId: propertyId, source: source);
    } catch (_) {}
  }

  /// Leads on MY properties. [status]: null/'' = all.
  Future<LeadPage> getMyLeads({String? status, int page = 1, int limit = 20}) async {
    try {
      final response = await _dio.get('/api/leads', queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
        'limit': limit,
      });
      final data = response.data as Map<String, dynamic>;
      final list = data['leads'] as List<dynamic>? ?? [];
      return LeadPage(
        items: list.map((e) => Lead.fromJson(e as Map<String, dynamic>)).toList(),
        counts: LeadCounts.fromJson((data['counts'] as Map<String, dynamic>?) ?? {}),
        total: (data['total'] as num?)?.toInt() ?? list.length,
        hasMore: data['has_more'] as bool? ?? false,
      );
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Lead> updateStatus(String leadId, String status) async {
    try {
      final response = await _dio.patch('/api/leads/$leadId/status', data: {'status': status});
      return Lead.fromJson(response.data['lead'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}