import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/route_names.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import 'auth_service.dart';

/// Email-OTP screen. The OTP was already emailed by the login screen
/// (send-otp succeeded before we got here); this screen collects the code and
/// calls /api/auth/verify-otp. "Resend" re-calls send-otp with the same
/// credentials, throttled by a 60s countdown (the backend enforces it too).
class OtpScreen extends StatefulWidget {
  final String email;
  final String name;
  final String password;

  /// False when the server couldn't deliver the email (testing mode only).
  final bool emailSent;

  /// True when the backend allows skipping OTP (DEV_SKIP_OTP=true, testing only).
  final bool skipAvailable;

  const OtpScreen({
    super.key,
    required this.email,
    required this.name,
    required this.password,
    this.emailSent = true,
    this.skipAvailable = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _resendSeconds = 60;

  final _otpController = TextEditingController();
  String? _errorText;
  bool _loading = false;
  bool _resending = false;
  late bool _emailSent = widget.emailSent;
  late bool _skipAvailable = widget.skipAvailable;
  int _secondsLeft = _resendSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _errorText = null;
    });
    final result = await AuthService.instance.sendOtp(
      name: widget.name,
      email: widget.email,
      password: widget.password,
    );
    if (!mounted) return;
    setState(() => _resending = false);

    if (result.success) {
      setState(() {
        _emailSent = result.emailSent;
        _skipAvailable = result.skipAvailable;
      });
      _startCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.emailSent
              ? 'A new OTP has been sent to your email'
              : 'Could not send the email right now. You can skip for now.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Could not resend OTP')),
      );
    }
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorText = 'Enter the 6-digit OTP');
      return;
    }
    setState(() {
      _errorText = null;
      _loading = true;
    });

    final result = await AuthService.instance.verifyOtp(
      email: widget.email,
      otp: otp,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      context.go(RouteNames.roleSelection);
    } else {
      setState(() => _errorText = result.errorMessage);
    }
  }

  /// Testing only — shown when the backend runs with DEV_SKIP_OTP=true.
  Future<void> _skip() async {
    setState(() {
      _errorText = null;
      _loading = true;
    });

    final result = await AuthService.instance.skipOtp(email: widget.email);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      context.go(RouteNames.roleSelection);
    } else {
      setState(() => _errorText = result.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify email')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter verification code', style: AppTextStyles.h2),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _emailSent
                  ? 'We sent a 6-digit code to ${widget.email}. Check your spam folder if you don\'t see it.'
                  : 'We could not send the code to ${widget.email} right now. You can skip verification for now.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: AppTextStyles.h2.copyWith(letterSpacing: 8),
              textAlign: TextAlign.center,
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              decoration: InputDecoration(
                counterText: '',
                errorText: _errorText,
                hintText: '••••••',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Verify & Continue',
              loading: _loading,
              onPressed: _loading ? null : _verify,
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton(
                onPressed: (_secondsLeft > 0 || _resending) ? null : _resend,
                child: Text(
                  _resending
                      ? 'Sending...'
                      : _secondsLeft > 0
                          ? 'Resend code in ${_secondsLeft}s'
                          : "Didn't receive code? Resend",
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => context.pop(),
                child: const Text('Change email'),
              ),
            ),
            if (_skipAvailable) ...[
              const Divider(height: AppSpacing.xl),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : _skip,
                  child: const Text('Skip for now (testing only)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}