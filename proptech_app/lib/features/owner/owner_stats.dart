class OwnerStats {
  final int totalProperties;
  final int available;
  final int rented;
  final int sold;
  final int activeLeads;
  final int visitsThisWeek;

  OwnerStats({
    required this.totalProperties,
    required this.available,
    required this.rented,
    required this.sold,
    required this.activeLeads,
    required this.visitsThisWeek,
  });
}

final dummyOwnerStats = OwnerStats(
  totalProperties: 8,
  available: 5,
  rented: 2,
  sold: 1,
  activeLeads: 12,
  visitsThisWeek: 4,
);