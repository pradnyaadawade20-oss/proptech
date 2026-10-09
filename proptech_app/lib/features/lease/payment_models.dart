double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;
String _s(dynamic v) => v?.toString() ?? '';
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class OwnerBank {
  final String accountHolder, accountLast4, ifsc, status, statusDetail;
  const OwnerBank({
    required this.accountHolder,
    required this.accountLast4,
    required this.ifsc,
    required this.status,
    required this.statusDetail,
  });

  /// pending | active | verification_failed | inactive
  bool get ready => status == 'active';

  factory OwnerBank.fromJson(Map<String, dynamic> j) => OwnerBank(
        accountHolder: _s(j['account_holder']),
        accountLast4: _s(j['account_last4']),
        ifsc: _s(j['ifsc']),
        status: _s(j['status']),
        statusDetail: _s(j['status_detail']),
      );
}

class CheckoutSession {
  final String orderId, paymentSessionId, environment; // environment: SANDBOX | PRODUCTION
  final double amount;
  final bool resumed;
  const CheckoutSession({
    required this.orderId,
    required this.paymentSessionId,
    required this.environment,
    required this.amount,
    required this.resumed,
  });

  factory CheckoutSession.fromJson(Map<String, dynamic> j) => CheckoutSession(
        orderId: _s(j['order_id']),
        paymentSessionId: _s(j['payment_session_id']),
        environment: _s(j['environment']),
        amount: _n(j['amount']),
        resumed: j['resumed'] == true,
      );
}

class PaymentOrder {
  final String id, orderId, kind, leaseId, propertyTitle, periodLabel, payerName;
  final String status; // created | paid | expired | cancelled | superseded | duplicate
  final String paymentMethod, failureReason, cfPaymentId;
  final double amount, ownerAmount, platformFee;
  final int attempts;
  final String settlementStatus, settlementUtr; // pending | settled | failed
  final double? settlementAmount;
  final DateTime? paidAt, settledAt, createdAt;

  const PaymentOrder({
    required this.id,
    required this.orderId,
    required this.kind,
    required this.leaseId,
    required this.propertyTitle,
    required this.periodLabel,
    required this.payerName,
    required this.status,
    required this.paymentMethod,
    required this.failureReason,
    required this.cfPaymentId,
    required this.amount,
    required this.ownerAmount,
    required this.platformFee,
    required this.attempts,
    required this.settlementStatus,
    required this.settlementUtr,
    this.settlementAmount,
    this.paidAt,
    this.settledAt,
    this.createdAt,
  });

  String get title => kind == 'deposit' ? 'Security deposit' : (periodLabel.isEmpty ? 'Rent' : 'Rent - $periodLabel');

  factory PaymentOrder.fromJson(Map<String, dynamic> j) => PaymentOrder(
        id: _s(j['id']),
        orderId: _s(j['order_id']),
        kind: _s(j['kind']),
        leaseId: _s(j['lease_id']),
        propertyTitle: _s(j['property_title']),
        periodLabel: _s(j['period_label']),
        payerName: _s(j['payer_name']),
        status: _s(j['status']),
        paymentMethod: _s(j['payment_method']),
        failureReason: _s(j['failure_reason']),
        cfPaymentId: _s(j['cf_payment_id']),
        amount: _n(j['amount']),
        ownerAmount: _n(j['owner_amount']),
        platformFee: _n(j['platform_fee']),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        settlementStatus: _s(j['settlement_status']),
        settlementUtr: _s(j['settlement_utr']),
        settlementAmount: j['settlement_amount'] == null ? null : _n(j['settlement_amount']),
        paidAt: _dt(j['paid_at']),
        settledAt: _dt(j['settled_at']),
        createdAt: _dt(j['created_at']),
      );
}

/// Answer of GET /api/payments/orders/:orderId
class OrderOutcome {
  final PaymentOrder order;
  final String outcome; // success | failed | pending | expired | duplicate
  final String message;
  const OrderOutcome({required this.order, required this.outcome, required this.message});

  bool get finished => outcome != 'pending';

  factory OrderOutcome.fromJson(Map<String, dynamic> j) => OrderOutcome(
        order: PaymentOrder.fromJson(j['order'] as Map<String, dynamic>),
        outcome: _s(j['outcome']),
        message: _s(j['message']),
      );
}

class SettlementTotals {
  final double collected, settled, pending, platformFees;
  const SettlementTotals({this.collected = 0, this.settled = 0, this.pending = 0, this.platformFees = 0});

  factory SettlementTotals.fromJson(Map<String, dynamic> j) => SettlementTotals(
        collected: _n(j['collected_total']),
        settled: _n(j['settled_total']),
        pending: _n(j['pending_total']),
        platformFees: _n(j['platform_fees']),
      );
}