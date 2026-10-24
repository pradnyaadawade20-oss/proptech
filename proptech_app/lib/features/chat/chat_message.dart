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

/// One call (audio) with the other person, shown inside the chat thread
/// like WhatsApp's "Voice call" rows. Comes from GET /api/calls?peer_id=.
class ChatCall {
  final String id;
  final bool isOutgoing;

  /// ringing | active | ended | rejected | missed
  final String status;
  final DateTime createdAt;
  final int durationSec;

  const ChatCall({
    required this.id,
    required this.isOutgoing,
    required this.status,
    required this.createdAt,
    this.durationSec = 0,
  });

  factory ChatCall.fromJson(Map<String, dynamic> json) {
    return ChatCall(
      id: json['id'] as String,
      isOutgoing: (json['direction'] as String?) == 'outgoing',
      status: json['status'] as String? ?? 'ended',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      durationSec: (json['duration_sec'] as num?)?.toInt() ?? 0,
    );
  }

  /// Calls still ringing / in progress are not history yet.
  bool get isFinished => status != 'ringing' && status != 'active';

  /// Missed (incoming, nobody picked up) or declined by the other side.
  bool get isMissed => status == 'missed' || status == 'rejected';

  String get title {
    if (isOutgoing) {
      if (status == 'missed') return 'No answer';
      if (status == 'rejected') return 'Call declined';
      return 'Outgoing voice call';
    }
    if (status == 'missed') return 'Missed voice call';
    if (status == 'rejected') return 'Declined voice call';
    return 'Incoming voice call';
  }

  /// "2:05" / "1:02:07", or empty when the call was never answered.
  String get durationLabel {
    if (durationSec <= 0) return '';
    final h = durationSec ~/ 3600;
    final m = (durationSec % 3600) ~/ 60;
    final s = durationSec % 60;
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }
}