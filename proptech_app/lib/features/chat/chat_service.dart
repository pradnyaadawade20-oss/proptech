import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';
import 'chat_message.dart';

/// Talks to /api/messages/*. The backend identifies the current user via
/// a `user_id` query param for now, so we read it from [TokenStore].
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final Dio _dio = ApiClient.instance.dio;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Exception _toException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(message);
  }

  Future<String> currentUserId() async {
    final id = await TokenStore.instance.getUserId();
    if (id == null || id.isEmpty) {
      throw Exception('Please log in again.');
    }
    return id;
  }

  /// Chat list: one row per person the user has exchanged messages with.
  Future<List<ChatConversation>> getConversations() async {
    final userId = await currentUserId();
    try {
      final response = await _dio.get(
        '/api/messages/conversations',
        queryParameters: {'user_id': userId},
      );
      final list = response.data['conversations'] as List<dynamic>? ?? [];
      return list
          .map((e) => ChatConversation.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Full message history with [otherUserId], oldest first.
  Future<List<ChatMessage>> getThread(String otherUserId) async {
    final userId = await currentUserId();
    try {
      final response = await _dio.get(
        '/api/messages/thread',
        queryParameters: {'user_id': userId, 'other_user_id': otherUserId},
      );
      final list = response.data['messages'] as List<dynamic>? ?? [];
      return list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<ChatMessage> send({
    required String receiverId,
    required String text,
    String? propertyId,
  }) async {
    final userId = await currentUserId();
    try {
      final response = await _dio.post('/api/messages', data: {
        'sender_id': userId,
        'receiver_id': receiverId,
        'text': text,
        // Only link a property when it's a real backend id (UUID).
        if (propertyId != null && _uuid.hasMatch(propertyId)) 'property_id': propertyId,
      });
      return ChatMessage.fromJson(response.data['message'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Marks everything [otherUserId] sent to the current user as read.
  Future<void> markRead(String otherUserId) async {
    final userId = await currentUserId();
    try {
      await _dio.post(
        '/api/messages/read',
        queryParameters: {'user_id': userId, 'other_user_id': otherUserId},
      );
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}