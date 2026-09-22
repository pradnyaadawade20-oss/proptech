import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';

/// One room's 360° panorama + its regular listing photos.
///
/// [panoramaUrl] must be a real equirectangular (2:1, spherical) image —
/// exactly the kind of file the phone's "Panorama"/"Photo Sphere" camera
/// mode produces (like the capture shown in the reference video). Dragging
/// over it pans a real camera around the room, the same way Google Street
/// View / a Photo Sphere viewer works — this is not a simulated rotation.
///
/// [images] are ordinary photos of that room (used for the thumbnail and
/// the photo strip under the panorama) and are unrelated to the 360 sphere.
///
/// NOTE: the panorama URLs below are real, license-clean (CC0, Poly Haven)
/// equirectangular indoor photos — a hotel bedroom, a lounge, a kitchen,
/// a bathroom, etc. — chosen to *look like* the correct room type, but
/// they are still generic stock scenes, not photos of these specific
/// properties. Swap each [panoramaUrl] for the property's actual Photo
/// Sphere capture of that room (the .jpg saved after using the phone's
/// Panorama mode, same as in the reference video) as soon as those are
/// available — no other code needs to change.
class RoomData {
  final String label;
  final IconData icon;
  final String panoramaUrl; // equirectangular 360° image for this room
  final List<String> images; // regular photos of this room

  const RoomData({
    required this.label,
    required this.icon,
    required this.panoramaUrl,
    required this.images,
  });
}

/// Generic room photo sets — reused across all dummy properties.
/// Replace with per-property, per-room images/panoramas once real capture
/// data is available.
const List<RoomData> defaultRooms = [
  RoomData(
    label: 'Hall',
    icon: Icons.weekend_outlined,
    panoramaUrl: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lebombo.jpg',
    images: [
      'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
      'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267',
      'https://images.unsplash.com/photo-1567016432779-094069958ea5',
      'https://images.unsplash.com/photo-1583847268964-b28dc8f51f92',
    ],
  ),
  RoomData(
    label: 'Living Room',
    icon: Icons.chair_outlined,
    panoramaUrl: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/wooden_lounge.jpg',
    images: [
      'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2',
      'https://images.unsplash.com/photo-1512918728675-ed5a9ecdebfd',
      'https://images.unsplash.com/photo-1591079103656-c81c1e5a8b56',
      'https://images.unsplash.com/photo-1550581190-9c1c48d21d6c',
    ],
  ),
  RoomData(
    label: 'Bedroom',
    icon: Icons.bed_outlined,
    panoramaUrl: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/hotel_room.jpg',
    images: [
      'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85',
      'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af',
      'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf',
      'https://images.unsplash.com/photo-1560185893-a55cbc8c57e8',
    ],
  ),
  RoomData(
    label: 'Kitchen',
    icon: Icons.kitchen_outlined,
    panoramaUrl: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/kiara_interior.jpg',
    images: [
      'https://images.unsplash.com/photo-1556911220-e15b29be8c8f',
      'https://images.unsplash.com/photo-1600585154340-be6161a56a0c',
      'https://images.unsplash.com/photo-1556909212-d5b604d0c90d',
      'https://images.unsplash.com/photo-1571877227200-a0d98ea607e9',
    ],
  ),
  RoomData(
    label: 'Washroom',
    icon: Icons.bathtub_outlined,
    panoramaUrl: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/bathroom.jpg',
    images: [
      'https://images.unsplash.com/photo-1584622650111-993a426fbf0a',
      'https://images.unsplash.com/photo-1620626011761-996317b8d101',
      'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14',
      'https://images.unsplash.com/photo-1600566752355-35792bedcfea',
    ],
  ),
];

/// Inline preview card shown on the detail screen — tapping opens the
/// full-screen 360° viewer.
class Room360Preview extends StatelessWidget {
  final List<RoomData> rooms;
  const Room360Preview({super.key, this.rooms = defaultRooms});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Room360FullScreen(rooms: rooms),
          ),
        );
      },
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
              imageUrl: '${rooms.first.images.first}?w=800&q=70&fit=crop&auto=format',
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.divider),
              errorWidget: (_, __, ___) => Container(color: AppColors.divider),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.55)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 14,
              right: 14,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.threesixty, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Explore in 360° — Hall, Living Room, Bedroom, Kitchen, Washroom',
                      style: AppTextStyles.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen 360° room viewer. Renders each room's real equirectangular
/// panorama with drag-to-look-around (and device-tilt, where supported) —
/// the same interaction as the phone's Panorama/Photo Sphere capture.
/// Tabs switch rooms; a photo strip below shows that room's regular photos.
class Room360FullScreen extends StatefulWidget {
  final List<RoomData> rooms;
  const Room360FullScreen({super.key, this.rooms = defaultRooms});

  @override
  State<Room360FullScreen> createState() => _Room360FullScreenState();
}

class _Room360FullScreenState extends State<Room360FullScreen> {
  int _roomIndex = 0;

  RoomData get _room => widget.rooms[_roomIndex];

  void _selectRoom(int index) {
    if (index == _roomIndex) return;
    setState(() => _roomIndex = index);
  }

  void _openPhoto(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: '$url?w=1400&q=85&fit=crop&auto=format', fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Real 360° sphere — drag horizontally/vertically to look around,
          // pinch to zoom. IMPORTANT: this widget is never given a
          // room-based key and is never removed from the tree when the
          // room changes — only its `child` image swaps. Rebuilding it via
          // a changing key (e.g. ValueKey(_roomIndex)) forces the framework
          // to fully dispose and recreate the underlying GL scene, which is
          // what causes the '_dependents.isEmpty' assertion crash on room
          // switch. Swapping just the child lets PanoramaViewer update the
          // texture in place instead.
          Positioned.fill(
            child: PanoramaViewer(
              animSpeed: 0,
              sensorControl: SensorControl.orientation,
              child: Image(
                image: CachedNetworkImageProvider(_room.panoramaUrl),
              ),
            ),
          ),

          // Top gradient + back button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 20, color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${_room.label} · 360° view',
                      style: AppTextStyles.h3.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                ],
              ),
            ),
          ),

          // Drag-to-look-around hint (fades away — doesn't block dragging).
          IgnorePointer(
            child: TweenAnimationBuilder<double>(
              key: ValueKey('hint_$_roomIndex'),
              tween: Tween(begin: 1.0, end: 0.0),
              duration: const Duration(milliseconds: 2200),
              curve: const Interval(0.5, 1.0),
              builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swipe, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Drag to look around', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom: room tabs + this room's regular photos
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + AppSpacing.md, top: AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // this room's regular photos
                  SizedBox(
                    height: 56,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      itemCount: _room.images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final url = _room.images[i];
                        return GestureDetector(
                          onTap: () => _openPhoto(url),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: '$url?w=200&q=70&fit=crop&auto=format',
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: Colors.white12),
                              errorWidget: (_, __, ___) => Container(color: Colors.white12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // room tabs
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      itemCount: widget.rooms.length,
                      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final room = widget.rooms[index];
                        final selected = index == _roomIndex;
                        return GestureDetector(
                          onTap: () => _selectRoom(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                              border: Border.all(
                                color: selected ? AppColors.primary : Colors.white38,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(room.icon, size: 16, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  room.label,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}