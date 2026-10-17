import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import 'lease_widgets.dart';
import 'online_payment.dart';
import 'receipt_screen.dart';

DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Agreement between the broker (agent) and the tenant about the broker's commission.
/// sent (broker signed) -> signed (tenant signed) -> paid after the rental agreement is completed.
class CommissionAgreement {
  final String id, number, propertyId, propertyTitle, agentName, tenantName;
  final String note, status, payStatus, paymentMethod, reference, receiptNo, role, leaseId;
  final double amount;
  final DateTime? agentSignedAt, tenantSignedAt, paidAt, createdAt;

  const CommissionAgreement({
    required this.id,
    required this.number,
    required this.propertyId,
    required this.propertyTitle,
    required this.agentName,
    required this.tenantName,
    required this.note,
    required this.status,
    required this.payStatus,
    required this.paymentMethod,
    required this.reference,
    required this.receiptNo,
    required this.role,
    required this.leaseId,
    required this.amount,
    required this.agentSignedAt,
    required this.tenantSignedAt,
    required this.paidAt,
    required this.createdAt,
  });

  bool get isAgent => role == 'agent';
  bool get isTenant => role == 'tenant';
  bool get paid => payStatus == 'paid';
  bool get signed => status == 'signed';

  String get statusLabel {
    if (paid) return 'Paid';
    switch (status) {
      case 'sent':
        return 'Waiting for tenant to sign';
      case 'signed':
        return 'Signed by both';
      case 'declined':
        return 'Declined by tenant';
      case 'cancelled':
        return 'Cancelled';
    }
    return status;
  }

  factory CommissionAgreement.fromJson(Map<String, dynamic> j) {
    String s(String k) => j[k]?.toString() ?? '';
    return CommissionAgreement(
      id: s('id'),
      number: s('agreement_number'),
      propertyId: s('property_id'),
      propertyTitle: s('property_title'),
      agentName: s('agent_name'),
      tenantName: s('tenant_name'),
      note: s('note'),
      status: s('status'),
      payStatus: s('pay_status'),
      paymentMethod: s('payment_method'),
      reference: s('reference'),
      receiptNo: s('receipt_no'),
      role: s('role'),
      leaseId: s('lease_id'),
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      agentSignedAt: _dt(j['agent_signed_at']),
      tenantSignedAt: _dt(j['tenant_signed_at']),
      paidAt: _dt(j['paid_at']),
      createdAt: _dt(j['created_at']),
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

  Future<List<CommissionAgreement>> list() async {
    try {
      final r = await _dio.get('/api/commission-agreements');
      final items = (r.data['items'] as List?) ?? const [];
      return items.map((e) => CommissionAgreement.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<CommissionAgreement> get(String id) async {
    try {
      final r = await _dio.get('/api/commission-agreements/$id');
      return CommissionAgreement.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Broker: create + sign in one go.
  Future<CommissionAgreement> create({
    required String propertyId,
    required String tenantEmail,
    required double amount,
    required String note,
    required String signatureType,
    required String signatureData,
  }) async {
    try {
      final r = await _dio.post('/api/properties/$propertyId/commission-agreement', data: {
        'tenant_email': tenantEmail,
        'amount': amount,
        'note': note,
        'signature_type': signatureType,
        'signature_data': signatureData,
      });
      return CommissionAgreement.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> sign(String id, String signatureType, String signatureData) async {
    try {
      await _dio.post('/api/commission-agreements/$id/sign',
          data: {'signature_type': signatureType, 'signature_data': signatureData});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> decline(String id) async {
    try {
      await _dio.post('/api/commission-agreements/$id/decline');
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> cancel(String id) async {
    try {
      await _dio.post('/api/commission-agreements/$id/cancel');
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<CheckoutInfo> checkout(String id) async {
    try {
      final r = await _dio.post('/api/commission-agreements/$id/checkout');
      return CheckoutInfo.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<Uint8List> pdf(String id) async {
    try {
      final r = await _dio.get<List<int>>('/api/commission-agreements/$id/pdf',
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(r.data ?? const []);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// The signed commission agreement that belongs to a lease (null when there is none / not your lease).
  Future<CommissionAgreement?> forLease(String leaseId) async {
    try {
      final r = await _dio.get('/api/leases/$leaseId/commission-agreement');
      final d = r.data['commission_agreement'];
      return d is Map<String, dynamic> ? CommissionAgreement.fromJson(d) : null;
    } on DioException catch (e) {
      throw _err(e);
    }
  }
}

/// Receipt page content for a paid commission (same look as rent / deposit receipts).
ReceiptData commissionReceipt(CommissionAgreement c) => ReceiptData(
      title: 'Agent commission',
      receiptNo: c.receiptNo,
      amount: c.amount,
      paidAt: c.paidAt,
      loadPdf: null, // the signed agreement PDF is on the agreement screen
      rows: [
        ('Property', c.propertyTitle),
        ('Commission', inr(c.amount)),
        ('Note', c.note),
        ('Paid by', c.tenantName),
        ('Received by', c.agentName),
        ('Payment method', prettify(c.paymentMethod)),
        ('Transaction ID', c.reference),
        ('Paid on', fmtDateTime(c.paidAt)),
      ],
    );