import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';

import '../../app/theme/app_colors.dart';
import 'lease_widgets.dart';
import 'payment_models.dart';
import 'payment_service.dart';

/// Opens Cashfree checkout for one order and completes when the SDK reports back.
/// The SDK result is NOT trusted for success - the server confirms the payment.
class _CashfreeRun {
  final _done = Completer<String?>(); // null = SDK says completed, text = SDK error message
  final _service = CFPaymentGatewayService();

  Future<String?> open(CheckoutSession s) {
    _service.setCallback(
      (String orderId) {
        if (!_done.isCompleted) _done.complete(null);
      },
      (CFErrorResponse error, String orderId) {
        if (!_done.isCompleted) _done.complete(error.getMessage() ?? 'Payment was not completed');
      },
    );
    try {
      final env = s.environment == 'PRODUCTION' ? CFEnvironment.PRODUCTION : CFEnvironment.SANDBOX;
      final session = CFSessionBuilder()
          .setEnvironment(env)
          .setOrderId(s.orderId)
          .setPaymentSessionId(s.paymentSessionId)
          .build();
      final payment = CFWebCheckoutPaymentBuilder().setSession(session).build();
      _service.doPayment(payment);
    } on CFException catch (e) {
      if (!_done.isCompleted) _done.complete(e.message);
    } catch (e) {
      if (!_done.isCompleted) _done.complete('Could not open the payment screen');
    }
    return _done.future.timeout(const Duration(minutes: 35), onTimeout: () => 'Payment timed out');
  }
}

/// Full online-payment flow:
///   1. ask our server for a checkout session (amount is decided on the server)
///   2. open Cashfree
///   3. ask the server for the real result (it re-checks Cashfree itself)
/// Returns true when the payment is confirmed. Failures are shown to the user.
Future<bool> payOnline(
  BuildContext context, {
  required Future<CheckoutSession> Function() start,
}) async {
  final CheckoutSession session;
  try {
    session = await start();
  } catch (e) {
    if (context.mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    return false;
  }
  if (!context.mounted) return false;

  final sdkError = await _CashfreeRun().open(session);
  if (!context.mounted) return false;

  // Confirm with the server. Poll for ~20s because the bank can be a little slow.
  _showBusy(context, 'Confirming your payment...');
  OrderOutcome? last;
  Object? netError;
  for (var i = 0; i < 10; i++) {
    try {
      last = await PaymentService.instance.orderStatus(session.orderId);
      netError = null;
      if (last.finished) break;
    } catch (e) {
      netError = e;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (!context.mounted) return false;

  if (last == null) {
    snack(context, netError?.toString().replaceFirst('Exception: ', '') ?? 'Could not confirm the payment. Pull down to refresh.', error: true);
    return false;
  }

  switch (last.outcome) {
    case 'success':
      await _result(context, ok: true, title: 'Payment successful', body: '${inr(last.order.amount)} paid. Your receipt is ready.');
      return true;
    case 'duplicate':
      await _result(context, ok: true, title: 'Already paid', body: last.message);
      return true;
    case 'failed':
      await _result(context, ok: false, title: 'Payment failed', body: last.message);
      return false;
    case 'expired':
      await _result(context, ok: false, title: 'Payment session ended', body: last.message);
      return false;
    default:
      // Still pending: money may be in transit. Do NOT tell the user it failed.
      await _result(
        context,
        ok: false,
        pending: true,
        title: sdkError == null ? 'Payment is processing' : 'Payment not completed',
        body: sdkError == null
            ? 'Your bank has not confirmed yet. If money was deducted it will show here automatically within a few minutes - do not pay again.'
            : '$sdkError. If money was deducted it will be updated here automatically.',
      );
      return false;
  }
}

void _showBusy(BuildContext context, String text) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(child: Text(text)),
        ]),
      ),
    ),
  );
}

Future<void> _result(BuildContext context, {required bool ok, required String title, required String body, bool pending = false}) {
  final color = ok ? AppColors.success : (pending ? AppColors.warning : AppColors.error);
  final icon = ok ? Icons.check_circle : (pending ? Icons.hourglass_top : Icons.error_outline);
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      icon: Icon(icon, color: color, size: 44),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(body, textAlign: TextAlign.center),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );
}