/// One row on the chat list screen. [id] is the OTHER user's id — the
/// backend returns one conversation per person you've exchanged messages
/// with, so the same id is used to open the thread (`/chats/:id`).
class ChatConversation {
  final String id;
  final String name;
  final String avatarUrl;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;

  const ChatConversation({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    return ChatConversation(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Unknown user',
      avatarUrl: json['avatar_url'] as String? ?? '',
      lastMessage: json['last_message'] as String? ?? '',
      lastMessageTime:
          DateTime.tryParse(json['last_message_time'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final DateTime sentAt;

  /// True once the other person has opened the chat (blue double tick).
  final bool isRead;

  /// True while a message you just typed is still being sent (clock icon).
  final bool isPending;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isMe,
    required this.sentAt,
    this.isRead = false,
    this.isPending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      isMe: json['is_me'] as bool? ?? false,
      isRead: json['is_read'] as bool? ?? false,
      sentAt: DateTime.tryParse(json['sent_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

/// "11:04" for today, "Yesterday" for yesterday, otherwise "24/09".
String formatChatTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;

  if (diff <= 0) {
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
  if (diff == 1) return 'Yesterday';
  return '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
}


/// "09:41" — time shown inside a message bubble.
String formatBubbleTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// "Today", "Yesterday" or "24 Sep 2026" — date separator in a thread.
String formatDateLabel(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${day.day} ${months[day.month - 1]} ${day.year}';
}