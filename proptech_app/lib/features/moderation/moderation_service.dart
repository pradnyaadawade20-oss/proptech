import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';

/// Approval state of one of the logged-in user's own listings.
class ListingModeration {
  final String status; // pending | approved | rejected
  final String reason;
  const ListingModeration(this.status, this.reason);

  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
}

class DuplicateListing {
  final String id;
  final String title;
  final String location;
  final bool sameOwner;
  const DuplicateListing({
    required this.id,
    required this.title,
    required this.location,
    required this.sameOwner,
  });

  factory DuplicateListing.fromJson(Map<String, dynamic> j) => DuplicateListing(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        location: j['location']?.toString() ?? '',
        sameOwner: j['same_owner'] == true,
      );
}

class DuplicateCheck {
  final bool hasDuplicates;
  final bool blocked; // same owner already listed it
  final List<DuplicateListing> duplicates;
  const DuplicateCheck({this.hasDuplicates = false, this.blocked = false, this.duplicates = const []});
}

/// (value sent to the API, label shown to the user)
const List<(String, String)> reportReasons = [
  ('fake_listing', 'Fake listing'),
  ('wrong_info', 'Wrong information'),
  ('already_rented_sold', 'Already rented / sold'),
  ('duplicate', 'Duplicate listing'),
  ('spam', 'Spam'),
  ('inappropriate', 'Inappropriate content'),
  ('other', 'Other'),
];

/// Step 3: approval status, duplicate check and report listing.
class ModerationService {
  ModerationService._();
  static final ModerationService instance = ModerationService._();

  final Dio _dio = ApiClient.instance.dio;

  /// property id -> approval state, for the logged-in user's own listings.
  final ValueNotifier<Map<String, ListingModeration>> statuses = ValueNotifier({});

  Exception _toException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(message);
  }

  Future<void> refresh() async {
    try {
      final r = await _dio.get('/api/properties/my-moderation');
      final list = (r.data['items'] as List<dynamic>? ?? []);
      statuses.value = {
        for (final e in list)
          (e as Map<String, dynamic>)['property_id'].toString(): ListingModeration(
            e['approval_status']?.toString() ?? 'approved',
            e['rejection_reason']?.toString() ?? '',
          ),
      };
    } on DioException {
      // Keep whatever we had; the badge is informational only.
    }
  }

  /// Asked before submitting a new listing. A network failure returns "no
  /// duplicates" so posting is never blocked by this check (the server checks
  /// again on create).
  Future<DuplicateCheck> checkDuplicate({
    required String category,
    required String bhk,
    required double area,
    required int floorNumber,
    required String society,
    required String locality,
    required String city,
    required String pincode,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final r = await _dio.post('/api/properties/check-duplicate', data: {
        'category': category,
        'bhk': bhk,
        'area': area,
        'floor_number': floorNumber,
        'society': society,
        'locality': locality,
        'city': city,
        'pincode': pincode,
        'latitude': latitude,
        'longitude': longitude,
      });
      final d = r.data as Map<String, dynamic>;
      return DuplicateCheck(
        hasDuplicates: d['has_duplicates'] == true,
        blocked: d['blocked'] == true,
        duplicates: (d['duplicates'] as List<dynamic>? ?? [])
            .map((e) => DuplicateListing.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on DioException {
      return const DuplicateCheck();
    }
  }

  Future<void> report({required String propertyId, required String reason, String details = ''}) async {
    try {
      await _dio.post('/api/properties/$propertyId/report', data: {
        'reason': reason,
        'details': details.trim(),
      });
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}