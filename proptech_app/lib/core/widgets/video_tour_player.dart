import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
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

  bool get _isYoutube {
    final h = Uri.tryParse(videoUrl)?.host.toLowerCase() ?? '';
    return h.contains('youtube.com') || h.contains('youtu.be');
  }

  Future<void> _openVideo(BuildContext context) async {
    // YouTube links can't be played by video_player, so only those go external.
    if (_isYoutube) {
      final uri = Uri.tryParse(videoUrl);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoTourScreen(videoUrl: videoUrl)));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openVideo(context),
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 4),
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
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.30)),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.black87, size: 32),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_outlined, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Watch Property Tour', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen in-app player (play/pause, seek bar, fullscreen toggle).
class VideoTourScreen extends StatefulWidget {
  final String videoUrl;
  const VideoTourScreen({super.key, required this.videoUrl});

  @override
  State<VideoTourScreen> createState() => _VideoTourScreenState();
}

class _VideoTourScreenState extends State<VideoTourScreen> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final v = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _video = v;
      await v.initialize();
      if (!mounted) return;
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: v,
          autoPlay: true,
          looping: false,
          aspectRatio: v.value.aspectRatio,
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.primary,
            handleColor: AppColors.primary,
            bufferedColor: Colors.white38,
            backgroundColor: Colors.white24,
          ),
        );
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Property Tour'),
      ),
      body: Center(
        child: _failed
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Video could not be played.', style: TextStyle(color: Colors.white)),
              )
            : _chewie == null
                ? const CircularProgressIndicator(color: Colors.white)
                : Chewie(controller: _chewie!),
      ),
    );
  }
}