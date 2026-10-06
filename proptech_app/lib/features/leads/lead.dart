/// A buyer's enquiry on a property (backs the owner's Leads screen).
class Lead {
  final String id;
  final String propertyId;
  final String propertyTitle;
  final String propertyImageUrl;
  final String ownerId;
  final String buyerId;
  final String name;
  final String phone;
  final String email;
  final String message;
  final String source; // contact | call | chat | visit
  final String status; // new | contacted | visited | closed
  final DateTime createdAt;
  final DateTime updatedAt;

  const Lead({
    required this.id,
    required this.propertyId,
    required this.propertyTitle,
    required this.propertyImageUrl,
    required this.ownerId,
    required this.buyerId,
    required this.name,
    required this.phone,
    required this.email,
    required this.message,
    required this.source,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Lead.fromJson(Map<String, dynamic> j) => Lead(
        id: j['id'] as String,
        propertyId: j['property_id'] as String? ?? '',
        propertyTitle: j['property_title'] as String? ?? '',
        propertyImageUrl: j['property_image_url'] as String? ?? '',
        ownerId: j['owner_id'] as String? ?? '',
        buyerId: j['buyer_id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        email: j['email'] as String? ?? '',
        message: j['message'] as String? ?? '',
        source: j['source'] as String? ?? 'contact',
        status: j['status'] as String? ?? 'new',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}

class LeadCounts {
  final int all, newCount, contacted, visited, closed;
  const LeadCounts({this.all = 0, this.newCount = 0, this.contacted = 0, this.visited = 0, this.closed = 0});

  factory LeadCounts.fromJson(Map<String, dynamic> j) => LeadCounts(
        all: (j['all'] as num?)?.toInt() ?? 0,
        newCount: (j['new'] as num?)?.toInt() ?? 0,
        contacted: (j['contacted'] as num?)?.toInt() ?? 0,
        visited: (j['visited'] as num?)?.toInt() ?? 0,
        closed: (j['closed'] as num?)?.toInt() ?? 0,
      );

  int forStatus(String status) {
    switch (status) {
      case 'new':
        return newCount;
      case 'contacted':
        return contacted;
      case 'visited':
        return visited;
      case 'closed':
        return closed;
      default:
        return all;
    }
  }
}

class LeadPage {
  final List<Lead> items;
  final LeadCounts counts;
  final int total;
  final bool hasMore;
  const LeadPage({required this.items, required this.counts, required this.total, required this.hasMore});
}

/// Result of sending an enquiry: the owner's contact so the app can call/chat.
class LeadResult {
  final Lead lead;
  final bool isNew;
  final String ownerName;
  final String ownerPhone;
  const LeadResult({required this.lead, required this.isNew, required this.ownerName, required this.ownerPhone});
}