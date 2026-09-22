import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// Thumbnail card for a property's video tour. Tapping opens [videoUrl]
/// in an external player (browser/YouTube app etc.) via url_launcher,
/// which the project already depends on — keeps this widget dependency-free
/// rather than pulling in a video player package just for this card.
class VideoTourCard extends StatelessWidget {
  final String videoUrl;
  final String thumbnailUrl;

  const VideoTourCard({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
  });

  Future<void> _openVideo() async {
    final uri = Uri.tryParse(videoUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openVideo,
      child: Container(
        height: 170,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: thumbnailUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.divider),
              errorWidget: (_, __, ___) => Container(color: AppColors.divider),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25)),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow, color: AppColors.primary, size: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}