import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';
import '../lease/online_payment.dart';

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

/// Fallback packages (same as backend models.SubscriptionPlans).
const List<SubscriptionPlan> defaultPlans = [
  SubscriptionPlan(id: 'monthly', name: 'Pro Monthly', price: 499, months: 1),
  SubscriptionPlan(id: 'yearly', name: 'Pro Yearly', price: 4999, months: 12),
];

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
    var plans = (data['plans'] as List<dynamic>? ?? [])
        .map((e) => SubscriptionPlan.fromJson(e as Map<String, dynamic>))
        .toList();
    // Server did not send any plans (older deploy / empty list): still show the
    // two packages. Keep these in sync with SubscriptionPlans in the Go backend.
    if (plans.isEmpty) plans = List.of(defaultPlans);
    return BrokerSubscriptionData(sub, plans);
  }

  Exception _err(DioException e) {
    final d = e.response?.data;
    if (d is Map && d['error'] != null) return Exception(d['error'].toString());
    final code = e.response?.statusCode;
    if (code == 404) {
      return Exception('Subscription is not available on the server yet. Please try again after the app server is updated.');
    }
    if (code == 401 || code == 403) return Exception('Please log in again and retry.');
    if (code != null && code >= 500) return Exception('Server error. Please try again in a moment.');
    return Exception('Could not reach the server. Check your internet and try again.');
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

  /// Starts a Cashfree order for [planId] ('monthly' or 'yearly'). The plan is
  /// activated by the server itself once the payment is confirmed - after the
  /// payment finishes just call [getMine] again.
  Future<CheckoutInfo> checkout(String planId) async {
    final id = await _userId();
    try {
      final r = await _dio.post('/api/broker/$id/subscription/checkout', data: {'plan': planId});
      return CheckoutInfo.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _err(e);
    }
  }
}