import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'auth_service.dart';

/// Forgot password, two steps on one screen:
///   1. enter email  -> backend emails a 6-digit code
///   2. enter code + new password -> password updated, back to login
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _resendSeconds = 60;

  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _codeSent = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Timer? _timer;
  int _cooldown = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _emailValid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (!_emailValid) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AuthService.instance.sendPasswordReset(_email.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.success) {
      setState(() => _error = result.errorMessage);
      return;
    }
    setState(() => _codeSent = true);
    _startCooldown();
  }

  Future<void> _reset() async {
    final otp = _otp.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AuthService.instance.resetPassword(
      email: _email.text.trim(),
      otp: otp,
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.success) {
      setState(() => _error = result.errorMessage);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password updated. Please log in.')),
    );
    context.go(RouteNames.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              _codeSent ? 'Enter the code' : 'Reset your password',
              style: AppTextStyles.h2,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _codeSent
                  ? 'If an account exists for ${_email.text.trim()}, we have emailed a 6-digit code. It is valid for 10 minutes.'
                  : 'Enter the email you signed up with. We will email you a 6-digit code.',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _email,
              enabled: !_codeSent && !_loading,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _otp,
                enabled: !_loading,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  counterText: '',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _password,
                enabled: !_loading,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _confirm,
                enabled: !_loading,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _loading ? null : (_codeSent ? _reset : _sendCode),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_codeSent ? 'Update Password' : 'Send Code'),
            ),
            if (_codeSent) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: (_loading || _cooldown > 0) ? null : _sendCode,
                    child: Text(_cooldown > 0 ? 'Resend code in ${_cooldown}s' : 'Resend code'),
                  ),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _error = null;
                              _otp.clear();
                            }),
                    child: const Text('Change email'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}