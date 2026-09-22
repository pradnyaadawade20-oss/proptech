/// A single point in a property's price-change history, used to draw the
/// "Price Trend" chart on the detail screen.
class PricePoint {
  final DateTime date;
  final double price;
  const PricePoint({required this.date, required this.price});

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'price': price,
      };

  factory PricePoint.fromJson(Map<String, dynamic> json) => PricePoint(
        date: DateTime.parse(json['date'] as String),
        price: (json['price'] as num).toDouble(),
      );
}

/// A nearby point of interest (school, hospital, metro station, etc.) shown
/// on the property detail screen so buyers/renters know what's around.
class NearbyLandmark {
  final String name;
  final String type; // 'school' | 'hospital' | 'metro' | 'mall' | 'market' | 'park' | 'bus_stop'
  final double distanceKm;
  const NearbyLandmark({required this.name, required this.type, required this.distanceKm});

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'distanceKm': distanceKm,
      };

  factory NearbyLandmark.fromJson(Map<String, dynamic> json) => NearbyLandmark(
        name: json['name'] as String,
        type: json['type'] as String,
        distanceKm: (json['distanceKm'] as num).toDouble(),
      );
}

/// A single ownership-proof document attached to a listing (Sale Deed,
/// Property Tax Receipt, RERA Certificate, etc.) — the actual scanned
/// image, not just its name, so a buyer can open and inspect it.
class OwnershipDocument {
  final String name;
  final String imageUrl;
  final bool isVerified;
  const OwnershipDocument({required this.name, required this.imageUrl, this.isVerified = false});

  Map<String, dynamic> toJson() => {
        'name': name,
        'imageUrl': imageUrl,
        'isVerified': isVerified,
      };

  factory OwnershipDocument.fromJson(Map<String, dynamic> json) => OwnershipDocument(
        name: json['name'] as String,
        imageUrl: json['imageUrl'] as String,
        isVerified: json['isVerified'] as bool? ?? false,
      );
}