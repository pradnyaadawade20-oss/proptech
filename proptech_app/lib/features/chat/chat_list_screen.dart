import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'chat_avatar.dart';
import 'chat_message.dart';
import 'chat_service.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatConversation> _conversations = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;
  bool _wasActive = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Light polling so new messages show up without a manual refresh.
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  // The bottom-nav keeps this screen alive while other tabs are open, so
  // refresh the moment the Messages tab becomes visible again. Inactive
  // tabs have TickerMode turned off, which is how we detect the switch.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.of(context);
    if (active && !_wasActive) _load(silent: true);
    _wasActive = active;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final data = await ChatService.instance.getConversations();
      if (!mounted) return;
      setState(() {
        _conversations = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return; // keep showing the old list on a silent failure
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openChat(ChatConversation convo) async {
    await context.push('/chats/${convo.id}');
    if (mounted) _load(silent: true); // unread counts changed while inside the thread
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    // ListView (even when empty) so pull-to-refresh always works.
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _conversations.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                const Center(child: Text('No conversations yet')),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: _conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final convo = _conversations[index];
                return ListTile(
                  onTap: () => _openChat(convo),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  leading: ChatAvatar(name: convo.name, avatarUrl: convo.avatarUrl),
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
                      Text(formatChatTime(convo.lastMessageTime), style: AppTextStyles.caption),
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