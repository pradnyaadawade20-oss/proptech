import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import 'kyc_service.dart';
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

/// Aadhaar-based KYC: enter Aadhaar number -> verify OTP -> done.
/// Everything is verified server-side (/api/kyc/*); the app never stores the
/// Aadhaar number, it only holds it in memory until the OTP step finishes.
/// Pops with `true` once KYC is verified, so callers (e.g. the agreement
/// signing flow) can continue.
class KycVerificationScreen extends StatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  State<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

enum _KycStep { loading, details, otp, success }

class _KycVerificationScreenState extends State<KycVerificationScreen> {
  _KycStep _step = _KycStep.loading;
  final _aadhaarController = TextEditingController();
  final _otpController = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  String? _aadhaarError;
  String? _otpError;
  String? _notice;
  int _resendSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _aadhaarController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final s = await KycService.instance.getStatus();
      KycStore.instance.update(s);
      if (!mounted) return;
      setState(() => _step = s.isVerified ? _KycStep.success : _KycStep.details);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _KycStep.details;
        _notice = 'Could not check your KYC status. You can still continue.';
      });
    }
  }

  bool get _isValidAadhaar => _aadhaarController.text.replaceAll(' ', '').length == 12;

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _sendOtp({bool isResend = false}) async {
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
      _busy = true;
    });
    try {
      final wait = await KycService.instance.sendOtp(aadhaar: _aadhaarController.text, consent: _consent);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _KycStep.otp;
        _otpController.clear();
        _otpError = null;
      });
      _startResendCountdown(wait);
      if (isResend) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP resent')));
      }
    } on KycException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'kyc_already_verified') {
        await KycStore.instance.refresh();
        if (mounted) setState(() => _step = _KycStep.success);
      } else if (e.code == 'kyc_invalid_aadhaar') {
        setState(() => _aadhaarError = e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  void _startResendCountdown(int seconds) {
    _resendSeconds = seconds;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _step != _KycStep.otp) return false;
      setState(() => _resendSeconds--);
      return _resendSeconds > 0;
    });
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _otpError = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _otpError = null;
      _busy = true;
    });
    try {
      final result = await KycService.instance.verifyOtp(otp);
      KycStore.instance.update(result);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _KycStep.success;
      });
    } on KycException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      switch (e.code) {
        case 'kyc_invalid_otp':
          setState(() => _otpError = e.attemptsLeft != null
              ? 'Invalid OTP. ${e.attemptsLeft} attempt(s) left.'
              : 'Invalid OTP.');
        case 'kyc_too_many_attempts':
        case 'kyc_no_active_otp':
          // This OTP is dead — go back and request a new one.
          setState(() {
            _step = _KycStep.details;
            _notice = e.message;
          });
        default:
          setState(() => _otpError = e.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _otpError = _msg(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KYC Verification')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: switch (_step) {
          _KycStep.loading => const Center(child: CircularProgressIndicator()),
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
          'KYC is required before you can sign a rental agreement. It also adds a "KYC Verified" badge to your profile.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        if (_notice != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_notice!, style: AppTextStyles.bodySmall.copyWith(color: Colors.red)),
        ],
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
          loading: _busy,
          onPressed: _busy ? null : _sendOtp,
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
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Verify & Complete KYC',
          loading: _busy,
          onPressed: _busy ? null : _verifyOtp,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: _resendSeconds > 0
              ? Text('Resend code in ${_resendSeconds}s', style: AppTextStyles.caption)
              : TextButton(
                  onPressed: _busy ? null : () => _sendOtp(isResend: true),
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
          if (result.maskedAadhaar != null)
            Text(
              'Aadhaar ${result.maskedAadhaar}',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          if (result.verifiedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Verified on ${result.verifiedAt!.day}/${result.verifiedAt!.month}/${result.verifiedAt!.year}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    );
  }
}