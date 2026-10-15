import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import 'lease_widgets.dart';
import 'online_payment.dart';
import 'receipt_screen.dart';

DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// The agent's fee, agreed before the rental agreement and paid by the tenant after both sign.
class CommissionInfo {
  final double amount;
  final String note, status, paymentMethod, reference, receiptNo;
  final DateTime? paidAt;
  const CommissionInfo({
    required this.amount,
    required this.note,
    required this.status,
    required this.paymentMethod,
    required this.reference,
    required this.receiptNo,
    required this.paidAt,
  });

  bool get paid => status == 'paid';
  bool get accepted => status == 'accepted';

  factory CommissionInfo.fromJson(Map<String, dynamic> j) => CommissionInfo(
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        note: j['note']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        paymentMethod: j['payment_method']?.toString() ?? '',
        reference: j['reference']?.toString() ?? '',
        receiptNo: j['receipt_no']?.toString() ?? '',
        paidAt: _dt(j['paid_at']),
      );
}

class CommissionView {
  final bool hasAgent, canSet, canAccept, canPay;
  final String role, agentName;
  final CommissionInfo? commission;
  const CommissionView({
    required this.hasAgent,
    required this.canSet,
    required this.canAccept,
    required this.canPay,
    required this.role,
    required this.agentName,
    required this.commission,
  });
}

/// One row of the broker's "Agent commissions" screen.
class AgentAgreement {
  final String agreementId, propertyTitle, tenantName, agreementStatus;
  final CommissionInfo? commission; // null = not proposed yet
  const AgentAgreement({
    required this.agreementId,
    required this.propertyTitle,
    required this.tenantName,
    required this.agreementStatus,
    required this.commission,
  });

  factory AgentAgreement.fromJson(Map<String, dynamic> j) {
    final status = j['status']?.toString() ?? '';
    return AgentAgreement(
      agreementId: j['agreement_id']?.toString() ?? '',
      propertyTitle: j['property_title']?.toString() ?? '',
      tenantName: j['tenant_name']?.toString() ?? '',
      agreementStatus: j['agreement_status']?.toString() ?? '',
      commission: status.isEmpty ? null : CommissionInfo.fromJson(j),
    );
  }
}

class CommissionService {
  CommissionService._();
  static final CommissionService instance = CommissionService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _err(DioException e) {
    final data = e.response?.data;
    final msg = (data is Map && data['error'] != null) ? data['error'].toString() : (e.message ?? 'Something went wrong.');
    return Exception(msg);
  }

  Future<CommissionView> get(String agreementId) async {
    try {
      final r = await _dio.get('/api/agreements/$agreementId/commission');
      final d = r.data as Map<String, dynamic>;
      return CommissionView(
        hasAgent: d['has_agent'] == true,
        canSet: d['can_set'] == true,
        canAccept: d['can_accept'] == true,
        canPay: d['can_pay'] == true,
        role: d['role']?.toString() ?? '',
        agentName: d['agent_name']?.toString() ?? '',
        commission: d['commission'] is Map<String, dynamic> ? CommissionInfo.fromJson(d['commission'] as Map<String, dynamic>) : null,
      );
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> set(String agreementId, double amount, String note) async {
    try {
      await _dio.put('/api/agreements/$agreementId/commission', data: {'amount': amount, 'note': note});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> accept(String agreementId) async {
    try {
      await _dio.post('/api/agreements/$agreementId/commission/accept');
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> decline(String agreementId) async {
    try {
      await _dio.post('/api/agreements/$agreementId/commission/decline');
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<CheckoutInfo> checkout(String agreementId) async {
    try {
      final r = await _dio.post('/api/agreements/$agreementId/commission/checkout');
      return CheckoutInfo.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<List<AgentAgreement>> agentAgreements() async {
    try {
      final r = await _dio.get('/api/agent/agreements');
      final list = (r.data['agreements'] as List?) ?? const [];
      return list.map((e) => AgentAgreement.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _err(e);
    }
  }
}

/// The receipt page content for a paid commission (same look as rent / deposit receipts).
ReceiptData commissionReceipt({
  required CommissionInfo c,
  required String property,
  required String paidBy,
  required String receivedBy,
}) =>
    ReceiptData(
      title: 'Agent commission',
      receiptNo: c.receiptNo,
      amount: c.amount,
      paidAt: c.paidAt,
      loadPdf: null,
      rows: [
        ('Property', property),
        ('Commission', inr(c.amount)),
        ('Note', c.note),
        ('Paid by', paidBy),
        ('Received by', receivedBy),
        ('Payment method', prettify(c.paymentMethod)),
        ('Transaction ID', c.reference),
        ('Paid on', fmtDateTime(c.paidAt)),
      ],
    );