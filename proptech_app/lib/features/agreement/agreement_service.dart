import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import 'agreement.dart';

/// Thrown when the server refuses to sign/send a signing OTP because the
/// user hasn't completed KYC (HTTP 403, code "kyc_required").
class KycRequiredException implements Exception {
  final String message;
  const KycRequiredException(this.message);

  @override
  String toString() => message;
}

/// Talks to /api/agreements/*. Mirrors AgreementRepository on the backend
/// exactly: create -> updateDraft -> sign -> (auto-completes when both
/// parties have signed) / updateStatus for cancel-reject.
class AgreementService {
  AgreementService._();
  static final AgreementService instance = AgreementService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _toException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    if (e.response?.statusCode == 403 && data is Map && data['code'] == 'kyc_required') {
      return KycRequiredException(message);
    }
    return Exception(message);
  }

  /// Step 1: raise a request for an agreement on a property.
  Future<Agreement> create({
    required String propertyId,
    required String ownerId,
    required String tenantId,
  }) async {
    try {
      final response = await _dio.post('/api/agreements', data: {
        'property_id': propertyId,
        'owner_id': ownerId,
        'tenant_id': tenantId,
      });
      return Agreement.fromJson(response.data['agreement'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// All agreements where the given user is either owner or tenant.
  Future<List<Agreement>> getForUser(String userId) async {
    try {
      final response = await _dio.get('/api/agreements', queryParameters: {'user_id': userId});
      final list = response.data['agreements'] as List<dynamic>? ?? [];
      return list.map((e) => Agreement.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Agreement> getById(String id) async {
    try {
      final response = await _dio.get('/api/agreements/$id');
      return Agreement.fromJson(response.data['agreement'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Step 2 (owner only): fill in rent/deposit/terms -> status becomes draft_ready.
  Future<Agreement> updateDraft({
    required String id,
    double? monthlyRent,
    double? securityDeposit,
    String? startDate, // YYYY-MM-DD
    int? durationMonths,
    required String terms,
  }) async {
    try {
      final response = await _dio.put('/api/agreements/$id/draft', data: {
        'monthly_rent': monthlyRent,
        'security_deposit': securityDeposit,
        'start_date': startDate,
        'duration_months': durationMonths,
        'terms': terms,
      });
      return Agreement.fromJson(response.data['agreement'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Step 3: either party signs — draw (base64 PNG) or type (name text).
  /// Needs a verified OTP first (sendSignOtp -> verifySignOtp).
  Future<Agreement> sign({
    required String id,
    required String signerRole, // 'owner' | 'tenant'
    required String signatureType, // 'draw' | 'type'
    required String signatureData,
  }) async {
    try {
      final response = await _dio.post('/api/agreements/$id/sign', data: {
        'signer_role': signerRole,
        'signature_type': signatureType,
        'signature_data': signatureData,
      });
      return Agreement.fromJson(response.data['agreement'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Emails a 6-digit code to the signer. Must be verified before sign().
  Future<void> sendSignOtp({required String id, required String signerRole}) async {
    try {
      await _dio.post('/api/agreements/$id/sign/send-otp', data: {'signer_role': signerRole});
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<void> verifySignOtp({
    required String id,
    required String signerRole,
    required String code,
  }) async {
    try {
      await _dio.post('/api/agreements/$id/sign/verify-otp', data: {
        'signer_role': signerRole,
        'code': code,
      });
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Cancel or reject an agreement.
  Future<Agreement> updateStatus({required String id, required String status}) async {
    try {
      final response = await _dio.patch('/api/agreements/$id/status', data: {'status': status});
      return Agreement.fromJson(response.data['agreement'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}