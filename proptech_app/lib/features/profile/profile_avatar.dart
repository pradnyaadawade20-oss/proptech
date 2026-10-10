import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Circular profile photo with a gradient initial fallback, white ring and an
/// optional camera badge. The photo is always center-cropped to a perfect
/// circle (BoxFit.cover inside a square ClipOval), whatever its aspect ratio.
class ProfileAvatar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final double size;
  final bool uploading;
  final bool showCameraBadge;
  final VoidCallback? onTap;

  const ProfileAvatar({
    super.key,
    required this.name,
    required this.avatarUrl,
    this.size = 72,
    this.uploading = false,
    this.showCameraBadge = true,
    this.onTap,
  });

  static const LinearGradient _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B6CFF), Color(0xFF14E0B0)],
  );

  Widget _initial(double d) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: _gradient),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: d * 0.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const ring = 3.0;
    final inner = size - ring * 2;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    final Widget photo = avatarUrl.isEmpty
        ? _initial(inner)
        : CachedNetworkImage(
            imageUrl: avatarUrl,
            width: inner,
            height: inner,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            memCacheWidth: (inner * dpr).round(),
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, __) => _initial(inner),
            errorWidget: (_, __, ___) => _initial(inner),
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: uploading ? null : onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(ring),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: SizedBox(
                  width: inner,
                  height: inner,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      photo,
                      if (uploading)
                        Container(
                          color: Colors.black.withValues(alpha: 0.45),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (showCameraBadge && onTap != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2F6BFF),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.photo_camera_rounded,
                      size: 13, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}