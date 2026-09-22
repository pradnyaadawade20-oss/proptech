/// A user-saved search criteria set. When new properties matching this
/// criteria get added, the user should be alerted ("naya property is
/// criteria ka aaye to notify karo").
class SavedSearch {
  final String id;
  final String name;
  final String query;
  final String? type; // Apartment / Villa / PG / House / Office / null
  final double budgetStart;
  final double budgetEnd;
  final DateTime createdAt;

  /// Ids of properties already shown to the user for this search — used to
  /// figure out which matches are "new" since the search was last checked.
  final List<String> seenPropertyIds;

  const SavedSearch({
    required this.id,
    required this.name,
    required this.query,
    required this.type,
    required this.budgetStart,
    required this.budgetEnd,
    required this.createdAt,
    this.seenPropertyIds = const [],
  });

  SavedSearch copyWith({List<String>? seenPropertyIds}) {
    return SavedSearch(
      id: id,
      name: name,
      query: query,
      type: type,
      budgetStart: budgetStart,
      budgetEnd: budgetEnd,
      createdAt: createdAt,
      seenPropertyIds: seenPropertyIds ?? this.seenPropertyIds,
    );
  }

  /// Short human-readable summary of the criteria, e.g. "Powai, Mumbai · Apartment · ₹25K–₹50K".
  String get summary {
    final parts = <String>[];
    if (query.trim().isNotEmpty) parts.add(query.trim());
    if (type != null) parts.add(type!);
    parts.add('${_formatPrice(budgetStart)}–${_formatPrice(budgetEnd)}');
    return parts.join(' · ');
  }

  static String _formatPrice(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(v % 10000000 == 0 ? 0 : 1)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(v % 100000 == 0 ? 0 : 1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    return '₹${v.toInt()}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'query': query,
        'type': type,
        'budgetStart': budgetStart,
        'budgetEnd': budgetEnd,
        'createdAt': createdAt.toIso8601String(),
        'seenPropertyIds': seenPropertyIds,
      };

  factory SavedSearch.fromJson(Map<String, dynamic> json) => SavedSearch(
        id: json['id'] as String,
        name: json['name'] as String,
        query: json['query'] as String? ?? '',
        type: json['type'] as String?,
        budgetStart: (json['budgetStart'] as num).toDouble(),
        budgetEnd: (json['budgetEnd'] as num).toDouble(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        seenPropertyIds: (json['seenPropertyIds'] as List?)?.cast<String>() ?? const [],
      );
}