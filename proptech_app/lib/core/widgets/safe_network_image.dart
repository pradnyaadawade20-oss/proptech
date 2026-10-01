import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Network image that never throws into the UI: bad/empty/local (file://)
/// URLs and failed loads show a neutral placeholder instead of an error box.
class SafeNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  const SafeNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: AppColors.surfaceSoft,
        alignment: Alignment.center,
        child: const Icon(Icons.home_outlined, size: 28, color: AppColors.textHint),
      );

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return _placeholder();
    return Image.network(
      u,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }
}