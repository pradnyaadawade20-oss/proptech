import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../profile/profile_service.dart';
import 'chat_avatar.dart';
import 'chat_message.dart';
import 'chat_service.dart';

/// [chatId] is the OTHER user's id. [propertyId] (optional) links the
/// messages sent from here to the listing the person was looking at.
class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String? propertyId;
  const ChatDetailScreen({super.key, required this.chatId, this.propertyId});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  static const Color _myBubble = Color(0xFFDDF0E8);
  static const Color _readTick = Color(0xFF34B7F1);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<ChatMessage> _messages = [];
  UserProfile? _other;
  bool _loading = true;
  bool _hasText = false;
  int _pendingCount = 0; // messages currently being sent
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _loadOtherUser();
    _loadThread();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _loadThread(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadOtherUser() async {
    try {
      final profile = await ProfileService.instance.getProfile(widget.chatId);
      if (mounted) setState(() => _other = profile);
    } catch (_) {
      // Header just falls back to a generic title.
    }
  }

  Future<void> _loadThread({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final data = await ChatService.instance.getThread(widget.chatId);
      if (!mounted) return;
      // Don't overwrite the list while a message is mid-send; the next poll will sync.
      if (_pendingCount > 0) return;

      final previousCount = _messages.length;
      final hasIncoming = data.any((m) => !m.isMe);
      setState(() {
        _messages = data;
        _loading = false;
        _error = null;
      });

      if (data.length != previousCount) {
        _scrollToBottom(jump: previousCount == 0);
        if (hasIncoming) {
          ChatService.instance.markRead(widget.chatId).catchError((_) {});
        }
      }
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(max);
      } else {
        _scroll.animateTo(max, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  /// WhatsApp-style: the bubble appears instantly with a clock icon, then
  /// becomes a tick once the server confirms it. On failure it's removed
  /// and the text is put back in the box.
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final temp = ChatMessage(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      isMe: true,
      sentAt: DateTime.now(),
      isPending: true,
    );

    setState(() {
      _messages = [..._messages, temp];
      _pendingCount++;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final sent = await ChatService.instance.send(
        receiverId: widget.chatId,
        text: text,
        propertyId: widget.propertyId,
      );
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((m) => m.id == temp.id ? sent : m).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((m) => m.id != temp.id).toList();
        if (_controller.text.isEmpty) _controller.text = text;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _pendingCount--);
    }
  }

  Future<void> _callOther() async {
    final phone = _other?.phone ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available.')),
      );
      return;
    }
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final launched = await launchUrl(Uri(scheme: 'tel', path: clean));
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dialer for $phone')),
      );
    }
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final other = _other;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: other == null
            ? const Text('Chat')
            : Row(
                children: [
                  ChatAvatar(name: other.name, avatarUrl: other.avatarUrl, radius: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          other.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h3.copyWith(fontSize: 16),
                        ),
                        if (other.phone.isNotEmpty)
                          Text(other.phone, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call_outlined),
            onPressed: _callOther,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 6, AppSpacing.sm, AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: _hasText ? AppColors.primary : AppColors.primary.withValues(alpha: 0.4),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _hasText ? _send : null,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.send, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
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
              OutlinedButton(onPressed: _loadThread, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(child: Text('Say hi 👋', style: AppTextStyles.bodyMedium));
    }

    // Interleave date separators ("Today", "Yesterday"...) between days.
    final items = <Object>[];
    DateTime? lastDay;
    for (final m in _messages) {
      final day = DateTime(m.sentAt.year, m.sentAt.month, m.sentAt.day);
      if (lastDay == null || day != lastDay) {
        items.add(day);
        lastDay = day;
      }
      items.add(m);
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is DateTime) return _DateChip(label: formatDateLabel(item));
        return _buildBubble(item as ChatMessage);
      },
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isMe = msg.isMe;
    const big = Radius.circular(14);
    const small = Radius.circular(3);

    Widget tick = const SizedBox.shrink();
    if (isMe) {
      if (msg.isPending) {
        tick = const Icon(Icons.access_time, size: 13, color: Colors.grey);
      } else if (msg.isRead) {
        tick = const Icon(Icons.done_all, size: 16, color: _readTick);
      } else {
        tick = const Icon(Icons.done, size: 16, color: Colors.grey);
      }
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _copyMessage(msg.text),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isMe ? _myBubble : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: big,
              topRight: big,
              bottomLeft: isMe ? big : small,
              bottomRight: isMe ? small : big,
            ),
            border: isMe ? null : Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  msg.text,
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatBubbleTime(msg.sentAt),
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  if (isMe) ...[const SizedBox(width: 3), tick],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  const _DateChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ),
    );
  }
}