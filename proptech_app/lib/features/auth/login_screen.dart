import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/route_names.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// Accepts "98765 43210", "09876543210", "+91 98765 43210" and returns the
  /// plain 10-digit number, or null if it isn't a valid Indian mobile number.
  static String? _cleanPhone(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    return RegExp(r'^[6-9][0-9]{9}$').hasMatch(d) ? d : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendOtp() async {
    final name = _nameController.text.trim();
    final phone = _cleanPhone(_phoneController.text);
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (name.isEmpty) {
      _snack('Please enter your name');
      return;
    }
    if (phone == null) {
      _snack('Enter a valid 10-digit mobile number');
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      _snack('Enter a valid email address');
      return;
    }
    if (password.length < 8) {
      _snack('Password must be at least 8 characters');
      return;
    }

    setState(() => _loading = true);
    final result = await AuthService.instance.sendOtp(
      name: name,
      phone: phone,
      email: email,
      password: password,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.success) {
      _snack(result.errorMessage ?? 'Could not send OTP. Please try again.');
      return;
    }

    context.push(
      RouteNames.otpVerification,
      extra: {
        'name': name,
        'phone': phone,
        'email': email,
        'password': password,
        'emailSent': result.emailSent.toString(),
        'skipAvailable': result.skipAvailable.toString(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Text('Welcome to PropTech', style: AppTextStyles.h1),
              const SizedBox(height: AppSpacing.xs),
              Text('Enter your details to continue', style: AppTextStyles.bodyMedium),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(
                hint: 'Full name',
                controller: _nameController,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                hint: 'Mobile number (10 digits)',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                prefixIcon: const Icon(Icons.phone_outlined),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  LengthLimitingTextInputFormatter(16),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                hint: 'Email address',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                prefixIcon: const Icon(Icons.email_outlined),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                hint: 'Password (min 8 characters)',
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Send OTP',
                loading: _loading,
                onPressed: _loading ? null : _sendOtp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}