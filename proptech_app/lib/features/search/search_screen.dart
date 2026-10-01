import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/location_service.dart';
import '../../core/services/place_autocomplete_service.dart';
import '../../core/widgets/property_card.dart';
import '../properties/property.dart';
import '../properties/property_store.dart';
import 'locality_utils.dart';
import 'nearby_search.dart';
import 'recent_search_store.dart';
import 'saved_search.dart';
import 'saved_search_store.dart';
import 'saved_searches_screen.dart';
import 'search_criteria.dart';

class SearchScreen extends StatefulWidget {
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with PropertyStoreListener<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Buy / Rent / Commercial tab + every filter (type, budget, BHK, ...).
  bool _commercialRent = false;
  SearchCriteria _criteria = SearchCriteria.forMode(ListingMode.buy);
  String _query = '';

  /// City picked for "Popular localities". null = the city with most listings.
  String? _city;

  bool _showResults = false;
  bool _showSuggestions = false;
  String _sortOption = 'default'; // default, newest, price_low, price_high, rating, area_large
  List<PlaceSuggestion> _placeMatches = [];
  bool _isSearchingPlace = false;
  Timer? _placeDebounce;

  // --- "Use my current location" / nearby search ---
  bool _isLocating = false;
  bool _nearbyMode = false;
  double? _myLat;
  double? _myLng;
  String _myCity = '';
  String _myLocality = '';
  String _nearbyLabel = '';
  double _radiusKm = 10;

  ListingMode get _mode => _criteria.mode ?? ListingMode.buy;

  @override
  void initState() {
    super.initState();
    SavedSearchStore.instance.load();
    RecentSearchStore.instance.load();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      _query = initial;
      _showResults = true;
      RecentSearchStore.instance.add(initial);
    }
  }

  @override
  void dispose() {
    _placeDebounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ───────────────────────── mode tabs & criteria ─────────────────────────

  /// New criteria for [mode]: budget and property type are tab-specific so
  /// they reset; the other filters carry over.
  SearchCriteria _carry(ListingMode mode, bool commercialRent) {
    final base = SearchCriteria.forMode(mode, commercialRent: commercialRent);
    final keepType = _criteria.type != null && mode.propertyTypes.contains(_criteria.type);
    return base.copyWith(
      type: keepType ? _criteria.type : null,
      bhk: mode == ListingMode.commercial ? <String>{} : _criteria.bhk,
      furnishing: _criteria.furnishing,
      postedBy: _criteria.postedBy,
      amenities: _criteria.amenities,
      verifiedOnly: _criteria.verifiedOnly,
    );
  }

  void _setMode(ListingMode mode) {
    if (mode == _mode) return;
    setState(() => _criteria = _carry(mode, _commercialRent));
  }

  void _setCommercialRent(bool rent) {
    if (rent == _commercialRent) return;
    setState(() {
      _commercialRent = rent;
      _criteria = _carry(ListingMode.commercial, rent);
    });
  }

  void _resetFilters() {
    setState(() => _criteria = SearchCriteria.forMode(_mode, commercialRent: _commercialRent));
  }

  Set<String> _toggled(Set<String> set, String value) {
    final next = Set<String>.of(set);
    if (!next.remove(value)) next.add(value);
    return next;
  }

  // ───────────────────────── results ─────────────────────────

  List<Property> get _filteredProperties {
    final all = PropertyStore.instance.all;
    if (_nearbyMode && _myLat != null && _myLng != null) {
      final matched = _criteria.copyWith(query: '').apply(all);
      final nearby = nearbyProperties(
        matched,
        lat: _myLat!,
        lng: _myLng!,
        radiusKm: _radiusKm,
        city: _myCity,
        locality: _myLocality,
      );
      return sortProperties(nearby, _sortOption);
    }
    return sortProperties(_criteria.copyWith(query: _query).apply(all), _sortOption);
  }

  // ───────────────────────── locations ─────────────────────────

  /// Listings of the current tab (falls back to everything while the tab is
  /// still empty so the chips never disappear on a small dataset).
  List<Property> get _modeProperties {
    final all = PropertyStore.instance.all;
    final inMode = SearchCriteria.forMode(_mode, commercialRent: _commercialRent).apply(all);
    return inMode.isNotEmpty ? inMode : List<Property>.of(all);
  }

  String? get _activeCity {
    final cities = citiesByListings(_modeProperties);
    final picked = _city?.toLowerCase();
    if (picked != null) {
      for (final c in cities) {
        if (c.toLowerCase() == picked) return c;
      }
    }
    return cities.isEmpty ? null : cities.first;
  }

  List<String> get _allLocations {
    final locations = PropertyStore.instance.all.map((p) => p.location).where((l) => l.trim().isNotEmpty).toSet().toList();
    locations.sort();
    return locations;
  }

  /// Locations of OUR listings that match what the user typed (place name,
  /// city, locality, title or BHK, e.g. "2 bhk"), best matches first.
  List<String> get _locationSuggestions {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final starts = <String>[];
    final others = <String>[];
    final seen = <String>{};
    for (final p in PropertyStore.instance.all) {
      final loc = p.location.trim();
      if (loc.isEmpty || seen.contains(loc.toLowerCase())) continue;
      final locLower = loc.toLowerCase();
      final matchesPlace = locLower.contains(q) ||
          p.locality.toLowerCase().contains(q) ||
          p.city.toLowerCase().contains(q);
      final matchesListing = p.title.toLowerCase().contains(q) || p.bhk.toLowerCase().contains(q);
      if (!matchesPlace && !matchesListing) continue;
      seen.add(locLower);
      (locLower.startsWith(q) ? starts : others).add(loc);
    }
    starts.sort();
    others.sort();
    return [...starts, ...others].take(8).toList();
  }

  /// Online place suggestions can be from anywhere in India. Keep only the
  /// ones near our listings (within 60 km of a listing, or in a city where
  /// we have listings).
  List<PlaceSuggestion> _nearListings(List<PlaceSuggestion> places) {
    final all = PropertyStore.instance.all;
    final anchors = all.where((p) => p.hasMapPosition).toList();
    final cities = citiesByListings(all).map((c) => c.toLowerCase()).toList();
    if (anchors.isEmpty && cities.isEmpty) return places;

    bool isNear(PlaceSuggestion s) {
      for (final p in anchors) {
        if (haversineKm(s.lat, s.lng, p.latitude, p.longitude) <= 60) return true;
      }
      final name = s.displayName.toLowerCase();
      return cities.any(name.contains);
    }

    return places.where(isNear).toList();
  }

  /// Runs the search for [text] (sets the box, saves it to recents, shows results).
  void _commitSearch(String text) {
    final q = text.trim();
    _controller.text = q;
    _placeDebounce?.cancel();
    setState(() {
      _nearbyMode = false;
      _query = q;
      _showSuggestions = false;
      _placeMatches = [];
      _showResults = true;
    });
    if (q.isNotEmpty) RecentSearchStore.instance.add(q);
    _searchFocusNode.unfocus();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _nearbyMode = false;
      _query = value;
      _showSuggestions = value.isNotEmpty;
    });
    _placeDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _placeMatches = []);
      return;
    }
    _placeDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _isSearchingPlace = true);
      var results = _nearListings(await PlaceAutocompleteService.instance.search(value));
      // Nothing close by? Retry inside the city where we have the most listings.
      final city = _activeCity;
      if (results.isEmpty && city != null) {
        results = _nearListings(await PlaceAutocompleteService.instance.search('$value, $city'));
      }
      if (!mounted) return;
      setState(() {
        _placeMatches = results;
        _isSearchingPlace = false;
      });
    });
  }

  Future<void> _pickCity() async {
    final cities = citiesByListings(_modeProperties);
    if (cities.isEmpty) return;
    final active = _activeCity;
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('Select city', style: AppTextStyles.h3),
              ),
              for (final c in cities)
                ListTile(
                  title: Text(c),
                  trailing: c == active ? const Icon(Icons.check, color: AppColors.primary) : null,
                  onTap: () => Navigator.pop(sheetContext, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _city = picked);
  }

  /// Search-bar location icon: GPS -> address -> show properties nearby.
  Future<void> _useCurrentLocation() async {
    if (_isLocating) return;
    _searchFocusNode.unfocus();
    setState(() => _isLocating = true);

    final res = await LocationService.instance.getCurrent();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _isLocating = false);
      _showLocationError(res.failure!);
      return;
    }

    final addr = await PlaceAutocompleteService.instance.reverse(res.lat!, res.lng!);
    if (!mounted) return;

    final label = [addr?.locality ?? '', addr?.city ?? ''].where((e) => e.isNotEmpty).join(', ');
    setState(() {
      _isLocating = false;
      _nearbyMode = true;
      _myLat = res.lat;
      _myLng = res.lng;
      _myCity = addr?.city ?? '';
      _myLocality = addr?.locality ?? '';
      _nearbyLabel = label.isEmpty ? 'your location' : label;
      _controller.text = label.isEmpty ? 'Current location' : label;
      _query = '';
      _showSuggestions = false;
      _placeMatches = [];
      _showResults = true;
      if (_myCity.isNotEmpty) _city = _myCity;
    });
  }

  void _showLocationError(LocationFailure failure) {
    String message;
    bool canOpenSettings = false;
    switch (failure) {
      case LocationFailure.serviceDisabled:
        message = 'Location is turned off. Please enable GPS.';
        canOpenSettings = true;
      case LocationFailure.denied:
        message = 'Location permission is needed to find properties near you.';
      case LocationFailure.deniedForever:
        message = 'Location permission is blocked. Enable it from app settings.';
        canOpenSettings = true;
      case LocationFailure.timeout:
        message = 'Could not get your location. Please try again outdoors.';
      case LocationFailure.unknown:
        message = 'Could not fetch your location.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: canOpenSettings
            ? SnackBarAction(
                label: 'Settings',
                onPressed: () => LocationService.instance.openSettingsFor(failure),
              )
            : null,
      ),
    );
  }

  // ───────────────────────── save / sort ─────────────────────────

  Future<void> _saveCurrentSearch() async {
    final fallback = [_mode.label, if (_criteria.type != null) _criteria.type!].join(' · ');
    final nameController = TextEditingController(text: _query.trim().isNotEmpty ? _query.trim() : fallback);
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
      criteria: _criteria.copyWith(query: _query),
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

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final results = _showResults ? _filteredProperties : const <Property>[];

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
        ],
      ),
      body: Column(
        children: [
          _buildModeTabs(),
          Expanded(child: _showResults ? _buildResultsView(results) : _buildFiltersView()),
        ],
      ),
    );
  }

  /// 99acres-style Buy / Rent / Commercial tabs.
  Widget _buildModeTabs() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (final m in ListingMode.values)
            Expanded(
              child: InkWell(
                onTap: () => _setMode(m),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: m == _mode ? AppColors.primary : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    m.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: m == _mode ? FontWeight.w700 : FontWeight.w500,
                      color: m == _mode ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ───────────────────────── small widgets ─────────────────────────

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return FilterChip(
      label: Text(label),
      avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? Colors.white : AppColors.textSecondary),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceSoft,
      side: BorderSide.none,
      labelStyle: TextStyle(
        fontSize: 13,
        color: selected ? Colors.white : AppColors.textPrimary,
      ),
      onSelected: (_) => onTap(),
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h3.copyWith(fontSize: 15)),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _wrapChips(List<Widget> chips) => Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: chips);

  Widget _buildSearchBox() {
    return Container(
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
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search locality, project or city',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: _onQueryChanged,
              onSubmitted: _commitSearch,
              onTap: () => setState(() => _showSuggestions = _query.isNotEmpty),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _controller.clear();
                _nearbyMode = false;
                _query = '';
                _showSuggestions = false;
                _placeMatches = [];
              }),
              child: const Icon(Icons.close, size: 18, color: AppColors.textHint),
            ),
          Tooltip(
            message: 'Use my current location',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isLocating ? null : _useCurrentLocation,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _isLocating
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 22, color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    final listings = _locationSuggestions;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      constraints: const BoxConstraints(maxHeight: 280),
      child: (listings.isEmpty && _placeMatches.isEmpty && !_isSearchingPlace)
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
                if (listings.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                    child: Text('In Our Listings', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  for (final loc in listings)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.home_work_outlined, size: 18, color: AppColors.primary),
                      title: Text(loc, style: AppTextStyles.bodySmall),
                      onTap: () => _commitSearch(loc),
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
                      title: Text(place.displayName,
                          style: AppTextStyles.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      // Listings store "Locality, City", so search by the
                      // place's own name (first part), not the long OSM address.
                      onTap: () => _commitSearch(place.displayName.split(',').first),
                    ),
                ],
              ],
            ),
    );
  }

  /// Commercial tab: for sale / for rent.
  Widget _buildCommercialToggle() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        children: [
          _chip('For Sale', !_commercialRent, () => _setCommercialRent(false)),
          const SizedBox(width: AppSpacing.sm),
          _chip('For Rent', _commercialRent, () => _setCommercialRent(true)),
        ],
      ),
    );
  }

  /// Popular localities of the selected city (chips), driven by real listings.
  Widget _buildPopularLocalities() {
    final city = _activeCity;
    final localities = popularLocalities(_modeProperties, city: city, limit: 10);
    if (localities.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Popular Localities', style: AppTextStyles.h3.copyWith(fontSize: 15)),
              ),
              if (city != null)
                InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  onTap: _pickCity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_city, size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(city,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                        const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _wrapChips([
            for (final loc in localities)
              ActionChip(
                avatar: const Icon(Icons.add, size: 16, color: AppColors.primary),
                label: Text(loc),
                backgroundColor: AppColors.surfaceSoft,
                side: BorderSide.none,
                labelStyle: AppTextStyles.bodySmall,
                onPressed: () => _commitSearch(loc),
              ),
          ]),
        ],
      ),
    );
  }

  /// Saved on the device (RecentSearchStore), survives an app restart.
  Widget _buildRecentSearches() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: RecentSearchStore.instance.searches,
      builder: (context, recents, _) {
        if (recents.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Recent Searches', style: AppTextStyles.h3.copyWith(fontSize: 15))),
                  TextButton(
                    onPressed: RecentSearchStore.instance.clear,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              _wrapChips([
                for (final s in recents)
                  InputChip(
                    avatar: const Icon(Icons.history, size: 16, color: AppColors.textSecondary),
                    label: Text(s),
                    backgroundColor: AppColors.surfaceSoft,
                    side: BorderSide.none,
                    labelStyle: AppTextStyles.bodySmall,
                    onPressed: () => _commitSearch(s),
                    onDeleted: () => RecentSearchStore.instance.remove(s),
                    deleteIconColor: AppColors.textHint,
                  ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBudget() {
    final c = _criteria;
    final max = c.budgetMax;
    final start = c.budgetStart.clamp(0.0, max).toDouble();
    final end = c.budgetEnd.clamp(0.0, max).toDouble();
    final suffix = c.isRent ? '/mo' : '';
    final endLabel = SearchCriteria.formatPrice(end) + (c.budgetOpenEnded ? '+' : '') + suffix;
    return Column(
      children: [
        RangeSlider(
          values: RangeValues(start, end),
          min: 0,
          max: max,
          divisions: c.isRent ? 40 : 35,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.surfaceSoft,
          labels: RangeLabels(
            SearchCriteria.formatPrice(start) + suffix,
            endLabel,
          ),
          onChanged: (v) => setState(() => _criteria = _criteria.copyWith(budgetStart: v.start, budgetEnd: v.end)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(SearchCriteria.formatPrice(start) + suffix, style: AppTextStyles.bodySmall),
            Text(endLabel, style: AppTextStyles.bodySmall),
          ],
        ),
      ],
    );
  }

  Widget _buildFiltersView() {
    final c = _criteria;
    final isPlot = c.type == 'Plot';
    final showBhk = _mode != ListingMode.commercial && !isPlot;
    final filterCount = c.activeFilterCount;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _buildSearchBox(),
        if (_showSuggestions) _buildSuggestions(),
        if (_mode == ListingMode.commercial) _buildCommercialToggle(),
        _buildPopularLocalities(),
        _buildRecentSearches(),
        const SizedBox(height: AppSpacing.lg),

        // EMI Calculator quick-access (buying only)
        if (!c.isRent) ...[
          const _EmiCalculatorCard(),
          const SizedBox(height: AppSpacing.lg),
        ],

        Row(
          children: [
            Expanded(
              child: Text(
                filterCount > 0 ? 'Filters ($filterCount)' : 'Filters',
                style: AppTextStyles.h3,
              ),
            ),
            if (filterCount > 0) TextButton(onPressed: _resetFilters, child: const Text('Reset all')),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        _section(
          'Property Type',
          _wrapChips([
            for (final t in _mode.propertyTypes)
              _chip(
                t,
                c.type == t,
                () => setState(() => _criteria = c.type == t ? c.copyWith(clearType: true) : c.copyWith(type: t)),
              ),
          ]),
        ),

        _section(c.isRent ? 'Budget (per month)' : 'Budget', _buildBudget()),

        if (showBhk)
          _section(
            'BHK Type',
            _wrapChips([
              for (final b in searchBhkOptions)
                _chip(b, c.bhk.contains(b), () => setState(() => _criteria = c.copyWith(bhk: _toggled(c.bhk, b)))),
            ]),
          ),

        if (!isPlot)
          _section(
            'Furnishing',
            _wrapChips([
              for (final f in searchFurnishingOptions)
                _chip(f, c.furnishing.contains(f),
                    () => setState(() => _criteria = c.copyWith(furnishing: _toggled(c.furnishing, f)))),
            ]),
          ),

        _section(
          'Posted By',
          _wrapChips([
            for (final e in searchPostedByOptions.entries)
              _chip(e.value, c.postedBy.contains(e.key),
                  () => setState(() => _criteria = c.copyWith(postedBy: _toggled(c.postedBy, e.key)))),
          ]),
        ),

        _section(
          'Amenities',
          _wrapChips([
            for (final a in searchAmenityOptions)
              _chip(a.label, c.amenities.contains(a.key),
                  () => setState(() => _criteria = c.copyWith(amenities: _toggled(c.amenities, a.key))),
                  icon: a.icon),
          ]),
        ),

        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: SwitchListTile(
            value: c.verifiedOnly,
            activeThumbColor: AppColors.primary,
            secondary: const Icon(Icons.verified_outlined, color: AppColors.verifiedBadge),
            title: Text('Verified properties only', style: AppTextStyles.bodyMedium),
            onChanged: (v) => setState(() => _criteria = c.copyWith(verifiedOnly: v)),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _nearbyMode ? setState(() => _showResults = true) : _commitSearch(_controller.text),
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

  Widget _buildRadiusChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          for (final km in const [2.0, 5.0, 10.0, 25.0, 50.0])
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text('${km.toInt()} km'),
                selected: _radiusKm == km,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(color: _radiusKm == km ? Colors.white : AppColors.textPrimary),
                onSelected: (_) => setState(() => _radiusKm = km),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsView(List<Property> results) {
    final filterCount = _criteria.activeFilterCount;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  _nearbyMode ? '${results.length} near $_nearbyLabel' : '${results.length} Properties Found',
                  style: AppTextStyles.h3.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _openSortSheet,
                    icon: const Icon(Icons.swap_vert, size: 16),
                    label: const Text('Sort'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _showResults = false),
                    icon: Badge(
                      isLabelVisible: filterCount > 0,
                      label: Text('$filterCount'),
                      child: const Icon(Icons.tune, size: 16),
                    ),
                    label: const Text('Filter'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_nearbyMode) _buildRadiusChips(),
        const Divider(height: 1),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    _nearbyMode
                        ? 'No properties within ${_radiusKm.toInt()} km.\nTry a bigger radius.'
                        : 'No properties found',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final property = results[index];
                    final km = (_nearbyMode && _myLat != null && _myLng != null)
                        ? distanceKmTo(property, _myLat!, _myLng!)
                        : null;
                    final card = PropertyCard(
                      property: property,
                      onTap: () => context.push('/property/${property.id}'),
                      onFavoriteTap: () => PropertyStore.instance.toggleFavorite(property.id),
                    );
                    if (km == null) return card;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.near_me, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(formatDistance(km),
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        card,
                      ],
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