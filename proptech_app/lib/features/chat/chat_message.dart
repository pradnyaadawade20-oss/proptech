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
}

class ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isMe,
    required this.sentAt,
  });
}

final List<ChatConversation> dummyConversations = [
  ChatConversation(
    id: '1',
    name: 'Rahul Sharma',
    avatarUrl: 'https://i.pravatar.cc/150?img=12',
    lastMessage: 'Is the property still available?',
    lastMessageTime: DateTime.now().subtract(const Duration(minutes: 10)),
    unreadCount: 2,
  ),
  ChatConversation(
    id: '2',
    name: 'Priya Verma',
    avatarUrl: 'https://i.pravatar.cc/150?img=32',
    lastMessage: 'Thanks, see you at the visit!',
    lastMessageTime: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  ChatConversation(
    id: '3',
    name: 'Aman Gupta',
    avatarUrl: 'https://i.pravatar.cc/150?img=51',
    lastMessage: 'Can we reschedule to next week?',
    lastMessageTime: DateTime.now().subtract(const Duration(days: 1)),
  ),
];

final Map<String, List<ChatMessage>> dummyMessages = {
  '1': [
    ChatMessage(id: 'm1', text: 'Hi, I saw your listing for the 2 BHK.', isMe: false, sentAt: DateTime.now().subtract(const Duration(minutes: 20))),
    ChatMessage(id: 'm2', text: 'Yes, it is still available!', isMe: true, sentAt: DateTime.now().subtract(const Duration(minutes: 18))),
    ChatMessage(id: 'm3', text: 'Is the property still available?', isMe: false, sentAt: DateTime.now().subtract(const Duration(minutes: 10))),
  ],
  '2': [
    ChatMessage(id: 'm1', text: 'Visit confirmed for tomorrow 5 PM.', isMe: true, sentAt: DateTime.now().subtract(const Duration(hours: 4))),
    ChatMessage(id: 'm2', text: 'Thanks, see you at the visit!', isMe: false, sentAt: DateTime.now().subtract(const Duration(hours: 3))),
  ],
  '3': [
    ChatMessage(id: 'm1', text: 'Can we reschedule to next week?', isMe: false, sentAt: DateTime.now().subtract(const Duration(days: 1))),
  ],
};