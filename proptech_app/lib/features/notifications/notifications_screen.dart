import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import 'notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = [];
  bool _loading = true;
  String? _error;

  static const _tabRoutes = {
    RouteNames.home,
    RouteNames.search,
    RouteNames.favorites,
    RouteNames.chatList,
    RouteNames.profile,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await NotificationService.instance.getAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load notifications.';
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      await NotificationService.instance.markAllRead();
      if (!mounted) return;
      setState(() => _items = _items.map((n) => n.copyWith(isRead: true)).toList());
    } catch (_) {}
  }

  /// Route stored with the notification; older rows fall back to their type.
  String? _routeFor(AppNotification n) {
    if (n.route.startsWith('/')) return n.route;
    switch (n.type) {
      case 'message':
        return RouteNames.chatList;
      case 'visit':
        return RouteNames.myVisits;
    }
    return null;
  }

  Future<void> _onTap(AppNotification n) async {
    if (!n.isRead) {
      setState(() {
        _items = _items.map((x) => x.id == n.id ? x.copyWith(isRead: true) : x).toList();
      });
      final left = _items.where((x) => !x.isRead).length;
      NotificationService.instance.unread.value = left;
      NotificationService.instance.markRead(n.id).catchError((_) {});
    }
    final route = _routeFor(n);
    if (route == null || !mounted) return;
    if (_tabRoutes.contains(route)) {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  Future<void> _delete(AppNotification n) async {
    setState(() => _items = _items.where((x) => x.id != n.id).toList());
    NotificationService.instance.unread.value = _items.where((x) => !x.isRead).length;
    NotificationService.instance.delete(n.id).catchError((_) {});
  }

  IconData _icon(String type) {
    switch (type) {
      case 'message':
        return Icons.chat_bubble_outline;
      case 'visit':
        return Icons.event_available_outlined;
      case 'agreement':
        return Icons.description_outlined;
      case 'property':
        return Icons.home_work_outlined;
      case 'offer':
        return Icons.local_offer_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => !n.isRead);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Text(
                              _error ?? 'No notifications yet',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = _items[i];
                        return Dismissible(
                          key: ValueKey(n.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red.shade400,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          onDismissed: (_) => _delete(n),
                          child: ListTile(
                            tileColor: n.isRead ? null : AppColors.primaryLight,
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primaryLight,
                              child: Icon(_icon(n.type), color: AppColors.primary),
                            ),
                            title: Text(
                              n.title,
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.body,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodyMedium),
                                  const SizedBox(height: 4),
                                  Text(_ago(n.createdAt),
                                      style: AppTextStyles.caption
                                          .copyWith(color: AppColors.textHint)),
                                ],
                              ),
                            ),
                            isThreeLine: true,
                                                        trailing: n.isRead
                                ? null
                                : Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                            onTap: () => _onTap(n),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}