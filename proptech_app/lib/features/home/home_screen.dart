import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/property_card.dart';
import '../properties/property.dart';
import '../properties/recently_viewed_store.dart';
import '../auth/role_switcher_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late List<Property> properties;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _homeQuery = '';
  bool _showHomeSuggestions = false;

  final PageController _heroPageController = PageController();
  int _heroPageIndex = 0;
  final List<String> _heroImages = const [
    'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=500',
    'https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=500',
    'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=500',
  ];

  final PageController _listBannerController = PageController();
  int _listBannerIndex = 0;
  final List<Map<String, String>> _listBannerSlides = const [
    {
      'image': 'https://images.unsplash.com/photo-1568605114967-8130f3a36994',
      'title': 'List your property',
      'subtitle': 'Get verified & find the right buyers or tenants faster.',
    },
    {
      'image': 'https://images.unsplash.com/photo-1512917774080-9991f1c4c750',
      'title': 'Sell faster with us',
      'subtitle': 'Reach thousands of verified buyers in your city.',
    },
    {
      'image': 'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9',
      'title': 'Zero brokerage rentals',
      'subtitle': 'List your rental and connect directly with tenants.',
    },
  ];

  @override
  void initState() {
    super.initState();
    properties = List.of(dummyProperties);
    RecentlyViewedStore.instance.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _heroPageController.dispose();
    _listBannerController.dispose();
    super.dispose();
  }

  List<String> get _homeLocationSuggestions {
    if (_homeQuery.isEmpty) return [];
    final locations = dummyProperties.map((p) => p.location).toSet().toList()..sort();
    return locations.where((loc) => loc.toLowerCase().contains(_homeQuery.toLowerCase())).toList();
  }

  void _goToSearchResults(String query) {
    _searchFocusNode.unfocus();
    setState(() => _showHomeSuggestions = false);
    context.push(RouteNames.search, extra: query);
  }

  void _toggleFavorite(String id) {
    final index = dummyProperties.indexWhere((p) => p.id == id);
    if (index != -1) {
      dummyProperties[index] = dummyProperties[index].copyWith(isFavorite: !dummyProperties[index].isFavorite);
      notifyPropertiesChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: propertiesVersion,
      builder: (context, _, __) {
        properties = List.of(dummyProperties);
        return _buildScaffold(context);
      },
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.home_work, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('PropTech', style: AppTextStyles.h3),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Switch role',
            onPressed: () => showRoleSwitcherSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: () => context.push(RouteNames.favorites),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No new notifications')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Greeting heading + hero banner (gradient-fade image, like "List your property" banner)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Container(
              height: 170,
              decoration: const BoxDecoration(color: AppColors.background),
              child: Stack(
                children: [
                  // Background house image bleeding off the right edge
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 160,
                    child: PageView.builder(
                      controller: _heroPageController,
                      itemCount: _heroImages.length,
                      onPageChanged: (i) => setState(() => _heroPageIndex = i),
                      itemBuilder: (context, index) => CachedNetworkImage(
                        imageUrl: _heroImages[index],
                        width: 160,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(width: 160, color: AppColors.primaryLight),
                        errorWidget: (_, __, ___) => Container(width: 160, color: AppColors.primaryLight),
                      ),
                    ),
                  ),
                  // Fade so text stays readable, matches background color on the left
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            AppColors.background,
                            AppColors.background,
                            AppColors.background.withValues(alpha: 0.0),
                          ],
                          stops: const [0.0, 0.55, 0.9],
                        ),
                      ),
                    ),
                  ),
                  // Text content
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: SizedBox(
                      width: 250,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: AppTextStyles.h1.copyWith(height: 1.2),
                              children: [
                                const TextSpan(text: 'Find your\n'),
                                TextSpan(
                                  text: 'perfect property',
                                  style: const TextStyle().copyWith(color: AppColors.primary),
                                ),
                                const TextSpan(text: ' 👋'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Buy, Rent or Sell verified properties with complete trust.',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_heroImages.length, (i) {
                final active = i == _heroPageIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Quick-action icons row inside dark teal card
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: SizedBox(
              height: 78,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                children: [
                  _HeroIconItem(icon: Icons.home_outlined, label: 'Buy', onTap: () => context.push('/category/buy')),
                  const _HeroIconDivider(),
                  _HeroIconItem(icon: Icons.vpn_key_outlined, label: 'Rent', onTap: () => context.push('/category/rent')),
                  const _HeroIconDivider(),
                  _HeroIconItem(icon: Icons.apartment_outlined, label: 'Commercial', onTap: () => context.push('/category/commercial')),
                  const _HeroIconDivider(),
                  _HeroIconItem(icon: Icons.landscape_outlined, label: 'Plot/Land', onTap: () => context.push('/category/plot')),
                  const _HeroIconDivider(),
                  _HeroIconItem(icon: Icons.bed_outlined, label: 'PG', onTap: () => context.push('/category/pg')),
                  const _HeroIconDivider(),
                  _HeroIconItem(icon: Icons.add_circle_outline, label: 'Post', onTap: () => context.push(RouteNames.addProperty)),
                  const _HeroIconDivider(),
                  _HeroIconItem(icon: Icons.arrow_forward, label: 'View all', onTap: () => context.push('/all-categories')),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Search bar with filter icon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.textHint),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Search location, city, or area...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    style: AppTextStyles.bodyMedium,
                    onChanged: (value) => setState(() {
                      _homeQuery = value;
                      _showHomeSuggestions = value.isNotEmpty;
                    }),
                    onTap: () => setState(() => _showHomeSuggestions = _homeQuery.isNotEmpty),
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) _goToSearchResults(value.trim());
                    },
                  ),
                ),
                GestureDetector(
                  onTap: () => context.push(RouteNames.search),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.tune, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),

          // Live location suggestions as the person types
          if (_showHomeSuggestions)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.border),
              ),
              constraints: const BoxConstraints(maxHeight: 220),
              child: _homeLocationSuggestions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        'No matching location',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _homeLocationSuggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final loc = _homeLocationSuggestions[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_outlined, size: 18, color: AppColors.textSecondary),
                          title: Text(loc, style: AppTextStyles.bodySmall),
                          onTap: () {
                            _searchController.text = loc;
                            _goToSearchResults(loc);
                          },
                        );
                      },
                    ),
            ),
          const SizedBox(height: AppSpacing.md),

          // Category chips
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _PopularChip(label: '1 BHK', onTap: () => context.push('/category/1bhk')),
                const SizedBox(width: 8),
                _PopularChip(label: '2 BHK', onTap: () => context.push('/category/2bhk')),
                const SizedBox(width: 8),
                _PopularChip(label: 'PG', onTap: () => context.push('/category/pg')),
                const SizedBox(width: 8),
                _PopularChip(label: 'Rooms', onTap: () => context.push('/category/rooms')),
                const SizedBox(width: 8),
                _PopularChip(label: 'Villa', onTap: () => context.push('/category/villa')),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // List your property banner (swipeable carousel)
          SizedBox(
            height: 190,
            child: PageView.builder(
              controller: _listBannerController,
              itemCount: _listBannerSlides.length,
              onPageChanged: (i) => setState(() => _listBannerIndex = i),
              itemBuilder: (context, index) {
                final slide = _listBannerSlides[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: Container(
                    decoration: const BoxDecoration(color: AppColors.primary),
                    child: Stack(
                      children: [
                        // Background house image bleeding off the right edge
                        Positioned(
                          right: -20,
                          bottom: -20,
                          top: 0,
                          child: Image.network(
                            slide['image']!,
                            width: 180,
                            fit: BoxFit.cover,
                            color: Colors.black.withValues(alpha: 0.15),
                            colorBlendMode: BlendMode.darken,
                          ),
                        ),
                        // Fade so text stays readable
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  AppColors.primary,
                                  AppColors.primary.withValues(alpha: 0.85),
                                  AppColors.primary.withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 0.55, 1.0],
                              ),
                            ),
                          ),
                        ),
                        // Text content
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                slide['title']!,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 190,
                                child: Text(
                                  slide['subtitle']!,
                                  style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              ElevatedButton(
                                onPressed: () => context.push(RouteNames.addProperty),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                                ),
                                child: const Text('List Now'),
                              ),
                            ],
                          ),
                        ),
                        // Dots indicator
                        Positioned(
                          bottom: 10,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_listBannerSlides.length, (i) {
                              final active = i == _listBannerIndex;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: active ? 16 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: active ? Colors.white : Colors.white38,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Recommended header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recommended for you', style: AppTextStyles.h3),
              GestureDetector(
                onTap: () => context.push(RouteNames.search),
                child: Text(
                  'See all',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: properties.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final property = properties[index];
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 400 + (index * 100)),
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
                  child: SizedBox(
                    width: 190,
                    child: PropertyCard(
                      property: property,
                      onTap: () => context.push('/property/${property.id}'),
                      onFavoriteTap: () => _toggleFavorite(property.id),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---------------- Recently Viewed properties ----------------
          ValueListenableBuilder<List<String>>(
            valueListenable: RecentlyViewedStore.instance.ids,
            builder: (context, viewedIds, _) {
              final viewed = RecentlyViewedStore.resolve(viewedIds, limit: 10);
              if (viewed.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FadeSlideIn(
                    delayMs: 0,
                    child: _SectionHeader(
                      title: 'Recently Viewed',
                      subtitle: 'Pick up where you left off',
                      trailing: TextButton(
                        onPressed: () async {
                          await RecentlyViewedStore.instance.clear();
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _FadeSlideIn(
                    delayMs: 50,
                    child: SizedBox(
                      height: 210,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: viewed.length,
                        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final property = viewed[index];
                          return _RecentlyViewedCard(
                            property: property,
                            onTap: () => context.push('/property/${property.id}'),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              );
            },
          ),

          // ---------------- Recently posted properties ----------------
          const _FadeSlideIn(
            delayMs: 0,
            child: _SectionHeader(
              title: 'Recently posted properties',
              subtitle: 'Fresh properties, be quick before they rent out',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _FadeSlideIn(
            delayMs: 50,
            child: SizedBox(
              height: 250,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recentlyPosted.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final item = _recentlyPosted[index];
                  return _RecentlyPostedCard(
                    data: item,
                    onTap: () => context.push('/property/${item['id']}'),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---------------- Recommended Projects ----------------
          const _FadeSlideIn(
            delayMs: 100,
            child: _SectionHeader(
              title: 'Recommended Projects',
              subtitle: 'The most searched projects near you',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _FadeSlideIn(
            delayMs: 150,
            child: SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recommendedProjects.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final item = _recommendedProjects[index];
                  return _ProjectCard(
                    data: item,
                    onTap: () => context.push('/property/${item['id']}'),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---------------- Curated rental collections ----------------
          const _FadeSlideIn(
            delayMs: 200,
            child: _SectionHeader(
              title: 'Curated rental collections',
              subtitle: 'Handpicked for how you live',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _FadeSlideIn(
            delayMs: 250,
            child: SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _rentalCollections.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final item = _rentalCollections[index];
                  return _CollectionCard(
                    data: item,
                    onTap: () => context.push('/category/${item['type']}'),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---------------- Homes by furnishing ----------------
          const _FadeSlideIn(
            delayMs: 300,
            child: _SectionHeader(
              title: 'Homes by furnishing',
              subtitle: 'Choose your preferred furnishing',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _FadeSlideIn(
            delayMs: 350,
            child: SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _furnishingOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final item = _furnishingOptions[index];
                  return _ImageLabelTile(
                    imageUrl: item['image']!,
                    label: item['label']!,
                    onTap: () => context.push('/category/${item['type']}'),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---------------- Properties posted by ----------------
          _FadeSlideIn(
            delayMs: 400,
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Properties\nposted by', style: AppTextStyles.h2.copyWith(height: 1.2)),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _PostedByCard(
                        icon: Icons.badge_outlined,
                        label: 'Dealer',
                        subtitle: '9,300+ Properties',
                        onTap: () => context.push('/category/dealer'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _PostedByCard(
                        icon: Icons.person_outline,
                        label: 'Owner',
                        subtitle: '710+ Properties',
                        onTap: () => context.push('/category/owner'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---------------- Apartments, Villas and more ----------------
          const _FadeSlideIn(
            delayMs: 450,
            child: _SectionHeader(
              title: 'Apartments, Villas and more',
              subtitle: 'in your city',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _FadeSlideIn(
            delayMs: 500,
            child: Row(
              children: [
                Expanded(
                  child: _CategoryImageCard(
                    title: 'Residential\nApartment',
                    subtitle: '9,800+ Properties',
                    imageUrl: 'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00',
                    bgColor: AppColors.primaryLight,
                    onTap: () => context.push('/category/buy'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _CategoryImageCard(
                    title: 'Studio\nApartment',
                    subtitle: '90+ Properties',
                    imageUrl: 'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688',
                    bgColor: const Color(0xFFDCE7F0),
                    onTap: () => context.push('/category/rent'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---------------- BHK choice in mind? ----------------
          _FadeSlideIn(
            delayMs: 550,
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: const Color(0xFFFBEBD3),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BHK choice\nin mind?', style: AppTextStyles.h2.copyWith(height: 1.2)),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _bhkChoices.length,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final item = _bhkChoices[index];
                      return _BhkCard(
                        label: item['label']!,
                        subtitle: item['subtitle']!,
                        onTap: () => context.push(RouteNames.search),
                      );
                    },
                  ),
                ),
              ],
            ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

// ==================== Dummy dashboard data ====================

final List<Map<String, String>> _recentlyPosted = [
  {
    'id': 'rp1',
    'image': 'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267',
    'price': '₹10,000 /month',
    'title': '1 RK Studio Apartment',
    'subtitle': 'In Priyadarshani CHS, Gaurish Nagar',
    'time': '22 hrs ago',
  },
  {
    'id': 'rp2',
    'image': 'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2',
    'price': '₹10,000 /month',
    'title': '1 RK Studio Apartment',
    'subtitle': 'In Priyadarshani CHS, Savitribai Rd',
    'time': '23 hrs ago',
  },
  {
    'id': 'rp3',
    'image': 'https://images.unsplash.com/photo-1502672023488-70e25813eb80',
    'price': '₹6,500 /month',
    'title': '1 RK Studio Apartment',
    'subtitle': 'In apartment complex, Chembur',
    'time': '1 day ago',
  },
  {
    'id': 'rp4',
    'image': 'https://images.unsplash.com/photo-1493809842364-78817add7ffb',
    'price': '₹18,000 /month',
    'title': '2 BHK Apartment',
    'subtitle': 'In Sunrise Towers, Andheri',
    'time': '2 days ago',
  },
];

final List<Map<String, String>> _recommendedProjects = [
  {
    'id': 'proj1',
    'image': 'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab',
    'title': 'Marathon Neopark',
    'subtitle': '1 BHK · 1 RK Studio Apartment in Bhandup West, Mumbai',
  },
  {
    'id': 'proj2',
    'image': 'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00',
    'title': 'Sayba Swarnaz',
    'subtitle': '1, 2 BHK Apartment in Kandivali, Mumbai',
  },
  {
    'id': 'proj3',
    'image': 'https://images.unsplash.com/photo-1512917774080-9991f1c4c750',
    'title': 'Lodha Amara',
    'subtitle': '2, 3 BHK Apartment in Thane West, Mumbai',
  },
];

final List<Map<String, String>> _rentalCollections = [
  {
    'type': 'family',
    'image': 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c',
    'title': 'For Family',
    'subtitle': '10,000+ Properties',
  },
  {
    'type': 'singles',
    'image': 'https://images.unsplash.com/photo-1522771930-78848d9293e8',
    'title': 'For Singles',
    'subtitle': '5,900+ Properties',
  },
  {
    'type': 'petfriendly',
    'image': 'https://images.unsplash.com/photo-1560185127-6ed189bf02f4',
    'title': 'Pet Friendly',
    'subtitle': '3,200+ Properties',
  },
];

final List<Map<String, String>> _furnishingOptions = [
  {'type': 'furnished', 'image': 'https://images.unsplash.com/photo-1493809842364-78817add7ffb', 'label': 'Furnished'},
  {'type': 'semifurnished', 'image': 'https://images.unsplash.com/photo-1595428774223-ef52624120d2', 'label': 'Semifurnished'},
  {'type': 'unfurnished', 'image': 'https://images.unsplash.com/photo-1519710164239-da123dc03ef4', 'label': 'Unfurnished'},
];

final List<Map<String, String>> _bhkChoices = [
  {'label': '1 RK/1 BHK', 'subtitle': '2,000+ Properties'},
  {'label': '2 BHK', 'subtitle': '4,700+ Properties'},
  {'label': '3 BHK', 'subtitle': '2,100+ Properties'},
];

// ==================== Reusable dashboard widgets ====================

// Reusable entrance animation: fade + slight upward slide, staggered by delay.
class _FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int delayMs;
  const _FadeSlideIn({required this.child, this.delayMs = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 450 + delayMs),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _SectionHeader({required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.h2),
        const SizedBox(height: 2),
        Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
      ],
    );
    if (trailing == null) return content;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: content),
        trailing!,
      ],
    );
  }
}

class _RecentlyViewedCard extends StatelessWidget {
  final Property property;
  final VoidCallback onTap;
  const _RecentlyViewedCard({required this.property, required this.onTap});

  String _formatPrice(Property p) {
    final v = p.price;
    String formatted;
    if (v >= 10000000) {
      formatted = '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    } else if (v >= 100000) {
      formatted = '₹${(v / 100000).toStringAsFixed(1)}L';
    } else {
      formatted = '₹${v.toStringAsFixed(0)}';
    }
    return '$formatted${p.priceUnit}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: CachedNetworkImage(
                imageUrl: property.imageUrl,
                height: 120,
                width: 180,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: 120, color: AppColors.divider),
                errorWidget: (_, __, ___) => Container(height: 120, color: AppColors.divider, child: const Icon(Icons.home_work_outlined, size: 28)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(property.title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(property.location, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(_formatPrice(property), style: AppTextStyles.price.copyWith(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _RecentlyPostedCard extends StatelessWidget {
  final Map<String, String> data;
  final VoidCallback onTap;
  const _RecentlyPostedCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 165,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: data['image']!,
                  height: 110,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(height: 110, color: AppColors.divider),
                  errorWidget: (_, __, ___) => Container(
                    height: 110,
                    color: AppColors.divider,
                    child: const Icon(Icons.apartment, size: 32),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.favorite_border, size: 14, color: AppColors.textSecondary),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      data['price']!,
                      style: AppTextStyles.caption.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['title']!, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(data['subtitle']!, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Posted by Owner  ', style: AppTextStyles.caption),
                      Flexible(
                        child: Text(
                          data['time']!,
                          style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
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

class _ProjectCard extends StatelessWidget {
  final Map<String, String> data;
  final VoidCallback onTap;
  const _ProjectCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: CachedNetworkImage(
                    imageUrl: data['image']!,
                    height: 140,
                    width: 220,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(height: 140, color: AppColors.divider),
                    errorWidget: (_, __, ___) => Container(height: 140, color: AppColors.divider, child: const Icon(Icons.location_city, size: 32)),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.favorite_border, size: 14, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(data['title']!, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
            const SizedBox(height: 2),
            Text(data['subtitle']!, style: AppTextStyles.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final Map<String, String> data;
  final VoidCallback onTap;
  const _CollectionCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 190,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: data['image']!,
              height: 150,
              width: 190,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(height: 150, color: AppColors.divider),
              errorWidget: (_, __, ___) => Container(height: 150, color: AppColors.divider),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.45)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Text(
                data['title']!,
                style: AppTextStyles.h3.copyWith(color: Colors.white),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              right: 12,
              child: Text(
                data['subtitle']!,
                style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageLabelTile extends StatelessWidget {
  final String imageUrl;
  final String label;
  final VoidCallback onTap;
  const _ImageLabelTile({required this.imageUrl, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 96,
                width: 130,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: 96, color: AppColors.divider),
                errorWidget: (_, __, ___) => Container(height: 96, color: AppColors.divider),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _PostedByCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _PostedByCard({required this.icon, required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _CategoryImageCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final Color bgColor;
  final VoidCallback onTap;
  const _CategoryImageCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700), maxLines: 2),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusSm)),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 90,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: 90, color: AppColors.divider),
                errorWidget: (_, __, ___) => Container(height: 90, color: AppColors.divider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BhkCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _BhkCard({required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.home_outlined, color: AppColors.primary, size: 22),
            const SizedBox(height: 6),
            Text(label, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _HeroIconItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeroIconItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primaryDark, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroIconDivider extends StatelessWidget {
  const _HeroIconDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white24,
    );
  }
}

class _CategoryIconItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CategoryIconItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        margin: const EdgeInsets.only(right: AppSpacing.sm),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontSize: 11, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PopularChip({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
      backgroundColor: AppColors.primaryLight,
      side: BorderSide.none,
      onPressed: onTap,
    );
  }
}