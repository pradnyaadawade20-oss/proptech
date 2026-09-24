import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';

class UserProfile {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String avatarUrl;
  final DateTime? createdAt;

  const UserProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.avatarUrl,
    this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
    );
  }
}

/// Talks to /api/profile/:id.
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _toException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(message);
  }

  Future<UserProfile> getProfile(String userId) async {
    try {
      final response = await _dio.get('/api/profile/$userId');
      return UserProfile.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Profile of the logged-in user.
  Future<UserProfile> getMyProfile() async {
    final userId = await TokenStore.instance.getUserId();
    if (userId == null || userId.isEmpty) {
      throw Exception('Please log in again.');
    }
    return getProfile(userId);
  }

  /// Note: the backend overwrites avatar_url with whatever is sent (an
  /// empty string clears it), so always pass the current [avatarUrl] back.
  Future<UserProfile> updateProfile({
    required String userId,
    required String name,
    required String email,
    required String avatarUrl,
  }) async {
    try {
      final response = await _dio.put('/api/profile/$userId', data: {
        'name': name,
        'email': email,
        'avatar_url': avatarUrl,
      });
      return UserProfile.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}
