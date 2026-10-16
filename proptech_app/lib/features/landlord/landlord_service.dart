import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../properties/property.dart';

/// A broker's invitation to the real owner of a listing.
class LandlordInvite {
  final String id;
  final String propertyId;
  final String propertyTitle;
  final String brokerId;
  final String brokerName;
  final String shareUrl; // the link to send the owner; only filled for the broker who created it
  final String landlordName;
  final String landlordPhone;
  final String landlordEmail;
  final String landlordUserName; // real account name once accepted
  final String status; // pending | accepted | declined | cancelled | expired
  final DateTime? expiresAt;

  const LandlordInvite({
    required this.id,
    required this.propertyId,
    required this.propertyTitle,
    required this.brokerId,
    required this.brokerName,
    required this.shareUrl,
    required this.landlordName,
    required this.landlordPhone,
    required this.landlordEmail,
    required this.landlordUserName,
    required this.status,
    this.expiresAt,
  });

  factory LandlordInvite.fromJson(Map<String, dynamic> j) => LandlordInvite(
        id: j['id'] as String,
        propertyId: j['property_id'] as String? ?? '',
        propertyTitle: j['property_title'] as String? ?? '',
        brokerId: j['broker_id'] as String? ?? '',
        brokerName: j['broker_name'] as String? ?? '',
        shareUrl: j['share_url'] as String? ?? '',
        landlordName: j['landlord_name'] as String? ?? '',
        landlordPhone: j['landlord_phone'] as String? ?? '',
        landlordEmail: j['landlord_email'] as String? ?? '',
        landlordUserName: j['landlord_user_name'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        expiresAt: DateTime.tryParse(j['expires_at'] as String? ?? '')?.toLocal(),
      );

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
}

/// What the owner sees after opening the share link: the invitation and the full listing.
class InviteView {
  final LandlordInvite invite;
  final Property property;
  const InviteView(this.invite, this.property);
}

/// Server error with the machine-readable `code` (kyc_required / upi_required / ...).
class LandlordApiException implements Exception {
  final String message;
  final String? code;
  const LandlordApiException(this.message, [this.code]);

  @override
  String toString() => message;
}

/// Broker -> real-owner linking. Talks to /api/properties/:id/landlord-invite and /api/landlord-invites/*.
class LandlordService {
  LandlordService._();
  static final LandlordService instance = LandlordService._();

  final Dio _dio = ApiClient.instance.dio;

  LandlordApiException _toException(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return LandlordApiException(data['error'].toString(), data['code']?.toString());
    }
    return LandlordApiException(e.message ?? 'Something went wrong. Please try again.');
  }

  // ---- broker side ----

  Future<LandlordInvite?> getPropertyInvite(String propertyId) async {
    try {
      final r = await _dio.get('/api/properties/$propertyId/landlord-invite');
      final inv = r.data['invite'];
      return inv == null ? null : LandlordInvite.fromJson(inv as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<LandlordInvite> createInvite(String propertyId, {required String name, String phone = '', String email = ''}) async {
    try {
      final r = await _dio.post('/api/properties/$propertyId/landlord-invite', data: {
        'name': name,
        'phone': phone,
        'email': email,
      });
      return LandlordInvite.fromJson(r.data['invite'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<void> cancelInvite(String propertyId) async {
    try {
      await _dio.delete('/api/properties/$propertyId/landlord-invite');
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  // ---- owner side ----

  Future<List<LandlordInvite>> myInvites() async {
    try {
      final r = await _dio.get('/api/landlord-invites/mine');
      final list = (r.data['invites'] as List?) ?? const [];
      return list.map((e) => LandlordInvite.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Owner opened the share link (logged in): fetch the invitation + listing to review.
  Future<InviteView> byToken(String token) async {
    try {
      final r = await _dio.get('/api/landlord-invites/by-token/${Uri.encodeComponent(token.trim())}');
      final data = r.data as Map<String, dynamic>;
      return InviteView(
        LandlordInvite.fromJson(data['invite'] as Map<String, dynamic>),
        Property.fromJson(data['property'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// APPROVE. Pass the link token (opened from the share link) or the invite id (invite listed for my email/phone).
  /// The listing goes live for tenants only after this succeeds.
  Future<LandlordInvite> accept({String? inviteId, String? token}) async {
    try {
      final r = await _dio.post('/api/landlord-invites/accept', data: {
        if (inviteId != null) 'invite_id': inviteId,
        if (token != null) 'token': token,
      });
      return LandlordInvite.fromJson(r.data['invite'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<void> decline({String? inviteId, String? token}) async {
    try {
      await _dio.post('/api/landlord-invites/decline', data: {
        if (inviteId != null) 'invite_id': inviteId,
        if (token != null) 'token': token,
      });
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  // ---- tenant side ----

  /// Can tenants request an agreement on this listing? (Broker listings: only after the owner is linked.)
  Future<bool> agreementAvailable(String propertyId) async {
    try {
      final r = await _dio.get('/api/properties/$propertyId/agreement-eligibility');
      return r.data['available'] == true;
    } on DioException {
      return false;
    }
  }
}