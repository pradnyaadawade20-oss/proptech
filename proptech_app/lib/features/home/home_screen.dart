import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/property_card.dart';
import '../properties/property.dart';
import '../properties/property_store.dart';
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

  final PageController _listBannerController = PageController();
  int _listBannerIndex = 0;
  final List<Map<String, String>> _listBannerSlides = const [
    {
      'image': 'assets/images/onboarding_1.jpg',
      'title': 'List your property',
      'subtitle': 'Get verified & find the right buyers or tenants faster.',
    },
    {
      'image': 'assets/images/onboarding_2.jpg',
      'title': 'Sell faster with us',
      'subtitle': 'Reach verified buyers in your city.',
    },
    {
      'image': 'assets/images/onboarding_3.jpg',
      'title': 'Zero brokerage rentals',
      'subtitle': 'List your rental and connect directly with tenants.',
    },
  ];

  @override
  void initState() {
    super.initState();
    properties = List.of(PropertyStore.instance.all);
    RecentlyViewedStore.instance.load();
    WidgetsBinding.instance.addPostFrameCallback((_) => PropertyStore.instance.load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listBannerController.dispose();
    super.dispose();
  }

  List<String> get _homeLocationSuggestions {
    if (_homeQuery.isEmpty) return [];
    final locations = PropertyStore.instance.all.map((p) => p.location).toSet().toList()..sort();
    return locations.where((loc) => loc.toLowerCase().contains(_homeQuery.toLowerCase())).toList();
  }

  // ---- Real numbers / images derived from the loaded listings ----
  int _count(bool Function(Property) test) => PropertyStore.instance.all.where(test).length;

  String _countLabel(int n) => n == 1 ? '1 Property' : '$n Properties';

  String _imageFor(bool Function(Property) test) {
    for (final p in PropertyStore.instance.all) {
      if (test(p) && p.imageUrl.isNotEmpty) return p.imageUrl;
    }
    return '';
  }

  bool _isBuy(Property p) => p.category == 'Residential' && p.priceUnit != '/month';
  bool _isRent(Property p) => p.category == 'Residential' && p.priceUnit == '/month' && p.bhk != 'PG';
  bool _isFurnished(Property p) => p.furnishing == 'Furnished' || p.furnishing == 'Fully Furnished';

  String _priceText(Property p) {
    final v = p.price;
    final String s;
    if (v >= 10000000) {
      s = '₹${(v / 10000000).toStringAsFixed(2)} Cr';
    } else if (v >= 100000) {
      s = '₹${(v / 100000).toStringAsFixed(2)} L';
    } else {
      s = '₹${v.toStringAsFixed(0)}';
    }
    return p.priceUnit.isEmpty ? s : '$s ${p.priceUnit}';
  }

  String _timeAgo(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hrs ago';
    if (d.inDays == 1) return '1 day ago';
    return '${d.inDays} days ago';
  }

  List<Map<String, String>> get _recentlyPostedItems {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final list = List<Property>.of(PropertyStore.instance.all)
      ..sort((a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
    return list
        .take(6)
        .map((p) => {
              'id': p.id,
              'image': p.imageUrl,
              'price': _priceText(p),
              'title': p.title,
              'subtitle': p.location,
              'time': _timeAgo(p.createdAt),
            })
        .toList();
  }

  Widget _storeStatus() {
    final store = PropertyStore.instance;
    if (store.loading && !store.loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (store.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          children: [
            Text(store.error!, style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
            TextButton(onPressed: store.load, child: const Text('Retry')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Text('No properties listed yet', style: AppTextStyles.bodySmall),
      ),
    );
  }

  void _goToSearchResults(String query) {
    _searchFocusNode.unfocus();
    setState(() => _showHomeSuggestions = false);
    context.push(RouteNames.search, extra: query);
  }

  Future<void> _toggleFavorite(String id) async {
    final ok = await PropertyStore.instance.toggleFavorite(id);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update favorite. Please log in and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: propertiesVersion,
      builder: (context, _, __) {
        properties = List.of(PropertyStore.instance.all);
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
      body: RefreshIndicator(
        onRefresh: () => PropertyStore.instance.load(),
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                    child: Image.asset(
                      'assets/images/hero_house.jpg',
                      width: 160,
                      fit: BoxFit.cover,
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
                      width: 200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: AppTextStyles.h1.copyWith(height: 1.2, fontSize: 21),
                              children: [
                                const TextSpan(text: 'Find your 👋\n'),
                                TextSpan(
                                  text: 'perfect property',
                                  style: const TextStyle().copyWith(color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Buy, Rent or Sell verified properties with complete trust.',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
                          child: Image.asset(
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

          properties.isEmpty
              ? _storeStatus()
              : SizedBox(
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
          if (_recentlyPostedItems.isNotEmpty) ...[
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
                  itemCount: _recentlyPostedItems.length,
                  separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = _recentlyPostedItems[index];
                    return _RecentlyPostedCard(
                      data: item,
                      onTap: () => context.push('/property/${item['id']}'),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

          // ---------------- Homes by furnishing ----------------
          if (PropertyStore.instance.all.isNotEmpty) ...[
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
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ImageLabelTile(
                      imageUrl: _imageFor(_isFurnished),
                      label: 'Furnished (${_count(_isFurnished)})',
                      onTap: () => context.push('/category/furnished'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ImageLabelTile(
                      imageUrl: _imageFor((p) => p.furnishing == 'Semi Furnished'),
                      label: 'Semifurnished (${_count((p) => p.furnishing == 'Semi Furnished')})',
                      onTap: () => context.push('/category/semifurnished'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ImageLabelTile(
                      imageUrl: _imageFor((p) => p.furnishing == 'Unfurnished'),
                      label: 'Unfurnished (${_count((p) => p.furnishing == 'Unfurnished')})',
                      onTap: () => context.push('/category/unfurnished'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

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
                    title: 'Homes\nfor Sale',
                    subtitle: _countLabel(_count(_isBuy)),
                    imageUrl: _imageFor(_isBuy),
                    bgColor: AppColors.primaryLight,
                    onTap: () => context.push('/category/buy'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _CategoryImageCard(
                    title: 'Homes\nfor Rent',
                    subtitle: _countLabel(_count(_isRent)),
                    imageUrl: _imageFor(_isRent),
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
                    itemCount: 3,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final labels = ['1 RK/1 BHK', '2 BHK', '3 BHK'];
                      final tests = <bool Function(Property)>[
                        (p) => p.bhk == '1 RK' || p.bhk == '1 BHK',
                        (p) => p.bhk == '2 BHK',
                        (p) => p.bhk == '3 BHK',
                      ];
                      return _BhkCard(
                        label: labels[index],
                        subtitle: _countLabel(_count(tests[index])),
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
      ),
    );
  }
}

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
                      Text('Posted  ', style: AppTextStyles.caption),
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