import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
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

  /// Uploads a new profile photo. Returns the profile with the new avatarUrl.
  Future<UserProfile> uploadAvatar({
    required String userId,
    required XFile file,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final form = FormData.fromMap({
        'avatar': MultipartFile.fromBytes(
          bytes,
          filename: file.name.isEmpty ? 'avatar.jpg' : file.name,
        ),
      });
      final response = await _dio.post(
        '/api/profile/$userId/avatar',
        data: form,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      return UserProfile.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<UserProfile> removeAvatar(String userId) async {
    try {
      final response = await _dio.delete('/api/profile/$userId/avatar');
      return UserProfile.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}