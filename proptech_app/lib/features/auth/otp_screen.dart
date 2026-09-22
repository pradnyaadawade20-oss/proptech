import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/route_names.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import 'auth_service.dart';

/// Backend-connected OTP screen. Calls /api/auth/send-otp on load (so a
/// real OTP exists server-side to check against) and /api/auth/verify-otp
/// when the person submits. The backend currently echoes the OTP back in
/// the send-otp response since there's no real SMS gateway yet — shown
/// here only as a dev convenience banner, remove once SMS is wired up.
class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final String name;
  const OtpScreen({super.key, required this.phoneNumber, required this.name});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  String? _errorText;
  bool _loading = false;
  bool _sendingOtp = true;
  String? _devOtpHint;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() => _sendingOtp = true);
    try {
      final otp = await AuthService.instance.sendOtp(widget.phoneNumber);
      if (mounted) setState(() => _devOtpHint = otp);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send OTP: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  void _verify() async {
    if (_otpController.text.trim().isEmpty) {
      setState(() => _errorText = 'Enter the OTP');
      return;
    }
    setState(() {
      _errorText = null;
      _loading = true;
    });

    final result = await AuthService.instance.verifyOtp(
      phone: widget.phoneNumber,
      name: widget.name,
      otp: _otpController.text.trim(),
    );

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
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter verification code', style: AppTextStyles.h2),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Sent to +91 ${widget.phoneNumber}',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: AppTextStyles.h2.copyWith(letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '',
                errorText: _errorText,
                hintText: '••••••',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_sendingOtp)
              Text('Sending OTP...', style: AppTextStyles.caption)
            else if (_devOtpHint != null)
              Text(
                'Dev mode — OTP is: ${_devOtpHint!} (remove this once SMS is wired up)',
                style: AppTextStyles.caption.copyWith(color: AppColors.primary),
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
                onPressed: _sendingOtp ? null : _sendOtp,
                child: const Text("Didn't receive code? Resend"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}