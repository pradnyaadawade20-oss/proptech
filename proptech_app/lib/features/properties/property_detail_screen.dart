import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/gallery_viewer_screen.dart';
import '../../core/widgets/video_tour_player.dart';
import '../../core/api/token_store.dart';
import '../profile/profile_service.dart';
import '../visits/visit_service.dart';
import '../leads/lead_service.dart';
import '../moderation/report_listing_sheet.dart';
import '../../app/router/route_names.dart';
import '../compare/compare_store.dart';
import '../reviews/property_reviews_section.dart';
import 'property.dart';
import 'property_store.dart';
import 'recently_viewed_store.dart';
import '../../core/utils/price_format.dart';

class PropertyDetailScreen extends StatefulWidget {
  final String propertyId;
  const PropertyDetailScreen({super.key, required this.propertyId});

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> with PropertyStoreListener<PropertyDetailScreen> {
  final PageController _imagePageController = PageController();
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    // Record this view for the "Recently Viewed" section, after first frame
    // so it doesn't interfere with this screen's own build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RecentlyViewedStore.instance.markViewed(widget.propertyId);
      _ensureLoaded();
    });
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  bool _notFound = false;

  /// Property might not be cached yet (opened from a link / notification).
  Future<void> _ensureLoaded() async {
    if (PropertyStore.instance.byId(widget.propertyId) != null) return;
    final fetched = await PropertyStore.instance.ensure(widget.propertyId);
    if (!mounted) return;
    if (fetched == null) setState(() => _notFound = true);
  }

  void _openGallery(Property property, int initialIndex) {
    Navigator.of(context).push(
      GalleryViewerScreen.route(
        imageUrls: property.galleryImages,
        initialIndex: initialIndex,
      ),
    );
  }

  void _shareProperty(Property property) {
    final price = formatPrice(property.price, property.priceUnit);
    final link = 'https://proptech-ozo0.onrender.com/p/${property.id}';
    Share.share(
      '${property.title}\n$price • ${property.location}\n\n$link',
      subject: property.title,
    );
  }

    void _showVerifiedInfo() {
    Widget row(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, size: 18, color: Color(0xFF0F9D58)),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.verified, color: Color(0xFF0F9D58), size: 36),
        title: const Text('Verified listing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Live photo taken at the property'),
            row('Phone location captured with the photo'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }


  void _toggleCompare(Property property) {
    final store = CompareStore.instance;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (!store.contains(property.id) && store.count >= CompareStore.maxItems) {
      messenger.showSnackBar(const SnackBar(content: Text('You can compare up to 3 properties. Remove one first.')));
      return;
    }
    store.toggle(property.id);
    setState(() {});
    final added = store.contains(property.id);
    messenger.showSnackBar(SnackBar(
      content: Text(added ? 'Added to compare (${store.count}/${CompareStore.maxItems})' : 'Removed from compare'),
      action: store.count >= 2 ? SnackBarAction(label: 'COMPARE', onPressed: () => context.push(RouteNames.compare)) : null,
    ));
  }

  void _toggleFavorite(Property property) {
    PropertyStore.instance.toggleFavorite(property.id);
  }

  Future<void> _bookVisit(Property property) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    final scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final messenger = ScaffoldMessenger.of(context);
    if (!scheduledAt.isAfter(DateTime.now())) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please pick a time in the future.')),
      );
      return;
    }
    try {
      await VisitService.instance.create(propertyId: property.id, scheduledAt: scheduledAt);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Visit requested for ${property.title} on ${date.day}/${date.month}/${date.year} at ${time.format(context)}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not book visit: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

    void _contactOwner(Property property) {
    LeadService.instance.track(property.id, 'contact'); // lead banao, UI ko block nahi karta
    context.push('/property/${property.id}/owner');
  }

  Future<void> _requestAgreement(Property property) async {
    final tenantId = await TokenStore.instance.getUserId();
    if (!mounted) return;
    if (tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to request an agreement.')),
      );
      return;
    }
    var ownerName = property.ownerName;
    if (ownerName.isEmpty && property.ownerId.isNotEmpty) {
      try {
        ownerName = (await ProfileService.instance.getProfile(property.ownerId)).name;
      } catch (_) {}
    }
    if (!mounted) return;
    context.push(
      '/property/${property.id}/agreement/request',
      extra: {
        'propertyTitle': property.title,
        'propertyImageUrl': property.imageUrl,
        'counterpartyName': ownerName,
        'ownerId': property.ownerId,
        'tenantId': tenantId,
      },
    );
  }

  void _viewAllAmenities(Property property) {
    const allAmenities = [
      'wifi', 'parking', 'lift', 'power_backup', 'gym', 'pool',
      'security', 'water_supply', 'gas_pipeline', 'cctv', 'clubhouse', 'garden', 'play_area',
    ];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('All Amenities', style: AppTextStyles.h3),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: allAmenities.map((a) {
                    final available = property.amenities.contains(a);
                    return Opacity(
                      opacity: available ? 1 : 0.35,
                      child: SizedBox(width: 70, child: _AmenityTile(type: a)),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final property = PropertyStore.instance.byId(widget.propertyId);
    if (property == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _notFound ? const Text('Property not found') : const CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Swipeable image carousel with back / favorite buttons + page dots
            Stack(
              children: [
                Hero(
                  tag: 'property_image_${property.id}',
                  child: SizedBox(
                    height: 300,
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () => _openGallery(property, _imageIndex),
                      child: PageView.builder(
                        controller: _imagePageController,
                        itemCount: property.galleryImages.length,
                        onPageChanged: (i) => setState(() => _imageIndex = i),
                        itemBuilder: (context, i) {
                          return CachedNetworkImage(
                            imageUrl: property.galleryImages[i],
                            height: 300,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: AppColors.divider),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.divider,
                              child: const Icon(Icons.home_work_outlined, size: 40, color: AppColors.textHint),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (property.galleryImages.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(property.galleryImages.length, (i) {
                        final active = i == _imageIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white70,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _RoundIconButton(
                          icon: Icons.arrow_back,
                          onTap: () => context.pop(),
                        ),
                        Row(
                          children: [
                            _RoundIconButton(
                              icon: Icons.share_outlined,
                              onTap: () => _shareProperty(property),
                            ),
                            const SizedBox(width: 8),
                            _RoundIconButton(
                              icon: Icons.compare_arrows,
                              iconColor: CompareStore.instance.contains(property.id) ? AppColors.primary : AppColors.textPrimary,
                              onTap: () => _toggleCompare(property),
                            ),
                            const SizedBox(width: 8),
                            _RoundIconButton(
                              icon: Icons.flag_outlined,
                              onTap: () => ReportListingSheet.show(context, property.id),
                            ),
                            const SizedBox(width: 8),
                            _RoundIconButton(
                              icon: property.isFavorite ? Icons.favorite : Icons.favorite_border,
                              iconColor: property.isFavorite ? Colors.red : AppColors.textPrimary,
                              onTap: () => _toggleFavorite(property),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (property.isVerified)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 64,
                    left: AppSpacing.md,
                    child: _VerifiedBadge(onTap: _showVerifiedInfo),
                  ),
              ],
            ),

            // Curved info card overlapping the image
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + price
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(property.title, style: AppTextStyles.h2),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatPrice(property.price, property.priceUnit),
                              style: AppTextStyles.price.copyWith(fontSize: 20),
                            ),
                            if (property.isPriceNegotiable) ...[
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Negotiable',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Location + rating
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(property.location, style: AppTextStyles.bodySmall),
                        ),
                        if (property.reviewCount > 0) ...[
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            '${property.rating.toStringAsFixed(1)} (${property.reviewCount} reviews)',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Beds / Baths / Sqft / Type row
                    Row(
                      children: [
                        _InfoTag(icon: Icons.bed_outlined, label: property.bhk),
                        const SizedBox(width: AppSpacing.sm),
                        _InfoTag(icon: Icons.chair_outlined, label: property.furnishing),
                        const SizedBox(width: AppSpacing.sm),
                        if (property.isVerified)
                          const _InfoTag(icon: Icons.verified_outlined, label: 'Verified'),
                      ],
                    ),
                    const Divider(height: AppSpacing.xl),


                    // About — owner's description.
                    if (property.description.isNotEmpty) ...[
                      _SectionCard(
                        icon: Icons.info_outline,
                        title: 'About this property',
                        child: Text(
                          property.description,
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary, height: 1.5),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Property Details — possession, age, floor, facing, area, etc.
                    if (property.possessionStatus.isNotEmpty ||
                        property.ageOfPropertyYears >= 0 ||
                        property.totalFloors > 0 ||
                        property.facing.isNotEmpty ||
                        property.area > 0 ||
                        property.bathrooms > 0 ||
                        property.balconies > 0 ||
                        property.society.isNotEmpty ||
                        property.ownershipType.isNotEmpty ||
                        property.availableFrom != null ||
                        property.securityDeposit > 0 ||
                        property.maintenanceCharges > 0 ||
                        property.preferredTenants.isNotEmpty ||
                        property.isPriceNegotiable) ...[
                      _SectionCard(
                        icon: Icons.home_work_outlined,
                        title: 'Property Details',
                        child: _PropertyDetailsGrid(property: property),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Price Trend — only worth a chart with 2+ data points.
                    if (property.priceHistory.length >= 2) ...[
                      _SectionCard(
                        icon: Icons.trending_up,
                        title: 'Price Trend',
                        child: _PriceTrendChart(property: property),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Amenities
                    if (property.amenities.isNotEmpty) ...[
                      _SectionCard(
                        icon: Icons.auto_awesome_outlined,
                        title: 'Amenities',
                        onViewAll: () => _viewAllAmenities(property),
                        child: LayoutBuilder(builder: (context, c) {
                          final itemW = (c.maxWidth - 3 * AppSpacing.sm) / 4;
                          return Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.md,
                            children: property.amenities
                                .take(8)
                                .map((a) => SizedBox(width: itemW, child: _AmenityTile(type: a)))
                                .toList(),
                          );
                        }),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Nearby Landmarks — schools, hospitals, metro, etc.
                    if (property.nearbyLandmarks.isNotEmpty) ...[
                      _SectionCard(
                        icon: Icons.place_outlined,
                        title: 'Nearby Landmarks',
                        child: _NearbyLandmarksSection(property: property),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Gallery — tap any photo to open the fullscreen viewer.
                    _SectionCard(
                      icon: Icons.photo_library_outlined,
                      title: 'Gallery',
                      onViewAll: () => _openGallery(property, 0),
                      child: Builder(builder: (context) {
                        final images = property.galleryImages;
                        // Up to 4 slots; if there are more photos, the last
                        // slot becomes a "+N" overlay tile.
                        const maxSlots = 4;
                        final showOverflow = images.length > maxSlots;
                        final visibleCount = showOverflow ? maxSlots - 1 : images.length;
                        final remaining = images.length - visibleCount;
                        return SizedBox(
                          height: 76,
                          child: Row(
                            children: [
                              for (int i = 0; i < visibleCount; i++) ...[
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _openGallery(property, i),
                                    child: _GalleryThumb(imageUrl: images[i]),
                                  ),
                                ),
                                if (i != visibleCount - 1 || showOverflow) const SizedBox(width: AppSpacing.sm),
                              ],
                              if (showOverflow)
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _openGallery(property, visibleCount),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _GalleryThumb(imageUrl: images[visibleCount]),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryDark.withValues(alpha: 0.6),
                                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '+$remaining',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Video Tour — only shown when the owner/dealer has
                    // uploaded a walkthrough video for this listing.
                    if (property.videoTourUrl != null) ...[
                      _SectionCard(
                        icon: Icons.play_circle_fill_rounded,
                        title: 'Video Tour',
                        child: VideoTourCard(
                          videoUrl: property.videoTourUrl!,
                          thumbnailUrl: property.imageUrl,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Floor Plan — only shown when the owner/dealer has
                    // uploaded one. Tap opens it fullscreen with pinch-zoom
                    // (reusing the same viewer as the photo gallery).
                    if (property.floorPlanUrl != null) ...[
                      Text('Floor Plan', style: AppTextStyles.h3),
                      const SizedBox(height: AppSpacing.sm),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          GalleryViewerScreen.route(
                            imageUrls: [property.floorPlanUrl!],
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          child: Stack(
                            children: [
                              CachedNetworkImage(
                                imageUrl: property.floorPlanUrl!,
                                height: 170,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(height: 170, color: AppColors.divider),
                                errorWidget: (_, __, ___) => Container(height: 170, color: AppColors.divider),
                              ),
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.zoom_in, color: Colors.white, size: 16),
                                      SizedBox(width: 4),
                                      Text('View Full Size', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _bookVisit(property),
                            icon: const Icon(Icons.calendar_month_outlined, size: 20),
                            label: const Text('Book a Visit'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _contactOwner(property),
                            icon: const Icon(Icons.person_outline, size: 20),
                            label: const Text('Contact Owner'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Material(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        onTap: () => _requestAgreement(property),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 20, color: AppColors.primary),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Request Agreement',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Reviews (public; writing needs a completed visit).
                    PropertyReviewsSection(propertyId: property.id),
                    const SizedBox(height: AppSpacing.xl),

                    // Similar Properties
                    Builder(builder: (context) {
                      final similar = similarProperties(property, limit: 8);
                      if (similar.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Similar Properties', style: AppTextStyles.h3),
                          const SizedBox(height: 2),
                          Text(
                            'Based on location, type & budget',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            height: 210,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: similar.length,
                              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                              itemBuilder: (context, index) {
                                final p = similar[index];
                                return _SimilarPropertyCard(
                                  property: p,
                                  onTap: () => context.pushReplacement('/property/${p.id}'),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimilarPropertyCard extends StatelessWidget {
  final Property property;
  final VoidCallback onTap;
  const _SimilarPropertyCard({required this.property, required this.onTap});

  String _formatPrice(Property p) {
    return formatPrice(p.price, p.priceUnit);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
                  child: CachedNetworkImage(
                    imageUrl: property.imageUrl,
                    height: 110,
                    width: 180,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(height: 110, color: AppColors.divider),
                    errorWidget: (_, __, ___) => Container(height: 110, color: AppColors.divider, child: const Icon(Icons.home_work_outlined, size: 28)),
                  ),
                ),
                if (property.isVerified)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Verified', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(property.title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(property.location, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatPrice(property), style: AppTextStyles.price.copyWith(fontSize: 13)),
                      if (property.reviewCount > 0)
                        Row(
                          children: [
                            const Icon(Icons.star, size: 12, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(property.rating.toStringAsFixed(1), style: AppTextStyles.caption),
                          ],
                        ),
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

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  const _RoundIconButton({required this.icon, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: iconColor ?? AppColors.textPrimary),
      ),
    );
  }
}

class _InfoTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  final String imageUrl;
  const _GalleryThumb({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ), 
    );
  }
}
class _AmenityTile extends StatelessWidget {
  final String type;
  const _AmenityTile({required this.type});

  IconData get _icon {
    switch (type) {
      case 'wifi':
        return Icons.wifi;
      case 'parking':
        return Icons.local_parking_outlined;
      case 'lift':
        return Icons.elevator_outlined;
      case 'power_backup':
        return Icons.power_outlined;
      case 'gym':
        return Icons.fitness_center_outlined;
      case 'pool':
        return Icons.pool_outlined;
      case 'security':
        return Icons.security_outlined;
      case 'water_supply':
        return Icons.water_drop_outlined;
      case 'gas_pipeline':
        return Icons.local_fire_department_outlined;
      case 'cctv':
        return Icons.videocam_outlined;
      case 'clubhouse':
        return Icons.deck_outlined;
      case 'garden':
        return Icons.park_outlined;
      case 'play_area':
        return Icons.child_care_outlined;
      default:
        return Icons.check_circle_outline;
    }
  }

  String get _label {
    switch (type) {
      case 'wifi':
        return 'Wifi';
      case 'parking':
        return 'Parking';
      case 'lift':
        return 'Lift';
      case 'power_backup':
        return 'Power Backup';
      case 'gym':
        return 'Gym';
      case 'pool':
        return 'Pool';
      case 'security':
        return 'Security';
      case 'water_supply':
        return '24x7 Water';
      case 'gas_pipeline':
        return 'Gas Pipeline';
      case 'cctv':
        return 'CCTV';
      case 'clubhouse':
        return 'Clubhouse';
      case 'garden':
        return 'Garden';
      case 'play_area':
        return 'Play Area';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.secondary, AppColors.primary],
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 4),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(_icon, size: 22, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          _label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 2-column grid of key facts: possession, age of construction, floor,
/// facing, and carpet/plot area.
class _PropertyDetailsGrid extends StatelessWidget {
  final Property property;
  const _PropertyDetailsGrid({required this.property});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      if (property.possessionStatus.isNotEmpty)
        (
          Icons.event_available_outlined,
          'Possession',
          property.possessionDate != null
              ? '${property.possessionStatus} • ${property.possessionDate!.day}/${property.possessionDate!.month}/${property.possessionDate!.year}'
              : property.possessionStatus,
        ),
      if (property.ageOfPropertyYears >= 0)
        (
          Icons.cake_outlined,
          'Age of Property',
          property.ageOfPropertyYears == 0 ? 'New Construction' : '${property.ageOfPropertyYears} yrs old',
        ),
      if (property.totalFloors > 0)
        (
          Icons.stairs_outlined,
          'Floor',
          '${property.floorNumber == 0 ? 'Ground' : property.floorNumber} of ${property.totalFloors}',
        ),
      if (property.facing.isNotEmpty) (Icons.explore_outlined, 'Facing', property.facing),
      if (property.area > 0) (Icons.square_foot_outlined, 'Area', '${property.area.toStringAsFixed(0)} sqft'),
      if (property.bathrooms > 0) (Icons.bathtub_outlined, 'Bathrooms', '${property.bathrooms}'),
      if (property.balconies > 0) (Icons.balcony_outlined, 'Balconies', '${property.balconies}'),
      if (property.society.isNotEmpty) (Icons.apartment_outlined, 'Society', property.society),
      if (property.ownershipType.isNotEmpty) (Icons.gavel_outlined, 'Ownership', property.ownershipType),
      if (property.availableFrom != null)
        (
          Icons.event_outlined,
          'Available From',
          '${property.availableFrom!.day}/${property.availableFrom!.month}/${property.availableFrom!.year}',
        ),
      if (property.securityDeposit > 0)
        (Icons.savings_outlined, 'Security Deposit', '₹${property.securityDeposit.toStringAsFixed(0)}'),
      if (property.maintenanceCharges > 0)
        (Icons.build_outlined, 'Maintenance', '₹${property.maintenanceCharges.toStringAsFixed(0)}/month'),
      if (property.preferredTenants.isNotEmpty)
        (Icons.groups_outlined, 'Preferred Tenants', property.preferredTenants.join(', ')),
      if (property.isPriceNegotiable) (Icons.handshake_outlined, 'Price', 'Negotiable'),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return GridView.count(
      padding: EdgeInsets.zero,
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 3.0,
      children: items.map((item) {
        final (icon, label, value) = item;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                width:28,
                height: 28,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Icon(icon, size: 15, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                    Text(
                      value,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// RERA number + the list of documents checked as part of verification.
/// The overall "Verified" badge is only ever shown when this data backs it
/// up (see [Property.isDocumentVerified]).
/// Small line chart of the listing's historical price points, with an
/// overall change badge (e.g. "+8.7% since Feb").
class _PriceTrendChart extends StatelessWidget {
  final Property property;
  const _PriceTrendChart({required this.property});

  String _formatPrice(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(0)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final history = property.priceHistory;
    final first = history.first.price;
    final last = history.last.price;
    final changePct = first == 0 ? 0.0 : ((last - first) / first) * 100;
    final isUp = changePct >= 0;

    final minY = history.map((p) => p.price).reduce((a, b) => a < b ? a : b);
    final maxY = history.map((p) => p.price).reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.15 + 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatPrice(last), style: AppTextStyles.h3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isUp ? AppColors.success : AppColors.error).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUp ? Icons.trending_up : Icons.trending_down,
                      size: 14,
                      color: isUp ? AppColors.success : AppColors.error,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${isUp ? '+' : ''}${changePct.toStringAsFixed(1)}%',
                      style: AppTextStyles.caption.copyWith(
                        color: isUp ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 110,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < history.length; i++) FlSpot(i.toDouble(), history[i].price),
                    ],
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: AppColors.primary.withValues(alpha: 0.1)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Since ${history.first.date.day}/${history.first.date.month}/${history.first.date.year}',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Nearby points of interest with a type-specific icon and distance.
class _NearbyLandmarksSection extends StatelessWidget {
  final Property property;
  const _NearbyLandmarksSection({required this.property});

  IconData _iconFor(String type) {
    switch (type) {
      case 'school':
        return Icons.school_outlined;
      case 'hospital':
        return Icons.local_hospital_outlined;
      case 'metro':
        return Icons.directions_subway_outlined;
      case 'mall':
        return Icons.local_mall_outlined;
      case 'market':
        return Icons.storefront_outlined;
      case 'park':
        return Icons.park_outlined;
      case 'bus_stop':
        return Icons.directions_bus_outlined;
      default:
        return Icons.place_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: property.nearbyLandmarks.map((landmark) {
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                child: Icon(_iconFor(landmark.type), size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(landmark.name, style: AppTextStyles.bodySmall),
              ),
              Text(
                '${landmark.distanceKm.toStringAsFixed(1)} km',
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// White rounded card with an icon + title header and an optional
/// "View all >" link. Used for Amenities, Gallery and Video Tour.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onViewAll;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Icon(icon, size: 15, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.h3.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
              ),
              if (onViewAll != null)
                InkWell(
                  onTap: onViewAll,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          'View all',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
class _VerifiedBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _VerifiedBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F9D58),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 16, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'Verified',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            SizedBox(width: 4),
            Icon(Icons.info, size: 14, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}