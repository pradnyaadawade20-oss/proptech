import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/property_card.dart';
import '../../core/services/place_autocomplete_service.dart';
import '../properties/property.dart';
import 'saved_search.dart';
import 'saved_search_store.dart';
import 'saved_searches_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';
  String? _selectedType;
  RangeValues _budget = const RangeValues(0, 35000000);
  bool _showResults = false;
  bool _showSuggestions = false;
  String _sortOption = 'default'; // default, newest, price_low, price_high, rating, area_large
  List<PlaceSuggestion> _placeMatches = [];
  bool _isSearchingPlace = false;
  Timer? _placeDebounce;

  final List<String> _recentSearches = ['Powai, Mumbai', 'Andheri West', 'Bandra East'];

  List<String> get _allLocations {
    final locations = dummyProperties.map((p) => p.location).toSet().toList();
    locations.sort();
    return locations;
  }

  List<String> get _locationSuggestions {
    if (_query.isEmpty) return [];
    return _allLocations
        .where((loc) => loc.toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  void _selectLocation(String location) {
    _controller.text = location;
    setState(() {
      _query = location;
      _showSuggestions = false;
      _placeMatches = [];
      if (!_recentSearches.contains(location)) {
        _recentSearches.insert(0, location);
        if (_recentSearches.length > 5) _recentSearches.removeLast();
      }
    });
    _searchFocusNode.unfocus();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _showSuggestions = value.isNotEmpty;
    });
    _placeDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _placeMatches = []);
      return;
    }
    _placeDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearchingPlace = true);
      final results = await PlaceAutocompleteService.instance.search(value);
      if (!mounted) return;
      setState(() {
        _placeMatches = results;
        _isSearchingPlace = false;
      });
    });
  }

  @override
  void dispose() {
    _placeDebounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SavedSearchStore.instance.load();
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _controller.text = widget.initialQuery!;
      _query = widget.initialQuery!;
      _showResults = true;
      if (!_recentSearches.contains(widget.initialQuery)) {
        _recentSearches.insert(0, widget.initialQuery!);
        if (_recentSearches.length > 5) _recentSearches.removeLast();
      }
    }
  }

  final List<Map<String, dynamic>> _propertyTypes = const [
    {'label': 'Apartment', 'icon': Icons.apartment_outlined},
    {'label': 'Villa', 'icon': Icons.villa_outlined},
    {'label': 'PG', 'icon': Icons.meeting_room_outlined},
    {'label': 'House', 'icon': Icons.house_outlined},
    {'label': 'Office', 'icon': Icons.business_outlined},
  ];

  String _formatPrice(double value) {
    if (value >= 10000000) return '₹${(value / 10000000).toStringAsFixed(value % 10000000 == 0 ? 0 : 1)}Cr';
    if (value >= 100000) return '₹${(value / 100000).toStringAsFixed(value % 100000 == 0 ? 0 : 1)}L';
    if (value >= 1000) return '₹${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    return '₹${value.toInt()}';
  }

  List<Property> get _filteredProperties {
    final results = filterProperties(
      dummyProperties,
      query: _query,
      type: _selectedType,
      budgetStart: _budget.start,
      budgetEnd: _budget.end,
    );
    return sortProperties(results, _sortOption);
  }

  Future<void> _saveCurrentSearch() async {
    final nameController = TextEditingController(
      text: _query.trim().isNotEmpty ? _query.trim() : (_selectedType ?? 'My Search'),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save this search'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name for this search'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final search = SavedSearch(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      query: _query,
      type: _selectedType,
      budgetStart: _budget.start,
      budgetEnd: _budget.end,
      createdAt: DateTime.now(),
    );
    await SavedSearchStore.instance.add(search);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$name" saved. You\'ll be alerted when a new matching property is listed.')),
    );
  }

  void _openSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (sheetContext) {
        Widget option(String label, String value) {
          return RadioListTile<String>(
            title: Text(label),
            value: value,
            groupValue: _sortOption,
            activeColor: AppColors.primary,
            onChanged: (selected) {
              setState(() => _sortOption = selected!);
              Navigator.pop(sheetContext);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('Sort by', style: AppTextStyles.h3),
              ),
              option('Most Relevant', 'default'),
              option('Newest First', 'newest'),
              option('Price: Low to High', 'price_low'),
              option('Price: High to Low', 'price_high'),
              option('Rating: High to Low', 'rating'),
              option('Area: Largest First', 'area_large'),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _filteredProperties;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_showResults) {
              setState(() => _showResults = false);
            } else if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouteNames.home);
            }
          },
        ),
        title: const Text('Search'),
        actions: [
          ValueListenableBuilder<List<SavedSearch>>(
            valueListenable: SavedSearchStore.instance.searches,
            builder: (context, savedList, _) {
              final newCount = SavedSearchStore.instance.totalNewMatches;
              return IconButton(
                icon: Badge(
                  isLabelVisible: newCount > 0,
                  label: Text('$newCount'),
                  child: const Icon(Icons.bookmark_border),
                ),
                tooltip: 'Saved Searches',
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SavedSearchesScreen(),
                  ));
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Map View',
            onPressed: () => context.push('/map-search'),
          ),
        ],
      ),
      body: _showResults ? _buildResultsView(results) : _buildFiltersView(),
    );
  }

  Widget _buildFiltersView() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // Search input
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
                  controller: _controller,
                  focusNode: _searchFocusNode,
                  decoration: const InputDecoration(
                    hintText: 'Powai, Mumbai',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: _onQueryChanged,
                  onTap: () => setState(() => _showSuggestions = _query.isNotEmpty),
                ),
              ),
              if (_controller.text.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() {
                    _controller.clear();
                    _query = '';
                    _showSuggestions = false;
                    _placeMatches = [];
                  }),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textHint),
                ),
            ],
          ),
        ),

        // Location suggestions dropdown — app's own listings first, then
        // live place autocomplete (Google-Places-style, via OSM Nominatim).
        if (_showSuggestions)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            constraints: const BoxConstraints(maxHeight: 280),
            child: (_locationSuggestions.isEmpty && _placeMatches.isEmpty && !_isSearchingPlace)
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      _query.trim().length < 3 ? 'Keep typing to search places...' : 'No matching location',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      if (_locationSuggestions.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                          child: Text('In Our Listings', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        for (final loc in _locationSuggestions)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.home_work_outlined, size: 18, color: AppColors.primary),
                            title: Text(loc, style: AppTextStyles.bodySmall),
                            onTap: () => _selectLocation(loc),
                          ),
                      ],
                      if (_isSearchingPlace)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                          child: Center(
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        )
                      else if (_placeMatches.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                          child: Text('Places', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        for (final place in _placeMatches)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined, size: 18, color: AppColors.textSecondary),
                            title: Text(place.displayName, style: AppTextStyles.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => _selectLocation(place.displayName),
                          ),
                      ],
                    ],
                  ),
          ),
        const SizedBox(height: AppSpacing.lg),

        // Recent searches
        Text('Recent Searches', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _recentSearches.map((s) {
            return GestureDetector(
              onTap: () => _selectLocation(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(s, style: AppTextStyles.bodySmall),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.lg),

        // EMI Calculator quick-access
        const _EmiCalculatorCard(),
        const SizedBox(height: AppSpacing.lg),

        // Property type
        Text('Property Type', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: _propertyTypes.map((type) {
            final isSelected = _selectedType == type['label'];
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _selectedType = isSelected ? null : type['label'] as String;
                }),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Icon(
                        type['icon'] as IconData,
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type['label'] as String,
                      style: AppTextStyles.caption,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Budget range
        Text('Budget Range', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        RangeSlider(
          values: _budget,
          min: 0,
          max: 35000000,
          divisions: 35,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.surfaceSoft,
          labels: RangeLabels(
            _formatPrice(_budget.start),
            _formatPrice(_budget.end),
          ),
          onChanged: (values) => setState(() => _budget = values),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatPrice(_budget.start), style: AppTextStyles.bodySmall),
            Text(_budget.end >= 35000000 ? '${_formatPrice(_budget.end)}+' : _formatPrice(_budget.end), style: AppTextStyles.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),

        // Show results button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _showResults = true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
            ),
            child: Text('Show ${_filteredProperties.length} Results'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _saveCurrentSearch,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Save this search & get alerts'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsView(List<Property> results) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${results.length} Properties Found', style: AppTextStyles.h3.copyWith(fontSize: 15)),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _openSortSheet,
                    icon: const Icon(Icons.swap_vert, size: 16),
                    label: const Text('Sort'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _showResults = false),
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text('Filter'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: results.isEmpty
              ? const Center(child: Text('No properties found'))
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final property = results[index];
                    return PropertyCard(
                      property: property,
                      onTap: () => context.push('/property/${property.id}'),
                      onFavoriteTap: () {
                        final i = dummyProperties.indexWhere((p) => p.id == property.id);
                        if (i != -1) {
                          dummyProperties[i] = property.copyWith(isFavorite: !property.isFavorite);
                          notifyPropertiesChanged();
                          setState(() {});
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
/// Quick-access card that opens the EMI Calculator.
class _EmiCalculatorCard extends StatelessWidget {
  const _EmiCalculatorCard();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: () => context.push(RouteNames.emiCalculator),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: const Color(0xFFFBEBD3),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(color: AppColors.primaryDark, shape: BoxShape.circle),
              child: const Icon(Icons.calculate_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('EMI Calculator', style: AppTextStyles.h3.copyWith(fontSize: 15, color: AppColors.primaryDark)),
                  const SizedBox(height: 2),
                  Text(
                    'Estimate your monthly home loan EMI',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.primaryDark.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.primaryDark),
          ],
        ),
      ),
    );
  }
}