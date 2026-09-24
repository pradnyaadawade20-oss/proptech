import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Profile photo, or the person's initial when they have no avatar set.
class ChatAvatar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final double radius;

  const ChatAvatar({
    super.key,
    required this.name,
    required this.avatarUrl,
    this.radius = 26,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final fallback = Text(
      initial,
      style: TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
        fontSize: radius * 0.75,
      ),
    );

    if (avatarUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        child: fallback,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      backgroundImage: NetworkImage(avatarUrl),
      onBackgroundImageError: (_, __) {},
    );
  }
}