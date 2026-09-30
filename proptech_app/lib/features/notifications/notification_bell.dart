import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import 'notification_service.dart';

/// Bell icon for the app bar with an unread-count badge.
/// Tap opens the notifications screen.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  @override
  void initState() {
    super.initState();
    NotificationService.instance.refreshUnread();
  }

  Future<void> _open() async {
    await context.push(RouteNames.notifications);
    NotificationService.instance.refreshUnread();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.instance.unread,
      builder: (context, count, _) {
        return IconButton(
          onPressed: _open,
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: Icon(count > 0 ? Icons.notifications : Icons.notifications_none),
          ),
        );
      },
    );
  }
}