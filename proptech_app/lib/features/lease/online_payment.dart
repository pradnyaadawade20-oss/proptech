import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';
import '../../core/api/api_client.dart';
import 'lease_widgets.dart';

/// What the server gives us to open Cashfree's payment page.
class CheckoutInfo {
  final String orderId, checkoutUrl;
  final double amount;
  const CheckoutInfo({required this.orderId, required this.checkoutUrl, required this.amount});

  factory CheckoutInfo.fromJson(Map<String, dynamic> j) => CheckoutInfo(
        orderId: j['order_id']?.toString() ?? '',
        checkoutUrl: j['checkout_url']?.toString() ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
      );
}

class PayStatus {
  final String status; // paid | pending | expired | duplicate
  final String reason;
  const PayStatus(this.status, this.reason);
}

/// Talks to the Cashfree endpoints of our backend (no keys in the app).
class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _err(DioException e) {
    final data = e.response?.data;
    final msg = (data is Map && data['error'] != null) ? data['error'].toString() : (e.message ?? 'Something went wrong.');
    return Exception(msg);
  }

  Future<CheckoutInfo> rentCheckout(String paymentId) async {
    try {
      final r = await _dio.post('/api/rent/$paymentId/checkout');
      return CheckoutInfo.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<CheckoutInfo> depositCheckout(String leaseId) async {
    try {
      final r = await _dio.post('/api/leases/$leaseId/deposit/checkout');
      return CheckoutInfo.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<PayStatus> status(String orderId) async {
    try {
      final r = await _dio.get('/api/payments/orders/$orderId');
      return PayStatus(r.data['status']?.toString() ?? 'pending', r.data['failure_reason']?.toString() ?? '');
    } on DioException catch (e) {
      throw _err(e);
    }
  }
}

/// "Pay" button flow: create order -> open Cashfree page (UPI / card / netbanking) -> wait for result.
/// Returns true when the payment succeeded.
Future<bool> payOnline(
  BuildContext context, {
  required Future<CheckoutInfo> Function() start,
}) async {
  CheckoutInfo info;
  try {
    info = await start();
  } catch (e) {
    if (context.mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    return false;
  }
  if (!await _open(info.checkoutUrl)) {
    if (context.mounted) snack(context, 'Could not open the payment page.', error: true);
    return false;
  }
  if (!context.mounted) return false;
  final paid = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WaitDialog(info: info),
  );
  return paid ?? false;
}

Future<bool> _open(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class _WaitDialog extends StatefulWidget {
  final CheckoutInfo info;
  const _WaitDialog({required this.info});

  @override
  State<_WaitDialog> createState() => _WaitDialogState();
}

class _WaitDialogState extends State<_WaitDialog> with WidgetsBindingObserver {
  Timer? _timer;
  final DateTime _started = DateTime.now();
  String _state = 'waiting'; // waiting | paid | expired | duplicate | timeout
  String _reason = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the browser / UPI app -> check right away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking || _state != 'waiting' || !mounted) return;
    if (DateTime.now().difference(_started) > const Duration(minutes: 15)) {
      _timer?.cancel();
      setState(() => _state = 'timeout');
      return;
    }
    _checking = true;
    try {
      final s = await PaymentService.instance.status(widget.info.orderId);
      if (!mounted) return;
      if (s.status == 'paid' || s.status == 'duplicate' || s.status == 'expired') {
        _timer?.cancel();
        setState(() => _state = s.status);
        if (s.status == 'paid') {
          await Future.delayed(const Duration(milliseconds: 1400));
          if (mounted) Navigator.of(context).pop(true);
        }
      } else if (s.reason.isNotEmpty && s.reason != _reason) {
        setState(() => _reason = s.reason);
      }
    } catch (_) {
      // network hiccup - the next tick tries again
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary);
    late final Widget icon;
    late final String title, body;
    final actions = <Widget>[];

    switch (_state) {
      case 'paid':
        icon = const Icon(Icons.check_circle, color: Colors.green, size: 56);
        title = 'Payment successful';
        body = '${inr(widget.info.amount)} paid. Your receipt is ready.';
        break;
      case 'duplicate':
        icon = const Icon(Icons.info_outline, color: Colors.orange, size: 56);
        title = 'Already paid';
        body = 'This was already paid, so this extra payment will be refunded.';
        actions.add(TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('OK')));
        break;
      case 'expired':
        icon = const Icon(Icons.error_outline, color: Colors.red, size: 56);
        title = 'Payment not completed';
        body = _reason.isNotEmpty ? _reason : 'The payment session ended. No money is taken. Please tap Pay to try again.';
        actions.add(TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')));
        break;
      case 'timeout':
        icon = const Icon(Icons.hourglass_bottom, color: Colors.orange, size: 56);
        title = 'Still waiting';
        body = 'We have not received the payment yet. If money was deducted it will show here shortly - check again in a few minutes.';
        actions.add(TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')));
        break;
      default:
        icon = const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3));
        title = 'Waiting for payment';
        body = 'Complete the payment of ${inr(widget.info.amount)} on the Cashfree page (UPI, card or net banking), then come back here.';
        actions.addAll([
          TextButton(
            onPressed: () => _open(widget.info.checkoutUrl),
            child: const Text('Reopen payment page'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')),
        ]);
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        icon,
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: t),
        if (_state == 'waiting' && _reason.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Last attempt failed: $_reason', textAlign: TextAlign.center, style: t.copyWith(color: Colors.red)),
        ],
      ]),
      actionsAlignment: MainAxisAlignment.center,
      actions: actions,
    );
  }
}