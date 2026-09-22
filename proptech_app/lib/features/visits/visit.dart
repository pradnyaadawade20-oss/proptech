enum VisitStatus { pending, confirmed, completed, cancelled }

class Visit {
  final String id;
  final String propertyTitle;
  final String propertyImageUrl;
  final String visitorName;
  final DateTime scheduledAt;
  final VisitStatus status;

  const Visit({
    required this.id,
    required this.propertyTitle,
    required this.propertyImageUrl,
    required this.visitorName,
    required this.scheduledAt,
    required this.status,
  });
}

final List<Visit> dummyVisits = [
  Visit(
    id: '1',
    propertyTitle: '2 BHK Apartment',
    propertyImageUrl: 'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2',
    visitorName: 'Rahul Sharma',
    scheduledAt: DateTime.now().add(const Duration(days: 1, hours: 3)),
    status: VisitStatus.pending,
  ),
  Visit(
    id: '2',
    propertyTitle: '1 BHK Apartment',
    propertyImageUrl: 'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688',
    visitorName: 'Priya Verma',
    scheduledAt: DateTime.now().add(const Duration(days: 2)),
    status: VisitStatus.confirmed,
  ),
  Visit(
    id: '3',
    propertyTitle: 'PG for Boys',
    propertyImageUrl: 'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267',
    visitorName: 'Aman Gupta',
    scheduledAt: DateTime.now().subtract(const Duration(days: 1)),
    status: VisitStatus.completed,
  ),
];