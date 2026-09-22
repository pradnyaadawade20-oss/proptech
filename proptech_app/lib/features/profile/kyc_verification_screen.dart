import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import 'kyc_store.dart';

/// Adds a space after every 4 digits as the user types an Aadhaar number,
/// e.g. "1234 5678 9012".
class _AadhaarInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 12 ? digits.substring(0, 12) : digits;
    final buffer = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i != 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(limited[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Aadhaar-based KYC verification flow: enter Aadhaar number → verify OTP
/// → done. This is a mock flow — there's no live UIDAI/Aadhaar API
/// integration (the app has no backend), so it behaves the way the rest of
/// the app's auth screens do (default OTP is always 123456), and only
/// ever stores a masked Aadhaar number locally.
class KycVerificationScreen extends StatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  State<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

enum _KycStep { details, otp, success }

class _KycVerificationScreenState extends State<KycVerificationScreen> {
  static const _defaultOtp = '123456';

  _KycStep _step = _KycStep.details;
  final _aadhaarController = TextEditingController();
  final _otpController = TextEditingController();
  bool _consent = false;
  bool _loading = false;
  String? _aadhaarError;
  String? _otpError;
  int _resendSeconds = 30;

  @override
  void initState() {
    super.initState();
    final existing = KycStore.instance.status.value;
    if (existing != null) _step = _KycStep.success;
  }

  @override
  void dispose() {
    _aadhaarController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  bool get _isValidAadhaar => _aadhaarController.text.replaceAll(' ', '').length == 12;

  Future<void> _sendOtp() async {
    if (!_isValidAadhaar) {
      setState(() => _aadhaarError = 'Enter a valid 12-digit Aadhaar number');
      return;
    }
    if (!_consent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the consent to continue')),
      );
      return;
    }
    setState(() {
      _aadhaarError = null;
      _loading = true;
    });
    await Future.delayed(const Duration(milliseconds: 700)); // mock UIDAI OTP dispatch
    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = _KycStep.otp;
    });
    _startResendCountdown();
  }

  void _startResendCountdown() {
    _resendSeconds = 30;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _step != _KycStep.otp) return false;
      setState(() => _resendSeconds--);
      return _resendSeconds > 0;
    });
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim() != _defaultOtp) {
      setState(() => _otpError = 'Invalid OTP. Try 123456 for now.');
      return;
    }
    setState(() {
      _otpError = null;
      _loading = true;
    });
    await Future.delayed(const Duration(milliseconds: 600)); // mock verify delay
    await KycStore.instance.markVerified(_aadhaarController.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = _KycStep.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KYC Verification')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: switch (_step) {
          _KycStep.details => _buildDetailsStep(),
          _KycStep.otp => _buildOtpStep(),
          _KycStep.success => _buildSuccessStep(),
        },
      ),
    );
  }

  Widget _buildDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.badge_outlined, size: 40, color: AppColors.primary),
        const SizedBox(height: AppSpacing.md),
        Text('Verify your identity', style: AppTextStyles.h2),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Complete Aadhaar-based KYC to unlock a "KYC Verified" badge on your profile and build trust with owners/dealers.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Aadhaar Number', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _aadhaarController,
          keyboardType: TextInputType.number,
          inputFormatters: [_AadhaarInputFormatter()],
          style: AppTextStyles.h3.copyWith(letterSpacing: 2),
          decoration: InputDecoration(
            hintText: '1234 5678 9012',
            prefixIcon: const Icon(Icons.credit_card_outlined),
            errorText: _aadhaarError,
          ),
          onChanged: (_) {
            if (_aadhaarError != null) setState(() => _aadhaarError = null);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        CheckboxListTile(
          value: _consent,
          onChanged: (v) => setState(() => _consent = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'I authorize PropTech to verify my identity using my Aadhaar number for KYC purposes, as per UIDAI guidelines.',
            style: AppTextStyles.caption,
          ),
        ),
        const Spacer(),
        AppButton(
          label: 'Send OTP',
          loading: _loading,
          onPressed: _loading ? null : _sendOtp,
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            'Your Aadhaar number is used only for verification and is never stored in full.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    final digits = _aadhaarController.text.replaceAll(' ', '');
    final masked = digits.length >= 4 ? 'XXXX XXXX ${digits.substring(digits.length - 4)}' : digits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter verification code', style: AppTextStyles.h2),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Sent to the mobile number linked with Aadhaar $masked',
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
            errorText: _otpError,
            hintText: '••••••',
          ),
          onChanged: (_) {
            if (_otpError != null) setState(() => _otpError = null);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Default OTP for testing: 123456', style: AppTextStyles.caption),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Verify & Complete KYC',
          loading: _loading,
          onPressed: _loading ? null : _verifyOtp,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: _resendSeconds > 0
              ? Text('Resend code in ${_resendSeconds}s', style: AppTextStyles.caption)
              : TextButton(
                  onPressed: () {
                    _startResendCountdown();
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('OTP resent successfully')),
                    );
                  },
                  child: const Text("Didn't receive code? Resend"),
                ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    final result = KycStore.instance.status.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
          child: const Icon(Icons.verified, size: 56, color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('KYC Verified', style: AppTextStyles.h2),
        const SizedBox(height: AppSpacing.xs),
        if (result != null) ...[
          Text(
            'Aadhaar ${result.maskedAadhaar}',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            'Verified on ${result.verifiedAt.day}/${result.verifiedAt.month}/${result.verifiedAt.year}',
            style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}