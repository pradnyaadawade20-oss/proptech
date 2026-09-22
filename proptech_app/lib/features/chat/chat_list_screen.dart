import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'chat_message.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final conversations = dummyConversations;

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: conversations.isEmpty
          ? const Center(child: Text('No conversations yet'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final convo = conversations[index];
                return ListTile(
                  onTap: () => context.push('/chats/${convo.id}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundImage: NetworkImage(convo.avatarUrl),
                  ),
                  title: Text(convo.name, style: AppTextStyles.h3.copyWith(fontSize: 15)),
                  subtitle: Text(
                    convo.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall,
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${convo.lastMessageTime.hour}:${convo.lastMessageTime.minute.toString().padLeft(2, '0')}',
                        style: AppTextStyles.caption,
                      ),
                      if (convo.unreadCount > 0) ...[
                        const SizedBox(height: 4),
                        CircleAvatar(
                          radius: 9,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            '${convo.unreadCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}