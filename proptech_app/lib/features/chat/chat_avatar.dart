import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Profile photo, or the person's initial when they have no avatar set.
/// Photo is center-cropped into a perfect circle.
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
    final d = radius * 2;
    final fallback = Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      color: AppColors.primary.withValues(alpha: 0.12),
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.75,
        ),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: d,
        height: d,
        child: avatarUrl.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: avatarUrl,
                width: d,
                height: d,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                memCacheWidth: (d * MediaQuery.devicePixelRatioOf(context)).round(),
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}