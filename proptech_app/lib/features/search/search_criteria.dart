import '../properties/property.dart';
import 'locality_utils.dart';

/// The Buy / Rent / Commercial tabs of the search screen.
enum ListingMode {
  buy('Buy', ['Apartment', 'Villa', 'House', 'Plot']),
  rent('Rent', ['Apartment', 'Villa', 'House', 'PG']),
  commercial('Commercial', ['Office', 'Shop', 'Warehouse', 'Showroom']);

  const ListingMode(this.label, this.propertyTypes);
  final String label;
  final List<String> propertyTypes;
}

/// Who posted the listing: 'owner' | 'dealer' | 'builder', or null when the
/// Property model doesn't carry that information.
///
/// The Property model has no "posted by" field yet. Until it does, return it
/// here (e.g. `p.postedBy`) and the "Posted By" filter starts working. While
/// this returns null, that filter never hides a listing.
String? postedByOf(Property p) => null;

bool _isRentListing(Property p) => p.priceUnit.toLowerCase().contains('month');

/// Everything the search screen can filter on. Immutable: use [copyWith].
class SearchCriteria {
  static const double buyBudgetMax = 35000000;
  static const double rentBudgetMax = 200000;

  /// null = no Buy/Rent/Commercial restriction (searches saved before tabs existed).
  final ListingMode? mode;
  final bool commercialRent;
  final String query;
  final String? type;
  final double budgetStart;
  final double budgetEnd;
  final Set<String> bhk;
  final Set<String> furnishing;
  final Set<String> postedBy;
  final Set<String> amenities;
  final bool verifiedOnly;

  const SearchCriteria({
    this.mode,
    this.commercialRent = false,
    this.query = '',
    this.type,
    this.budgetStart = 0,
    this.budgetEnd = buyBudgetMax,
    this.bhk = const {},
    this.furnishing = const {},
    this.postedBy = const {},
    this.amenities = const {},
    this.verifiedOnly = false,
  });

  /// Fresh criteria for a tab: full budget range, no other filters.
  factory SearchCriteria.forMode(ListingMode mode, {bool commercialRent = false}) {
    final rent = mode == ListingMode.rent || (mode == ListingMode.commercial && commercialRent);
    return SearchCriteria(
      mode: mode,
      commercialRent: commercialRent,
      budgetEnd: rent ? rentBudgetMax : buyBudgetMax,
    );
  }

  bool get isRent => mode == ListingMode.rent || (mode == ListingMode.commercial && commercialRent);
  double get budgetMax => isRent ? rentBudgetMax : buyBudgetMax;
  bool get budgetOpenEnded => budgetEnd >= budgetMax;

  /// Number of filters changed from their defaults (the search text isn't counted).
  int get activeFilterCount {
    var n = 0;
    if (type != null) n++;
    if (budgetStart > 0 || !budgetOpenEnded) n++;
    if (bhk.isNotEmpty) n++;
    if (furnishing.isNotEmpty) n++;
    if (postedBy.isNotEmpty) n++;
    if (amenities.isNotEmpty) n++;
    if (verifiedOnly) n++;
    return n;
  }

  SearchCriteria copyWith({
    String? query,
    String? type,
    bool clearType = false,
    double? budgetStart,
    double? budgetEnd,
    Set<String>? bhk,
    Set<String>? furnishing,
    Set<String>? postedBy,
    Set<String>? amenities,
    bool? verifiedOnly,
  }) {
    return SearchCriteria(
      mode: mode,
      commercialRent: commercialRent,
      query: query ?? this.query,
      type: clearType ? null : (type ?? this.type),
      budgetStart: budgetStart ?? this.budgetStart,
      budgetEnd: budgetEnd ?? this.budgetEnd,
      bhk: bhk ?? this.bhk,
      furnishing: furnishing ?? this.furnishing,
      postedBy: postedBy ?? this.postedBy,
      amenities: amenities ?? this.amenities,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
    );
  }

  // ───────────────────────── matching ─────────────────────────

  bool _matchesMode(Property p) {
    final m = mode;
    if (m == null) return true;
    final commercial = p.category == 'Commercial';
    switch (m) {
      case ListingMode.commercial:
        return commercial && _isRentListing(p) == commercialRent;
      case ListingMode.buy:
        return !commercial && !_isRentListing(p);
      case ListingMode.rent:
        return !commercial && _isRentListing(p);
    }
  }

  bool _matchesType(Property p) {
    final t = type;
    if (t == null) return true;
    switch (t) {
      case 'Apartment':
      case 'Villa':
      case 'House':
      case 'PG':
      case 'Office':
        return propertyMatchesType(p, t);
      default: // Plot, Shop, Warehouse, Showroom
        final needle = t.toLowerCase();
        return p.title.toLowerCase().contains(needle) ||
            p.category.toLowerCase().contains(needle) ||
            p.bhk.toLowerCase().contains(needle);
    }
  }

  bool _matchesQuery(Property p) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return p.title.toLowerCase().contains(q) ||
        p.location.toLowerCase().contains(q) ||
        p.city.toLowerCase().contains(q) ||
        p.locality.toLowerCase().contains(q);
  }

  bool matches(Property p) {
    if (!_matchesMode(p) || !_matchesQuery(p) || !_matchesType(p)) return false;
    if (p.price < budgetStart) return false;
    if (!budgetOpenEnded && p.price > budgetEnd) return false;
    if (bhk.isNotEmpty && !bhk.contains(p.bhk)) return false;
    if (furnishing.isNotEmpty && !furnishing.contains(p.furnishing)) return false;
    if (postedBy.isNotEmpty) {
      final who = postedByOf(p);
      if (who != null && !postedBy.contains(who)) return false;
    }
    if (amenities.isNotEmpty && !amenities.every(p.amenities.contains)) return false;
    if (verifiedOnly && !p.isVerified) return false;
    return true;
  }

  List<Property> apply(List<Property> input) => input.where(matches).toList();

  // ───────────────────────── display ─────────────────────────

  static String formatPrice(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(v % 10000000 == 0 ? 0 : 1)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(v % 100000 == 0 ? 0 : 1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    return '₹${v.toInt()}';
  }

  /// e.g. "Rent · Powai · Apartment · 2 BHK · Owner · ₹10K–₹50K/mo"
  String get summary {
    final parts = <String>[];
    final m = mode;
    if (m != null) {
      parts.add(m == ListingMode.commercial ? 'Commercial ${commercialRent ? 'Rent' : 'Sale'}' : m.label);
    }
    if (query.trim().isNotEmpty) parts.add(query.trim());
    if (type != null) parts.add(type!);
    if (bhk.isNotEmpty) parts.add(bhk.join(', '));
    if (furnishing.isNotEmpty) parts.add(furnishing.join(', '));
    if (postedBy.isNotEmpty) parts.add(postedBy.map((k) => searchPostedByOptions[k] ?? k).join(', '));
    if (amenities.isNotEmpty) parts.add('${amenities.length} amenit${amenities.length == 1 ? 'y' : 'ies'}');
    if (verifiedOnly) parts.add('Verified');
    final suffix = isRent ? '/mo' : '';
    parts.add('${formatPrice(budgetStart)}–${formatPrice(budgetEnd)}${budgetOpenEnded ? '+' : ''}$suffix');
    return parts.join(' · ');
  }

  // ───────────────────────── storage ─────────────────────────

  Map<String, dynamic> toJson() => {
        'mode': mode?.name,
        'commercialRent': commercialRent,
        'query': query,
        'type': type,
        'budgetStart': budgetStart,
        'budgetEnd': budgetEnd,
        'bhk': bhk.toList(),
        'furnishing': furnishing.toList(),
        'postedBy': postedBy.toList(),
        'amenities': amenities.toList(),
        'verifiedOnly': verifiedOnly,
      };

  /// Also reads old saved searches (flat query/type/budgetStart/budgetEnd, no mode).
  factory SearchCriteria.fromJson(Map<String, dynamic> json) {
    Set<String> set(String k) => (json[k] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
    final modeName = json['mode'] as String?;
    ListingMode? mode;
    for (final m in ListingMode.values) {
      if (m.name == modeName) mode = m;
    }
    return SearchCriteria(
      mode: mode,
      commercialRent: json['commercialRent'] as bool? ?? false,
      query: json['query'] as String? ?? '',
      type: json['type'] as String?,
      budgetStart: (json['budgetStart'] as num?)?.toDouble() ?? 0,
      budgetEnd: (json['budgetEnd'] as num?)?.toDouble() ?? buyBudgetMax,
      bhk: set('bhk'),
      furnishing: set('furnishing'),
      postedBy: set('postedBy'),
      amenities: set('amenities'),
      verifiedOnly: json['verifiedOnly'] as bool? ?? false,
    );
  }
}