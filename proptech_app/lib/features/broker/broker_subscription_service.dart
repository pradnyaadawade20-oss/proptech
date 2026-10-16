import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';

class SubscriptionPlan {
  final String id; // monthly | yearly
  final String name;
  final int price;
  final int months;
  const SubscriptionPlan({required this.id, required this.name, required this.price, required this.months});

  factory SubscriptionPlan.fromJson(Map<String, dynamic> j) => SubscriptionPlan(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        price: (j['price'] as num?)?.toInt() ?? 0,
        months: (j['months'] as num?)?.toInt() ?? 1,
      );
}

class BrokerSubscription {
  final String planName;
  final String planType; // free | monthly | yearly
  final int listingsUsed;
  final int listingsLimit;
  final bool unlimited;
  final bool isActive;
  final bool expired;
  final bool canAddListing;
  final DateTime? expiresAt;

  const BrokerSubscription({
    required this.planName,
    required this.planType,
    required this.listingsUsed,
    required this.listingsLimit,
    required this.unlimited,
    required this.isActive,
    required this.expired,
    required this.canAddListing,
    required this.expiresAt,
  });

  factory BrokerSubscription.fromJson(Map<String, dynamic> j) => BrokerSubscription(
        planName: j['plan_name'] as String? ?? 'Free Plan',
        planType: j['plan_type'] as String? ?? 'free',
        listingsUsed: (j['listings_used'] as num?)?.toInt() ?? 0,
        listingsLimit: (j['listings_limit'] as num?)?.toInt() ?? 3,
        unlimited: j['unlimited'] as bool? ?? false,
        isActive: j['is_active'] as bool? ?? false,
        expired: j['expired'] as bool? ?? false,
        canAddListing: j['can_add_listing'] as bool? ?? true,
        expiresAt: j['expires_at'] == null ? null : DateTime.tryParse(j['expires_at'] as String)?.toLocal(),
      );

  /// "3 of 3 listings used" / "5 listings • Unlimited"
  String get usageLabel =>
      unlimited ? '$listingsUsed listings • Unlimited' : '$listingsUsed of $listingsLimit listings used';

  String? get expiryLabel {
    final d = expiresAt;
    if (d == null) return null;
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}

class BrokerSubscriptionData {
  final BrokerSubscription subscription;
  final List<SubscriptionPlan> plans;
  const BrokerSubscriptionData(this.subscription, this.plans);
}

/// Talks to /api/broker/:id/subscription*.
class BrokerSubscriptionService {
  BrokerSubscriptionService._();
  static final BrokerSubscriptionService instance = BrokerSubscriptionService._();

  final Dio _dio = ApiClient.instance.dio;

  Future<String> _userId() async {
    final id = await TokenStore.instance.getUserId();
    if (id == null) throw Exception('Not logged in.');
    return id;
  }

  BrokerSubscriptionData _parse(dynamic data) {
    final sub = BrokerSubscription.fromJson(data['subscription'] as Map<String, dynamic>);
    final plans = (data['plans'] as List<dynamic>? ?? [])
        .map((e) => SubscriptionPlan.fromJson(e as Map<String, dynamic>))
        .toList();
    return BrokerSubscriptionData(sub, plans);
  }

  Exception _err(DioException e) {
    final d = e.response?.data;
    return Exception(d is Map && d['error'] != null ? d['error'].toString() : (e.message ?? 'Something went wrong.'));
  }

  Future<BrokerSubscriptionData> getMine() async {
    final id = await _userId();
    try {
      final r = await _dio.get('/api/broker/$id/subscription');
      return _parse(r.data);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// [planId] is 'monthly' or 'yearly'. Hook the payment gateway in before
  /// this call and pass its reference as [paymentRef].
  Future<BrokerSubscriptionData> subscribe(String planId, {String paymentRef = ''}) async {
    final id = await _userId();
    try {
      final r = await _dio.post(
        '/api/broker/$id/subscription/subscribe',
        data: {'plan': planId, 'payment_ref': paymentRef},
      );
      return _parse(r.data);
    } on DioException catch (e) {
      throw _err(e);
    }
  }
}