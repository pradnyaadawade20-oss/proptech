/// Views and interest for one of the owner's listings (GET /api/properties/my-stats).
class PropertyStats {
  final int views, interested, saved, enquiries;
  const PropertyStats({this.views = 0, this.interested = 0, this.saved = 0, this.enquiries = 0});

  factory PropertyStats.fromJson(Map<String, dynamic> j) => PropertyStats(
        views: (j['views'] as num?)?.toInt() ?? 0,
        interested: (j['interested'] as num?)?.toInt() ?? 0,
        saved: (j['saved'] as num?)?.toInt() ?? 0,
        enquiries: (j['enquiries'] as num?)?.toInt() ?? 0,
      );
}