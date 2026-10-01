import 'search_criteria.dart';

/// A user-saved search. When new properties matching [criteria] get added,
/// the user is alerted ("naya property is criteria ka aaye to notify karo").
///
/// [criteria] carries everything the search screen can filter on (Buy/Rent
/// tab, location, type, budget, BHK, furnishing, posted by, amenities,
/// verified-only), so a saved search matches exactly what the screen shows.
class SavedSearch {
  final String id;
  final String name;
  final SearchCriteria criteria;
  final DateTime createdAt;

  /// Ids of properties already shown to the user for this search — used to
  /// figure out which matches are "new" since the search was last checked.
  final List<String> seenPropertyIds;

  const SavedSearch({
    required this.id,
    required this.name,
    required this.criteria,
    required this.createdAt,
    this.seenPropertyIds = const [],
  });

  SavedSearch copyWith({List<String>? seenPropertyIds}) {
    return SavedSearch(
      id: id,
      name: name,
      criteria: criteria,
      createdAt: createdAt,
      seenPropertyIds: seenPropertyIds ?? this.seenPropertyIds,
    );
  }

  /// e.g. "Rent · Powai · Apartment · 2 BHK · Owner · ₹10K–₹50K"
  String get summary => criteria.summary;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'criteria': criteria.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'seenPropertyIds': seenPropertyIds,
      };

  /// Also reads searches saved before the new filters existed (flat
  /// query / type / budgetStart / budgetEnd fields, no Buy/Rent tab).
  factory SavedSearch.fromJson(Map<String, dynamic> json) {
    final c = json['criteria'];
    return SavedSearch(
      id: json['id'] as String,
      name: json['name'] as String,
      criteria: c is Map
          ? SearchCriteria.fromJson(Map<String, dynamic>.from(c))
          : SearchCriteria.fromJson(json),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      seenPropertyIds: (json['seenPropertyIds'] as List?)?.cast<String>() ?? const [],
    );
  }
}