import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import 'payment_models.dart';

/// Talks to the Cashfree-backed payment endpoints. No keys live in the app:
/// the server returns a one-time payment_session_id for a single order.
class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _err(DioException e) {
    var data = e.response?.data;
    if (data is List<int>) {
      try {
        data = jsonDecode(utf8.decode(data));
      } catch (_) {}
    }
    final msg = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(msg);
  }

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  // ---------------- owner bank ----------------

  Future<OwnerBank?> ownerBank() => _run(() async {
        final r = await _dio.get('/api/owner/bank');
        final b = r.data['bank'];
        return b is Map<String, dynamic> ? OwnerBank.fromJson(b) : null;
      });

  Future<OwnerBank?> saveOwnerBank({
    required String holder,
    required String accountNumber,
    required String confirmAccountNumber,
    required String ifsc,
  }) =>
      _run(() async {
        final r = await _dio.put('/api/owner/bank', data: {
          'account_holder': holder,
          'account_number': accountNumber,
          'confirm_account_number': confirmAccountNumber,
          'ifsc': ifsc,
        });
        final b = r.data['bank'];
        return b is Map<String, dynamic> ? OwnerBank.fromJson(b) : null;
      });

  Future<OwnerBank?> refreshOwnerBank() => _run(() async {
        final r = await _dio.post('/api/owner/bank/refresh', data: {});
        final b = r.data['bank'];
        return b is Map<String, dynamic> ? OwnerBank.fromJson(b) : null;
      });

  // ---------------- checkout ----------------

  Future<CheckoutSession> startRentCheckout(String paymentId) => _run(() async {
        final r = await _dio.post('/api/rent/$paymentId/online-order', data: {});
        return CheckoutSession.fromJson(r.data['session'] as Map<String, dynamic>);
      });

  Future<CheckoutSession> startDepositCheckout(String leaseId) => _run(() async {
        final r = await _dio.post('/api/leases/$leaseId/deposit/online-order', data: {});
        return CheckoutSession.fromJson(r.data['session'] as Map<String, dynamic>);
      });

  /// The server re-checks Cashfree itself, so this works even if the webhook is late.
  Future<OrderOutcome> orderStatus(String orderId) => _run(() async {
        final r = await _dio.get('/api/payments/orders/$orderId');
        return OrderOutcome.fromJson(r.data as Map<String, dynamic>);
      });

  // ---------------- history / settlements ----------------

  Future<List<PaymentOrder>> leasePayments(String leaseId) => _run(() async {
        final r = await _dio.get('/api/leases/$leaseId/payments');
        return ((r.data['orders'] as List?) ?? const [])
            .map((e) => PaymentOrder.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<(List<PaymentOrder>, SettlementTotals)> settlements() => _run(() async {
        final r = await _dio.get('/api/payments/settlements');
        final list = ((r.data['orders'] as List?) ?? const [])
            .map((e) => PaymentOrder.fromJson(e as Map<String, dynamic>))
            .toList();
        final t = r.data['totals'] is Map
            ? SettlementTotals.fromJson(r.data['totals'] as Map<String, dynamic>)
            : const SettlementTotals();
        return (list, t);
      });

  Future<void> refreshSettlement(String orderId) =>
      _run(() => _dio.post('/api/payments/orders/$orderId/settlement', data: {}));

  Future<Uint8List> depositReceiptPdf(String leaseId) => _run(() async {
        final r = await _dio.get<List<int>>('/api/leases/$leaseId/deposit/receipt',
            options: Options(responseType: ResponseType.bytes));
        return Uint8List.fromList(r.data ?? const []);
      });
}