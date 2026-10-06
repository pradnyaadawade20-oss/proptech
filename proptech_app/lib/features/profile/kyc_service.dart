import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';

/// KYC state as the server reports it. `state` is one of:
/// not_started | pending | verified | rejected
class KycStatus {
  final String state;
  final String? maskedAadhaar; // e.g. "XXXX XXXX 4321"
  final DateTime? verifiedAt;
  const KycStatus({required this.state, this.maskedAadhaar, this.verifiedAt});

  bool get isVerified => state == 'verified';

  factory KycStatus.fromJson(Map<String, dynamic> json) => KycStatus(
        state: json['status'] as String? ?? 'not_started',
        maskedAadhaar: json['masked_aadhaar'] as String?,
        verifiedAt: DateTime.tryParse(json['verified_at'] as String? ?? '')?.toLocal(),
      );
}

/// Error from a /api/kyc call. [code] is the server's machine-readable code
/// (kyc_invalid_otp, kyc_cooldown, kyc_aadhaar_in_use, ...).
class KycException implements Exception {
  final String message;
  final String? code;
  final int? attemptsLeft;
  final int? retryAfterSeconds;
  const KycException(this.message, {this.code, this.attemptsLeft, this.retryAfterSeconds});

  @override
  String toString() => message;
}

/// Talks to /api/kyc/*. The server is the source of truth — nothing about
/// KYC is trusted from local storage.
class KycService {
  KycService._();
  static final KycService instance = KycService._();

  final Dio _dio = ApiClient.instance.dio;

  KycException _toException(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      return KycException(
        data['error']?.toString() ?? 'Something went wrong.',
        code: data['code']?.toString(),
        attemptsLeft: data['attempts_left'] as int?,
        retryAfterSeconds: data['retry_after_seconds'] as int?,
      );
    }
    return KycException(e.message ?? 'Something went wrong.');
  }

  Future<KycStatus> getStatus() async {
    try {
      final r = await _dio.get('/api/kyc/status');
      return KycStatus.fromJson(r.data['kyc'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Sends an OTP to the mobile linked with the Aadhaar.
  /// Returns how many seconds to wait before a resend is allowed.
  Future<int> sendOtp({required String aadhaar, required bool consent}) async {
    try {
      final r = await _dio.post('/api/kyc/aadhaar/send-otp', data: {
        'aadhaar': aadhaar.replaceAll(RegExp(r'\D'), ''),
        'consent': consent,
      });
      return (r.data['resend_after_seconds'] as int?) ?? 30;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<KycStatus> verifyOtp(String otp) async {
    try {
      final r = await _dio.post('/api/kyc/aadhaar/verify-otp', data: {'otp': otp});
      return KycStatus.fromJson(r.data['kyc'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}